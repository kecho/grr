#ifndef __GEOMETRY__

namespace geometry
{

    struct Vertex
    {
        float3 p;
        float3 n;
        float2 uv;
    };

    struct Triangle
    {
        int a;
        int b;
        int c;
    };

    Triangle sampleTriangle(Buffer<int> indices, int triangleId)
    {
        Triangle t;
        int i = 3 * triangleId;
        t.a = indices[i + 0];
        t.b = indices[i + 1];
        t.c = indices[i + 2];
        return t;
    }

    float triangleArea(float2 a, float2 b, float2 c)
    {
        return 0.5 * (a.x * (b.y - c.y) + b.x * (c.y - a.y) + c.x * (a.y - b.y));
    }

    float3 computeBaryCoord(float2 a, float2 b, float2 c, float2 p)
    {
        float totalArea = triangleArea(a, b, c);
        float area1 = triangleArea(b, c, p);
        float area2 = triangleArea(c, a, p);
        float2 bari = float2(area1 / totalArea, area2 / totalArea);
        return float3(bari.x, bari.y, 1.0 - (bari.x + bari.y));
    }

    float3 computeBaryCoordPerspective(float3 aw, float3 bw, float3 cw, float2 p)
    {
        float3 b = computeBaryCoord(aw.xy, bw.xy, cw.xy, p);
        float3 B = float3(b.x / aw.z, b.y / bw.z, b.z / cw.z);
        B /= (B.x + B.y + B.z);
        return B;
    }
}

#endif
