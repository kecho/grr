import coalpy.gpu as g
import numpy as np
import os.path
import sys
import pathlib
import pywavefront
import json
from . import gpugeo
from . import default_scenes as scenes
from . import get_module_path
from . import camera as c
from . import vec

class EditorPanel:
    def __init__(self, name, state):
        self.name = name
        self.state = state

class EditorViewport:

    def __init__(self, id):
        self.m_name = "Viewport " + str(id)
        self.m_texture = None
        self.m_width = 1920
        self.m_height = 1080
        self.m_active = True
        self.m_is_focused = False
        self.m_id = id

    def build_ui(self, imgui: g.ImguiBuilder):
        self.m_active = imgui.begin(self.m_name, self.m_active)
        (cr_min_w, cr_min_h) = imgui.get_window_content_region_min()
        (cr_max_w, cr_max_h) = imgui.get_window_content_region_max()
        (nw, nh) = (int(cr_max_w - cr_min_w), int(cr_max_h - cr_min_h))
        self.m_is_focused = imgui.is_window_focused(flags = g.ImGuiFocusedFlags.RootWindow)
        if (self.m_active):
            #update viewport texture
            if (nw > 0 and nh > 0 and (self.m_texture == None or self.m_width != nw or self.m_height != nh)):
                self.m_width = nw;
                self.m_height = nh;
                self.m_texture = g.Texture(
                    name = self.m_name, width = self.m_width, height = self.m_height,
                    format = g.Format.RGBA_8_UNORM)

            if (self.m_texture != None):
                imgui.image(
                    texture = self.m_texture,
                    size = (self.m_width, self.m_height))
        imgui.end() 
        return self.m_active

    @property
    def width(self):
        return self.m_width

    @property
    def height(self):
        return self.m_height
    
    @property
    def texture(self):
        return self.m_texture

    @property
    def id(self):
        return self.m_id

    @property
    def name(self):
        return self.m_name

    @property
    def is_focused(self):
        return self.m_is_focused
    

