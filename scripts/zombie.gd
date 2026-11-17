extends Node3D
## Zombie: navigace po úrovni, útok, reakce podle zasažené části těla, odstřelené končetiny,
## brodění a plavání, po smrti fyzikální ragdoll, který se po dopadu zapeče.
signal died(point: Vector3, impulse: Vector3, bone: int)
signal attacked(damage: float)
const MODEL:=preload("res://assets/zombie/zombie.fbx")
# Typy zombie: model + vlastnosti. hp/dmg = násobky, react = jak moc s nimi zásah škubne,
# pitch = výška hlasu. Alfa (kostlivec) je nejtužší, chodí pomalu a skoro neucukne.
const TYPES:={
	"classic":  {"model":"res://assets/zombie/zombie.fbx","hp":1.0,"dmg":1.0,"react":1.0,"pitch":1.0},
	"cop":      {"model":"res://assets/zombie/types/cop.fbx","hp":1.0,"dmg":1.0,"react":1.0,"pitch":0.95},
	"girl":     {"model":"res://assets/zombie/types/girl.fbx","hp":0.85,"dmg":0.9,"react":1.15,"pitch":1.25},
	"ch10":     {"model":"res://assets/zombie/types/ch10_fixed.scn","hp":0.9,"dmg":0.9,"react":1.1,"pitch":1.1},
	"parasite": {"model":"res://assets/zombie/types/parasite.fbx","hp":2.2,"dmg":1.5,"react":0.6,"pitch":0.85},
	"alpha":    {"model":"res://assets/zombie/types/skeleton.fbx","hp":6.0,"dmg":2.5,"react":0.25,"pitch":0.62},
	# Dítě: zmenšená mixamo kostra (build_kid.gd) – pozice pánve v animacích se zmenší stejně.
	"kid":      {"model":"res://assets/zombie/types/kid.scn","hp":0.6,"dmg":0.6,"react":1.35,"pitch":1.55,"hips":0.647},
}
static var _scaled_anims:={}

static func _anims_for(hips: float) -> AnimationLibrary:
	if hips==1.0: return ANIMS
	if _scaled_anims.has(hips): return _scaled_anims[hips]
	var lib:=AnimationLibrary.new()
	for name in ANIMS.get_animation_list():
		var a: Animation=ANIMS.get_animation(name).duplicate(true)
		for t in a.get_track_count():
			if a.track_get_type(t)!=Animation.TYPE_POSITION_3D: continue
			if not String(a.track_get_path(t)).ends_with("mixamorig_Hips"): continue
			for key in a.track_get_key_count(t):
				a.track_set_key_value(t,key,(a.track_get_key_value(t,key) as Vector3)*hips)
		lib.add_animation(name,a)
	_scaled_anims[hips]=lib
	return lib
static var _renamed:={}
var kind:="classic"
var react_mult:=1.0
const ANIMS:=preload("res://assets/zombie/zombie_anims.res")
const GibScript:=preload("res://scripts/zombie_gib.gd")
const MULTIPLIER:={"head":4.0,"torso":1.0,"arm":0.6,"leg":0.75}
const TRANSFER:={"head":0.6,"torso":1.0,"arm":0.65,"leg":0.8}
const SPEEDS:={"walk":0.75,"jog":2.1,"sprint":3.1}
const DEEP:=0.8                  # od této hloubky zombie plave
const SWIM_LEVEL:=0.35           # jak hluboko pod hladinou je při plavání kořen postavy
const ATTACK_SPEED:=1.5
const ATTACK_HIT:=1.05           # okamžik úderu v klipu (s)
const ATTACK_END:=1.65
const CORPSE_TIME:=14.0
static var crowd: Array=[]
static var _shared_materials: Dictionary={}
static var _eye_material: StandardMaterial3D
static var water_level:=-1000.0
static var water_at: Callable       # hladina podle místa (vypuštěné bazény, nádrž)
static var fx: Node3D            # scripts/combat_fx.gd
static var sfx: Node             # Sfx
static var sim: Node             # WaterSim
static var splash: Callable      # main.splash_at(pos, strength)
static var insta_kill:=false
static var _step_clock:=0

var target: Node3D               # koho pronásleduje; bez cíle jen stojí
var ai:=false
var tier:="walk"                 # walk | jog | sprint
var max_health:=100.0
var health:=100.0
var attack_damage:=34.0
var crawling:=false              # bez nohy
var swimming:=false              # nad hlubokou vodou
var dead:=false
var last_region:="torso"
var skeleton: Skeleton3D
var simulator: PhysicalBoneSimulator3D
var _ragdolled:=false          # pád z galerie jako hadrová panenka, pak se zvedne
var _rag_t:=0.0
var _rag_rise:=false
var keep_corpse:=false            # mrtvola jako kulisa: nezmizí
var _sleeping:=false
var _sleep_frozen:=false              # leží jako mrtvá, dokud hráč nepřijde blízko
var bodies: Dictionary={}
var hitboxes: Array[Area3D]=[]
var _model: Node3D
var _animation: AnimationPlayer
var _gib: SkeletonModifier3D
var _severed: Dictionary={}
var _limb_damage: Dictionary={}
var _eyes: Array=[]
var _blocker: AnimatableBody3D
var _blocker_shape: CapsuleShape3D
var _blocker_col: CollisionShape3D
var _blocker_low:=false
var _clip:=""
var _clip_speed:=1.0
var _attack_left:=0.0
var _attack_time:=0.0
var _attack_hit:=false
var _lunge:=0.6
var _scream_left:=0.0
var _bite_timer:=0.0
var _stagger:=0.0
var _gait_factor:=1.0
var _dry_step:=0.0
var _knock:=Vector3.ZERO
var _velocity:=Vector3.ZERO
var _fall:=0.0
var _low:=false
var _low_timer:=0.0
var _emerge:=0.0
var _emerged:=false
var _repath:=0.0
var _corner:=Vector3.ZERO
var _wade:=0.0
var _voice_timer:=0.0
var _pitch:=1.0
var _look_yaw:=0.0
var _drop:=Vector3.ZERO
var _look_pitch:=0.0
var _sweep: PhysicsShapeQueryParameters3D
var _capsule: CapsuleShape3D
var _capsule_low: CapsuleShape3D
var _frozen:=false
var _time:=0.0
var _death_pending:=false
var _pending_impacts: Array=[]
var _pose_history: Dictionary={}
var _pose_velocity: Dictionary={}
var _pose_spin: Dictionary={}
var _reactions: Array=[]
const REACT_GAIN:=1.4        # celková síla škubnutí při zásahu
var _muscles: Array=[]
var _death_time:=0.0
var _injured_bone:=-1
var _inertia: Dictionary={}
var _ids: Dictionary={}
var _style:="torso"
var _rest_timer:=0.0
var _resting:=false
var _rng:=RandomNumberGenerator.new()
const EYE_OFFSET:=Vector3(0,0,0.012)

func _physical_parent(bone: int) -> int:
	var parent:=skeleton.get_bone_parent(bone)
	while parent>=0 and not bodies.has(parent): parent=skeleton.get_bone_parent(parent)
	return parent

func _region(bone: int) -> String:
	if not bodies.has(bone): return "torso"
	var part: String=bodies[bone].get_meta("part_name")
	if part in ["Head","Neck"]: return "head"
	if part.ends_with("Leg") or part.ends_with("Foot"): return "leg"
	if part.ends_with("Arm") or part.ends_with("Hand"): return "arm"
	return "torso"

