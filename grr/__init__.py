import os
import sys
import pathlib
import coalpy.gpu as g


print ("graphics devices:")
[print("{}: {}".format(idx, nm)) for (idx, nm) in g.get_adapters()]

def _checkGpu(gpuInfo, substring):
    (idx, nm) = gpuInfo
    return substring in nm.lower()

##if we find an nvidia or amd gpu, the first one, we select it.
selectedGpu = next((adapter for adapter in g.get_adapters() if _checkGpu(adapter, "nvidia") or _checkGpu(adapter, "amd")), None)
if selectedGpu != None:
    g.set_current_adapter(selectedGpu[0])

g_module_path = os.path.dirname(pathlib.Path(sys.modules[__name__].__file__)) + "\\"
g.add_data_path(g_module_path)

def get_module_path():
    return g_module_path
