import sys, importlib
sys.path.insert(0, "D:/Echoes-of-the-void-main/tools/blender")
import bl_lib
importlib.reload(bl_lib)
from bl_lib import *

olive = mat("LockerOlive", (0.16, 0.24, 0.15), 0.75, 0.25)
olive_dk = mat("LockerDark", (0.09, 0.14, 0.09), 0.8, 0.2)
rust = mat("Rust", (0.30, 0.15, 0.07), 0.95)
steel = mat("PropSteel", (0.48, 0.48, 0.46), 0.45, 0.85)
dark = mat("PropDark", (0.07, 0.07, 0.07), 0.8, 0.3)
yellow = mat("SafetyYellow", (0.75, 0.55, 0.08), 0.7)
hazard_bk = mat("HazardBlack", (0.04, 0.04, 0.04), 0.8)
cream = mat("PanelCream", (0.62, 0.60, 0.52), 0.8)
white = mat("DialWhite", (0.78, 0.76, 0.68), 0.6)
red_l = mat("LampRed", (0.6, 0.05, 0.04), 0.4, emit=(1.0, 0.1, 0.05), emit_strength=1.6)
green_l = mat("LampGreen", (0.1, 0.5, 0.15), 0.4, emit=(0.15, 1.0, 0.3), emit_strength=1.6)
rubber = mat("Rubber2", (0.05, 0.05, 0.05), 0.95)
orange = mat("Orange2", (0.72, 0.30, 0.06), 0.8)
leather = mat("Strap", (0.18, 0.11, 0.06), 0.9)

SUIT_KEEP = ("SpaceSuit", "Helmet", "Camera", "Light", "PreviewCam")
for o in list(bpy.data.objects):
    if o.type == "MESH" and o.name not in SUIT_KEEP:
        bpy.data.objects.remove(o, do_unlink=True)

shown = []


def finish(o, fname, slot, size=1024):
    ground(o)
    bake_wear(o, fname.replace(".glb", "_tex"), size=size, dirt=0.75)
    export(o, fname, display_loc=slot)
    shown.append(o)