func _ready() -> void:
	var info: Dictionary=TYPES.get(kind,TYPES.classic)
	_model=(load(info.model) as PackedScene).instantiate()
	add_child(_model)
	skeleton=_model.get_node("Skeleton3D")
	if info.has("prefix"): _rename_bones(info.prefix)
	react_mult=float(info.react)
	_animation=_model.get_node("AnimationPlayer")
	_animation.add_animation_library("z",_anims_for(float(info.get("hips",1.0))))
	_animation.callback_mode_process=AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	_play("idle",1.0)
	_animation.seek(randf()*4.0,true)
	_animation.advance(0)
	_capsule=CapsuleShape3D.new()
	_capsule.radius=0.3
	_capsule.height=1.2
	_capsule_low=CapsuleShape3D.new()
	_capsule_low.radius=0.28
	_capsule_low.height=0.6
	_sweep=PhysicsShapeQueryParameters3D.new()
	_sweep.shape=_capsule
	_sweep.collision_mask=1
	_pitch=randf_range(0.82,1.18)*float(info.pitch)
	_voice_timer=randf_range(1.0,6.0)
	crowd.append(self)
	for mesh in _model.find_children("*","MeshInstance3D",true,false):
		mesh.extra_cull_margin=4.0
		for surface in mesh.mesh.get_surface_count():
			# Materiál sdílejí všechny zombie; jeden na povrch místo kopie pro každý kus.
			var source: Material=mesh.get_active_material(surface)
			if not _shared_materials.has(source):
				var material: StandardMaterial3D=source.duplicate()
				material.texture_filter=BaseMaterial3D.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS_ANISOTROPIC
				_shared_materials[source]=material
			# Varianta, která se pod hladinou nekreslí do odrazu vody.
			mesh.set_surface_override_material(surface,preload("res://scripts/water_clip.gd").clip_material(_shared_materials[source]))
		# Vlastní vrstva: krvavé stopy se promítají jen na místnost, ne na těla.
		mesh.layers=512
		mesh.visibility_range_end=50.0    # vzdálená těla (mrtvoly, spáči) se nekreslí
	# Žhnoucí oči: v šeru prozradí, odkud zombie jde.
	if _eye_material==null:
		_eye_material=StandardMaterial3D.new()
		_eye_material.albedo_color=Color(0.02,0.01,0.0)
		_eye_material.emission_enabled=true
		_eye_material.emission=Color(1.0,0.5,0.08)
		_eye_material.emission_energy_multiplier=5.0
	for eye_name in ["mixamorig_LeftEye","mixamorig_RightEye"]:
		if skeleton.find_bone(eye_name)<0: continue
		var socket:=BoneAttachment3D.new()
		skeleton.add_child(socket)
		socket.bone_name=eye_name
		var eye:=MeshInstance3D.new()
		var ball:=SphereMesh.new()
		ball.radius=0.0105
		ball.height=0.021
		ball.radial_segments=10
		ball.rings=5
		eye.mesh=ball
		eye.material_override=_eye_material
		eye.cast_shadow=GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.layers=512
		eye.position=EYE_OFFSET
		socket.add_child(eye)
		_eyes.append(eye)
	simulator=PhysicalBoneSimulator3D.new()
	simulator.name="Ragdoll"
	skeleton.add_child(simulator)
	for part in [
		["Hips","Spine",0.15,12.0], ["Spine","Spine2",0.13,8.0],
		["Spine2","Neck",0.15,14.0], ["Neck","Head",0.065,1.5], ["Head","HeadTop_End",0.105,4.0],
		["LeftArm","LeftForeArm",0.065,3.0], ["LeftForeArm","LeftHand",0.05,2.0],
		["RightArm","RightForeArm",0.065,3.0], ["RightForeArm","RightHand",0.05,2.0],
		["LeftHand","LeftHandMiddle1",0.045,0.6], ["RightHand","RightHandMiddle1",0.045,0.6],
		["LeftUpLeg","LeftLeg",0.085,7.0], ["LeftLeg","LeftFoot",0.065,4.0],
		["RightUpLeg","RightLeg",0.085,7.0], ["RightLeg","RightFoot",0.065,4.0],
		["LeftFoot","LeftToeBase",0.065,1.0], ["RightFoot","RightToeBase",0.065,1.0]]:
		_build_part(part[0],part[1],part[2],part[3])
	for bone in bodies:
		var parent:=_physical_parent(bone)
		if parent>=0:
			bodies[bone].add_collision_exception_with(bodies[parent])
			bodies[parent].add_collision_exception_with(bodies[bone])
	# Dokud zombie žije, fyzikální kosti se nepřepočítávají; zapnou se až při smrti.
	simulator.active=false
	_gib=GibScript.new()
	skeleton.add_child(_gib)
	# Pevná překážka pro hráče: skrz zombie se nedá projít.
	_blocker=AnimatableBody3D.new()
	_blocker.sync_to_physics=false
	_blocker.collision_layer=128
	_blocker.collision_mask=0
	_blocker_shape=CapsuleShape3D.new()
	_blocker_shape.radius=0.3
	_blocker_shape.height=1.7
	_blocker_col=CollisionShape3D.new()
	_blocker_col.shape=_blocker_shape
	_blocker_col.position.y=0.85
	_blocker.add_child(_blocker_col)
	add_child(_blocker)

func _rename_bones(prefix: String) -> void:
	# Model s jinou předponou kostí (mixamorig5_) převést na mixamorig_, aby seděly animace i ragdoll.
	# Skin (vazba meshe na kosti) je sdílený, přejmenuje se jen jednou.
	for i in skeleton.get_bone_count():
		var n:=skeleton.get_bone_name(i)
		if n.begins_with(prefix): skeleton.set_bone_name(i,"mixamorig_"+n.substr(prefix.length()))
	for mesh in _model.find_children("*","MeshInstance3D",true,false):
		var skin: Skin=(mesh as MeshInstance3D).skin
		if skin==null or _renamed.has(skin): continue
		_renamed[skin]=true
		for b in skin.get_bind_count():
			var n2:=skin.get_bind_name(b)
			if n2.begins_with(prefix): skin.set_bind_name(b,"mixamorig_"+n2.substr(prefix.length()))

func bone_pose(bone: int) -> Transform3D:
	# Globální pózu drží engine v mezipaměti; ruční skládání přes rodiče bylo nejdražší částí zombie.
	return skeleton.get_bone_global_pose(bone) if bone>=0 else Transform3D.IDENTITY

func _build_part(bone_name: String, end_name: String, radius: float, mass_now: float) -> void:
	var bone:=skeleton.find_bone("mixamorig_"+bone_name)
	var end:=skeleton.find_bone("mixamorig_"+end_name)
	if bone<0: return
	var start_rest:=skeleton.get_bone_global_rest(bone)
	var to_end: Vector3
	if end>=0:
		to_end=start_rest.affine_inverse()*skeleton.get_bone_global_rest(end).origin
	else:
		# Chybějící koncová kost (některé modely nemají prsty): první dítě, nebo krátký kus ve směru kosti.
		var kids:=skeleton.get_bone_children(bone)
		to_end=start_rest.affine_inverse()*skeleton.get_bone_global_rest(kids[0]).origin if kids.size()>0 else Vector3(0,0.08,0)
	var length_now:=to_end.length()
	var offset:=Transform3D(Basis(Quaternion(Vector3.UP,to_end.normalized())),to_end*0.5)
	var shape:=CapsuleShape3D.new()
	shape.radius=radius
	shape.height=maxf(length_now,radius*2.0+0.005)
	var body:=PhysicalBone3D.new()
	body.name="Physics_"+bone_name
	simulator.add_child(body)
	body.set("bone_name","mixamorig_"+bone_name)
	body.body_offset=offset
	body.joint_offset=offset.affine_inverse()
	body.mass=mass_now
	body.friction=0.85
	body.bounce=0
	body.linear_damp=0.03
	body.angular_damp=0.25
	body.collision_layer=0
	body.collision_mask=1|32
	body.set_meta("part_name",bone_name)
	body.set_meta("half",maxf(0.0,shape.height*0.5-radius))
	body.set_meta("radius",radius)
	_ids[bone_name]=bone
	_inertia[bone]=maxf(mass_now*(3.0*radius*radius+shape.height*shape.height)/12.0,mass_now*radius*radius*0.4)
	# Lehké články dostanou vyšší setrvačnost, jinak se v kloubech třepou.
	var boost: float={"Neck":0.035,"Head":0.09,"LeftHand":0.012,"RightHand":0.012,"LeftFoot":0.03,"RightFoot":0.03}.get(bone_name,0.0)
	if boost>_inertia[bone]:
		_inertia[bone]=boost
		PhysicsServer3D.body_set_param(body.get_rid(),PhysicsServer3D.BODY_PARAM_INERTIA,Vector3.ONE*boost)
	bodies[bone]=body
	_configure_joint(bone)
	var collision:=CollisionShape3D.new()
	collision.shape=shape
	body.add_child(collision)
	body.set_meta("zombie",self)
	body.set_meta("bone",bone)
	bodies[bone]=body
	var area:=Area3D.new()
	area.collision_layer=64
	area.collision_mask=0
	area.monitoring=false
	area.set_meta("zombie",self)
	area.set_meta("bone",bone)
	area.set_meta("offset",offset)
	var hit_shape:=CollisionShape3D.new()
	hit_shape.shape=shape
	area.add_child(hit_shape)
	add_child(area)
	hitboxes.append(area)
	area.global_transform=skeleton.global_transform*bone_pose(bone)*offset

