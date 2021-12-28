#include "geometry.hlsl"
#include "raster_util.hlsl"

//Shared inputs
StructuredBuffer<geometry::Vertex> g_verts : register(t0);
Buffer<int> g_indices : register(t1);

RWTexture2D<float4> g_output  : register(u0);

cbuffer Constant : register(b0)
{
    float4x4 g_view;
    float4x4 g_proj;
    float4 g_outputSize;
    float4 g_timeOffsetCount;
}

[numthreads(8,8,1)]
void csMainRasterBruteForce(int3 dispatchThreadId : SV_DispatchThreadID)
{
    float2 uv = (dispatchThreadId.xy + 0.5) * g_outputSize.zw;
    uv.y = 1.0 - uv.y;

    float2 hCoords = uv * float2(2.0,2.0) - float2(1.0, 1.0);

    int triOffset = g_timeOffsetCount.y;
    int triCounts = g_timeOffsetCount.z;

    //hack, clear target
    float4 color = float4(0,0,0,0);
    bool writeColor = false;
    for (int triId = 0; triId < triCounts; ++triId)
    {
        geometry::TriangleI ti;
        ti.load(g_indices, triOffset + triId);

        geometry::TriangleV tv;
        tv.load(g_verts, ti);

        geometry::TriangleH th;
        th.init(tv, g_view, g_proj);

        geometry::TriInterpResult interpResult = th.interp(hCoords);
        
        float3 finalCol = interpResult.eval(float3(1,0,0), float3(0,1,0), float3(0,0,1));
        if (interpResult.visible)
        {
            writeColor = true;
            color.xyz = finalCol;
        }
    }
    if (writeColor)
        g_output[dispatchThreadId.xy] = color;//interpResult.visible ? float4(finalCol, 1) : float4(0,0,0,1);
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
    int4 g_binRecordCounts;
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

