#ifndef __COVERAGE__
#define __COVERAGE__

//Utilities for coverage bit mask on an 8x8 grid.
namespace coverage
{

//lut for 4x4 quad mask. See buildQuadMask function
// 2 states for horizontal flipping
groupshared uint gs_quadMask[16 * 2]; 

// buildQuadMask
//Function that builds a 4x4 compact bit quad for line coverage.
// the line is assumed to have a positive slope < 1.0. That means it can only be raised 1 step at most.
// "incrementMask" is a bit mask specifying how much the y component of a line increments.
// "incrementMask" only describes 4 bits, the rest of the bits are ignored.
// For example, given this bit mask:
// 1 0 1 0
// would generate this 4x4 coverage mask:
//
// 0 0 0 0 
// 0 0 0 1 <- 3rd bit tells the line to raise here
// 0 1 1 1 <- first bit raises the line
// 1 1 1 1 <- low axis is always covered
uint buildQuadMask(uint incrementMask)
{
    uint c = 0;

    uint mask = 0xF;
    for (int r = 0; r < 4; ++r)
    {
        c |= mask << (r * 8);
        if (incrementMask == 0)
            break;
        int b = firstbitlow(incrementMask);
        mask = (0xFu << (b + 1)) & 0xFu;
        incrementMask ^= 1u << b;
    }

    return c;
}

//flip 4 bit nibble
uint flipNibble(uint mask, int offset)
{
    mask = (mask >> offset) & 0xF;
    uint r = ((mask << 3) & 0x8)
           | ((mask << 1) & 0x4)
           | ((mask >> 1) & 0x2)
           | ((mask >> 3) & 0x1);
    return (r << offset);
}

//flip an entire 4x4 bit quad
uint flipQuadInX(uint mask)
{
    return flipNibble(mask, 0) | flipNibble(mask, 8) | flipNibble(mask, 16) | flipNibble(mask, 24);
}

uint transposeQuad(uint mask)
{
    uint result = 0;
    [unroll]
    for (int i = 0; i < 4; ++i)
    {
        for (int j = 0; j < 4; ++j)
        {
            if (mask & (1u << (i * 8 + j)))
                result |= 1u << (j * 8 + i);
        }
    }
    return result;
}

// Builds all the luts necessary for fast bit based coverage
void init(uint groupThreadIndex)
{
    // Neutral
    if (groupThreadIndex < 16)
        gs_quadMask[groupThreadIndex] = buildQuadMask(groupThreadIndex);

    GroupMemoryBarrierWithGroupSync();

    // Flip in X axis, transpose
    if (groupThreadIndex < 16)
    {
        gs_quadMask[groupThreadIndex + 16] = flipQuadInX(gs_quadMask[groupThreadIndex]);
        gs_quadMask[groupThreadIndex + 32] = transposeQuad(gs_quadMask[groupThreadIndex]);
    }
}

// Represents a 2D analytical line.
// stores slope (a) and offset (b)
struct Line
{
    float a;
    float b;

    // Builds an analytical line based on two points.
    void build(float2 v0, float2 v1)
    {
        //line equation: f(x): a * x + b;
        // where a = (v1.y - v0.y)/(v1.x - v0.x)
        float2 l = v1 - v0;
        a = l.y/l.x;
        b = v1.y - a * v1.x;
    }

    // Builds a "Flipped" line.
    // A flipped line is defined as having a positive slope < 1.0 
    // The two output booleans specify the flip operators to recover the original line.
    void buildFlipped(float2 v0, float2 v1, out bool outFlipX, out bool outFlipAxis)
    {
        //build line with flip bits for lookup compression
        //This line will have a slope between 0 and 0.5, and always positive.
        //We output the flips as bools

        float2 ll = v1 - v0;
        outFlipAxis = abs(ll.y) > abs(ll.x);
        if (outFlipAxis)
        {
            ll.xy = ll.yx;
            v0.xy = v0.yx;
            v1.xy = v1.yx;
        }

        outFlipX = sign(ll.y) != sign(ll.x);
        a = ll.y/ll.x;
        if (outFlipX)
        {
            v0.x = 1.0 - v0.x;
            v1.x = 1.0 - v1.x;
            a *= -1;
        }

        b = v1.y - a * v1.x;
    }

    // Evaluates f(x) = a * x + b for the line
    float eval(float xval)
    {
        return xval * a + b;
    }

    // Evaluates 4 inputs of f(x) = a * x + b for the line
    float4 eval4(float4 xvals)
    {
        return xvals * a + b;
    }

