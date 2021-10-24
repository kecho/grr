import numpy as np
import quaternion

def float3(x, y, z):
    return np.array([x, y, z], dtype='f')

def float4(x, y, z, w):
    return np.array([x, y, z, w], dtype='f')

def veclen(v):
    return np.sqrt(np.sum(v ** 2))

def normalize(v):
    v[:] = v[:] / veclen(v)
    return v

def q_from_angle_axis(angle, axis):
    a = np.sin(angle) * normalize(axis)
    w = np.cos(angle)
    return np.quaternion(w, a[0], a[1], a[2])
    
