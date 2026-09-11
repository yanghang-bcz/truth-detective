import bpy, math, json
from mathutils import Vector, Matrix
from pathlib import Path
P=Path(globals().get('PROJECT_DIR', '/Users/emobcccz/.codex/.chatgpt-projects/g-p-69aed7ee2424819192fda2d3828aa78d/TruthDetective_Player'))
bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
bpy.ops.import_scene.fbx(filepath=str(P/'assets/characters/source/character-a.fbx'))
for o in bpy.context.scene.objects:
 if o.animation_data:
  a=next((a for a in bpy.data.actions if a.name.startswith(o.name+'|static|')),None)
  if a:o.animation_data.action=a
bpy.context.scene.frame_set(1);bpy.context.view_layer.update()
def mat(name,c,metal=0):
 m=bpy.data.materials.new(name);m.diffuse_color=(*c,1);m.use_nodes=True
 bs=m.node_tree.nodes.get('Principled BSDF');bs.inputs['Base Color'].default_value=(*c,1);bs.inputs['Roughness'].default_value=.78;bs.inputs['Metallic'].default_value=metal
 return m
coat=mat('Weathered slate taupe wool',(.23,.205,.17));trim=mat('Raised seams',(.32,.28,.22));skin=mat('Warm muted skin',(.46,.335,.24));dark=mat('Charcoal leather',(.035,.044,.046));gold=mat('Aged brass',(.38,.27,.115),.65);scarf=mat('Petrol scarf',(.055,.105,.105));eyes=mat('Eyes',(.016,.02,.022))
parts=[]; bindings={}
def finish(o,name,m,bone,bevel=0):
 o.name=name;o.data.materials.clear();o.data.materials.append(m)
 if bevel:
  bpy.context.view_layer.objects.active=o;mod=o.modifiers.new('Soft cut edges','BEVEL');mod.width=bevel;mod.segments=2;bpy.ops.object.modifier_apply(modifier=mod.name)
 parts.append(o);bindings[o.name]=bone;return o
for o in list(bpy.context.scene.objects):
 if o.type!='MESH':continue
 name=o.name;vs=[o.matrix_world@v.co for v in o.data.vertices];o.animation_data_clear();o.parent=None;o.matrix_world=Matrix.Identity(4)
 for v,p in zip(o.data.vertices,vs):
  if name=='head':p=Vector((p.x*.52,p.y*.48,(p.z-1.9)*.48+1.01))
  else:
   p=Vector((p.x*.48,p.y*.48,p.z*.53))
   if 'arm' in name:
    center=.288 if 'left' in name else -.288
    p.x=center+(p.x-center)*.76
    p.y=.048+(p.y-.048)*.8
  v.co=p
 finish(o,name,skin if name=='head' else dark if 'leg' in name else coat,name if name!='torso' else 'Chest',.13 if name=='head' else .055 if 'arm' in name else .022)
for o in list(bpy.context.scene.objects):
 if o.type=='EMPTY':bpy.data.objects.remove(o,do_unlink=True)
for a in list(bpy.data.actions):bpy.data.actions.remove(a)
def mesh(name,verts,faces,m,bone):
 me=bpy.data.meshes.new(name);me.from_pydata(verts,[],faces);me.update();o=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(o);return finish(o,name,m,bone)
def box(name,loc,size,m,bone,bevel=.012):
 bpy.ops.mesh.primitive_cube_add(size=1,location=loc);o=bpy.context.object;o.scale=size;bpy.ops.object.transform_apply(location=False,rotation=False,scale=True);return finish(o,name,m,bone,bevel)
def ring(name,z,rx,ry,height,m,bone,top=.9):
 verts=[];n=16
 for h,s in [(z,1),(z+height,top)]:
  for i in range(n):
   a=i*math.tau/n;verts.append((rx*math.cos(a)*s,ry*math.sin(a)*s,h))
 faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]+[(i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n)]
 return mesh(name,verts,faces,m,bone)
# Front is Blender -Y; exported as Godot +Z.
ring('Trench coat skirt',.35,.26,.18,.34,coat,'Chest',.76)
ring('Waist belt',.675,.213,.153,.035,dark,'Chest',1)
box('Brass buckle',(0,-.16,.69),(.068,.022,.047),gold,'Chest')
for x in [-.10,.10]:
 for z in [.76,.84]:box('Double breasted button',(x,-.157,z),(.026,.018,.026),gold,'Chest',.006)
