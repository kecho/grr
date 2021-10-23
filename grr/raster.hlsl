#include "geometry.hlsl"

StructuredBuffer<geometry::Vertex> g_verts : register(t0);
Buffer<int> g_indices : register(t1);
RWTexture2D<float4> g_output  : register(u0);

cbuffer Constant : register(b0)
{
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

    //a.p.xy = mul(rotm,a.p.xy);
    //b.p.xy = mul(rotm,b.p.xy);
    //c.p.xy = mul(rotm,c.p.xy);

    float2 ea = b.p.xy - a.p.xy;
    float2 eb = c.p.xy - b.p.xy;
    float2 ec = a.p.xy - c.p.xy;

    float2 pa = hCoords - a.p.xy;
    float2 pb = hCoords - b.p.xy;
    float2 pc = hCoords - c.p.xy;

    float wa = ea.x * pa.y - ea.y * pa.x;
    float wb = eb.x * pb.y - eb.y * pb.x;
    float wc = ec.x * pc.y - ec.y * pc.x;

    float m = max(wa, max(wb, wc));

    g_output[dispatchThreadId.xy] = m > 0.0 ? float4(0.0,0,0,0) : float4(0.3,0,0,1);
}
