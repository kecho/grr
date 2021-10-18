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
}

#endif
