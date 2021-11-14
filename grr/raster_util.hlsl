#ifndef RASTER_UTIL_H
#define RASTER_UTIL_H

namespace raster
{

    //Size must match raster.py
    struct BinIntersectionRecord
    {
        int triangleId;
        int binId;

        int2 getCoord()
        {
            return int2(binId & 0xffff, binId >> 16);
        }

        void setCoord(int2 coord)
        {
            binId = (coord.x & 0xffff) | (coord.y << 16);
        }

        int3 getIndices()
        {
            int3 baseIdx = triangleId * 3;
            return baseIdx + int3(0, 1, 2);
        }
    };

}

#endif
