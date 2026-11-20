"""Create a wider hatch leaf and hull aperture while preserving the EVA deck."""
from pathlib import Path
import math

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / ".codex_qa" / "airlock_geometry" / "build_platform_preview.py"
source = SOURCE.read_text(encoding="utf-8")
source = source.replace(
    "HULL=ROOT/'assetss/ship_exterior/ship_hull_v2_eva.glb'",
    "HULL=ROOT/'assetss/ship_exterior/ship_hull_v2_eva.glb'",
)
source = source.replace(
    "HATCH=ROOT/'assetss/ship_exterior/airlock_hatch_v2.glb'",
    "HATCH=ROOT/'assetss/ship_exterior/airlock_hatch_v3_wide.glb'",
)
source = source.replace(
    "OUT=ROOT/'.codex_qa/airlock_geometry/ship_hull_v2_eva_platform_preview.glb'",
    "OUT=ROOT/'assetss/ship_exterior/ship_hull_v2_eva_platform_wide_airlock.glb'",
)
source = source.replace(
    "PREVIEW=ROOT/'.codex_qa/airlock_geometry/platform_lower_wider_preview.png'",
    "PREVIEW=ROOT/'.codex_qa/physical_airlock/hull_hatch_blender_preview.png'",
)
marker = "# A low, chamfered EVA landing deck that docks beneath the hatch without legs.\n"
cut = r'''
# Widen the existing shell bore to a clipped-corner human-sized portal before
# creating and joining the EVA deck. Both hull skins are cleared; the deck stays intact.
half_w, half_h, clip = .89, 1.18, .22
cross=[(-half_w+clip,-half_h),(half_w-clip,-half_h),(half_w,-half_h+clip),
       (half_w,half_h-clip),(half_w-clip,half_h),(-half_w+clip,half_h),
       (-half_w,half_h-clip),(-half_w,-half_h+clip)]
verts=[]
for x in (-10.0,-7.05):
    verts.extend((x,-11.90+y,3.30+z) for y,z in cross)
faces=[tuple(reversed(range(8))),tuple(range(8,16))]
for i in range(8):
    j=(i+1)%8
    faces.append((i,j,j+8,i+8))
cut_mesh=bpy.data.meshes.new('TEMP_Wide_Airlock_CutterMesh')
cut_mesh.from_pydata(verts,[],faces); cut_mesh.update()
cutter=bpy.data.objects.new('TEMP_Wide_Airlock_Cutter',cut_mesh)
bpy.context.collection.objects.link(cutter)
mod=hull.modifiers.new('Wide through hull airlock', 'BOOLEAN')
mod.operation='DIFFERENCE'; mod.solver='EXACT'; mod.object=cutter
bpy.context.view_layer.objects.active=hull
bpy.ops.object.modifier_apply(modifier=mod.name)
bpy.data.objects.remove(cutter, do_unlink=True)
# The source hull is a thin shell, so the Boolean leaves two flat closing caps
# across the cut depth. Remove only those cap triangles inside the octagonal bore.
bm=bmesh.new(); bm.from_mesh(hull.data); bm.normal_update()
portal_caps=[]
for face in bm.faces:
    center=hull.matrix_world @ face.calc_center_median()
    normal=(hull.matrix_world.to_3x3() @ face.normal).normalized()
    if abs(normal.x)<.95 or abs(center.y+11.90)>.95 or not (2.0<center.z<4.6):
        continue
    if abs(center.x+7.05)<.005 or abs(center.x+10.0)<.005:
        portal_caps.append(face)
if portal_caps:
    bmesh.ops.delete(bm,geom=portal_caps,context='FACES_ONLY')
    loose=[vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm,geom=loose,context='VERTS')
    bm.to_mesh(hull.data)
print('REMOVED_PORTAL_BOOLEAN_CAPS',len(portal_caps))
bm.free()
print('WIDENED_HULL_APERTURE clear_width=1.78m clear_height=2.36m depth=2.95m deck_not_joined_yet')
'''
if marker not in source:
    raise RuntimeError("Could not find the EVA deck creation marker")
source = source.replace(marker, cut + "\n" + marker, 1)
post_join_marker = "# Hatch is retained for the render only; it remains a separate runtime scene in Godot.\n"
post_join = r'''
# The joined landing deck and the source hull contain a few thin internal wall
# slivers behind the Boolean cut. Remove only x-facing faces inside the player
# clearance envelope, otherwise the doorway works in one direction only.
bm=bmesh.new(); bm.from_mesh(hull.data); bm.normal_update()
portal_clearance_faces=[]
for face in bm.faces:
    center=hull.matrix_world @ face.calc_center_median()
    normal=(hull.matrix_world.to_3x3() @ face.normal).normalized()
    if abs(normal.x)<.95:
        continue
    if -9.95<center.x<-7.10 and abs(center.y+11.90)<.84 and 2.24<center.z<4.36:
        portal_clearance_faces.append(face)
if portal_clearance_faces:
    bmesh.ops.delete(bm,geom=portal_clearance_faces,context='FACES_ONLY')
    loose=[vertex for vertex in bm.verts if not vertex.link_faces]
    if loose:
        bmesh.ops.delete(bm,geom=loose,context='VERTS')
    bm.to_mesh(hull.data)
print('REMOVED_PORTAL_CLEARANCE_FACES',len(portal_clearance_faces))
bm.free()
'''
if post_join_marker not in source:
    raise RuntimeError("Could not find the post-join export marker")
source = source.replace(post_join_marker, post_join + "\n" + post_join_marker, 1)
source = source.replace(
    "hatch=next(o for o in bpy.context.scene.objects if o.type=='MESH' and o!=hull)\nhatch.location.y+=0.72",
    "hatch=next(o for o in bpy.context.scene.objects if o.type=='MESH' and o!=hull)\n"
    "# The separate v3 asset has a fixed frame and a hinged leaf.\n"
    "print('RENDERING_WITH_HATCH_V3')",
)
if "hatch.location.y+=0.72" in source:
    raise RuntimeError("Old hatch alignment was not replaced")
source = source.replace("import bpy, bmesh, math\n", "import bpy, bmesh, math\n")
namespace = {"__file__": str(SOURCE), "__name__": "__main__"}
exec(compile(source, str(SOURCE), "exec"), namespace)