# ------------------------------------------------------------ suit locker --
def locker(open_door):
    W, D, H = 0.74, 0.56, 2.05
    p = []
    p.append(box("Back", (W, 0.025, H), (0, D / 2 - 0.0125, H / 2), olive, 0.006))
    p.append(box("SideL", (0.025, D, H), (-W / 2 + 0.0125, 0, H / 2), olive, 0.006))
    p.append(box("SideR", (0.025, D, H), (W / 2 - 0.0125, 0, H / 2), olive, 0.006))
    p.append(box("Top", (W, D, 0.03), (0, 0, H - 0.015), olive_dk, 0.006))
    p.append(box("Bottom", (W, D, 0.06), (0, 0, 0.03), olive_dk, 0.006))
    p.append(box("Plinth", (W - 0.06, D - 0.06, 0.04), (0, 0, 0.02), dark, 0.004))
    p.append(box("HookBar", (W - 0.06, 0.03, 0.03), (0, 0.18, H - 0.15), steel, 0.004))
    for i in range(3):
        p.append(cyl("Hook%d" % i, 0.012, 0.09, (-0.2 + i * 0.2, 0.15, H - 0.19), steel, rot=(math.pi / 2, 0, 0)))
    p.append(box("Shelf", (W - 0.06, D - 0.12, 0.02), (0, 0.06, H - 0.30), steel, 0.004))
    p.append(box("ShelfFront", (W - 0.06, 0.015, 0.05), (0, -0.20, H - 0.28), steel, 0.004))
    for i in range(6):
        p.append(box("Frame%d" % i, (0.04, 0.03, 0.04), (-W / 2 + 0.03, -D / 2 + 0.01, 0.3 + i * 0.3), olive_dk, 0.004))
    p.append(box("Label", (0.14, 0.01, 0.05), (0.0, D / 2 - 0.03, 1.1), yellow, 0.002))
    # door: hinged on the left edge
    dw, dh = W - 0.02, H - 0.08
    door_parts = [box("Door", (dw, 0.025, dh), (dw / 2, 0, dh / 2 + 0.06), olive, 0.007)]
    for i in range(5):
        door_parts.append(box("Vent%d" % i, (dw - 0.3, 0.012, 0.015), (dw / 2, -0.015, dh - 0.15 - i * 0.055), dark, 0.002))
    door_parts.append(box("Handle", (0.03, 0.05, 0.16), (dw - 0.06, -0.03, 1.0), steel, 0.006))
    door_parts.append(box("Plate", (0.18, 0.012, 0.07), (dw / 2, -0.02, dh - 0.45), yellow, 0.003))
    door_parts.append(box("PlateStripe", (0.18, 0.014, 0.012), (dw / 2, -0.022, dh - 0.495), hazard_bk, 0.001))
    for i in range(9):
        door_parts += bolts("Rv%d_" % i, steel, [(0.035, -0.016, 0.2 + i * 0.2), (dw - 0.035, -0.016, 0.2 + i * 0.2)], 0.007, 0.006)
    for i in range(3):
        door_parts.append(box("Hinge%d" % i, (0.03, 0.03, 0.12), (0.012, -0.022, 0.35 + i * 0.7), steel, 0.004))
    door_parts.append(box("Rib1", (dw - 0.1, 0.01, 0.02), (dw / 2, -0.016, 0.75), olive_dk, 0.002))
    door_parts.append(box("Rib2", (dw - 0.1, 0.01, 0.02), (dw / 2, -0.016, 1.45), olive_dk, 0.002))
    door = join(door_parts, "DoorGroup")
    # pivot at the hinge edge (x = 0, y = 0 of the door) -> set the object origin there and rotate about Z
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.select_all(action="DESELECT")
    door.select_set(True)
    bpy.context.view_layer.objects.active = door
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    door.location = (-W / 2 + 0.005, -D / 2 + 0.01, 0)
    door.rotation_euler = (0, 0, math.radians(-105) if open_door else 0)
    bpy.ops.object.select_all(action="DESELECT")
    door.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=True, scale=False)
    p.append(door)
    # rust streaks near the bottom
    p.append(box("RustL", (0.2, 0.005, 0.25), (-0.18, -D / 2 - 0.004 if not open_door else D / 2 - 0.03, 0.30), rust, 0.001))
    return join(p, "Locker")


lk_open = locker(True)
finish(lk_open, "airlock_locker_open.glb", (2.2, 0.0, 0.0))
lk_closed = locker(False)
finish(lk_closed, "airlock_locker_closed.glb", (3.4, 0.0, 0.0))


# ------------------------------------------------------------ tether coil --
def carabiner(name, at, rot=(0, 0, 0), scale=1.0):
    s = scale
    parts = [
        torus(name + "Ring", 0.04 * s, 0.0075 * s, at, steel, rot=rot, maj_seg=20, min_seg=6),
        box(name + "Gate", (0.012 * s, 0.014 * s, 0.05 * s), (at[0] + 0.04 * s, at[1], at[2]), orange, 0.002),
    ]
    parts[0].scale = (0.62, 1.0, 1.0)
    bpy.context.view_layer.objects.active = parts[0]
    parts[0].select_set(True)
    bpy.ops.object.transform_apply(scale=True)
    parts[0].select_set(False)
    return parts


tether_parts = []
for i in range(6):
    tether_parts.append(torus("Loop%d" % i, 0.21 - i * 0.004, 0.014, (0, 0, 0.016 + i * 0.027), yellow, maj_seg=36, min_seg=7))
