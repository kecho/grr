/*
MIT License

Copyright (c) 2022 Kleber Garcia

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
*/

#ifndef __COVERAGE__
#define __COVERAGE__

//Utilities for coverage bit mask on an 8x8 grid.
namespace coverage
{

//**************************************************************************************************************/
//                                           How to use
//**************************************************************************************************************/
/*
To utilize this library, first call the genLUT function at the beginning of your compute shader.
This function must be followed by a group sync. Example follows:

...
coverage::genLUT(groupThreadIndex);
GroupMemoryBarrierWithGroupSync();
...

Alternatively, you can dump the contents into buffer. The contents of the LUT are inside gs_quadMask, which is 64 entries.

After this use the coverage functions. For example:

uint2 lineCoverage = coverage::lineCoverageMask(float2(0.0, 0.0), float2(0.5, 0.5), 0.2, 0.2);

This line will hold a 8x8 mask of coverage for such line.


*/

//**************************************************************************************************************/
//                                        Coordinate System 
//**************************************************************************************************************/
/*
The functions in this library follow the same convension, input is a shape described by certain vertices,
output is a 64 bit mask with such shape's coverage.

The coordinate system is (0,0) for the top left of an 8x8 grid, and (1,1) for the bottom right.
The LSB represents coordinate (0,0), and sample points are centered on the pixel.

(0.0,0.0)                           (1.0,0.0)
    |                                   |
    |___________________________________|
    |   |   |   |   |   |   |   |   |   |
    | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 |
    |___|___|___|___|___|___|___|___|___|
    |   |   |   |   |   |   |   |   |   |
    | 9 | 10| 11| 12| 13| 14| 15| 16| 17|
    |___|___|___|___|___|___|___|___|___|___(1.0, 2.0/8.0)

 the center of bit 0 would be 0.5,0.5 and so on

any points outside of the range (0,1) means they are outside the grid.
*/

//**************************************************************************************************************/
//                                           coverage API
//**************************************************************************************************************/

/*
Call this function to generate the coverage 4x4 luts
groupThreadIndex - the thread index.
NOTE: must sync group threads after calling this. 
*/
void genLUT(uint groupThreadIndex);

/*
Call this function to get a 64 bit coverage mask for a triangle.
v0, v1, v2 - the triangle coordinates in right hand ruling order
return - the coverage mask for this triangle
*/
uint2 triangleCoverageMask(float2 v0, float2 v1, float2 v2, bool showFrontFace, bool showBackface, bool isConservative = false);


/*
Call this function to get a 64 bit coverage mask for a line.
v0, v1 - the line coordinates.
thickness - thickness of line in normalized space. 1.0 means the entire 8 pixels in a tile
caps - extra pixels in the caps of the line in normalized space. 1.0 means 8 pixels in a tile
return - the coverage mask of this line
*/
uint2 lineCoverageMask(float2 v0, float2 v1, float thickness, float caps);


//**************************************************************************************************************/
//                                       coverage implementation 
//**************************************************************************************************************/

/*
function that builds a 4x4 compact bit quad for line coverage.
the line is assumed to have a positive slope < 1.0. That means it can only be raised 1 step at most.
"incrementMask" is a bit mask specifying how much the y component of a line increments.
"incrementMask" only describes 4 bits, the rest of the bits are ignored.
For example, given this bit mask:
1 0 1 0
would generate this 4x4 coverage mask:

0 0 0 0 
0 0 0 1 <- 3rd bit tells the line to raise here
0 1 1 1 <- first bit raises the line
1 1 1 1 <- low axis is always covered
*/
uint buildQuadMask(uint incrementMask)
{
    uint c = 0;

    uint mask = 0xF;
    for (int r = 0; r < 4; ++r)
    {
        c |= mask << (r * 4);
        if (incrementMask == 0)
            break;
        int b = firstbitlow(incrementMask);
        mask = ((0xFu << (b + 1)) & 0xFu);
        incrementMask ^= 1u << b;
    }

    return c;
}

/*
lut for 4x4 quad mask. See buildQuadMask function, packed in 16 bits.
4 states for horizontal flipping and vertical flipping
You can dump this lut to a buffer, and preload it manually,
or just regenerated in your thread group
*/
groupshared uint gs_quadMask[8]; 

// Builds all the luts necessary for fast bit based coverage
void genLUT(uint groupThreadIndex)
{
    if (groupThreadIndex < 8u)
    {
        uint m0 = buildQuadMask((groupThreadIndex << 1) | 0);
        uint m1 = buildQuadMask((groupThreadIndex << 1) | 1);
        gs_quadMask[groupThreadIndex] = m0 | (m1 << 16);
    }
}

uint sampleLUT(uint lookup)
{
    uint mask = (gs_quadMask[lookup >> 1] >> (16 * (lookup & 0x1))) & 0xFFFF;
    return (mask & 0xF) | ((mask & 0xF0) << 4) | ((mask & 0xF00) << 8) | ((mask & 0xF000) << 12);
}

uint2 transposeCoverageMask(uint2 mask)
{
    //1x1 transpose
    mask = ((mask & 0x00aa00aa) << 7) | ((mask & 0x55005500) >> 7) | (mask & 0xaa55aa55);

    //2x2 transpose
    mask = ((mask & 0x0000cccc) << 14) | ((mask & 0x33330000) >> 14) | (mask & 0xcccc3333);

    //4x4
    mask = uint2((mask.y & 0x0f0f0f0f) << 4, (mask.x & 0xf0f0f0f0) >> 4) | (mask & uint2(0x0f0f0f0f, 0xf0f0f0f0));
    return mask;
}

uint2 mirrorXCoverageMask(uint2 mask)
{
    //flip 1 in x
    mask = ((mask & 0x55555555) << 1) | ((mask & 0xaaaaaaaa) >> 1);

    //flip 2 in x
    mask = ((mask & 0xcccccccc) >> 2) | ((mask & 0x33333333) << 2);

    //flip 4 in x
    mask = ((mask & 0xf0f0f0f0) >> 4) | ((mask & 0x0f0f0f0f) << 4);
    return mask;
}

uint2 mirrorYCoverageMask(uint2 mask)
{
    //flip 4 in y
    mask.yx = mask;
    //flip 2 in y
    mask = ((mask & 0x0000ffff) << (uint2)16u) | ((mask & 0xffff0000) >> (uint2)16u);
    //flip 1 in y
    mask = ((mask & 0x00ff00ff) << 8) | ((mask & 0xff00ff00) >> 8);

    return  mask;
}

#define COVERAGE_LINE_FLAGS_TRANSPOSE (1 << 0)
#define COVERAGE_LINE_FLAGS_X_FLIP (1 << 1)
#define COVERAGE_LINE_FLAGS_Y_FLIP (1 << 2)
#define COVERAGE_LINE_FLAGS_VALID (1 << 3)

// Represents a 2D analytical line.
// stores slope (a) and offset (b)
struct Line
{
    float a;
    float b;

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


// Builds an analytical line based on two points.
Line buildLine(float2 v0, float2 v1)
{
    //line equation: f(x): a * x + b;
    // where a = (v1.y - v0.y)/(v1.x - v0.x)
    float2 l = v1 - v0;
    Line li;
    li.a = l.y/l.x;
    li.b = v1.y - li.a * v1.x;
    return li;
}


// Builds a "Positive" line.
// A positive line is defined as having a positive slope less than 1.0.
// The positive line stores also flags that can be used to recover the original line.
Line buildPositiveLine(float2 v0, float2 v1, out uint flags)
{
    //build line with flip bits for lookup compression
    //This line will have a slope between 0 and 0.5, and always positive.
    //We output the flips as bools

    Line li;
    flags = 0u;

    if (v0.x > v1.x)
    {
        flags |= COVERAGE_LINE_FLAGS_X_FLIP;
        v0.x = 1.0 - v0.x;
        v1.x = 1.0 - v1.x;
    }
    if (v0.y > v1.y)
    {
        flags |= COVERAGE_LINE_FLAGS_Y_FLIP;
        v0.y = 1.0 - v0.y;
        v1.y = 1.0 - v1.y;
    }

    float2 ll = v1 - v0;
    flags |= abs(ll.y) > abs(ll.x) ? COVERAGE_LINE_FLAGS_TRANSPOSE : 0u;
    if (flags & COVERAGE_LINE_FLAGS_TRANSPOSE)
    {
        ll.xy = ll.yx;
        v0.xy = v0.yx;
        v1.xy = v1.yx;
    }

    flags |= any(v1 != v0) ? COVERAGE_LINE_FLAGS_VALID : 0;
    li.a = ll.y/ll.x;
    li.b = v1.y - li.a * v1.x;
    return li;
}

// Packing
// [bits] | [data]
//  0-3   | left_mask
//  4-7   | right_mask
//  8-11  | left_offset
//  12-15 | right_offset
//  16-20 | flags 
#define COVERAGE_DATA_BIT_MASK ((1u << 4) - 1u)
#define COVERAGE_LEFT_MASK_BIT_SHIFT 0
#define COVERAGE_RIGHT_MASK_BIT_SHIFT 4
#define COVERAGE_FLAGS_OFFSET_BIT_SHIFT 8

/*
Represents a set of bits in an 8x8 grid divided by a line.
The representation is given by 2 splits of the 8x8 grid.
offsets represents how much we offset the quadCoverage on either x or y (flipped dependant axis)
the mask represents the increment mask used to look up the quadCoverage
*/
struct LineArea
{
    uint coverageData;
    int2 offsets;
    Line debugLine;
} ;

// Creates a line area object, based on 2 points on an 8x8 quad
// quad coordinate domain is 0.0 -> 1.0 for both axis.
// Anything negative or greater than 1.0 is by definition outside of the 8x8 quad.
LineArea buildLineArea(float2 v0, float2 v1)
{
    LineArea data;

    //line debug data
    data.debugLine = buildLine(v0, v1);

    uint flags;
    Line l = buildPositiveLine(v0, v1, flags);
    data.coverageData = (flags & COVERAGE_DATA_BIT_MASK) << COVERAGE_FLAGS_OFFSET_BIT_SHIFT;

    // Xs values of 8 points
    const float4 xs0 = float4(0.5,1.5,2.5,3.5)/8.0;
    const float4 xs1 = float4(4.5,5.5,6.5,7.5)/8.0;

    // Ys values of 8 points
    float4 ys0 = l.eval4(xs0);
    float4 ys1 = l.eval4(xs1);

    int4 ysi0 = clamp((int4)floor(ys0 * 8.0 - 0.5), -1,8);
    int4 ysi1 = clamp((int4)floor(ys1 * 8.0 - 0.5), -1,8);

    // Incremental masks
    uint4 dysmask0 = uint4(ysi0.yzw, ysi1.x) - ysi0.xyzw;
    uint4 dysmask1 = uint4(ysi1.yzw, 0) - uint4(ysi1.xyz, 0);


    // Final output, offset and mask
    uint mask0 = dysmask0.x | (dysmask0.y << 1) | (dysmask0.z << 2) | (dysmask0.w << 3);
    data.coverageData |= (mask0 & COVERAGE_DATA_BIT_MASK) << COVERAGE_LEFT_MASK_BIT_SHIFT;
    uint mask1 = dysmask1.x | (dysmask1.y << 1) | (dysmask1.z << 2) | (dysmask1.w << 3);
    data.coverageData |= (mask1 & COVERAGE_DATA_BIT_MASK) << COVERAGE_RIGHT_MASK_BIT_SHIFT;
    data.offsets = int2(ysi0.x, countbits(mask0) + ysi0.x);

    return data;
}

uint2 createCoverageMask(in LineArea lineArea)
{
    const uint leftSideMask = 0x0F0F0F0F;
    const uint2 horizontalMask = uint2(leftSideMask, ~leftSideMask);
    int2 offsets = lineArea.offsets;

    uint2 halfSamples = uint2(
        sampleLUT((lineArea.coverageData >> COVERAGE_LEFT_MASK_BIT_SHIFT) & COVERAGE_DATA_BIT_MASK),
        sampleLUT((lineArea.coverageData >> COVERAGE_RIGHT_MASK_BIT_SHIFT) & COVERAGE_DATA_BIT_MASK));
    
    uint2 sideMasks = uint2(halfSamples.x, (halfSamples.y) << 4);

    // 4 quadrands (top left, top right, bottom left, bottom right)
    int4 quadrantOffsets = clamp((offsets.xyxy - int4(0,0,4,4)) << 3, -31, 31);

    uint flags = (lineArea.coverageData >> COVERAGE_FLAGS_OFFSET_BIT_SHIFT) & COVERAGE_DATA_BIT_MASK;
    uint4 halfMasks = select(quadrantOffsets > 0, (~sideMasks.xyxy & horizontalMask.xyxy) << quadrantOffsets, ~(sideMasks.xyxy >> -quadrantOffsets)) & horizontalMask.xyxy;
    uint2 coverageMask = uint2(halfMasks.x | halfMasks.y, halfMasks.z | halfMasks.w);
    coverageMask = (flags & COVERAGE_LINE_FLAGS_TRANSPOSE) ? ~transposeCoverageMask(coverageMask) : coverageMask;
    coverageMask = (flags & COVERAGE_LINE_FLAGS_X_FLIP) ? ~mirrorXCoverageMask(coverageMask) : coverageMask;
    coverageMask = (flags & COVERAGE_LINE_FLAGS_Y_FLIP) ? ~mirrorYCoverageMask(coverageMask) : coverageMask;
    return (flags & COVERAGE_LINE_FLAGS_VALID) ? ~coverageMask : 0u;
}

uint2 triangleCoverageMask(float2 v0, float2 v1, float2 v2, bool showFrontFace, bool showBackface, bool isConservative)
{
    uint2 mask0 = coverage::createCoverageMask(coverage::buildLineArea(v0, v1));
    uint2 mask1 = coverage::createCoverageMask(coverage::buildLineArea(v1, v2));
    uint2 mask2 = coverage::createCoverageMask(coverage::buildLineArea(v2, v0));
    uint2 frontMask = (mask0 & mask1 & mask2);
    bool frontMaskValid = any(mask0 != 0) || any(mask1 != 0) || any(mask2 != 0);
    uint2 triangleMask = (showFrontFace * (mask0 & mask1 & mask2)) | ((frontMaskValid && showBackface) * (~mask0 & ~mask1 & ~mask2));

    if (isConservative)
    {
        triangleMask |= (triangleMask >> 1) & ~0x80808080u; //left
        triangleMask |= (triangleMask << 1) & ~0x01010101u; //right

        //top
        triangleMask.x |= (triangleMask.y << 24) | (triangleMask.x >> 8);
        triangleMask.y |= triangleMask.y >> 8;

        //bottom
        triangleMask.y |= (triangleMask.x >> 24) | (triangleMask.y << 8);
        triangleMask.x |= triangleMask.x << 8;
    }

    return triangleMask;
}

uint2 lineCoverageMask(float2 v0, float2 v1, float thickness, float caps)
{
    float2 lineVector = normalize(v1 - v0);
    float2 D = cross(float3(lineVector, 0.0),float3(0,0,1)).xy * thickness;
    v0 -= caps * lineVector;
    v1 += caps * lineVector;
    
    uint2 mask0 = coverage::createCoverageMask(coverage::buildLineArea(v0 - D, v1 - D));
    uint2 mask1 = coverage::createCoverageMask(coverage::buildLineArea(v1 + D, v0 + D));
    uint2 mask2 = coverage::createCoverageMask(coverage::buildLineArea(v0 + D, v0 - D));
    uint2 mask3 = coverage::createCoverageMask(coverage::buildLineArea(v1 - D, v1 + D));
    return mask0 & mask1 & mask3 & mask2;
}

}

#endif

