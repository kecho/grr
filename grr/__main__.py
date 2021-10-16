import coalpy.gpu as g
import numpy as np
import editor

active_editor = editor.Editor(None)
#hello world
def on_render(renderArgs : g.RenderArgs):
    active_editor.render_ui(renderArgs.imgui)
    #todo: lets do this
    return

w = g.Window(title="grr - gpu rasterizer and renderer for python. Kleber Garcia, 2021", on_render = on_render, width = 720, height = 480)
g.run()
