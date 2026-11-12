# -*- coding: utf-8 -*-
"""Анализ сырых данных аудита (.codex_qa/model_audit/*.json).
   Детекторы: z-fighting (копланарные грани), глубокие пересечения, дубликаты,
   парящие/утопленные декали, perf-сводка, привязка к коду сборщика.
   Пишет: overlaps.json, overlaps.csv, _analyze_out.txt"""
import json, math, collections, csv, sys
from pathlib import Path

try:
    sys.stdout.reconfigure(encoding="utf-8", errors="replace")
except Exception:
    pass

BASE = Path(r"D:\4\.codex_qa\model_audit")
meshes = json.loads((BASE / "meshes.json").read_text(encoding="utf-8"))
probes = json.loads((BASE / "probes.json").read_text(encoding="utf-8"))
lights = json.loads((BASE / "lights.json").read_text(encoding="utf-8"))
meta = json.loads((BASE / "meta.json").read_text(encoding="utf-8"))

FLOOR, CEIL = 2.1486, 4.7486
Z0, Z1 = 10.5, 13.3
X_AIR_AFT, X_CORR_AFT, X_CORR_FWD, X_BRIDGE_FWD = -7.8, -4.0, 9.4, 14.8
ROOM_X0, ROOM_X1, ROOM_Z0, ROOM_DOOR_X = 3.2, 6.6, 7.2, 5.0

# ------------------------------------------------------------------ утилиты --
def glb_name(r):
    g = r.get("glb") or ""
    return g.split("/")[-1].replace(".glb", "")

def center_of(r):
    a = r["aabb"]
    return [(a["min"][i] + a["max"][i]) / 2 for i in range(3)]

def size_of(r):
    a = r["aabb"]
    return [a["max"][i] - a["min"][i] for i in range(3)]

def categorize(r):
    g, n, path = glb_name(r), r["name"], r["path"]
    if g == "sun" or n in ("SpaceGasGiant", "SpaceRing", "SpaceBlackHole") or \
            math.sqrt(sum(v * v for v in r["pos"])) > 100:
        return "space"
    if g.startswith("floor_tile"):
        return "floor"
    if g == "ceil_panel":
        return "ceil"
    if g.startswith("wall_panel"):
        return "wall"
    if g == "trim_hazard":
        return "trim"
    if g in ("door_frame", "door_b3", "airlock_door"):
        return "door"
    if g == "ceil_light_fixture":
        return "light_fixture"
    if g in ("pipe_run", "pipe_valves"):
        return "pipe"
    if g == "cable_bundle":
        return "cable"
    if g in ("console_section", "crt_terminal"):
        return "console"
    if g in ("crate", "crate_small"):
        return "crate"
    if g in ("equip_keyboard", "equip_mug", "equip_papers"):
        return "equip"
    if g in ("poster", "sign_warning"):
        return "sign"
    if g == "suit_rack":
        return "suit_rack"
    if g in ("bunk_bed", "locker", "shelf_rack", "table_small", "chair_folded",
             "sleeping_bag", "wall_pipes_small", "vent_grille", "cable_bundle_floor",
             "papers_scattered") or g.startswith("personal_"):
        return "furniture"
    if n.startswith("Decal_") or (n.startswith("@MeshInstance3D@") and
                                  (r.get("material_override") or {}).get("name", "").startswith("decal_")):
        return "decal"
    if n.startswith("ScreenQuad"):
        return "screen"
    if path.startswith("Radio"):
        return "radio"
    if path.startswith("Sun"):
        return "space"
    if n.startswith("@MeshInstance3D@") or n.startswith("@Node3D@"):
        sz = size_of(r)
        ov = (r.get("material_override") or {})
        if max(sz) > 2.0 or ov.get("tex_key") in ("metal_dark", "metal_panel", ""):
            return "shell"
        return "code_mesh"
    return "other"

def zone_of(r):
    c = categorize(r)
    if c == "space":
        return "space"
    p = r["pos"]
    if 2.9 <= p[0] <= 7.0 and 6.8 <= p[2] <= 10.6:
        return "quarters"
    if p[0] < -4.05:
        return "airlock"
    if p[0] > 9.45:
        return "bridge"
    if p[0] < -3.75:
        return "airlock"
    if p[0] > 9.15:
        return "bridge"
    return "corridor"

