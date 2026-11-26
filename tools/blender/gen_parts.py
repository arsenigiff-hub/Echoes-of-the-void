import bpy, bmesh, sys
from mathutils import Vector
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="assetss/tripo/shuttle_oxygen_generator.glb")
obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
bpy.context.view_layer.objects.active = obj
bpy.ops.object.mode_set(mode="EDIT")
bm = bmesh.from_edit_mesh(obj.data)
bm.faces.ensure_lookup_table()
seen = set(); islands = []
for f in bm.faces:
    if f.index in seen: continue
    stack = [f]; comp = []
    seen.add(f.index)
    while stack:
        cur = stack.pop(); comp.append(cur)
        for e in cur.edges:
            for nf in e.link_faces:
                if nf.index not in seen:
                    seen.add(nf.index); stack.append(nf)
    islands.append(comp)
print("ISLANDS", len(islands))
rows = []
for comp in islands:
    vs = [v.co for f in comp for v in f.verts]
    # glTF space: x, y = blender z, z = -blender y
    xs = [v.x for v in vs]; ys = [v.z for v in vs]; zs = [-v.y for v in vs]
    rows.append((len(comp), min(xs), max(xs), min(ys), max(ys), min(zs), max(zs)))
rows.sort(key=lambda r: -r[6])
for r in rows[:25]:
    print("ISL faces=%d x[%.2f,%.2f] y[%.2f,%.2f] z[%.2f,%.2f]" % r)
