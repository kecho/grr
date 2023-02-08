#ifndef __DEPTH_UTILS__
#define __DEPTH_UTILS__

#define MAX_DEPTH 1.0
#define MIN_DEPTH 0.0
#define InterlockedMaxDepth(a,b,c) InterlockedMax(a,b,c)
#define InterlockedMinDepth(a,b,c) InterlockedMin(a,b,c)
#define IsDepthLess(a,b) a < b
#define IsDepthLessOrEqual(a,b) a <= b
#define IsDepthGreater(a,b) a > b
#define IsDepthGreaterOrEqual(a,b) a >= b

#endif