CAT_RU = {
    "floor": "пол (плитка)", "ceil": "потолок (панель)", "wall": "стеновая панель",
    "trim": "hazard-трим", "door": "дверь/рамочный модуль", "light_fixture": "плафон",
    "pipe": "трубы/вентили", "cable": "кабельный жгут", "console": "консоль/CRT",
    "crate": "ящик", "equip": "мелкий предмет", "sign": "табличка/плакат (GLB)",
    "suit_rack": "шкаф скафандра", "furniture": "мебель/личные вещи",
    "decal": "декаль-квад", "screen": "экран-квад", "radio": "радио",
    "space": "космос", "shell": "внешняя оболочка (box)", "code_mesh": "box из кода",
    "other": "прочее",
}

for r in meshes:
    r["cat"] = categorize(r)
    r["zone"] = zone_of(r)
    r["sizes"] = size_of(r)
    r["min_dim"] = min(r["sizes"])
    r["center"] = center_of(r)
    r["tex_sig"] = "|".join(sorted(set(
        (s.get("tex_key") or s.get("name") or "") for s in r["surfaces"]))) or \
        ((r.get("material_override") or {}).get("tex_key") or "")

# --------------------------------------------------------- привязка к коду ---
def expected_spawns():
    """повторяет циклы build_ship.gd / build_and_save.gd -> ожидаемые инстансы"""
    E = []
    def add(glb, pos, rot=(0, 0, 0), scale=(1, 1, 1), src="", func="", note=""):
        E.append({"glb": glb, "pos": tuple(pos), "rot": tuple(rot), "scale": tuple(scale),
                  "src": src, "func": func, "note": note})
    S = "build_ship.gd"
    # коридор: пол/потолок
    x = X_CORR_AFT + 1.0
    while x < X_CORR_FWD:
        add("floor_tile", (x, FLOOR - 0.008, 11.9), (0, 0, 0), (1, 1, 1.4), S,
            "_build_corridor", "пол 2м, scale.z=1.4")
        add("ceil_panel", (x, CEIL + 0.012, 11.9), (0, 0, 0), (1, 1, 1.4), S,
            "_build_corridor", "потолок 2м, scale.z=1.4")
        x += 2.0
    # стены+трим коридора
    x, i = X_CORR_AFT, 0
    while x < X_CORR_FWD:
        panel = "wall_panel_a" if i % 2 == 0 else "wall_panel_b"
        cx = x + 1.0
        if abs(cx - ROOM_DOOR_X) > 0.1:
            add(panel, (cx, FLOOR, Z0), (0, 0, 0), (1, 1, 1), S, "_build_corridor",
                "левый борт; проём каюты на x=5")
        add(panel, (cx, FLOOR, Z1), (0, 180, 0), (1, 1, 1), S, "_build_corridor", "правый борт")
        add("trim_hazard", (cx, FLOOR + 0.12, Z0 + 0.02), (0, 0, 0), (1, 1, 1), S,
            "_build_corridor", "hazard-полоса у пола (без пропуска у проёма!)")
        add("trim_hazard", (cx, FLOOR + 0.12, Z1 - 0.02), (0, 180, 0), (1, 1, 1), S,
            "_build_corridor", "hazard-полоса у пола")
        x += 2.0
        i += 1
    # трубы/кабели/плафоны
    mid_x = (X_CORR_AFT + X_CORR_FWD) * 0.5
    add("pipe_run", (mid_x, CEIL - 0.28, Z0 + 0.3), (0, 90, 0), (1, 1, 1), S, "_build_corridor")
    add("cable_bundle", (mid_x, CEIL - 0.22, Z1 - 0.3), (0, 90, 0), (1, 1, 1), S, "_build_corridor")
    x = X_CORR_AFT + 2.0
    while x < X_CORR_FWD:
        add("ceil_light_fixture", (x, CEIL, 11.9), (0, 0, 0), (1, 1, 1), S, "_build_corridor")
        x += 3.5
    # шлюз
    x = X_AIR_AFT
    while x < X_CORR_AFT:
        cx = x + 1.0
        add("floor_tile_wet", (cx, FLOOR - 0.008, 11.9), (0, 0, 0), (1, 1, 1.4), S, "_build_airlock")
        add("ceil_panel", (cx, CEIL + 0.012, 11.9), (0, 0, 0), (1, 1, 1.4), S, "_build_airlock")
        add("wall_panel_b", (cx, FLOOR, Z0), (0, 0, 0), (1, 1, 1), S, "_build_airlock")
        add("wall_panel_b", (cx, FLOOR, Z1), (0, 180, 0), (1, 1, 1), S, "_build_airlock")
        x += 2.0
    add("airlock_door", (X_AIR_AFT + 0.08, FLOOR + 1.15, 11.9), (0, 90, 0), (1, 1, 1), S, "_build_airlock")
    add("suit_rack", (-6.2, FLOOR, Z0 + 0.62), (0, 59, 0), (1, 1, 1), S, "_build_airlock")
    add("crt_terminal", (-4.62, FLOOR, Z0 + 0.62), (0, 0, 0), (1, 1, 1), S, "_build_airlock")
    add("pipe_valves", (-7.2, FLOOR + 1.6, Z1 - 0.25), (0, 180, 0), (1, 1, 1), S, "_build_airlock")
    add("crate", (-6.8, FLOOR, Z1 - 0.7), (0, 25, 0), (1, 1, 1), S, "_build_airlock")
    add("crate_small", (-6.3, FLOOR, Z1 - 0.9), (0, 70, 0), (1, 1, 1), S, "_build_airlock")
    # мостик
    x = X_CORR_FWD
    while x < X_BRIDGE_FWD - 0.5:
        cx = x + 1.0
        add("floor_tile", (cx, FLOOR - 0.008, 11.9), (0, 0, 0), (1, 1, 1.4), S, "_build_bridge")
        add("wall_panel_a", (cx, FLOOR, Z0), (0, 0, 0), (1, 1, 1), S, "_build_bridge")
        add("wall_panel_a", (cx, FLOOR, Z1), (0, 180, 0), (1, 1, 1), S, "_build_bridge")
        x += 2.0
    cx = X_CORR_FWD
    while cx < X_BRIDGE_FWD - 0.2:
        add("ceil_panel", (cx + 1.0, CEIL + 0.012, 11.9), (0, 0, 0), (1, 1, 1.4), S, "_build_bridge")
        cx += 2.0
    add("console_section", (13.55, FLOOR, 11.9), (0, -90, 0), (1, 1, 1), S, "_build_bridge")
    add("console_section", (11.35, FLOOR, 12.88), (0, 180, 0), (1, 1, 1), S, "_build_bridge")
    add("equip_keyboard", (13.17, FLOOR + 0.678, 12.18), (0, -90, 0), (1, 1, 1), S, "_build_bridge")
    add("equip_mug", (13.17, FLOOR + 0.674, 11.52), (0, 30, 0), (1, 1, 1), S, "_build_bridge")
    add("crt_terminal", (12.55, FLOOR, 10.72), (0, -71, 0), (1, 1, 1), S, "_build_bridge")
    add("poster", (10.6, FLOOR + 1.55, Z0 + 0.06), (0, 0, 0), (1, 1, 1), S, "_build_bridge")
    for pos in [(X_CORR_FWD + 0.3, CEIL, Z0 + 0.2), (X_CORR_FWD + 0.3, CEIL, Z1 - 0.2),
                (X_BRIDGE_FWD - 0.5, CEIL, Z0 + 0.2), (X_BRIDGE_FWD - 0.5, CEIL, Z1 - 0.2)]:
        add("lamp_red", pos, (0, 0, 0), (1, 1, 1), S, "_build_bridge")
    # каюта: пол/потолок/стены
    mid_z = (ROOM_Z0 + Z0) * 0.5
    depth = Z0 - ROOM_Z0
    for tx in [4.0, 5.9]:
        add("floor_tile", (tx, FLOOR - 0.008, mid_z), (0, 0, 0), (1, 1, depth / 2), S, "_build_quarters",
            "плитка каюты scale.z=1.65")
        add("ceil_panel", (tx, CEIL + 0.012, mid_z), (0, 0, 0), (1, 1, depth / 2), S, "_build_quarters")
    for wx in [4.0, 5.8]:
        add("wall_panel_a", (wx, FLOOR, ROOM_Z0), (0, 0, 0), (1, 1, 1), S, "_build_quarters", "задняя стена каюты")
    for wz in [8.2, 9.9]:
        add("wall_panel_a", (ROOM_X0, FLOOR, wz), (0, 90, 0), (1, 1, 1), S, "_build_quarters", "левый борт каюты")
        add("wall_panel_b", (ROOM_X1, FLOOR, wz), (0, -90, 0), (1, 1, 1), S, "_build_quarters", "правый борт каюты")
    add("door_frame", (ROOM_DOOR_X, FLOOR, Z0), (0, 0, 0), (1, 1, 1), S, "_build_quarters")
    add("ceil_light_fixture", (ROOM_DOOR_X, CEIL, mid_z), (0, 0, 0), (1, 1, 1), S, "_build_quarters")
    # build_props
    add("crate", (-1.8, FLOOR, Z0 + 0.5), (0, 15, 0), (1, 1, 1), S, "_build_props")
    add("crate_small", (-2.3, FLOOR, Z0 + 0.35), (0, 55, 0), (1, 1, 1), S, "_build_props")
    add("crate", (7.8, FLOOR, Z1 - 0.6), (0, -12, 0), (1, 1, 1), S, "_build_props")
    add("sign_warning", (1.2, FLOOR + 1.5, Z0 + 0.12), (0, 0, 0), (1, 1, 1), S, "_build_props")
    add("poster", (-2.9, FLOOR + 1.6, Z1 - 0.12), (0, 180, 0), (1, 1, 1), S, "_build_props")
    add("cable_bundle", (-0.5, FLOOR + 0.05, Z1 - 0.35), (0, 20, 0), (1, 1, 1), S, "_build_props")
    for i in range(10):
        add("equip_papers", (None, FLOOR + 0.01, None), (0, None, 0), (1, 1, 1), S, "_build_props",
            "10 случайных бумаг (scale не применён!)")
    for lx in [-2.5, 6.5]:
        add("lamp_red", (lx, CEIL, 11.9), (0, 0, 0), (1, 1, 1), S, "_build_props")
    # build_and_save: мебель каюты
    Q = Vector3 = lambda a, b, c: (a, b, c)
    qorg = ((ROOM_X0 + ROOM_X1) * 0.5, FLOOR, (ROOM_Z0 + Z0) * 0.5)
    qitems = [
        ("bunk_bed", (0.0, 0.0, -1.008), 0.0), ("locker", (1.305, 0.0, -0.85), -90.0),
        ("shelf_rack", (-1.422, 0.0, -0.45), 90.0), ("table_small", (0.62, 0.0, 0.35), -6.0),
        ("chair_folded", (1.477, 0.0, 0.95), -90.0), ("sleeping_bag", (-0.625, 0.0, 1.05), 4.0),
        ("wall_pipes_small", (-0.45, 2.18, -1.429), 0.0), ("vent_grille", (0.95, 2.05, -1.456), 0.0),
        ("cable_bundle_floor", (0.55, 0.0, 1.44), 0.0), ("papers_scattered", (0.68, 0.0, 1.02), 20.0),
        ("personal_photo_a", (0.31, 0.754, 0.28), 8.0), ("personal_photo_b", (0.9, 0.754, 0.4), -38.0),
        ("personal_mug", (0.78, 0.754, 0.16), 25.0), ("personal_notebook", (0.5, 0.754, 0.31), -12.0),
        ("personal_pencil", (0.38, 0.757, 0.47), 70.0), ("personal_boots", (1.26, 0.0, -0.32), 24.0),
        ("personal_toothbrush", (0.93, 0.754, 0.2), 100.0),
    ]
    for glb, off, rot in qitems:
        add(glb, (qorg[0] + off[0], qorg[1] + off[1], qorg[2] + off[2]), (0, rot, 0),
            (1, 1, 1), "build_and_save.gd", "_place_quarters_furniture")
    # POLISH_PROPS
    P = [
        ("equip_papers", (13.0, FLOOR + 0.696, 11.9), 35.0, (0.30, 0.01, 0.40)),
        ("cable_bundle", (11.9, FLOOR + 0.041, 10.9), 80.0, (1.6, 0.10, 0.10)),
        ("equip_mug", (3.95, FLOOR + 0.971, 12.75), -20.0, (0.1, 0.1, 0.1)),
        ("cable_bundle", (-3.2, FLOOR + 0.041, 12.95), 15.0, (2.0, 0.12, 0.12)),
        ("crate_small", (-7.15, FLOOR, 12.95), 35.0, (1, 1, 1)),
    ]
    for glb, pos, rot, sc in P:
        add(glb, pos, (0, rot, 0), sc, "build_and_save.gd", "_polish_props")
    return E

