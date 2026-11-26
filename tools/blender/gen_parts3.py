import bpy
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="assetss/tripo/shuttle_oxygen_generator.glb")
obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
hist = {}
for v in obj.data.vertices:
    x, y, z = v.co.x, v.co.z, -v.co.y
    if abs(x + 0.045) < 0.14 and abs(y - 0.415) < 0.14:
        k = round(z / 0.02) * 0.02
        hist[k] = hist.get(k, 0) + 1
for k in sorted(hist):
    print("ZH %.2f %d" % (k, hist[k]))
