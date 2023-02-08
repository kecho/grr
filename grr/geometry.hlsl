#ifndef __GEOMETRY__
#define __GEOMETRY__

//Geometry file with utitlies and definitions.
#include "depth_utils.hlsl"

namespace geometry
{
    //------------------------------------------
    // Geometric declarations
    //------------------------------------------
    struct TriangleI;
    struct TriangleV;
    struct TriangleH;
    struct AABB;

    float triangleArea(float2 a, float2 b, float2 c);
    float3 computeBaryCoord(float2 a, float2 b, float2 c, float2 p);
    float3 computeBaryCoordPerspective(float3 aw, float3 bw, float3 cw, float2 p);
    bool intersectsSAT(in TriangleH tri, in AABB aabb);

    //-----------------------------------------
    // Triangle / geometric types
    //-----------------------------------------

    struct Vertex
    {
        float3 p;
        //float3 n;
        //float2 uv;
    };

    //Triangle with indices.
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

    // Triangle with Vertices. Vertices are resolved already in registers
    struct TriangleV
    {
        Vertex a;
        Vertex b;
        Vertex c;

        Vertex loadVertex(ByteAddressBuffer vertBuffer, int index)
        {
            Vertex v;
            v.p = asfloat(vertBuffer.Load3((index * 3)  << 2));
            return v;
        }

        void load(ByteAddressBuffer vertices, in TriangleI indices)
        {
            a = loadVertex(vertices, indices.a);
            b = loadVertex(vertices, indices.b);
            c = loadVertex(vertices, indices.c);
        }
    };

    // Interpolation result with 3 baricenters. See TriangleH::interp
    struct TriInterpResult
    {
        bool isBackface;
        bool isFrontface;
        bool visible;
        float3 bari;

        float3 eval(float3 a, float3 b, float3 c)
        {
            return a * bari.x + b * bari.y + c * bari.z;
        }

        float eval(float a, float b, float c)
        {
            return a * bari.x + b * bari.y + c * bari.z;
        }
    };

    // Represents a 3d bounding box
    struct AABB
    {
        float3 begin;
        float3 end;

        float3 center()
        {
            return (begin + end) * 0.5;
        }

        float3 size()
        {
            return end - begin;
        }

        float3 extents()
        {
            return size() * 0.5;
        }

        bool intersects(AABB other)
        {
            return all(begin < other.end) && all(other.begin < end);
        }
    };

    // Represents a single transformed triangle in homogeneous coordinates
    struct TriangleH
    {
        // Homogeneous coordinates before perspective correction
        float4 h0;
        float4 h1;
        float4 h2;

        // Homogeneous screen coordinates after division by W
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

            float backFace = -max(wa, max(wb, wc));
            float frontFace = min(wa, min(wb, wc));

            TriInterpResult result;
            result.bari = computeBaryCoordPerspective(float3(p0.xy,h0.w), float3(p1.xy,h1.w), float3(p2.xy,h2.w), hCoords);
            result.isBackface = backFace > 0.0;
            result.isFrontface = frontFace > 0.0;
            result.visible = result.isBackface || result.isFrontface;
            return result;
        }