EXPECTED = expected_spawns()

def match_spawn(r):
    g = glb_name(r)
    best, bd = None, 1e9
    for e in EXPECTED:
        if e["glb"] != g:
            continue
        if e["pos"][0] is None:
            # рандомные бумаги: только по y/glb
            d = abs(r["pos"][1] - e["pos"][1]) + 0.5
        else:
            d = math.dist(r["pos"], e["pos"])
        if d < bd:
            bd, best = d, e
    if best is not None and bd < 0.35:
        best = dict(best)
        best["dist"] = round(bd, 3)
        return best
    return None

for r in meshes:
    r["spawn"] = match_spawn(r)

# --------------------------------------------------------------- интерьер ----
# границы = фактические видимые плоскости (по данным аудита):
#   port wall  z=10.4375, stbd wall z=13.3625, floor y=2.1106..2.1486, ceil y=4.7806
#   каюта: x 3.1375..6.6625, z 7.1375..10.4375
MAIN_X0, MAIN_X1 = -7.60, 14.66
MAIN_Z0, MAIN_Z1 = 10.432, 13.368
Q_X0, Q_X1, Q_Z0, Q_Z1 = 3.132, 6.668, 7.132, 10.442

def interior(p, margin=0.0):
    x, y, z = p
    if not (FLOOR - 0.02 - margin <= y <= CEIL + 0.02 + margin):
        return False
    if MAIN_X0 - margin <= x <= MAIN_X1 + margin and MAIN_Z0 - margin <= z <= MAIN_Z1 + margin:
        return True
    if Q_X0 - margin <= x <= Q_X1 + margin and Q_Z0 - margin <= z <= Q_Z1 + margin:
        return True
    return False

