import coalpy.gpu as g
import numpy as np
import math
from . import gpugeo

g_brute_force_shader = g.Shader(file = "raster_cs.hlsl", name = "raster_brute_force", main_function = "csMainRasterBruteForce" )
g_bin_triangle_shader = g.Shader(file = "raster_cs.hlsl", name = "raster_bining", main_function = "csMainBinTriangles" )
g_bin_triangle_shader.resolve()

class Rasterizer:

    def __init__(self, w, h):
        self.m_max_w = 0
        self.m_max_h = 0
        self.update_view(w, h)
        return

    def update_view(self, w, h):
        if w <= self.m_max_w and h <= self.m_max_h:
            return
        self.m_visibility_buffer = g.Texture(
            name = "vis_buffer",
            format = g.Format.RGBA_8_UNORM,
            width = w, height = h)
        self.m_max_w = w
        self.m_max_h = w

    def rasterize_brute_force(
        self,
        cmd_list,
        t, w, h, view_matrix, proj_matrix,
        gpugeo : gpugeo.GpuGeo):
        batch_size = 128
        count_left = gpugeo.triCounts
        offset = 0
        counts = 0
        while offset < gpugeo.triCounts:
            batch_count = min(count_left, batch_size)
            cmd_list.dispatch(
                shader = g_brute_force_shader,
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
                outputs =  self.m_visibility_buffer)

            offset = offset + batch_count
            count_left = count_left - batch_count
            counts = counts + 1
    
    def bin_rasterize(
        cmd_list,
        t, w, h, view_matrix, proj_matrix,
        gpugeo : gpugeo.GpuGeo,
        texture : g.Texture):
        return

    @property
    def visibility_buffer(self):
        return self.m_visibility_buffer
