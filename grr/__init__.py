import os
import sys
import pathlib
import coalpy.gpu as g


print ("graphics devices:")
[print("{}: {}".format(idx, nm)) for (idx, nm) in g.get_adapters()]

def _checkGpu(gpuInfo, substring):
    (idx, nm) = gpuInfo
    return substring in nm.lower()

#if we find an nvidia or amd gpu, the first one, we select it.
print ("GRR - GPU Render And Rasterizer")
selected_gpu = next((adapter for adapter in g.get_adapters() if _checkGpu(adapter, "nvidia") or _checkGpu(adapter, "amd")), None)
if selected_gpu is not None:
    print ("Setting gpu %d" % selected_gpu[0] )
    g.get_settings().adapter_index = selected_gpu[0]

#g.get_settings().spirv_debug_reflection = True
g.get_settings().enable_debug_device = False
g.get_settings().graphics_api = "dx12"


g_module_path = os.path.dirname(pathlib.Path(sys.modules[__name__].__file__)) + "\\"
g.add_data_path(g_module_path)

def get_module_path():
    return g_module_path