def plane_visible(p):
    ax = p["ax"]
    d = [0.0, 0.0, 0.0]
    d[ax] = -1.0 * p["sign"]          # computed normal = -actual (winding Godot)
    ucen = (p["u0"] + p["u1"]) / 2
    vcen = (p["v0"] + p["v1"]) / 2
    if ax == 0:
        pt = (p["coord"], ucen, vcen)
    elif ax == 1:
        pt = (vcen, p["coord"], ucen)
    else:
        pt = (ucen, vcen, p["coord"])
    return interior([pt[k] + d[k] * 0.15 for k in range(3)])

# ------------------------------------------------------------- z-fighting ---
TOL, MIN_AREA, MIN_WIDTH = 0.006, 0.0008, 0.002

def rect_overlap(p, q):
    uw = min(p["u1"], q["u1"]) - max(p["u0"], q["u0"])
    vw = min(p["v1"], q["v1"]) - max(p["v0"], q["v0"])
    if uw <= MIN_WIDTH or vw <= MIN_WIDTH:
        return None
    return uw * vw, uw, vw, max(p["u0"], q["u0"]), min(p["u1"], q["u1"]), max(p["v0"], q["v0"])

def uv_to_xyz(ax, coord, ucen, vcen):
    return ((coord, ucen, vcen), (vcen, coord, ucen), (ucen, vcen, coord))[ax]

