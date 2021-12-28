import numpy as np
import coalpy.gpu as g

from . import editor
from . import gpugeo
from . import utilities
from . import raster
from . import debug

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

initial_w = 720
initial_h = 480
geo = gpugeo.GpuGeo()
geo.create_simple_triangle()
rasterizer = raster.Rasterizer(initial_w, initial_h)
active_editor = editor.Editor(geo, None)
active_editor.load_editor_state()

def on_render(render_args : g.RenderArgs):
    cmd_list = g.CommandList()
    output_texture = render_args.window.display_texture
    w = render_args.width
    h = render_args.height
    if w == 0 or h == 0:
        return False

    active_editor.update_camera(w, h, render_args.delta_time, render_args.window)

    rasterizer.update_view(w, h)

    utilities.clear_texture(
        cmd_list, [0.0, 0.0, 0.0, 0.0],
        rasterizer.visibility_buffer, w, h)

    rasterizer.bin_tri_records(
        cmd_list, w, h, 
        active_editor.camera.view_matrix,
        active_editor.camera.proj_matrix,
        geo)

    rasterizer.generate_bin_list(
        cmd_list, w, h)

    #rasterizer.rasterize_brute_force(
    rasterizer.rasterize(
        cmd_list,
        render_args.render_time, w, h,
        active_editor.camera.view_matrix,
        active_editor.camera.proj_matrix,
        geo)

    debug.debug_visibility_buffer(
        cmd_list,
        rasterizer, output_texture, w, h)

    active_editor.render_ui(render_args.imgui)
    g.schedule(cmd_list)
    return

w = g.Window(
    title="GRR - gpu rasterizer and renderer for python. Kleber Garcia, 2021",
    on_render = on_render,
    width = 720, height = 480)

g.run()
active_editor.save_editor_state()
