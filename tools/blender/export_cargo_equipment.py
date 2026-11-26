"""Bake and export the right-wall cargo kit from blender/cargo_equipment.blend."""

from pathlib import Path
import runpy

import bpy


def export_cargo():
    helpers = runpy.run_path(str(Path(__file__).with_name("export_reactor_wiring.py")))
    select, merge, bake = (helpers[name] for name in ("select", "merge", "bake"))
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.device = "CPU"
    kit = []
    for prefix, name, side in (
        ("01 |", "CargoModule", 1024),
        ("02 |", "LashingBelts", 512),
        ("03 |", "RestraintNet", 512),
        ("04 |", "DeckTracks", 512),
        ("05 |", "TransitCase", 512),
    ):
        collection = next(c for c in scene.collection.children if c.name.startswith(prefix))
        for obj in list(collection.objects):
            if obj.type == "FONT":
                obj.data.resolution_u = 3
                select(obj)
                bpy.ops.object.convert(target="MESH")
            elif obj.name.startswith(("Socket keyway", "Latch inset", "Fork inner lower")):
                # These mostly flat inset details don't need bevel geometry in game.
                obj.modifiers.clear()
        objects = [o for o in collection.objects if o.type == "MESH"]
        result = merge(name, objects)
        bake(result, side)
        result.data.calc_loop_triangles()
        print(name, len(result.data.loop_triangles), "triangles")
        kit.append(result)
    select(*kit)
    target = Path(bpy.data.filepath).resolve().parents[1] / "assetss/blender/cargo_equipment/cargo_equipment.glb"
    target.parent.mkdir(parents=True, exist_ok=True)
    staged = target.with_name(".cargo_equipment_export.glb")
    assert bpy.ops.export_scene.gltf(
        filepath=str(staged), use_selection=True, export_yup=True,
        export_animations=False, export_cameras=False, export_lights=False,
    ) == {"FINISHED"}
    staged.replace(target)
    print("CARGO_EXPORT_OK", target, target.stat().st_size)


if __name__ == "__main__":
    export_cargo()
