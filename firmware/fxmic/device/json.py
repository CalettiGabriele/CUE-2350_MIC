# FXMic boot hook (ADR-003): the factory code imports json as its second statement.
# Give it back the built-in json, then start FXMic and stop the factory code. Any failure
# falls through, so the factory logic still runs.
import sys

class FXMicBoot(Exception):
    pass

_me = sys.modules.pop('json', None)
_p = sys.path[:]
sys.path[:] = []
try:
    import json as _j
finally:
    sys.path[:] = _p
sys.modules['json'] = _j
dump, dumps, load, loads = _j.dump, _j.dumps, _j.load, _j.loads
try:
    import fxmic
    fxmic.start()
except Exception:
    fxmic = None
if fxmic:
    raise FXMicBoot()
