import numpy as np
from . import vec
from . import transform

class Camera:

    def __init__(self):
        self.m_transform = Transform()
        return

    @property
    def transform(self):
        return self.m_transform
