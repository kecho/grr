import coalpy.gpu as g
import numpy as np
import math
from . import gpugeo
from . import utilities
from . import prefix_sum

#enums, must match those in raster_cs.hlsl
class RasterizerFlags:
    RASTERIZER_FLAGS_OUTPUT_FINE_RASTER_COUNT = 1 << 0

g_fine_raster_shader = g.Shader(file = "raster_cs.hlsl", name = "raster_fine_tile", main_function = "csMainFineRaster", defines = ["FINE_RASTER"])
g_bin_triangle_shader = g.Shader(file = "raster_cs.hlsl", name = "raster_bining", main_function = "csMainBinTriangles" )
g_bin_elements_args_shader = g.Shader(file = "raster_cs.hlsl", name = "raster_elements_args", main_function = "csWriteBinElementArgsBuffer");
g_bin_elements_shader = g.Shader(file = "raster_cs.hlsl", name = "raster_elements", main_function = "csMainWriteBinElements");

class Rasterizer:

    # triangleId (4b), binOffset (4b), binId (4b). See raster_utils.hlsl
    bin_intersection_record_byte_size = (4 + 4 + 4) 

    # single uint buffer, with the triangle ID
    bin_element_size = 4 
    bin_record_buffer_byte_size = (256 * 1024 * 1024) 
    bin_record_buffer_element_count = math.ceil(bin_record_buffer_byte_size / (bin_intersection_record_byte_size + bin_element_size))

    #coarse tile size in pixels
    coarse_tile_size = (1 << 5)

    #coarse tile size in pixels
    fine_tile_size = (1 << 3)

    def __init__(self, w, h):
        self.m_max_w = 0
        self.m_max_h = 0
        self.m_total_tiles = 0 
        self.m_bin_offsets_buffer = None
        self.m_fine_tile_counter_buffer = None
        self.m_constant_buffer = None
        self.update_view(w, h)
        self.allocate_raster_resources()
        return

    def get_tile_size(self, w, h):
        return (math.ceil(w / Rasterizer.coarse_tile_size), math.ceil(h / Rasterizer.coarse_tile_size))

    def get_fine_tile_size(self, w, h):
        return (math.ceil(w / Rasterizer.fine_tile_size), math.ceil(h / Rasterizer.fine_tile_size))

    def rasterize(self, cmd_list, w, h, view_matrix, proj_matrix, geo, view_settings = None):

        cmd_list.begin_marker("rasterize")

        utilities.clear_texture(
            cmd_list, [0.0, 0.0, 0.0, 0.0],
            self.m_visibility_buffer, w, h)

        self.update_view(w, h)

        flags = 0
        if view_settings != None:
            flags |= RasterizerFlags.RASTERIZER_FLAGS_OUTPUT_FINE_RASTER_COUNT if view_settings.debug_fine_tiles else 0
        self.setup_constants(cmd_list, w, h, view_matrix, proj_matrix, int(geo.triCounts), flags)

        self.bin_tri_records(
            cmd_list, w, h, 
            view_matrix,
            proj_matrix,
            geo)

        self.generate_bin_list(
            cmd_list, w, h)

        self.dispatch_fine_raster(
            cmd_list,
            w, h,
            view_matrix,
            proj_matrix,
            geo)

        cmd_list.end_marker()
        

    def setup_constants(self, cmd_list, w, h, view_matrix, proj_matrix, triangle_counts, flags):

        cmd_list.begin_marker("setup_constants")
        tiles_w, tiles_h = self.get_tile_size(w, h)
        fine_tiles_w, fine_tiles_h = self.get_fine_tile_size(w, h)

        const= [
            float(w), float(h), 1.0/w, 1.0/h,
            int(w), int(h), int(triangle_counts), flags,
            float(tiles_w), float(tiles_h), float(fine_tiles_w), float(fine_tiles_h),
        ]
        const.extend(view_matrix.flatten().tolist())
        const.extend(proj_matrix.flatten().tolist())

        if self.m_constant_buffer is None:
            self.m_constant_buffer = g.Buffer(
                name = "ConstantBuffer", type=g.BufferType.Standard,
                format = g.Format.R32_FLOAT, element_count = len(const), is_constant_buffer = True)

    
        cmd_list.upload_resource( source = const, destination = self.m_constant_buffer)
        cmd_list.end_marker()

    def allocate_raster_resources(self):
        self.m_total_records_buffer = g.Buffer(
                name = "total_bins_buffer",
                type = g.BufferType.Standard,
                format = g.Format.R32_UINT,
                element_count = 1)

        self.m_bin_record_buffer = g.Buffer(
            name = "bin_record_buffer",
            type = g.BufferType.Structured,
            element_count = Rasterizer.bin_record_buffer_element_count,
            stride = Rasterizer.bin_intersection_record_byte_size)

        self.m_bin_element_buffer = g.Buffer(
            name = "bin_element_buffer",
            type = g.BufferType.Standard,
            format = g.Format.R32_UINT,
            element_count = Rasterizer.bin_record_buffer_element_count)

        self.m_bin_elements_args_buffer = g.Buffer(
            name = "bin_elements_arg_buffer",
            type = g.BufferType.Standard,
            format = g.Format.RGBA_32_UINT,
            element_count = 1)

    def update_view(self, w, h):
        if w <= self.m_max_w and h <= self.m_max_h:
            return

        self.m_visibility_buffer = g.Texture(
            name = "vis_buffer",
            format = g.Format.RGBA_8_UNORM,
            width = w, height = h)
            
        self.m_max_w = w
        self.m_max_h = h

        tiles_w, tiles_h = self.get_tile_size(w, h)

        self.m_total_tiles = tiles_w * tiles_h
        self.m_prefix_sum_bins_args = prefix_sum.allocate_args(self.m_total_tiles)

        self.m_bin_counter_buffer = g.Buffer(
            name = "bin_coarse_tiles_counter",
            type = g.BufferType.Standard,
            format = g.Format.R32_UINT,
            element_count = tiles_w * tiles_h)

        fine_tiles_w, fine_tiles_h = self.get_fine_tile_size(w, h)
        self.m_fine_tile_counter_buffer = g.Buffer(
            name = "fine_tile_counter",
            type = g.BufferType.Standard,
            format = g.Format.R32_UINT,
            element_count = fine_tiles_w * fine_tiles_h)

    def clear_counter_buffers(self, cmd_list, w, h):
        tiles_w, tiles_h = self.get_tile_size(w, h)
        utilities.clear_uint_buffer(cmd_list, 0, self.m_bin_counter_buffer, 0, tiles_w * tiles_h)
        utilities.clear_uint_buffer(cmd_list, 0, self.m_total_records_buffer, 0, 1)
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

        cmd_list.dispatch(
            shader = g_bin_triangle_shader,
            constants = self.m_constant_buffer,#const,  

            inputs = [
                gpugeo.m_vertex_buffer,
                gpugeo.m_index_buffer
            ],

            outputs = [
                self.m_total_records_buffer,
                self.m_bin_counter_buffer,
                self.m_bin_record_buffer
            ],

            x = math.ceil(gpugeo.triCounts / 64),
            y = 1,
            z = 1)
        cmd_list.end_marker()

    def generate_bin_list(self, cmd_list, w, h):

        tiles_w = math.ceil(w / Rasterizer.coarse_tile_size)
        tiles_h = math.ceil(h / Rasterizer.coarse_tile_size)

        cmd_list.begin_marker("generate_bin_list")

        cmd_list.dispatch(
            x = 1, y = 1, z = 1,
            shader = g_bin_elements_args_shader,
            inputs = self.m_total_records_buffer,
            outputs = self.m_bin_elements_args_buffer)

        self.m_bin_offsets_buffer = prefix_sum.run(cmd_list, self.m_bin_counter_buffer, self.m_prefix_sum_bins_args, is_exclusive = True, input_counts = tiles_w * tiles_h)

        cmd_list.dispatch(
            indirect_args = self.m_bin_elements_args_buffer,
            #x = 1, y = 1, z = 1,
            shader = g_bin_elements_shader,
            inputs = [self.m_total_records_buffer, self.m_bin_offsets_buffer, self.m_bin_record_buffer ],
            outputs = self.m_bin_element_buffer)

        cmd_list.end_marker()

    def dispatch_fine_raster(
        self,
        cmd_list,
        w, h, view_matrix, proj_matrix,
        gpugeo : gpugeo.GpuGeo):

        (fine_tiles_x, fine_tiles_y) = self.get_fine_tile_size(w, h)
        cmd_list.begin_marker("fine_raster")
        cmd_list.dispatch(
            shader = g_fine_raster_shader,
            constants = self.m_constant_buffer,#const,
            inputs = [
                gpugeo.m_vertex_buffer, 
                gpugeo.m_index_buffer,
                self.m_bin_counter_buffer,
                self.m_bin_offsets_buffer,
                self.m_bin_element_buffer],
            outputs = [
                self.m_visibility_buffer,
                self.m_fine_tile_counter_buffer ],
            x = fine_tiles_x,
            y = fine_tiles_y,
            z = 1)
        cmd_list.end_marker()

    @property
    def visibility_buffer(self):
        return self.m_visibility_buffer
