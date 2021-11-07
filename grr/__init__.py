import os
import sys
import pathlib
import coalpy.gpu as g


print ("graphics devices:")
[print("{}: {}".format(idx, nm)) for (idx, nm) in g.get_adapters()]

g.set_current_adapter(1)

g_module_path = os.path.dirname(pathlib.Path(sys.modules[__name__].__file__)) + "\\"
g.add_data_path(g_module_path)

def get_module_path():
    return g_module_path
