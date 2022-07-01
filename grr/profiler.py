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
        if self.m_active and imgui.begin_tab_bar("profiler-tab"):
            if imgui.begin_tab_item("Hierarchy"):
                self._build_hierarchy_ui(imgui)
                imgui.end_tab_item()
            if imgui.begin_tab_item("Timeline"):
                imgui.text("TODO: timeline")
                imgui.end_tab_item()
            if imgui.begin_tab_item("Raw Counters"):
                self._build_raw_counter_ui(imgui)
                imgui.end_tab_item()
            imgui.end_tab_bar()
        imgui.end()

    def _build_raw_counter_ui(self, imgui : g.ImguiBuilder):
        titles = ["ID", "ParentID", "Name", "Time", "BeginTimestamp", "EndTimestamp"]
        imgui.text(f"{titles[0] : <4} {titles[1] : <8} {titles[2] : <32} {titles[3] : ^10} {titles[4] : ^18} {titles[5] : ^18} ")
        for id in range(0, len(self.m_marker_data)):
            (name, end_timestamp, begin_timestamp, parent_id) = self.m_marker_data[id]
            time = end_timestamp - begin_timestamp
            time_str = "%.4f ms" % (time * 1000)
            imgui.text(f"{id: <4} {parent_id : <8} {name : <32} {time_str : ^10} {begin_timestamp : ^18} {end_timestamp : ^18} ")
            #imgui.text(name + ": " + ("%.4f ms" % (time * 1000)))

    def _build_hierarchy_ui(self, imgui : g.ImguiBuilder):
        if len(self.m_marker_data) == 0:
            return

        hierarchy = [(id, []) for id in range(0, len(self.m_marker_data))]
        node_stack = []
        for id in range(0, len(self.m_marker_data)):
            (_, _, _, parent_id) = self.m_marker_data[id]
            if parent_id != -1:
                hierarchy[parent_id][1].append(id)
            else:
                node_stack.append((id, False))

        node_stack.reverse()
        for (_, l) in hierarchy:
            l.reverse()

        while len(node_stack) > 0:
            (id, was_visited) = node_stack.pop()
            if was_visited:
                imgui.tree_pop()
            else:
                (name, timestamp_end, timestamp_begin, _) = self.m_marker_data[id]
                children = hierarchy[id][1]
                flags = (g.ImGuiTreeNodeFlags.Leaf|g.ImGuiTreeNodeFlags.Bullet) if len(children) == 0 else 0
                timestamp_str = "%.4f ms" % ((timestamp_end - timestamp_begin) * 1000)
                if imgui.tree_node_with_id(id, f"{name : <32}{timestamp_str}", flags):
                    node_stack.append((id, True)) #set was_visited to True
                    node_stack.extend([(child_id, False) for child_id in children])

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
            self.m_marker_data = [ (name, gpu_timestamps[ei]/data.timestamp_frequency, gpu_timestamps[bi]/data.timestamp_frequency, pid) for (name, pid, bi, ei) in data.markers]
        
