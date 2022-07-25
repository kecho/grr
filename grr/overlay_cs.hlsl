#include "raster_util.hlsl"
#include "geometry.hlsl"
#include "debug_font.hlsl"

#define OVERLAY_FLAGS_NONE 0
#define OVERLAY_FLAGS_SHOW_COARSE_TILES 1 << 0
#define OVERLAY_FLAGS_SHOW_FINE_TILES 1 << 1

SamplerState g_fontSampler : register(s0);

Texture2D<float4> g_debugFont : register(t0);
Texture2D<float4> g_colorBuffer : register(t1);
Buffer<uint> g_totalBins : register(t2);
Buffer<uint> g_binCounters : register(t3);
Buffer<uint> g_binOffsets : register(t4);
StructuredBuffer<raster::BinIntersectionRecord> g_binOutputRecords : register(t5);
Buffer<uint> g_fineTileCounters : register(t6);

RWTexture2D<float4> g_output : register(u0);

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
    int   g_overlayFlags;
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
        float4 fontCol = Font::drawNumber(g_debugFont, g_fontSampler, fontTileUv / fontBlock, numberOfDigits, tileCount);
        float4 fontColShadow = Font::drawNumber(g_debugFont, g_fontSampler, (fontTileUv - 2.0 * 1.5/TILE_SIZE) / fontBlock, numberOfDigits, tileCount);
        tileColor.rgba = lerp(tileColor.rgba, float4(0,0,0,1), fontColShadow.a);
        tileColor.rgba = lerp(tileColor.rgba, fontCol.rgba, fontCol.a);
    }

    return tileColor;
}

float3 heatColor(float t)
{
    float r = t*t*t;
    float g = pow(abs(1.0 - abs(1.0 - (2.0 * t))), 3);
    float b = pow((1-t),3);
    return float3(r,g,b);
}

float4 drawHeatmapLegend(float2 uv, float2 minUv, float2 maxUv)
{
    if (any(uv < minUv) || any(uv > maxUv))
        return float4(0,0,0,0);

    float fontSquare = FONT_BLOCK_SIZE / TILE_SIZE;
    float2 txy = (uv - minUv)/(maxUv - minUv);
    txy.y = 1.0 - txy.y;

    float2 quadSizePixels = (maxUv - minUv) * float2(g_dims.xy);
    float2 fontQuad = quadSizePixels/FONT_BLOCK_SIZE;
    
    float4 beginFont  = Font::drawNumber(g_debugFont, g_fontSampler, (txy - float2(0.0 , 0))*fontQuad / float2(2,1), 2, 1);
    float4 middleFont = Font::drawNumber(g_debugFont, g_fontSampler, (txy - float2(0.5 , 0))*fontQuad / float2(3,1), 3, 500) * float4(0.3,0.3,0.3,1.0);
    float4 endFont    = Font::drawNumber(g_debugFont, g_fontSampler, (txy - float2(1.0 - (4 * FONT_BLOCK_SIZE/quadSizePixels.x), 0))*fontQuad / float2(4,1), 4, 1000);
    float4 fontCol = float4(0,0,0,0);
    fontCol = lerp(fontCol, beginFont,  beginFont.a);
    fontCol = lerp(fontCol, middleFont, middleFont.a);
    fontCol = lerp(fontCol, endFont,    endFont.a);
    float4 bgCol = float4(heatColor(txy.x), 0.9);
    return lerp(bgCol, fontCol, fontCol.a);
}

[numthreads(FINE_TILE_SIZE, FINE_TILE_SIZE, 1)]
void csMainOverlay(int3 dti : SV_DispatchThreadID, int2 groupID : SV_GroupID)
{
    float3 finalColor = g_colorBuffer[dti.xy].xyz;
    int2 outputCoord = int2(dti.x, g_dims.y - dti.y - 1);
    float2 uv = geometry::pixelToUV(dti.xy, g_dims.xy);

    [branch]
    if ((g_overlayFlags & OVERLAY_FLAGS_SHOW_COARSE_TILES) != 0)
    {
        int tileX = groupID.x >> FINE_TILE_TO_TILE_SHIFT;
        int tileY = groupID.y >> FINE_TILE_TO_TILE_SHIFT;
        int tileId = tileY * g_binTileX + tileX;
        uint count = g_binCounters[tileId];
        float4 tileColor = drawTile(uv * g_dims.xy * 1.0, COARSE_TILE_SIZE, count);
        float4 debugBinCol = count != 0 ? tileColor : float4(0,0,0,0);
        finalColor = lerp(finalColor, debugBinCol.xyz, debugBinCol.a);
    }

    [branch]
    if ((g_overlayFlags & OVERLAY_FLAGS_SHOW_FINE_TILES) != 0)
    {
        float4 heatmapColor = drawHeatmapLegend(uv, float2(0.07, 0.1), float2(0.93, 0.15));
        float2 fineTileSize = ceil((float2)g_dims.xy / FINE_TILE_SIZE);
        uint tileCounts = g_fineTileCounters[groupID.y * (int)fineTileSize.x + groupID.x];
        float3 tileColor = heatColor(saturate((float)tileCounts / 300.0));
        finalColor = lerp(finalColor, tileColor, 0.7 * (tileCounts > 0 ? 1.0 : 0.0));
        finalColor = lerp(finalColor, heatmapColor.rgb, heatmapColor.a);
    }

    g_output[outputCoord] = float4(finalColor, 1.0);
}
