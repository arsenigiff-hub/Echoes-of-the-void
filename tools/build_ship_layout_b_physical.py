"""Build the production room mesh with a dogleg airlock tunnel.

The canonical B layout stays untouched; this wrapper applies the approved
physical portal to a separate asset so it is easy to compare or roll back.
Run with Blender's --background --python.
"""
from pathlib import Path
import json

ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "tools" / "build_ship_layout_b.py"
source = SOURCE.read_text(encoding="utf-8")

replacements = [
    ("OUT=os.path.join(ROOT,'assetss','ship_layout_b'); QA=os.path.join(ROOT,'.codex_qa','ship_layout_b')",
     "OUT=os.path.join(ROOT,'assetss','ship_layout_b_physical'); QA=os.path.join(ROOT,'.codex_qa','physical_airlock')"),
    ("wall('airlock','x',-2,2,6);wall('airlock','x',2,2,6);wall('airlock','z',6,-2,2)",
     "wall('airlock','x',-2,2,6);door('airlock','x',2,2,6,5.0,1.5);wall('airlock','z',6,-2,2)"),
    ("for z in (z0+.18,z0+1.25,z1-1.25,z1-.18):arch(zone,z)",
     "for z in (z0+.18,z0+1.25,z1-1.25,z1-.18):\n"
     "  if zone=='airlock' and abs(z-4.75)<.01: continue\n"
     "  arch(zone,z)"),
    ("# External hatch is a raised solid octagonal leaf over a closed bulkhead, surface facing room.\ndef hatch(c,r,mat,z):\n x,y=c; vs=[(x+r*math.cos((i+.5)*math.pi/4),y+r*math.sin((i+.5)*math.pi/4),z) for i in range(8)]; geom('airlock',mat,vs,[tuple(reversed(range(8)))])\nhatch((0,1.2),.95,black,5.92);hatch((0,1.2),.86,steel,5.90);hatch((0,1.2),.77,wall_materials['airlock'],5.88)\nfor y in (.57,1.83):box('airlock',dark,(-.57,y,5.84),(.13,.17,.07))\ncyl('airlock',steel,(.34,1.2,5.83),.08,.06,(0,0,1),10)\n",
     "# The former dead-end hatch plate was removed; the side bulkhead now opens into the dogleg tunnel.\n"),
    ("box('airlock',dark,(1.69,.78,4.77),(.42,1.44,1.05),'console');box('airlock',paint,(1.44,1.25,4.77),(.035,.38,.86));box('airlock',green,(1.415,1.30,4.78),(.015,.17,.33))\nfor z in (4.47,4.60,4.73):cyl('airlock',steel,(1.405,1.08,z),.028,.03,(1,0,0),8)\nbox('airlock',dark,(1.65,.44,3.10),(.48,.12,1.2),'bench');box('airlock',cloth,(1.65,.53,3.10),(.46,.08,1.18))\nfor z in (2.65,3.55):box('airlock',steel,(1.65,.22,z),(.06,.44,.06))\n",
     "box('airlock',dark,(-1.69,.78,4.77),(.42,1.44,1.05),'console');box('airlock',paint,(-1.44,1.25,4.77),(.035,.38,.86));box('airlock',green,(-1.415,1.30,4.78),(.015,.17,.33))\nfor z in (4.47,4.60,4.73):cyl('airlock',steel,(-1.405,1.08,z),.028,.03,(1,0,0),8)\nbox('airlock',dark,(1.35,.44,3.10),(.42,.12,1.2),'bench');box('airlock',cloth,(1.35,.53,3.10),(.40,.08,1.18))\nfor z in (2.65,3.55):box('airlock',steel,(1.35,.22,z),(.06,.44,.06))\n"),
]
for before, after in replacements:
    if before not in source:
        raise RuntimeError(f"Expected source block not found: {before[:100]!r}")
    source = source.replace(before, after, 1)

