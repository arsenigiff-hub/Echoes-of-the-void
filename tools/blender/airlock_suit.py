import sys, importlib
sys.path.insert(0, "D:/Echoes-of-the-void-main/tools/blender")
import bl_lib
importlib.reload(bl_lib)
from bl_lib import *

for o in list(bpy.data.objects):
    if o.type == "MESH":
        bpy.data.objects.remove(o, do_unlink=True)

white = mat("SuitWhite", (0.60, 0.58, 0.52), 0.85)
white2 = mat("SuitCream", (0.52, 0.50, 0.44), 0.9)
grey = mat("SuitGrey", (0.30, 0.30, 0.29), 0.65, 0.35)
orange = mat("SuitOrange", (0.70, 0.28, 0.05), 0.8)
visor = mat("Visor", (0.015, 0.02, 0.025), 0.06, 0.7)
rubber = mat("Rubber", (0.04, 0.04, 0.04), 0.95)
steel = mat("SuitSteel", (0.46, 0.46, 0.44), 0.45, 0.85)
brass = mat("SuitBrass", (0.50, 0.38, 0.15), 0.5, 0.8)
lamp_g = mat("SuitLamp", (0.1, 0.55, 0.18), 0.5, emit=(0.1, 0.9, 0.3), emit_strength=1.2)
lamp_r = mat("SuitLampR", (0.5, 0.05, 0.04), 0.5, emit=(1.0, 0.1, 0.05), emit_strength=1.0)


def glove(side, at):
    """Mitten-style glove with a segmented thumb and four fingers."""
    ax, ay, az = at
    p = [box("Palm", (0.085, 0.045, 0.085), (ax, ay, az), rubber, 0.012)]
    for i in range(4):
        fx = ax + (i - 1.5) * 0.021
        L = (0.055, 0.058, 0.052, 0.04)[i]
        p.append(cyl("F%da" % i, 0.0105, L, (fx, ay, az - 0.042 - L / 2), rubber, verts=8))
        p.append(cyl("F%db" % i, 0.0095, L * 0.7, (fx, ay - 0.004, az - 0.042 - L - L * 0.3), rubber, verts=8, rot=(0.25, 0, 0)))
    p.append(cyl("Thumb", 0.012, 0.05, (ax + side * 0.055, ay - 0.012, az - 0.012), rubber, rot=(0, side * 0.9, 0), verts=8))
    p.append(cyl("Cuff", 0.052, 0.03, (ax, ay, az + 0.055), steel, verts=16))
    p += bolts("CB", steel, ring_pts((ax, ay, az + 0.055), 0.052, 8, "XY"), 0.005, 0.01, "Z")
    return p


def boot(x):
    p = [box("Sole", (0.135, 0.30, 0.025), (x, -0.02, 0.0125), rubber, 0.01)]
    for i in range(6):   # tread blocks
        p.append(box("Tread%d" % i, (0.125, 0.025, 0.012), (x, -0.13 + i * 0.047, 0.03), rubber, 0.003))
    p.append(box("Foot", (0.125, 0.26, 0.09), (x, -0.03, 0.082), grey, 0.025))
    p.append(box("Toe", (0.12, 0.07, 0.07), (x, -0.15, 0.065), white2, 0.025))
    p.append(box("Ankle", (0.12, 0.14, 0.11), (x, 0.01, 0.17), white, 0.03))
    p.append(box("Strap", (0.135, 0.05, 0.02), (x, -0.07, 0.115), orange, 0.005))
    p.append(box("Buckle", (0.035, 0.012, 0.03), (x, -0.098, 0.115), steel, 0.003))
    p.append(torus("BootRing", 0.075, 0.014, (x, 0.012, 0.235), steel, maj_seg=18))
    return p


def build_helmet(prefix="H", at=(0, 0, 0)):
    ax, ay, az = at
    parts = [
        sphere(prefix + "Shell", 0.185, (ax, ay, az + 0.19), white, scale=(1, 1.06, 1.03), seg=32, rings=20),
        sphere(prefix + "Visor", 0.158, (ax, ay - 0.085, az + 0.195), visor, scale=(1.02, 0.72, 0.84), seg=32, rings=20),
        torus(prefix + "VisorRim", 0.152, 0.012, (ax, ay - 0.115, az + 0.195), steel, rot=(math.pi / 2, 0, 0), maj_seg=32),
        torus(prefix + "Neck", 0.125, 0.026, (ax, ay + 0.012, az + 0.035), steel, maj_seg=24),
        cyl(prefix + "NeckSeal", 0.118, 0.04, (ax, ay + 0.012, az + 0.0), rubber, verts=24),
        box(prefix + "LampL", (0.045, 0.05, 0.035), (ax - 0.165, ay - 0.1, az + 0.30), grey, 0.008),
        box(prefix + "LampR", (0.045, 0.05, 0.035), (ax + 0.165, ay - 0.1, az + 0.30), grey, 0.008),
        cyl(prefix + "LensL", 0.016, 0.012, (ax - 0.165, ay - 0.13, az + 0.30), lamp_g, rot=(math.pi / 2, 0, 0), verts=10),
        cyl(prefix + "LensR", 0.016, 0.012, (ax + 0.165, ay - 0.13, az + 0.30), lamp_g, rot=(math.pi / 2, 0, 0), verts=10),
        box(prefix + "TopStripe", (0.11, 0.018, 0.03), (ax, ay - 0.18, az + 0.365), orange, 0.004),
        cyl(prefix + "Antenna", 0.004, 0.14, (ax + 0.09, ay + 0.06, az + 0.43), steel, verts=6),
        box(prefix + "Vent", (0.06, 0.012, 0.025), (ax, ay + 0.19, az + 0.2), grey, 0.003),
    ]
    parts += bolts(prefix + "RB", steel, ring_pts((ax, ay - 0.115, az + 0.195), 0.152, 14, "XZ"), 0.005, 0.008, "Y")
    return parts


