import bpy, math, json, os, time
from mathutils import Vector
from pathlib import Path
T=time.time(); ROOT=str(Path(__file__).resolve().parents[1]); OUT=os.path.join(ROOT,'assetss','ship_details_b'); QA=os.path.join(ROOT,'.codex_qa','ship_details_b'); os.makedirs(OUT,exist_ok=True); os.makedirs(QA,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials):bpy.data.materials.remove(m)
palette={'detail_ivory':(.46,.48,.43),'detail_dark_metal':(.09,.11,.10),'detail_brushed_steel':(.26,.28,.26),'detail_cable_rubber':(.028,.035,.032),'detail_pipe_red':(.24,.065,.04),'detail_copper':(.38,.20,.11),'detail_floor_grate':(.14,.17,.16),'detail_floor_tread':(.16,.18,.17),'detail_acoustic':(.16,.18,.16),'detail_vinyl':(.19,.15,.12),'detail_blanket':(.29,.31,.27),'detail_pillow':(.50,.50,.44),'detail_oxygen':(.27,.37,.33),'detail_locker':(.38,.41,.36),'detail_laminate':(.43,.41,.34),'detail_cardboard':(.35,.27,.19),'detail_paper':(.65,.62,.52),'detail_notebook':(.18,.24,.23),'detail_foil':(.45,.44,.37),'detail_hazard':(.65,.43,.09)}
materials={}
for name,col in palette.items():
 m=bpy.data.materials.new(name);m.diffuse_color=(*col,1);m.use_nodes=True;b=m.node_tree.nodes.get('Principled BSDF');b.inputs['Base Color'].default_value=(*col,1);b.inputs['Roughness'].default_value=.87;b.inputs['Metallic'].default_value=.38 if name in ('detail_brushed_steel','detail_dark_metal','detail_copper') else .05;materials[name]=m
def P(p):return(p[0],-p[2],p[1])
objects=[]; active=''; cur=[]; reports=[]
def start(name):
 global active,cur
 if active:finish()
 active=name;cur=[]
def part(material,vs,fs):
 global cur
 me=bpy.data.meshes.new(active+'_'+material);me.from_pydata([P(p) for p in vs],[],fs);me.update();me.materials.append(materials['detail_'+material]);uv=me.uv_layers.new(name='UVMap')
 for p in me.polygons:
  drop=max(range(3),key=lambda i:abs(p.normal[i])); ax=[i for i in range(3) if i!=drop]
  for li in p.loop_indices:
   v=me.vertices[me.loops[li].vertex_index].co;uv.data[li].uv=(v[ax[0]]*.7,v[ax[1]]*.7)
 ob=bpy.data.objects.new(active+'_'+material,me);bpy.context.collection.objects.link(ob); mod=ob.modifiers.new('softened edges','BEVEL');mod.width=.003;mod.segments=1;mod.affect='EDGES';objects.append(ob);cur.extend(vs)
def finish():
 global active,cur
 if not active:return
 reports.append({'name':active,'bounds_godot':{'min':[round(min(v[i] for v in cur),3) for i in range(3)],'max':[round(max(v[i] for v in cur),3) for i in range(3)]}});active='';cur=[]
def box(mat,c,s):
 x,y,z=c;a,b,d=[n/2 for n in s];v=[(x+i*a,y+j*b,z+k*d) for i,j,k in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]];part(mat,v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
def beam(mat,a,b,w,d):
 a,b=Vector(a),Vector(b);dr=(b-a).normalized();ref=Vector((0,0,1)) if abs(dr.z)<.9 else Vector((0,1,0));u=dr.cross(ref).normalized()*w/2;v=dr.cross(u).normalized()*d/2;vs=[tuple(p+u*i+v*j) for p in (a,b) for i,j in [(-1,-1),(1,-1),(1,1),(-1,1)]];part(mat,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
def cyl(mat,c,r,length,axis=(0,1,0),n=12):
 c=Vector(c);d=Vector(axis).normalized();ref=Vector((0,0,1)) if abs(d.z)<.9 else Vector((0,1,0));u=d.cross(ref).normalized();v=d.cross(u).normalized();vs=[tuple(c+d*length*t/2+r*(u*math.cos(i*2*math.pi/n)+v*math.sin(i*2*math.pi/n))) for t in (-1,1) for i in range(n)];fs=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)];part(mat,vs,fs)
