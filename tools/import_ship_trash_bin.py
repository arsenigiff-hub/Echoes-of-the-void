import bpy
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[1]
src = ROOT / 'assetss/ship_clutter_external/source/yughues_free_trashes/01/trash_01.obj'
out = ROOT / 'assetss/ship_clutter_external/trash_bin_lowpoly.glb'

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
bpy.ops.wm.obj_import(filepath=str(src))
objects = [o for o in bpy.context.scene.objects if o.type == 'MESH']
if not objects:
    raise RuntimeError('OBJ contains no mesh')

# The author's model is in centimeters. Convert to meters, put its base on z=0,
# center its footprint, and replace the smooth PBR look with a flat game material.
bpy.ops.object.select_all(action='DESELECT')
for o in objects:
    o.select_set(True)
    o.scale = tuple(v * .01 for v in o.scale)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
for o in objects:
    for p in o.data.polygons:
        p.use_smooth = False
    for m in list(o.data.materials):
        o.data.materials.clear()
    mat = bpy.data.materials.get('detail_dark_metal') or bpy.data.materials.new('detail_dark_metal')
    mat.diffuse_color = (.09, .11, .10, 1)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get('Principled BSDF')
    bsdf.inputs['Base Color'].default_value = (.09, .11, .10, 1)
    bsdf.inputs['Roughness'].default_value = .92
    bsdf.inputs['Metallic'].default_value = .08
    o.data.materials.append(mat)

deps = bpy.context.evaluated_depsgraph_get()
coords = [o.matrix_world @ Vector(corner) for o in objects for corner in o.bound_box]
mins = [min(v[i] for v in coords) for i in range(3)]
maxs = [max(v[i] for v in coords) for i in range(3)]
center = ((mins[0]+maxs[0])/2, (mins[1]+maxs[1])/2, mins[2])
for o in objects:
    o.location.x -= center[0]
    o.location.y -= center[1]
    o.location.z -= center[2]
    o.name = 'external_trash_bin'
bpy.context.scene.unit_settings.system = 'METRIC'
bpy.ops.object.select_all(action='DESELECT')
for o in objects:
    o.select_set(True)
bpy.context.view_layer.objects.active = objects[0]
bpy.ops.export_scene.gltf(filepath=str(out), export_format='GLB', use_selection=True)
print('TRASH_BIN_BOUNDS_M', [round(maxs[i]-mins[i], 3) for i in range(3)])
print('TRASH_BIN_GLB', out)