pairs, hidden_pairs = [], []
n = len(meshes)
for i in range(n):
    A = meshes[i]
    if A["cat"] == "space" or not A["visible"] or not A["planes"]:
        continue
    for j in range(i + 1, n):
        B = meshes[j]
        if B["cat"] == "space" or not B["visible"] or not B["planes"]:
            continue
        best = best_hidden = None
        for p in A["planes"]:
            for q in B["planes"]:
                if p["ax"] != q["ax"] or p["sign"] != q["sign"]:
                    continue
                gap = abs(p["coord"] - q["coord"])
                if gap > TOL:
                    continue
                ro = rect_overlap(p, q)
                if ro is None:
                    continue
                area, uw, vw, u0, u1, v0q = ro
                if area < MIN_AREA:
                    continue
                ax = p["ax"]
                ucen = (u0 + u1) / 2
                v1q = min(p["v1"], q["v1"])
                vcen = (v0q + v1q) / 2
                coord = (p["coord"] + q["coord"]) / 2
                xyz = uv_to_xyz(ax, coord, ucen, vcen)
                rec = {"gap": gap, "area": area, "uw": uw, "vh": vw, "xyz": xyz, "ax": ax}
                if plane_visible(p) and plane_visible(q):
                    if best is None or (area, -gap) > (best["area"], -best["gap"]):
                        best = rec
                else:
                    if best_hidden is None or (area, -gap) > (best_hidden["area"], -best_hidden["gap"]):
                        best_hidden = rec
        if best is not None:
            pairs.append({"type": "zfight", "a": i, "b": j, "visible_side": True,
                          "ax": "XYZ"[best["ax"]], "gap_m": round(best["gap"], 5),
                          "overlap_m2": round(best["area"], 5),
                          "overlap_w": round(best["uw"], 4), "overlap_h": round(best["vh"], 4),
                          "xyz": [round(v, 4) for v in best["xyz"]]})
        elif best_hidden is not None:
            hidden_pairs.append({"type": "zfight_hidden", "a": i, "b": j, "visible_side": False,
                                 "ax": "XYZ"[best_hidden["ax"]], "gap_m": round(best_hidden["gap"], 5),
                                 "overlap_m2": round(best_hidden["area"], 5),
                                 "xyz": [round(v, 4) for v in best_hidden["xyz"]]})

