import bpy, math, os, json, time
from pathlib import Path
from mathutils import Vector
T=time.time(); ROOT=str(Path(__file__).resolve().parents[1]); OUT=os.path.join(ROOT,'assetss','ship_layout_b'); QA=os.path.join(ROOT,'.codex_qa','ship_layout_b'); os.makedirs(OUT,exist_ok=True); os.makedirs(QA,exist_ok=True)
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
for m in list(bpy.data.materials):bpy.data.materials.remove(m)
def mat(name,c,metal=0,rough=.87,img=None,em=0):
 m=bpy.data.materials.new(name); m.diffuse_color=(*c,1); m.use_nodes=True; b=m.node_tree.nodes.get('Principled BSDF'); b.inputs['Base Color'].default_value=(*c,1); b.inputs['Metallic'].default_value=metal; b.inputs['Roughness'].default_value=rough
 if img:
  node=m.node_tree.nodes.new('ShaderNodeTexImage'); node.image=bpy.data.images.load(os.path.join(ROOT,img),check_existing=True); node.image.pack(); node.interpolation='Closest'
  mix=m.node_tree.nodes.new('ShaderNodeMixRGB'); mix.blend_type='MULTIPLY'; mix.inputs[0].default_value=1; mix.inputs[2].default_value=(*c,1); m.node_tree.links.new(node.outputs['Color'],mix.inputs[1]); m.node_tree.links.new(mix.outputs[0],b.inputs['Base Color'])
 if em:b.inputs['Emission Color'].default_value=(*c,1); b.inputs['Emission Strength'].default_value=em
 return m
paint=mat('ivory_aged',(.68,.70,.64),.15,img='assetss/interior_experimental_textures_v1/ivory_paint_candidate.png')
dark=mat('structural_graphite',(.065,.082,.079),.35); steel=mat('brushed_edges',(.22,.26,.24),.55); black=mat('black_rubber',(.018,.024,.021)); rust=mat('oxidised_red_cable',(.22,.065,.035),.1)
floor=mat('deck_plate',(.38,.43,.4),.3,img='assetss/interior_experimental_textures_v1/floor_tread_candidate.png'); cloth=mat('bedding',(.5,.54,.5),0,img='assetss/tex_gemini/tiles/fabric_blanket.png'); lamp=mat('lamp_diffuser',(.6,.68,.55),0,em=1.2); green=mat('crt_phosphor',(.045,.3,.15),0,em=.9); amber=mat('amber_indicator',(.75,.25,.045),0,em=1)
wall_palette={name:mat('wall_'+name,(.30,.32,.30),.1,.9) for name in ['common','quarters','airlock','technical']}
wall_materials={zone:wall_palette[name] for zone,name in [('common','common'),('bulkhead','common'),('quarters','quarters'),('airlock','airlock'),('passage','technical'),('turn','technical')]}
groups={}; surfaces=[]
def point(v):return (v[0],-v[2],v[1])
def geom(zone,material,vs,faces):
 v,f=groups.setdefault((zone,material.name),([],[])); n=len(v); v.extend([point(p) for p in vs]); f.extend([tuple(i+n for i in face) for face in faces])
def box(zone,material,c,s,tag=''):
 x,y,z=c; a,b,d=(q/2 for q in s); v=[(x+i*a,y+j*b,z+k*d) for i,j,k in [(-1,-1,-1),(1,-1,-1),(1,1,-1),(-1,1,-1),(-1,-1,1),(1,-1,1),(1,1,1),(-1,1,1)]]
 geom(zone,material,v,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
 if tag:surfaces.append({'tag':tag,'center':c,'size':s})
def beam(zone,mat,a,b,w,d):
 a,b=Vector(a),Vector(b); v=(b-a).normalized(); ref=Vector((0,0,1)) if abs(v.z)<.9 else Vector((0,1,0)); u=v.cross(ref).normalized()*w/2; q=v.cross(u).normalized()*d/2
 vs=[tuple(p+u*i+q*j) for p in (a,b) for i,j in [(-1,-1),(1,-1),(1,1),(-1,1)]]; geom(zone,mat,vs,[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)])
