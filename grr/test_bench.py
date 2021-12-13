import coalpy.gpu as g
import numpy as np
import math
import functools
from . import bin_queues

def prefix_sum(input_data):
    accum = 0
    output = []
    for i in range(0, len(input_data), 1):
        accum += input_data[i]
        output.append(accum)
    return output

def test_cluster_gen():
    buffersz = 5348
    input_data = np.array([1 for _ in range(0, buffersz, 1)], dtype='i')
    test_input_buffer = g.Buffer(format = g.Format.R32_UINT, element_count = buffersz)

    reduction_buffers = bin_queues.allocate_queue_buffers_args(buffersz)

    cmd_list = g.CommandList()
    cmd_list.upload_resource(source = input_data, destination = test_input_buffer)
    bin_queues.cluster_gen_queue_offsets(cmd_list, test_input_buffer, reduction_buffers)

    g.schedule(cmd_list)

    output = reduction_buffers[1]
    dr = g.ResourceDownloadRequest(resource = output)
    dr.resolve()

    result = np.frombuffer(dr.data_as_bytearray(), dtype='i')
    result = np.resize(result, buffersz)
    expected = prefix_sum(input_data)
    correct_count = functools.reduce(lambda x, y: x + y, [1 if x == y else 0 for (x, y) in zip(result, expected)])
    return True if correct_count == len(input_data) else False

def run_test(nm, fn):
    result = fn()
    print(nm + " : " + ("PASS" if result else "FAIL"))

if __name__ == "__main__":
    run_test("test_cluster_gen_prefix_sum", test_cluster_gen)

