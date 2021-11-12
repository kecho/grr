import coalpy.gpu as g
import math

g_debug_vis_shader = g.Shader(file = "debug_cs.hlsl", name = "debug_visibility", main_function = "csMainDebugVis")

def debug_visibility_buffer(cmd_list, visibility_buffer, output_texture, w, h):
    cmd_list.dispatch(
        shader = g_debug_vis_shader,
        constants = [w, h, 0, 0],
        inputs = visibility_buffer,
        outputs = output_texture,
        x = math.ceil(w / 8),
        y = math.ceil(h / 8),
        z = 1)
    