# ------------------------------------------------- глубокие пересечения -----
def axis_overlap(a, b):
    lo = [max(a["min"][k], b["min"][k]) for k in range(3)]
    hi = [min(a["max"][k], b["max"][k]) for k in range(3)]
    return [hi[k] - lo[k] for k in range(3)], lo, hi

inter = []
for i in range(n):
    A = meshes[i]
    if A["cat"] == "space" or not A["visible"] or A["min_dim"] < 0.02:
        continue
    for j in range(i + 1, n):
        B = meshes[j]
        if B["cat"] == "space" or not B["visible"] or B["min_dim"] < 0.02:
            continue
        ov, lo, hi = axis_overlap(A["aabb"], B["aabb"])
        if min(ov) <= 0.01:
            continue
        c = [(lo[k] + hi[k]) / 2 for k in range(3)]
        inter.append({"type": "intersect", "a": i, "b": j,
                      "pen_m": round(min(ov), 4),
                      "volume_m3": round(ov[0] * ov[1] * ov[2], 4),
                      "ov": [round(x, 4) for x in ov],
                      "xyz": [round(x, 4) for x in c],
                      "visible_volume": interior(c, 0.02)})

dups = []
for i in range(n):
    A = meshes[i]
    for j in range(i + 1, n):
        B = meshes[j]
        if not A["glb"] or A["glb"] != B["glb"]:
            continue
        d = math.dist(A["pos"], B["pos"])
        if d < 0.02:
            dups.append({"type": "duplicate", "a": i, "b": j, "dist_m": round(d, 4), "xyz": A["pos"]})

# ------------------------------------------------------- декали/экраны ------
decals = []
for pr in probes:
    idx = pr["id"]
    r = meshes[idx]
    hf = pr["hit_front"] if pr["hit_front"].get("dist", -1) >= 0 else None
    hb = pr["hit_back"] if pr["hit_back"].get("dist", -1) >= 0 else None
    item = {"id": idx, "path": pr["path"], "name": r["name"], "cat": r["cat"],
            "zone": r["zone"], "center": [round(v, 4) for v in pr["center"]],
            "normal": [round(v, 3) for v in pr["normal"]],
            "front_m": round(hf["dist"], 4) if hf else None,
            "front_hit": hf["path"] if hf else None,
            "back_m": round(hb["dist"], 4) if hb else None,
            "back_hit": hb["path"] if hb else None}
    # классификация зазора
    if hf and hf["dist"] < 0.02:
        item["issue"] = "buried"       # поверхность впереди декали
    elif hb is None:
        item["issue"] = "floating_no_backing"
    elif hb["dist"] > 0.02:
        item["issue"] = "floating"
    elif hb["dist"] < 0.0005:
        item["issue"] = "coplanar"
    else:
        item["issue"] = "ok"
    decals.append(item)

# ------------------------------------------------------------- severity -----
STRUCT = {"floor", "ceil", "wall", "trim", "door", "shell"}
SEV = {"P0": 0, "P1": 1, "P2": 2, "P3": 3}

def sev_zfight(p, A, B):
    ca, cb = A["cat"], B["cat"]
    area, gap = p["overlap_m2"], p["gap_m"]
    cats = {ca, cb}
    if ca == "decal" and cb == "decal":
        return "P0" if area >= 0.01 else "P1"      # две наклейки друг на друге
    if ca == "decal" or cb == "decal":
        return "P1" if area >= 0.01 else "P2"
    if ca == "screen" or cb == "screen":
        return "P2"
    if ca == "light_fixture" or cb == "light_fixture":
        return "P2" if area >= 0.03 else "P3"
    if ca == "radio" or cb == "radio":
        return "P2"
    if ca == "equip" and cb == "equip":
        return "P2"
    structural = cats <= STRUCT | {"code_mesh"}
    if structural:
        if area >= 0.3 and gap <= 0.003:
            return "P0"
        if area >= 0.05 and gap <= 0.003:
            return "P0"
        if gap <= 0.0015 and area >= 0.02:
            return "P0"
        if area >= 0.05 and gap <= 0.006:
            return "P1"
        if area >= 0.01:
            return "P1" if gap <= 0.004 else "P2"
        return "P2"
    # проп/мебель vs конструкция или проп vs проп
    if area >= 0.05 and gap <= 0.003:
        return "P1"
    if area >= 0.01:
        return "P2"
    return "P3"

