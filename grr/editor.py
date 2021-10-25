import coalpy.gpu as g
import sys
import pathlib
import pywavefront
from . import gpugeo
from . import default_scenes as scenes
from . import get_module_path
from . import camera as c
from . import vec

class Editor:

    def __init__(self, geo : gpugeo.GpuGeo, default_scene : str):
        self.m_active_scene_name = None
        self.m_active_scene = None
        self.m_geo = geo
        self.m_active_scene = default_scene
        self.m_editor_camera = c.Camera(1920, 1080)

        #input state
        self.m_right_pressed = False
        self.m_left_pressed = False
        self.m_top_pressed = False
        self.m_bottom_pressed = False
        self.m_can_move_pressed = False
        self.m_last_mouse = (0.0, 0.0)

        #camera settings
        self.m_cam_move_speed = 0.1

        self.reload_scene()

    def render_menu_bar(self, imgui : g.ImguiBuilder):
        if (imgui.begin_main_menu_bar()):
            if (imgui.begin_menu("File")):
                if (imgui.begin_menu("Open")):
                    if (imgui.begin_menu("Default Scenes")):
                        menu_results = [(imgui.menu_item(nm), nm) for nm in scenes.data.keys()]
                        valid_results = [nm for (is_selected, nm) in menu_results if is_selected == True]
                        if valid_results:
                            self.m_active_scene_name = get_module_path() + scenes.data[valid_results[0]]
                            self.reload_scene()
                        imgui.end_menu()
                    imgui.end_menu()
                imgui.end_menu()
            imgui.end_main_menu_bar()

    @property
    def camera(self):
        return self.m_editor_camera

    def _update_inputs(self, input_states):
        self.m_right_pressed = input_states.get_key_state(g.Keys.D) 
        self.m_left_pressed = input_states.get_key_state(g.Keys.A)
        self.m_top_pressed = input_states.get_key_state(g.Keys.W)
        self.m_bottom_pressed = input_states.get_key_state(g.Keys.S)
        #if (self.m_right_pressed):
        #    print("RIGHT")
        #if (self.m_left_pressed):
        #    print("LEFT")
        #if (self.m_top_pressed):
        #    print("TOP")
        #if (self.m_bottom_pressed):
        #    print("BOTTOM")
        prev_mouse = self.m_can_move_pressed
        self.m_can_move_pressed = True 
        if prev_mouse == False and self.m_can_move_pressed:
            m = input_states.get_mouse_position()
            self.last_mouse = (m[2], m[3])

    def update_camera(self, w, h, delta_time, input_states):
        self.m_editor_camera.w = w
        self.m_editor_camera.h = h
        self._update_inputs(input_states)
        if (self.m_can_move_pressed):
            cam_t = self.m_editor_camera.transform
            new_pos = self.m_editor_camera.pos
            zero = vec.float3(0, 0, 0)
            new_pos = new_pos + ((cam_t.right * self.m_cam_move_speed) if self.m_right_pressed  else zero)
            new_pos = new_pos - ((cam_t.right * self.m_cam_move_speed) if self.m_left_pressed   else zero)
            new_pos = new_pos + ((cam_t.front * self.m_cam_move_speed   ) if self.m_top_pressed    else zero)
            new_pos = new_pos - ((cam_t.front * self.m_cam_move_speed   ) if self.m_bottom_pressed else zero)
            self.m_editor_camera.pos = new_pos

    def render_ui(self, imgui : g.ImguiBuilder):
        self.render_menu_bar(imgui)

    def reload_scene(self):
        if self.m_active_scene_name == None:
            return
        print ("[Editor]: loading scene: "+'"'+self.m_active_scene_name+"'")
        try:
            self.m_active_scene = pywavefront.Wavefront(file_name= self.m_active_scene_name, create_materials=True, collect_faces=True)        
        except Exception as err:
            print ("[Editor]: failed parsing scene, reason: " + str(err))

        
 
