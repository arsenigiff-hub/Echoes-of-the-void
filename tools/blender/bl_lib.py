"""Shared helpers for building shuttle props in Blender (run through bmcp.py inside the open window).
Conventions: 1 unit = 1 m, Z up in Blender. The model FRONT faces -Y (becomes +Z in glTF/Godot),
origin at the centre of the bottom face."""
import bpy, bmesh, math, os
from mathutils import Vector

OUT_DIR = "D:/Echoes-of-the-void-main/assetss/blender"
os.makedirs(OUT_DIR, exist_ok=True)

_mats = {}


def mat(name, color, rough=0.7, metal=0.0, emit=None, emit_strength=2.0):
    if name in _mats and _mats[name].name in bpy.data.materials:
        return _mats[name]
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    b = next((n for n in nt.nodes if n.type == "BSDF_PRINCIPLED"), None)
    if b is None:   # Blender 5.x can hand out an empty tree
        b = nt.nodes.new("ShaderNodeBsdfPrincipled")
        out = next((n for n in nt.nodes if n.type == "OUTPUT_MATERIAL"), None) or nt.nodes.new("ShaderNodeOutputMaterial")
        nt.links.new(b.outputs["BSDF"], out.inputs["Surface"])
    b.inputs["Base Color"].default_value = (*color, 1.0)
    b.inputs["Roughness"].default_value = rough
    b.inputs["Metallic"].default_value = metal
    if emit:
        b.inputs["Emission Color"].default_value = (*emit, 1.0)
        b.inputs["Emission Strength"].default_value = emit_strength
    _mats[name] = m
    return m


def _finish(o, material, bevel, smooth=True):
    if material is not None:
        o.data.materials.append(material)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.transform_apply(location=False, rotation=True, scale=True)
    if bevel > 0:
        mod = o.modifiers.new("bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=mod.name)
    if smooth:
        bpy.ops.object.shade_smooth()
    o.select_set(False)
    return o


def box(name, size, loc, material, bevel=0.008, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = size
    o.rotation_euler = rot
    return _finish(o, material, bevel, smooth=False)


def cyl(name, r, depth, loc, material, rot=(0, 0, 0), verts=20, bevel=0.0, r2=None):
    if r2 is None:
        bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, vertices=verts, location=loc)
    else:
        bpy.ops.mesh.primitive_cone_add(radius1=r, radius2=r2, depth=depth, vertices=verts, location=loc)
    o = bpy.context.object
    o.name = name
    o.rotation_euler = rot
    return _finish(o, material, bevel)


def sphere(name, r, loc, material, scale=(1, 1, 1), seg=20, rings=12):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, segments=seg, ring_count=rings, location=loc)
    o = bpy.context.object
    o.name = name
    o.scale = scale
    return _finish(o, material, 0.0)


def torus(name, major, minor, loc, material, rot=(0, 0, 0), maj_seg=28, min_seg=8):
    bpy.ops.mesh.primitive_torus_add(major_radius=major, minor_radius=minor, major_segments=maj_seg,
                                     minor_segments=min_seg, location=loc)
    o = bpy.context.object
    o.name = name
    o.rotation_euler = rot
    return _finish(o, material, 0.0)


def tube(name, points, radius, material, res=6):
    """A smooth tube (hose / cable / rope) along a list of points."""
    curve = bpy.data.curves.new(name, "CURVE")
    curve.dimensions = "3D"
    curve.bevel_depth = radius
    curve.bevel_resolution = res
    curve.resolution_u = 12
    sp = curve.splines.new("BEZIER")
    sp.bezier_points.add(len(points) - 1)
    for p, bp in zip(points, sp.bezier_points):
        bp.co = p
        bp.handle_left_type = "AUTO"
        bp.handle_right_type = "AUTO"
    o = bpy.data.objects.new(name, curve)
    bpy.context.collection.objects.link(o)
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.convert(target="MESH")
    o = bpy.context.object
    o.data.materials.append(material)
    bpy.ops.object.shade_smooth()
    o.select_set(False)
    return o


