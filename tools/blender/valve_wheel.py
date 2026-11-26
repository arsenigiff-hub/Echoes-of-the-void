"""Hatch hand wheel for the shuttle bulkheads. Run:
blender --background --python tools/blender/valve_wheel.py
Output: assetss/blender/hatch_wheel.glb  (1 unit = 1 m, origin at the wheel centre, faces +Z)"""
import bpy, bmesh, math, os

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "assetss", "blender", "hatch_wheel.glb")
os.makedirs(os.path.dirname(OUT), exist_ok=True)

bpy.ops.wm.read_factory_settings(use_empty=True)

def material(name, color, rough, metal):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    b = m.node_tree.nodes["Principled BSDF"]
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    return m

iron = material("WheelIron", (0.20, 0.18, 0.15), 0.75, 0.6)
rust = material("WheelRust", (0.32, 0.17, 0.08), 0.9, 0.2)
brass = material("WheelBrass", (0.42, 0.34, 0.16), 0.6, 0.7)

parts = []

def add(obj, mat):
    obj.data.materials.append(mat)
    parts.append(obj)
    return obj

# Rim: a torus lying in the XY plane (axis Z).
bpy.ops.mesh.primitive_torus_add(major_radius=0.135, minor_radius=0.0165, major_segments=24, minor_segments=8)
add(bpy.context.object, iron)

# Six spokes from hub to rim.
for i in range(6):
    a = i * math.tau / 6
    bpy.ops.mesh.primitive_cylinder_add(radius=0.0085, depth=0.135, vertices=8)
    o = bpy.context.object
    o.rotation_euler = (0, 0, a)
    # cylinder axis is Z: tilt it into the XY plane then spin around Z
    o.rotation_euler = (math.pi / 2, 0, 0)
    bpy.context.view_layer.update()
    o.location = (0, 0.0675, 0)
    # spin the spoke around the Z axis by moving its pivot to the origin
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.context.scene.cursor.location = (0, 0, 0)
    bpy.ops.object.origin_set(type="ORIGIN_CURSOR")
    o.rotation_euler = (math.pi / 2, 0, 0)
    o.rotation_mode = "XYZ"
    # apply spin via a parent-free matrix
    import mathutils
    rot = mathutils.Matrix.Rotation(a, 4, "Z")
    o.matrix_world = rot @ o.matrix_world
    add(o, iron)

# Hub with a boss, a stem to the wall and a lock nut.
bpy.ops.mesh.primitive_cylinder_add(radius=0.034, depth=0.05, vertices=12, location=(0, 0, 0.01))
add(bpy.context.object, brass)
bpy.ops.mesh.primitive_cylinder_add(radius=0.016, depth=0.07, vertices=8, location=(0, 0, -0.04))
add(bpy.context.object, iron)
bpy.ops.mesh.primitive_cylinder_add(radius=0.05, depth=0.02, vertices=6, location=(0, 0, -0.07))
add(bpy.context.object, rust)
# Small knob on the rim: the grip you turn the wheel by.
bpy.ops.mesh.primitive_cylinder_add(radius=0.014, depth=0.05, vertices=8, location=(0.135, 0, 0.03))
add(bpy.context.object, brass)

bpy.ops.object.select_all(action="DESELECT")
for p in parts:
    p.select_set(True)
bpy.context.view_layer.objects.active = parts[0]
bpy.ops.object.join()
wheel = bpy.context.object
wheel.name = "HatchWheel"
# Blender is Z-up: the wheel was built with its axis along Z, which glTF (Y-up) turns into "lying flat".
# Rotate 90 deg about X so the axis points along glTF +Z (the wheel faces the room).
wheel.rotation_euler = (math.pi / 2, 0, 0)
bpy.ops.object.transform_apply(location=False, rotation=True, scale=False)
bpy.ops.object.shade_smooth()
bpy.ops.export_scene.gltf(filepath=OUT, export_format="GLB", use_selection=True, export_yup=True)
print("EXPORTED", OUT)