tunnel_code = r'''
# Dogleg access passage: a single concave footprint keeps the turn sealed and walkable.
def add_access_tunnel():
    # Room-local X/Z outline. End at z=6 is the enlarged outside portal;
    # the x=2 edge is the 1.5 m pressure-door opening into the EVA bay.
    outline = [(2.0,4.25),(4.1,4.25),(4.1,5.25),(4.2375,5.25),
               (4.2375,6.0),(2.7375,6.0),(2.7375,5.75),(2.0,5.75)]
    floor_y, ceiling_y = .035, 2.15
    floor_vertices = [(x,floor_y,z) for x,z in outline]
    ceiling_vertices = [(x,ceiling_y,z) for x,z in outline]
    # Winding is chosen so the floor/ceiling normals point into the passage.
    geom('airlock_tunnel',floor,list(reversed(floor_vertices)),[tuple(range(8))])
    geom('airlock_tunnel',dark,ceiling_vertices,[tuple(range(8))])
    # Omit the two portal edges; all remaining perimeter edges are sealed walls.
    # Open the matching sidewall doorway and the outer hull portal.
    open_edges = {4,7}
    for i,(a,b) in enumerate(zip(outline,outline[1:]+outline[:1])):
        if i in open_edges:
            continue
        ax,az=a; bx,bz=b
        quad=[(ax,floor_y,az),(bx,floor_y,bz),(bx,ceiling_y,bz),(ax,ceiling_y,az)]
        geom('airlock_tunnel',wall_materials['airlock'],quad,[(0,1,2,3)])
    # Ceiling cross-braces give the passage a pressure-rated structure without
    # placing floor-to-ceiling posts in the player's swept capsule path.
    for z in (5.18,5.62,5.91):
        beam('airlock_tunnel',steel,(2.05,2.12,z),(4.20,2.12,z),.035,.035)
        beam('airlock_tunnel',steel,(4.20,.10,z),(4.20,2.12,z),.035,.035)
        if abs(z-5.91)<.01:
            beam('airlock_tunnel',steel,(2.77,.10,z),(2.77,2.12,z),.035,.035)
    for x in (2.05,3.43):
        beam('airlock_tunnel',steel,(x,2.12,4.29),(x,2.12,5.71),.035,.035)
    for y in (2.10,2.135):
        cyl('airlock_tunnel',black,(3.45,y,5.52),.018,1.05,(1,0,0),8)

add_access_tunnel()
'''
marker = "# Build one editable mesh per zone/material with metric UVs; all textural images packed.\n"
if marker not in source:
    raise RuntimeError("Could not find mesh build section")
source = source.replace(marker, tunnel_code + "\n" + marker, 1)

source = source.replace("'airlock_console':[1.44,1.25,4.77]", "'airlock_console':[-1.44,1.25,4.77]")
source = source.replace("'airlock_bench':[1.65,.53,3.1]", "'airlock_bench':[1.35,.53,3.1]")
source = source.replace("'External hatch is static.'", "'Dogleg tunnel opens at outer z=6 and at airlock sidewall x=2, z=5; nominal clear width 1.5m, height 2.115m.'")

namespace = {"__file__": str(SOURCE), "__name__": "__main__"}
exec(compile(source, str(SOURCE), "exec"), namespace)

report_path = ROOT / ".codex_qa" / "physical_airlock" / "report.json"
report = json.loads(report_path.read_text(encoding="utf-8"))
report["physical_airlock"] = {
    "layout_asset": "res://assetss/ship_layout_b_physical/ship_layout_b_physical.glb",
    "portal_outer_center_local": [3.4875, 1.1, 6.0],
    "portal_inner_center_local": [2.0, 1.1, 5.0],
    "clear_width_m": 1.5,
    "clear_height_m": 2.115,
    "layout_side_door": {"axis": "x", "wall_x": 2.0, "center_z": 5.0},
}
report_path.write_text(json.dumps(report, ensure_ascii=False, indent=2), encoding="utf-8")
print("PHYSICAL_AIRLOCK_REPORT", json.dumps(report["physical_airlock"], ensure_ascii=False))
