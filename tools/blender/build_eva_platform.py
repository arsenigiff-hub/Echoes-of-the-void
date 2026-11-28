"""Author the side-hatch landing in the live Blender via MCP. Blender Z is up."""
from pathlib import Path
import math
import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]


def build():
    scene = bpy.data.scenes.new("ARIADNA | EVA landing platform")
    bpy.context.window.scene = scene
    scene.unit_settings.system = "METRIC"
    groups = {}
    for name in ("PlatformDeck", "PlatformRails", "PlatformStructure"):
        c = bpy.data.collections.new(name)
        scene.collection.children.link(c)
        groups[name] = c

    def material(name, dark, light, scale):
        m = bpy.data.materials.new(name)
        m.use_nodes = True
        tree = m.node_tree
        shader = tree.nodes.get("Principled BSDF")
        shader.inputs["Roughness"].default_value = 0.88
        shader.inputs["Metallic"].default_value = 0.35
        noise = tree.nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = scale
        noise.inputs["Detail"].default_value = 3
        coord = tree.nodes.new("ShaderNodeNewGeometry")
        tree.links.new(coord.outputs["Position"], noise.inputs["Vector"])
        ramp = tree.nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.28
        ramp.color_ramp.elements[0].color = (*dark, 1)
        ramp.color_ramp.elements[1].position = 0.68
        ramp.color_ramp.elements[1].color = (*light, 1)
        tree.links.new(noise.outputs["Fac"], ramp.inputs[0])
        tree.links.new(ramp.outputs["Color"], shader.inputs["Base Color"])
        m.diffuse_color = (*light, 1)
        return m

    steel = material("Platform | worn cold steel", (.035,.043,.045), (.19,.22,.23), 35)
    edge = material("Platform | exposed frame", (.045,.052,.056), (.30,.32,.30), 22)
    yellow = material("Platform | worn ochre safety paint", (.10,.085,.045), (.42,.34,.12), 17)
    black = material("Platform | rubber inserts", (.012,.016,.018), (.035,.043,.047), 45)

    def put(obj, group, mat):
        for c in list(obj.users_collection):
            c.objects.unlink(obj)
        groups[group].objects.link(obj)
        obj.data.materials.append(mat)
        return obj

    def box(name, size, pos, mat=steel, group="PlatformDeck", bevel=.012):
        bpy.ops.mesh.primitive_cube_add(size=1, location=pos)
        obj = bpy.context.object
        obj.name = name
        obj.dimensions = size
        bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
        if bevel:
            mod = obj.modifiers.new("Folded and eased edges", "BEVEL")
            mod.width = bevel
            mod.segments = 1
        return put(obj, group, mat)

    def bar(name, a, b, radius=.026, mat=yellow, group="PlatformRails"):
        a,b = Vector(a),Vector(b)
        bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=radius, depth=(b-a).length, location=(a+b)*.5)
        o = bpy.context.object
        o.name = name
        o.rotation_euler = (b-a).to_track_quat("Z","Y").to_euler()
        return put(o, group, mat)

    # Three removable tread panels; their top is exactly flush with the tunnel.
    for i in range(3):
        x = -4.23 - i*.92
        box("Removable tread cassette", (.90,2.68,.075), (x,0,-.038))
        for y in (-1.26,1.26):
            for dx in (-.36,.36):
                bpy.ops.mesh.primitive_cylinder_add(vertices=6, radius=.026, depth=.009, location=(x+dx,y,.003))
                put(bpy.context.object,"PlatformDeck",edge).name="Recessed tread fastener"
        for y in [j*.16 for j in range(-7,8)]:
            for dx in (-.21,.21):
                box("Raised anti-slip rib", (.29,.025,.009), (x+dx,y,.004), edge, bevel=.005)
        box("Dark drainage insert", (.032,2.35,.004), (x+.40,0,.002), black, bevel=0)

    for y in (-1.41,1.41):
        box("Perimeter channel", (2.94,.14,.19), (-5.15,y,-.085), edge, "PlatformStructure")
        box("Boot stop curb", (2.94,.075,.10), (-5.15,y,.055), yellow, "PlatformRails")
        for x in (-3.92,-5.13,-6.42):
            box("Bolted stanchion socket", (.16,.18,.09), (x,y,.055), edge, "PlatformRails")
            bar("Handrail upright", (x,y,.07), (x,y,1.12))
        bar("Continuous upper handrail", (-6.42,y,1.12), (-3.92,y,1.12), .033)
        bar("Intermediate guardrail", (-6.42,y,.60), (-3.92,y,.60), .022, steel)
        for x in (-4.30,-5.72):
            bar("Black grip sleeve", (x-.15,y,1.12), (x+.15,y,1.12), .040, black)
        # Load-bearing diagonal knees back to the pressure collar.
        bar("Triangulated support strut", (-3.76,y,-.77), (-5.93,y,-.18), .065, edge, "PlatformStructure")
        box("Hull mounting shoe", (.14,.28,.30), (-3.76,y,-.64), edge, "PlatformStructure")
    for x in (-3.73,-4.70,-5.62,-6.57):
        box("Underdeck crossbeam", (.12,2.78,.18), (x,0,-.16), edge, "PlatformStructure")
    # The outer end has a generous opening for an intentional EVA push-off.
    for sign in (-1,1):
        y0,y1 = sign*.72,sign*1.41
        bar("Outer corner handhold", (-6.42,y0,1.12),(-6.42,y1,1.12),.033)
        bar("Launch opening post", (-6.42,y0,.04),(-6.42,y0,1.12))
        box("Outer edge caution strip", (.13,.57,.016), (-6.52,sign*1.05,.008),yellow)
    box("Flush threshold bridge", (.25,1.40,.075), (-3.78,0,-.038),edge)

    # A separate preview rig is excluded by the exporter.
    bpy.ops.object.camera_add(location=(-9.7,-6.4,5.3))
    camera=bpy.context.object
    camera.rotation_euler=(Vector((-5.1,0,.2))-camera.location).to_track_quat("-Z","Y").to_euler()
    camera.data.type="ORTHO"
    camera.data.ortho_scale=5.3
    scene.camera=camera
    for pos,energy,size in [((-5,-3,6),1100,5),((-3,3,4),850,4)]:
        bpy.ops.object.light_add(type="AREA",location=pos)
        light=bpy.context.object
        light.data.energy=energy
        light.data.shape="DISK"
        light.data.size=size
        light.rotation_euler=(Vector((-5.1,0,0))-light.location).to_track_quat("-Z","Y").to_euler()
    scene.world=bpy.data.worlds.new("Platform preview world")
    scene.world.color=(.075,.075,.075)
    scene.render.resolution_x=1100
    scene.render.resolution_y=850
    scene.render.resolution_percentage=100
    scene.render.engine="CYCLES"
    scene.cycles.samples=16
    scene.cycles.device="CPU"
    for area in bpy.context.screen.areas:
        if area.type=="VIEW_3D":
            area.spaces.active.region_3d.view_perspective="CAMERA"
            area.spaces.active.shading.type="MATERIAL"
    bpy.context.preferences.filepaths.save_version=0
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/"blender/eva_platform.blend"),compress=True)
    print("EVA_PLATFORM_SOURCE_OK",sum(len(c.objects) for c in groups.values()))


if __name__=="__main__":
    build()
