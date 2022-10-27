import coalpy.gpu as g
from . import debug_font
import math

# Flags must match coverage_lut_tool.hlsl
class CoverageImageFlags:
    ShowTriangle  = 1 << 0
    ShowTriangleBackface  = 1 << 1
    ShowTriangleFrontface = 1 << 2
    ShowLine      = 1 << 3
    
g_coverage_lut_tool_shader = g.Shader(file="coverage_lut_tool.hlsl", name="coverage_lut_tool", main_function = "csMain")

class CoverageLUTTool:
    def __init__(self):
        self.m_active = False
        self.m_texture = None
        self.m_tex_width = 0
        self.m_tex_height = 0
        self.m_show_triangle = True
        self.m_show_triangle_backface = True
        self.m_show_triangle_frontface = True
        self.m_show_line = True
        self.m_v0x = 0.2
        self.m_v0y = 0.2
        self.m_v1x = 0.5
        self.m_v1y = 0.9
        self.m_v2x = 0.9
        self.m_v2y = 0.2
        self.m_v3x = 0.2
        self.m_v3y = 0.5
        self.m_v4x = 0.8 
        self.m_v4y = 0.5
        self.m_line_thickness = 0.18
        self.m_line_cap = 0.0
        self.m_is_focused = False
        return

    @property
    def active(self):
        return self.m_active

    @active.setter
    def active(self, value):
        self.m_active = value

    @property
    def is_focused(self):
        return self.m_is_focused

    def render(self):
        if self.m_tex_width == 0 or self.m_tex_height == 0:
            return

        cmd = g.CommandList()

        flags =  CoverageImageFlags.ShowTriangle if self.m_show_triangle else 0
        flags |= CoverageImageFlags.ShowTriangleBackface if self.m_show_triangle_backface else 0
        flags |= CoverageImageFlags.ShowTriangleFrontface if self.m_show_triangle_frontface else 0
        flags |= CoverageImageFlags.ShowLine if self.m_show_line else 0

        cmd.dispatch(
            shader = g_coverage_lut_tool_shader,
            constants = [
                float(self.m_tex_width), float(self.m_tex_height), 1.0/float(self.m_tex_width), 1.0/float(self.m_tex_height),
                float(self.m_v0x), float(self.m_v0y), float(self.m_v1x), float(self.m_v1y),
                float(self.m_v2x), float(self.m_v2y), float(self.m_v3x), float(self.m_v3y),
                float(self.m_v4x), float(self.m_v4y), float(0.0), float(0.0),
                float(self.m_line_thickness), float(self.m_line_cap), float(0.0), float(0.0),
                int(flags), 0, 0, 0],
            
            samplers = [debug_font.font_sampler],
            inputs = [debug_font.font_texture],
            outputs = self.m_texture,

            x = math.ceil(self.m_tex_width/8),
            y = math.ceil(self.m_tex_height/8),
            z = 1
        )

        g.schedule(cmd)
        return

    def build_ui_properties(self, imgui : g.ImguiBuilder):
        if (imgui.collapsing_header("Coverage lut props", g.ImGuiTreeNodeFlags.DefaultOpen)):
            self.m_show_triangle = imgui.checkbox("show_triangle", self.m_show_triangle)
            self.m_show_line = imgui.checkbox("show_line", self.m_show_line)

        if (self.m_show_triangle and imgui.collapsing_header("Coverage lut tool triangle", g.ImGuiTreeNodeFlags.DefaultOpen)):
            self.m_show_triangle_backface  = imgui.checkbox("show_triangle_backface", self.m_show_triangle_backface  )
            self.m_show_triangle_frontface = imgui.checkbox("show_triangle_frontface", self.m_show_triangle_frontface)
            self.m_v0x = imgui.slider_float(label="tri_v0x", v=self.m_v0x, v_min=0.0, v_max=1.0)
            self.m_v0y = imgui.slider_float(label="tri_v0y", v=self.m_v0y, v_min=0.0, v_max=1.0)
            self.m_v1x = imgui.slider_float(label="tri_v1x", v=self.m_v1x, v_min=0.0, v_max=1.0)
            self.m_v1y = imgui.slider_float(label="tri_v1y", v=self.m_v1y, v_min=0.0, v_max=1.0)
            self.m_v2x = imgui.slider_float(label="tri_v2x", v=self.m_v2x, v_min=0.0, v_max=1.0)
            self.m_v2y = imgui.slider_float(label="tri_v2y", v=self.m_v2y, v_min=0.0, v_max=1.0)

        if (self.m_show_line and imgui.collapsing_header("Coverage lut tool line", g.ImGuiTreeNodeFlags.DefaultOpen)):
            self.m_v3x = imgui.slider_float(label="line_v0x", v=self.m_v3x, v_min=0.0, v_max=1.0)
            self.m_v3y = imgui.slider_float(label="line_v0y", v=self.m_v3y, v_min=0.0, v_max=1.0)
            self.m_v4x = imgui.slider_float(label="line_v1x", v=self.m_v4x, v_min=0.0, v_max=1.0)
            self.m_v4y = imgui.slider_float(label="line_v1y", v=self.m_v4y, v_min=0.0, v_max=1.0)
            self.m_line_thickness = imgui.slider_float(label="thickness", v=self.m_line_thickness, v_min=0.0, v_max=1.0)
            self.m_line_cap = imgui.slider_float(label="cap", v=self.m_line_cap, v_min=0.0, v_max=1.0)

    def build_ui(self, imgui : g.ImguiBuilder):
        self.m_active = imgui.begin("Coverage LUT Tool", self.m_active)
        self.m_is_focused = imgui.is_window_focused(flags = g.ImGuiFocusedFlags.RootWindow)
        (cr_min_w, cr_min_h) = imgui.get_cursor_pos()
        (cr_max_w, cr_max_h) = imgui.get_window_content_region_max()
        (nw, nh) = (int(cr_max_w - cr_min_w), int(cr_max_h - cr_min_h))

        if nw > 0 and nh > 0 and (nw != self.m_tex_width or nh != self.m_tex_height or self.m_texture is None):
            self.m_tex_width = nw
            self.m_tex_height = nh
            self.m_texture = g.Texture(
                name = "coverage_lut_tool_target", width = self.m_tex_width, height = self.m_tex_height,
                format = g.Format.RGBA_8_UNORM)

        if self.m_texture != None:
            imgui.image(texture = self.m_texture, size = (self.m_tex_width, self.m_tex_height))

        imgui.end()