func _exit_tree() -> void:
	crowd.erase(self)

func _play(clip: String, speed: float) -> void:
	_clip_speed=speed
	if _clip==clip: return
	_clip=clip
	var blend:=0.12 if clip.contains("attack") else (0.22 if clip.contains("crawl") else 0.28)
	_animation.play("z/"+clip,blend)

func _say(group: String, volume: float) -> void:
	if sfx: sfx.play_at(group,global_position+Vector3.UP*(0.4 if _is_low() else 1.7),volume,_pitch)

func _wl() -> float:
	return float(water_at.call(global_position)) if water_at.is_valid() else water_level

func _is_low() -> bool:
	return crawling or swimming or _low

func _is_descendant(bone: int, ancestor: int) -> bool:
	var parent:=skeleton.get_bone_parent(bone)
	while parent>=0:
		if parent==ancestor: return true
		parent=skeleton.get_bone_parent(parent)
	return false

func stump(bone: int) -> Transform3D:
	# Místo, kde končí odstřelená část; sleduje tělo zaživa i v ragdollu.
	if dead and not _frozen and bodies.has(bone):
		return bodies[bone].global_transform*bodies[bone].body_offset.affine_inverse()
	return skeleton.global_transform*bone_pose(bone)

# ------------------------------------------------------------------ pohyb a rozhodování

func _physics_process(dt: float) -> void:
	var _perf_t0:=Time.get_ticks_usec()
	_physics_process_timed(dt)
	PerfMon.add("Zombie AI",Time.get_ticks_usec()-_perf_t0)

func _physics_process_timed(dt: float) -> void:
	if dead:
		for impact in _pending_impacts:
			var body: PhysicalBone3D=bodies.get(impact[0])
			if body:
				body.apply_impulse(impact[2],(impact[1]-body.global_position).limit_length(0.4))
		_pending_impacts.clear()
		_death_time+=dt
		_drive_muscles()
		_impact_sounds(dt)
		return
	if _ragdolled:
		_update_ragdoll(dt)
		for area in hitboxes:
			if area.collision_layer!=0:
				area.global_transform=skeleton.global_transform*bone_pose(area.get_meta("bone"))*area.get_meta("offset")
		return
	_time+=dt
	_think(dt)
	_animation.advance(dt*_clip_speed*(_gait_factor if _clip in ["walk","run","crawl","crawl_fast"] else 1.0))
	_look(dt)
	_update_reactions(dt)
	_sample_pose_motion(dt)
	for area in hitboxes:
		if area.collision_layer!=0:
			area.global_transform=skeleton.global_transform*bone_pose(area.get_meta("bone"))*area.get_meta("offset")
	var low:=_is_low()
	if low!=_blocker_low:
		_blocker_low=low
		_blocker_shape.height=0.75 if low else 1.7
		_blocker_col.position.y=0.38 if low else 0.85
	if ai:
		_voice_timer-=dt
		if _voice_timer<=0.0:
			_voice_timer=randf_range(1.6,4.5)
			# Víc hlasů: sténání, občas chrčení. U velké hordy jen část, ať to není kakofonie.
			if crowd.size()<=6 or randf()<0.75:
				_say("zombie_gurgle" if randf()<0.2 else "zombie_groan",-8.0)
		_announce(dt)

# Ohlášení: zombie, kterou hráč ještě nevidí (za rohem, za zády), se nejdřív ozve –
# hlasitě a ze svého směru. Strach dělá to, co slyšíš, ale nevidíš.
var _announced:=false
var _announce_check:=0.0

func _announce(dt: float) -> void:
	if _announced or not is_instance_valid(target) or sfx==null: return
	_announce_check-=dt
	if _announce_check>0.0: return
	_announce_check=0.4
	var d:=global_position.distance_to(target.global_position)
	if d>18.0 or d<4.0: return
	var cam: Camera3D=target.get("camera")
	if cam==null: return
	var head:=global_position+Vector3.UP*1.5
	var to:=(head-cam.global_position).normalized()
	var in_view:=to.dot(-cam.global_basis.z)>0.55
	var blocked:=not get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(cam.global_position,head,1)).is_empty()
	if in_view and not blocked: 
		_announced=true          # už ji vidí – ohlášení zbytečné
		return
	_announced=true
	_say("zombie_gurgle" if randf()<0.4 else "zombie_groan",-3.0+(18.0-d)*0.15)

func _lured() -> bool:
	# Zombie jde po dýňové bombě: mlátí do ní, hráče to nezraní.
	return is_instance_valid(target) and target.has_method("_pull_zombies")

func _look(dt: float) -> void:
	# Hlava sleduje kořist, i když tělo zrovna obchází překážku.
	var yaw:=0.0
	var pitch:=0.0
	if ai and is_instance_valid(target) and not _is_low() and _attack_left<=0.0:
		var local: Vector3=global_transform.affine_inverse()*(target.global_position+Vector3.UP*1.5)
		yaw=clampf(atan2(local.x,local.z),-0.85,0.85)
		pitch=clampf(atan2(local.y-1.75,Vector2(local.x,local.z).length()),-0.5,0.4)
	_look_yaw=lerpf(_look_yaw,yaw,1.0-exp(-6.0*dt))
	_look_pitch=lerpf(_look_pitch,pitch,1.0-exp(-6.0*dt))
	if absf(_look_yaw)<0.01 and absf(_look_pitch)<0.01: return
	var neck: int=_ids["Neck"]
	var head: int=_ids["Head"]
	_rotate_bone(neck,Vector3.UP,_look_yaw*0.45)
	_rotate_bone(head,Vector3.UP,_look_yaw*0.45)
	_rotate_bone(head,Vector3.RIGHT,-_look_pitch*0.7)

func _ray(from: Vector3, to: Vector3) -> Dictionary:
	return get_world_3d().direct_space_state.intersect_ray(PhysicsRayQueryParameters3D.create(from,to,1))

func _move(step: Vector3) -> void:
	var space:=get_world_3d().direct_space_state
	var dt:=get_physics_process_delta_time()
	var low:=_is_low()
	for part in [Vector3(step.x,0,0),Vector3(0,0,step.z)]:
		if part.is_zero_approx(): continue
		_sweep.shape=_capsule_low if low else _capsule
		_sweep.transform=Transform3D(Basis.IDENTITY,global_position+Vector3(0,0.42 if low else 0.95,0))
		_sweep.motion=part
		var allowed: float=space.cast_motion(_sweep)[0]
		if allowed<=0.0:
			if not low:
				# Nízký průlez: vestoje to nejde, vleže ano.
				_sweep.shape=_capsule_low
				_sweep.transform.origin=global_position+Vector3(0,0.42,0)
				if space.cast_motion(_sweep)[0]>0.5:
					_low=true
					_low_timer=1.2
			continue
		# Hrana bez vody pod ní se nepřekračuje; do hluboké vody se naopak plave.
		var ahead: Vector3=global_position+part*allowed+part.normalized()*0.25
		var probe:=_ray(ahead+Vector3.UP*0.6,ahead+Vector3.DOWN*9.0)
		if probe.is_empty(): continue
		var deep_ahead: bool=probe.position.y<_wl()-DEEP
		if not deep_ahead and not swimming and _drop.is_zero_approx() and probe.position.y<global_position.y-0.6: continue
		global_position+=part*allowed
	var ground:=_ray(global_position+Vector3.UP*0.6,global_position+Vector3.DOWN*12.0)
	if ground.is_empty(): return
	# Sešlápnutí z galerie: zbytek pádu je fyzikální, jako hadrová panenka.
	if not _drop.is_zero_approx() and global_position.y>ground.position.y+1.2:
		_start_ragdoll_fall()
		return
	swimming=ground.position.y<_wl()-DEEP
	if swimming:
		_fall=0.0
		global_position.y=lerpf(global_position.y,_wl()-SWIM_LEVEL,1.0-exp(-5.0*dt))
	elif global_position.y>ground.position.y+0.02:
		_fall+=9.8*dt
		global_position.y=maxf(ground.position.y,global_position.y-_fall*dt)
	else:
		if _fall>4.0: _land()
		_fall=0.0
		global_position.y=lerpf(global_position.y,ground.position.y,1.0-exp(-14.0*dt))
	if _low:
		_low_timer-=dt
		if _low_timer<=0.0:
			if _ray(global_position+Vector3.UP*0.5,global_position+Vector3.UP*1.8).is_empty(): _low=false
			else: _low_timer=0.3

