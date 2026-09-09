"""Rebuild the original Milo character, editable rig, USDZ, portraits and rig manifest.
Run: Blender --background --python Scripts/build_milo.py -- /absolute/repo
No external models, textures or services are used.
"""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector
ROOT=Path(sys.argv[sys.argv.index('--')+1])
ART=ROOT/'Art/Milo'; RES=ROOT/'LangLearn/Resources'
ART.mkdir(parents=True,exist_ok=True); RES.mkdir(parents=True,exist_ok=True)
bpy.context.preferences.filepaths.save_version=0
bpy.ops.object.select_all(action='SELECT'); bpy.ops.object.delete(use_global=False)
materials={}
def mat(name,color,rough=.65):
 m=bpy.data.materials.new(name); m.diffuse_color=(*color,1); m.use_nodes=True
 p=m.node_tree.nodes.get('Principled BSDF'); p.inputs['Base Color'].default_value=(*color,1); p.inputs['Roughness'].default_value=rough
 materials[name]=m; return m
mat('Warm skin',(.68,.36,.20)); mat('Nose and ears',(.73,.34,.22)); mat('Cream shirt',(.91,.83,.66)); mat('Olive wool',(.19,.27,.12)); mat('Red silk',(.60,.055,.038)); mat('Espresso',(.075,.035,.022)); mat('Hair',(.042,.021,.013)); mat('Eye white',(1,.97,.88),.3); mat('Hazel iris',(.25,.11,.03),.3); mat('Pupil',(.012,.008,.005),.25); mat('Catchlight',(1,1,1),.2); mat('Mouth',(.11,.012,.016)); mat('Lip',(.52,.17,.105)); mat('Gold',(.67,.43,.12),.32)
parts=[]
def finish(o,name,material,bone,tag=None):
 o.name=name; o.data.materials.append(materials[material]); bpy.context.view_layer.objects.active=o
 bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 for poly in o.data.polygons: poly.use_smooth=True
 o.vertex_groups.new(name=bone).add(list(range(len(o.data.vertices))),1,'REPLACE')
 if tag: o.vertex_groups.new(name='face_'+tag).add(list(range(len(o.data.vertices))),1,'REPLACE')
 parts.append(o); return o

def ball(name,loc,scale,material,bone='spine',tag=None,segments=18,rings=12):
 bpy.ops.mesh.primitive_uv_sphere_add(segments=segments,ring_count=rings,location=loc)
 o=bpy.context.object; o.scale=scale; return finish(o,name,material,bone,tag)

def tube(name,points,radius,material,bone='head',tag=None):
 c=bpy.data.curves.new(name,'CURVE'); c.dimensions='3D'; c.resolution_u=6; c.bevel_depth=radius; c.bevel_resolution=1
 s=c.splines.new('BEZIER'); s.bezier_points.add(len(points)-1)
 for p,co in zip(s.bezier_points,points): p.co=co; p.handle_left_type='AUTO'; p.handle_right_type='AUTO'
 o=bpy.data.objects.new(name,c); bpy.context.collection.objects.link(o); bpy.context.view_layer.objects.active=o; o.select_set(True)
 bpy.ops.object.convert(target='MESH'); finish(o,name,material,bone,tag); o.select_set(False); return o

def limb(name,a,b,width,depth,material,bone):
 middle=(Vector(a)+Vector(b))/2; o=ball(name,middle,(width,depth,(Vector(b)-Vector(a)).length/2+width*.5),material,bone)
 o.rotation_mode='QUATERNION'; o.rotation_quaternion=(Vector(b)-Vector(a)).to_track_quat('Z','Y'); return o

# Short rounded legs and a relaxed, open stance.
for side,s in [('L',1),('R',-1)]:
 limb('Trouser '+side,(s*.20,0,.67),(s*.22,-.01,.20),.16,.18,'Espresso','leg_'+side)
 ball('Shoe '+side,(s*.22,-.10,.13),(.18,.28,.115),'Espresso','foot_'+side)
 tube('Shoe seam '+side,[(s*.22-.12,-.30,.14),(s*.22,-.36,.155),(s*.22+.12,-.30,.14)],.008,'Gold','foot_'+side)
