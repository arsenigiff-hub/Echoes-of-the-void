"""Bake the galley slippers without the staging floor or lights."""

from pathlib import Path
import runpy

import bpy


if __name__ == "__main__":
    helpers = runpy.run_path(str(Path(__file__).with_name("export_reactor_wiring.py")))
    select, merge, bake = (helpers[name] for name in ("select", "merge", "bake"))
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.device = "CPU"
    kit = scene.collection.children["01 | Slippers"]
    for obj in list(kit.objects):
        if obj.type == "CURVE":
            select(obj)
            bpy.ops.object.convert(target="MESH")
    pair = merge("Slippers", list(kit.objects))
    bake(pair, 512)
    select(pair)
    target = Path(bpy.data.filepath).resolve().parents[1] / "assetss/blender/galley_slippers/galley_slippers.glb"
    target.parent.mkdir(parents=True, exist_ok=True)
    assert bpy.ops.export_scene.gltf(
        filepath=str(target), use_selection=True, export_yup=True,
        export_animations=False, export_cameras=False, export_lights=False,
    ) == {"FINISHED"}
