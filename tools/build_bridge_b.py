import bpy, math, os, json, sys
from pathlib import Path
from mathutils import Vector
from mathutils.bvhtree import BVHTree
ROOT=str(Path(__file__).resolve().parents[1])
OUT=os.path.join(ROOT,'assetss','radio_room_v2'); QA=os.path.join(ROOT,'.codex_qa','radio_room_v2')
BRIDGE=True
if BRIDGE: OUT=os.path.join(ROOT,'assetss','ship_bridge_b')
os.makedirs(OUT,exist_ok=True); os.makedirs(QA,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials): bpy.data.materials.remove(m)
def xyz(p): return (p[0],-p[2],p[1])
def material(name,color,metal=0,rough=.8,image=None,emission=0):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True; bs=m.node_tree.nodes.get('Principled BSDF'); bs.inputs['Base Color'].default_value=(*color,1); bs.inputs['Metallic'].default_value=metal; bs.inputs['Roughness'].default_value=rough
 if image:
  t=m.node_tree.nodes.new('ShaderNodeTexImage'); t.image=bpy.data.images.load(os.path.join(ROOT,image),check_existing=True); t.image.pack(); t.interpolation='Closest'
  # Mix pigment tint into image, rather than replacing the intended dark paint.
  mix=m.node_tree.nodes.new('ShaderNodeMixRGB'); mix.blend_type='MULTIPLY'; mix.inputs[0].default_value=1; mix.inputs[2].default_value=(*color,1); m.node_tree.links.new(t.outputs['Color'],mix.inputs[1]); m.node_tree.links.new(mix.outputs[0],bs.inputs['Base Color'])
 if emission: bs.inputs['Emission Color'].default_value=(*color,1); bs.inputs['Emission Strength'].default_value=emission
 return m
paint=material('ivory_aged',(.68,.70,.64),.15,.86,'assetss/interior_experimental_textures_v1/ivory_paint_candidate.png')
wall_paint=material('wall_bridge',(.30,.32,.30),.1,.9)
dark=material('structural_graphite',(.065,.082,.079),.4,.78)
steel=material('brushed_edges',(.22,.26,.24),.65,.67)
black=material('black_rubber',(.018,.024,.021),0,.97)
rust=material('oxidised_red_cable',(.22,.065,.035),.1,.85)
floor=material('deck_plate',(.38,.43,.4),.3,.85,'assetss/interior_experimental_textures_v1/floor_tread_candidate.png')
cloth=material('seat_olive_vinyl',(.105,.13,.1),0,.87)
screen=material('crt_phosphor',(.045,.3,.15),0,.5,emission=.9)
trace=material('crt_trace',(.16,.75,.4),0,.4,emission=1.0)
lamp=material('lamp_diffuser',(.6,.68,.55),0,.8,emission=1.2)
amber=material('amber_indicator',(.75,.25,.045),0,.7,emission=1.0)
paper=material('label_ivory',(.42,.43,.34),0,.9)
viewport_glass=material('viewport_glass',(.11,.19,.23),0,.18)
viewport_glass.node_tree.nodes.get('Principled BSDF').inputs['Alpha'].default_value=.22
objects=[]
def mesh(name,vs,fs,mat,bevel=0):
 me=bpy.data.meshes.new(name); me.from_pydata([xyz(v) for v in vs],[],fs); me.update(); me.materials.append(mat)
 ob=bpy.data.objects.new(name,me); bpy.context.collection.objects.link(ob); objects.append(ob)
 uv=me.uv_layers.new(name='UVMap')
 for p in me.polygons:
  drop=max(range(3),key=lambda k:abs(p.normal[k])); axes=[k for k in range(3) if k!=drop]
  for li in p.loop_indices:
   v=me.vertices[me.loops[li].vertex_index].co; uv.data[li].uv=(v[axes[0]]*.7,v[axes[1]]*.7)
 if bevel:
  mod=ob.modifiers.new('Machined edge','BEVEL'); mod.width=bevel; mod.segments=1
  mod.affect='EDGES'
 return ob
faces_box=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
def box(name,c,s,mat,bevel=.008):
 return mesh(name,[(c[0]+i*s[0]/2,c[1]+j*s[1]/2,c[2]+k*s[2]/2) for i,j,k in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]],faces_box,mat,bevel)
