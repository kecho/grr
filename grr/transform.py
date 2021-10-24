import numpy as np
import quaternion
from . import vec

class Transform:

    def Identity():
        return np.identity(4, dtype='f')

    __tmp_matrix = np.identity(4, dtype='f')

    s_DirtyScales = 1 << 0
    s_DirtyTranslations = 1 << 1
    s_DirtyRotation = 1 << 1

    def __init__(self):
        self.m_rotation = vec.q_from_angle_axis(0.0, vec.float3(1, 0, 0))
        self.m_translation = vec.float3(0, 0, 0)
        self.m_scale = vec.float3(1, 1, 1)

        self.m_transform = Transform.Identity
        self.m_rotation_matrix = Transform.Identity()
        self.m_translation_matrix = Transform.Identity()
        self.m_scale_matrix = Transform.Identity()
        self.m_transform_matrix = Transform.Identity()
        self.m_transform_inv_matrix = Transform.Identity()
        self.m_dirty_flags = 0
        return;
            
    @property
    def rotation(self):
        return self.m_rotation

    @property
    def translation(self):
        return self.m_translation

    @property
    def scale(self):
        return self.m_scale

    @property
    def right(self):
        self.update_mats()
        return self.m_rotation_matrix[0:3, 0].copy()

    @property
    def up(self):
        self.update_mats()
        return self.m_rotation_matrix[0:3, 1].copy()

    @property
    def front(self):
        self.update_mats()
        return self.m_rotation_matrix[0:3, 2].copy()

    @rotation.setter
    def rotation(self, value : np.quaternion):
        if (type(value) != np.quaternion):
            raise ValueError("value for propety must be a numpy quaternion") 
        self.m_dirty_flags = self.m_dirty_flags | Transform.s_DirtyRotation
        self.m_rotation = value.copy()

    @translation.setter
    def translation(self, value):
        self.m_dirty_flags = self.m_dirty_flags | Transform.s_DirtyTranslations
        Transform._set_vec_val(self.m_translation, value)

    @scale.setter
    def scale(self, value):
        self.m_dirty_flags = self.m_dirty_flags | Transform.s_DirtyScales
        Transform._set_vec_val(self.m_scale, value)

    @property
    def translation_matrix(self):
        self.update_mats()
        return self.m_translation_matrix

    @property
    def rotation_matrix(self):
        self.update_mats()
        return self.m_rotation_matrix

    @property
    def transform_matrix(self):
        self.update_mats()
        return self.m_transform_matrix

    @property
    def transform_inv_matrix(self):
        self.update_mats()
        return self.m_transform_inv_matrix

    @property
    def scale_matrix(self):
        self.update_mats()
        return self.m_scale_matrix

    def _set_vec_val(target, value):
        if type(value) == np.ndarray and value.size == 3:
            target[:] = value[:]
        elif type(value) == list and len(value) == 3:
            target[:] = value
        else:
            raise ValueError("value for propety must be a numpy ndarray of size 3, or a flat array")

    def update_mats(self):
        if ((self.m_dirty_flags & Transform.s_DirtyTranslations)):
            self.m_translation_matrix[0,3] = self.m_translation[0]
            self.m_translation_matrix[1,3] = self.m_translation[1]
            self.m_translation_matrix[2,3] = self.m_translation[2]

        if ((self.m_dirty_flags & Transform.s_DirtyRotation)):
            self.m_rotation_matrix[0:3, 0:3] = quaternion.as_rotation_matrix(self.m_rotation)

        if ((self.m_dirty_flags & Transform.s_DirtyScales)):
            self.m_scale_matrix[0, 0] = self.m_scale[0]
            self.m_scale_matrix[1, 1] = self.m_scale[1]
            self.m_scale_matrix[2, 2] = self.m_scale[2]

        if (self.m_dirty_flags != 0):
            np.matmul(self.m_rotation_matrix, self.m_scale_matrix, Transform.__tmp_matrix)
            np.matmul(self.m_translation_matrix, Transform.__tmp_matrix, self.m_transform_matrix)
            self.m_transform_inv_matrix = np.linalg.inv(self.m_transform_matrix)

        self.m_dirty_flags = 0

def projection_matrix(l, r, t, b, n, f, is_ortho=False):
    mat = Transform.Identity()
    proj_num = 2.0 if is_ortho else (2.0*n)
    r_m_l = r - l;
    t_m_b = t - b;
    f_m_n = f - n;
    mat[0, 0:4] = [proj_num/r_m_l, 0.0, (r+l)/r_m_l, 0.0]
    mat[1, 0:4] = [0.0, proj_num/t_m_b, (t+b)/t_m_b, 0.0]
    if is_ortho:
        # domain goes from 0 to 1 on Z
        mat[2, 0:4] = [0.0, 0.0, -1.0/f_m_n, -n/f_m_n]
    else:
        mat[2, 0:4] = [0.0, 0.0, -f/f_m_n, -(n*f)/f_m_n]
    mat[3, 0:4] = [0.0, 0.0, -1.0, 0.0]
    return mat

def projection_matrix_from_aspect(fov, aspect, n, f):
    r = n*np.tan(0.5*fov);
    t = aspect * r;
    return projection_matrix(-r,r,t,-t,n,f)