def sev_intersect(p, A, B):
    if not p["visible_volume"]:
        return "P3"           # пересечение спрятано в стене/полу/потолке
    ca, cb = A["cat"], B["cat"]
    cats = {ca, cb}
    pen = p["pen_m"]
    if cats <= STRUCT:
        return "P2"           # конструкция в конструкцию (обычно скрыто стыком)
    if ca == "shell" or cb == "shell":
        return "P1" if pen >= 0.05 else "P2"
    if pen >= 0.05:
        return "P1"
    return "P2"

for p in pairs:
    A, B = meshes[p["a"]], meshes[p["b"]]
    p.update({"cat_a": A["cat"], "cat_b": B["cat"],
              "zone": A["zone"] if A["zone"] == B["zone"] else A["zone"] + "+" + B["zone"],
              "path_a": A["path"], "path_b": B["path"],
              "tex_a": A["tex_sig"], "tex_b": B["tex_sig"],
              "diff_tex": A["tex_sig"] != B["tex_sig"],
              "spawn_a": (A["spawn"] or {}).get("func", ""),
              "spawn_b": (B["spawn"] or {}).get("func", ""),
              "spawn_note_a": (A["spawn"] or {}).get("note", ""),
              "spawn_note_b": (B["spawn"] or {}).get("note", "")})
    p["severity"] = sev_zfight(p, A, B)
for p in inter:
    A, B = meshes[p["a"]], meshes[p["b"]]
    p.update({"cat_a": A["cat"], "cat_b": B["cat"],
              "zone": A["zone"] if A["zone"] == B["zone"] else A["zone"] + "+" + B["zone"],
              "path_a": A["path"], "path_b": B["path"],
              "diff_tex": A["tex_sig"] != B["tex_sig"],
              "spawn_a": (A["spawn"] or {}).get("func", ""),
              "spawn_b": (B["spawn"] or {}).get("func", ""),
              "spawn_note_a": (A["spawn"] or {}).get("note", ""),
              "spawn_note_b": (B["spawn"] or {}).get("note", "")})
    p["severity"] = sev_intersect(p, A, B)

# ------------------------------------------------------------------ perf ----
vis = [r for r in meshes if r["visible"]]
surfaces = sum(r["surface_count"] for r in vis)
tri = sum(r["triangles"] for r in vis)
mat_keys = set()
for r in vis:
    for s in r["surfaces"]:
        mat_keys.add((s.get("cls"), s.get("name"), s.get("tex_key")))
by_zone = collections.defaultdict(lambda: {"meshes": 0, "surfaces": 0, "tris": 0})
by_cat = collections.defaultdict(lambda: {"instances": 0, "surfaces": 0, "tris": 0, "unique": set()})
for r in vis:
    z = by_zone[r["zone"]]; z["meshes"] += 1; z["surfaces"] += r["surface_count"]; z["tris"] += r["triangles"]
    c = by_cat[r["cat"]]; c["instances"] += 1; c["surfaces"] += r["surface_count"]; c["tris"] += r["triangles"]
    c["unique"].add(r["mesh_id"])
perf = {
    "mesh_instances_total": len(meshes),
    "mesh_instances_visible": len(vis),
    "unique_mesh_resources": len({r["mesh_id"] for r in meshes}),
    "surface_slots_visible": surfaces,
    "estimated_draw_calls_opaque": surfaces,
    "shadow_caster_surfaces": sum(r["surface_count"] for r in vis if r["cast_shadow"] != 0),
    "triangles_visible": tri,
    "nodes_total": meta["nodes_total"],
    "lights_total": len(lights), "lights_shadow": sum(1 for l in lights if l["shadow"]),
    "colliders": meta["colliders"],
    "unique_material_slots": len(mat_keys),
    "by_zone": {k: dict(v) for k, v in sorted(by_zone.items())},
    "by_cat": {k: {"instances": v["instances"], "surfaces": v["surfaces"], "tris": v["tris"],
                   "unique_meshes": len(v["unique"])} for k, v in sorted(by_cat.items())},
    "top_repeated": [[k, cnt] for k, cnt in
                     collections.Counter((m["glb"] or "CODE:" + m["name"]) for m in vis).most_common(20)],
    "dead_resources_main_tscn": {"ArrayMesh": 360, "ConcavePolygonShape3D": 140,
                                 "StandardMaterial3D": 7, "other": 4,
                                 "note": "неиспользуемые sub_resource в scenes/main.tscn — 511 шт., ~440 КБ"},
}