def pipe(name,a,b,mat='brushed_steel',r=.028):
 start(name);v=Vector(b)-Vector(a);cyl(mat,tuple((Vector(a)+Vector(b))/2),r,v.length,tuple(v),10)
def clamp(name,c,axis='z'):
 start(name)
 if axis=='z':box('dark_metal',c,(.10,.10,.035));box('brushed_steel',(c[0]-.05,c[1],c[2]),(.012,.13,.05))
 else:box('dark_metal',c,(.035,.11,.11))
def grille(name,c,orientation='x'):
 start(name)
 if orientation=='x':
  box('dark_metal',c,(.035,.36,.52))
  for y in (-.12,-.06,0,.06,.12):box('brushed_steel',(c[0]-.022,c[1]+y,c[2]),(.015,.018,.45))
 else:
  box('dark_metal',c,(.52,.36,.035))
  for y in (-.12,-.06,0,.06,.12):box('brushed_steel',(c[0],c[1]+y,c[2]-.022),(.45,.018,.015))
# COMMON: horizontal and vertical plumbing is attached to right wall, outside its door zone.
pipe('common pipe main',(1.82,1.58,.90),(1.82,1.58,1.67),'brushed_steel',.038)
pipe('common return line',(1.82,1.42,.90),(1.82,1.42,1.67),'pipe_red',.030)
for z in (.98,1.35,1.64):clamp('common pipe clamp %.2f'%z,(1.82,1.50,z))
pipe('common pipe drop',(1.82,1.55,1.66),(1.82,.63,1.66),'brushed_steel',.030)
start('common isolation valve');cyl('dark_metal',(1.77,1.06,1.66),.085,.035,(1,0,0));cyl('copper',(1.74,1.06,1.66),.038,.02,(1,0,0))
start('common power junction');box('dark_metal',(1.81,1.14,.94),(.12,.38,.32));box('ivory',(1.735,1.14,.94),(.022,.30,.24));box('hazard',(1.717,1.14,.94),(.012,.06,.09))
grille('common extraction grille',(1.85,1.93,1.40))
# Objects on worktable (surface y=.8275) grouped as individual meaningful props.
for i,z in enumerate((.36,.59,.83,1.10,1.36)):
 start('common paper sheet %d'%i);box('paper',(-1.34,.833+i*.001,z),(.26,.004,.18))
start('common mug');cyl('ivory',(-1.55,.89,1.52),.055,.12);cyl('dark_metal',(-1.55,.955,1.52),.040,.009);beam('ivory',(-1.49,.90,1.52),(-1.46,.90,1.52),.02,.035)
start('common wrench');beam('brushed_steel',(-1.61,.846,.34),(-1.36,.846,.42),.025,.012);cyl('brushed_steel',(-1.62,.846,.34),.035,.015)
start('common screwdriver');beam('dark_metal',(-1.62,.85,.78),(-1.53,.85,.78),.034,.025);beam('brushed_steel',(-1.53,.85,.78),(-1.36,.85,.78),.009,.009)
start('common pliers');beam('dark_metal',(-1.60,.85,1.03),(-1.45,.85,1.06),.022,.018);beam('brushed_steel',(-1.45,.85,1.06),(-1.34,.85,1.10),.017,.014)
start('common underbench crate');box('cardboard',(-1.50,.145,1.18),(.31,.24,.29));box('dark_metal',(-1.50,.278,1.18),(.32,.025,.30));box('paper',(-1.33,.16,1.18),(.012,.08,.12))
start('common wall clipboard');box('dark_metal',(-1.86,1.45,1.80),(.035,.30,.20));box('paper',(-1.835,1.45,1.80),(.01,.25,.16));box('brushed_steel',(-1.826,1.57,1.80),(.008,.025,.06))
# CABIN: bedside objects and mounted utilities; floor cluster opposite central passage.
start('quarters notebook');box('notebook',(-1.19,.615,-3.05),(.29,.026,.22));box('paper',(-1.19,.631,-3.05),(.26,.008,.19))
start('quarters reading light');box('dark_metal',(-1.84,1.30,-5.43),(.055,.16,.15));beam('brushed_steel',(-1.80,1.30,-5.43),(-1.60,1.40,-5.43),.025,.025);cyl('ivory',(-1.57,1.40,-5.43),.055,.07,(1,0,0),10)
start('quarters duffel bag');box('vinyl',(1.21,.18,-5.10),(.49,.30,.32));beam('blanket',(.99,.34,-5.1),(1.42,.34,-5.1),.032,.025);box('dark_metal',(1.21,.22,-5.27),(.18,.045,.02))
start('quarters folded fabric roll');cyl('blanket',(1.55,.135,-5.55),.10,.38,(0,0,1),12);box('vinyl',(1.55,.14,-5.55),(.21,.20,.04))
start('quarters boot left');box('vinyl',(.98,.094,-5.52),(.17,.13,.31));box('dark_metal',(.98,.036,-5.52),(.18,.02,.32))
start('quarters boot right');box('vinyl',(1.18,.094,-5.53),(.17,.13,.31));box('dark_metal',(1.18,.036,-5.53),(.18,.02,.32))
start('quarters towel rail');beam('brushed_steel',(1.10,1.55,-5.87),(1.67,1.55,-5.87),.025,.025)
start('quarters hanging towel');box('blanket',(1.42,1.24,-5.84),(.40,.58,.025));box('pillow',(1.42,1.05,-5.82),(.38,.14,.015))
start('quarters photograph frame');box('dark_metal',(-1.84,1.52,-5.72),(.045,.28,.23));box('paper',(-1.812,1.52,-5.72),(.012,.21,.16))
start('quarters personal note');box('paper',(1.5955,1.78,-4.48),(.009,.18,.13));cyl('copper',(1.587,1.84,-4.48),.012,.018,(1,0,0),8)
# AIRLOCK: pressure tools, gauges fixed outside central hatch approach.
for z in (3.10,3.53,3.96):
 start('airlock cylinder gauge %.2f'%z);cyl('brushed_steel',(-1.50,1.70,z),.095,.045,(1,0,0),12);cyl('paper',(-1.467,1.70,z),.075,.012,(1,0,0),12);beam('dark_metal',(-1.458,1.70,z),(-1.458,1.735,z+.025),.009,.009)
