import coalpy.gpu as g
import numpy as np
import math
import functools
from . import prefix_sum as gpu_prefix_sum

def prefix_sum(input_data, is_exclusive = False):
    accum = 0
    output = []
    for i in range(0, len(input_data), 1):
        if is_exclusive:
            output.append(accum)
            accum += input_data[i]
        else:
            accum += input_data[i]
            output.append(accum)
    return output

def test_cluster_gen(is_exclusive = False):
    buffersz = 8529
    input_data = np.array([x  for x in range(0, buffersz, 1)], dtype='i')
    test_input_buffer = g.Buffer(format = g.Format.R32_UINT, element_count = buffersz)

    reduction_buffers = gpu_prefix_sum.allocate_args(buffersz)

    cmd_list = g.CommandList()
    cmd_list.upload_resource(source = input_data, destination = test_input_buffer)
    output = gpu_prefix_sum.run(cmd_list, test_input_buffer, reduction_buffers, is_exclusive)

    g.schedule(cmd_list)

    dr = g.ResourceDownloadRequest(resource = output)
    dr.resolve()

    result = np.frombuffer(dr.data_as_bytearray(), dtype='i')
    result = np.resize(result, buffersz)
    expected = prefix_sum(input_data, is_exclusive)
    correct_count = functools.reduce(lambda x, y: x + y, [1 if x == y else 0 for (x, y) in zip(result, expected)])
    return True if correct_count == len(input_data) else False

def run_test(nm, fn):
    result = fn()
    print(nm + " : " + ("PASS" if result else "FAIL"))

def test_cluster_gen_inclusive():
    return test_cluster_gen(is_exclusive = False)

def test_cluster_gen_exclusive():
    return test_cluster_gen(is_exclusive = True)

if __name__ == "__main__":
    run_test("test prefix sum inclusive", test_cluster_gen_inclusive)
    run_test("test prefix sum exclusive", test_cluster_gen_exclusive)

