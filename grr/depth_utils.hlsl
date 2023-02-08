#ifndef __DEPTH_UTILS__
#define __DEPTH_UTILS__

#ifndef INVERTED_DEPTH
#define INVERTED_DEPTH 1
#endif

#if INVERTED_DEPTH

#define MAX_DEPTH 0.0
#define MIN_DEPTH 1.0
#define InterlockedMaxDepth(a,b,c) InterlockedMin(a,b,c)
#define InterlockedMinDepth(a,b,c) InterlockedMax(a,b,c)
#define IsDepthLess(a,b) a > b
#define IsDepthLessOrEqual(a,b) a >= b
#define IsDepthGreater(a,b) a < b
#define IsDepthGreaterOrEqual(a,b) a <= b

#else

#define MAX_DEPTH 1.0
#define MIN_DEPTH 0.0
#define InterlockedMaxDepth(a,b,c) InterlockedMax(a,b,c)
#define InterlockedMinDepth(a,b,c) InterlockedMin(a,b,c)
#define IsDepthLess(a,b) a < b
#define IsDepthLessOrEqual(a,b) a <= b
#define IsDepthGreater(a,b) a > b
#define IsDepthGreaterOrEqual(a,b) a >= b

#endif

#endif
