import coalpy.gpu as g
import numpy as np
import math
from . import gpugeo

raster_shader = g.Shader(file = "raster.hlsl", name = "raster", main_function = "csMainRaster" )

def rasterize(
    cmd_list,
    t, w, h, view_matrix, proj_matrix,
    gpugeo : gpugeo.GpuGeo,
    texture : g.Texture):

    batch_size = 128
    count_left = gpugeo.triCounts
    offset = 0
    counts = 0
    while offset < gpugeo.triCounts:
        batch_count = min(count_left, batch_size)
        cmd_list.dispatch(
            shader = raster_shader,
            constants = np.array([
                view_matrix[0, 0:4],
                view_matrix[1, 0:4],
                view_matrix[2, 0:4],
                view_matrix[3, 0:4],
                proj_matrix[0, 0:4],
                proj_matrix[1, 0:4],
                proj_matrix[2, 0:4],
                proj_matrix[3, 0:4],
                [w, h, 1.0/w, 1.0/h],
                [t, float(offset), float(batch_count), 0.0]
            ], dtype='f'),
            x = math.ceil(w / 8),
            y = math.ceil(w / 8),
            z = 1,
            inputs = [gpugeo.m_vertex_buffer, gpugeo.m_index_buffer],
            outputs = texture 
        )
        offset = offset + batch_count
        count_left = count_left - batch_count
        counts = counts + 1
