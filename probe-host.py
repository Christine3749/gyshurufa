import struct, sys

PIPE = r"\\.\pipe\GYInput.Host.v1"
MAGIC = 0x4759494D
STATUS, LOOKUP = 2, 1

def roundtrip(f, mtype, text):
    payload = text.encode("utf-16-le")
    f.write(struct.pack("<IHH I", MAGIC, 1, mtype, len(payload)) + payload)
    f.flush()
    raw = f.read(12)
    if len(raw) < 12:
        return None
    magic, ver, rtype, nbytes = struct.unpack("<IHHI", raw)
    body = f.read(nbytes) if nbytes else b""
    return rtype, body.decode("utf-16-le", errors="replace")

try:
    f = open(PIPE, "r+b", buffering=0)
except OSError as e:
    print("OPEN FAIL:", e); sys.exit(1)

r = roundtrip(f, STATUS, "")
print("STATUS ->", r)
r = roundtrip(f, LOOKUP, "woshishui")
if r:
    cands = [c for c in r[1].split("\x00") if c]
    print("LOOKUP woshishui ->", cands[:8] if cands else "(EMPTY)")
else:
    print("LOOKUP FAIL")
f.close()
