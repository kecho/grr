
#define GROUP_SIZE 64

Buffer<uint> g_inputBuffer : register(t0);
RWBuffer<uint> g_outputPrefixBuffer : register(u0);

cbuffer ConstantsPrefixSum : register(b0)
{
    int4 g_BufferCounts;
}

groupshared uint gs_prefixCache[GROUP_SIZE];

[numthreads(GROUP_SIZE, 1, 1)]
void csMainPrefixSumGroup(int3 dispatchThreadID : SV_DispatchThreadID, int groupIndex : SV_GroupIndex)
{
    int threadID = groupIndex;
    gs_prefixCache[threadID] = threadID >= g_BufferCounts.x ? 0u : g_inputBuffer[threadID];

    GroupMemoryBarrierWithGroupSync();
    
    //Hillis Steele Scan
    for (int i = 1; i < (GROUP_SIZE >> 1); i <<= 1)
    {
        uint val = threadID >= i ? gs_prefixCache[threadID - i] : 0u;
        GroupMemoryBarrierWithGroupSync();

        gs_prefixCache[threadID] += val;

        GroupMemoryBarrierWithGroupSync();
    }

    g_outputPrefixBuffer[dispatchThreadID.x] = gs_prefixCache[threadID];
}
