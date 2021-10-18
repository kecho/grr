import numpy as np
import coalpy.gpu as g

from . import editor
from . import gpugeo
from . import utilities

geo = gpugeo.GpuGeo()
geo.create_simple_triangle()
active_editor = editor.Editor(3, None)

#hello world
def on_render(render_args : g.RenderArgs):
    cmd_list = g.CommandList()

    utilities.clear_texture(
        cmd_list, [0.0, 0.0, 0.0, 0.0],
        render_args.window.display_texture, render_args.width, render_args.height)

    active_editor.render_ui(render_args.imgui)
    g.schedule([cmd_list])

    return

w = g.Window(
    title="grr - gpu rasterizer and renderer for python. Kleber Garcia, 2021",
    on_render = on_render,
    width = 720, height = 480)

g.run()
