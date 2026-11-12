# -*- coding: utf-8 -*-
"""Сравнение AABB-сканов до/после: разбивка пар по классам объектов."""
import json
from collections import Counter


def load(p):
    return json.load(open(p, encoding="utf-8"))


base = load(r".codex_qa\zfight_fix\out\scan_baseline_repro.json")
fix = load(r".codex_qa\zfight\scan_after_lead.json")


def cls(name):
    n = name.lower()
    if "decal" in n:
        return "decal"
    if "trim_hazard" in n:
        return "trim"
    if "pipe" in n or "cable" in n:
        return "pipe/cable"
    if "floor_tile" in n:
        return "floor"
    if "ceil_panel" in n:
        return "ceiling"
    if "wall_panel" in n:
        return "wall"
    if "airlock" in n or "room_" in n:
        return "airlock GLB"
    if "fixture" in n or "lamp" in n:
        return "fixtures"
    return "прочее"


def stats(d):
    out = {}
    for key in ("thin", "deep"):
        c = Counter()
        for p in d.get(key, []):
            pair = " + ".join(sorted([cls(p["a"]), cls(p["b"])]))
            c[pair] += 1
        out[key] = c
    return out


sb, sf = stats(base), stats(fix)
print("=== THIN: base -> fixed (только изменения) ===")
for k in sorted(set(sb["thin"]) | set(sf["thin"])):
    b, f = sb["thin"].get(k, 0), sf["thin"].get(k, 0)
    if b != f:
        print("  %-34s %3d -> %3d" % (k, b, f))
print("=== DEEP: base -> fixed (только изменения) ===")
for k in sorted(set(sb["deep"]) | set(sf["deep"])):
    b, f = sb["deep"].get(k, 0), sf["deep"].get(k, 0)
    if b != f:
        print("  %-34s %3d -> %3d" % (k, b, f))
print("\nTOTAL base thin=%d deep=%d; fixed thin=%d deep=%d"
      % (len(base["thin"]), len(base["deep"]), len(fix["thin"]), len(fix["deep"])))


def has(d, key, sub):
    return [p for p in d.get(key, []) if sub in (p["a"] + " " + p["b"]).lower()]


for label, sub in [("floor_tile", "floor_tile"), ("trim_hazard", "trim_hazard"),
                   ("cable_bundle", "cable_bundle"), ("pipe_run", "pipe_run"),
                   ("wall_panel", "wall_panel")]:
    print("  %-12s base thin/deep=%d/%d -> fixed=%d/%d"
          % (label,
             len(has(base, "thin", sub)), len(has(base, "deep", sub)),
             len(has(fix, "thin", sub)), len(has(fix, "deep", sub))))