def beam(name,a,b,w,d,mat,bevel=.004):
 a=Vector(a); b=Vector(b); dr=(b-a).normalized(); ref=Vector((0,0,1))
 if abs(dr.dot(ref))>.95: ref=Vector((1,0,0))
 u=dr.cross(ref).normalized()*w/2; v=dr.cross(u).normalized()*d/2
 return mesh(name,[tuple(p+u*i+v*j) for p in (a,b) for i,j in [(-1,-1),(1,-1),(1,1),(-1,1)]],faces_box,mat,bevel)
def cyl(name,c,r,length,axis,mat,n=12):
 axis=Vector(axis).normalized(); ref=Vector((0,1,0))
 if abs(axis.dot(ref))>.95: ref=Vector((1,0,0))
 u=axis.cross(ref).normalized(); v=axis.cross(u).normalized(); c=Vector(c)
 vs=[tuple(c+axis*t*length/2+r*(u*math.cos(i*2*math.pi/n)+v*math.sin(i*2*math.pi/n))) for t in (-1,1) for i in range(n)]
 fs=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 return mesh(name,vs,fs,mat,.002)
def plate(name,a,b,z0,z1,mat,depth=.025):
 # strip with true thickness, normal toward the room centre
 a=Vector(a); b=Vector(b); dr=(b-a).normalized(); norm=Vector((-dr.y,dr.x))
 mid=(a+b)/2
 if norm.dot(Vector((0,1.3))-mid)<0:norm=-norm
 vs=[]
 for t in (0,depth):
  aa=a+norm*t; bb=b+norm*t
  vs.extend([(aa.x,aa.y,z0),(bb.x,bb.y,z0),(bb.x,bb.y,z1),(aa.x,aa.y,z1)])
 return mesh(name,vs,faces_box,mat,.004)
contour=[(-1.65,0),(-1.93,.28),(-1.93,1.64),(-1.75,2.12),(-1.27,2.49),(-.65,2.68),(.65,2.68),(1.27,2.49),(1.75,2.12),(1.93,1.64),(1.93,.28),(1.65,0)]
# Each bay is one shell strip; ribs sit in deliberately reserved gaps.
for k,(a,b) in enumerate(zip(contour,contour[1:])):
 plate('Hull backing %02d'%k,a,b,-2.4,2.4,dark,0.012)
 for j in range(4):
  z0=-2.4+j*1.2+.07; z1=z0+1.06
  # two proper equipment recesses, no opaque backing panel over their fronts
  if k in (1,9) and j in (1,2):continue
  plate('Inset shell panel %02d %02d'%(k,j),a,b,z0,z1,wall_paint,.035)
# One joined faceted arch per station, no overlapping separate beams at corners.
for z in [-2.37,-1.2,0,1.2,2.37]:
 inner=[]
 for x,y in contour:
  vec=Vector((-x,1.3-y)).normalized()*.085; inner.append((x+vec.x,y+vec.y))
 vs=[]
 for zz in (z-.035,z+.035):
  for ring in (contour,inner):vs +=[(x,y,zz) for x,y in ring]
 n=len(contour); fs=[]
 for i in range(n-1):
  fs.extend([(i,i+1,n+i+1,n+i),(2*n+i,3*n+i,3*n+i+1,2*n+i+1),(i,2*n+i,2*n+i+1,i+1),(n+i,n+i+1,3*n+i+1,3*n+i)])
 fs.extend([(0,n,3*n,2*n),(n-1,3*n-1,4*n-1,2*n-1)])
 mesh('Pressure rib %.2f'%z,vs,fs,steel,.006)
box('Deck foundation',(0,-.075,0),(3.3,.15,4.8),dark)
for j in range(6):
 z=-2+j*.8
 box('Deck tile %d'%j,(0,.012,z),(2.62,.024,.775),floor,.003)
 for x in (-1.49,1.49):box('Edge removable plate',(x,.012,z),(.3,.024,.775),steel,.003)
# Back bulkhead: solid pressure wall with a true aperture for an observation window.
n=len(contour); z_front=2.38; z_back=2.49
wall_vertices=[(x,y,z) for z in (z_front,z_back) for x,y in contour]
wall_faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
wall_faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
aft_wall=mesh('Aft pressure wall',wall_vertices,wall_faces,wall_paint)
# The cutter is aligned to Blender Y, the normal of the bulkhead after xyz() mapping.
bpy.ops.mesh.primitive_cylinder_add(vertices=8, radius=1, depth=.24,
    location=(-.35,-2.435,1.22), rotation=(math.radians(90),0,0))