# -------------------------------------------------------------- сохранение --
z_sorted = sorted(pairs, key=lambda p: (SEV[p["severity"]], -p["overlap_m2"], p["gap_m"]))
i_sorted = sorted(inter, key=lambda p: (SEV[p["severity"]], -p["pen_m"]))
h_sorted = sorted(hidden_pairs, key=lambda p: -p["overlap_m2"])
out = {"zfight": z_sorted, "zfight_hidden_backfaces": h_sorted, "intersect": i_sorted,
       "duplicates": dups, "decals": decals, "perf": perf, "meta": meta,
       "meshes": meshes}
(BASE / "overlaps.json").write_text(json.dumps(out, ensure_ascii=False, indent=1), encoding="utf-8")

with (BASE / "overlaps.csv").open("w", newline="", encoding="utf-8-sig") as f:
    w = csv.writer(f, delimiter=";")
    w.writerow(["type", "severity", "zone", "obj_a", "cat_a", "spawn_a", "obj_b", "cat_b", "spawn_b",
                "axis", "gap_mm", "overlap_m2", "pen_m", "volume_m3", "x", "y", "z", "diff_texture"])
    for p in z_sorted + i_sorted:
        w.writerow([p["type"], p["severity"], p["zone"], p["path_a"], p["cat_a"], p["spawn_a"],
                    p["path_b"], p["cat_b"], p["spawn_b"], p.get("ax", ""),
                    round(p.get("gap_m", 0) * 1000, 2), p.get("overlap_m2", ""),
                    p.get("pen_m", ""), p.get("volume_m3", ""), *p["xyz"], p.get("diff_tex", "")])
    for d in dups:
        A, B = meshes[d["a"]], meshes[d["b"]]
        w.writerow(["duplicate", "P1", A["zone"], A["path"], A["cat"], "", B["path"], B["cat"], "",
                    "", "", "", "", "", *d["xyz"], ""])

# ------------------------------------------------------------- консоль ------
def show_pairs(lst, title, limit=10000, sev_max="P1"):
    print("\n=== " + title + " ===")
    cnt = collections.Counter(p["severity"] for p in lst)
    print(dict(cnt))
    shown = 0
    for p in lst:
        if SEV[p["severity"]] > SEV[sev_max]:
            break
        if shown >= limit:
            break
        shown += 1
        A, B = meshes[p["a"]], meshes[p["b"]]
        extra = (f'area={p.get("overlap_m2"):.3f}m2 gap={p.get("gap_m",0)*1000:.1f}mm'
                 if p["type"] == "zfight" else f'pen={p.get("pen_m"):.3f} '
                 f'vol={p.get("volume_m3")} vis={p.get("visible_volume")}')
        print(f'{p["severity"]} {p["zone"]:22s} {extra} {p.get("ax","")} @{p["xyz"]}')
        print(f'    A [{A["cat"]:11s}] {A["path"][-56:]}  {A["spawn"]["func"] if A["spawn"] else ""}')
        print(f'    B [{B["cat"]:11s}] {B["path"][-56:]}  {B["spawn"]["func"] if B["spawn"] else ""}')

show_pairs(z_sorted, "ZFIGHT P0/P1", sev_max="P1")
show_pairs(i_sorted, "INTERSECT P1 (видимые объёмы)", sev_max="P1")

print("\n=== HIDDEN backface coplanar (не видно изнутри, топ-15) ===")
for p in h_sorted[:15]:
    A, B = meshes[p["a"]], meshes[p["b"]]
    print(f'area={p["overlap_m2"]:.3f} {p["ax"]} @{p["xyz"]} [{A["cat"]}] {A["path"][-40:]} vs [{B["cat"]}] {B["path"][-40:]}')

print("\n=== DECALS ===")
for d in decals:
    if d["cat"] in ("decal", "screen") or d["name"].startswith("@"):
        print(f'{d["issue"]:18s} {d["name"][:24]:24s} back={d["back_m"]} front={d["front_m"]} '
              f'center={d["center"]} hit_back={(d["back_hit"] or "").split("/")[-1]}')

print("\n=== PERF ===")
print(json.dumps({k: perf[k] for k in ("mesh_instances_total", "unique_mesh_resources",
                                       "surface_slots_visible", "triangles_visible",
                                       "lights_total", "lights_shadow",
                                       "unique_material_slots")}, ensure_ascii=False, indent=1))
print("by_zone:", json.dumps(perf["by_zone"], ensure_ascii=False))
print("\n=== UNMATCHED meshes (нет привязки к спавну) ===")
for r in meshes:
    if r["spawn"] is None and r["cat"] not in ("space", "decal", "screen"):
        print(f'{r["cat"]:10s} {r["path"][:70]:70s} pos={[round(v,2) for v in r["pos"]]} glb={glb_name(r)}')
