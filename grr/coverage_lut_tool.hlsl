#include "debug_font.hlsl"

cbuffer Constants : register(b0)
{
    float4 g_size; //w,h,1/w,1/h
    float4 g_packedTri0;
    float4 g_packedTri1;
}

struct InputTri
{
    float2 v0;
    float2 v1;
    float2 v2;

    void load()
    {
        float2 aspect = float2(g_size.x * g_size.w, 1.0);
        v0 = g_packedTri0.xy * aspect;    
        v1 = g_packedTri0.zw * aspect;    
        v2 = g_packedTri1.xy * aspect;    
    }
};

SamplerState g_fontSampler : register(s0);
Texture2D<float4> g_fontTexture : register(t0);
RWTexture2D<float4> g_output : register(u0);

float2 getGridUV(float2 uv)
{
    return uv * 8.0;
}

float4 drawGrid(float2 uv, uint2 bitMask)
{
    float2 gridUV = getGridUV(uv);
    int2 gridCoord = (int2)gridUV;
    int gridIndex = gridCoord.y * 8 + gridCoord.x;
    
    gridUV = frac(gridUV);

    float4 numCol = Font::drawNumber(
        g_fontTexture, g_fontSampler, gridUV * float2(2.0,4.0), 2, gridIndex);

    float4 col = ((gridCoord.x + (gridCoord.y & 0x1)) & 0x1) ? float4(1,1,1,0.4) : float4(0.5,0.5,0.5,0.4);

    col.rgb += numCol.rgb * numCol.a;
    int bitVal =  ((gridIndex >= 32) ? (bitMask.x >> (gridIndex - 32)) : (bitMask.y >> gridIndex)) & 0x1; 
    if (bitVal)
    {
        col = lerp(col, float4(0.6, 0, 0, 1), length(gridUV * 2.0 - 1.0) < 0.4 ? 1.0 : 0.0);
    }

    return col;
}

float3 drawVertex(float3 col, float2 v, float2 uv)
{
    float d = distance(v, uv);
    if (d < 0.01)
        return float3(0.8,0.8,0.0);
    return col;
}

float3 drawLine(float3 col, float2 v0, float2 v1, float2 uv)
{
    float ldist = distance(v1, v0);
    float2 lv = v1 - v0;
    float2 ld = lv/ldist;
    float2 ruv = uv - v0;
    float t = dot(ld, ruv);
    if (t < 0.0 || t > ldist)
        return col;

    float2 hitPoint = t * ld + v0;
    if (distance(hitPoint, uv) < 0.005)
        return float3(0.0, 0.0, 1.0);
    return col;
}

float3 drawBaseMask(float3 col, uint offset, uint mask, float2 uv)
{
    float2 gridUV = getGridUV(uv);
    float d = distance(gridUV, float2(0.5,0.5));
    if (d > 0.1)
        return col;

    return float3(0.0,0.0,0.1);
}

[numthreads(8,8,1)]
void csMain(
    uint2 dispatchThreadID : SV_DispatchThreadID)
{
    uint2 pixelCoord = dispatchThreadID.xy;
    float aspect = g_size.x * g_size.w;
    float2 screenUv = float2(pixelCoord) * g_size.zw * float2(aspect, 1.0);
    float2 boardOffset = 0.5 * aspect * float2((g_size.x - g_size.y), 0.0) * g_size.zw;
    float2 boardUv = screenUv - boardOffset;
    float3 color = float3(0,0,0);

    InputTri tri;
    tri.load();
    color = drawLine(color, tri.v0, tri.v1, screenUv);
    color = drawLine(color, tri.v1, tri.v2, screenUv);
    color = drawLine(color, tri.v2, tri.v0, screenUv);
    color = drawVertex(color, tri.v0, screenUv);
    color = drawVertex(color, tri.v1, screenUv);
    color = drawVertex(color, tri.v2, screenUv);

    if (all(boardUv >= 0.0) && all(boardUv <= 1.0))
    {
        uint2 mask = uint2(0, 1251512);
        float4 gridCol = drawGrid(boardUv, mask);
        color = lerp(color, gridCol.rgb, saturate(gridCol.a));
        color = drawBaseMask(color, 0, 0, boardUv);
    }

    g_output[pixelCoord] = float4(color, 1.0);
}