window_cutter=bpy.context.object; window_cutter.name='Temporary observation-window cutter'
window_cutter.scale=(.64,.84,1); bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
window_boolean=aft_wall.modifiers.new('Cut observation-window aperture','BOOLEAN')
window_boolean.operation='DIFFERENCE'; window_boolean.solver='EXACT'; window_boolean.object=window_cutter
bpy.context.view_layer.objects.active=aft_wall
bpy.ops.object.modifier_apply(modifier=window_boolean.name)
bpy.data.objects.remove(window_cutter,do_unlink=True)
def octagon(name,c,rx,ry,depth,mat):
 vs=[]
 for z in (c[2]-depth/2,c[2]+depth/2):
  vs +=[(c[0]+rx*math.cos((i+.5)*math.pi/4),c[1]+ry*math.sin((i+.5)*math.pi/4),z) for i in range(8)]
 return mesh(name,vs,[tuple(range(7,-1,-1)),tuple(range(8,16))]+[(i,(i+1)%8,(i+1)%8+8,i+8) for i in range(8)],mat,.008)
def octagon_ring(name,c,rx_outer,ry_outer,rx_inner,ry_inner,depth,mat):
 vs=[]
 for z in (c[2]-depth/2,c[2]+depth/2):
  for rx,ry in ((rx_outer,ry_outer),(rx_inner,ry_inner)):
   vs +=[(c[0]+rx*math.cos((i+.5)*math.pi/4),c[1]+ry*math.sin((i+.5)*math.pi/4),z) for i in range(8)]
 fs=[]
 for i in range(8):
  j=(i+1)%8
  fs.extend([(i,j,8+j,8+i),(16+i,24+i,24+j,16+j),
             (i,16+i,16+j,j),(8+i,8+j,24+j,24+i)])
 return mesh(name,vs,fs,mat,.008)
octagon_ring('Viewport outer gasket',(-.35,1.22,2.355),.80,1.00,.72,.92,.085,black)
octagon_ring('Viewport steel coaming',(-.35,1.22,2.305),.735,.93,.635,.835,.07,steel)
octagon_ring('Viewport sealing lip',(-.35,1.22,2.285),.675,.865,.615,.815,.05,dark)
octagon('Viewport laminated glass',(-.35,1.22,2.505),.625,.825,.025,viewport_glass)
for i in range(8):
 q=(i+.5)*math.pi/4
 cyl('Viewport locking stud',(-.35+.70*math.cos(q),1.22+.89*math.sin(q),2.255),.026,.035,(0,0,1),black,8)
# Entry surrounds open 1.25m central passage; side walls follow the hull.
for side in (-1,1):box('Entry side',(side*1.30,1.05,-2.43),(1.25,2.1,.08),wall_paint)
box('Entry lintel',(0,2.4,-2.43),(3.3,.5,.08),wall_paint)
for x in (-.66,.66):box('Entry jamb',(x,1.075,-2.39),(.07,2.15,.10),steel)
# Exposed services occupy recesses, clear of rib fronts and workspaces.
for side in (-1,1):
 for i in range(3):
  y=1.82+i*.075
  cyl('Cable run',(side*1.78,y,0),.025,3.9,(0,0,1),rust if i==1 else black,8)
 for z in (-1.65,-.65,.65,1.65):box('Cable saddle',(side*1.76,1.895,z),(.035,.24,.035),steel,.002)
 for z in (-.6,.6):
  box('Recess backplate',(side*1.94,1.15,z),(.025,.85,1.06),dark)
  if side==-1:
   box('Service cassette',(side*1.82,1.18,z),(.18,.55,.70),steel)
   box('Service recessed door',(side*1.715,1.18,z),(.022,.45,.60),dark)
   for yy in (.99,1.1,1.21,1.32):box('Cassette vent',(side*1.696,yy,z),(.012,.024,.45),black,.001)
# Right console: shaped pedestal sides and a solid sloped control surface.
x0,x1=.98,1.72; z0,z1=.12,1.72
for z in (z0+.05,z1-.05):
 profile=[(x0,.72),(x0,.84),(1.1,.9),(x1,1.25),(x1,.08),(1.52,.08),(1.48,.66)]
 vs=[(x,y,zz) for zz in (z-.025,z+.025) for x,y in profile]; n=len(profile)
 mesh('Console cheek',vs,[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)],paint,.012)
