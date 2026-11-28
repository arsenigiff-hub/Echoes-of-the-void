"""Bake and export the authored EVA landing, keeping physics meshes separate."""
from pathlib import Path
import runpy
import bpy

root=Path(__file__).resolve().parents[2]
helpers=runpy.run_path(str(Path(__file__).with_name("export_reactor_wiring.py")))
scene=bpy.context.scene
scene.render.engine="CYCLES"
scene.cycles.samples=1
scene.cycles.device="CPU"
parts=[]
for name,size in (("PlatformDeck",1024),("PlatformRails",512),("PlatformStructure",512)):
    collection=next(c for c in scene.collection.children if c.name==name)
    obj=helpers["merge"](name,list(collection.objects))
    helpers["bake"](obj,size)
    parts.append(obj)
helpers["select"](*parts)
target=root/"assetss/blender/eva_platform/eva_platform.glb"
target.parent.mkdir(parents=True,exist_ok=True)
bpy.ops.export_scene.gltf(filepath=str(target),use_selection=True,use_active_scene=True,
    export_yup=True,export_animations=False,export_cameras=False,export_lights=False)
print("EVA_PLATFORM_EXPORT_OK",target.stat().st_size)
