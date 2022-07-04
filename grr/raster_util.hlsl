#ifndef RASTER_UTIL_H
#define RASTER_UTIL_H

#define COARSE_TILE_POW 5
#define COARSE_TILE_SIZE (1 << (COARSE_TILE_POW))

#define FINE_TILE_POW 3 
#define FINE_TILE_SIZE (1 << FINE_TILE_POW)

#define FINE_TILE_TO_TILE_SHIFT (COARSE_TILE_POW - FINE_TILE_POW)

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
