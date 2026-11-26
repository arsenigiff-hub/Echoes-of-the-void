import bpy, math
bpy.ops.wm.read_factory_settings(use_empty=True)
bpy.ops.import_scene.gltf(filepath="assetss/tripo/shuttle_oxygen_generator.glb")
obj = [o for o in bpy.context.scene.objects if o.type == "MESH"][0]
pts = [(v.co.x, v.co.z, -v.co.y) for v in obj.data.vertices]  # glTF x, y, z
cx, cy = -0.045, 0.415
for it in range(8):
    sel = [(x, y, z) for x, y, z in pts if math.hypot(x - cx, y - cy) < 0.17 and 0.0 < z < 0.12]
    if not sel: break
    cx = sum(p[0] for p in sel) / len(sel); cy = sum(p[1] for p in sel) / len(sel)
    print("ITER", it, len(sel), round(cx, 3), round(cy, 3))
# ring: vertices on the front plane z in [0.12,0.18]; fit radius by extremes around the centre
ring = [(x, y, z) for x, y, z in pts if 0.11 < z < 0.2 and 0.12 < math.hypot(x - cx, y - cy) < 0.3]
rs = sorted(math.hypot(x - cx, y - cy) for x, y, z in ring)
print("RING n", len(ring), "r percentiles", [round(rs[int(len(rs) * q)], 3) for q in (0.05, 0.25, 0.5, 0.75, 0.95)] if rs else None)
# depth of fan blades: z extent of the near-centre points
core = [z for x, y, z in pts if math.hypot(x - cx, y - cy) < 0.15 and 0 < z < 0.2]
print("CORE z min/max", round(min(core), 3), round(max(core), 3), "median", round(sorted(core)[len(core)//2], 3))