def cyl(zone,mat,c,r,length,axis=(0,1,0),n=12):
 c=Vector(c); d=Vector(axis).normalized(); ref=Vector((0,0,1)) if abs(d.z)<.9 else Vector((0,1,0)); u=d.cross(ref).normalized(); v=d.cross(u).normalized()
 vs=[tuple(c+d*length*t/2+r*(u*math.cos(i*2*math.pi/n)+v*math.sin(i*2*math.pi/n))) for t in (-1,1) for i in range(n)]; fs=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]; geom(zone,mat,vs,fs)
def floorzone(zone,x0,x1,z0,z1):
 box(zone,dark,((x0+x1)/2,-.055,(z0+z1)/2),(x1-x0,.11,z1-z0),'floor')
 nx=math.ceil(x1-x0); nz=math.ceil(z1-z0); dx=(x1-x0)/nx; dz=(z1-z0)/nz
 for i in range(nx):
  for j in range(nz):box(zone,floor,(x0+(i+.5)*dx,.012,z0+(j+.5)*dz),(dx-.018,.024,dz-.018))
 box(zone,dark,((x0+x1)/2,2.68,(z0+z1)/2),(x1-x0,.06,z1-z0))
 for z in (z0+.8,z1-.8):
  box(zone,steel,((x0+x1)/2,2.60,z),(.40,.07,.65)); box(zone,lamp,((x0+x1)/2,2.555,z),(.25,.022,.52))
def wall(zone,axis,at,start,end):
 if end-start < .05:return
 wall_paint=wall_materials.get(zone,paint)
 if axis=='z':box(zone,dark,((start+end)/2,1.32,at),(end-start,2.64,.10),'wall')
 else:box(zone,dark,(at,1.32,(start+end)/2),(.10,2.64,end-start),'wall')
 n=max(1,math.ceil((end-start)/.92)); unit=(end-start)/n
 for i in range(n):
  p=start+(i+.5)*unit; w=unit-.035
  if axis=='z':
   box(zone,wall_paint,(p,1.28,at),(w-.05,1.86,.15)); box(zone,steel,(p,.20,at),(w-.05,.28,.20)); box(zone,steel,(p,2.46,at),(w-.05,.25,.20))
  else:
   box(zone,wall_paint,(at,1.28,p),(.15,1.86,w-.05)); box(zone,steel,(at,.20,p),(.20,.28,w-.05)); box(zone,steel,(at,2.46,p),(.20,.25,w-.05))
def door(zone,axis,at,start,end,mid,width=1.3):
 wall(zone,axis,at,start,mid-width/2);wall(zone,axis,at,mid+width/2,end)
 if axis=='z':
  for x in (mid-width/2,mid+width/2):box(zone,steel,(x,1.075,at),(.075,2.15,.18),'jamb')
  box(zone,dark,(mid,2.40,at),(width,.50,.18))
 else:
  for z in (mid-width/2,mid+width/2):box(zone,steel,(at,1.075,z),(.18,2.15,.075),'jamb')
  box(zone,dark,(at,2.40,mid),(.18,.50,width))
def arch(zone,z):
 contour=[(-1.67,.06),(-1.93,.30),(-1.93,2.20),(-1.56,2.60),(1.56,2.60),(1.93,2.20),(1.93,.30),(1.67,.06)]
 # omit uprights near central common↔corridor doorway; caller handles no arch at z≈0.
 for a,b in zip(contour,contour[1:]):beam(zone,steel,(a[0],a[1],z),(b[0],b[1],z),.055,.055)
for zone,z0,z1 in [('quarters',-6,-2),('common',-2,2),('airlock',2,6)]:
 floorzone(zone,-2,2,z0,z1)
 for z in (z0+.18,z0+1.25,z1-1.25,z1-.18):arch(zone,z)
