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
    float2 hCoords = uv * float2(2.0,2.0) - float2(1.0, 1.0);

    float rot = g_timeOffsetCount.x * 0.001;
    int triOffset = g_timeOffsetCount.y;
    int triCounts = g_timeOffsetCount.z;
    float2 sc = float2(sin(rot), cos(rot));
    float2x2 rotm = float2x2(sc.x, sc.y, -sc.y, sc.x);

    //hack, clear target
    float4 color = float4(0,0,0,0);
    bool writeColor = false;
    for (int triId = 0; triId < triCounts; ++triId)
    {
        geometry::TriangleI ti;
        ti.load(g_indices, triOffset + triId);

        geometry::TriangleV tv;
        tv.load(g_verts, ti);

        //tv.a.p.xz = mul(tv.a.p.xz, rotm);
        //tv.b.p.xz = mul(tv.b.p.xz, rotm);
        //tv.c.p.xz = mul(tv.c.p.xz, rotm);

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

RWBuffer<uint> g_totalBins : register(u0);
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

    geometry::TriangleAABB aabb = th.aabb();

    int2 beginTiles = ((aabb.begin.xy * 0.5 + 0.5) * g_binFrameDims.xy) / g_binCoarseTileSize;
    int2 endTiles =   ((aabb.end.xy   * 0.5 + 0.5) * g_binFrameDims.xy) / g_binCoarseTileSize;

    //go for each tile in this tri
    for (int tileX = beginTiles.x; tileX <= endTiles.x; ++tileX)
    {
        for (int tileY = beginTiles.y; tileY <= endTiles.y; ++tileY)
        {
            int binId = (tileY * g_binTileX + tileX);
            uint unused = 0;
            InterlockedAdd(g_binCounters[binId], 1, unused);
        }
    }
}

