import coalpy.gpu as g
import numpy as np
import math
import functools

g_cluster_gen_queue_shader = g.Shader(file = "cluster_queue_gen_cs.hlsl", main_function = "csMainPrefixSumGroup")

def prefix_sum(input_data):
    accum = 0
    output = []
    for i in range(0, len(input_data), 1):
        accum += input_data[i]
        output.append(accum)

    return output
        

def test_cluster_gen():
    input_data = np.array([1,2,3,4,5,6], dtype='i')
    input_buffer = g.Buffer(name="input_test", type = g.BufferType.Standard, format = g.Format.R32_UINT, element_count = len(input_data))
    output_buffer = g.Buffer(name="output_test", type = g.BufferType.Standard, format = g.Format.R32_UINT, element_count = len(input_data))

    cmd_list = g.CommandList()
    cmd_list.upload_resource(source = input_data, destination = input_buffer)
    cmd_list.dispatch(
        x = math.ceil(len(input_data)/64), y = 1, z = 1,
        constants = [len(input_data), 0, 0, 0 ],
        shader = g_cluster_gen_queue_shader,
        inputs = input_buffer,
        outputs = output_buffer)

    g.schedule(cmd_list)

    dr = g.ResourceDownloadRequest(resource = output_buffer)
    dr.resolve()

    result = np.frombuffer(dr.data_as_bytearray(), dtype='i')
    expected = prefix_sum(input_data)
    correct_count = functools.reduce(lambda x, y: x + y, [1 if x == y else 0 for (x, y) in zip(result, expected)])
    return True if correct_count == len(input_data) else False


def run_test(nm, fn):
    result = fn()
    print(nm + " : " + ("PASS" if result else "FAIL"))

if __name__ == "__main__":
    run_test("test_cluster_gen_prefix_sum", test_cluster_gen)

