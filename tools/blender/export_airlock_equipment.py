"""Bake airlock dressing and export its four independent wall mounts."""

from pathlib import Path
import runpy

import bpy
from mathutils import Vector


def export_airlock():
    helpers = runpy.run_path(str(Path(__file__).with_name("export_reactor_wiring.py")))
    select, merge, bake = (helpers[name] for name in ("select", "merge", "bake"))
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.device = "CPU"
    export_objects = []
    for prefix, name, origin_x, size in (
        ("01 |", "Suit", -0.49, 1024),
        ("02 |", "Bench", -1.68, 1024),
        ("03 |", "Lockers", 0.58, 1024),
        ("04 |", "Hooks", -2.14, 256),
    ):
        collection = next(c for c in scene.collection.children if c.name.startswith(prefix))
        for obj in list(collection.objects):
            if obj.type in {"FONT", "CURVE"}:
                if obj.type == "FONT":
                    obj.data.resolution_u = 3
                select(obj)
                bpy.ops.object.convert(target="MESH")
        result = merge(name + "Mesh", [o for o in collection.objects if o.type == "MESH"])
        bake(result, size)
        anchor = bpy.data.objects.new(name + "Mount", None)
        collection.objects.link(anchor)
        result.parent = anchor
        result.location -= Vector((origin_x, 0, 0))
        export_objects.extend((anchor, result))
        result.data.calc_loop_triangles()
        print(name, len(result.data.loop_triangles), "triangles")
    select(*export_objects)
    target = Path(bpy.data.filepath).resolve().parents[1] / "assetss/blender/airlock_equipment/airlock_equipment.glb"
    target.parent.mkdir(parents=True, exist_ok=True)
    staged = target.with_name(".airlock_equipment_export.glb")
    assert bpy.ops.export_scene.gltf(
        filepath=str(staged), use_selection=True, export_yup=True,
        export_animations=False, export_cameras=False, export_lights=False,
    ) == {"FINISHED"}
    staged.replace(target)
    print("AIRLOCK_EXPORT_OK", target, target.stat().st_size)


if __name__ == "__main__":
    export_airlock()
