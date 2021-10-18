

RWTexture2D<float4> g_output : register(u0);
cbuffer Constants : register(b0)
{
    float4 clearColor;
}

[numthreads(8,8,1)]
void main_clear(int2 dispatchThreadID : SV_DispatchThreadID)
{
    g_output[dispatchThreadID] = clearColor;
}