for z in (3.12,3.52,3.92):
 start('airlock cylinder valve %.2f'%z);cyl('copper',(-1.69,1.70,z),.065,.06,(0,1,0),10);beam('brushed_steel',(-1.79,1.75,z),(-1.59,1.75,z),.022,.022)
start('airlock sealed repair case');box('dark_metal',(1.30,.15,3.05),(.46,.25,.34));box('oxygen',(1.30,.285,3.05),(.42,.025,.30));box('brushed_steel',(1.30,.31,3.05),(.20,.02,.035))
start('airlock instruction plate');box('dark_metal',(-1.86,1.87,5.24),(.035,.44,.31));box('paper',(-1.835,1.87,5.24),(.012,.37,.25))
start('airlock wall handle');beam('brushed_steel',(-1.78,1.10,5.40),(-1.78,1.47,5.40),.035,.035);beam('brushed_steel',(-1.86,1.10,5.40),(-1.78,1.10,5.40),.03,.03);beam('brushed_steel',(-1.86,1.47,5.40),(-1.78,1.47,5.40),.03,.03)
start('airlock floor check card');box('paper',(1.10,.029,5.30),(.20,.005,.28))
# TECH: pipeline with bends, flange joints, cable tray and wall control, no mid-passage elements.
pipe('tech red pipeline A',(2.55,1.94,1.10),(4.30,1.94,1.10),'pipe_red',.038)
pipe('tech red pipeline B',(4.30,1.94,1.10),(6.42,1.94,1.10),'pipe_red',.038)
pipe('tech downpipe',(6.40,1.94,1.10),(6.40,.65,1.10),'pipe_red',.038)
for x in (2.70,3.35,4.0,4.70,5.38,6.15):
 start('tech pipeline clamp %.2f'%x);box('dark_metal',(x,1.94,1.10),(.045,.12,.10));box('brushed_steel',(x,1.94,1.04),(.055,.10,.018));beam('brushed_steel',(x,1.98,1.10),(x,2.625,1.10),.022,.022);box('brushed_steel',(x,2.625,1.10),(.16,.035,.12))
for x in (3.15,5.75):
 start('tech flange joint %.2f'%x);cyl('brushed_steel',(x,1.94,1.10),.072,.045,(1,0,0),10)