def build_suit():
    p = []
    for s, name in ((-1, "L"), (1, "R")):
        x = s * 0.105
        p.append(cyl("Thigh" + name, 0.082, 0.34, (x, 0, 0.78), white, verts=18))
        p += ribbed("KneeRib" + name, grey, (x, -0.005, 0.57), 0.078, 0.10, 4)
        p.append(cyl("Calf" + name, 0.074, 0.30, (x, 0, 0.40), white, verts=18))
        p.append(box("ThighPad" + name, (0.11, 0.03, 0.17), (x, -0.075, 0.82), white2, 0.012))
        p.append(box("KneePad" + name, (0.10, 0.03, 0.085), (x, -0.085, 0.57), orange, 0.012))
        p.append(box("ShinPlate" + name, (0.09, 0.025, 0.17), (x, -0.075, 0.40), white2, 0.01))
        p += bolts("ShinB" + name, steel, [(x - 0.03, -0.09, 0.34), (x + 0.03, -0.09, 0.34), (x - 0.03, -0.09, 0.46), (x + 0.03, -0.09, 0.46)], 0.006, 0.006)
        p += boot(x)
    p.append(box("Pelvis", (0.34, 0.20, 0.15), (0, 0, 0.99), white, 0.045))
    p.append(box("Belt", (0.35, 0.21, 0.04), (0, 0, 1.06), orange, 0.01))
    p.append(box("BeltBuckle", (0.07, 0.02, 0.04), (0, -0.108, 1.06), steel, 0.006))
    for i in range(4):
        p.append(box("Loop%d" % i, (0.03, 0.02, 0.04), (-0.12 + i * 0.08, -0.108, 1.06), grey, 0.004))
    p.append(box("Torso", (0.44, 0.25, 0.50), (0, 0, 1.33), white, 0.055))
    p.append(box("Collar", (0.22, 0.17, 0.05), (0, 0, 1.60), steel, 0.012))
    # panel seams on the torso (thin dark grooves) and shoulder yoke
    for sx in (-0.11, 0.11):
        p.append(box("Seam", (0.008, 0.012, 0.42), (sx, -0.13, 1.33), grey, 0.001))
    p.append(box("SeamH", (0.38, 0.012, 0.008), (0, -0.13, 1.18), grey, 0.001))
    p.append(box("YokeL", (0.14, 0.26, 0.04), (-0.16, 0, 1.56), white2, 0.012, rot=(0, 0.35, 0)))
    p.append(box("YokeR", (0.14, 0.26, 0.04), (0.16, 0, 1.56), white2, 0.012, rot=(0, -0.35, 0)))
    # chest control box: screen, buttons, dials, lamps
    p.append(box("ChestBox", (0.25, 0.055, 0.16), (0, -0.14, 1.36), grey, 0.014))
    p.append(box("ChestScreen", (0.10, 0.012, 0.05), (-0.045, -0.172, 1.40), mat("Screen", (0.03, 0.08, 0.04), 0.3, emit=(0.1, 0.5, 0.2), emit_strength=0.4), 0.003))
    for i in range(4):
        p.append(box("Btn%d" % i, (0.026, 0.016, 0.026), (-0.075 + i * 0.05, -0.172, 1.32), orange if i == 2 else steel, 0.004))
    p.append(cyl("Dial", 0.026, 0.014, (0.07, -0.172, 1.40), white, rot=(math.pi / 2, 0, 0), verts=14))
    p.append(cyl("LampG", 0.011, 0.012, (0.09, -0.172, 1.32), lamp_g, rot=(math.pi / 2, 0, 0), verts=8))
    p.append(cyl("LampR", 0.011, 0.012, (0.115, -0.172, 1.32), lamp_r, rot=(math.pi / 2, 0, 0), verts=8))
    p += bolts("ChestB", steel, [(-0.115, -0.172, 1.43), (0.115, -0.172, 1.43), (-0.115, -0.172, 1.29), (0.115, -0.172, 1.29)], 0.006, 0.006)
    # shoulder patches and ID tab
    p.append(box("PatchL", (0.012, 0.09, 0.08), (-0.30, 0, 1.5), orange, 0.004))
    p.append(box("Tag", (0.07, 0.012, 0.03), (0.13, -0.132, 1.52), white2, 0.003))
    # backpack life support
    p.append(box("Pack", (0.40, 0.18, 0.54), (0, 0.215, 1.33), grey, 0.04))
    p.append(box("PackTop", (0.34, 0.14, 0.09), (0, 0.215, 1.66), white, 0.025))
    p.append(box("PackPlate", (0.30, 0.012, 0.30), (0, 0.31, 1.30), white2, 0.006))
    for i in range(3):
        p.append(cyl("PackDial%d" % i, 0.022, 0.014, (-0.09 + i * 0.09, 0.32, 1.40), white, rot=(math.pi / 2, 0, 0), verts=12))
    for sx in (-0.11, 0.11):
        p.append(cyl("O2Tank", 0.052, 0.40, (sx, 0.345, 1.34), steel, verts=18))
        p.append(cyl("TankCap", 0.036, 0.04, (sx, 0.345, 1.56), brass, verts=14))
        p.append(torus("TankBand", 0.054, 0.007, (sx, 0.345, 1.22), grey, maj_seg=16))
        p.append(torus("TankBand2", 0.054, 0.007, (sx, 0.345, 1.44), grey, maj_seg=16))
    p.append(box("PackHandle", (0.16, 0.03, 0.03), (0, 0.33, 1.68), rubber, 0.006))
    for s, name in ((-1, "L"), (1, "R")):
        x = s * 0.30
        p.append(sphere("Shoulder" + name, 0.10, (s * 0.255, 0, 1.51), white, scale=(1, 1, 0.95)))
        p += ribbed("ShoulderRib" + name, grey, (s * 0.265, 0, 1.43), 0.073, 0.08, 3, tilt=(0, s * 0.18, 0))
        p.append(cyl("UpperArm" + name, 0.068, 0.22, (s * 0.295, 0, 1.30), white, rot=(0, s * 0.16, 0), verts=18))
        p += ribbed("ElbowRib" + name, grey, (s * 0.325, 0, 1.15), 0.065, 0.09, 4, tilt=(0, s * 0.12, 0))
        p.append(cyl("Forearm" + name, 0.062, 0.24, (s * 0.35, -0.005, 0.99), white, rot=(0, s * 0.10, 0), verts=18))
        p.append(box("ArmPad" + name, (0.04, 0.10, 0.11), (s * 0.385, -0.02, 1.22), white2, 0.012))
        p.append(torus("ArmStripe" + name, 0.07, 0.014, (s * 0.31, 0, 1.22), orange, maj_seg=20))
        p += glove(s, (s * 0.372, -0.012, 0.80))
    for s in (-1, 1):
        pts = [(s * 0.07, -0.17, 1.40), (s * 0.20, -0.17, 1.54), (s * 0.26, 0.00, 1.64), (s * 0.12, 0.2, 1.64)]
        p.append(tube("Hose", pts, 0.016, rubber, res=8))
        p.append(cyl("Conn", 0.022, 0.035, (s * 0.07, -0.17, 1.40), steel, verts=10, rot=(math.pi / 2, 0, 0)))
        p.append(cyl("ConnB", 0.022, 0.035, (s * 0.12, 0.2, 1.62), steel, verts=10, rot=(math.pi / 2, 0, 0)))
    p.append(tube("Tether", [(0.0, -0.12, 1.07), (0.07, -0.16, 0.96), (0.02, -0.17, 0.90)], 0.012, mat("TetherYellow", (0.65, 0.5, 0.08), 0.8)))
    p += build_helmet("Hm", (0, -0.005, 1.62))
    return p


suit = join(build_suit(), "SpaceSuit")
ground(suit)
suit.location.z += 0.04
bpy.context.view_layer.update()
bpy.ops.object.select_all(action="DESELECT")
suit.select_set(True)
bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)

helmet = join(build_helmet("B", (0, 0, 0.0)), "Helmet")
ground(helmet)

bake_wear(suit, "airlock_suit_tex", size=2048, dirt=0.7)
bake_wear(helmet, "airlock_helmet_tex", size=1024, dirt=0.7)
export(suit, "airlock_suit.glb", display_loc=(0.0, 0.0, 0.0))
export(helmet, "airlock_helmet.glb", display_loc=(1.3, 0.0, 0.0))
bpy.context.scene.render.engine = "BLENDER_WORKBENCH"
preview([suit, helmet], "D:/Echoes-of-the-void-main/.codex_qa/audit_2026-11-23/blender/suit.png",
        size=(1100, 900), cam_dir=(0.5, -2.6, 0.35))
bl_lib.show_in_viewport("SOLID")
print("SUIT_OK", len(suit.data.polygons))
