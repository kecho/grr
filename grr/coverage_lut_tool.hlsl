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

struct LineData
{
    float a;
    float b;
    float2 i0;
    float2 i1;

    void build(float2 v0, float2 v1)
    {
        //line equation: f(x): a * x + b;
        // where a = (v1.y - v0.y)/(v1.x - v0.x)
        float2 l = v1 - v0;
        a = l.y/l.x;
        b = v1.y - a * v1.x;

        i0 = float2(0.5/8.0, eval(0.5/8.0)); 
        i1 = float2(7.5/8.0, eval(7.5/8.0)); 
    }

    float eval(float xval)
    {
        return xval * a + b;
    }

    float4 eval4(float4 xvals)
    {
        return xvals * a + b;
    }
};

struct LineBaseMask
{
    int offsets[2]; //offset is 1st int y coord of ys
    uint masks[2]; //corresponds to increment 
    LineData debugLine;
    bool flipX;

    float2 getPoint(uint i)
    {
        int j = i & 0x3;
        int m = i >> 2;
        int yval = offsets[m] + (int)countbits(((1u << j) - 1) & masks[m]);
        float2 v = float2(i + 0.5, yval + 0.5) * 1.0/8.0;
        if (flipX)
            v.x = 1.0 - v.x;
        return v;
    }
    
    static LineBaseMask create(float2 v0, float2 v1)
    {
        LineBaseMask data;

        //line debug data
        data.debugLine.build(v0, v1);

        LineData l = (LineData)0;
        {
            float2 ll = v1 - v0;
            data.flipX = sign(ll.y) != sign(ll.x);
            if (data.flipX)
            {
                v0.x = 1.0 - v0.x;
                v1.x = 1.0 - v1.x;
                l.a = -ll.y/ll.x;
            }
            else
            {
                l.a = ll.y/ll.x;
            }

            l.b = v1.y - l.a * v1.x;
        }

        // Xs values of 5 points
        const float4 xs = (float4(0,1,2,3) + 0.5)/8.0;
        const float xs4 = 4.5/8.0;

        // Ys values of 5 points, and also  their uint counterparts
        float4 ys = l.eval4(xs);
        float ys4 = l.eval(xs4);

        int4 ysi = (int4)floor(ys * 8.0);
        int ysi4 = (int) floor(ys4 * 8.0);

        // Incremental mask
        uint4 dysmask = uint4(ysi.yzw,ysi4) - ysi.xyzw;

        // Final output, offset and mask
        data.offsets[0] = ysi.x;
        data.masks[0] = dysmask.x | (dysmask.y << 1) | (dysmask.z << 2) | (dysmask.w << 3);

        //Second mask
        ys = l.eval4(xs + 4.0/8.0);
        ys4 = l.eval(8.5/8.0);
        ysi = (int4)floor(ys * 8.0);
        ysi4 = (int) floor(ys4 * 8.0);
        dysmask = uint4(ysi.yzw,ysi4) - ysi.xyzw;

        data.offsets[1] = countbits(data.masks[0]) + data.offsets[0];
        data.masks[1] = dysmask.x | (dysmask.y << 1) | (dysmask.z << 2) | (dysmask.w << 3);
        return data;
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

float3 drawBaseMask(float3 col, in LineBaseMask lineBaseMask, uint i, float2 uv)
{
    float2 gridUV = getGridUV(uv);
    float d = distance(gridUV, lineBaseMask.getPoint(i) * 8.0);
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

    //make all uv coordinates relative to board
    tri.v0 -= boardOffset;
    tri.v1 -= boardOffset;
    tri.v2 -= boardOffset;

    if (all(boardUv >= 0.0) && all(boardUv <= 1.0))
    {
        uint2 mask = uint2(0, 1251512);
        float4 gridCol = drawGrid(boardUv, mask);
        color = lerp(color, gridCol.rgb, saturate(gridCol.a));
        
        LineBaseMask lineMask = LineBaseMask::create(tri.v0, tri.v1);
        if (abs(lineMask.debugLine.a) < 0.5)
        {
            for (uint i = 0; i < 8; ++i)
                color = drawBaseMask(color, lineMask, i, boardUv);
        }
        color = drawVertex(color, lineMask.debugLine.i0, boardUv);
        color = drawVertex(color, lineMask.debugLine.i1, boardUv);
    }

    g_output[pixelCoord] = float4(color, 1.0);
}
