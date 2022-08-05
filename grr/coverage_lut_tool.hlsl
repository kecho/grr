#include "debug_font.hlsl"
#include "coverage.hlsl"

// Flags must match coverage_lut_tool.py
#define SHOW_TRIANGLE (1 << 0)
#define SHOW_TRIANGLE_BACKFACE (1 << 1)
#define SHOW_TRIANGLE_FRONTFACE (1 << 2)
#define SHOW_LINE (1 << 3)

cbuffer Constants : register(b0)
{
    float4 g_size; //w,h,1/w,1/h
    float4 g_packedV0;
    float4 g_packedV1;
    float4 g_packedV2;
    float4 g_lineArgs;
    uint4 g_miscArgs;
}

struct InputVertices
{
    float2 v0;
    float2 v1;
    float2 v2;
    float2 v3;
    float2 v4;

    void load()
    {
        float2 aspect = float2(g_size.x * g_size.w, 1.0);
        v0 = g_packedV0.xy * aspect;    
        v1 = g_packedV0.zw * aspect;    
        v2 = g_packedV1.xy * aspect;    
        v3 = g_packedV1.zw * aspect;    
        v4 = g_packedV2.xy * aspect;    
    }
};

SamplerState g_fontSampler : register(s0);
Texture2D<float4> g_fontTexture : register(t0);
RWTexture2D<float4> g_output : register(u0);

float2 getGridUV(float2 uv)
{
    return uv * 8.0;
}

float4 drawGrid(float2 uv)
{
    float2 gridUV = getGridUV(uv);
    int2 gridCoord = (int2)gridUV;
    int gridIndex = gridCoord.y * 8 + gridCoord.x;
    
    gridUV = frac(gridUV);

    float4 numCol = Font::drawNumber(
        g_fontTexture, g_fontSampler, gridUV * float2(2.0,4.0), 2, gridIndex);

    float4 col = ((gridCoord.x + (gridCoord.y & 0x1)) & 0x1) ? float4(1,1,1,0.4) : float4(0.5,0.5,0.5,0.4);

    col.rgb += numCol.rgb * numCol.a;

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

float3 drawBaseMask(float3 col, in coverage::LineArea lineArea, uint i, float2 uv)
{
    float2 gridUV = getGridUV(uv);
    float d = distance(gridUV, lineArea.getBoundaryPoint(i) * 8.0);
    if (d > 0.1)
        return col;

    return float3(0.0,0.0,0.1);
}

float3 drawCoverageMask(float3 col, uint2 coverageMask, float2 uv)
{
    float2 gridUV = getGridUV(uv);
    int2 gridCoord = (int2)floor(gridUV);
    int gridCellId = gridCoord.y * 8 + gridCoord.x;
    uint shift = gridCellId & 0x1F;
    if ((1u << shift) & (gridCellId < 32 ? coverageMask.x : coverageMask.y))
    {
        float2 cellUv = frac(gridUV);
        float d = distance(float2(0.5,0.5), cellUv);
        if (d < 0.1)
            return float3(0.0,0.1,0.7);
    }

    return col;
}

[numthreads(8,8,1)]
void csMain(
    uint2 dispatchThreadID : SV_DispatchThreadID,
    uint groupThreadIndex : SV_GroupIndex)
{
    coverage::init(groupThreadIndex);

    GroupMemoryBarrierWithGroupSync();

    uint2 pixelCoord = dispatchThreadID.xy;
    float aspect = g_size.x * g_size.w;
    float2 screenUv = float2(pixelCoord) * g_size.zw * float2(aspect, 1.0);
    float2 boardOffset = 0.5 * aspect * float2((g_size.x - g_size.y), 0.0) * g_size.zw;
    float2 boardUv = screenUv - boardOffset;
    float3 color = float3(0,0,0);

    uint drawFlags = g_miscArgs.x;

    bool showTriangle = drawFlags & SHOW_TRIANGLE;
    bool showLine = drawFlags & SHOW_LINE;

    InputVertices verts;
    verts.load();
    if (showTriangle)
    {
        color = drawLine(color, verts.v0, verts.v1, screenUv);
        color = drawLine(color, verts.v1, verts.v2, screenUv);
        color = drawLine(color, verts.v2, verts.v0, screenUv);
        color = drawVertex(color, verts.v0, screenUv);
        color = drawVertex(color, verts.v1, screenUv);
        color = drawVertex(color, verts.v2, screenUv);
    }

    if (showLine)
    {
        color = drawLine(color, verts.v3, verts.v4, screenUv);
        color = drawVertex(color, verts.v3, screenUv);
        color = drawVertex(color, verts.v4, screenUv);
    }

    //make all uv coordinates relative to board
    verts.v0 -= boardOffset;
    verts.v1 -= boardOffset;
    verts.v2 -= boardOffset;
    verts.v3 -= boardOffset;
    verts.v4 -= boardOffset;

    uint2 triangleMask = 0;
    uint2 lineMask = 0;
    if (all(boardUv >= 0.0) && all(boardUv <= 1.0))
    {
        uint2 mask = uint2(0, 1251512);
        float4 gridCol = drawGrid(boardUv);
        color = lerp(color, gridCol.rgb, saturate(gridCol.a));

        bool showFrontFace = (drawFlags & SHOW_TRIANGLE_FRONTFACE) != 0;
        bool showBackFace = (drawFlags & SHOW_TRIANGLE_BACKFACE) != 0;
        triangleMask = showTriangle ? coverage::triangleCoverageMask(verts.v0, verts.v1, verts.v2, showFrontFace, showBackFace) : 0;

        float lineThickness = g_lineArgs.x;
        float lineCap = g_lineArgs.y;
        lineMask = showLine ? coverage::lineCoverageMask(verts.v3, verts.v4, lineThickness, lineCap) : 0;
    }

    color = drawCoverageMask(color, triangleMask | lineMask, boardUv);
    g_output[pixelCoord] = float4(color, 1.0);
}
