import coalpy.gpu as g
import array
import numpy as np
import math

class GpuGeo:

    # 32 megabytes.
    vertex_pool_byte_size = 32 * 1024 * 1024

    # 16 megabytes
    index_pool_byte_size = 16 * 1024 * 1024

    # 3 floats (pos) + 3 floats (normal) + 2 floats (uv)
    vertex_format_byte_size = ((4 * 3) + (4 * 3) +  (4 * 2))

    #32 bits for now
    index_format_byte_size = 4

    def __init__(self):

        self.m_vertex_buffer = g.Buffer(
            name ="global_vertex_buffer",
            type = g.BufferType.Raw,
            stride = 4,
            element_count = math.ceil(GpuGeo.vertex_pool_byte_size/4)
        )


        self.m_index_buffer = g.Buffer(
            name = "global_index_buffer",
            type = g.BufferType.Standard,
            format = g.Format.R32_UINT,
            element_count = math.ceil(GpuGeo.index_pool_byte_size/GpuGeo.index_format_byte_size)
        )

        self.triCounts = 0

    
    #simple testing function
    def load_simple_triangle(self):
        tri_data = array.array('f', [
             #v.x,  v.y,  v.z,    # uv.x, uv.y, n.x,  n.y,  n.z
               1.0,  -0.5,  -2.0,  # 0.0,  0.0,  0.0,  0.0,  1.0,
              -1.0,  -0.5,  -2.0,  # 1.0,  0.0,  0.0,  0.0,  1.0,
               0.0,   1.0,  2.0,   # 0.5,  1.0,  0.0,  0.0,  1.0

             #v.x,  v.y,  v.z,    # uv.x, uv.y, n.x,  n.y,  n.z
               1.0,  -0.5,  -4.0,  # 0.0,  0.0,  0.0,  0.0,  1.0,
              -1.0,  -0.5,  -4.0,  # 1.0,  0.0,  0.0,  0.0,  1.0,
               0.0,   1.0,  0.0    # 0.5,  1.0,  0.0,  0.0,  1.0
        ])

        index_data = [0, 1, 2, 3, 4, 5]

        c = g.CommandList()
        c.upload_resource(
            source = tri_data,
            destination = self.m_vertex_buffer            
        )

        c.upload_resource(
            source = index_data,
            destination = self.m_index_buffer
        )

        g.schedule(c)
        self.triCounts = 2

    def register_wavefront_obj(self, wavefront_obj):
        self.triCounts = 0

        try:
            vertex_data = np.array(wavefront_obj.vertices, dtype='f')
            index_data = np.array(wavefront_obj.mesh_list[0].faces, dtype='i')
            c = g.CommandList()
            c.upload_resource(source = vertex_data, destination = self.m_vertex_buffer)
            c.upload_resource(source = index_data, destination = self.m_index_buffer)
            g.schedule(c)
            self.triCounts = len(wavefront_obj.mesh_list[0].faces) 
        except Exception as err:
            print("[gpugeo]: Failed uploading wavefront obj to GPU: " + str(err))

        