tether_parts.append(tube("LeadOut", [(0.21, 0, 0.05), (0.42, 0.05, 0.03), (0.66, -0.10, 0.015), (0.80, -0.05, 0.015)], 0.014, yellow))
tether_parts.append(box("Tag", (0.07, 0.01, 0.05), (0.0, -0.215, 0.10), orange, 0.002))
tether_parts += carabiner("CarA", (0.83, -0.05, 0.03), rot=(math.pi / 2, 0, 0.3), scale=1.3)
tether_parts.append(tube("Tie", [(0.15, -0.15, 0.03), (0.0, -0.22, 0.09), (-0.15, -0.15, 0.14)], 0.008, leather))
tether = join(tether_parts, "TetherCoil")
finish(tether, "airlock_tether_coil.glb", (0.0, 2.2, 0.0))

# ------------------------------------------------------- carabiner rack ----
rk = [box("Plate", (0.62, 0.025, 0.30), (0, 0.0, 0.15), dark, 0.006),
      box("Rail", (0.58, 0.03, 0.025), (0, -0.02, 0.27), steel, 0.004),
      box("Label", (0.20, 0.012, 0.05), (0, -0.016, 0.06), yellow, 0.002)]
for i in range(5):
    x = -0.22 + i * 0.11
    rk.append(cyl("Peg%d" % i, 0.008, 0.05, (x, -0.04, 0.27), steel, rot=(math.pi / 2, 0, 0)))
    rk += carabiner("Rk%d" % i, (x, -0.065, 0.205), rot=(math.pi / 2, 0, 0), scale=1.25)
rack = join(rk, "CarabinerRack")
finish(rack, "airlock_carabiner_rack.glb", (1.4, 2.2, 0.0))

# ------------------------------------------------------ pressure panel -----
pp = [box("Body", (0.64, 0.09, 0.52), (0, 0.0, 0.26), cream, 0.012),
      box("Face", (0.58, 0.012, 0.46), (0, -0.05, 0.26), dark, 0.006),
      box("HazardTop", (0.58, 0.014, 0.03), (0, -0.058, 0.47), yellow, 0.002)]
for i in range(7):
    pp.append(box("Hz%d" % i, (0.035, 0.016, 0.031), (-0.255 + i * 0.085, -0.058, 0.47), hazard_bk, 0.001, rot=(0, 0, 0.45)))
for i, x in enumerate((-0.15, 0.15)):
    pp.append(cyl("DialRim%d" % i, 0.095, 0.03, (x, -0.062, 0.30), steel, rot=(math.pi / 2, 0, 0)))
    pp.append(cyl("DialFace%d" % i, 0.082, 0.012, (x, -0.082, 0.30), white, rot=(math.pi / 2, 0, 0)))
    pp.append(box("Needle%d" % i, (0.006, 0.006, 0.065), (x - 0.02 + i * 0.05, -0.092, 0.31), red_l if i else dark, 0.001, rot=(0, 0.6 - i * 1.4, 0)))
for i in range(4):
    pp.append(cyl("Sw%d" % i, 0.014, 0.05, (-0.21 + i * 0.14, -0.07, 0.115), steel, rot=(math.pi / 2, 0, 0)))
    pp.append(sphere("Knob%d" % i, 0.018, (-0.21 + i * 0.14, -0.098, 0.115), dark))
pp.append(cyl("LampG", 0.024, 0.02, (-0.22, -0.065, 0.04), green_l, rot=(math.pi / 2, 0, 0)))
pp.append(cyl("LampR", 0.024, 0.02, (0.22, -0.065, 0.04), red_l, rot=(math.pi / 2, 0, 0)))
pp.append(box("LabelPlate", (0.26, 0.012, 0.05), (0, -0.062, 0.04), yellow, 0.002))
pp += bolts("PB", steel, [(-0.29, -0.063, 0.48), (0.29, -0.063, 0.48), (-0.29, -0.063, 0.04), (0.29, -0.063, 0.04)], 0.011, 0.01)
for i in range(3):
    pp.append(box("Slot%d" % i, (0.16, 0.012, 0.016), (0.0, -0.06, 0.20 + i * 0.0), dark, 0.002)) if i == 0 else None
