#!/usr/bin/env python3
"""Offline Qt metadata inventory for the exact 269602 arm64 module. No native calls."""
import argparse, hashlib

parser = argparse.ArgumentParser()
parser.add_argument("module")
parser.add_argument("output", help="new output directory")
args = parser.parse_args()
digest = hashlib.sha256()
with open(args.module, "rb") as module:
    for block in iter(lambda: module.read(1024 * 1024), b""):
        digest.update(block)
if (
    digest.hexdigest()
    != "6e82322680d7747020c305f67e932b235fe68b22578c24d9c524dabb31a4694a"
):
    parser.error(
        "module does not match pristine 269602; refusing fixed-layout analysis"
    )
from pathlib import Path

output = Path(args.output)
output.mkdir(parents=True, exist_ok=False)
import mmap, struct, json
from pathlib import Path

f = open(args.module, "rb")
d = mmap.mmap(f.fileno(), 0, access=mmap.ACCESS_READ)
_, n = struct.unpack_from(">II", d)
off, size = next(
    (a[2], a[3])
    for a in [struct.unpack_from(">IIIII", d, 8 + 20 * i) for i in range(n)]
    if a[0] == 0x100000C
)
h = struct.unpack_from("<8I", d, off)
pos = off + 32
segs = []
for _ in range(h[4]):
    cmd, sz = struct.unpack_from("<II", d, pos)
    if cmd == 0x19:
        name, va, vs, fo, fs = struct.unpack_from("<16sQQQQ", d, pos + 8)
        segs.append((name.rstrip(b"\0").decode(), va, vs, fo, fs))
    pos += sz


def fp(va):
    for name, v, s, p, fs in segs:
        if v <= va < v + fs:
            return off + p + va - v
    raise ValueError("outside file")


def q(va):
    return struct.unpack_from("<Q", d, fp(va))[0] & 0xFFFFFFFFF


def u(va):
    return struct.unpack_from("<I", d, fp(va))[0]


def st(table, i):
    p = fp(table + 24 * i)
    ref, ln = struct.unpack_from("<ii", d, p)
    delta = struct.unpack_from("<q", d, p + 16)[0]
    if ref != -1 or not 0 <= ln < 4096 or not -200000 < delta < 200000:
        raise ValueError("bad string")
    return d[p + delta : p + delta + ln].decode("utf8")


records = []
for name, va, vs, fo, fs in segs:
    if name != "__DATA_CONST":
        continue
    for at in range(va, va + fs - 48, 8):
        try:
            table = q(at + 8)
            data = q(at + 16)
            if not (va <= table < 0x9F38000) or not 7 <= u(data) <= 8:
                continue
            cname = st(table, u(data + 4))
            if not cname or len(cname) > 250:
                continue
            vals = struct.unpack_from("<14I", d, fp(data))
            nmethod, methodoffset = vals[4:6]
            if nmethod > 500 or vals[6] > 500:
                continue
            methods = []
            for i in range(nmethod):
                m = struct.unpack_from("<5I", d, fp(data + 4 * (methodoffset + 5 * i)))
                params = struct.unpack_from(
                    "<" + str(1 + m[1] * 2) + "I", d, fp(data + m[2] * 4)
                )

                def typ(t):
                    return st(table, t & 0x7FFFFFFF) if t & 0x80000000 else str(t)

                methods.append(
                    {
                        "name": st(table, m[0]),
                        "argc": m[1],
                        "flags": m[4],
                        "return": typ(params[0]),
                        "types": [typ(t) for t in params[1 : 1 + m[1]]],
                    }
                )
            records.append(
                {
                    "name": cname,
                    "meta": hex(at),
                    "super": hex(q(at)),
                    "strings": hex(table),
                    "data": hex(data),
                    "call": hex(q(at + 24)),
                    "methods": methods,
                }
            )
        except (ValueError, struct.error, UnicodeError, OverflowError):
            pass
(output / "qtmeta.json").write_text(json.dumps(records, ensure_ascii=False, indent=2))
print("Parsed metaobjects", len(records))
import array, bisect

records = json.loads((output / "qtmeta.json").read_text())
byaddr = {int(r["meta"], 16): r for r in records}
# LC_FUNCTION_STARTS stores ULEB128 deltas relative to __TEXT vmaddr 0.
pos = off + 32
starts = []
for _ in range(h[4]):
    cmd, sz = struct.unpack_from("<II", d, pos)
    if cmd == 0x26:
        at, ln = struct.unpack_from("<II", d, pos + 8)
        buf = d[off + at : off + at + ln]
        delta = 0
        shift = 0
        address = 0
        for b in buf:
            delta |= (b & 0x7F) << shift
            if b & 0x80:
                shift += 7
            else:
                if delta == 0:
                    break
                address += delta
                starts.append(address)
                delta = 0
                shift = 0
    pos += sz
words = array.array("I", d[off : off + 0x6CB0000])
functions = {}
for i in range(len(words) - 2):
    w = words[i]
    if w & 0x9F00001F != 0x90000000:
        continue
    a = words[i + 1]
    if a & 0xFFC003FF != 0x91000000 or words[i + 2] != 0xD65F03C0:
        continue
    imm = ((w >> 5) & 0x7FFFF) << 2 | ((w >> 29) & 3)
    if imm & (1 << 20):
        imm -= 1 << 21
    address = (i * 4 & ~0xFFF) + (imm << 12) + ((a >> 10) & 0xFFF)
    if address in byaddr:
        entry = starts[bisect.bisect_right(starts, i * 4) - 1]
        if i * 4 - entry < 160:
            functions[entry] = byaddr[address]
print("function starts", len(starts), "metaObject implementations", len(functions))
vtables = []
for name, va, vs, fo, fs in segs:
    if name != "__DATA_CONST":
        continue
    for a in range(va + 16, va + fs - 40, 8):
        fn = q(a)
        if fn in functions and struct.unpack_from("<q", d, fp(a - 16))[0] == 0:
            rec = functions[fn]
            if rec["name"].startswith("mmui::"):
                vtables.append(
                    {
                        "class": rec["name"],
                        "vtable": hex(a),
                        "metaObject": hex(fn),
                        "meta": rec["meta"],
                    }
                )
(output / "vtables.json").write_text(json.dumps(vtables, indent=2))
print("mapped mmui vtables", len(vtables))
