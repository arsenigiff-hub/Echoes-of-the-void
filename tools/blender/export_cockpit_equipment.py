"""Bake the authored pilot deck kit, excluding meshes used only for scale and preview."""

from pathlib import Path
import runpy

import bpy


def export_cockpit():
    helpers = runpy.run_path(str(Path(__file__).with_name("export_reactor_wiring.py")))
    select, merge, bake = (helpers[name] for name in ("select", "merge", "bake"))
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.device = "CPU"
    kit = []
    for prefix, name, size in (
        ("01 |", "NavPlinth", 1024),
        ("02 |", "BreakerBank", 1024),
        ("03 |", "WindowFrame", 1024),
        ("04 |", "DeskProps", 512),
    ):
        collection = next(c for c in scene.collection.children if c.name.startswith(prefix))
        for obj in list(collection.objects):
            if obj.type in {"FONT", "CURVE"}:
                select(obj)
                bpy.ops.object.convert(target="MESH")
        result = merge(name, [o for o in collection.objects if o.type == "MESH"])
        bake(result, size)
        result.data.calc_loop_triangles()
        print(name, len(result.data.loop_triangles), "triangles")
        kit.append(result)
    select(*kit)
    target = Path(bpy.data.filepath).resolve().parents[1] / "assetss/blender/cockpit_equipment/cockpit_equipment.glb"
    target.parent.mkdir(parents=True, exist_ok=True)
    staged = target.with_name(".cockpit_equipment_export.glb")
    assert bpy.ops.export_scene.gltf(
        filepath=str(staged), use_selection=True, export_yup=True,
        export_animations=False, export_cameras=False, export_lights=False,
    ) == {"FINISHED"}
    staged.replace(target)
    print("COCKPIT_EXPORT_OK", target, target.stat().st_size)


if __name__ == "__main__":
    export_cockpit()
