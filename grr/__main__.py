import numpy as np
import coalpy.gpu as g

from . import editor
from . import gpugeo
from . import utilities
from . import raster
from . import overlay

info = g.get_current_adapter_info()
print("""
+--------------------------------+
{  ____________________________  } 
{ /  _____/\______   \______   \ }   
{/   \  ___ |       _/|       _/ } 
{\    \_\  \|    |   \|    |   \ } 
{ \______  /|____|_  /|____|_  / } 
{        \/        \/        \/  } 
+--------------------------------+
{  Gpu Renderer and Rasterizer   } 
{  Kleber Garcia (c) 2021        }
{  v 0.1                         }
+--------------------------------+
""")
print("device: {}".format(info[1]))
initial_w = 1600 
initial_h = 900
geo = gpugeo.GpuGeo()
geo.create_simple_triangle()
rasterizer = raster.Rasterizer(initial_w, initial_h)
active_editor = editor.Editor(geo, None)
active_editor.load_editor_state()

def on_render(render_args : g.RenderArgs):
    output_texture = render_args.window.display_texture
    if render_args.width == 0 or render_args.height == 0:
        return False

    active_editor.build_ui(render_args.imgui, render_args.implot)
    viewports = active_editor.viewports
    active_editor.profiler.begin_capture()
    active_editor.render_tools()
    for vp in viewports:
        cmd_list = g.CommandList()
        w = vp.width
        h = vp.height
        if w == 0 or h == 0 or vp.texture == None:
            continue

        vp.update(render_args.delta_time)

        utilities.clear_texture(
            cmd_list, [0.0, 0.0, 0.0, 0.0],
            rasterizer.visibility_buffer, w, h)

        rasterizer.rasterize(
            cmd_list,
            w, h,
            vp.camera.view_matrix,
            vp.camera.proj_matrix,
            geo,
            vp)

        overlay.render_overlay(
            cmd_list,
            rasterizer, vp.texture, vp)

        g.schedule(cmd_list)
    active_editor.profiler.end_capture()

    return

w = g.Window(
    title="GRR - gpu rasterizer and renderer for python. Kleber Garcia, 2021",
    on_render = on_render,
    width = initial_w, height = initial_h)

g.run()
active_editor.save_editor_state()
w = None
