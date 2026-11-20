"""Build a compact, hinged industrial EVA hatch from the project's worn materials."""
import bpy
import math
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assetss" / "ship_exterior" / "airlock_hatch_v2.glb"
OUTPUT = ROOT / "assetss" / "ship_exterior" / "airlock_hatch_v3_wide.glb"

bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath=str(SOURCE))
source_obj = next(o for o in bpy.context.scene.objects if o.type == "MESH")
materials = {m.name: m for m in source_obj.data.materials if m is not None}
bpy.data.objects.remove(source_obj, do_unlink=True)

def material(name, fallback):
    if name in materials:
        return materials[name]
    mat = bpy.data.materials.new(name)
    mat.diffuse_color = (*fallback, 1.0)
    mat.use_nodes = True
    mat.node_tree.nodes.get("Principled BSDF").inputs["Base Color"].default_value = (*fallback, 1.0)
    mat.node_tree.nodes.get("Principled BSDF").inputs["Roughness"].default_value = 0.84
    materials[name] = mat
    return mat

dark = material("metal_dark", (0.045, 0.060, 0.068))
steel = material("metal_panel", (0.24, 0.30, 0.32))
paint = material("paint_worn", (0.42, 0.46, 0.45))
white = material("paint_white", (0.60, 0.63, 0.60))
hazard = material("hazard_y", (0.66, 0.38, 0.08))
red = material("red_lamp", (0.62, 0.045, 0.025))

def octagon(width, height, clip):
    w = width * 0.5
    h = height * 0.5
    c = min(clip, w * 0.45, h * 0.45)
    return [(-w+c,-h),(w-c,-h),(w,-h+c),(w,h-c),
            (w-c,h),(-w+c,h),(-w,h-c),(-w,-h+c)]

def add_metric_uv(mesh):
    uv = mesh.uv_layers.new(name="UVMap")
    for poly in mesh.polygons:
        axis = max(range(3), key=lambda i: abs(poly.normal[i]))
        coords = [i for i in range(3) if i != axis]
        for loop_index in poly.loop_indices:
            vertex = mesh.vertices[mesh.loops[loop_index].vertex_index].co
            uv.data[loop_index].uv = (vertex[coords[0]] * 0.8, vertex[coords[1]] * 0.8)

def ring_object(name, center, outer_size, inner_size, clip, x_depth, front_mat, side_mat):
    outer = octagon(outer_size[0], outer_size[1], clip)
    inner = octagon(inner_size[0], inner_size[1], max(clip * 0.75, 0.08))
    verts = []
    # Local Blender axes: X is hull normal, Y is ship width, Z is vertical.
    for x, loop in [(-x_depth/2, outer), (-x_depth/2, inner),
                    (x_depth/2, outer), (x_depth/2, inner)]:
        verts.extend((x, y, z) for y, z in loop)
    faces = []
    face_materials = []
    for i in range(8):
        j = (i + 1) % 8
        faces.append((i, j, 8+j, 8+i)); face_materials.append(1)
        faces.append((16+i, 24+i, 24+j, 16+j)); face_materials.append(0)
        faces.append((i, 16+i, 16+j, j)); face_materials.append(1)
        faces.append((8+i, 8+j, 24+j, 24+i)); face_materials.append(1)
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(front_mat)
    mesh.materials.append(side_mat)
    mesh.update()
    add_metric_uv(mesh)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    obj.location = center
    for poly, idx in zip(mesh.polygons, face_materials):
        poly.material_index = idx
    bevel = obj.modifiers.new("Forged chamfer", "BEVEL")
    bevel.width = 0.025
    bevel.segments = 1
    obj.modifiers.new("Weighted corner normals", "WEIGHTED_NORMAL")
    created.append(obj)
    return obj

def prism(name, center, size, clip, x_depth, mat, parent=None, local_center=None):
    coords = octagon(size[0], size[1], clip)
    x_offset, y_offset, z_offset = local_center if local_center is not None else (0.0, 0.0, 0.0)
    verts = []
    for x in (x_offset-x_depth/2, x_offset+x_depth/2):
        verts.extend((x, y + y_offset, z + z_offset) for y, z in coords)
    faces = [tuple(reversed(range(8))), tuple(range(8,16))]
    for i in range(8):
        j = (i+1)%8
        faces.append((i,j,j+8,i+8))
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata(verts, [], faces)
    mesh.materials.append(mat)
    mesh.update()
    add_metric_uv(mesh)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.collection.objects.link(obj)
    if parent is None:
        obj.location = center
    else:
        obj.parent = parent
        obj.location = (0.0, 0.0, 0.0)
    bevel = obj.modifiers.new("Machined edge bevel", "BEVEL")
    bevel.width = 0.025
    bevel.segments = 1
    created.append(obj)
    return obj

