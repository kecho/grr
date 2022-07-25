#ifndef _DEBUG_FONT_
#define _DEBUG_FONT_

#define FONT_BLOCK_SIZE 16.0

namespace Font
{

float4 drawNumber(
    Texture2D<float4> fontTexture,
    SamplerState fontSampler,
    float2 uv,
    int digitsCount,
    int number)
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
    float4 val = fontTexture.SampleLevel(fontSampler, samplePos, 0.0);
    return float4(val.rgb, val.r > 0.5 ? 1.0 : 0.0);
}

}

#endif
