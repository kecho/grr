import coalpy.gpu as g
import math

g_coverage_lut_tool_shader = g.Shader(file="coverage_lut_tool.hlsl", name="coverage_lut_tool", main_function = "csMain")

class CoverageLUTTool:
    def __init__(self):
        self.m_active = True
        self.m_texture = None
        self.m_tex_width = 0
        self.m_tex_height = 0
        return

    @property
    def active(self):
        return self.m_active

    @active.setter
    def active(self, value):
        self.m_active = value

    def render(self):
        if self.m_tex_width == 0 or self.m_tex_height == 0:
            return

        cmd = g.CommandList()

        cmd.dispatch(
            shader = g_coverage_lut_tool_shader,
            constants = [
                float(self.m_tex_width), float(self.m_tex_height), 1.0/float(self.m_tex_width), 1.0/float(self.m_tex_height)],
            outputs = self.m_texture,

            x = math.ceil(self.m_tex_width/8),
            y = math.ceil(self.m_tex_height/8),
            z = 1
        )

        g.schedule(cmd)
        return

    def build_ui(self, imgui : g.ImguiBuilder):
        self.m_active = imgui.begin("Coverage LUT Tool", self.m_active)
        (cr_min_w, cr_min_h) = imgui.get_window_content_region_min()
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