ball('Round cream belly',(0,-.025,1.015),(.46,.335,.49),'Cream shirt')
# Tailored vest panels follow the belly, leaving an open cream centre.
for side,s in [('L',1),('R',-1)]:
 verts=[]; faces=[]
 for j in range(17):
  theta=.38+j/16*2.25
  for i in range(13):
   phi=(.34+i/12*2.65)*s
   verts.append((.477*math.sin(theta)*math.sin(phi),-.025-.352*math.sin(theta)*math.cos(phi),1.025+.49*math.cos(theta)))
 for j in range(16):
  for i in range(12):
   a=j*13+i; faces.append((a,a+1,a+14,a+13) if s>0 else (a+13,a+14,a+1,a))
 mesh=bpy.data.meshes.new('Tailored panel'); mesh.from_pydata(verts,[],faces); mesh.update()
 o=bpy.data.objects.new('Waistcoat '+side,mesh); bpy.context.collection.objects.link(o); finish(o,o.name,'Olive wool','spine')
 for z in [.96,1.10,1.24]:
  y=-.03-.353*math.sqrt(max(0,1-((z-1.025)/.49)**2))
  ball('Vest button '+side,(s*.18,y-.006,z),(.018,.013,.018),'Gold',segments=12,rings=8)
 ball('Shirt shoulder '+side,(s*.40,.00,1.30),(.20,.20,.19),'Cream shirt','upper_arm_'+side)
 limb('Rolled sleeve '+side,(s*.44,0,1.30),(s*.58,-.01,1.03),.14,.15,'Cream shirt','upper_arm_'+side)
 ball('Cuff '+side,(s*.575,-.015,1.04),(.146,.157,.08),'Cream shirt','upper_arm_'+side)
 limb('Forearm '+side,(s*.58,-.015,1.02),(s*.64,-.045,.82),.105,.11,'Warm skin','forearm_'+side)
 ball('Palm '+side,(s*.65,-.06,.77),(.112,.088,.13),'Warm skin','hand_'+side)
 for i in range(4):
  ball('Finger '+side+str(i),(s*(.578+i*.047),-.081,.692),(.030,.05,.075),'Warm skin','hand_'+side,segments=12,rings=8)
 thumb=ball('Thumb '+side,(s*.55,-.105,.79),(.05,.06,.095),'Warm skin','hand_'+side); thumb.rotation_euler.y=s*-.4
ball('Neck',(0,0,1.49),(.165,.165,.22),'Warm skin','neck')
# Silk scarf knot and two short draped ends.
ball('Scarf collar',(0,0,1.49),(.20,.185,.075),'Red silk','neck')
ball('Scarf knot',(.025,-.188,1.46),(.075,.07,.075),'Red silk','neck')
for x,angle in [(-.035,-.2),(.075,.3)]:
 o=ball('Scarf tail',(x,-.215,1.35),(.06,.035,.15),'Red silk','neck'); o.rotation_euler.y=angle
# Oversized face: cheeks, ears, large readable eyes, a smiling mouth below the moustache.
ball('Head',(0,0,1.88),(.39,.305,.425),'Warm skin','head',segments=32,rings=20)
ball('Chin',(0,-.185,1.62),(.235,.15,.16),'Warm skin','head','chin')
for side,s in [('L',1),('R',-1)]:
 ball('Ear '+side,(s*.388,0,1.89),(.087,.07,.13),'Warm skin','head')
 ball('Inner ear '+side,(s*.407,-.052,1.89),(.040,.025,.078),'Nose and ears','head',segments=16,rings=10)
 ball('Cheek '+side,(s*.235,-.205,1.77),(.148,.096,.13),'Warm skin','head')
 ball('Eye socket '+side,(s*.153,-.25,1.96),(.155,.09,.184),'Nose and ears','head')
 ball('Eye white '+side,(s*.151,-.293,1.96),(.131,.075,.150),'Eye white','head','eye_'+side)
 ball('Iris '+side,(s*.145,-.359,1.955),(.066,.024,.087),'Hazel iris','head','eye_'+side)
 ball('Pupil '+side,(s*.143,-.380,1.955),(.036,.013,.057),'Pupil','head','eye_'+side)
 ball('Eye glint '+side,(s*.143-.02,-.395,1.99),(.016,.008,.02),'Catchlight','head','eye_'+side,segments=12,rings=8)
 tube('Brow '+side,[(s*.05,-.29,2.11),(s*.14,-.29,2.151),(s*.25,-.25,2.12)],.026,'Hair','head','brow_'+side)