func drop(direction: Vector3) -> void:
	# Zombie na galerii: vyjde ze tmy k hraně a spadne dolů mezi hráče.
	ai=true
	_drop=direction.normalized()
	rotation.y=atan2(_drop.x,_drop.z)

func lie_down() -> void:
	# Zombie leží na zemi jako mrtvola; vstane, až se hráč přiblíží (nebo ho někdo trefí).
	ai=false
	_drop=Vector3.FORWARD.rotated(Vector3.UP,rotation.y)*0.05
	_sleeping=true
	_start_ragdoll_fall()

func _sleep_freeze() -> void:
	# Ležící „mrtvola“ se zapeče do kostry a fyzika se vypne, dokud ji hráč neprobudí.
	var poses:=[]
	var inverse:=skeleton.global_transform.affine_inverse()
	for bone in skeleton.get_bone_count():
		var parent:=skeleton.get_bone_parent(bone)
		if bodies.has(bone): poses.append((inverse*bodies[bone].global_transform*bodies[bone].body_offset.affine_inverse()).orthonormalized())
		elif parent>=0: poses.append(poses[parent]*skeleton.get_bone_pose(bone))
		else: poses.append(skeleton.get_bone_pose(bone))
	simulator.physical_bones_stop_simulation()
	simulator.active=false
	for bone in skeleton.get_bone_count():
		var parent:=skeleton.get_bone_parent(bone)
		var local: Transform3D=poses[parent].affine_inverse()*poses[bone] if parent>=0 else poses[bone]
		skeleton.set_bone_pose_position(bone,local.origin)
		skeleton.set_bone_pose_rotation(bone,local.basis.get_rotation_quaternion())
	for body in bodies.values(): body.collision_layer=0
	_sleep_frozen=true

func wake() -> void:
	if not _sleeping: return
	_sleeping=false
	ai=true
	if sfx: sfx.play_at("sleeper_wake",global_position+Vector3.UP*0.5,-4.0,randf_range(0.9,1.05))
	if _sleep_frozen:
		_sleep_frozen=false
		simulator.active=true
		simulator.influence=1.0
		simulator.physical_bones_start_simulation()
		for id in bodies:
			bodies[id].global_transform=(skeleton.global_transform*bone_pose(id)*bodies[id].body_offset).orthonormalized()
			bodies[id].collision_layer=32
	_begin_rise(bodies[_ids["Hips"]])
	_say("zombie_attack",-3.0)

func _start_ragdoll_fall() -> void:
	_ragdolled=true
	_rag_t=0.0
	_rag_rise=false
	_blocker.collision_layer=0
	simulator.influence=1.0
	simulator.active=true
	simulator.physical_bones_start_simulation()
	for id in bodies:
		bodies[id].global_transform=(skeleton.global_transform*bone_pose(id)*bodies[id].body_offset).orthonormalized()
	for id in bodies: _configure_joint(id,false)
	_add_overlap_exceptions()
	var push:=_drop*1.6+Vector3.DOWN*0.5
	for id in bodies:
		var body: PhysicalBone3D=bodies[id]
		body.collision_layer=32
		body.linear_damp=0.05
		body.angular_damp=0.6
		body.linear_velocity=push
	# Trochu rotace, ať nepadá jako prkno.
	var spine: PhysicalBone3D=bodies.get(_ids.get("Spine2",-1))
	if spine: spine.angular_velocity=Vector3(randf_range(-2,2),0,randf_range(-2,2))
	_drop=Vector3.ZERO
	if not _sleeping: _say("zombie_attack",-5.0)

func _update_ragdoll(dt: float) -> void:
	_rag_t+=dt
	var hips: PhysicalBone3D=bodies[_ids["Hips"]]
	if _sleeping:
		if _rag_t>2.5 and not get_meta("calm",false):
			set_meta("calm",true)
			for body in bodies.values():
				body.linear_damp=6.0
				body.angular_damp=6.0
		if _rag_t>4.0 and not _sleep_frozen: _sleep_freeze()
		if target and is_instance_valid(target) and _rag_t>1.0:
			var to: Vector3=target.global_position-bodies[_ids["Hips"]].global_position
			if Vector2(to.x,to.z).length()<4.5 and absf(to.y)<2.0: wake()
		return
	if not _rag_rise:
		var settled:=_rag_t>1.3 and hips.linear_velocity.length()<0.5
		if settled or _rag_t>4.0:
			_begin_rise(hips)
		elif _rag_t>0.15 and hips.global_position.y<_wl()+0.6 and not get_meta("splashed",false):
			set_meta("splashed",true)
			var spot:=Vector3(hips.global_position.x,_wl()+0.03,hips.global_position.z)
			if splash.is_valid(): splash.call(spot,0.8)
			if sim: sim.add_impulse(Vector2(spot.x,spot.z),0.6,-1.6)
			if sfx: sfx.play_at("splash_big",spot,-5.0,0.9)
		return
	# Zvedání: ragdoll póza plynule přechází do animace.
	var k:=clampf((_rag_t)/1.1,0.0,1.0)
	simulator.influence=1.0-smoothstep(0.0,1.0,k)
	_animation.advance(dt)
	if k>=1.0:
		simulator.physical_bones_stop_simulation()
		simulator.active=false
		simulator.influence=1.0
		for body in bodies.values():
			body.collision_layer=0
			body.linear_damp=0.03
			body.angular_damp=0.25
		_blocker.collision_layer=128
		_ragdolled=false
		_stagger=0.4
		set_meta("splashed",false)

func _begin_rise(hips: PhysicalBone3D) -> void:
	_rag_rise=true
	_rag_t=0.0
	# Kořen postavy přesunout pod pánev a natočit podle těla; tělesa zůstanou, kde leží.
	var keep:={}
	for id in bodies: keep[id]=bodies[id].global_transform
	var at:=hips.global_position
	var ground:=_ray(at+Vector3.UP*0.5,at+Vector3.DOWN*4.0)
	var floor_y: float=ground.position.y if not ground.is_empty() else global_position.y
	var forward:=hips.global_basis.z
	forward.y=0
	global_position=Vector3(at.x,floor_y,at.z)
	if forward.length()>0.1: rotation.y=atan2(forward.x,forward.z)
	for id in bodies:
		bodies[id].global_transform=keep[id]
		bodies[id].linear_velocity=Vector3.ZERO
		bodies[id].angular_velocity=Vector3.ZERO
		bodies[id].linear_damp=8.0
		bodies[id].angular_damp=8.0
	_play("idle",1.0)

func _land() -> void:
	_drop=Vector3.ZERO
	_stagger=0.7
	var spot:=Vector3(global_position.x,_wl()+0.03,global_position.z)
	if global_position.y<_wl()+0.1:
		if splash.is_valid(): splash.call(spot,0.7)
		if sim: sim.add_impulse(Vector2(spot.x,spot.z),0.5,-1.5)
		if sfx: sfx.play_at("splash_big",spot,-6.0,0.95)
	_say("zombie_attack",-5.0)

