#ifndef RASTER_UTIL_H
#define RASTER_UTIL_H

namespace raster
{
    //Size must match raster.py
    struct BinIntersectionRecord
    {
        int triangleId;
        int binOffset;
        int tileId;

        void init(int inTileId, int triId, int inBinOffset)
        {
            triangleId = triId;
            binOffset = inBinOffset;
            tileId = inTileId;
        }

        int3 getIndices()
        {
            int3 baseIdx = triangleId * 3;
            return baseIdx + int3(0, 1, 2);
        }
    };

}

#endif
