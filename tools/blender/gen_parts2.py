import bpy, bmesh
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="assetss/tripo/shuttle_oxygen_generator.glb")
obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
me = obj.data
# glTF space: x, y=blender z, z=-blender y
hist = {}
for v in me.vertices:
    x, y, z = v.co.x, v.co.z, -v.co.y
    key = (round(z / 0.04) * 0.04)
    hist.setdefault(key, [0, 0, 0])
    hist[key][0] += 1
    if y > 0.28: hist[key][1] += 1
    if y < 0.2 and x < -0.0: hist[key][2] += 1
for k in sorted(hist):
    print("Z %.2f total=%d highY=%d lowYleft=%d" % (k, *hist[k]))