start('tech valve body');cyl('dark_metal',(4.85,1.94,1.10),.08,.12,(1,0,0));cyl('copper',(4.85,1.94,1.02),.07,.035,(0,0,1),10);beam('brushed_steel',(4.76,1.94,.99),(4.94,1.94,.99),.025,.025)
start('tech electrical tray');box('dark_metal',(6.83,1.47,-3.50),(.10,.18,3.5));box('brushed_steel',(6.76,1.55,-3.50),(.035,.025,3.5))
for y in (1.40,1.46,1.52):pipe('tech cable %.2f'%y,(6.75,y,-5.15),(6.75,y,-1.85),'cable_rubber',.015)
for z in (-4.95,-4.05,-3.15,-2.25):clamp('tech tray bracket %.2f'%z,(6.73,1.46,z))
grille('tech ventilation left',(4.52,1.94,-5.20))
grille('tech ventilation right',(6.83,2.12,-4.10))
start('tech inspection unit');box('dark_metal',(4.53,1.20,-3.70),(.10,.55,.58));box('locker',(4.595,1.20,-3.70),(.025,.46,.48));box('brushed_steel',(4.615,1.20,-3.55),(.015,.12,.025))
start('tech lowered cable wall run');beam('cable_rubber',(6.74,1.40,-2.0),(6.74,1.03,-2.10),.025,.025);beam('cable_rubber',(6.74,1.03,-2.10),(6.74,.83,-2.30),.025,.025);box('dark_metal',(6.72,.82,-2.31),(.08,.11,.10))
start('tech floor service panel');box('floor_grate',(6.30,.033,-4.8),(.38,.012,.46))
# BRIDGE: possessions deliberately away from the live radio and control panel.
for i,z in enumerate((-7.4,-7.74,-8.08)):
 start('bridge floor paper %d'%i);box('paper',(5.30,.030+i*.002,z),(.26,.005,.20))
start('bridge small cassette case');box('dark_metal',(4.60,.08,-9.90),(.30,.10,.20));box('laminate',(4.60,.137,-9.90),(.25,.012,.15));box('paper',(4.60,.145,-9.90),(.15,.005,.07))
start('bridge document folder');box('notebook',(5.30,.04,-7.08),(.36,.025,.25));box('paper',(5.30,.056,-7.08),(.28,.006,.19))
start('bridge pencil');beam('copper',(5.15,.061,-7.02),(5.35,.061,-7.10),.009,.009)
start('bridge tape reel');cyl('dark_metal',(4.55,.055,-9.60),.09,.05,(0,1,0),14);cyl('brushed_steel',(4.55,.084,-9.60),.035,.01,(0,1,0),12)
# Mount the grille on the swept corridor's right wall. These two stations
# bracket the panel on the vertical side of the corridor profile.
def connector_right_wall(t):
 smooth=t*t*(3-2*t)
 center=Vector((5.70+(3.075-5.70)*smooth,0,-5.90+(-13.44+5.90)*t))
 tangent=Vector(((3.075-5.70)*6*t*(1-t),0,-7.54)).normalized()
 return center+tangent.cross(Vector((0,1,0)))*1.15
wall_in=connector_right_wall(23/36)
wall_out=connector_right_wall(26/36)
across=(wall_out-wall_in).normalized()
inward=across.cross(Vector((0,-1,0)))
mount=(wall_in+wall_out)/2+Vector((0,1.72,0))

def vent_box(mat, height, depth, size):
 width,h,d=size
 corners=[tuple(mount-across*(i*width/2)+Vector((0,height+j*h/2,0))+inward*(depth+k*d/2))
          for i,j,k in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
 part(mat,corners,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])

start('bridge wall ventilation')
vent_box('dark_metal',0,.014,(.48,.30,.058))
for y in (-.11,-.06,-.01,.04,.09):
 vent_box('brushed_steel',y,.049,(.42,.015,.016))
for z in (0,-4,4):
 start('acoustic ceiling liner %.1f'%z);box('acoustic',(0,2.605,z),(1.20,.035,.80))
