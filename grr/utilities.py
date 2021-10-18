import coalpy.gpu as g
import math
from . import get_module_path

clear_target_shader = g.Shader(file = "clear_target.hlsl", name = "clear", main_function = "main_clear" )


def clear_texture(cmd_list, color, texture, w, h):
    cmd_list.dispatch(
        shader = clear_target_shader,
        constants = color,
        x = math.ceil(w / 8), 
        y = math.ceil(h / 8), 
        z = 1,
        outputs = texture
    )
    