        AABB aabb()
        {
            AABB val;
            val.begin = min(p0, min(p1, p2));
            val.end = max(p0, max(p1, p2));
            return val;
        }
    };

    //-----------------------------
    // Implementations of functions
    //-----------------------------

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

    bool intersectsSATAxis(float3 aabbExtents, float3 axis, float3 v0, float3 v1, float3 v2)
    {
        // Compute the face normals of the AABB, because the AABB
        // is at center, and of course axis aligned, we know that 
        // it's normals are the X, Y and Z axis.
        const float3 u0 = float3(1.0f, 0.0f, 0.0f);
        const float3 u1 = float3(0.0f, 1.0f, 0.0f);
        const float3 u2 = float3(0.0f, 0.0f, 1.0f);

        // Testing axis: axis_u0_f0
        // Project all 3 vertices of the triangle onto the Seperating axis
        float p0 = dot(v0, axis);
        float p1 = dot(v1, axis);
        float p2 = dot(v2, axis);

        // Project the AABB onto the seperating axis
        // We don't care about the end points of the prjection
        // just the length of the half-size of the AABB
        // That is, we're only casting the extents onto the 
        // seperating axis, not the AABB center. We don't
        // need to cast the center, because we know that the
        // aabb is at origin compared to the triangle!
        float r = aabbExtents.x * abs(dot(u0, axis)) +
                    aabbExtents.y * abs(dot(u1, axis)) +
                    aabbExtents.z * abs(dot(u2, axis));

        // Now do the actual test, basically see if either of
        // the most extreme of the triangle points intersects r
        // You might need to write Min & Max functions that take 3 arguments
        if (max(-(max(p0, max(p1, p2))), min(p0, min(p1, p2))) > r) {
            // This means BOTH of the points of the projected triangle
            // are outside the projected half-length of the AABB
            // Therefore the axis is seperating and we can exit
            return false;
        }

        return true;
    }

    // Intersection between AABB and triangle using SAT algorithm.
    // Translated from https://gdbooks.gitbooks.io/3dcollisions/content/Chapter4/aabb-triangle.html to glsl
    bool intersectsSAT(in TriangleH tri, in AABB aabb)
    {
        // Get the triangle points as vectors
        float3 v0 = tri.p0;
        float3 v1 = tri.p1;
        float3 v2 = tri.p2;

        // Convert AABB to center-extents form
        float3 c = aabb.center();
        float3 e = aabb.extents();

        // Translate the triangle as conceptually moving the AABB to origin
        // This is the same as we did with the point in triangle test
        v0 -= c;
        v1 -= c;
        v2 -= c;

        // Compute the edge vectors of the triangle  (ABC)
        // That is, get the lines between the points as vectors
        float3 f0 = v1 - v0; // B - A
        float3 f1 = v2 - v1; // C - B
        float3 f2 = v0 - v2; // A - C

        // Compute the face normals of the AABB, because the AABB
        // is at center, and of course axis aligned, we know that 
        // it's normals are the X, Y and Z axis.
        float3 u0 = float3(1.0f, 0.0f, 0.0f);
        float3 u1 = float3(0.0f, 1.0f, 0.0f);
        float3 u2 = float3(0.0f, 0.0f, 1.0f);

        // There are a total of 13 axis to test!

        // We first test against 9 axis, these axis are given by
        // cross product combinations of the edges of the triangle
        // and the edges of the AABB. You need to get an axis testing
        // each of the 3 sides of the AABB against each of the 3 sides
        // of the triangle. The result is 9 axis of seperation
        // https://awwapp.com/b/umzoc8tiv/

        // Compute the 9 axis
        float3 axis_u0_f0 = cross(u0, f0);
        float3 axis_u0_f1 = cross(u0, f1);
        float3 axis_u0_f2 = cross(u0, f2);

        float3 axis_u1_f0 = cross(u1, f0);
        float3 axis_u1_f1 = cross(u1, f1);
        float3 axis_u1_f2 = cross(u2, f2);

        float3 axis_u2_f0 = cross(u2, f0);
        float3 axis_u2_f1 = cross(u2, f1);
        float3 axis_u2_f2 = cross(u2, f2);

        if (!intersectsSATAxis(e, axis_u0_f0, v0, v1, v2))
            return false;
        if (!intersectsSATAxis(e, axis_u0_f1, v0, v1, v2))
            return false;
        if (!intersectsSATAxis(e, axis_u0_f2, v0, v1, v2))
            return false;
        if (!intersectsSATAxis(e, axis_u1_f0, v0, v1, v2))
            return false;
        if (!intersectsSATAxis(e, axis_u1_f1, v0, v1, v2))
            return false;
        if (!intersectsSATAxis(e, axis_u1_f2, v0, v1, v2))
            return false;
        if (!intersectsSATAxis(e, axis_u2_f1, v0, v1, v2))
            return false;
        if (!intersectsSATAxis(e, axis_u2_f2, v0, v1, v2))
            return false;
        if (!intersectsSATAxis(e, axis_u2_f2, v0, v1, v2))
            return false;

        // Next, we have 3 face normals from the AABB
        // for these tests we are conceptually checking if the bounding box
        // of the triangle intersects the bounding box of the AABB
        // that is to say, the seperating axis for all tests are axis aligned:
        // axis1: (1, 0, 0), axis2: (0, 1, 0), axis3 (0, 0, 1)
        if (!aabb.intersects(tri.aabb()))
            return false;

        // Finally, we have one last axis to test, the face normal of the triangle
        // We can get the normal of the triangle by crossing the first two line segments
        float3 triangleNormal = cross(f0, f1);
        if (!intersectsSATAxis(e, triangleNormal, v0, v1, v2))
            return false;

        // Passed testing for all 13 seperating axis that exist!
        return true;
    }

    float2 pixelToUV(int2 pixelCoord, int2 screenSize)
    {
        float2 uv = (pixelCoord + 0.5) / (float2)screenSize.xy;
        return uv;
    }

    int2 uvToPixel(float2 uv, int2 screenSize)
    {
        return uv.xy * screenSize;
    }

    float2 uvToH(float2 uv)
    {
        return float2(1,1) * (uv * 2.0 - 1.0);
    }

    float2 hToUV(float2 hCoord)
    {
        float2 uv = (hCoord * float2(1,1)) * 0.5 + 0.5;
        return uv;
    }
}

#endif