box('Worktop front lip',(1.015,.79,.92),(.09,.06,1.55),steel,.012)
# Extruded top slab with controls seated above its exact plane.
mesh('Sloped panel chassis',[(.99,.83,z0),(1.73,1.24,z0),(1.73,1.24,z1),(.99,.83,z1),(.99,.79,z0),(1.73,1.20,z0),(1.73,1.20,z1),(.99,.79,z1)],faces_box,dark,.012)
slope=.41/.74; normal=Vector((-slope,1,0)).normalized()
def panel_y(x):return .83+(x-.99)*slope
for x in (1.14,1.37):
 for z in (.30,.51,.72):
  y=panel_y(x)+.023
  cyl('Switch washer',(x,y,z),.032,.015,normal,steel,10)
  beam('Toggle lever',(x,y+.015,z),(x-.027,y+.075,z),.016,.016,black,.002)
for z in (.97,1.21,1.45):
 x=1.17; y=panel_y(x)+.027
 cyl('Knurled tuning dial',(x,y,z),.062,.047,normal,steel,12)
 beam('Dial index',(x-.015,y+.027,z-.035),(x-.015,y+.027,z+.005),.008,.008,paper,.001)
# CRT body is tapered, with inclined face and an inset bevelled bezel.
vs=[(1.27,1.24,.88),(1.27,1.79,.88),(1.27,1.79,1.57),(1.27,1.24,1.57),(1.77,1.30,.98),(1.77,1.70,.98),(1.77,1.70,1.47),(1.77,1.30,1.47)]
mesh('Tapered CRT housing',vs,faces_box,dark,.025)
box('CRT bezel',(1.23,1.515,1.225),(.07,.52,.66),steel,.015)
box('CRT inner seal',(1.185,1.53,1.225),(.02,.405,.51),black,.009)
box('CRT glass',(1.17,1.53,1.225),(.012,.355,.46),screen,.014)
# Explicit low-poly phosphor trace replaces an unrelated stretched screenshot.
for j in range(22):
 z=.998+j*.0205; z2=z+.0205; y=1.53+.055*math.sin(j*.65); yy=1.53+.055*math.sin((j+1)*.65)
 beam('Phosphor waveform',(1.161,y,z),(1.161,yy,z2),.002,.003,trace,0)
for y in (1.43,1.53,1.63):beam('CRT grid',(1.164,y,1.01),(1.164,y,1.44),.001,.001,screen,0)
for z in (1.05,1.16,1.27,1.38):beam('CRT grid',(1.164,1.40,z),(1.164,1.66,z),.001,.001,screen,0)
# Chair faces +X; its entire envelope ends before console leading edge.
cx,cz=.40,.96
cyl('Chair swivel column',(cx,.27,cz),.055,.42,(0,1,0),steel)
for a in range(5):
 q=a*2*math.pi/5; beam('Chair foot',(cx,.075,cz),(cx+.29*math.cos(q),.06,cz+.29*math.sin(q)),.05,.04,dark)
box('Seat undertray',(cx,.45,cz),(.47,.065,.51),dark,.018)
box('Cushion',(cx,.51,cz),(.46,.08,.49),cloth,.034)
beam('Back support',(.17,.43,cz),(.10,1.05,cz),.045,.07,steel)
mesh('Formed seat back',[(.12,.61,cz-.23),(.045,1.07,cz-.20),(.045,1.07,cz+.20),(.12,.61,cz+.23),(.075,.61,cz-.23),(0,1.07,cz-.20),(0,1.07,cz+.20),(.075,.61,cz+.23)],faces_box,cloth,.018)
# Left radio rack, separated from both passage and hull ribs.
box('Radio shelf',(-1.48,.89,.75),(.58,.06,1.1),steel,.01)
for z in (.3,1.2):beam('Shelf bracket',(-1.82,.64,z),(-1.23,.85,z),.04,.04,steel)
box('Receiver body',(-1.51,1.12,.76),(.43,.39,.88),dark,.028)
box('Receiver face',(-1.28,1.12,.76),(.025,.33,.80),steel,.005)
box('Analogue meter recess',(-1.26,1.17,.58),(.015,.15,.28),black,.004)
box('Analogue meter face',(-1.248,1.17,.58),(.008,.12,.24),paper,.004)
beam('Meter needle',(-1.242,1.12,.58),(-1.242,1.20,.52),.006,.006,black,0)
for z in (.84,1.03):cyl('Receiver control',(-1.22,1.06,z),.046,.045,(1,0,0),black)
# Single functional vent grille below the service rack, no floating dark overlays.
box('Vent recessed body',(-1.85,.42,-.55),(.12,.35,.72),dark)
for z in [-.84+i*.075 for i in range(9)]:box('Vent louvre',(-1.775,.42,z),(.045,.27,.027),steel,.002)
# Overhead caged fixture and a small rear amber utility light.
cyl('Overhead housing',(0,2.48,-.4),.21,.16,(0,1,0),dark,12)
cyl('Overhead diffuser',(0,2.385,-.4),.17,.025,(0,1,0),lamp,12)
for x in (-.10,0,.10):beam('Lamp cage',(x,2.36,-.54),(x,2.36,-.26),.012,.012,steel)
box('Utility lamp backing',(-1.31,1.85,2.32),(.18,.32,.07),dark)
box('Utility amber lens',(-1.31,1.85,2.265),(.095,.22,.03),amber,.012)
# Preserve editable pieces; export merges only after the blend is saved.
if BRIDGE:
 for ob in list(objects):
  if ob.name.startswith(('Receiver body','Receiver face','Receiver control','Analogue meter','Meter needle')):
   objects.remove(ob); bpy.data.objects.remove(ob,do_unlink=True)
