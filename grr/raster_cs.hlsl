#include "geometry.hlsl"
#include "raster_util.hlsl"

#define ENABLE_Z 1

//Shared inputs
ByteAddressBuffer g_verts : register(t0);
Buffer<int> g_indices : register(t1);
Buffer<uint> g_rasterBinCounts   : register(t2);
Buffer<uint> g_rasterBinOffsets  : register(t3);
Buffer<uint> g_rasterBinTriIds  : register(t4);

RWTexture2D<float4> g_output  : register(u0);

cbuffer Constants : register(b0)
{
    float4 g_outputSize;

    int2   g_outputSizeInts;
    int g_binTriCounts;
    int g_unused1;

    float2 g_coarseTileSize;
    float2 g_fineTileSize;

    float4x4 g_view;
    float4x4 g_proj;
}

groupshared int gs_tileCount;
groupshared int gs_tileOffset;

#define TRIANGLE_CACHE_COUNT (FINE_TILE_SIZE * FINE_TILE_SIZE)
groupshared uint gs_furthestZ;
groupshared geometry::TriangleH gs_th[TRIANGLE_CACHE_COUNT];
groupshared uint gs_triValid[TRIANGLE_CACHE_COUNT];
groupshared geometry::AABB gs_tileBounds;

void loadTriangleGroup(int groupThreadIndex)
{
    geometry::TriangleH th = (geometry::TriangleH)0;
    uint triValid = 0;
    if (groupThreadIndex < gs_tileCount) 
    {
        int triId = g_rasterBinTriIds[groupThreadIndex + gs_tileOffset];
        geometry::TriangleI ti;
        ti.load(g_indices, triId);
        
        geometry::TriangleV tv;
        tv.load(g_verts, ti);
        th.init(tv, g_view, g_proj);
        triValid = asuint(th.aabb().end.z) >= gs_furthestZ && th.aabb().intersects(gs_tileBounds) ? 1 : 0;
    }

    gs_th[groupThreadIndex] = th;
    gs_triValid[groupThreadIndex] = triValid;
}

void nextTriangleGroup(int groupThreadIndex)
{
    if (groupThreadIndex == 0)
    {
        gs_tileCount -= TRIANGLE_CACHE_COUNT;
        gs_tileOffset += TRIANGLE_CACHE_COUNT;
        gs_furthestZ = asuint(1.0);
    }
}

[numthreads(FINE_TILE_SIZE, FINE_TILE_SIZE, 1)]
void csMainRaster(int3 dispatchThreadId : SV_DispatchThreadID, int3 groupID : SV_GroupID, int groupThreadIndex : SV_GroupIndex)
{
    float2 uv = geometry::pixelToUV(dispatchThreadId.xy, g_outputSizeInts);
    float2 hCoords = uv * float2(2.0,2.0) - float2(1.0, 1.0);

    //hack, clear target
    float4 color = float4(0,0,0,0);
    bool writeColor = false;

    if (groupThreadIndex == 0)
    {
        int tileX = groupID.x >> MICRO_TILE_TO_TILE_SHIFT;
        int tileY = groupID.y >> MICRO_TILE_TO_TILE_SHIFT;
        int tileId = tileY * g_coarseTileSize.x + tileX;
        gs_tileCount = min(g_rasterBinCounts[tileId], 10000);
        gs_tileOffset = g_rasterBinOffsets[tileId];
        gs_tileBounds.begin = float3(geometry::uvToH(geometry::pixelToUV(groupID.xy * FINE_TILE_SIZE, g_outputSize.xy)), 0.0);
        gs_tileBounds.end = float3(geometry::uvToH(geometry::pixelToUV((groupID.xy + int2(1,1)) * FINE_TILE_SIZE, g_outputSize.xy)), 1.0);
        gs_furthestZ = asuint(1.0f);
    }
    
    GroupMemoryBarrierWithGroupSync();

    float zBuffer = 0.0;
    while (gs_tileCount > 0)
    {
        uint unusedVal;
        InterlockedMin(gs_furthestZ, asuint(zBuffer), unusedVal);
        GroupMemoryBarrierWithGroupSync();

        loadTriangleGroup(groupThreadIndex);
        GroupMemoryBarrierWithGroupSync();

        int cacheCount = min(TRIANGLE_CACHE_COUNT, gs_tileCount);
        for (int triIndex = 0; triIndex < cacheCount; ++triIndex)
        {
            if (!gs_triValid[triIndex])
                continue;

            geometry::TriangleH th = gs_th[triIndex];
            geometry::TriInterpResult interpResult = th.interp(hCoords);
            float3 finalCol = interpResult.eval(float3(1,0,0), float3(0,1,0), float3(0,0,1));
            if (interpResult.visible)
            {
                float pZ = interpResult.eval(th.h0.z, th.h1.z, th.h2.z);
                float pW = interpResult.eval(th.h0.w, th.h1.w, th.h2.w);
                float minW = min(th.h0.w, min(th.h1.w, th.h2.w));
                float maxW = max(th.h0.w, max(th.h1.w, th.h2.w));
                pZ *= rcp(pW);
                if (pZ < 1.0 && pZ > zBuffer)
                {
                    writeColor = true;
                    color.xyz = finalCol;
                    zBuffer = pZ; 
                }
            }
        }

        nextTriangleGroup(groupThreadIndex);
        GroupMemoryBarrierWithGroupSync();
    }

    if (writeColor)
        g_output[dispatchThreadId.xy] = color;
}

