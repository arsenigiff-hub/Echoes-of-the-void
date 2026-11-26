"""Export the editable cabinet for Godot, baking the Blender-only paint shaders.

blender --background blender/reactor_wiring_cabinet.blend --python tools/blender/export_reactor_wiring.py
"""

from pathlib import Path

import bpy


def select(*objects):
    bpy.ops.object.select_all(action="DESELECT")
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]


def merge(name, objects):
    for obj in objects:
        select(obj)
        for modifier in list(obj.modifiers):
            bpy.ops.object.modifier_apply(modifier=modifier.name)
    select(*objects)
    bpy.ops.object.join()
    result = bpy.context.object
    result.name = name
    return result


def bake(obj, size):
    select(obj)
    for uv in list(obj.data.uv_layers):
        obj.data.uv_layers.remove(uv)
    obj.data.uv_layers.new(name="GameUV")
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(island_margin=0.0025)
    bpy.ops.object.mode_set(mode="OBJECT")

    image = bpy.data.images.new(obj.name + "_albedo", width=size, height=size, alpha=False)
    # Door and shell use independent atlases; the originals reuse materials.
    baked = {}
    for slot in obj.material_slots:
        original = slot.material
        if original not in baked:
            material = original.copy()
            material.name = obj.name + " | " + original.name
            tree = material.node_tree
            node = tree.nodes.new("ShaderNodeTexImage")
            node.image = image
            tree.nodes.active = node
            baked[original] = (material, node)
        slot.material = baked[original][0]
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=3)
    image.pack()
    for material, node in baked.values():
        tree = material.node_tree
        shader = next(n for n in tree.nodes if n.type == "BSDF_PRINCIPLED")
        tree.links.new(node.outputs["Color"], shader.inputs["Base Color"])
        for link in list(shader.inputs["Normal"].links):
            tree.links.remove(link)
        node.interpolation = "Closest"


def export_cabinet():
    scene = bpy.context.scene
    root = scene.objects["CabinetRoot"]
    door = scene.objects["DoorPivot"]
    door.rotation_euler.z = 0
    for obj in list(scene.objects):
        if any(c.name.startswith(("04 •", "90 •", "91 •")) for c in obj.users_collection):
            bpy.data.objects.remove(obj, do_unlink=True)
    scene.camera = None
    scene.render.engine = "CYCLES"
    scene.cycles.samples = 1
    scene.cycles.device = "CPU"
    bpy.context.view_layer.update()

    shell_meshes = [o for o in root.children if o.type == "MESH" and o.name != "Warm lamp diffuser"]
    door_meshes = [o for o in door.children if o.type == "MESH"]
    door_meshes.sort(key=lambda o: not o.name.startswith("Door | pressed steel panel"))
    shell = merge("CabinetShell", shell_meshes)
    door_mesh = merge("CabinetDoor", door_meshes)
    bake(shell, 1024)
    bake(door_mesh, 1024)
    select(*list(scene.objects))
    target = Path(bpy.data.filepath).resolve().parents[1] / "assetss/blender/reactor_wiring/reactor_wiring.glb"
    target.parent.mkdir(parents=True, exist_ok=True)
    staged = target.with_name(".reactor_wiring_export.glb")
    bpy.ops.export_scene.gltf(filepath=str(staged), use_selection=True, export_yup=True,
                              export_animations=False, export_cameras=False, export_lights=False)
    staged.replace(target)
    print("CABINET_EXPORT_OK", target, target.stat().st_size)


if __name__ == "__main__":
    export_cabinet()
