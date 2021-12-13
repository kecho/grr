import coalpy.gpu as g
from . import utilities as utils

g_reduction_group_size = 128
g_cluster_gen_queue_shader = g.Shader(file = "cluster_queue_gen_cs.hlsl", main_function = "csMainPrefixSumGroup")
g_cluster_gen_prep_next_shader = g.Shader(file = "cluster_queue_gen_cs.hlsl", main_function = "csMainPrepareNextInput")
g_cluster_gen_resolve = g.Shader(file = "cluster_queue_gen_cs.hlsl", main_function = "csMainPrefixResolveGroup")

def allocate_queue_buffers_args(max_bin_tile_count):
    aligned_bin_count = utils.alignup(max_bin_tile_count, g_reduction_group_size)
    reduction_count = 0
    c = max_bin_tile_count
    perform_reduction = True
    while perform_reduction:
        reduction_count += utils.alignup(c, g_reduction_group_size)
        c = utils.divup(c, g_reduction_group_size)
        perform_reduction = c > 1

    return (g.Buffer(name = "reductionBufferInput", element_count = aligned_bin_count, format = g.Format.R32_UINT),
            g.Buffer(name = "reductionBufferOutput", element_count = reduction_count, format = g.Format.R32_UINT),
            max_bin_tile_count)

def cluster_gen_queue_offsets(cmd_list, input_buffer, queue_buffers_args):
    reduction_buffer_in = queue_buffers_args[0]
    reduction_buffer_out = queue_buffers_args[1]
    tile_count = queue_buffers_args[2]
    group_count = tile_count
    perform_reduction = tile_count > 0 
    iteration = 0
    input_count = 0
    input_offset = 0
    output_offset = 0
    pass_list = []
    while perform_reduction:
        input_count = group_count
        group_count = utils.divup(group_count, g_reduction_group_size)
        pass_list.append((input_count, output_offset))

        cmd_list.dispatch(
            x = group_count, y = 1, z = 1,
            shader = g_cluster_gen_queue_shader,           
            inputs = input_buffer if iteration == 0 else reduction_buffer_in,
            outputs = reduction_buffer_out,
            constants = [input_count, 0, output_offset, 0])

        perform_reduction = group_count > 1
        if perform_reduction:
            next_group_count = utils.divup(group_count, g_reduction_group_size)
            cmd_list.dispatch(
                x = next_group_count, y = 1, z = 1,
                shader = g_cluster_gen_prep_next_shader,
                inputs = reduction_buffer_out,
                outputs = reduction_buffer_in,
                constants = [0, output_offset, 0, 0])

        iteration += 1
        output_offset += utils.alignup(input_count, g_reduction_group_size)

    for i in range(1, len(pass_list)):
        idx = len(pass_list) - 1 - i
        (parent_count, parent_offset) = pass_list[idx + 1]
        (count, offset) = pass_list[idx]
        cmd_list.dispatch(
            x = utils.divup(count, g_reduction_group_size), y = 1, z = 1,
            shader = g_cluster_gen_resolve,
            outputs = reduction_buffer_out,
            constants = [0, 0, offset, parent_offset])
