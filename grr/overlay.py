import coalpy.gpu as g
import math
from . import raster
from . import debug_font

#enums, must match those in debug_cs.hlsl
class OverlayFlags:
    NONE = 0
    SHOW_COARSE_TILES = 1 << 0
    SHOW_FINE_TILES = 1 << 1

#font stuff
g_overlay_shader = g.Shader(file = "overlay_cs.hlsl", name = "main_overlay", main_function = "csMainOverlay")

def render_overlay(cmd_list, rasterizer, output_texture, view_settings):
    w = view_settings.width
    h = view_settings.height
    cmd_list.begin_marker("overlay")
    tile_x = math.ceil(w / raster.Rasterizer.coarse_tile_size)
    tile_y = math.ceil(h / raster.Rasterizer.coarse_tile_size)
    overlay_flags = OverlayFlags.NONE
    if view_settings.debug_coarse_tiles:
        overlay_flags |= OverlayFlags.SHOW_COARSE_TILES
    if view_settings.debug_fine_tiles:
        overlay_flags |= OverlayFlags.SHOW_FINE_TILES

    cmd_list.dispatch(
        shader = g_overlay_shader,
        constants = [
            int(w), int(h), 0, 0,
            float(tile_x), float(tile_y), int(raster.Rasterizer.coarse_tile_size), int(overlay_flags)
        ],

        inputs = [
            debug_font.font_texture,
            rasterizer.visibility_buffer,
            rasterizer.m_total_records_buffer,
            rasterizer.m_bin_counter_buffer,
            rasterizer.m_bin_offsets_buffer,
            rasterizer.m_bin_record_buffer,
            rasterizer.m_fine_tile_counter_buffer],

        samplers = debug_font.font_sampler,

        outputs = output_texture,
        x = math.ceil(w / 8),
        y = math.ceil(h / 8),
        z = 1)
    cmd_list.end_marker()
    