    // Evaluates a single 2d in the line given an X.
    float2 pointAt(float xv)
    {
        return float2(xv, eval(xv));
    }
};

// Represents a set of bits in an 8x8 grid divided by a line.
// The representation is given by 2 splits of the 8x8 grid.
// offsets represents how much we offset the quadCoverage on either x or y (flipped dependant axis)
// the mask represents the increment mask used to look up the quadCoverage
struct LineArea
{
    int offsets[2];
    uint masks[2];
    bool flipX;
    bool flipAxis;
    Line debugLine;

    // Recovers a single point in the boundary
    // of the line (where the line intersects a pixel).
    // Theres a total of 8 possible points
    float2 getBoundaryPoint(uint i)
    {
        int j = i & 0x3;
        int m = i >> 2;
        int yval = offsets[m] + (int)countbits(((1u << j) - 1) & masks[m]);
        float2 v = float2(i + 0.5, yval + 0.5) * 1.0/8.0;
        if (flipX)
            v.x = 1.0 - v.x;
        if (flipAxis)
        {
            float2 tmp = v;
            v.xy = tmp.yx;
        }
        return v;
    }
    
    // Creates a line area object, based on 2 points on an 8x8 quad
    // quad coordinate domain is 0.0 -> 1.0 for both axis.
    // Anything negative or greater than 1.0 is by definition outside of the 8x8 quad.
    static LineArea create(float2 v0, float2 v1)
    {
        LineArea data;

        //line debug data
        data.debugLine.build(v0, v1);

        Line l;
        l.buildFlipped(v0, v1, data.flipX, data.flipAxis);

        // Xs values of 8 points
        const float4 xs0 = float4(0.5,1.5,2.5,3.5)/8.0;
        const float4 xs1 = float4(4.5,5.5,6.5,7.5)/8.0;

        // Ys values of 8 points
        float4 ys0 = l.eval4(xs0);
        float4 ys1 = l.eval4(xs1);

        int4 ysi0 = (int4)floor(ys0 * 8.0 - 0.5);
        int4 ysi1 = (int4)floor(ys1 * 8.0 - 0.5);

        // Incremental masks
        uint4 dysmask0 = uint4(ysi0.yzw, ysi1.x) - ysi0.xyzw;
        uint4 dysmask1 = uint4(ysi1.yzw, 0) - uint4(ysi1.xyz, 0);

        // Final output, offset and mask
        data.offsets[0] = ysi0.x;
        data.masks[0] = dysmask0.x | (dysmask0.y << 1) | (dysmask0.z << 2) | (dysmask0.w << 3);
        data.offsets[1] = countbits(data.masks[0]) + data.offsets[0];
        data.masks[1] = dysmask1.x | (dysmask1.y << 1) | (dysmask1.z << 2) | (dysmask1.w << 3);
        return data;
    }
} ;

uint2 createCoverageMask(in LineArea lineArea)
{
    const uint leftSideMask = 0x0F0F0F0F;
    const uint2 horizontalMask = uint2(leftSideMask, ~leftSideMask);

    //prepare samples
    int2 ii = lineArea.flipX ? int2(1,0) : int2(0,1);
    int2 flipOffset = lineArea.flipX ? int2(16,16) : int2(0,0);
    int2 offsets = int2(lineArea.offsets[ii.x],lineArea.offsets[ii.y]);

#if 1
    // generate masks
    uint2 quadSamples = uint2(gs_quadMask[lineArea.masks[ii.x] + flipOffset.x], gs_quadMask[lineArea.masks[ii.y] + flipOffset.y]);
    uint2 sideMasks = uint2(~quadSamples.x, ~(quadSamples.y << 4)) & horizontalMask;
    int4 tOffsets = clamp((offsets.xyxy - int4(0,0,4,4)) << 3, -31, 31);
    uint4 halfMasks = (tOffsets > 0 ? sideMasks.xyxy << tOffsets : ~(~sideMasks.xyxy >> -tOffsets)) & horizontalMask.xyxy;
    return uint2(halfMasks.x|halfMasks.y, halfMasks.z|halfMasks.w);
#else
    uint2 sampledQuads = uint2(gs_quadMask[lineArea.masks[0] + 32], gs_quadMask[lineArea.masks[1] + 32]);
    int2 offsets = int2(lineArea.offsets[0],lineArea.offsets[1]);
    int2 tOffsets = offsets;
    bool2 validMasks = abs(tOffsets) < 8;
    uint2 halfMasks = tOffsets.xy < 4.xx ? horizontalMask.xx : (~horizontalMask).xx;
    uint2 masks = (sampledQuads * validMasks);
    uint2 halfs = tOffsets > 0 ? masks << tOffsets : masks >> -tOffsets;
    return halfs & halfMasks;
#endif
}

}

#endif
