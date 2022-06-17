#include "raster_util.hlsl"
#include "geometry.hlsl"

SamplerState g_fontSampler : register(s0);

Texture2D<float4> g_debugFont : register(t0);
Texture2D<float4> g_visibilityBuffer : register(t1);
Buffer<uint> g_totalBins : register(t2);
Buffer<uint> g_binCounters : register(t3);
Buffer<uint> g_binOffsets : register(t4);
StructuredBuffer<raster::BinIntersectionRecord> g_binOutputRecords : register(t5);

RWTexture2D<float4> g_output : register(u0);

#define FONT_BLOCK_SIZE 16.0
#define TILE_SIZE 32.0
#define BORDER_PIXELS 1.0
#define BORDER_COLOR float4(0.8, 0.8, 0.8, 0.3)
#define FONT_COLOR float4(0.8, 0.8, 0.8, 1.0)
#define TILE_COLOR float4(0, 0, 1.0, 0.3)

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
    if (any(uv < 0.0) || any(uv > 1.0))
        return float4(0,0,0,0);
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
    
    float row = 3.0/FONT_BLOCK_SIZE;
    float col = float(number % 10)/FONT_BLOCK_SIZE;
    float2 samplePos = float2(col + uv.x * 1.0/FONT_BLOCK_SIZE, row + uv.y * 1.0/FONT_BLOCK_SIZE);
    float4 val = g_debugFont.SampleLevel(g_fontSampler, samplePos, 0.0);
    return float4(val.rgb, val.r > 0.5 ? 1.0 : 0.0) * FONT_COLOR;
}

float4 drawTile(int2 coord, int tileSize, int tileCount)
{
    float borderThickness = BORDER_PIXELS / FONT_BLOCK_SIZE;
    const int numberOfDigits = 4;
    float fontSquare = FONT_BLOCK_SIZE/TILE_SIZE;
    float2 fontBlock = float2(fontSquare * numberOfDigits, fontSquare);

    int2 tileCoord = int2(coord.x % tileSize, coord.y % tileSize);
    float2 tileUv = (tileCoord + 0.5) / (float)tileSize;
    tileUv.y = 1.0 - tileUv.y;
    float2 borderUvs = abs(tileUv * 2.0 - 1.0) - (1.0 - borderThickness);
    bool isBorder = any(borderUvs > 0.0);
    if (isBorder)
        return BORDER_COLOR;
    
    float2 fontTileUv = tileUv - 5.0/TILE_SIZE;
    bool isFont = all(fontTileUv < fontBlock);
    fontTileUv *= 1.5;
    float4 tileColor = TILE_COLOR;
    if (isFont)
    {
        float4 fontCol = drawNumber(fontTileUv / fontBlock, numberOfDigits, tileCount);
        float4 fontColShadow = drawNumber((fontTileUv - 2.0 * 1.5/TILE_SIZE) / fontBlock, numberOfDigits, tileCount);
        tileColor.rgba = lerp(tileColor.rgba, float4(0,0,0,1), fontColShadow.a);
        tileColor.rgba = lerp(tileColor.rgba, fontCol.rgba, fontCol.a);
    }

    return tileColor;
}

[numthreads(MICRO_TILE_SIZE,MICRO_TILE_SIZE,1)]
void csMainDebugVis(int3 dti : SV_DispatchThreadID, int2 groupID : SV_GroupID)
{
    float2 uv = geometry::pixelToUV(dti.xy, g_dims.xy);
    int tileX = groupID.x >> MICRO_TILE_TO_TILE_SHIFT;
    int tileY = groupID.y >> MICRO_TILE_TO_TILE_SHIFT;
    int tileId = tileY * g_binTileX + tileX;
    uint count = g_binCounters[tileId];

    float4 tileColor = drawTile(uv * g_dims.xy * 1.0, COARSE_TILE_SIZE, count);
    float4 debugBinCol = count != 0 ? tileColor : float4(0,0,0,0);
    //float4 debugBinCol = float4(0,0,0,0);
    float3 finalColor = lerp(g_visibilityBuffer[dti.xy].xyz, debugBinCol.xyz, debugBinCol.a);

    int2 outputCoord = int2(dti.x, g_dims.y - dti.y - 1);
    g_output[outputCoord] = float4(finalColor, 1.0);
}