RWBuffer<uint> g_outTotalRecords : register(u0);
RWBuffer<uint> g_binCounters : register(u1);
RWStructuredBuffer<raster::BinIntersectionRecord> g_binOutputRecords : register(u2);


[numthreads(64, 1, 1)]
void csMainBinTriangles(int3 dti : SV_DispatchThreadID)
{
    if (dti.x >= g_binTriCounts)
        return;

    int triId = dti.x;

    geometry::TriangleI ti;
    ti.load(g_indices, triId);

    geometry::TriangleV tv;
    tv.load(g_verts, ti);

    geometry::TriangleH th;
    th.init(tv, g_view, g_proj);

    float wEpsilon = 0.000001;
    if (th.h0.w < 0.0)
    {
        th.h0 = float4(0.0,0.0,0.0,0.0);
        th.p0 = float3(0.0,0.0,0.0);
    }
    if (th.h1.w < 0.0)
    {
        th.h1 = float4(0.0,0.0,0.0,0.0);
        th.p1 = float3(0.0,0.0,0.0);
    }
    if (th.h2.w < 0.0)
    {
        th.h2 = float4(0.0,0.0,0.0,0.0);
        th.p2 = float3(0.0,0.0,0.0);
    }

    //float wEpsilon = 0.001;
    //if (th.h0.w < wEpsilon || th.h1.w < wEpsilon || th.h2.w < wEpsilon)
    //    return;

    geometry::AABB aabb = th.aabb();
    if (any(aabb.begin.xy > float2(1,1)) || any(aabb.end.xy < float2(-1,-1)))
        return;

    if (any(aabb.extents().xy < g_outputSize.zw))
        return;

    int2 tilePointA = (geometry::hToUV(aabb.begin.xy) * g_outputSize.xy) / COARSE_TILE_SIZE;
    int2 tilePointB =   (geometry::hToUV(aabb.end.xy) * g_outputSize.xy) / COARSE_TILE_SIZE;

    int2 beginTiles = clamp(min(tilePointA, tilePointB), int2(0,0), int2(g_coarseTileSize) - 1);
    int2 endTiles   = clamp(max(tilePointA, tilePointB), int2(0,0), int2(g_coarseTileSize) - 1);

    //go for each tile in this tri
    for (int tileX = beginTiles.x; tileX <= endTiles.x; ++tileX)
    {
        for (int tileY = beginTiles.y; tileY <= endTiles.y; ++tileY)
        {
            int2 tileB = int2(tileX, tileY);
            int2 tileE = tileB + 1;
            geometry::AABB tile;

            tile.begin = float3(geometry::uvToH(geometry::pixelToUV(tileB * COARSE_TILE_SIZE, g_outputSize.xy)), 0.0);
            tile.end = float3(geometry::uvToH(geometry::pixelToUV(tileE * COARSE_TILE_SIZE, g_outputSize.xy)), 1.0);

            //if (any(aabb.begin.xy > tile.end.xy) || any(aabb.end.xy < tile.begin.xy))
            if (!aabb.intersects(tile))
                continue;
            
            if (!geometry::intersectsSAT(th, tile))
                continue;

            //TODO: Optimize this by caching into LDS, and writting then 64 tris per batch
            int binId = (tileY * g_coarseTileSize.x + tileX);
            uint binOffset = 0, globalOffset = 0;
            InterlockedAdd(g_binCounters[binId], 1, binOffset);
            InterlockedAdd(g_outTotalRecords[0], 1, globalOffset);

            raster::BinIntersectionRecord record;
            record.init(binId, triId, binOffset);
            g_binOutputRecords[globalOffset] = record;
        }
    }
}

Buffer<uint> g_totalRecords : register(t0);
Buffer<uint> g_binOffsets : register(t1);
StructuredBuffer<raster::BinIntersectionRecord> g_binRecords : register(t2);
RWBuffer<uint> g_outBinElements : register(u0);

RWBuffer<uint4> g_outArgsBuffer : register(u0);

[numthreads(1,1,1)]
void csWriteBinElementArgsBuffer()
{
    g_outArgsBuffer[0] = uint4((g_totalRecords[0] + 63)/64,1,1,0);
}

groupshared uint gs_totalRecords;

[numthreads(64,1,1)]
void csMainWriteBinElements(int3 dispatchThreadId : SV_DispatchThreadID, int groupThreadIndex : SV_GroupIndex)
{
    if (groupThreadIndex == 0)
    {
        gs_totalRecords = g_totalRecords[0];
    }

    GroupMemoryBarrierWithGroupSync();

    if (dispatchThreadId.x >= gs_totalRecords)
        return;

    raster::BinIntersectionRecord record = g_binRecords[dispatchThreadId.x];
    int binIndex = record.tileId;
    int outputIndex = g_binOffsets[binIndex] + record.binOffset;
    g_outBinElements[outputIndex] = record.triangleId;
}