func _splash_step(amount: float) -> void:
	# Vlny a šplouchání při brodění a plavání; zvuk jen občas, ať hala nezní jako vodopád.
	var in_water:=swimming or global_position.y<_wl()-0.05
	if not in_water:
		_dry_step+=amount
		var stride:=0.62 if tier=="walk" else 1.05
		if _dry_step>=stride:
			_dry_step=fmod(_dry_step,stride)
			if sfx and not crawling and is_instance_valid(target) and global_position.distance_to(target.global_position)<12.0:
				sfx.play_at("step_tile",global_position,-19.0,0.78 if kind=="alpha" else 0.92)
		return
	_wade+=amount
	if _wade<(0.55 if swimming else 0.8): return
	_wade=0.0
	if sim: sim.add_impulse(Vector2(global_position.x,global_position.z),0.3 if swimming else 0.24,-0.7 if swimming else -0.45)
	_step_clock+=1
	if sfx and _step_clock%3==0 and is_instance_valid(target) and global_position.distance_to(target.global_position)<16.0:
		sfx.play_at("step_water",global_position,-15.0,0.9)

func _think(dt: float) -> void:
	_velocity=Vector3.ZERO
	_stagger=maxf(0.0,_stagger-dt)
	_gait_factor=lerpf(_gait_factor,0.15 if _stagger>0.0 else 1.0,1.0-exp(-(24.0 if _stagger>0.0 else 7.0)*dt))
	if _knock.length()>0.03:
		_move(_knock*dt)
		_knock*=exp(-9.0*dt)
	if _emerge>0.0:
		_rise(dt)
		return
	if not _drop.is_zero_approx():
		_play("walk" if tier=="walk" else "run",2.0 if tier=="walk" else 0.6)
		_move(_drop*(1.6 if _fall<=0.0 else 0.8)*dt)
		return
	if not ai or not is_instance_valid(target):
		if _is_low(): _play("crawl",0.35)
		else: _play("idle",1.0)
		_move(Vector3.ZERO)
		return
	var goal:=target.global_position
	var to:=goal-global_position
	var height:=absf(to.y)
	to.y=0
	var distance:=to.length()
	var low:=_is_low()
	# Cesta po navigační síti; bez ní (nebo zblízka) přímo za cílem.
	_repath-=dt
	if _repath<=0.0:
		_repath=randf_range(0.3,0.5)
		_corner=goal
		if distance>2.0:
			var path:=NavigationServer3D.map_get_path(get_world_3d().navigation_map,global_position,goal,true)
			for i in range(1,path.size()):
				if Vector2(path[i].x-global_position.x,path[i].z-global_position.z).length()>0.5:
					_corner=path[i]
					break
	var aim:=_corner-global_position if distance>2.0 else to
	aim.y=0
	if aim.length()>0.05:
		rotation.y=lerp_angle(rotation.y,atan2(aim.x,aim.z),1.0-exp(-(3.0 if low else 7.0)*dt))
	var forward:=Basis(Vector3.UP,rotation.y)*Vector3.BACK
	if _scream_left>0.0:
		_scream_left-=dt
		_move(Vector3.ZERO)
		return
	if _attack_left>0.0:
		_attack_left-=dt
		_attack_time+=dt
		# Výpad: běžící zombie se do úderu vrhne a setrvačnost doběhne až k ráně (nezastaví se jako socha).
		var hit_t:=ATTACK_HIT/ATTACK_SPEED
		var lunge:=maxf(0.6,_lunge*(1.0-_attack_time/hit_t))
		if _attack_time<hit_t and distance>0.8: _move(forward*lunge*dt)
		else: _move(Vector3.ZERO)
		if not _attack_hit:
			if _attack_time>=ATTACK_HIT/ATTACK_SPEED:
				_attack_hit=true
				if distance<1.9 and height<1.5 and to.normalized().dot(forward)>0.3 and not _lured(): attacked.emit(attack_damage)
			elif distance>2.8: _attack_left=0.0      # cíl utekl z dosahu: nedokončovat úder do prázdna
		return
	var reach:=1.3 if (tier=="walk" or kind=="alpha" or swimming) else 2.1
	if distance<(1.05 if low else reach) and height<1.5 and _stagger<=0.0:
		if low:
			_play("crawl",0.5)
			_bite_timer-=dt
			if _bite_timer<=0.0:
				_bite_timer=1.1
				_say("zombie_attack",-6.0)
				if not _lured(): attacked.emit(attack_damage*0.7)
			_move(Vector3.ZERO)
		else:
			_play("attack",ATTACK_SPEED)
			_animation.seek(0.0,true)
			_attack_left=ATTACK_END/ATTACK_SPEED
			_attack_time=0.0
			_attack_hit=false
			_lunge=0.6 if distance<1.4 else float(SPEEDS[tier])*0.8*_gait_factor
			_say("zombie_attack",-5.0 if _lunge<1.0 else -2.5)
		return
	var speed:=0.0
	if swimming:
		speed=1.35
		_play("crawl_fast",speed/2.32)
	elif low:
		speed=0.7 if tier=="walk" else 1.5
		if tier=="walk": _play("crawl",speed/0.46)
		else: _play("crawl_fast",speed/2.32)
	else:
		speed=SPEEDS[tier]
		if tier=="walk": _play("walk",speed/0.35)
		else: _play("run",speed/3.29)
	speed*=_gait_factor
	var step:=forward*speed
	# Zombie se navzájem neprolínají.
	for other in crowd:
		if other==self or not is_instance_valid(other) or other.dead: continue
		var away: Vector3=global_position-other.global_position
		away.y=0
		if away.length()<0.75 and away.length()>0.01: step+=away.normalized()*(0.75-away.length())*4.0
	_velocity=step
	_move(step*dt)
	_splash_step(speed*dt)

func alert(scream: bool) -> void:
	ai=true
	if scream and not _is_low():
		_play("scream",1.4)
		_scream_left=2.8/1.4
		_say("zombie_attack",-4.0)

func emerge() -> void:
	# Vynoření z hlubokého bazénu: začíná pod hladinou u dna.
	ai=true
	_emerge=1.9
	_emerged=false
	global_position.y=_wl()-2.5
	_play("idle",1.0)

func _rise(dt: float) -> void:
	_emerge-=dt
	var k:=1.0-_emerge/1.9
	if k<0.7:
		global_position.y=lerpf(_wl()-2.5,_wl()-1.5,smoothstep(0.0,0.62,k))
	else:
		_play("crawl_fast",0.6)
		global_position.y=lerpf(_wl()-1.5,_wl()-SWIM_LEVEL,smoothstep(0.7,1.0,k))
	if not _emerged and k>0.42:
		_emerged=true
		var surface:=Vector3(global_position.x,_wl()+0.03,global_position.z)
		if splash.is_valid(): splash.call(surface,0.85)
		if sim:
			sim.add_impulse(Vector2(surface.x,surface.z),0.55,-1.6)
			sim.add_impulse(Vector2(surface.x,surface.z),0.25,-1.2)
		if sfx: sfx.play_at("splash_big",surface,-7.0,0.85)
		_say("zombie_gurgle",-3.0)
	if is_instance_valid(target):
		var to:=target.global_position-global_position
		rotation.y=lerp_angle(rotation.y,atan2(to.x,to.z),1.0-exp(-3.0*dt))
	if _emerge<=0.0: swimming=true

# ------------------------------------------------------------------ zásahy

func hit(bone: int, point: Vector3, direction: Vector3, strength: float=1.0, damage: float=50.0, flat: bool=false) -> void:
	if _sleeping and health-damage>0.0 and not insta_kill: wake()
	if not bodies.has(bone) or not direction.is_finite() or direction.is_zero_approx(): return
	direction=direction.normalized()
	strength=clampf(strength,0.1,3.0)
	var region:=_region(bone)
	# Hybnost střely působí v místě zásahu, nikoli vždy do pánve a vzhůru.
	var weapon_energy:=clampf(sqrt(maxf(damage,1.0)/50.0),0.55,1.65)
	var impulse:=direction*14.0*strength*weapon_energy*float(TRANSFER[region])
	if dead:
		if _frozen: return
		_wake()
		_pending_impacts.append([bone,point,impulse])
		return
	if _death_pending: return
	last_region=region
	# flat = úder pažbou: stejná síla do kterékoli části těla.
	var amount:=damage if flat else damage*strength*float(MULTIPLIER[region])
	if insta_kill: amount=maxf(amount,health+1.0)
	health-=amount
	var part: String=bodies[bone].get_meta("part_name")
	var side:="Left" if part.begins_with("Left") else "Right"
	var limb:=side+region
	if region=="arm" or region=="leg": _limb_damage[limb]=float(_limb_damage.get(limb,0.0))+amount
	if health<=0.0:
		_death_pending=true
		# Smrtelná rána zblízka trhá: hlava praskne, končetina odletí.
		if region=="head" and (strength>0.8 or randf()<0.5): _sever("Head",direction)
		elif region=="leg" and randf()<0.6: _sever(side+"Leg",direction)
		elif region=="arm" and randf()<0.6: _sever(side+"ForeArm",direction)
		kill.call_deferred(point,impulse,bone)
		return
	# Síla škubnutí podle skutečné rány: Deagle a brokovnice trhnou víc než samopal.
	_react(bone,point,direction,strength*clampf(amount/40.0,0.85,1.8),region)
	if flat:
		_stagger=0.7
		_knock+=Vector3(direction.x,0,direction.z)*2.6
	var limit:=maxf(70.0,max_health*0.55)
	if region=="leg" and float(_limb_damage[limb])>=limit:
		_sever(side+"Leg",direction)
		if not crawling:
			# Bez nohy jde k zemi a plazí se dál.
			crawling=true
			_attack_left=0.0
			_scream_left=0.0
			_stagger=0.6
	elif region=="arm" and float(_limb_damage[limb])>=limit:
		_sever(side+"ForeArm",direction)