pp.append(tube("Cable", [(0.30, -0.02, 0.02), (0.42, -0.06, -0.02), (0.55, -0.03, 0.04)], 0.012, rubber))
panel = join(pp, "PressurePanel")
finish(panel, "airlock_pressure_panel.glb", (2.6, 2.2, 0.0))

# ----------------------------------------------------- magnetic boots ------
def boot(x, yaw):
    parts = [
        box("Sole", (0.13, 0.30, 0.045), (x, 0, 0.0225), rubber, 0.015),
        box("MagPlate", (0.11, 0.22, 0.03), (x, 0.0, 0.06), steel, 0.006),
        box("Foot", (0.12, 0.26, 0.10), (x, -0.01, 0.125), mat("BootGrey", (0.38, 0.38, 0.36), 0.7, 0.2), 0.03),
        cyl("Leg", 0.065, 0.20, (x, 0.07, 0.28), mat("BootGrey", (0.38, 0.38, 0.36), 0.7, 0.2)),
        box("Strap", (0.14, 0.06, 0.025), (x, -0.04, 0.17), orange, 0.006),
        box("Buckle", (0.04, 0.02, 0.03), (x, -0.075, 0.17), steel, 0.003),
        torus("Cuff", 0.068, 0.014, (x, 0.07, 0.385), steel),
    ]
    return parts


bp = boot(-0.09, 0) + boot(0.09, 0)
boots = join(bp, "MagBoots")
finish(boots, "airlock_mag_boots.glb", (3.8, 2.2, 0.0))

# ---------------------------------------------------------- toolbox --------
tb = [box("Base", (0.50, 0.22, 0.12), (0, 0, 0.06), mat("ToolRed", (0.45, 0.08, 0.06), 0.65, 0.3), 0.012),
      box("Inner", (0.46, 0.18, 0.10), (0, 0, 0.09), dark, 0.004),
      box("Tray", (0.44, 0.08, 0.025), (0, -0.04, 0.115), steel, 0.004),
      box("LidBack", (0.50, 0.02, 0.17), (0, 0.13, 0.215), mat("ToolRed", (0.45, 0.08, 0.06), 0.65, 0.3), 0.01, rot=(0.2, 0, 0)),
      box("Handle", (0.22, 0.02, 0.02), (0, 0.135, 0.31), steel, 0.004, rot=(0.2, 0, 0))]
tb.append(box("Wrench", (0.30, 0.025, 0.012), (-0.02, -0.03, 0.135), steel, 0.004, rot=(0, 0, 0.12)))
tb.append(torus("WrenchHead", 0.026, 0.009, (-0.17, -0.025, 0.135), steel))
tb.append(cyl("Driver", 0.011, 0.20, (0.05, 0.02, 0.134), orange, rot=(0, math.pi / 2, 0.1)))
tb.append(cyl("DriverShaft", 0.005, 0.12, (-0.1, 0.02, 0.134), steel, rot=(0, math.pi / 2, 0.1)))
tb.append(torus("TapeRoll", 0.04, 0.016, (0.17, -0.04, 0.145), yellow, rot=(math.pi / 2, 0, 0)))
tb.append(box("Hammer", (0.20, 0.03, 0.03), (0.0, 0.05, 0.14), mat("Wood", (0.3, 0.18, 0.08), 0.9), 0.004, rot=(0, 0, -0.1)))
tb.append(box("HammerHead", (0.07, 0.04, 0.045), (0.1, 0.05, 0.145), steel, 0.005))
tb.append(box("Latch", (0.04, 0.02, 0.05), (0.0, -0.115, 0.10), steel, 0.004))
toolbox = join(tb, "Toolbox")
finish(toolbox, "airlock_toolbox.glb", (4.8, 2.2, 0.0))

preview(shown + [bpy.data.objects.get("SpaceSuit")], "D:/Echoes-of-the-void-main/.codex_qa/audit_2026-11-23/blender/props.png",
        size=(1400, 900), cam_dir=(0.4, -1.8, 0.9))
bl_lib.show_in_viewport("SOLID")
print("PROPS_OK", [o.name for o in shown])