wall('quarters','x',-2,-6,-2);wall('quarters','x',2,-6,-2);wall('quarters','z',-6,-2,2)
wall('common','x',-2,-2,2);door('common','x',1.97,-2,2,0,1.3)
wall('airlock','x',-2,2,6);wall('airlock','x',2,2,6);wall('airlock','z',6,-2,2)
door('bulkhead','z',-2,-2,2,0,1.3);door('bulkhead','z',2,-2,2,0,1.3)
floorzone('passage',2,7,-1.3,1.3);floorzone('turn',4.4,7,-6,-1.3)
wall('passage','z',1.3,2,7);wall('passage','z',-1.3,2,4.4);wall('passage','x',7,-1.3,1.3)
wall('turn','x',4.4,-6,-1.3);wall('turn','x',7,-6,-1.3)
door('turn','z',-6,4.4,7,5.5,1.25)
# External hatch is a raised solid octagonal leaf over a closed bulkhead, surface facing room.
def hatch(c,r,mat,z):
 x,y=c; vs=[(x+r*math.cos((i+.5)*math.pi/4),y+r*math.sin((i+.5)*math.pi/4),z) for i in range(8)]; geom('airlock',mat,vs,[tuple(reversed(range(8)))])
hatch((0,1.2),.95,black,5.92);hatch((0,1.2),.86,steel,5.90);hatch((0,1.2),.77,wall_materials['airlock'],5.88)
for y in (.57,1.83):box('airlock',dark,(-.57,y,5.84),(.13,.17,.07))
cyl('airlock',steel,(.34,1.2,5.83),.08,.06,(0,0,1),10)
# Work table and drawers, each with separate raised faces and feet.
box('common',dark,(-1.42,.73,.95),(.9,.10,1.4),'table');box('common',paint,(-1.42,.80,.95),(.94,.055,1.45))
for z in (.43,1.47):box('common',steel,(-1.75,.37,z),(.07,.72,.07))
for z in (.64,1.20):
 box('common',dark,(-1.58,.49,z),(.60,.38,.46));box('common',paint,(-1.245,.49,z),(.035,.30,.40));box('common',steel,(-1.215,.51,z),(.025,.035,.20))
# Narrow cabinet to the left of central path, no blank cuboid front.
box('common',dark,(-1.77,1.12,-1.05),(.34,1.90,1.20),'cabinet')
for z in (-1.34,-.76):
 box('common',paint,(-1.565,1.12,z),(.035,1.68,.53));box('common',steel,(-1.535,1.12,z+.18),(.028,.18,.035))
for y in (.35,1.85):box('common',steel,(-1.54,y,-1.05),(.04,.05,1.12))
# Upper shelf safely above navigation; small equipment face and switches.
box('common',steel,(-1.65,2.17,.20),(.52,.055,1.1));box('common',dark,(-1.72,2.29,.20),(.34,.20,.52))
for z in (.04,.16,.28):cyl('common',amber,(-1.53,2.29,z),.022,.025,(1,0,0),8)
# Bunk and linen: surface segments offset to create blankets rather than a white solid cube.
box('quarters',dark,(-1.35,.34,-4.0),(1.05,.13,2.80),'bunk')
for x in (-1.75,-.96):
 for z in (-5.10,-2.90):box('quarters',steel,(x,.18,z),(.07,.36,.07))
box('quarters',cloth,(-1.35,.45,-4.0),(.98,.18,2.68));box('quarters',paint,(-1.35,.58,-4.95),(.66,.12,.46))
box('quarters',cloth,(-1.35,.57,-3.58),(.99,.06,1.70));box('quarters',cloth,(-1.86,.43,-3.58),(.035,.26,1.70))
box('quarters',dark,(1.77,1.68,-4.2),(.34,1.30,1.2),'locker')
for z in (-4.48,-3.92):
 box('quarters',paint,(1.57,1.68,z),(.035,1.14,.50));box('quarters',steel,(1.54,1.70,z+.15),(.025,.15,.03))
# EVA bay: cylinder rack safely along wall; fittings and two restraint rails.
for z in (3.05,3.52,3.99):
 cyl('airlock',steel,(-1.70,.94,z),.16,1.20,(0,1,0),12);cyl('airlock',dark,(-1.70,1.59,z),.09,.12,(0,1,0),10)
