
Texture2D<float4> g_visibilityBuffer : register(t0);
RWTexture2D<float4> g_output : register(u0);

cbuffer Constants : register(b0)
{
    int4 g_dims;
}

[numthreads(8,8,1)]
void csMainDebugVis(int3 dti : SV_DispatchThreadID)
{
    g_output[dti.xy] = g_visibilityBuffer[dti.xy];//float2((dti.xy + 0.5)/float2(g_dims.xy)).xxxx;
}
