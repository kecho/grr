import coalpy.gpu as g
import numpy as nm

class Profiler:
    def __init__(self):
        self.m_active = True
        self.m_gpu_queue = []
        self.m_marker_data = []

    @property
    def active(self):
        return self.m_active

    @active.setter
    def active(self, value):
        self.m_active = value

    def build_ui(self, imgui : g.ImguiBuilder):
        self.m_active = imgui.begin("Profiler", self.m_active)
        if self.m_active:
            for (name, time) in self.m_marker_data:
                imgui.text(name + ": " + ("%.4f ms" % (time * 1000)))
        imgui.end()

    def begin_capture(self):
        if not self.active:
            return

        g.begin_collect_markers()

    def end_capture(self):        
        if not self.active:
            return

        marker_gpu_data = g.end_collect_markers()
        request = g.ResourceDownloadRequest(marker_gpu_data.timestamp_buffer)
        self.m_gpu_queue.append((marker_gpu_data, request))

        if self.m_gpu_queue[0][1].is_ready():
            (data, req) = self.m_gpu_queue.pop(0)
            gpu_timestamps = nm.frombuffer(req.data_as_bytearray(), dtype=nm.uint64)
            self.m_marker_data = [ (name, (gpu_timestamps[ei] - gpu_timestamps[bi])/data.timestamp_frequency) for (name, pid, bi, ei) in data.markers]
        
