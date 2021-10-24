import numpy as np
from . import vec
from . import transform as t

class Camera:

    s_DirtyProj = 1 << 0

    def __init__(self, w, h):
        self.m_fov = 20 * t.to_radians()
        self.m_w = w
        self.m_h = h
        self.m_near = 0.1
        self.m_far = 10000
        self.m_transform = t.Transform()
        self.m_proj_matrix = t.Transform.Identity()
        self.m_proj_inv_matrix = t.Transform.Identity()
        self.m_dirty_flags = Camera.s_DirtyProj
        self.update_mats()
        return

    @property
    def transform(self):
        return self.m_transform

    @property
    def pos(self):
        return self.m_transform.translation

    @property
    def fov(self):
        return self.m_fov

    @property
    def w(self):
        return self.m_w

    @property
    def h(self):
        return self.m_h

    @property
    def near(self):
        return self.m_near

    @property
    def far(self):
        return self.m_far

    @property
    def proj_matrix(self):
        self.update_mats()
        return self.m_proj_matrix

    @property
    def proj_inv_matrix(self):
        self.update_mats()
        return self.m_proj_inv_matrix

    @property
    def view_matrix(self):
        return self.m_transform.transform_inv_matrix

    @fov.setter
    def fov(self, value):
        self.m_dirty_flags = Camera.s_DirtyProj
        self.m_fov = value

    @pos.setter
    def pos(self, value):
        self.m_transform.translation = value

    @w.setter
    def fov(self, value):
        self.m_dirty_flags = Camera.s_DirtyProj
        self.m_w = value

    @h.setter
    def fov(self, value):
        self.m_dirty_flags = Camera.s_DirtyProj
        self.m_h = value

    @near.setter
    def near(self, value):
        self.m_dirty_flags = Camera.s_DirtyProj
        self.m_near = value

    @far.setter
    def far(self, value):
        self.m_dirty_flags = Camera.s_DirtyProj
        self.m_far = value

    def update_mats(self):
        if ((self.m_dirty_flags & Camera.s_DirtyProj) != 0):
            self.m_proj_matrix = t.projection_matrix_from_aspect(self.m_fov, self.m_h / self.m_w, self.m_near, self.m_far)
            self.m_proj_inv_matrix = np.linalg.inv(self.m_proj_matrix)
