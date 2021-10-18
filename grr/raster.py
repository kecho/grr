import coalpy.gpu as g
import math
from . import gpugeo

raster_shader = g.Shader(file = "raster.hlsl", name = "raster", main_function = "csMainRaster" )

def rasterize(cmd_list, gpugeo : gpugeo.GpuGeo, texture : g.Texture, w, h, t):
    cmd_list.dispatch(
        shader = raster_shader,
        constants = [
            float(w), float(h), 1.0/float(w), 1.0/float(h),
            float(t), 0.0, 0.0, 0.0
        ],
        x = math.ceil(w / 8),
        y = math.ceil(w / 8),
        z = 1,
        inputs = [gpugeo.m_vertex_buffer, gpugeo.m_index_buffer],
        outputs = texture 
    )
