"""Export the eight real-scale props, excluding the review board and its text."""

from pathlib import Path
import runpy

import bpy


def export_props():
    helpers = runpy.run_path(str(Path(__file__).with_name("export_reactor_wiring.py")))
    select, merge, bake = (helpers[name] for name in ("select", "merge", "bake"))
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.device = "CPU"
    kit = []
    for i, name in enumerate((
        "Snapshot", "ChildDrawing", "WorkJacket", "RationPouch",
        "PersonalCassette", "UsedSyringeTray", "OilyRag", "ToolRoll",
    ), 1):
        collection = next(c for c in bpy.data.collections if c.name.startswith(f"{i:02d} |"))
        scene.collection.children.link(collection)
        bpy.context.view_layer.update()
        assert all(obj.type in {"MESH", "CURVE"} for obj in collection.objects)
        for obj in list(collection.objects):
            if obj.type == "CURVE":
                select(obj)
                bpy.ops.object.convert(target="MESH")
        visual = merge(name + "Mesh", list(collection.objects))
        bake(visual, 512 if name in {"WorkJacket", "ToolRoll"} else 256)
        anchor = bpy.data.objects.new(name, None)
        collection.objects.link(anchor)
        visual.parent = anchor
        kit.extend((anchor, visual))
    select(*kit)
    target = Path(bpy.data.filepath).resolve().parents[1] / "assetss/blender/crew_life_props/crew_life_props.glb"
    target.parent.mkdir(parents=True, exist_ok=True)
    staged = target.with_name(".crew_life_props_export.glb")
    assert bpy.ops.export_scene.gltf(
        filepath=str(staged), use_selection=True, use_active_scene=True, export_yup=True,
        export_animations=False, export_cameras=False, export_lights=False,
    ) == {"FINISHED"}
    staged.replace(target)
    print("CREW_LIFE_PROPS_OK", target.stat().st_size)


if __name__ == "__main__":
    export_props()
