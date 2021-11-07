import numpy as np
import coalpy.gpu as g

from . import editor
from . import gpugeo
from . import utilities
from . import raster

info = g.get_current_adapter_info()
print("Current device: {}".format(info[1]))

geo = gpugeo.GpuGeo()
geo.create_simple_triangle()
active_editor = editor.Editor(geo, None)

#hello world
def on_render(render_args : g.RenderArgs):
    cmd_list = g.CommandList()
    output_texture = render_args.window.display_texture
    w = render_args.width
    h = render_args.height
    active_editor.update_camera(w, h, render_args.delta_time, render_args.window)

    utilities.clear_texture(
        cmd_list, [0.0, 0.0, 0.0, 0.0],
        output_texture, w, h)

    raster.rasterize(
        cmd_list,
        render_args.render_time, w, h,
        active_editor.camera.view_matrix,
        active_editor.camera.proj_matrix,
        geo,
        output_texture)

    active_editor.render_ui(render_args.imgui)
    g.schedule([cmd_list])

    return

w = g.Window(
    title="GRR - gpu rasterizer and renderer for python. Kleber Garcia, 2021",
    on_render = on_render,
    width = 720, height = 480)

g.run()
