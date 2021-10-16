import coalpy.gpu as g
import default_scenes as scenes
import sys
import pathlib
import os

g_module_path = os.path.dirname(pathlib.Path(sys.modules[__name__].__file__)) + "\\"

class Editor:
    m_active_scene = None

    def __init__(self, default_scene):
        m_active_scene = default_scene
        self.reload_scene()

    def render_menu_bar(self, imgui : g.ImguiBuilder):
        if (imgui.begin_main_menu_bar()):
            if (imgui.begin_menu("File")):
                if (imgui.begin_menu("Open")):
                    if (imgui.begin_menu("Default Scenes")):
                        menu_results = [(imgui.menu_item(nm), nm) for nm in scenes.data.keys()]
                        valid_results = [nm for (is_selected, nm) in menu_results if is_selected == True]
                        if valid_results:
                            self.m_active_scene = g_module_path + scenes.data[valid_results[0]]
                            self.reload_scene()
                        imgui.end_menu()

                    imgui.end_menu()
                imgui.end_menu()
            imgui.end_main_menu_bar()

    def render_ui(self, imgui : g.ImguiBuilder):
        self.render_menu_bar(imgui)

    def reload_scene(self):
        if self.m_active_scene == None:
            return
        print ("[Editor]: loading scene: "+'"'+self.m_active_scene+"'")
        
