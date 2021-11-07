#include "geometry.hlsl"

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
void csMainRaster(int3 dispatchThreadId : SV_DispatchThreadID)
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
    if (triOffset != 0)
        color = g_output[dispatchThreadId.xy];
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
            color.xyz = finalCol;
    }
    g_output[dispatchThreadId.xy] = color;//interpResult.visible ? float4(finalCol, 1) : float4(0,0,0,1);
}