for side in [-1,1]:
 mesh('Notched lapel',[(side*.035,-.171,.77),(side*.16,-.171,.94),(side*.09,-.16,1.02),(side*.016,-.176,.89)],[(0,1,2,3),(3,2,1,0)],trim,'Chest')
 box('Pocket welt',(side*.155,-.168,.57),(.092,.018,.022),trim,'Chest')
 box('Shoulder epaulette',(side*.268,.03,.996),(.13,.14,.025),trim,'arm-left' if side==1 else 'arm-right')
 box('Boot toe',(side*.096,-.045,.09),(.185,.30,.18),dark,'leg-left' if side==1 else 'leg-right',.035)
ring('High collar',.985,.12,.12,.075,coat,'Chest',1.08)
box('Neck scarf',(0,-.136,.986),(.15,.035,.083),scarf,'Chest')
ring('Fedora brim',1.375,.345,.295,.038,coat,'head',.98)
crown=ring('Fedora crown',1.402,.218,.185,.19,coat,'head',.80)
for v in crown.data.vertices:
 if v.co.z>1.5:
  v.co.z-=.045*(1-abs(v.co.x)/.18)
  if v.co.y<0:v.co.x*=.76
ring('Hat ribbon',1.416,.221,.188,.045,dark,'head',.965)

box('Hat ribbon pin',(.208,-.03,1.44),(.018,.055,.026),gold,'head')
# Restrained face with small eyes under the brim, never glowing.
for x in [-.073,.073]:box('Eye',(x,-.195,1.205),(.027,.012,.025),eyes,'head',.006)
box('Nose',(0,-.208,1.155),(.055,.055,.07),skin,'head',.017)
# Rigid low-poly skinning keeps this lightweight, with a real exported skeleton.
arm=bpy.data.armatures.new('DetectiveRig');rig=bpy.data.objects.new('DetectiveRig',arm);bpy.context.collection.objects.link(rig);bpy.context.view_layer.objects.active=rig;rig.select_set(True)
bpy.ops.object.mode_set(mode='EDIT')
def bone(n,h,t,parent=None):
 b=arm.edit_bones.new(n);b.head=h;b.tail=t
 if parent:b.parent=arm.edit_bones[parent]
bone('Root',(0,0,0),(0,0,.15));bone('Chest',(0,0,.53),(0,0,1.0),'Root');bone('head',(0,0,1.01),(0,0,1.35),'Chest')
for s,n in [(1,'left'),(-1,'right')]:
 bone('leg-'+n,(s*.096,0,.53),(s*.096,0,.10),'Root');bone('arm-'+n,(s*.28,.048,.98),(s*.28,.048,.47),'Chest')
bpy.ops.object.mode_set(mode='OBJECT')
for o in parts:
 vg=o.vertex_groups.new(name=bindings[o.name]);vg.add(list(range(len(o.data.vertices))),1,'REPLACE');mod=o.modifiers.new('Detective skeleton','ARMATURE');mod.object=rig;o.parent=rig
bpy.context.scene.render.fps=30
for name,frames,amp,bob in [('Idle',60,.025,.006),('Walk',30,.43,.016),('Run',22,.72,.027)]:
 rig.animation_data_create();act=bpy.data.actions.new(name);rig.animation_data.action=act
 for f in range(1,frames+2):
  phase=(f-1)/frames*math.tau
  for pb in rig.pose.bones:
   pb.rotation_mode='XYZ';pb.rotation_euler=(0,0,0);pb.location=(0,0,0)
  rig.pose.bones['Root'].location.y=bob*(1-math.cos(phase*2))
  rig.pose.bones['Chest'].rotation_euler.x=.10 if name=='Run' else .015*math.sin(phase)
  rig.pose.bones['head'].rotation_euler.z=.02*math.sin(phase)
  for s,n in [(1,'left'),(-1,'right')]:
   rig.pose.bones['leg-'+n].rotation_euler.x=s*amp*math.sin(phase)
   rig.pose.bones['arm-'+n].rotation_euler.x=-s*amp*.8*math.sin(phase)
  for pb in rig.pose.bones:
   pb.keyframe_insert('rotation_euler',frame=f,group=pb.name);pb.keyframe_insert('location',frame=f,group=pb.name)
 act.use_fake_user=True
rig.animation_data.action=bpy.data.actions['Idle'];bpy.context.scene.frame_set(1)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.wm.save_as_mainfile(filepath=str(P/'blender/detective.blend'))
bpy.ops.export_scene.gltf(filepath=str(P/'assets/characters/detective.glb'),export_format='GLB',export_animations=True,export_animation_mode='ACTIONS',export_action_filter=False,export_force_sampling=True)
tri=sum(sum(len(p.vertices)-2 for p in o.data.polygons) for o in parts)
(P/'previews/model_stats.json').write_text(json.dumps({'triangles':tri,'height_m':1.598,'bones':len(arm.bones),'animations':['Idle','Walk','Run'],'source':'Kenney Blocky Characters 2.0 character-a, CC0'},indent=2))
print('DETECTIVE_EXPORTED',tri)
