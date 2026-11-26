"""Bake the crew bay models; exclude the radio already instanced in Godot."""

from pathlib import Path
import runpy

import bpy
from mathutils import Vector


def export_crew():
    helpers = runpy.run_path(str(Path(__file__).with_name("export_reactor_wiring.py")))
    select, merge, bake = (helpers[name] for name in ("select", "merge", "bake"))
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.device = "CPU"
    kit = []
    for prefix, name, origin_x, size in (
        ("01 |", "RadioDesk", -1.49, 1024),
        ("02 |", "CrewSeats", 2.43, 1024),
        ("03 |", "DeskDetails", -1.49, 512),
        ("04 |", "WatchSchedule", -0.46, 512),
    ):
        collection = next(c for c in scene.collection.children if c.name.startswith(prefix))
        for obj in list(collection.objects):
            if obj.type in {"FONT", "CURVE"}:
                select(obj)
                bpy.ops.object.convert(target="MESH")
        result = merge(name + "Mesh", [o for o in collection.objects if o.type == "MESH"])
        bake(result, size)
        anchor = bpy.data.objects.new(name + "Mount", None)
        collection.objects.link(anchor)
        result.parent = anchor
        result.location -= Vector((origin_x, 0, 0))
        result.data.calc_loop_triangles()
        print(name, len(result.data.loop_triangles), "triangles")
        kit.extend((anchor, result))
    select(*kit)
    target = Path(bpy.data.filepath).resolve().parents[1] / "assetss/blender/crew_equipment/crew_equipment.glb"
    target.parent.mkdir(parents=True, exist_ok=True)
    staged = target.with_name(".crew_equipment_export.glb")
    assert bpy.ops.export_scene.gltf(
        filepath=str(staged), use_selection=True, export_yup=True,
        export_animations=False, export_cameras=False, export_lights=False,
    ) == {"FINISHED"}
    staged.replace(target)
    print("CREW_EXPORT_OK", target, target.stat().st_size)


if __name__ == "__main__":
    export_crew()
