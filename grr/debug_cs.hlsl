#include "raster_util.hlsl"

SamplerState g_fontSampler : register(s0);

Texture2D<float4> g_debugFont : register(t0);
Texture2D<float4> g_visibilityBuffer : register(t1);
Buffer<uint> g_totalBins : register(t2);
Buffer<uint> g_binCounters : register(t3);
StructuredBuffer<raster::BinIntersectionRecord> g_binOutputRecords : register(t4);

RWTexture2D<float4> g_output : register(u0);

cbuffer Constants : register(b0)
{
    int4 g_dims;
    float g_binTileX;
    float g_binTileY;
    int   g_binCoarseTileSize;
    int   g_unused;
}

float4 drawNumber(float2 uv, int digitsCount, int number)
{
    int leadingZeros = 0;
    int leadingZN = number;
    while (leadingZN != 0)
    {
        ++leadingZeros;
        leadingZN /= 10;
    }
    leadingZN = digitsCount - leadingZeros;
    uv.x += (float)leadingZN/(float)digitsCount;
    if (uv.x > 1.0)
        return float4(0,0,0,0);

    int currDigit = clamp(digitsCount - (int)(uv.x * digitsCount) - 1.0, 0, digitsCount - 1);

    number /= pow(10, currDigit);
    uv.x = fmod(uv.x * digitsCount, 1.0);
    
    float row = 3.0/16.0;
    float col = float(number % 10)/16.0;
    float2 samplePos = float2(col + uv.x * 1.0/16.0, row + uv.y * 1.0/16.0);
    float4 val = g_debugFont.SampleLevel(g_fontSampler, samplePos, 0.0);
    return val.xxxx;
}

float4 drawTile(int2 coord, int tileSize, int tileCount)
{
    float borderThickness = 0.02;
    const int numberOfDigits = 4;
    float fontSquare = 16.0/64.0;
    float2 fontBlock = float2(fontSquare * numberOfDigits, fontSquare);
    float4 borderColor = float4(0.02, 0.03, 0.4, 1.0);
    float4 tileColor = float4(0, 0, 1.0, 0.3);

    int2 tileCoord = int2(coord.x % tileSize, coord.y % tileSize);
    float2 tileUv = (tileCoord + 0.5) / (float)tileSize;
    float2 borderUvs = abs(tileUv * 2.0 - 1.0) - (1.0 - borderThickness);
    bool isBorder = any(borderUvs > 0.0);
    if (isBorder)
        return borderColor;
    
    bool isFont = all(tileUv < fontBlock);
    if (isFont)
    {
        float4 fontCol = drawNumber(tileUv / fontBlock, numberOfDigits, tileCount);
        tileColor.rgba = lerp(tileColor.rgba, fontCol.rgba, fontCol.a);
    }

    return tileColor;
}

[numthreads(8,8,1)]
void csMainDebugVis(int3 dti : SV_DispatchThreadID)
{
    int tileX = dti.x / g_binCoarseTileSize;
    int tileY = dti.y / g_binCoarseTileSize;
    int tileId = tileY * g_binTileX + tileX;
    uint count = g_binCounters[tileId];

    float4 tileColor = drawTile(dti.xy, g_binCoarseTileSize, count);
    float4 debugBinCol = count != 0 ? tileColor : float4(0,0,0,0);

    float3 finalColor = lerp(g_visibilityBuffer[dti.xy].xyz, debugBinCol.xyz, debugBinCol.a);
    g_output[dti.xy] = float4(finalColor, 1.0);
}