scene=bpy.context.scene; scene.world.color=(.008,.01,.009)
bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'radio_room_v2.blend'))
deps=bpy.context.evaluated_depsgraph_get()
def bvh(ob):
 evaluated=ob.evaluated_get(deps); me=evaluated.to_mesh()
 tree=BVHTree.FromPolygons([ob.matrix_world@v.co for v in me.vertices],[list(p.vertices) for p in me.polygons])
 evaluated.to_mesh_clear(); return tree
chair_parts=[o for o in objects if o.name.startswith(('Cushion','Seat undertray','Formed seat back','Back support','Chair foot'))]
console_parts=[o for o in objects if o.name.startswith(('Console cheek','Sloped panel chassis','Worktop front lip'))]
intersections=[]
for a in chair_parts:
 for b in console_parts:
  if bvh(a).overlap(bvh(b)):intersections.append([a.name,b.name])
crt_collisions=bvh(bpy.data.objects['Tapered CRT housing']).overlap(bvh(bpy.data.objects['Sloped panel chassis']))
if intersections or crt_collisions:raise RuntimeError(('Unexpected furniture intersections',intersections,len(crt_collisions)))
# Flatten evaluated geometry by material for the runtime, retaining editable source above.
groups={}
for ob in objects:
 evaluated=ob.evaluated_get(deps); me=evaluated.to_mesh(); name=ob.data.materials[0].name
 g=groups.setdefault(name,{'vs':[],'fs':[],'uv':[]}); offset=len(g['vs'])
 g['vs'].extend([tuple(ob.matrix_world@v.co) for v in me.vertices])
 for p in me.polygons:
  g['fs'].append(tuple(offset+i for i in p.vertices))
  g['uv'].append([tuple(me.uv_layers.active.data[i].uv) for i in p.loop_indices])
 evaluated.to_mesh_clear()
bpy.ops.object.select_all(action='DESELECT')
merged=[]
for name,g in groups.items():
 me=bpy.data.meshes.new('Runtime '+name); me.from_pydata(g['vs'],[],g['fs']); me.update(); me.materials.append(bpy.data.materials[name]); uv=me.uv_layers.new(name='UVMap')
 for p,coords in zip(me.polygons,g['uv']):
  for li,coord in zip(p.loop_indices,coords):uv.data[li].uv=coord
 ob=bpy.data.objects.new('Runtime '+name,me); bpy.context.collection.objects.link(ob); ob.select_set(True); merged.append(ob)
bpy.context.view_layer.objects.active=merged[0]
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'radio_room_v2.glb'),export_format='GLB',use_selection=True,export_apply=True)
report={'chair_x_envelope':[-.03,.70],'console_x_envelope':[.98,1.77],'minimum_chair_console_gap_m':.28,'walkway_x':[-.7,-.1],'entry_width':1.25,'floor_top':.024,'ceiling_max':2.68,'camera':[-.48,1.57,-2.15],'target':[.18,1.32,.65],'source_objects':len(objects),'export_meshes':len(merged),'triangles':sum(sum(len(f)-2 for f in g['fs']) for g in groups.values()),'chair_console_surface_intersections':intersections,'crt_panel_surface_intersection_count':len(crt_collisions),'notes':'Editable source preserved. Physical mounts are deliberate contacts. No gameplay integrated.'}
with open(os.path.join(QA,'report.json'),'w') as f:json.dump(report,f,indent=2)
print('BUILD_OK',len(objects))