def box(name, center, size, mat, parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1.0, location=center)
    obj = bpy.context.object
    obj.name = name
    obj.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    obj.data.materials.append(mat)
    if not obj.data.uv_layers:
        add_metric_uv(obj.data)
    bevel = obj.modifiers.new("Edge chamfer", "BEVEL")
    bevel.width = min(size) * 0.18
    bevel.segments = 1
    if parent is not None:
        obj.parent = parent
        obj.location = center
    created.append(obj)
    return obj

def cylinder(name, center, radius, depth, mat, parent=None):
    bpy.ops.mesh.primitive_cylinder_add(vertices=12, radius=radius, depth=depth,
                                        location=center, rotation=(0.0, math.pi/2.0, 0.0))
    obj = bpy.context.object
    obj.name = name
    obj.data.materials.append(mat)
    if not obj.data.uv_layers:
        add_metric_uv(obj.data)
    if parent is not None:
        obj.parent = parent
        obj.location = center
    created.append(obj)
    return obj

created = []
# Static outer frame sits across the hull skin, with a dark pressure seal inside.
ring_object("AirlockFrame", (-8.53,-11.90,3.30), (2.24,2.84), (1.76,2.38), .24, .30, steel, dark)
ring_object("AirlockPressureSeal", (-8.70,-11.90,3.30), (1.78,2.40), (1.66,2.28), .20, .055, dark, dark)

# The pivot is on one vertical edge; EVA opens only the heavy leaf, not its frame.
pivot = bpy.data.objects.new("HatchLeafPivot", None)
bpy.context.collection.objects.link(pivot)
pivot.location = (-8.76,-12.875,3.30)
created.append(pivot)
prism("HatchLeaf", (0,0,0), (1.96,2.52), .22, .16, paint, pivot, (-.02,.98,0.0))
prism("HatchLeafFace", (0,0,0), (1.48,1.96), .16, .025, white, pivot, (-.11,.98,0.0))
prism("HatchLeafInset", (0,0,0), (1.12,1.48), .13, .018, paint, pivot, (-.13,.98,0.0))

# Mechanical hinge barrel and three separated knuckles explain the rotation axis.
cylinder("HatchHingeBarrel", (-8.55,-12.97,3.30), .105, 2.35, dark)
for idx, z in enumerate((2.58,3.30,4.02)):
    cylinder(f"HatchHingeKnuckle{idx+1}", (-8.72,-12.98,z), .125, .40, steel)

# Locking dogs on the latch edge, a hand wheel, and restrained status lamps.
for z in (2.47,2.88,3.72,4.13):
    box(f"HatchLockDog_{z:.2f}", (-.12,1.855,z-3.30), (.17,.18,.10), dark, pivot)
cylinder("HatchManualWheel", (-.18,1.705,0.0), .11, .07, hazard, pivot)
for z in (2.57,4.03):
    box(f"HatchStatusLens_{z:.2f}", (-8.74,-11.42,z), (.045,.08,.12), red)

# A short striped service tab marks the latch side without wrapping the whole frame.
box("HatchHazardTab", (-8.73,-11.19,4.54), (.035,.42,.10), hazard)

out_dir = OUTPUT.parent
out_dir.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action="DESELECT")
for obj in created:
    obj.select_set(True)
bpy.context.view_layer.objects.active = pivot
bpy.ops.export_scene.gltf(filepath=str(OUTPUT), export_format="GLB", use_selection=True,
                           export_apply=True, export_materials="EXPORT", export_image_format="AUTO")
print("EXPORTED_HATCH", OUTPUT)
print("HATCH_SPEC", {"clear_aperture_m":[1.76,2.38],"outer_frame_m":[2.24,2.84],
                     "moving_node":"HatchLeafPivot","mesh_parts":len(created)})