func _sever(part: String, direction: Vector3) -> void:
	var bone: int=_ids.get(part,-1)
	if bone<0 or _severed.has(bone): return
	_severed[bone]=true
	_gib.bones.append(bone)
	for area in hitboxes:
		var owner_bone: int=area.get_meta("bone")
		if owner_bone==bone or _is_descendant(owner_bone,bone): area.collision_layer=0
	if part=="Head":
		for eye in _eyes: eye.visible=false
	var origin:=stump(bone).origin
	if fx:
		fx.gib(origin,direction)
		fx.spurt(self,bone,2.6 if part=="Head" else 1.8)
	if sfx:
		sfx.play_at("gib",origin,-2.0,randf_range(0.9,1.1))
		# Odstřelená hlava: těžký mokrý úder navrch, ať to má váhu.
		if part=="Head": sfx.play_at("gore_smash",origin,-6.0,randf_range(0.92,1.05))

func _react(bone: int, point: Vector3, direction: Vector3, strength: float, region: String) -> void:
	var local_direction: Vector3=global_basis.inverse()*direction
	var local_point: Vector3=global_transform.affine_inverse()*point
	# Moment zásahu kolem svislé osy: rána do ramene tělo stočí, rána do středu jen prohne.
	var twist:=clampf((local_point.z*local_direction.x-local_point.x*local_direction.z)*4.0,-1.0,1.0)
	var part: String=bodies[bone].get_meta("part_name") if bodies.has(bone) else ""
	# Zásah do ramene/nadloktí: výrazná rotace trupu; rameno odhodí ve směru střely.
	var upper:=part.ends_with("Arm") and not part.ends_with("ForeArm")
	var side_sign:=1.0 if part.begins_with("Left") else -1.0
	if upper: twist=clampf(twist*1.6+side_sign*signf(local_direction.z)*0.6,-1.2,1.2)
	_reactions.append({"bone":bone,"direction":local_direction,"twist":twist,"region":region,"strength":minf(strength,2.0)*react_mult,"age":0.0,"upper":upper,"part":part})
	if _reactions.size()>6: _reactions.pop_front()
	_stagger=maxf(_stagger,float({"head":0.5,"torso":0.3,"leg":0.42,"arm":0.16}[region]))
	# Zásah do těla nebo hlavy přeruší rozmáchnutí: palba má zastavovací účinek.
	if _attack_left>0.0 and not _attack_hit and region!="arm": _attack_left=0.0
	_knock+=Vector3(direction.x,0,direction.z)*float({"head":1.2,"torso":1.7,"leg":0.8,"arm":0.5}[region])*strength*react_mult

func _rotate_bone(bone: int, axis: Vector3, angle: float) -> void:
	if bone<0 or axis.length_squared()<0.0001: return
	var pose_now:=bone_pose(bone)
	var parent:=skeleton.get_bone_parent(bone)
	var desired:=Basis(Quaternion(axis.normalized(),angle))*pose_now.basis
	skeleton.set_bone_pose_rotation(bone,(bone_pose(parent).basis.inverse()*desired).get_rotation_quaternion())

func _update_reactions(dt: float) -> void:
	if _reactions.is_empty(): return
	var reference:={}
	for id in bodies: reference[id]=skeleton.get_bone_pose_rotation(id)
	var hips_before:=skeleton.get_bone_pose_position(0)
	var spine: int=_ids["Spine"]
	var chest: int=_ids["Spine2"]
	var neck: int=_ids["Neck"]
	var head: int=_ids["Head"]
	for reaction in _reactions:
		reaction.age+=dt
		# Prudké škubnutí, pak tlumený návrat s malým překmitem; zásahy se sčítají.
		var age: float=reaction.age
		var envelope: float=(1.0-exp(-age*38.0))*exp(-age*3.8)*(0.8+0.2*cos(age*10.0))*float(reaction.strength)*REACT_GAIN
		var direction: Vector3=reaction.direction
		var bend:=Vector3.UP.cross(direction)
		var twist: float=reaction.twist
		match reaction.region:
			"leg":
				var bone: int=reaction.bone
				var side: String="Left" if skeleton.get_bone_name(bone).contains("Left") else "Right"
				var thigh: int=_ids[side+"UpLeg"]
				var knee: int=_ids[side+"Leg"]
				var foot: int=_ids[side+"Foot"]
				var calf_hit: bool=String(reaction.part).ends_with("Leg") and not String(reaction.part).ends_with("UpLeg")
				var foot_hit: bool=String(reaction.part).ends_with("Foot")
				# Krátký místní úlek předchází pomalejšímu podklesnutí. Stehno jde za
				# impulzem, zásah lýtka zvlášť kopne bércem; koleno se neláme do stran.
				var kick: float=(1.0-exp(-age*65.0))*exp(-age*9.0)*float(reaction.strength)*REACT_GAIN
				var limb: Vector3=(bone_pose(knee).origin-bone_pose(thigh).origin).normalized()
				_rotate_bone(thigh,limb.cross(direction),kick*(0.24 if calf_hit or foot_hit else 0.65))
				_rotate_bone(knee,Vector3.RIGHT,kick*(0.95 if calf_hit else 0.5 if foot_hit else 0.32)+envelope*0.16)
				if foot_hit: _rotate_bone(foot,Vector3.RIGHT,kick*0.3)
				# Váha krátce přejde na zdravou nohu. Trup reaguje méně než samotná končetina.
				_rotate_bone(0,Vector3.FORWARD,envelope*(0.08 if side=="Left" else -0.08))
				_rotate_bone(spine,bend,-envelope*0.06)
				_rotate_bone(chest,Vector3.FORWARD,envelope*(-0.06 if side=="Left" else 0.06))
				skeleton.set_bone_pose_position(0,skeleton.get_bone_pose_position(0)-Vector3.UP*envelope*0.055)
			"arm":
				var bone: int=reaction.bone
				var limb: Vector3=bone_pose(bone).basis*bodies[bone].body_offset.origin
				_rotate_bone(bone,limb.cross(direction),envelope*1.1)
				if reaction.get("upper",false):
					# Rána do ramene trup stočí, rameno jde dozadu a hlava se zhoupne.
					_rotate_bone(spine,Vector3.UP,envelope*twist*0.45)
					_rotate_bone(chest,Vector3.UP,envelope*twist*0.75)
					_rotate_bone(chest,bend,envelope*0.14)
					_rotate_bone(neck,Vector3.UP,-envelope*twist*0.35)
				else:
					_rotate_bone(chest,Vector3.UP,envelope*twist*0.5)
					_rotate_bone(chest,bend,envelope*0.06)
			"head":
				_rotate_bone(neck,bend,envelope*0.55)
				_rotate_bone(head,bend,envelope*0.6)
				_rotate_bone(head,Vector3.UP,envelope*twist*0.5)
				_rotate_bone(chest,bend,envelope*0.22)
			_:
				_rotate_bone(spine,bend,envelope*0.34)
				_rotate_bone(chest,bend,envelope*0.3)
				_rotate_bone(chest,Vector3.UP,envelope*twist*0.6)
				_rotate_bone(neck,bend,-envelope*0.3)
				skeleton.set_bone_pose_position(0,skeleton.get_bone_pose_position(0)-Vector3.UP*envelope*0.03)
	_reactions=_reactions.filter(func(reaction): return reaction.age<1.3)
	# Série zásahů do silné zombie nesmí sečíst šest úleků do přetočeného kloubu.
	for id in reference:
		var region:=_region(id)
		var limit:=0.55 if region=="torso" else (0.85 if region=="head" else 0.95)
		if region=="leg" and String(bodies[id].get_meta("part_name")).ends_with("UpLeg"): limit=0.65
		var current:=skeleton.get_bone_pose_rotation(id)
		var angle: float=reference[id].angle_to(current)
		if angle>limit: skeleton.set_bone_pose_rotation(id,reference[id].slerp(current,limit/angle))
	var hips_now:=skeleton.get_bone_pose_position(0)
	hips_now.y=maxf(hips_now.y,hips_before.y-0.1)
	skeleton.set_bone_pose_position(0,hips_now)

