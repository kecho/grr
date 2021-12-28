#include "geometry.hlsl"
#include "raster_util.hlsl"

#define ENABLE_Z 1

//Shared inputs
StructuredBuffer<geometry::Vertex> g_verts : register(t0);
Buffer<int> g_indices : register(t1);
Buffer<uint> g_rasterBinCounts   : register(t2);
Buffer<uint> g_rasterBinOffsets  : register(t3);
Buffer<uint> g_rasterBinTriIds  : register(t4);

RWTexture2D<float4> g_output  : register(u0);

cbuffer Constant : register(b0)
{
    float4x4 g_view;
    float4x4 g_proj;
    float4 g_outputSize;
    float4 g_timeOffsetCount;

    float g_rasterTileX;
    float g_rasterTileY;
    int g_rasterTileSize;
    int g_unused0;

    int4 g_outputSizeInts;
}

//TODO: align tile with group!!
//groupshared int gs_tileId;
//groupshared int gs_tileCount;
//groupshared int gs_tileOffset;

[numthreads(8,8,1)]
void csMainRaster(int3 dispatchThreadId : SV_DispatchThreadID, int3 groupID : SV_GroupID, int groupThreadIndex : SV_GroupIndex)
{
    float2 uv = (float2)(dispatchThreadId.xy) / (float2)g_outputSizeInts.xy;
    uv.y = 1.0 - uv.y;

    float2 hCoords = uv * float2(2.0,2.0) - float2(1.0, 1.0);

    //hack, clear target
    float4 color = float4(0,0,0,0);
    bool writeColor = false;

#if BRUTE_FORCE
    int triOffset = g_timeOffsetCount.y;
    int triCounts = g_timeOffsetCount.z;
#else
    

    //TODO: align tile with group!!
    //if (groupThreadIndex == 0)
    //{
        int gs_tileCount = 0;
        int gs_tileOffset = 0;
        int gs_tileId = 0;
        int tileX = int(uv.x * g_outputSizeInts.x) / g_rasterTileSize;
        int tileY = int(uv.y * g_outputSizeInts.y) / g_rasterTileSize;
        int tileId = tileY * g_rasterTileX + tileX;
        gs_tileCount = g_rasterBinCounts[tileId];
        gs_tileOffset = g_rasterBinOffsets[tileId];
        gs_tileId = tileId;
    //}
    
    GroupMemoryBarrierWithGroupSync();

    int triCounts = gs_tileCount;

//SAFETY: constrain if we get gpu hangs
#if 0
    triCounts = min(triCounts, 1024);
#endif

#endif

    float zBuffer = 1.0;

    for (int triIndex = 0; triIndex < triCounts; ++triIndex)
    {
#if BRUTE_FORCE
        int triId = triOffset + triIndex;
#else
        int triId = g_rasterBinTriIds[triIndex + gs_tileOffset];
#endif
        geometry::TriangleI ti;
        ti.load(g_indices, triId);

        geometry::TriangleV tv;
        tv.load(g_verts, ti);

        geometry::TriangleH th;
        th.init(tv, g_view, g_proj);

        geometry::TriInterpResult interpResult = th.interp(hCoords);
        
        float3 finalCol = interpResult.eval(float3(1,0,0), float3(0,1,0), float3(0,0,1));
        if (interpResult.visible)
        {
#if ENABLE_Z
            float pZ, pW;
            pZ = interpResult.eval(th.h0.z, th.h1.z, th.h2.z);
            pW = interpResult.eval(th.h0.w, th.h1.w, th.h2.w);
            pZ *= rcp(pW);
            if (pZ < zBuffer)
#endif
            {
                writeColor = true;
                color.xyz = finalCol;
#if ENABLE_Z
                zBuffer = pZ; 
#endif
            }
        }
    }

    if (writeColor)
        g_output[dispatchThreadId.xy] = color;
}

RWBuffer<uint> g_outTotalRecords : register(u0);
RWBuffer<uint> g_binCounters : register(u1);
RWStructuredBuffer<raster::BinIntersectionRecord> g_binOutputRecords : register(u2);

cbuffer ConstantBins : register(b0)
{
    float4 g_binFrameDims;
    float g_binTileX;
    float g_binTileY;
    float g_binCoarseTileSize;
    int g_binTriCounts;
    float4x4 g_binView;
    float4x4 g_binProj;
}

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
    th.init(tv, g_binView, g_binProj);

    geometry::AABB aabb = th.aabb();

    if (any(aabb.begin.xy > float2(1,1)) || any(aabb.end.xy < float2(-1,-1)))
        return;

    aabb.begin = clamp(aabb.begin, float3(-1,-1,0), float3(1,1,1));
    aabb.end = clamp(aabb.end, float3(-1,-1,0), float3(1,1,1));

    int2 beginTiles = ((aabb.begin.xy * 0.5 + 0.5) * g_binFrameDims.xy) / g_binCoarseTileSize;
    int2 endTiles =   ((aabb.end.xy   * 0.5 + 0.5) * g_binFrameDims.xy) / g_binCoarseTileSize;

    float2 tileDims = float2(g_binCoarseTileSize.xx / g_binFrameDims.xy) * 2.0;

    //go for each tile in this tri
    for (int tileX = beginTiles.x; tileX <= endTiles.x; ++tileX)
    {
        for (int tileY = beginTiles.y; tileY <= endTiles.y; ++tileY)
        {
            float2 tileB = float2(tileX, tileY);
            float2 tileE = tileB + 1.0;
            geometry::AABB tile;

            tile.begin = float3(tileB * tileDims - 1.0f.xx, 0.0);
            tile.end =   float3(tileE * tileDims - 1.0f.xx, 1.0);

            if (any(aabb.begin.xy > tile.end.xy) || any(aabb.end.xy < tile.begin.xy))
                continue;
            
            if (!geometry::intersectsSAT(th, tile))
                continue;

            //TODO: Optimize this by caching into LDS, and writting then 64 tris per batch
            int binId = (tileY * g_binTileX + tileX);
            uint binOffset = 0, globalOffset = 0;
            InterlockedAdd(g_binCounters[binId], 1, binOffset);
            InterlockedAdd(g_outTotalRecords[0], 1, globalOffset);

            raster::BinIntersectionRecord record;
            record.init(int2(tileX, tileY), triId, binOffset);
            g_binOutputRecords[globalOffset] = record;
        }
    }
}

Buffer<uint> g_totalRecords : register(t0);
Buffer<uint> g_binOffsets : register(t1);
StructuredBuffer<raster::BinIntersectionRecord> g_binRecords : register(t2);
RWBuffer<uint> g_outBinElements : register(u0);

cbuffer ConstantBinEls : register(b0)
{
    int4 g_binSizes;
}

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
    int2 binCoord = record.getCoord();
    int binIndex = g_binSizes.x * binCoord.y + binCoord.x;
    int outputIndex = g_binOffsets[binIndex] + record.binOffset;
    g_outBinElements[outputIndex] = record.triangleId;
}

