"""Rebuild the animated EVA fixture GLB from the Blender source."""

from pathlib import Path
import runpy

import bpy


def export_dock():
    helpers = runpy.run_path(str(Path(__file__).with_name("export_reactor_wiring.py")))
    select, merge, bake = (helpers[name] for name in ("select", "merge", "bake"))
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.device = "CPU"
    kits = []
    for prefix, name, size in (
        ("02 |", "PressureTunnel", 1024), ("04 |", "InnerGateArt", 512),
        ("05 |", "TetherArt", 128), ("06 |", "InteriorLiner", 512),
    ):
        group = next(c for c in scene.collection.children if c.name.startswith(prefix))
        result = merge(name, list(group.objects))
        bake(result, size)
        kits.append(result)
    for anchor_name, name in (("OuterLeafPivot", "OuterLeafArt"), ("OuterHandwheel", "WheelArt")):
        anchor = scene.objects[anchor_name]
        result = merge(name, [o for o in anchor.children if o.type == "MESH"])
        bake(result, 512 if anchor_name == "OuterLeafPivot" else 256)
        kits.extend((anchor, result))
    kits.append(scene.objects["AriadnaTripoHull"])
    select(*kits)
    target = Path(bpy.data.filepath).resolve().parents[1] / "assetss/blender/eva_shuttle_dock/eva_shuttle_dock.glb"
    target.parent.mkdir(parents=True, exist_ok=True)
    staged = target.with_name(".eva_shuttle_dock_export.glb")
    assert bpy.ops.export_scene.gltf(
        filepath=str(staged), use_selection=True, use_active_scene=True,
        export_yup=True, export_animations=False, export_cameras=False, export_lights=False,
    ) == {"FINISHED"}
    staged.replace(target)
    print("EVA_DOCK_OK", target.stat().st_size)


if __name__ == "__main__":
    export_dock()