# Přechod animace do fyziky zachová i švih končetin, ne jen rychlost kořene.
func _sample_pose_motion(dt: float) -> void:
	if dt<=0.0: return
	for id in bodies:
		var pose: Transform3D=(skeleton.global_transform*bone_pose(id)*bodies[id].body_offset).orthonormalized()
		if _pose_history.has(id):
			var previous: Transform3D=_pose_history[id]
			_pose_velocity[id]=((pose.origin-previous.origin)/dt-_velocity).limit_length(2.0)
			_pose_spin[id]=(_rotation_error(pose.basis,previous.basis)/dt).limit_length(5.0)
		_pose_history[id]=pose

func _wake() -> void:
	_resting=false
	_rest_timer=0.0
	for body in bodies.values():
		body.linear_damp=0.03
		body.angular_damp=0.25

func _add_overlap_exceptions() -> void:
	# Části, které se v klidové póze prolínají, by se při zapnutí sebekolize odstřelily.
	var ids:=bodies.keys()
	for i in ids.size():
		for j in range(i+1,ids.size()):
			var a: PhysicalBone3D=bodies[ids[i]]
			var b: PhysicalBone3D=bodies[ids[j]]
			var nearest:=1e9
			for u in 5:
				var pa:=a.global_position+a.global_basis.y*float(a.get_meta("half"))*(u*0.5-1.0)
				for v in 5:
					var pb:=b.global_position+b.global_basis.y*float(b.get_meta("half"))*(v*0.5-1.0)
					nearest=minf(nearest,pa.distance_to(pb))
			if nearest<float(a.get_meta("radius"))+float(b.get_meta("radius"))+0.03:
				a.add_collision_exception_with(b)
				b.add_collision_exception_with(a)

func kill(point: Vector3, impulse: Vector3, bone: int) -> void:
	if dead: return
	dead=true
	_ragdolled=false
	simulator.influence=1.0
	health=0
	_rng.randomize()
	_blocker.collision_layer=0
	for area in hitboxes: area.collision_layer=0
	simulator.active=true
	simulator.physical_bones_start_simulation()
	# Nejprve přenést VŠECHNA tělesa do aktuální pózy, pak vytvořit kotvy.
	for id in bodies:
		bodies[id].global_transform=(skeleton.global_transform*bone_pose(id)*bodies[id].body_offset).orthonormalized()
	for id in bodies: _configure_joint(id,false)
	_add_overlap_exceptions()
	for id in bodies:
		var body: PhysicalBone3D=bodies[id]
		var gone:=false
		for cut in _severed:
			if id==cut or _is_descendant(id,cut): gone=true
		if gone:
			# Odstřelená část v ragdollu nepřekáží ani netáhne tělo.
			body.collision_layer=0
			body.collision_mask=0
			body.gravity_scale=0.0
			body.mass=0.05
		else:
			body.collision_layer=32
	_injured_bone=bone
	_style=_region(bone)
	_muscles.clear()
	for id in bodies:
		var parent:=_physical_parent(id)
		if parent>=0:
			_muscles.append({"bone":id,"parent":parent,"target":bodies[parent].global_basis.inverse()*bodies[id].global_basis})
	crowd.erase(self)
	# Tělo si nese rychlost, kterou zombie běžela.
	for id in bodies:
		var body: PhysicalBone3D=bodies[id]
		body.linear_velocity=_velocity+_knock+Vector3(_pose_velocity.get(id,Vector3.ZERO))*0.65
		body.angular_velocity=Vector3(_pose_spin.get(id,Vector3.ZERO))*0.65
	_pending_impacts.append([bone,point,impulse])
	if _style!="head":
		# Tělo dostane ve směru střely mírnou rychlost, hrudník víc než pánev: zvrátí se a složí.
		var flat:=Vector3(impulse.x,0,impulse.z)
		if flat.length()>0.01:
			var push:=flat.normalized()*clampf(flat.length()/26.0,0.12,0.8)
			if _style=="leg": push*=0.45
			push+=Vector3(-push.z,0,push.x)*_rng.randf_range(-0.12,0.12)
			for name in ["Hips","Spine","Spine2"]:
				var body: PhysicalBone3D=bodies[_ids[name]]
				_pending_impacts.append([_ids[name],body.global_position,push*body.mass*(1.3 if name=="Spine2" else 0.7)])
	if not _severed.has(_ids["Head"]): _say("zombie_death",-5.0)
	# Z rány po smrti ještě chvíli teče krev (slabý pulz dolů, ne tepenný proud).
	if fx and bodies.has(bone) and not _severed.has(bone): fx.spurt(self,bone,randf_range(1.2,2.2),0.35)
	died.emit(point,impulse,bone)

# Dopady mrtvého těla: pánev, hrudník, hlava a paže při prudkém zabrzdění o podlahu žuchnou.
const IMPACT_PARTS:={"Hips":[0.0,0.82],"Spine2":[-1.0,0.9],"Head":[-6.0,1.12],"LeftForeArm":[-9.0,1.2],"RightForeArm":[-9.0,1.2],"LeftLeg":[-8.0,1.0],"RightLeg":[-8.0,1.0]}
var _impact_prev:={}
var _impact_cool:={}
var _impact_count:=0

func _impact_sounds(dt: float) -> void:
	if sfx==null or _impact_count>=7 or _death_time>4.0: return
	for part in IMPACT_PARTS:
		var id: int=_ids.get(part,-1)
		if not bodies.has(id) or _severed.has(id): continue
		var body: PhysicalBone3D=bodies[id]
		var v: Vector3=body.linear_velocity
		var before: Vector3=_impact_prev.get(id,v)
		_impact_prev[id]=v
		_impact_cool[id]=maxf(0.0,float(_impact_cool.get(id,0.0))-dt)
		# Náraz = rychlost dolů se během jednoho kroku skoro celá ztratila.
		var fall:=-before.y
		if fall<1.3 or v.y<-fall*0.45 or _impact_cool[id]>0.0: continue
		_impact_cool[id]=0.35
		_impact_count+=1
		var at: Vector3=body.global_position
		var force:=clampf((fall-1.3)/3.5,0.0,1.0)
		var cfg: Array=IMPACT_PARTS[part]
		if at.y<_wl()+0.12:
			sfx.play_at("water_plop",Vector3(at.x,_wl(),at.z),-10.0+force*6.0+float(cfg[0])*0.5,randf_range(0.7,0.9))
			if splash.is_valid() and part in ["Hips","Spine2"]: splash.call(Vector3(at.x,_wl()+0.03,at.z),0.35+force*0.4)
		else:
			sfx.play_at("body_fall",at,-9.0+force*8.0+float(cfg[0]),float(cfg[1])*randf_range(0.9,1.08)*(0.88 if kind=="alpha" else 1.0))

func _sink() -> void:
	# Stará těla se propadnou do podlahy a zmizí, ať jich v hale nepřibývá donekonečna.
	if not is_inside_tree(): return
	process_mode=Node.PROCESS_MODE_INHERIT
	var tween:=create_tween()
	tween.tween_property(self,"position:y",position.y-1.1,3.0).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_SINE)
	tween.tween_callback(queue_free)

