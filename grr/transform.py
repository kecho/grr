import numpy as np

class Transform:

    Identity = np.array(
        [[1.0,0.0,0.0],
         [0.0,1.0,0.0],
         [0.0,0.0,1.0]], dtype='f')

    s_DirtyTranslations = 1 << 0
    s_DirtyRotations = 1 << 1

    def __init__(self):
        self.m_transform = Transform.Identity
        self.m_translation = np.array([0.0, 0.0, 0.0], dtype='f')
        self.m_rotations = np.array([0.0, 0.0, 0.0], dtype='f')
        self.m_rotmat = Transform.Identity
        self.m_transmat = Transform.Identity
        self.m_dirty_flags = 0
        return;
            
    @property
    def translation(self):
        return self.m_translation

    @property
    def translation_mat(self):
        return self.m_transmat

    @property
    def rotations(self):
        return self.m_rotations

    @property
    def rotation_mat(self):
        return self.m_transmat

    @rotations.setter
    def rotations(self, value):
        self.m_dirty_flags = self.m_dirty_flags | Transform.s_DirtyRotations
        if type(value) == np.ndarray and value.size == 3:
            self.m_rotations = value
        elif type(value) == list and len(value) == 3:
            self.m_rotations[:] = value
        else:
            raise ValueError("value for translation must be a numpy ndarray of size 3, or a flat array")

    @translation.setter
    def translation(self, value):
        self.m_dirty_flags = self.m_dirty_flags | Transform.s_DirtyTranslations
        if type(value) == np.ndarray and value.size == 3:
            self.m_translation = value
        elif type(value) == list and len(value) == 3:
            self.m_translation[:] = value
        else:
            raise ValueError("value for translation must be a numpy ndarray of size 3, or a flat array")
        
