#include "geometry.hlsl"

StructuredBuffer<geometry::Vertex> g_verts : register(t0);
Buffer<int> g_indices : register(t1);
RWTexture2D<float4> g_output  : register(u0);

cbuffer Constant : register(b0)
{
    float4x4 g_view;
    float4x4 g_proj;
    float4 g_outputSize;
    float4 g_time;
}

[numthreads(8,8,1)]
void csMainRaster(int3 dispatchThreadId : SV_DispatchThreadID)
{
    float2 uv = (dispatchThreadId.xy + 0.5) * g_outputSize.zw;
    float2 hCoords = uv * float2(2.0,2.0) - float2(1.0, 1.0);

    float rot = g_time.x * 0.001;
    float2 sc = float2(sin(rot), cos(rot));
    float2x2 rotm = float2x2(sc.x, sc.y, -sc.y, sc.x);

    geometry::Triangle t = geometry::sampleTriangle(g_indices, 0);
    geometry::Vertex a = g_verts[t.a];
    geometry::Vertex b = g_verts[t.b];
    geometry::Vertex c = g_verts[t.c];

    a.p.xz = mul(a.p.xz, rotm);
    b.p.xz = mul(b.p.xz, rotm);
    c.p.xz = mul(c.p.xz, rotm);

    float4 ta = mul(mul(float4(a.p.xyz, 1.0), g_view), g_proj);
    float4 tb = mul(mul(float4(b.p.xyz, 1.0), g_view), g_proj);
    float4 tc = mul(mul(float4(c.p.xyz, 1.0), g_view), g_proj);
    a.p = (ta / ta.w).xyz;
    b.p = (tb / tb.w).xyz;
    c.p = (tc / tc.w).xyz;

    float2 ea = b.p.xy - a.p.xy;
    float2 eb = c.p.xy - b.p.xy;
    float2 ec = a.p.xy - c.p.xy;

    float2 pa = hCoords - a.p.xy;
    float2 pb = hCoords - b.p.xy;
    float2 pc = hCoords - c.p.xy;

    float wa = ea.x * pa.y - ea.y * pa.x;
    float wb = eb.x * pb.y - eb.y * pb.x;
    float wc = ec.x * pc.y - ec.y * pc.x;

    float3 barys = geometry::computeBaryCoordPerspective(float3(a.p.xy,ta.w), float3(b.p.xy,tb.w), float3(c.p.xy,tc.w), hCoords);
    float3 debugCol1 = float3(1,0,0) * barys.x;
    float3 debugCol2 = float3(0,1,0) * barys.y;
    float3 debugCol3 = float3(0,0,1) * barys.z;
    float3 finalCol = barys.x > 0.5 ? float3(1,0,0) : (barys.y > 0.5 ? float3(0,1,0) : (barys.z > 0.5 ? float3(0,0,1) : (debugCol1 + debugCol2 + debugCol3)));

    float frontFace = -max(wa, max(wb, wc));
    float backFace = min(wa, min(wb, wc));
    g_output[dispatchThreadId.xy] = (frontFace > 0.0) || (backFace > 0.0) ? float4(finalCol,0) : float4(0,0,0,1);
}