def join(parts, name):
    bpy.ops.object.select_all(action="DESELECT")
    for p in parts:
        p.select_set(True)
    bpy.context.view_layer.objects.active = parts[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    o.select_set(False)
    return o


def ground(o):
    """Move the object so its bounding box bottom-centre sits at the origin."""
    bpy.context.view_layer.update()
    pts = [o.matrix_world @ Vector(c) for c in o.bound_box]
    minz = min(p.z for p in pts)
    cx = (min(p.x for p in pts) + max(p.x for p in pts)) / 2
    cy = (min(p.y for p in pts) + max(p.y for p in pts)) / 2
    o.location -= Vector((cx, cy, minz))
    bpy.context.view_layer.objects.active = o
    o.select_set(True)
    bpy.ops.object.transform_apply(location=True, rotation=False, scale=False)
    o.select_set(False)


def export(o, filename, display_loc=None):
    """Export one object as GLB (at the origin), then park it at display_loc so you can see the set."""
    old = o.location.copy()
    o.location = (0, 0, 0)
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    path = os.path.join(OUT_DIR, filename)
    bpy.ops.export_scene.gltf(filepath=path, export_format="GLB", use_selection=True, export_yup=True,
                              export_apply=True)
    o.location = display_loc if display_loc is not None else old
    o.select_set(False)
    return path


def preview(objs, path, size=(900, 900), cam_dir=(-1.2, -2.0, 0.9), dist=3.0, target=None):
    """Workbench render of the given objects for a quick look."""
    scn = bpy.context.scene
    scn.render.engine = "BLENDER_WORKBENCH"
    scn.display.shading.light = "STUDIO"
    scn.display.shading.color_type = "TEXTURE"
    scn.render.resolution_x, scn.render.resolution_y = size
    xs = []
    for o in objs:
        xs += [o.matrix_world @ Vector(c) for c in o.bound_box]
    mn = Vector((min(p.x for p in xs), min(p.y for p in xs), min(p.z for p in xs)))
    mx = Vector((max(p.x for p in xs), max(p.y for p in xs), max(p.z for p in xs)))
    center = target or (mn + mx) / 2
    span = max((mx - mn).length, 0.3)
    cam = bpy.data.objects.get("PreviewCam")
    if cam is None:
        cam = bpy.data.objects.new("PreviewCam", bpy.data.cameras.new("PreviewCam"))
        bpy.context.collection.objects.link(cam)
    scn.camera = cam
    d = Vector(cam_dir).normalized()
    cam.location = center + d * span * 1.9
    direction = center - cam.location
    cam.rotation_euler = direction.to_track_quat("-Z", "Y").to_euler()
    scn.render.filepath = path
    bpy.ops.render.render(write_still=True)
    return path


def show_in_viewport(shading="SOLID"):
    """Frame everything in the user's 3D viewport and colour it by material so the build is visible."""
    for window in bpy.context.window_manager.windows:
        for area in window.screen.areas:
            if area.type != "VIEW_3D":
                continue
            space = area.spaces.active
            space.shading.type = "SOLID"
            space.shading.color_type = "TEXTURE"
            space.shading.light = "STUDIO"
            region = next(r for r in area.regions if r.type == "WINDOW")
            with bpy.context.temp_override(window=window, area=area, region=region):
                bpy.ops.view3d.view_all(center=False)


# ------------------------------------------------------------ detail helpers
def bolts(name, material, pts, r=0.008, h=0.006, axis="Y", flip=1.0):
    """A bolt head (hex-ish short cylinder) at each point; axis = the direction the head points along."""
    out = []
    rot = {"Y": (math.pi / 2, 0, 0), "X": (0, math.pi / 2, 0), "Z": (0, 0, 0)}[axis]
    for i, p in enumerate(pts):
        out.append(cyl("%s%d" % (name, i), r, h, (p[0], p[1], p[2]), material, rot=rot, verts=6))
    return out


def ring_pts(center, radius, count, plane="XZ", start=0.0):
    cx, cy, cz = center
    pts = []
    for i in range(count):
        a = start + i * math.tau / count
        if plane == "XZ":
            pts.append((cx + math.cos(a) * radius, cy, cz + math.sin(a) * radius))
        elif plane == "XY":
            pts.append((cx + math.cos(a) * radius, cy + math.sin(a) * radius, cz))
        else:
            pts.append((cx, cy + math.cos(a) * radius, cz + math.sin(a) * radius))
    return pts


def ribbed(name, material, center, radius, length, ribs, axis="Z", tilt=(0, 0, 0)):
    """Accordion joint: a stack of tori."""
    out = []
    cx, cy, cz = center
    for i in range(ribs):
        t = (i / max(ribs - 1, 1) - 0.5) * length
        out.append(torus("%s%d" % (name, i), radius, radius * 0.22, (cx, cy, cz + t), material, rot=tilt, maj_seg=18, min_seg=6))
    return out


def bake_wear(o, tex_name, size=1024, dirt=0.65, edge_color=None, samples=20):
    """Unwrap + bake dirt (AO + noise) and edge wear into ONE colour texture, then rewire the materials to it."""
    scn = bpy.context.scene
    scn.render.engine = "CYCLES"
    scn.cycles.device = "CPU"
    scn.cycles.samples = samples
    scn.cycles.use_denoising = False
    bpy.ops.object.select_all(action="DESELECT")
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(66), island_margin=0.004)
    bpy.ops.object.mode_set(mode="OBJECT")
    img = bpy.data.images.new(tex_name, size, size, alpha=False)
    img.colorspace_settings.name = "sRGB"
    created = {}
    for slot in o.material_slots:
        m = slot.material
        nt = m.node_tree
        bsdf = next(n for n in nt.nodes if n.type == "BSDF_PRINCIPLED")
        base = tuple(bsdf.inputs["Base Color"].default_value)[:3]
        nodes, links = nt.nodes, nt.links
        ao = nodes.new("ShaderNodeAmbientOcclusion")
        ao.inputs["Distance"].default_value = 0.18
        ao.samples = 8
        tc = nodes.new("ShaderNodeTexCoord")
        noise = nodes.new("ShaderNodeTexNoise")
        noise.inputs["Scale"].default_value = 9.0
        noise.inputs["Detail"].default_value = 9.0
        noise.inputs["Roughness"].default_value = 0.62
        links.new(tc.outputs["Object"], noise.inputs["Vector"])
        ramp = nodes.new("ShaderNodeValToRGB")
        ramp.color_ramp.elements[0].position = 0.38
        ramp.color_ramp.elements[1].position = 0.72
        links.new(noise.outputs["Fac"], ramp.inputs["Fac"])
        # dirt factor = (1 - AO) + grime, clamped
        inv = nodes.new("ShaderNodeMath"); inv.operation = "SUBTRACT"; inv.inputs[0].default_value = 1.0
        links.new(ao.outputs["AO"], inv.inputs[1])
        add = nodes.new("ShaderNodeMath"); add.operation = "ADD"; add.use_clamp = True
        links.new(inv.outputs[0], add.inputs[0])
        mulg = nodes.new("ShaderNodeMath"); mulg.operation = "MULTIPLY"; mulg.inputs[1].default_value = 0.38
        links.new(ramp.outputs["Color"], mulg.inputs[0])
        links.new(mulg.outputs[0], add.inputs[1])
        scale = nodes.new("ShaderNodeMath"); scale.operation = "MULTIPLY"; scale.inputs[1].default_value = dirt; scale.use_clamp = True
        links.new(add.outputs[0], scale.inputs[0])
        dirtcol = (base[0] * 0.18 + 0.02, base[1] * 0.15 + 0.016, base[2] * 0.12 + 0.012, 1.0)
        mix1 = nodes.new("ShaderNodeMix"); mix1.data_type = "RGBA"
        mix1.inputs["B"].default_value = dirtcol
        mix1.inputs["A"].default_value = (*base, 1.0)
        links.new(scale.outputs[0], mix1.inputs["Factor"])
        # edge wear: bevel normal vs geometry normal
        bev = nodes.new("ShaderNodeBevel"); bev.inputs["Radius"].default_value = 0.012; bev.samples = 6
        geo = nodes.new("ShaderNodeNewGeometry")
        dot = nodes.new("ShaderNodeVectorMath"); dot.operation = "DOT_PRODUCT"
        links.new(bev.outputs["Normal"], dot.inputs[0]); links.new(geo.outputs["Normal"], dot.inputs[1])
        edge = nodes.new("ShaderNodeMapRange"); edge.clamp = True
        edge.inputs["From Min"].default_value = 0.985; edge.inputs["From Max"].default_value = 0.90
        edge.inputs["To Min"].default_value = 0.0; edge.inputs["To Max"].default_value = 0.9
        links.new(dot.outputs["Value"], edge.inputs["Value"])
        ec = edge_color or (min(base[0] * 1.9 + 0.12, 0.9), min(base[1] * 1.9 + 0.12, 0.9), min(base[2] * 1.8 + 0.10, 0.9), 1.0)
        mix2 = nodes.new("ShaderNodeMix"); mix2.data_type = "RGBA"
        mix2.inputs["B"].default_value = ec
        links.new(mix1.outputs["Result"], mix2.inputs["A"])
        links.new(edge.outputs["Result"], mix2.inputs["Factor"])
        links.new(mix2.outputs["Result"], bsdf.inputs["Base Color"])
        tex = nodes.new("ShaderNodeTexImage"); tex.image = img
        nodes.active = tex
        created[m.name] = (nt, bsdf, tex, [ao, tc, noise, ramp, inv, add, mulg, scale, mix1, bev, geo, dot, edge, mix2])
    bpy.ops.object.bake(type="DIFFUSE", pass_filter={"COLOR"}, margin=4, use_clear=True)
    img.filepath_raw = os.path.join(OUT_DIR, tex_name + ".png")
    img.file_format = "PNG"
    img.save()
    for name, (nt, bsdf, tex, helpers) in created.items():
        for n in helpers:
            nt.nodes.remove(n)
        nt.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    return img