for y in (.55,1.25):box('airlock',dark,(-1.49,y,3.52),(.05,.07,1.30))
box('airlock',dark,(1.69,.78,4.77),(.42,1.44,1.05),'console');box('airlock',paint,(1.44,1.25,4.77),(.035,.38,.86));box('airlock',green,(1.415,1.30,4.78),(.015,.17,.33))
for z in (4.47,4.60,4.73):cyl('airlock',steel,(1.405,1.08,z),.028,.03,(1,0,0),8)
box('airlock',dark,(1.65,.44,3.10),(.48,.12,1.2),'bench');box('airlock',cloth,(1.65,.53,3.10),(.46,.08,1.18))
for z in (2.65,3.55):box('airlock',steel,(1.65,.22,z),(.06,.44,.06))
# Services in L-turn, close to wall: no obstruction in axial path.
for z in (-5.5,-4.5,-3.5,-2.5):box('turn',dark,(6.88,1.75,z),(.16,.22,.8))
for y in (1.70,1.76,1.82):cyl('turn',rust if y==1.76 else black,(6.77,y,-3.55),.025,4.4,(0,0,1),8)
for z in (-5,-4,-3,-2):box('turn',steel,(6.72,1.76,z),(.04,.20,.04))
for z in (-4.7,-2.7):
 box('turn',black,(4.49,1.35,z),(.035,.75,.7));box('turn',steel,(4.52,1.35,z),(.025,.64,.60));box('turn',dark,(4.54,1.35,z),(.014,.55,.51))
box('passage',dark,(3.5,1.35,1.20),(1.0,.8,.12));box('passage',paint,(3.5,1.35,1.11),(.9,.70,.035));box('passage',steel,(3.80,1.35,1.08),(.035,.18,.025))
# Build one editable mesh per zone/material with metric UVs; all textural images packed.
objects=[]
for (zone,name),(vs,fs) in groups.items():
 me=bpy.data.meshes.new(zone+' '+name); me.from_pydata(vs,[],fs); me.update(); me.materials.append(bpy.data.materials[name]); uv=me.uv_layers.new(name='UVMap')
 for p in me.polygons:
  drop=max(range(3),key=lambda k:abs(p.normal[k])); ax=[k for k in range(3) if k!=drop]
  for li in p.loop_indices:
   v=me.vertices[me.loops[li].vertex_index].co; uv.data[li].uv=(v[ax[0]]*.7,v[ax[1]]*.7)
 ob=bpy.data.objects.new(zone+' '+name,me); bpy.context.collection.objects.link(ob); objects.append(ob)
 bevel=ob.modifiers.new('Small edge bevels','BEVEL'); bevel.width=.006; bevel.segments=1
bpy.ops.object.select_all(action='SELECT'); bpy.ops.wm.save_as_mainfile(filepath=os.path.join(OUT,'ship_layout_b.blend'))
bpy.ops.export_scene.gltf(filepath=os.path.join(OUT,'ship_layout_b.glb'),export_format='GLB',use_selection=True,export_apply=True)
tri=sum(sum(len(f)-2 for f in fs) for vs,fs in groups.values())
report={'coordinate_system':'Godot XYZ; Blender x,-z,y; floor top y=.024','doors':{'quarters':[0,0,-2],'airlock':[0,0,2],'common_passage':[1.97,0,0],'bridge':[5.5,0,-6]},'door_clear_width_nominal_m':{'rooms':1.225,'bridge':1.175},'door_height_m':2.15,'external_hatch':[0,1.2,5.88],'equipment':{'common_desk':[-1.42,.8,.95],'common_cabinet':[-1.77,1.12,-1.05],'bunk':[-1.35,.45,-4],'quarters_locker':[1.77,1.68,-4.2],'oxygen_rack':[-1.7,.94,3.52],'airlock_console':[1.44,1.25,4.77],'airlock_bench':[1.65,.53,3.1]},'mesh_count':len(objects),'triangles':tri,'checks':'Door nominal width subtracts 0.075m jamb width. Geometry preserves axial routes; run actual Godot BVH collision test. No scene integration. External hatch is static.','seconds':round(time.time()-T,1)}
with open(os.path.join(QA,'report.json'),'w',encoding='utf-8') as f:json.dump(report,f,ensure_ascii=False,indent=2)
print('REPORT',json.dumps(report,ensure_ascii=False))