class Editor:
    
    def __init__(self, geo : gpugeo.GpuGeo, default_scene : str):
        #editor state
        self.m_active_scene_name = None
        self.m_active_scene = None
        self.m_geo = geo
        self.m_active_scene = default_scene
        self.m_editor_camera = c.Camera(1920, 1080)
        self.m_set_default_layout = False
        self.m_frame_it = 0
        self.m_ui_frame_it = 0
        self.m_viewports = {}
        
        self.reset_camera()

        #input state
        self.m_right_pressed = False
        self.m_left_pressed = False
        self.m_top_pressed = False
        self.m_bottom_pressed = False
        self.m_can_move_pressed = False
        self.m_can_orbit_pressed = False
        self.m_last_mouse = (0.0, 0.0)

        #camera settings
        self.m_cam_move_speed = 0.1
        self.m_cam_rotation_speed = 0.1
        self.m_last_mouse = (0, 0)

        #ui panels states
        self.m_tools = self.createToolPanels()
        self.reload_scene()

    def createToolPanels(self):
        return {
            'view_panel' : EditorPanel("View Settings", False)
        }

    def save_editor_state(self):
        state = {
            'tools_states' : [(k, v.state) for (k, v) in self.m_tools.items()],
            'viewport_ids' : [vp.id for vp in self.m_viewports.values()]
        }
        try:
            f = open('editor_state.json', "w")
            f.write(json.dumps(state))
            f.close()
        except Exception as err:
            print("[Editor]: error saving state"+str(err))

    def load_editor_state(self):
        try:
            if not os.path.exists('editor_state.json'):
                return

            f = open('editor_state.json', "r")

            state = json.loads(f.read())
            if 'tools_states' in state:
                toolsTuples = state['tools_states']
                for (tn, tstate) in toolsTuples:
                    if tn in self.m_tools:
                        self.m_tools[tn].state = tstate
            if 'viewport_ids' in state:
                for vp_id in state['viewport_ids']:
                    self.m_viewports[vp_id] = EditorViewport(vp_id)
            f.close()
        except Exception as err:
            print("[Editor]: error loading state"+str(err))

    def reset_camera(self):
        initial_pos = vec.float3(0, 0, -20)
        self.m_editor_camera.pos = initial_pos
        self.m_editor_camera.rotation = vec.q_from_angle_axis(0, vec.float3(1, 0, 0))
        self.m_editor_camera.focus_distance = vec.veclen(initial_pos)
        self.m_editor_camera.update_mats()

    def build_menu_bar(self, imgui : g.ImguiBuilder):
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
            if (imgui.begin_menu("Tools")):
                for t in self.m_tools.values():
                    t.state = True if imgui.menu_item(label = t.name) else t.state
                imgui.end_menu()
            if (imgui.begin_menu("Window")):
                if (imgui.menu_item(label = "New Viewport")):
                    vp_id_list = [vp.id for vp in self.m_viewports.values()]
                    next_id = (0 if vp_id_list is [] else max(vp_id_list)) + 1
                    new_name = "Viewport " + str(next_id)
                    self.m_viewports[next_id] = EditorViewport(next_id)
                if (imgui.menu_item(label = "Reset Layout")):
                    self.m_set_default_layout = True
                imgui.end_menu()
            imgui.end_main_menu_bar()

    def build_view_settings_panel(self, imgui : g.ImguiBuilder):
        panel = self.m_tools['view_panel']
        if not panel.state:
            return

        panel.state = imgui.begin(panel.name, panel.state)
        if (imgui.collapsing_header("params")):
            self.m_editor_camera.fov = imgui.slider_float(label="fov", v=self.m_editor_camera.fov, v_min=0.01 * np.pi, v_max=0.7 * np.pi)
            self.m_editor_camera.near = imgui.slider_float(label="near", v=self.m_editor_camera.near, v_min=0.001, v_max=8.0)
            self.m_editor_camera.far = imgui.slider_float(label="far", v=self.m_editor_camera.far, v_min=10.0, v_max=90000)

        if (imgui.collapsing_header("transform")):
            cam_transform = self.m_editor_camera.transform
            nx = cam_transform.translation[0]
            ny = cam_transform.translation[1]
            nz = cam_transform.translation[2]
            (nx, ny, nz) = imgui.input_float3(label="pos", v=[nx, ny, nz])
            cam_transform.translation = [nx, ny, nz]
            if (imgui.button("reset")):
                self.reset_camera()

        imgui.end()
            

    @property
    def camera(self):
        return self.m_editor_camera

    @property
    def viewports(self):
        return self.m_viewports.values()

    def _rotate_transform_mouse_control(self, target_transform, curr_mouse, delta_time, x_axis_sign = 1.0, y_axis_sign = 1.0):
        rot_vec = delta_time * self.m_cam_rotation_speed * vec.float3(curr_mouse[2] - self.m_last_mouse[0], curr_mouse[3] - self.m_last_mouse[1], 0.0)
        y_axis = vec.float3(0, 1, 0)
        qx = vec.q_from_angle_axis(-np.sign(x_axis_sign * rot_vec[0]) * (np.abs(rot_vec[0]) ** 1.2), y_axis)
        target_transform.rotation = (qx * target_transform.rotation)
        
        x_axis = target_transform.right
        qy = vec.q_from_angle_axis(np.sign(y_axis_sign * rot_vec[1]) * (np.abs(rot_vec[1]) ** 1.2), x_axis)
        target_transform.rotation = (qy * target_transform.rotation)

    def _update_inputs(self, input_states):
        self.m_right_pressed = input_states.get_key_state(g.Keys.D) 
        self.m_left_pressed = input_states.get_key_state(g.Keys.A)
        self.m_top_pressed = input_states.get_key_state(g.Keys.W)
        self.m_bottom_pressed = input_states.get_key_state(g.Keys.S)
        prev_move_pressed = self.m_can_move_pressed
        prev_orbit_pressed = self.m_can_orbit_pressed
        self.m_can_move_pressed =  input_states.get_key_state(g.Keys.MouseRight)
        self.m_can_orbit_pressed =  input_states.get_key_state(g.Keys.LeftAlt) and input_states.get_key_state(g.Keys.MouseLeft)
        if prev_move_pressed != self.m_can_move_pressed or prev_orbit_pressed != self.m_can_orbit_pressed:
            m = input_states.get_mouse_position()
            self.m_last_mouse = (m[2], m[3])

    def update_camera(self, w, h, delta_time, input_states):
        self.m_frame_it = self.m_frame_it + 1
        self.m_editor_camera.w = w
        self.m_editor_camera.h = h
        self._update_inputs(input_states)
        if (self.m_can_move_pressed):
            new_pos = self.m_editor_camera.pos
            zero = vec.float3(0, 0, 0)
            cam_transform = self.m_editor_camera.transform
            new_pos = new_pos - ((cam_transform.right * self.m_cam_move_speed) if self.m_right_pressed  else zero)
            new_pos = new_pos + ((cam_transform.right * self.m_cam_move_speed) if self.m_left_pressed   else zero)
            new_pos = new_pos + ((cam_transform.front * self.m_cam_move_speed   ) if self.m_top_pressed    else zero)
            new_pos = new_pos - ((cam_transform.front * self.m_cam_move_speed   ) if self.m_bottom_pressed else zero)
            self.m_editor_camera.pos = new_pos
            curr_mouse = input_states.get_mouse_position()
            self._rotate_transform_mouse_control(cam_transform, curr_mouse, delta_time)
            self.m_last_mouse = (curr_mouse[2], curr_mouse[3])
        elif (self.m_can_orbit_pressed):
            lookat_pos = self.m_editor_camera.focus_point
            lookat_dist = self.m_editor_camera.focus_distance
            cam_transform = self.m_editor_camera.transform
            curr_mouse = input_states.get_mouse_position()
            self._rotate_transform_mouse_control(cam_transform, curr_mouse, delta_time, -1.0)
            cam_transform.translation = lookat_pos - lookat_dist * cam_transform.front
            cam_transform.update_mats()
            self.m_last_mouse = (curr_mouse[2], curr_mouse[3])
            

    def setup_default_layout(self, root_d_id, imgui : g.ImguiBuilder):
        settings_loaded = imgui.settings_loaded()
        if ((settings_loaded or self.m_ui_frame_it > 0) and not self.m_set_default_layout):
            return

        if 0 not in self.m_viewports:
            newVp = EditorViewport(0)
            newVp.build_ui(imgui)
            self.m_viewports[0] = newVp

        imgui.dockbuilder_remove_child_nodes(root_d_id)
        (t, l, r) = imgui.dockbuilder_split_node(node_id=root_d_id, split_dir = g.ImGuiDir.Left, split_ratio = 0.2)
        view_panel = self.m_tools['view_panel']
        view_panel.state = True
        imgui.dockbuilder_dock_window(view_panel.name, t)
        imgui.dockbuilder_dock_window("Viewport 0", r)
        imgui.dockbuilder_finish(root_d_id)
        self.m_set_default_layout = False


    def build_ui(self, imgui : g.ImguiBuilder):

        root_d_id = imgui.get_id("RootDock")

        imgui.begin(name="MainWindow", is_fullscreen = True)
        imgui.dockspace(dock_id=root_d_id)
        imgui.end()

        self.build_menu_bar(imgui)
        self.build_view_settings_panel(imgui)
        viewport_objs = [vo for vo in self.m_viewports.values()]
        for vp in viewport_objs: 
            if not vp.build_ui(imgui):
                del self.m_viewports[vp.id]

        self.setup_default_layout(root_d_id, imgui)
        self.m_ui_frame_it = self.m_ui_frame_it + 1

    def reload_scene(self):
        if self.m_active_scene_name == None:
            return
        print ("[Editor]: loading scene: "+'"'+self.m_active_scene_name+"'")
        try:
            self.m_active_scene = pywavefront.Wavefront(file_name= self.m_active_scene_name, create_materials=True, collect_faces=True)
            self.m_geo.register_wavefront_obj(self.m_active_scene)
        except Exception as err:
            print ("[Editor]: failed parsing scene, reason: " + str(err))

        
 
