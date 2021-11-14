#ifndef __GEOMETRY__

namespace geometry
{
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

    struct Vertex
    {
        float3 p;
        //float3 n;
        //float2 uv;
    };

    struct TriangleI
    {
        int a;
        int b;
        int c;
    
        void load(Buffer<int> indices, int triangleId)
        {
            int i = 3 * triangleId;
            a = indices[i + 0];
            b = indices[i + 1];
            c = indices[i + 2];
        }
    };

    struct TriangleV
    {
        Vertex a;
        Vertex b;
        Vertex c;

        void load(StructuredBuffer<Vertex> vertices, in TriangleI indices)
        {
            a = vertices[indices.a];
            b = vertices[indices.b];
            c = vertices[indices.c];
        }
    };

    struct TriInterpResult
    {
        bool visible;
        float3 bari;

        float3 eval(float3 a, float3 b, float3 c)
        {
            return a * bari.x + b * bari.y + c * bari.z;
        }
    };

    struct TriangleAABB
    {
        float3 begin;
        float3 end;
    };

    struct TriangleH
    {
        float4 h0;
        float4 h1;
        float4 h2;

        float3 p0;
        float3 p1;
        float3 p2;

        void init(TriangleV tri, float4x4 view, float4x4 proj)
        {
            h0 = mul(mul(float4(tri.a.p.xyz, 1.0), view), proj);
            h1 = mul(mul(float4(tri.b.p.xyz, 1.0), view), proj);
            h2 = mul(mul(float4(tri.c.p.xyz, 1.0), view), proj);

            p0 = h0.xyz / h0.w;
            p1 = h1.xyz / h1.w;
            p2 = h2.xyz / h2.w;
        }

        TriInterpResult interp(float2 hCoords)
        {
            float2 ea = p1.xy - p0.xy;
            float2 eb = p2.xy - p1.xy;
            float2 ec = p0.xy - p2.xy;

            float2 pa = hCoords - p0.xy;
            float2 pb = hCoords - p1.xy;
            float2 pc = hCoords - p2.xy;

            float wa = ea.x * pa.y - ea.y * pa.x;
            float wb = eb.x * pb.y - eb.y * pb.x;
            float wc = ec.x * pc.y - ec.y * pc.x;

            float frontFace = -max(wa, max(wb, wc));
            float backFace = min(wa, min(wb, wc));

            TriInterpResult result;
            result.bari = computeBaryCoordPerspective(float3(p0.xy,h0.w), float3(p1.xy,h1.w), float3(p2.xy,h2.w), hCoords);
            result.visible = (frontFace > 0.0) || (backFace > 0.0);
            return result;
        }

        TriangleAABB aabb()
        {
            TriangleAABB val;
            val.begin = min(p0, min(p1, p2));
            val.end = max(p0, max(p1, p2));
            return val;
        }
    };

}

#endif