ball('Nose',(0,-.35,1.845),(.115,.143,.107),'Nose and ears','head')
ball('Smile cavity',(0,-.326,1.66),(.125,.019,.035),'Mouth','head','mouth')
tube('Lower smile',[(-.12,-.33,1.66),(0,-.35,1.617),(.12,-.33,1.66)],.014,'Lip','head','lip')
# The hairline and moustache are sculpted curls, not a texture pasted over the mouth.
ball('Hair cap',(0,.04,2.125),(.366,.28,.194),'Hair','head')
for i in range(7):
 x=-.29+i*.095
 o=ball('Wavy fringe '+str(i),(x,-.16+abs(x)*.15,2.22-abs(x)*.15+.018*math.sin(i*1.8)),(.094,.102,.080),'Hair','head',segments=16,rings=10)
 o.rotation_euler.y=-.30+i*.12
for s in [-1,1]:
 ball('Sideburn',(s*.332,-.115,2.018),(.05,.058,.15),'Hair','head',segments=16,rings=10)
 tube('Moustache',[(0,-.426,1.737),(s*.065,-.411,1.72),(s*.14,-.363,1.73),(s*.195,-.307,1.773)],.037,'Hair','head')

# One skinned mesh with named groups and an actual editable armature.
bpy.ops.object.select_all(action='DESELECT')
for o in parts:o.select_set(True)
bpy.context.view_layer.objects.active=parts[0]; bpy.ops.object.join(); body=bpy.context.object; body.name='MiloBody'
bpy.ops.object.transform_apply(location=True,rotation=True,scale=True)
body.shape_key_add(from_mix=False,name='Basis')
def group_indices(name):
 g=body.vertex_groups.get('face_'+name)
 return {v.index for v in body.data.vertices if g and any(x.group==g.index for x in v.groups)}
mouth=group_indices('mouth'); lip=group_indices('lip'); chin=group_indices('chin')
k=body.shape_key_add(from_mix=False,name='mouthOpen')
for index,v in enumerate(k.data):
 if index in mouth: v.co.z=1.682+(v.co.z-1.682)*2.7
 if index in lip: v.co.z-=.067
 if index in chin: v.co.z-=.017
for side in ['L','R']:
 k=body.shape_key_add(from_mix=False,name='blink'+side)
 for index in group_indices('eye_'+side):
  co=k.data[index].co; co.z=1.96+(co.z-1.96)*.035; co.y+=.005
k=body.shape_key_add(from_mix=False,name='smile')
for index in mouth|lip:
 co=k.data[index].co; co.x*=1.10; co.z+=abs(co.x)*.06
k=body.shape_key_add(from_mix=False,name='browRaise')
for side in ['L','R']:
 for index in group_indices('brow_'+side):k.data[index].co.z+=.035
for key in body.data.shape_keys.key_blocks: key.value=0
# Shape semantic groups must not be mistaken for deform joints.
for g in list(body.vertex_groups):
 if g.name.startswith('face_'):body.vertex_groups.remove(g)
armdata=bpy.data.armatures.new('MiloSkeleton'); arm=bpy.data.objects.new('MiloRig',armdata); bpy.context.collection.objects.link(arm)
bpy.context.view_layer.objects.active=arm; bpy.ops.object.mode_set(mode='EDIT')
def bone(name,head,tail,parent=None):
 b=armdata.edit_bones.new(name); b.head=head; b.tail=tail
 if parent:b.parent=armdata.edit_bones[parent]
 return b
bone('root',(0,0,0),(0,0,.2)); bone('spine',(0,0,.65),(0,0,1.42),'root'); bone('neck',(0,0,1.42),(0,0,1.59),'spine'); bone('head',(0,0,1.59),(0,0,2.23),'neck')
for side,s in [('L',1),('R',-1)]:
 bone('upper_arm_'+side,(s*.40,0,1.30),(s*.58,-.015,1.02),'spine')
 bone('forearm_'+side,(s*.58,-.015,1.02),(s*.64,-.045,.82),'upper_arm_'+side)
 bone('hand_'+side,(s*.64,-.045,.82),(s*.65,-.06,.68),'forearm_'+side)
 bone('leg_'+side,(s*.20,0,.67),(s*.22,-.01,.20),'root')
 bone('foot_'+side,(s*.22,-.01,.20),(s*.22,-.25,.12),'leg_'+side)