start('tech foil repair wrap');cyl('foil',(3.8,1.94,1.10),.045,.24,(1,0,0),12)
# NEW: loose equipment and discarded supplies. Clusters sit on existing furniture
# or against outer walls, clear of the capsule routes through every room.
start('common opened ration tin');cyl('dark_metal',(-1.20,.875,1.57),.060,.105,(0,1,0),10);cyl('brushed_steel',(-1.20,.934,1.57),.064,.012,(0,1,0),10);cyl('paper',(-1.20,.941,1.57),.049,.006,(0,1,0),10)
start('common detached ration lid');cyl('brushed_steel',(-1.34,.835,1.54),.058,.009,(0,1,0),10);cyl('dark_metal',(-1.34,.840,1.54),.018,.008,(0,1,0),8)
start('common crushed foil meal pack');box('foil',(-1.10,.842,1.20),(.18,.022,.13));beam('paper',(-1.18,.85,1.18),(-1.06,.855,1.23),.018,.02);box('hazard',(-1.11,.855,1.18),(.05,.004,.025))
start('common open service pouch');box('vinyl',(-1.75,.114,.70),(.28,.18,.24));box('dark_metal',(-1.75,.209,.70),(.28,.015,.24));beam('brushed_steel',(-1.86,.174,.58),(-1.64,.174,.58),.012,.012);cyl('copper',(-1.62,.204,.70),.018,.014,(1,0,0),8)
start('common pouch scattered fasteners')
for x,z in [(-1.62,.56),(-1.56,.63),(-1.68,.72),(-1.53,.78),(-1.61,.87)]:
 cyl('brushed_steel',(x,.037,z),.014,.038,(0,1,0),6);cyl('dark_metal',(x,.058,z),.022,.008,(0,1,0),6)
start('common opened paper carton');box('cardboard',(-1.46,.134,1.54),(.27,.22,.27));beam('cardboard',(-1.58,.244,1.41),(-1.72,.294,1.31),.11,.012);beam('cardboard',(-1.34,.244,1.41),(-1.20,.274,1.34),.10,.012);box('paper',(-1.46,.189,1.54),(.14,.08,.14))
start('quarters handheld recorder');box('dark_metal',(-1.05,.557,-4.60),(.22,.035,.14));box('brushed_steel',(-1.05,.577,-4.60),(.12,.008,.09));cyl('copper',(-.96,.588,-4.60),.018,.009,(0,1,0),8);box('paper',(-1.13,.587,-4.60),(.025,.008,.055))
start('quarters torn personal letter');box('paper',(-1.50,.603,-4.27),(.22,.006,.16));beam('paper',(-1.59,.608,-4.28),(-1.48,.608,-4.21),.005,.004);box('notebook',(-1.44,.607,-4.31),(.08,.006,.03))
start('quarters folded uniform on bunk');box('blanket',(-1.72,.64,-3.35),(.28,.075,.34));beam('vinyl',(-1.82,.69,-3.30),(-1.62,.69,-3.30),.025,.022);box('pillow',(-1.70,.69,-3.43),(.14,.02,.16))
start('quarters personal supply tube');cyl('laminate',(1.565,1.73,-4.20),.035,.16,(0,0,1),8);cyl('dark_metal',(1.565,1.73,-4.115),.038,.012,(0,0,1),8);beam('brushed_steel',(1.53,1.73,-4.25),(1.60,1.73,-4.25),.012,.012);beam('brushed_steel',(1.53,1.73,-4.15),(1.60,1.73,-4.15),.012,.012)
start('airlock open tool tray');box('dark_metal',(1.53,.588,3.18),(.34,.035,.25));box('oxygen',(1.53,.628,3.18),(.32,.045,.23));beam('brushed_steel',(1.43,.66,3.12),(1.62,.66,3.12),.014,.014);beam('dark_metal',(1.46,.66,3.20),(1.60,.66,3.20),.018,.018);cyl('copper',(1.48,.66,3.25),.018,.12,(1,0,0),8)
start('airlock discarded pressure glove');box('vinyl',(1.66,.595,3.63),(.15,.045,.13));beam('vinyl',(1.62,.61,3.60),(1.56,.61,3.55),.035,.025);beam('vinyl',(1.69,.61,3.60),(1.75,.61,3.56),.03,.022);beam('vinyl',(1.69,.61,3.65),(1.76,.61,3.66),.026,.02)
start('airlock tether cable coil')
for i in range(14):
 a=2*math.pi*i/14;b=2*math.pi*(i+1)/14;beam('cable_rubber',(1.56+.115*math.cos(a),.035,4.28+.115*math.sin(a)),(1.56+.115*math.cos(b),.035,4.28+.115*math.sin(b)),.020,.020)