func _rotation_error(target: Basis, current: Basis) -> Vector3:
	var rotation: Quaternion=(target*current.inverse()).get_rotation_quaternion().normalized()
	if rotation.w<0: rotation=-rotation
	var vector:=Vector3(rotation.x,rotation.y,rotation.z)
	return vector.normalized()*2.0*atan2(vector.length(),rotation.w) if vector.length()>0.0001 else Vector3.ZERO

func _tone(id: int) -> float:
	# Zbytkové svalové napětí: nohy povolí první, trup a paže doznívají déle. Zásah hlavy = okamžitě nic.
	if _style=="head": return 0.0
	var region:=_region(id)
	var start:=0.0
	var length:=0.28
	if region=="torso": start=0.1; length=0.6
	elif region=="head": start=0.15; length=0.7
	elif region=="arm": start=0.05; length=0.7
	var tone:=1.0-smoothstep(start,start+length,_death_time)
	if _style=="leg" and region=="leg":
		var hurt: String=bodies[_injured_bone].get_meta("part_name")
		var part: String=bodies[id].get_meta("part_name")
		if hurt.left(4)==part.left(4): return 0.0
	if id==_injured_bone: tone*=0.2
	return tone

func _drive_muscles() -> void:
	if _resting: return
	var dt:=get_physics_process_delta_time()
	for muscle in _muscles:
		var body: PhysicalBone3D=bodies[muscle.bone]
		var parent: PhysicalBone3D=bodies[muscle.parent]
		var region:=_region(muscle.bone)
		var i_c: float=_inertia[muscle.bone]
		var i_p: float=_inertia[muscle.parent]
		var i_eff:=i_c*i_p/(i_c+i_p)
		var omega:=11.0 if region=="torso" else (9.0 if region=="leg" else 7.0)
		var k:=omega*omega*i_eff*_tone(muscle.bone)
		# Trvalé tření v kloubech dává tělu váhu: končetiny nelétají jako špagety.
		var friction:=(9.0 if region=="torso" else (7.0 if region=="head" else 4.5))*i_eff
		var c:=2.0*sqrt(k*i_eff)+friction
		var denom:=1.0+(k*dt*dt+c*dt)/i_eff
		var error:=_rotation_error(parent.global_basis*muscle.target,body.global_basis)
		var velocity:=body.angular_velocity-parent.angular_velocity
		var torque:=((error*k-velocity*(k*dt+c))/denom).limit_length(120.0 if region in ["torso","leg"] else 40.0)
		PhysicsServer3D.body_apply_torque(body.get_rid(),torque)
		PhysicsServer3D.body_apply_torque(parent.get_rid(),-torque)
	if _death_time<1.5: return
	# Pojistka: tělo, které se na nerovnosti chvěje, se po 7 s zapeče tak jako tak.
	if _death_time>7.0:
		_resting=true
		_freeze()
		return
	var moving:=false
	for body in bodies.values():
		if body.linear_velocity.length()>0.1 or body.angular_velocity.length()>0.5:
			moving=true
			break
	_rest_timer=0.0 if moving else _rest_timer+dt
	if _rest_timer>0.5:
		_resting=true
		_freeze()

func _freeze() -> void:
	# Ležící tělo se zapeče do kostry a fyzika se vypne: mrtvoly pak nestojí žádný výkon.
	# Pózu určují fyzikální tělesa; kosti bez tělesa (prsty, klíční kosti) si nechají svůj úhel k rodiči.
	var poses:=[]
	var inverse:=skeleton.global_transform.affine_inverse()
	for bone in skeleton.get_bone_count():
		var parent:=skeleton.get_bone_parent(bone)
		if bodies.has(bone): poses.append((inverse*bodies[bone].global_transform*bodies[bone].body_offset.affine_inverse()).orthonormalized())
		elif parent>=0: poses.append(poses[parent]*skeleton.get_bone_pose(bone))
		else: poses.append(skeleton.get_bone_pose(bone))
	simulator.physical_bones_stop_simulation()
	simulator.active=false
	for bone in skeleton.get_bone_count():
		var parent:=skeleton.get_bone_parent(bone)
		var local: Transform3D=poses[parent].affine_inverse()*poses[bone] if parent>=0 else poses[bone]
		skeleton.set_bone_pose_position(bone,local.origin)
		skeleton.set_bone_pose_rotation(bone,local.basis.get_rotation_quaternion())
	for body in bodies.values():
		body.collision_layer=0
		body.collision_mask=0
	# Odstřelené části zůstanou smrštěné napořád; úprava pózy už není potřeba.
	for cut in _severed: skeleton.set_bone_pose_scale(cut,Vector3(0.001,0.001,0.001))
	_gib.active=false
	_frozen=true
	set_physics_process(false)
	# Zapečená mrtvola nepotřebuje žádné zpracování (kostra, animace, modifikátory) – jen se kreslí.
	process_mode=Node.PROCESS_MODE_DISABLED
	if not keep_corpse: get_tree().create_timer(CORPSE_TIME).timeout.connect(_sink)

func _configure_joint(bone: int, update_frame: bool=true) -> void:
	var body: PhysicalBone3D=bodies[bone]
	var part: String=body.get_meta("part_name")
	body.joint_type=PhysicalBone3D.JOINT_TYPE_NONE
	if part=="Hips": return
	var frame:=body.body_offset.affine_inverse()
	frame.basis=body.body_offset.basis.inverse()*Basis(Vector3.FORWARD,PI/2)
	if part in ["Spine","Spine2"]:
		if update_frame: body.joint_offset=frame
		body.joint_type=PhysicalBone3D.JOINT_TYPE_CONE
		body.set("joint_constraints/swing_span",14.0)
		body.set("joint_constraints/twist_span",9.0)
	elif part in ["LeftLeg","RightLeg","LeftForeArm","RightForeArm"]:
		var is_leg:=part.ends_with("Leg")
		var side: String="Left" if part.begins_with("Left") else "Right"
		var parent:=skeleton.find_bone("mixamorig_"+side+("UpLeg" if is_leg else "Arm"))
		var child:=skeleton.find_bone("mixamorig_"+side+("Foot" if is_leg else "Hand"))
		var pose_now:=skeleton.global_transform*bone_pose(bone)
		var from: Vector3=(pose_now.origin-(skeleton.global_transform*bone_pose(parent)).origin).normalized()
		var to: Vector3=((skeleton.global_transform*bone_pose(child)).origin-pose_now.origin).normalized()
		var axis_world: Vector3=skeleton.global_basis.x if is_leg else from.cross(to).normalized()
		if axis_world.length()<0.5: axis_world=skeleton.global_basis.z
		var axis_local: Vector3=pose_now.basis.inverse()*axis_world
		frame.basis=body.body_offset.basis.inverse()*Basis(Quaternion(Vector3.BACK,axis_local.normalized()))
		if update_frame: body.joint_offset=frame
		body.joint_type=PhysicalBone3D.JOINT_TYPE_HINGE
		var flex:=rad_to_deg(acos(clampf(from.dot(to),-1,1)))
		body.set("joint_constraints/angular_limit_enabled",true)
		# Kladný směr pantu je natažení: ohyb (pata dozadu, předloktí k rameni) leží v záporu.
		body.set("joint_constraints/angular_limit_lower",-((118.0 if is_leg else 132.0)-flex))
		body.set("joint_constraints/angular_limit_upper",flex-(3.0 if is_leg else 8.0))
	else:
		# Cone-twist otáčí kolem osy X; ta musí vést podél dlouhé osy končetiny.
		frame.basis=body.body_offset.basis.inverse()*Basis(Vector3.FORWARD,PI/2)
		if update_frame: body.joint_offset=frame
		body.joint_type=PhysicalBone3D.JOINT_TYPE_CONE
		var swing:=50.0
		var twist:=22.0
		if part in ["Head","Neck"]: swing=22.0; twist=25.0
		elif part.ends_with("Hand"): swing=25.0; twist=12.0
		elif part.ends_with("Foot"): swing=22.0; twist=10.0
		elif part.ends_with("UpLeg"): swing=42.0; twist=18.0
		elif part.ends_with("Arm"): swing=70.0; twist=30.0
		body.set("joint_constraints/swing_span",swing)
		body.set("joint_constraints/twist_span",twist)
