
#define GROUP_SIZE 128

Buffer<uint> g_inputBuffer : register(t0);
RWBuffer<uint> g_outputBuffer : register(u0);

cbuffer ConstantsPrefixSum : register(b0)
{
    int4 g_bufferArgs0;
}

#define inputCount g_bufferArgs0.x
#define inputOffset g_bufferArgs0.y
#define outputOffset g_bufferArgs0.z
#define parentOffset g_bufferArgs0.w

groupshared uint gs_prefixCache[GROUP_SIZE];

[numthreads(GROUP_SIZE, 1, 1)]
void csMainPrefixSumGroup(int3 dispatchThreadID : SV_DispatchThreadID, int groupIndex : SV_GroupIndex)
{
    int threadID = dispatchThreadID.x;
    gs_prefixCache[groupIndex] = threadID >= inputCount ? 0u : g_inputBuffer[threadID + inputOffset];

    GroupMemoryBarrierWithGroupSync();
    
    //Hillis Steele Scan
    for (int i = 1; i < GROUP_SIZE; i <<= 1)
    {
        uint val = groupIndex >= i ? gs_prefixCache[groupIndex - i] : 0u;
        GroupMemoryBarrierWithGroupSync();

        gs_prefixCache[groupIndex] += val;

        GroupMemoryBarrierWithGroupSync();
    }

    g_outputBuffer[threadID + outputOffset] = gs_prefixCache[groupIndex];
}

[numthreads(GROUP_SIZE, 1, 1)]
void csMainPrepareNextInput(int3 dispatchThreadID : SV_DispatchThreadID, int3 groupID : SV_GroupID)
{
    g_outputBuffer[dispatchThreadID.x] = g_inputBuffer[inputOffset + groupID.x * GROUP_SIZE + GROUP_SIZE - 1];
}

groupshared uint g_parentSum;

[numthreads(GROUP_SIZE, 1, 1)]
void csMainPrefixResolveGroup(int3 dispatchThreadID : SV_DispatchThreadID, int groupIndex : SV_GroupIndex, int3 groupID : SV_GroupID)
{
    if (groupIndex == 0)
        g_parentSum = groupID.x == 0 ? 0 : g_outputBuffer[parentOffset + groupID.x - 1];

    GroupMemoryBarrierWithGroupSync();

    g_outputBuffer[outputOffset + dispatchThreadID.x] += g_parentSum;
}