cyl('brushed_steel',(1.56,.041,4.28),.024,.035,(0,1,0),8)
start('tech replacement air filter');cyl('locker',(6.48,.17,-2.85),.14,.42,(0,0,1),10);cyl('dark_metal',(6.48,.17,-3.055),.145,.018,(0,0,1),10);cyl('dark_metal',(6.48,.17,-2.645),.145,.018,(0,0,1),10)
for z in (-3.00,-2.925,-2.85,-2.775,-2.70):cyl('brushed_steel',(6.48,.17,z),.147,.012,(0,0,1),10)
beam('brushed_steel',(6.38,.27,-2.85),(6.58,.27,-2.85),.014,.014)
start('tech loose cable spool');cyl('dark_metal',(6.62,.06,-3.37),.09,.07,(0,1,0),10);cyl('brushed_steel',(6.62,.06,-3.37),.028,.078,(0,1,0),8)
for i in range(9):
 a=2*math.pi*i/9;b=2*math.pi*(i+1)/9;beam('cable_rubber',(6.62+.11*math.cos(a),.035,-3.37+.11*math.sin(a)),(6.62+.11*math.cos(b),.035,-3.37+.11*math.sin(b)),.016,.016)
start('bridge field tape cartridge');box('dark_metal',(4.60,.075,-9.57),(.22,.10,.18));box('laminate',(4.60,.130,-9.57),(.18,.012,.14));cyl('brushed_steel',(4.55,.139,-9.57),.035,.01,(0,1,0),10);cyl('brushed_steel',(4.65,.139,-9.57),.035,.01,(0,1,0),10)
start('bridge scattered recording strips');box('paper',(5.25,.029,-7.17),(.21,.004,.12));box('notebook',(5.35,.031,-7.22),(.17,.006,.09));beam('paper',(5.28,.035,-7.20),(5.40,.035,-7.14),.004,.004)
start('bridge loose probe tool');beam('brushed_steel',(4.55,.045,-9.92),(4.75,.045,-9.83),.014,.014);cyl('dark_metal',(4.55,.045,-9.92),.026,.035,(0,1,0),8);box('copper',(4.65,.051,-9.86),(.035,.025,.05))
finish()
# Save editable source objects before export, then combine evaluated beveled meshes by material.
bpy.ops.object.select_all(action='SELECT');bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'ship_details_b.blend'))
deps=bpy.context.evaluated_depsgraph_get(); grouped={}
for ob in objects:
 ev=ob.evaluated_get(deps);me=ev.to_mesh(); g=grouped.setdefault(ob.data.materials[0].name,{'v':[],'f':[],'uv':[]});base=len(g['v']);g['v'].extend([tuple(ob.matrix_world@v.co) for v in me.vertices]); u=me.uv_layers.active
 for p in me.polygons:
  g['f'].append(tuple(base+i for i in p.vertices));g['uv'].append([tuple(u.data[li].uv) for li in p.loop_indices] if u else [(0,0)]*len(p.vertices))
 ev.to_mesh_clear()
export=[]
for name,g in grouped.items():
 me=bpy.data.meshes.new('export_'+name);me.from_pydata(g['v'],[],g['f']);me.update();me.materials.append(materials[name]);uv=me.uv_layers.new(name='UVMap')
 for p,uvs in zip(me.polygons,g['uv']):
  for li,t in zip(p.loop_indices,uvs):uv.data[li].uv=t
 ob=bpy.data.objects.new('export_'+name,me);bpy.context.collection.objects.link(ob);export.append(ob)
bpy.ops.object.select_all(action='DESELECT')
for ob in export:ob.select_set(True)
bpy.context.view_layer.objects.active=export[0];bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'ship_details_b.glb'),export_format='GLB',use_selection=True)
tri=sum(sum(len(f)-2 for f in g['f']) for g in grouped.values()); bbox={'min':[min(o['bounds_godot']['min'][i] for o in reports) for i in range(3)],'max':[max(o['bounds_godot']['max'][i] for o in reports) for i in range(3)]}; report={'coordinate_system':'Godot XYZ, floor top .024; Blender X,-Z,Y','bbox_godot':bbox,'logical_prop_count':len(reports),'editable_meshes':len(objects),'export_meshes':len(export),'triangles':tri,'props':reports,'materials':list(grouped),'elapsed_seconds':round(time.time()-T,1),'notes':'Contacts between pieces of one prop and their intentional mounts are expected. No gameplay collision. Manual Godot visual and route checks still required.'}
with open(os.path.join(QA,'report.json'),'w',encoding='utf-8') as f:json.dump(report,f,ensure_ascii=False,indent=2)
print('REPORT',json.dumps({k:v for k,v in report.items() if k!='props'},ensure_ascii=False))
