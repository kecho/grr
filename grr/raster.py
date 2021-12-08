import coalpy.gpu as g
import numpy as np
import math
from . import gpugeo
from . import utilities

g_brute_force_shader = g.Shader(file = "raster_cs.hlsl", name = "raster_brute_force", main_function = "csMainRasterBruteForce" )
g_bin_triangle_shader = g.Shader(file = "raster_cs.hlsl", name = "raster_bining", main_function = "csMainBinTriangles" )
g_bin_triangle_shader.resolve()

class Rasterizer:

    # triangleId (4b), binId (4b). See raster_utils.hlsl
    bin_intersection_record_byte_size = (4    +   4) 
    bin_record_buffer_byte_size = (16 * 1024 * 1024) 
    bin_record_buffer_element_count = math.ceil(bin_record_buffer_byte_size / bin_intersection_record_byte_size)

    #coarse tile size in pixels
    coarse_tile_size = 64 

    def __init__(self, w, h):
        self.m_max_w = 0
        self.m_max_h = 0
        self.update_view(w, h)
        self.allocate_raster_resources()
        return

    def allocate_raster_resources(self):
        self.m_total_bins_buffer = g.Buffer(
                name = "total_bins_buffer",
                type = g.BufferType.Standard,
                format = g.Format.R32_UINT,
                element_count = 1)

        self.m_bin_record_buffer = g.Buffer(
            name = "bin_record_buffer",
            type = g.BufferType.Structured,
            element_count = Rasterizer.bin_record_buffer_element_count,
            stride = Rasterizer.bin_intersection_record_byte_size)

    def update_view(self, w, h):
        if w <= self.m_max_w and h <= self.m_max_h:
            return

        self.m_visibility_buffer = g.Texture(
            name = "vis_buffer",
            format = g.Format.RGBA_8_UNORM,
            width = w, height = h)
            
        self.m_max_w = w
        self.m_max_h = h

        coarse_w = math.ceil(w / Rasterizer.coarse_tile_size)
        coarse_h = math.ceil(h / Rasterizer.coarse_tile_size)

        self.m_coarse_bin_tiles_counter_buffer = g.Buffer(
            name = "bin_coarse_tiles_counter",
            type = g.BufferType.Standard,
            format = g.Format.R32_UINT,
            element_count = coarse_w * coarse_h)

    def rasterize_brute_force(
        self,
        cmd_list,
        t, w, h, view_matrix, proj_matrix,
        gpugeo : gpugeo.GpuGeo):
        batch_size = 128
        count_left = gpugeo.triCounts
        offset = 0
        counts = 0
        const = []
        const.extend(view_matrix.flatten().tolist())
        const.extend(proj_matrix.flatten().tolist())
        while offset < gpugeo.triCounts:
            
            batch_count = min(count_left, batch_size)
            batch_const = const
            batch_const.extend([
                w, h, 1.0/w, 1.0/h,
                t, float(offset), float(batch_count), 0.0
            ])
            cmd_list.dispatch(
                shader = g_brute_force_shader,
                constants = batch_const,
                inputs = [gpugeo.m_vertex_buffer, gpugeo.m_index_buffer],
                outputs =  self.m_visibility_buffer,

                x = math.ceil(w / 8),
                y = math.ceil(w / 8),
                z = 1)

            offset = offset + batch_count
            count_left = count_left - batch_count
            counts = counts + 1
            #hack: avoid gpu hangs by over saturating the work queue
            if counts >= 20:
                break

    def clear_counter_buffers(self, cmd_list, w, h):
        tiles_w = math.ceil(w / Rasterizer.coarse_tile_size)
        tiles_h = math.ceil(h / Rasterizer.coarse_tile_size)
        utilities.clear_uint_buffer(cmd_list, 0, self.m_coarse_bin_tiles_counter_buffer, 0, tiles_w * tiles_h)
        utilities.clear_uint_buffer(cmd_list, 0, self.m_total_bins_buffer, 0, 1)
        return
    
    def bin_tri_records(
        self,
        cmd_list,
        w, h, view_matrix, proj_matrix,
        gpugeo : gpugeo.GpuGeo):

        cmd_list.begin_marker("raster_binning")
        self.clear_counter_buffers(cmd_list, w, h)

        tiles_w = math.ceil(w / Rasterizer.coarse_tile_size)
        tiles_h = math.ceil(h / Rasterizer.coarse_tile_size)

        const = [
            float(w), float(h), 1.0/float(w), 1.0/float(h),
            float(tiles_w), float(tiles_h), float(Rasterizer.coarse_tile_size), int(gpugeo.triCounts),
        ]
        const.extend(view_matrix.flatten().tolist())
        const.extend(proj_matrix.flatten().tolist())

        cmd_list.dispatch(
            shader = g_bin_triangle_shader,
            constants = const,  

            inputs = [
                gpugeo.m_vertex_buffer,
                gpugeo.m_index_buffer
            ],

            outputs = [
                self.m_total_bins_buffer,
                self.m_coarse_bin_tiles_counter_buffer,
                self.m_bin_record_buffer
            ],

            x = math.ceil(gpugeo.triCounts / 64),
            y = 1,
            z = 1)
        cmd_list.end_marker()

    @property
    def visibility_buffer(self):
        return self.m_visibility_buffer