bpy.ops.object.mode_set(mode='OBJECT'); body.parent=arm
mod=body.modifiers.new('Milo skin','ARMATURE'); mod.object=arm
# Action previews are also supplied to the artist. The app mixes these motions procedurally.
for name in ['Idle','Greeting','Thinking','Listening','Speaking','Encouraging','Celebrating','Walking']:
 arm.animation_data_create(); arm.animation_data.action=bpy.data.actions.new(name)
 for frame in [1,16,32,48,64]:
  t=(frame-1)/63*math.tau
  for p in arm.pose.bones:p.rotation_mode='XYZ'; p.rotation_euler=(0,0,0)
  arm.pose.bones['head'].rotation_euler.z=.035*math.sin(t)
  if name=='Greeting':
   arm.pose.bones['upper_arm_R'].rotation_euler.z=-1.9
   arm.pose.bones['forearm_R'].rotation_euler.z=-.35+.16*math.sin(t*2)
   arm.pose.bones['hand_R'].rotation_euler.x=.2*math.sin(t*2)
  if name=='Thinking':
   arm.pose.bones['head'].rotation_euler.z=.14; arm.pose.bones['forearm_L'].rotation_euler.x=-1.45
  if name in ['Speaking','Encouraging']:
   for side,s in [('L',1),('R',-1)]:arm.pose.bones['upper_arm_'+side].rotation_euler.x=-.2-.13*math.sin(t+s)
  if name=='Celebrating':
   arm.pose.bones['upper_arm_L'].rotation_euler.z=1.7; arm.pose.bones['upper_arm_R'].rotation_euler.z=-1.7
  if name=='Walking':
   for side,s in [('L',1),('R',-1)]:arm.pose.bones['leg_'+side].rotation_euler.x=.15*math.sin(t)*s
  for p in arm.pose.bones:p.keyframe_insert(data_path='rotation_euler',frame=frame)
 arm.animation_data.action.use_fake_user=True
arm.animation_data.action=None
for p in arm.pose.bones:p.rotation_euler=(0,0,0)
bpy.context.scene.frame_set(1)
bpy.ops.object.select_all(action='DESELECT'); arm.select_set(True); body.select_set(True); bpy.context.view_layer.objects.active=arm
bpy.ops.wm.usd_export(filepath=str(RES/'Milo.usdz'),selected_objects_only=True,export_animation=False,export_armatures=True,export_shapekeys=True,export_materials=True,export_normals=True,generate_preview_surface=True)
for key in body.data.shape_keys.key_blocks: key.value=0
body.data.calc_loop_triangles()
manifest={'triangles':len(body.data.loop_triangles),'vertices':len(body.data.vertices),'joints':[b.name for b in arm.data.bones],'blendShapes':[k.name for k in body.data.shape_keys.key_blocks][1:],'actions':[a.name for a in bpy.data.actions]}
(ART/'rig-manifest.json').write_text(json.dumps(manifest,indent=2))
# Studio render from the exact same model for fallback avatars; no raster substitutions.
scene=bpy.context.scene; scene.render.engine='CYCLES'; scene.cycles.samples=32; scene.render.resolution_x=768; scene.render.resolution_y=768; scene.render.resolution_percentage=100; scene.render.film_transparent=True
scene.world.color=(.25,.25,.25)
def aim(o,target):o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
for name,loc,power,size in [('Key',(-3,-4,5),450,4),('Fill',(3,-2,3),250,3),('Rim',(1,2,4),500,3)]:
 bpy.ops.object.light_add(type='AREA',location=loc); o=bpy.context.object; o.name=name; o.data.energy=power; o.data.shape='DISK'; o.data.size=size; aim(o,(0,0,1.2))
bpy.ops.object.camera_add(location=(.45,-5,2.5)); camera=bpy.context.object; aim(camera,(0,0,1.17)); camera.data.type='ORTHO'; camera.data.ortho_scale=2.85; scene.camera=camera
scene.view_settings.view_transform='AgX'; scene.render.image_settings.file_format='PNG'; scene.render.image_settings.color_mode='RGBA'
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'Milo.blend'))
scene.render.filepath=str(ROOT/'LangLearn/Assets.xcassets/Milo.imageset/milo.png'); bpy.ops.render.render(write_still=True)
arm.pose.bones['head'].rotation_euler.z=.12; arm.pose.bones['forearm_L'].rotation_euler.x=-1.1
scene.render.filepath=str(ROOT/'LangLearn/Assets.xcassets/MiloThinking.imageset/milo-thinking.png'); bpy.ops.render.render(write_still=True)
print('MILO_MANIFEST',json.dumps(manifest))
