
cbuffer Constants : register(b0)
{
    float4 g_size; //w,h,1/w,1/h
}

RWTexture2D<float4> g_output : register(u0);

[numthreads(8,8,1)]
void csMain(
    uint2 dispatchThreadID : SV_DispatchThreadID)
{
    //g_output[dispatchThreadID.xy] = float4(dispatchThreadID.xy,0.0,1.0) * float4(g_size.zw, 1.0, 1.0);
    g_output[dispatchThreadID.xy] = float4(dispatchThreadID.x * g_size.z > 0.5 ? float3(1,0,0) : float3(0,0,1), 1.0);
}
