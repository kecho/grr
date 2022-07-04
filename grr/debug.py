import coalpy.gpu as g
import math
from . import raster

#enums, must match those in debug_cs.hlsl
class OverlayFlags:
    NONE = 0
    SHOW_COARSE_TILES = 1 << 0
    SHOW_FINE_TILES = 1 << 1

#font stuff
g_font_sampler = g.Sampler(filter_type = g.FilterType.Linear)
g_debug_vis_shader = g.Shader(file = "debug_cs.hlsl", name = "debug_visibility", main_function = "csMainDebugVis")
g_debug_font_texture = g.Texture(file = "data/debug_font.jpg")

def debug_overlay(cmd_list, rasterizer, output_texture, view_settings):
    w = view_settings.width
    h = view_settings.height
    cmd_list.begin_marker("debug_visibility")
    tile_x = math.ceil(w / raster.Rasterizer.coarse_tile_size)
    tile_y = math.ceil(h / raster.Rasterizer.coarse_tile_size)
    overlay_flags = OverlayFlags.NONE
    if view_settings.debug_coarse_tiles:
        overlay_flags |= OverlayFlags.SHOW_COARSE_TILES

    cmd_list.dispatch(
        shader = g_debug_vis_shader,
        constants = [
            int(w), int(h), 0, 0,
            float(tile_x), float(tile_y), int(raster.Rasterizer.coarse_tile_size), int(overlay_flags)
        ],

        inputs = [
            g_debug_font_texture,
            rasterizer.visibility_buffer,
            rasterizer.m_total_records_buffer,
            rasterizer.m_bin_counter_buffer,
            rasterizer.m_bin_offsets_buffer,
            rasterizer.m_bin_record_buffer],

        samplers = g_font_sampler,

        outputs = output_texture,
        x = math.ceil(w / 8),
        y = math.ceil(h / 8),
        z = 1)
    cmd_list.end_marker()
    
