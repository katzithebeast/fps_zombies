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
	if _scaled_anims.has(hips): return _scaled_anims[hips]
	# Klipy z Mixama + vstávání ze země (bake_getup.gd); u dítěte se zmenší poloha pánve.
	var lib:=AnimationLibrary.new()
	for source: AnimationLibrary in [ANIMS,GETUP]:
		for name in source.get_animation_list():
			var a: Animation=source.get_animation(name)
			if hips!=1.0:
				a=a.duplicate(true)
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
const GETUP:=preload("res://assets/zombie/getup_anims.res")
const RISE_BLEND:=0.4            # jak dlouho se ležící ragdoll prolíná do první pózy vstávání (s)
## Zrcadlené varianty klipů (<klip>_m, tools/build_zombie.gd): každá zombie chodí trochu jinak.
const MIRRORED:=["idle","walk","run","scream"]
## Útoky: klipy (náhodně jeden), rychlost, úsek klipu [od, do], zásahy [čas v klipu, násobek poškození],
## dosah, odkud se útok spustí, a dosah, na který ještě zraní. Chycení: výskok, chytí za ramena, kousne do krku.
const ATTACKS:={
	"swipe":{"anims":["attack","attack_m"],"speed":1.5,"from":0.0,"end":1.65,"hits":[[1.05,1.0]],"hit_range":1.9},
	"grab":{"anims":["neck_bite","neck_bite_m"],"speed":1.3,"from":0.2,"end":3.45,"hits":[[1.0,0.45],[1.95,0.85]],"hit_range":1.65,"in_clip":true},
}
## Smrt animací, pak fyzika: postava se skácí sama a těsně před pádem ji převezme ragdoll.
## dying = podlomí se kolena a padá na obličej, death = trhne sebou dozadu a padá na záda.
const DEATHS:={"dying":{"anims":["dying","dying_m"],"hand":1.95,"speed":1.1,"space":Vector3(0,0,1.1)},
	"death":{"anims":["death"],"hand":1.45,"speed":1.15,"space":Vector3(0,0,-1.3)}}
## Stabilita: rány ji ubírají (nohy nejvíc), sama se rychle vrací. Silná rána nebo série ran
## zombii rozhodí (dva vrávoravé kroky), když stabilita dojde, spadne a zase se zvedne.
const POISE_MAX:=85.0
const POISE_HIT:={"head":1.2,"torso":0.95,"leg":1.9,"arm":0.45}
const POISE_REGEN:=38.0
static var knockdowns:=true          # pády po zásahu (testy je mohou vypnout)
## Fyzikální zásah: horní polovina těla se na chvíli stane ragdollem, který svaly táhnou zpátky
## do animace. Rána tak působí stejnou fyzikou jako pád a přechod do ragdollu nebo zpět nemá švy.
static var hit_physics:=true
const HITRAG_TIME:=0.7
const HITRAG_FADE:=0.22
## Rychlost, jakou rána nejvýš udělí části těla (m/s): kulka hne trupem, paží víc, ale nikdy ne
## tak, aby se předloktí přetočilo za jeden snímek.
const HIT_VMAX:={"torso":4.2,"head":5.6,"arm":5.2,"hand":5.2}
## Jak moc rána tělem cloumá (násobek impulzu střely). Zombie mají být těžké, ale každý zásah
## musí být vidět: trup se zlomí, hlava cukne, paže odletí, krok se zadrhne.
const HIT_PUNCH:=2.7
const HITRAG_SPAN:={"Head":[50.0,35.0],"Neck":[30.0,25.0],"Spine":[50.0,28.0],"Spine2":[50.0,28.0],
	"LeftArm":[75.0,35.0],"RightArm":[75.0,35.0],"LeftHand":[30.0,15.0],"RightHand":[30.0,15.0]}
## Stupně reakce podle síly rány v jednom snímku (poškození na střelu / 50 × síla, broky se sčítají):
## lehká (MP40, broky z dálky) jen škubne, střední (AK) zbrzdí krok, těžká (Deagle, brokovnice
## zblízka, úder) rozhodí nebo srazí.
const TIER_MEDIUM:=0.9
const TIER_HEAVY:=1.8
const RISE_POSE:=0.4                 # vstávání: ležící tělo se nejdřív fyzikálně srovná do první pózy klipu
static var death_anims:=true         # smrt animací před ragdollem
const GibScript:=preload("res://scripts/zombie_gib.gd")
const MULTIPLIER:={"head":4.0,"torso":1.0,"arm":0.6,"leg":0.75}
const TRANSFER:={"head":0.6,"torso":1.0,"arm":0.65,"leg":0.8}
const SPEEDS:={"walk":0.75,"jog":2.1,"sprint":3.1}
const DEEP:=0.8                  # od této hloubky zombie plave
const SWIM_LEVEL:=0.35           # jak hluboko pod hladinou je při plavání kořen postavy
const CORPSE_TIME:=14.0
static var crowd: Array=[]
static var corpses: Array=[]          # mrtvá těla (výbuch s nimi pohne)
static var wall_guard:=true           # části těla se při animacích nedostanou do zdí
# Body těla hlídané proti zdem: [těleso, konec kapsle (-1 začátek, 0 střed, 1 konec), poloměr, kdo opraví]
const WALL_PROBES:=[["Head",0,0.11,"body"],["Head",1,0.105,"body"],["Spine2",0,0.15,"body"],["Hips",0,0.14,"body"],
	["LeftLeg",-1,0.07,"body"],["RightLeg",-1,0.07,"body"],["LeftFoot",1,0.065,"body"],["RightFoot",1,0.065,"body"],
	["LeftForeArm",-1,0.06,"Left"],["RightForeArm",-1,0.06,"Right"],["LeftHand",1,0.05,"Left"],["RightHand",1,0.05,"Right"]]
const WATER_LIFT:=0.55                # vztlak mrtvého těla (podíl tíhy), tělo pod hladinou klesá pomalu
const WATER_DRAG:=3.5                 # odpor vody (1/s)
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
var _rise_clip:=""               # getup_front / getup_back; prázdné = jen prolnutí do idle (plazivec)
var _rise_len:=0.0
var _rise_speed:=1.0             # každá zombie vstává trochu jinak rychle, dav se nesynchronizuje
var _mirror:=false                # zrcadlová chůze / postoj
var _atk:={}                      # právě běžící útok (ATTACKS)
var _atk_hit_i:=0
var _poise:=POISE_MAX
var _poise_max:=POISE_MAX
var _poise_t:=0.0
var _knocked:=false               # leží po zásahu (ragdoll se svaly), pak vstane
var _stagger_clip:=""             # vrávorání po zásahu (klip s posunem kořene)
var _stagger_t:=0.0
var _stagger_rm:=PackedVector3Array()
var _stagger_fps:=30.0
var _stagger_len:=0.0
var _stagger_cool:=0.0
var _death_anim:=""               # smrt animací (DEATHS), "" = rovnou ragdoll
var _death_t:=0.0
var _death_args:=[]
var force_attack:=""              # ladění: vždy tento útok (swipe / grab)
var force_death:=""               # ladění: vždy tato smrt animací (dying / death)
var _hitrag_on:=false             # běží fyzikální zásah (část těla simulovaná)
var _hitrag_t:=0.0
var _hitrag_fade:=-1.0
var _hitrag_ids:=[]               # simulovaná tělesa (trup, hlava, paže)
var _hitrag_slack:={}             # těleso -> čas povolení (zasažené místo krátce povolí)
var _anim_prev:={}                # minulý cíl tělesa (rychlost animace pro tlumení)
var _anim_prev_pos:={}
var _pending_hits:=[]
var _hitrag_want:=false
var _jolts:=[]                    # rány do celého těla: pánev odhozená a natočená, doznívá pružinou
var _spine_bone:=-1
var _pushes:=[]                   # rozložené rány do fyzikálních těles: [id, impulz, bod, rotační impulz, krok]
var _spin_v:=0.0                  # natočení celé zombie po ráně do ramene / boku (rad/s)
var _hitrag_heavy:=0.0
var _knock_want:=[]
var _hitrag_fade_len:=HITRAG_FADE
var _pending_spin:=[]
var _frame_force:=0.0             # síla ran v tomto snímku (rozhoduje o stupni reakce)
var _hitch:=0.0                   # zbrzdění chůze po ráně (0..1)
var _kill_push:=Vector3.ZERO      # součet ran v posledním snímku (o smrti rozhoduje i brokovnice jako celek)
var _push_frame:=-1
var feeding:=false                # krmí se u těla (bite2), vyruší ho hráč nablízku, výstřel nebo zásah
var _feed_rise_t:=0.0
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
const REACT_GAIN:=1.75       # celková síla škubnutí při zásahu
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
	_mirror=randf()<0.5
	_poise_max=POISE_MAX*sqrt(maxf(max_health,50.0)/100.0)
	_poise=_poise_max
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
	corpses.erase(self)

func _play(clip: String, speed: float) -> void:
	_clip_speed=speed
	if _clip==clip: return
	_clip=clip
	var blend:=0.12 if clip.contains("attack") else (0.22 if clip.contains("crawl") else 0.28)
	_animation.play("z/"+(clip+"_m" if _mirror and clip in MIRRORED else clip),blend)

func _say(group: String, volume: float) -> void:
	if sfx: sfx.play_at(group,global_position+Vector3.UP*(0.4 if _is_low() else 1.7),volume,_pitch)

func _wl() -> float:
	return float(water_at.call(global_position)) if water_at.is_valid() else water_level

func _is_low() -> bool:
	return crawling or swimming or _low or feeding

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
	if dead and _death_anim!="":
		_update_death_anim(dt)
		return
	if dead:
		for impact in _pending_impacts:
			var body: PhysicalBone3D=bodies.get(impact[0])
			if body:
				body.apply_impulse(impact[2],(impact[1]-body.global_position).limit_length(0.4))
		_pending_impacts.clear()
		_death_time+=dt
		_water_forces()
		_drive_muscles()
		_impact_sounds(dt)
		return
	if _ragdolled:
		_jolts.clear()
		_spin_v=0.0
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
	_update_jolts(dt)
	if wall_guard: _keep_out_of_walls()
	if not _knock_want.is_empty():
		var kw: Array=_knock_want
		_knock_want=[]
		if _hitrag_want: _hitrag_activate()
		_knockdown(kw[0],kw[1],kw[2],kw[3])
		return
	if _hitrag_want: _hitrag_activate()
	if _hitrag_on: _update_hitrag(dt)
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
	# Zeď, od které ochrana právě odtlačila tělo: do ní se nejde (jinak se o ni zombie klepe).
	if _wall_hold>0.0 and step.dot(-_wall_n)>0.0: step-=-_wall_n*step.dot(-_wall_n)
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
	_hitrag_take_over()
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
	_pull_bodies_out_of_walls()
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
		for impact in _pending_impacts:
			var body: PhysicalBone3D=bodies.get(impact[0])
			if body: body.apply_impulse(impact[2],(impact[1]-body.global_position).limit_length(0.4))
		_pending_impacts.clear()
		if _knocked: _drive_muscles(true)
		_water_forces()
		var settled:=_rag_t>(1.0 if _knocked else 1.3) and hips.linear_velocity.length()<0.5
		if settled or _rag_t>4.0:
			_begin_rise(hips)
		elif _rag_t>0.15 and hips.global_position.y<_wl()+0.6 and not get_meta("splashed",false):
			set_meta("splashed",true)
			var spot:=Vector3(hips.global_position.x,_wl()+0.03,hips.global_position.z)
			if splash.is_valid(): splash.call(spot,0.8)
			if sim: sim.add_impulse(Vector2(spot.x,spot.z),0.6,-1.6)
			if sfx: sfx.play_at("splash_big",spot,-5.0,0.9)
		return
	if _rise_clip!="":
		# Vstávání: 1) animace stojí na prvním snímku a svaly ležící tělo fyzikálně (po zemi, bez
		# průniků) srovnají do jeho pózy, 2) klip se rozjede a fyzika ho ještě chvíli sleduje,
		# zatímco se prolíná pryč. Ragdoll a animace tak nikdy nemorfují skrz sebe.
		var t_anim:=_rag_t-RISE_POSE
		if simulator.active:
			_drive_to_anim(bodies.keys(),clampf(_rag_t/0.15,0.0,1.0),dt)
			var kr:=clampf(t_anim/RISE_BLEND,0.0,1.0)
			simulator.influence=1.0-smoothstep(0.0,1.0,kr)
			if kr>=1.0: _rag_bodies_off()
		if t_anim<=0.0: return
		_animation.advance(dt*_rise_speed)
		if not simulator.active: _update_reactions(dt)
		if t_anim*_rise_speed>=_rise_len-0.01:
			_rise_clip=""
			_blocker.collision_layer=128
			_ragdolled=false
			_stagger=0.25
			set_meta("splashed",false)
			_play("idle",1.0)
		return
	# Zvedání: ragdoll póza plynule přechází do animace.
	var k:=clampf((_rag_t)/1.1,0.0,1.0)
	simulator.influence=1.0-smoothstep(0.0,1.0,k)
	_animation.advance(dt)
	if k>=1.0:
		_rag_bodies_off()
		_blocker.collision_layer=128
		_ragdolled=false
		_stagger=0.4
		set_meta("splashed",false)

func _rag_bodies_off() -> void:
	simulator.physical_bones_stop_simulation()
	simulator.active=false
	simulator.influence=1.0
	for body in bodies.values():
		body.collision_layer=0
		body.linear_damp=0.03
		body.angular_damp=0.25

func _rag_bone(name: String) -> Vector3:
	# Poloha kosti podle ležícího tělesa ragdollu.
	var body: PhysicalBone3D=bodies[_ids[name]]
	return (body.global_transform*body.body_offset.affine_inverse()).origin

func _begin_rise(hips: PhysicalBone3D) -> void:
	_rag_rise=true
	_rag_t=0.0
	_rise_clip=""
	var knocked:=_knocked
	_knocked=false
	# Kořen postavy přesunout pod pánev a natočit podle těla; tělesa zůstanou, kde leží.
	var keep:={}
	for id in bodies: keep[id]=bodies[id].global_transform
	var at:=hips.global_position
	var ground:=_ray(at+Vector3.UP*0.5,at+Vector3.DOWN*4.0)
	var floor_y: float=ground.position.y if not ground.is_empty() else global_position.y
	var parts_ok:=true
	for n in ["Hips","Head","LeftArm","RightArm"]:
		if not _ids.has(n) or not bodies.has(_ids[n]): parts_ok=false
	if parts_ok and not crawling and floor_y>_wl()-DEEP:
		# Leží na břiše, nebo na zádech? Osa ramen × páteř = kam míří hrudník.
		var spine:=_rag_bone("Head")-_rag_bone("Hips")
		var chest:=(_rag_bone("LeftArm")-_rag_bone("RightArm")).cross(spine)
		_rise_clip="getup_front" if chest.y<0.0 else "getup_back"
		if _mirror and _animation.has_animation("z/"+_rise_clip+"_m"): _rise_clip+="_m"
		# Klip leží podél osy Z: na břiše hlavou dopředu, na zádech nohama dopředu.
		var along:=Vector3(spine.x,0.0,spine.z)*(1.0 if _rise_clip.begins_with("getup_front") else -1.0)
		if along.length()>0.05: rotation.y=atan2(along.x,along.z)
		global_position=Vector3(at.x,floor_y,at.z)
		var anim:=_animation.get_animation("z/"+_rise_clip)
		var track:=anim.find_track(NodePath("Skeleton3D:mixamorig_Hips"),Animation.TYPE_POSITION_3D)
		# Pánev v prvním snímku klipu přesně tam, kde leží pánev ragdollu.
		var hip0: Vector3=skeleton.global_transform*(anim.track_get_key_value(track,0) as Vector3)
		var shift:=_rag_bone("Hips")-hip0
		global_position+=Vector3(shift.x,0.0,shift.z)
		_rise_len=anim.length
		_rise_speed=randf_range(0.88,1.15)*(0.85 if kind=="alpha" else 1.0)*(1.15 if knocked else 1.0)
		_clip=_rise_clip
		_clip_speed=1.0
		_animation.play("z/"+_rise_clip,0.0)
		_animation.seek(0.0,true)
	else:
		var forward:=hips.global_basis.z
		forward.y=0
		global_position=Vector3(at.x,floor_y,at.z)
		if forward.length()>0.1: rotation.y=atan2(forward.x,forward.z)
		if crawling:
			# bez nohy: z ležení rovnou do plazení
			_play("crawl",0.35)
	_anim_prev.clear()
	for id in bodies:
		bodies[id].global_transform=keep[id]
		bodies[id].linear_velocity=Vector3.ZERO
		bodies[id].angular_velocity=Vector3.ZERO
		# s klipem se tělo srovnává svaly (malé tlumení), plazivec jen prolnutím (velké)
		bodies[id].linear_damp=2.5 if _rise_clip!="" else 8.0
		bodies[id].angular_damp=2.0 if _rise_clip!="" else 8.0
		# omezení kloubů z pózy pádu by nedovolila pokrčit kolena do výchozí pózy vstávání
		if _rise_clip!="" and bodies[id].joint_type!=PhysicalBone3D.JOINT_TYPE_NONE: bodies[id].joint_type=PhysicalBone3D.JOINT_TYPE_PIN
	if _rise_clip=="" and not crawling: _play("idle",1.0)

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
	_yaw_prev=rotation.y
	_wall_hold=maxf(0.0,_wall_hold-dt)
	_velocity=Vector3.ZERO
	_stagger=maxf(0.0,_stagger-dt)
	# zbrzdění kroku po ráně: plynule dolů i nahoru (žádné zaškobrtnutí animace)
	_hitch=move_toward(_hitch,0.0,dt*1.1)
	_gait_factor=lerpf(_gait_factor,1.0-_hitch,1.0-exp(-9.0*dt))
	if _knock.length()>0.03:
		_move(_knock*dt)
		_knock*=exp(-9.0*dt)
	_poise_t+=dt
	_stagger_cool=maxf(0.0,_stagger_cool-dt)
	if absf(_spin_v)>0.01:
		rotation.y+=_spin_v*dt
		_spin_v*=exp(-5.5*dt)
	if _poise_t>0.6: _poise=minf(_poise_max,_poise+POISE_REGEN*dt)
	if _stagger_clip!="":
		_update_stagger(dt)
		return
	if feeding or _feed_rise_t>0.0:
		_update_feeding(dt)
		return
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
		# těžké tělo: otáčí se líně, po zásahu ještě líněji (dokud se nevzpamatuje)
		rotation.y=lerp_angle(rotation.y,atan2(aim.x,aim.z),1.0-exp(-(3.0 if low else 5.5)*(1.0-0.65*_hitch)*dt))
	var forward:=Basis(Vector3.UP,rotation.y)*Vector3.BACK
	if _scream_left>0.0:
		_scream_left-=dt
		_move(Vector3.ZERO)
		return
	if _attack_left>0.0:
		_attack_left-=dt
		_attack_time+=dt
		# Výpad: běžící zombie se do úderu vrhne a setrvačnost doběhne až k ráně (nezastaví se jako socha).
		# Chycení má výskok v samotném klipu, kořen se nehýbe.
		var hits: Array=_atk.hits
		var hit_t:=(float(hits[0][0])-float(_atk.from))/float(_atk.speed)
		var lunge:=maxf(0.6,_lunge*(1.0-_attack_time/hit_t))
		if _attack_time<hit_t and distance>0.8 and not _atk.get("in_clip",false): _move(forward*lunge*dt)
		else: _move(Vector3.ZERO)
		if _atk_hit_i<hits.size():
			var h: Array=hits[_atk_hit_i]
			if _attack_time>=(float(h[0])-float(_atk.from))/float(_atk.speed):
				_atk_hit_i+=1
				_attack_hit=true
				if distance<float(_atk.hit_range) and height<1.5 and to.normalized().dot(forward)>0.3 and not _lured(): attacked.emit(attack_damage*float(h[1]))
			elif _atk_hit_i==0 and distance>2.8: _attack_left=0.0      # cíl utekl z dosahu: nedokončovat úder do prázdna
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
			_start_attack(distance)
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
	# součet ran v tomto snímku (broky brokovnice přijdou naráz)
	var frame_now:=Engine.get_physics_frames()
	if frame_now!=_push_frame:
		_push_frame=frame_now
		_kill_push=Vector3.ZERO
		_frame_force=0.0
	_kill_push+=impulse
	_frame_force+=damage/50.0*strength*(1.6 if flat else 1.0)
	if dead:
		if _death_anim!="":
			# skácí se: další rána ho převezme do fyziky hned, ve směru střely
			_death_handoff(point,impulse,bone)
			return
		if _frozen and not _unfreeze(): return
		_wake()
		_pending_impacts.append([bone,point,impulse])
		return
	if _death_pending: return      # další broky v tomtéž okamžiku jsou už v _kill_push
	if feeding: _feed_rise()
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
	var limit:=maxf(70.0,max_health*0.55)
	var lost_leg:=region=="leg" and float(_limb_damage[limb])>=limit and not crawling
	# Stabilita: kolik rána zombii rozhodí. V běhu zakopne snáz, alfa skoro vůbec.
	var pd:=amount*float(POISE_HIT[region])*weapon_energy*react_mult
	if flat: pd=maxf(pd,60.0*react_mult)
	pd*=1.0+0.5*clampf(_velocity.length()/2.5,0.0,1.0)
	if lost_leg:
		_sever(side+"Leg",direction)
		# Bez nohy jde k zemi (pád) a plazí se dál.
		crawling=true
		_attack_left=0.0
		_scream_left=0.0
		_stagger=0.6
	if _ragdolled:
		_hit_while_down(bone,point,impulse,pd)
		_react(bone,point,direction,strength*clampf(amount/40.0,0.85,1.8),region)
	elif not _knock_want.is_empty():
		# pád už je naplánovaný na tento snímek: další broky půjdou rovnou do padajícího těla
		_pending_impacts.append([bone,point,impulse])
	elif (lost_leg and _drop.is_zero_approx() and not swimming and _emerge<=0.0) or (knockdowns and _poise-pd<=0.0 and _can_fall()):
		_poise=_poise_max*0.7
		_poise_t=0.0
		# pád se spustí v příštím fyzikálním kroku zombie hned po animaci (žádný zamrzlý snímek)
		_knock_want=[bone,point,impulse,region]
		_attack_left=0.0
	else:
		_poise-=pd
		_poise_t=0.0
		# Síla škubnutí podle skutečné rány: Deagle a brokovnice trhnou víc než samopal.
		var physical:=hit_physics and region!="leg" and _hitrag_ok()
		_react(bone,point,direction,strength*clampf(amount/40.0,0.85,1.8),region,not physical)
		# fyzikální rána úměrná síle střely (MP40 < AK < Deagle; broky se sečtou v tělese)
		if physical: _hitrag_hit(bone,point,direction*14.0*clampf(damage/50.0*strength,0.2,3.0)*float(TRANSFER[region])*HIT_PUNCH*react_mult,region)
		if flat:
			_stagger=0.7
			_knock+=Vector3(direction.x,0,direction.z)*2.6
		var heavy:=_frame_force>=TIER_HEAVY and region!="leg"
		var medium:=_frame_force>=TIER_MEDIUM and region in ["torso","head"]
		# Celé tělo: pánev rána odhodí (kroky se zadrhnou), rána do ramene / boku zombii pootočí.
		if _hitrag_ok(): _jolt(direction,point,region)
		if _can_fall() and _stagger_clip=="" and _stagger_cool<=0.0:
			if heavy or _poise<_poise_max*0.4: _start_stagger(direction)
			# střední rána (AK do těla / hlavy): jeden vrávoravý krok, pak hned zase za kořistí
			elif medium and randf()<0.7: _start_stagger(direction,0.46)
	if not lost_leg and region=="arm" and float(_limb_damage[limb])>=limit:
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

func _react(bone: int, point: Vector3, direction: Vector3, strength: float, region: String, procedural:=true) -> void:
	var local_direction: Vector3=global_basis.inverse()*direction
	var local_point: Vector3=global_transform.affine_inverse()*point
	# Moment zásahu kolem svislé osy: rána do ramene tělo stočí, rána do středu jen prohne.
	var twist:=clampf((local_point.z*local_direction.x-local_point.x*local_direction.z)*4.0,-1.0,1.0)
	var part: String=bodies[bone].get_meta("part_name") if bodies.has(bone) else ""
	# Zásah do ramene/nadloktí: výrazná rotace trupu; rameno odhodí ve směru střely.
	var upper:=part.ends_with("Arm") and not part.ends_with("ForeArm")
	var side_sign:=1.0 if part.begins_with("Left") else -1.0
	if upper: twist=clampf(twist*1.6+side_sign*signf(local_direction.z)*0.6,-1.2,1.2)
	if procedural:
		_reactions.append({"bone":bone,"direction":local_direction,"twist":twist,"region":region,"strength":minf(strength,2.0)*react_mult,"age":0.0,"upper":upper,"part":part})
		if _reactions.size()>6: _reactions.pop_front()
	# Stupeň rány: lehká jen škubne, střední zbrzdí krok, těžká zastaví. Posun kořene je malý
	# (kořen ujíždí bez kroků = kloužou chodidla), velký posun dělá až vrávorání s kroky.
	var tier:=clampf((_frame_force-0.3)/(TIER_HEAVY-0.3),0.0,1.0)
	_stagger=maxf(_stagger,float({"head":0.5,"torso":0.3,"leg":0.42,"arm":0.16}[region])*lerpf(0.35,1.0,tier))
	_hitch=maxf(_hitch,lerpf(0.4,0.9,tier)*(0.6 if region=="arm" else 1.0))
	# Zásah do těla nebo hlavy přeruší rozmáchnutí, jen když je rána aspoň střední.
	if _attack_left>0.0 and not _attack_hit and region!="arm" and _frame_force>=TIER_MEDIUM: _attack_left=0.0
	_knock+=Vector3(direction.x,0,direction.z)*float({"head":1.2,"torso":1.7,"leg":0.8,"arm":0.5}[region])*minf(strength,1.0)*react_mult*lerpf(0.15,0.6,tier)*(0.3 if _stagger_clip!="" else 1.0)
	# nervové škubnutí: náhodné osy pro paže a hlavu, doznívá ~0,6 s
	if procedural: _reactions[-1]["spasm"]=[Vector3(randf_range(-1,1),randf_range(-1,1),randf_range(-1,1)).normalized(),Vector3(randf_range(-1,1),randf_range(-1,1),randf_range(-1,1)).normalized(),randf()*TAU]

## Výchylka tlumené pružiny po úderu (normovaná na vrchol 1): sin náběh, exp útlum.
static func _spring_env(age: float, omega: float, zeta: float) -> float:
	var wd:=omega*sqrt(1.0-zeta*zeta)
	var tp:=atan(wd/(zeta*omega))/wd
	var peak:=exp(-zeta*omega*tp)*sin(wd*tp)
	return exp(-zeta*omega*age)*sin(wd*age)/peak

## Rána do celého těla: pánev odletí ve směru střely a nakloní se, zombie se pootočí podle toho,
## jak daleko od osy těla rána přišla (rameno, bok). Síla podle stupně rány.
func _jolt(direction: Vector3, point: Vector3, region: String) -> void:
	var f:=clampf(_frame_force,0.2,3.0)
	var local: Vector3=global_basis.inverse()*direction
	local.y=0.0
	var amp:=f*float({"head":0.7,"torso":1.0,"arm":0.55,"leg":0.6}[region])*react_mult
	# broky jedné rány (a dávka ve stejném snímku) = jeden náraz, ne pět nad sebou
	var r: Vector3=point-global_position
	r.y=0.0
	# zásah mimo osu (rameno, bok) trup zkroutí; znaménko = na kterou stranu
	var twist:=clampf(r.cross(direction).y/0.25,-1.0,1.0)*(1.6 if region=="arm" else 1.0)
	if not _jolts.is_empty() and float(_jolts[-1].age)<=0.0:
		_jolts[-1].f=maxf(float(_jolts[-1].f),amp)
		_jolts[-1].dir=(Vector3(_jolts[-1].dir)+local.normalized()*0.3).normalized()
		_jolts[-1].tw=clampf(float(_jolts[-1].tw)+twist*0.3,-1.6,1.6)
	else:
		_jolts.append({"dir":local.normalized(),"f":amp,"tw":twist,"age":0.0})
	if _jolts.size()>4: _jolts.pop_front()
	# Celá zombie se pootočí jen při chůzi / stání (kroky to unesou); při vrávorání a útoku ne,
	# chodidla stojí na zemi a nesmí po ní klouzat.
	if _stagger_clip=="" and _attack_left<=0.0:
		_spin_v=clampf(_spin_v+clampf(r.cross(direction).y*f*(2.4 if region=="arm" else 1.3)*react_mult,-2.5,2.5),-2.0,2.0)

func _update_jolts(dt: float) -> void:
	if _jolts.is_empty(): return
	var tilt:=Vector3.ZERO
	for j in _jolts:
		j.age+=dt
		# krátký náběh (3–4 snímky): rána je prudká, ale tělo „neskočí“ o kus za jediný snímek
		var e:=_spring_env(float(j.age),8.0,0.5)*float(j.f)*smoothstep(0.0,0.07,float(j.age))
		var d: Vector3=j.dir
		tilt+=Vector3.UP.cross(d)*e*0.15+Vector3.UP*e*float(j.tw)*0.14
	_jolts=_jolts.filter(func(j): return j.age<1.2)
	# Celý trup od beder se zlomí ve směru rány a zkroutí (pánev a nohy stojí – chodidla neklouzou).
	if _spine_bone<0: _spine_bone=skeleton.find_bone("mixamorig_Spine")
	if tilt.length()>0.001: _rotate_bone(_spine_bone,tilt.normalized(),minf(tilt.length(),0.42))

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
		# Odezva tlumené pružiny na úder: plynulý (ne skokový) náběh, vrchol ~0,1 s, malý překmit
		# zpět a dozvuk. Zásahy se sčítají.
		var age: float=reaction.age
		var envelope: float=_spring_env(age,11.0,0.38)*float(reaction.strength)*REACT_GAIN
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
				var kick: float=_spring_env(age,13.0,0.42)*float(reaction.strength)*REACT_GAIN
				var buckle: float=_spring_env(age,8.0,0.62)*float(reaction.strength)*REACT_GAIN
				var limb: Vector3=(bone_pose(knee).origin-bone_pose(thigh).origin).normalized()
				_rotate_bone(thigh,limb.cross(direction),kick*(0.09 if calf_hit or foot_hit else 0.2))
				_rotate_bone(knee,Vector3.RIGHT,kick*(0.3 if calf_hit else 0.18 if foot_hit else 0.12)+buckle*(0.22 if calf_hit else 0.12))
				if foot_hit: _rotate_bone(foot,Vector3.RIGHT,kick*0.2)
				# Váha krátce přejde na zdravou nohu. Trup reaguje méně než samotná končetina.
				_rotate_bone(0,Vector3.FORWARD,envelope*(0.08 if side=="Left" else -0.08))
				_rotate_bone(spine,bend,-envelope*0.06)
				_rotate_bone(chest,Vector3.FORWARD,envelope*(-0.06 if side=="Left" else 0.06))
				# koleno podklesne: pánev klesne a stočí se ke zraněné noze
				skeleton.set_bone_pose_position(0,skeleton.get_bone_pose_position(0)-Vector3.UP*buckle*(0.085 if calf_hit else 0.05))
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
	# Škubnutí nervů: paže a hlava sebou po ráně ještě krátce cuknou (rychle tlumené kmity).
	for reaction in _reactions:
		var sp: Array=reaction.get("spasm",[])
		if sp.is_empty(): continue
		var age: float=reaction.age
		var amp:=exp(-age*6.5)*(1.0-exp(-age*30.0))*float(reaction.strength)*0.16
		if amp<0.004: continue
		var wob:=sin(age*29.0+float(sp[2]))
		for nm in ["LeftArm","RightArm","LeftForeArm","RightForeArm"]:
			if _ids.has(nm) and not _gone(_ids[nm]):
				_rotate_bone(_ids[nm],sp[0] if nm.begins_with("Left") else sp[1],amp*wob*(1.0 if nm.ends_with("ForeArm") else 0.7))
		_rotate_bone(head,sp[1],amp*sin(age*23.0+float(sp[2])*1.7)*0.8)
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
	var anim:=_pick_death(point,impulse,bone)
	_knock_want=[]
	dead=true
	health=0
	_rng.randomize()
	_blocker.collision_layer=0
	_stagger_clip=""
	feeding=false
	_feed_rise_t=0.0
	if anim!="":
		# Smrt animací: skácí se sám, těsně před pádem ho převezme fyzika (_death_handoff).
		var d: Dictionary=DEATHS[anim]
		var variants: Array=d.anims
		_death_anim=anim
		_death_t=0.0
		_death_args=[point,impulse,bone]
		_ragdolled=false
		_attack_left=0.0
		_scream_left=0.0
		crowd.erase(self)
		_clip=anim
		_clip_speed=float(d.speed)*randf_range(0.92,1.08)
		_animation.play("z/"+String(variants[1] if (_mirror and variants.size()>1) else variants[0]),0.12)
		_animation.seek(0.0,true)
		if not _severed.has(_ids["Head"]): _say("zombie_death",-5.0)
		if fx and bodies.has(bone) and not _severed.has(bone): fx.spurt(self,bone,randf_range(1.2,2.2),0.35)
		died.emit(point,impulse,bone)
		return
	_ragdoll_death(point,impulse,bone)
	if not _severed.has(_ids["Head"]): _say("zombie_death",-5.0)
	# Z rány po smrti ještě chvíli teče krev (slabý pulz dolů, ne tepenný proud).
	if fx and bodies.has(bone) and not _severed.has(bone): fx.spurt(self,bone,randf_range(1.2,2.2),0.35)
	died.emit(point,impulse,bone)

## Ragdoll mrtvého těla: tělesa do aktuální pózy, klouby, svaly, rychlost z animace a rána.
func _ragdoll_death(point: Vector3, impulse: Vector3, bone: int) -> void:
	_ragdolled=false
	_knocked=false
	_rag_rise=false
	_rise_clip=""
	var from_anim:=_death_anim!=""
	_death_anim=""
	var live:=_hitrag_take_over()
	simulator.influence=1.0
	for area in hitboxes: area.collision_layer=0
	simulator.active=true
	simulator.physical_bones_start_simulation()
	# Nejprve přenést VŠECHNA tělesa do aktuální pózy, pak vytvořit kotvy (už simulovaná nechat).
	for id in bodies:
		if not live.has(id): bodies[id].global_transform=_render_pose(id,live)
	for id in bodies: _configure_joint(id,false)
	_add_overlap_exceptions()
	_pull_bodies_out_of_walls()
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
		# Rychlé končetiny (brokovnice, výbuch) neprolétnou tenkou zdí.
		PhysicsServer3D.body_set_enable_continuous_collision_detection(body.get_rid(),true)
	_injured_bone=bone
	_style=_region(bone)
	_muscles.clear()
	for id in bodies:
		var parent:=_physical_parent(id)
		if parent>=0:
			_muscles.append({"bone":id,"parent":parent,"target":bodies[parent].global_basis.inverse()*bodies[id].global_basis})
	crowd.erase(self)
	if not corpses.has(self): corpses.append(self)
	# Tělo si nese rychlost, kterou zombie běžela (po smrti animací celou – padá dál stejně rychle).
	var carry:=1.0 if from_anim else 0.65
	for id in bodies:
		if live.has(id): continue
		var body: PhysicalBone3D=bodies[id]
		body.linear_velocity=_velocity+_knock+Vector3(_pose_velocity.get(id,Vector3.ZERO))*carry
		body.angular_velocity=Vector3(_pose_spin.get(id,Vector3.ZERO))*carry
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

## Která smrt: zásah do hlavy, silná zbraň zblízka, běh, voda nebo uříznutá končetina = rovnou fyzika
## (padne jako podťatá). Jinak se často skácí animací – přes kolena, nebo zásah zepředu dozadu.
func _pick_death(point: Vector3, impulse: Vector3, bone: int) -> String:
	if not death_anims or keep_corpse or _ragdolled or not _knock_want.is_empty() or _sleeping or feeding or _feed_rise_t>0.0: return ""
	if crawling or swimming or _is_low() or _emerge>0.0 or not _drop.is_zero_approx() or not _severed.is_empty(): return ""
	var region:=_region(bone)
	if region=="head" or maxf(impulse.length(),_kill_push.length())>17.0 or _velocity.length()>2.6 or (randf()>0.65 and force_death==""): return ""
	var local: Vector3=global_basis.inverse()*impulse.normalized()
	var pick:="death" if (region=="torso" and local.z<-0.45 and randf()<0.55) else "dying"
	if force_death!="": pick=force_death
	# na pád musí být místo, jinak by prošel zdí
	for name in [pick,"dying"]:
		var space: Vector3=DEATHS[name].space
		var from:=global_position+Vector3.UP*0.6
		if _ray(from,from+global_basis*space).is_empty(): return name
	return ""

func _update_death_anim(dt: float) -> void:
	_death_t+=dt*_clip_speed
	_animation.advance(dt*_clip_speed)
	_update_reactions(dt)
	if wall_guard: _keep_out_of_walls()
	if _hitrag_want: _hitrag_activate()
	if _hitrag_on: _update_hitrag(dt)
	_sample_pose_motion(dt)
	for area in hitboxes:
		if area.collision_layer!=0:
			area.global_transform=skeleton.global_transform*bone_pose(area.get_meta("bone"))*area.get_meta("offset")
	if _death_t>=float(DEATHS[_death_anim].hand):
		var args: Array=_death_args
		_death_handoff(args[0],(args[1] as Vector3)*0.12,args[2])

## Konec smrti animací: tělo převezme fyzika i s rychlostí, kterou mělo v animaci.
func _death_handoff(point: Vector3, impulse: Vector3, bone: int) -> void:
	if _death_anim=="": return
	_ragdoll_death(point,impulse,bone)
	if not corpses.has(self): corpses.append(self)

# ------------------------------------------------------------------ pád po zásahu, vrávorání

func _can_fall() -> bool:
	return not crawling and not swimming and not _ragdolled and _emerge<=0.0 and _drop.is_zero_approx() and not feeding and _feed_rise_t<=0.0 and not _sleeping

## Silná rána nebo došlá stabilita: zombie upadne jako hadrová panenka se zbytkem svalů
## (ruce se snaží zachytit, nohy se podlomí), pak vstane animací (_begin_rise).
func _knockdown(bone: int, point: Vector3, impulse: Vector3, region: String) -> void:
	_ragdolled=true
	_knocked=true
	_rag_t=0.0
	_rag_rise=false
	_rise_clip=""
	_stagger_clip=""
	_attack_left=0.0
	_scream_left=0.0
	_reactions.clear()
	_blocker.collision_layer=0
	var live:=_hitrag_take_over()
	simulator.influence=1.0
	simulator.active=true
	simulator.physical_bones_start_simulation()
	for id in bodies:
		if not live.has(id): bodies[id].global_transform=_render_pose(id,live)
	for id in bodies: _configure_joint(id,false)
	_add_overlap_exceptions()
	_pull_bodies_out_of_walls()
	for id in bodies:
		var body: PhysicalBone3D=bodies[id]
		body.collision_layer=0 if _gone(id) else 32
		body.linear_damp=0.05
		body.angular_damp=0.6
		if live.has(id): continue      # trup a paže už letí fyzikou: rychlost zůstane, žádný šev
		# nohy (animované) dostanou rychlost, kterou měly v animaci
		body.linear_velocity=_velocity+_knock*0.5+Vector3(_pose_velocity.get(id,Vector3.ZERO))
		body.angular_velocity=Vector3(_pose_spin.get(id,Vector3.ZERO))
	_knock=Vector3.ZERO
	_injured_bone=bone
	_muscles.clear()
	for id in bodies:
		var parent:=_physical_parent(id)
		if parent>=0:
			_muscles.append({"bone":id,"parent":parent,"target":bodies[parent].global_basis.inverse()*bodies[id].global_basis})
	_pending_impacts.append([bone,point,impulse*1.1])
	var flat:=Vector3(impulse.x,0,impulse.z).normalized()
	if region=="leg":
		# noha se podlomí: chodidlo ujede ve směru rány, trup jde dolů a dopředu (setrvačnost)
		var side:="Left" if String(bodies[bone].get_meta("part_name")).begins_with("Left") else "Right"
		var foot: int=_ids.get(side+"Foot",bone)
		if bodies.has(foot): _pending_impacts.append([foot,bodies[foot].global_position,flat*bodies[foot].mass*2.2])
		var chest: PhysicalBone3D=bodies[_ids["Spine2"]]
		var ahead:=global_basis.z*0.9+Vector3.DOWN*0.4
		_pending_impacts.append([_ids["Spine2"],chest.global_position,ahead*chest.mass])
	else:
		# trup odhodí ve směru střely, hlava se zvrátí
		for nm in ["Spine2","Head"]:
			var b: PhysicalBone3D=bodies.get(_ids.get(nm,-1))
			if b: _pending_impacts.append([_ids[nm],b.global_position,flat*b.mass*(1.4 if nm=="Spine2" else 0.8)])
	_say("zombie_attack",-6.0)

## Póza tělesa tak, jak je právě vidět: animovaná kost, ale vůči už simulované pánvi
## (nohy jsou při fyzikálním zásahu vykreslené od fyzikální pánve, ne od animované).
func _render_pose(id: int, live: Array) -> Transform3D:
	var body: PhysicalBone3D=bodies[id]
	var anim_g:=skeleton.global_transform*bone_pose(id)
	var hips: int=_ids.Hips
	if live.has(hips) and id!=hips and _is_descendant(id,hips):
		var hb: PhysicalBone3D=bodies[hips]
		var phys_hips:=hb.global_transform*hb.body_offset.affine_inverse()
		anim_g=phys_hips*(skeleton.global_transform*bone_pose(hips)).affine_inverse()*anim_g
	return (anim_g*body.body_offset).orthonormalized()

## Rána do ležící / vstávající zombie: ležící tělo jen postrčí, vstávající může znovu srazit.
func _hit_while_down(bone: int, point: Vector3, impulse: Vector3, pd: float) -> void:
	if simulator.active and not _rag_rise:
		var body: PhysicalBone3D=bodies.get(bone)
		if body: body.apply_impulse(impulse*0.7,(point-body.global_position).limit_length(0.4))
		_rag_t=minf(_rag_t,0.7)
	elif _rag_rise and _rise_clip!="" and knockdowns and pd>=24.0:
		_knockdown(bone,point,impulse,_region(bone))

## Vrávorání: rána zepředu = dva kroky vzad, z boku = úkrok stranou. Chodidla drží na zemi,
## kořen se posouvá podle "root_motion" klipu. Zásah do zad jen škubne a postrčí.
func _start_stagger(direction: Vector3, cut:=0.0) -> void:
	var local: Vector3=global_basis.inverse()*direction
	var clip:="stagger_back"
	if absf(local.x)>absf(local.z)*0.9: clip="stagger_left" if local.x>0.0 else "stagger_right"
	elif local.z>0.25: return
	if _mirror and _animation.has_animation("z/"+clip+"_m"): clip+="_m"
	var anim:=_animation.get_animation("z/"+clip)
	if anim==null or not anim.has_meta("root_motion"): return
	_stagger_clip=clip
	_stagger_t=0.0
	_stagger_rm=anim.get_meta("root_motion")
	_stagger_fps=float(anim.get_meta("root_fps"))
	_stagger_len=anim.length if cut<=0.0 else minf(cut,anim.length)
	_attack_left=0.0
	_scream_left=0.0
	_knock=Vector3.ZERO
	_clip=clip
	_clip_speed=randf_range(0.95,1.18)*(1.1 if cut>0.0 else 1.0)
	_animation.play("z/"+clip,0.15)
	_animation.seek(0.0,true)

func _root_at(t: float) -> Vector3:
	var f:=t*_stagger_fps
	var i:=clampi(int(f),0,_stagger_rm.size()-1)
	var j:=mini(i+1,_stagger_rm.size()-1)
	return _stagger_rm[i].lerp(_stagger_rm[j],clampf(f-float(i),0.0,1.0))

func _update_stagger(dt: float) -> void:
	var before:=_root_at(_stagger_t)
	_stagger_t+=dt*_clip_speed
	var step:=(_root_at(_stagger_t)-before)*float(TYPES.get(kind,TYPES.classic).get("hips",1.0))
	_velocity=global_basis*step/maxf(dt,0.0001)
	_move(global_basis*step)
	if _stagger_t>=_stagger_len-0.02:
		_stagger_clip=""
		_stagger_cool=0.35
		_clip=""      # další krok _think vybere chůzi / běh / idle s vlastním prolnutím

# ------------------------------------------------------------------ fyzikální zásah (aktivní ragdoll)

func _hitrag_ok() -> bool:
	return not _ragdolled and not swimming and not crawling and not feeding and _emerge<=0.0 and _drop.is_zero_approx() and not _sleeping

## Animační póza (bez fyziky) všech kostí v souřadnicích kostry: lokální pózy nastavuje animace,
## simulátor je nepřepisuje, takže skládáním přes rodiče dostaneme cíl pro svaly.
func _anim_globals() -> Array:
	var out:=[]
	out.resize(skeleton.get_bone_count())
	for b in skeleton.get_bone_count():
		var p:=skeleton.get_bone_parent(b)
		out[b]=(out[p] as Transform3D)*skeleton.get_bone_pose(b) if p>=0 else skeleton.get_bone_pose(b)
	return out

## Svaly táhnou tělesa k animaci (natočení ve světě, tlumení proti rychlosti animace).
## strength 1 = pevně drží animaci, 0 = volné. slack: tělesa, která právě povolila po ráně.
func _drive_to_anim(ids: Array, strength: float, dt: float, linear:=false) -> void:
	var G:=_anim_globals()
	var sb:=skeleton.global_basis.orthonormalized()
	for id in ids:
		var body: PhysicalBone3D=bodies[id]
		var target:=(sb*(G[id] as Transform3D).basis.orthonormalized()*body.body_offset.basis.orthonormalized()).orthonormalized()
		var target_pos: Vector3=(skeleton.global_transform*(G[id] as Transform3D)*body.body_offset).origin
		var w_anim:=Vector3.ZERO
		if _anim_prev.has(id): w_anim=(_rotation_error(target,_anim_prev[id])/maxf(dt,0.001)).limit_length(12.0)
		_anim_prev[id]=target
		var region:=_region(id)
		# trup drží pevně, hlava a paže volněji: po ráně se zhoupnou a doběhnou (setrvačnost)
		var pn:=String(body.get_meta("part_name"))
		# těžké tělo: svaly vracejí pomaleji, paže a hlava se houpou (setrvačnost)
		var omega:=12.0 if region=="torso" else (10.0 if region=="head" else (14.0 if pn.ends_with("Hand") else 9.5))
		var tone:=strength
		if _hitrag_slack.has(id):
			var sl: Array=_hitrag_slack[id]
			tone*=lerpf(float(sl[2]),1.0,smoothstep(0.04,float(sl[1]),_time-float(sl[0])))
		# PD na úrovni zrychlení (nezávislé na setrvačnosti, implicitní krok): stabilní i pro tenké
		# končetiny, které mají kolem dlouhé osy setrvačnost několikrát menší
		var st:=PhysicsServer3D.body_get_direct_state(body.get_rid())
		if st==null: continue
		var w:=omega*sqrt(maxf(tone,0.0))
		var c:=2.0*w+1.5
		var err:=_rotation_error(target,body.global_basis)
		var acc:=(err*w*w-(body.angular_velocity-w_anim)*(c+w*w*dt))/(1.0+c*dt+w*w*dt*dt)
		var torque:=(st.inverse_inertia_tensor.inverse()*acc).limit_length(260.0 if region=="torso" else 110.0)
		PhysicsServer3D.body_apply_torque(body.get_rid(),torque)
		if linear:
			# Poloha každého tělesa taky k animaci (jinak by řetěz trupu a paží při chůzi postupně
			# „odplaval“: svaly v kloubech neunesou setrvačnost celého řetězu za pánví).
			var v_anim:=Vector3.ZERO
			if _anim_prev_pos.has(id): v_anim=((target_pos-(_anim_prev_pos[id] as Vector3))/maxf(dt,0.001)).limit_length(8.0)
			_anim_prev_pos[id]=target_pos
			var wl:=omega*0.75*sqrt(maxf(tone,0.0))
			var cl:=2.0*wl+1.0
			var perr:=target_pos-body.global_position
			var lacc:=(perr*wl*wl-(body.linear_velocity-v_anim)*(cl+wl*wl*dt))/(1.0+cl*dt+wl*wl*dt*dt)
			PhysicsServer3D.body_apply_central_force(body.get_rid(),(lacc*body.mass).limit_length(body.mass*120.0))

## Povolit sval: [od kdy, za jak dlouho se vrátí, nejnižší napětí]
func _slack(id: int, dur: float, low: float) -> void:
	if not _hitrag_ids.has(id): return
	if _hitrag_slack.has(id):
		var old: Array=_hitrag_slack[id]
		if _time-float(old[0])<float(old[1]): low=minf(low,float(old[2])); dur=maxf(dur,float(old[1])-(_time-float(old[0])))
	_hitrag_slack[id]=[_time,dur,low]

func _part(id: int) -> String:
	return String(bodies[id].get_meta("part_name")) if bodies.has(id) else ""

## Rána: horní polovina těla přejde do fyziky (ve stejné póze a rychlosti jako animace – beze švu),
## rána do ní strčí v místě zásahu, svaly ji vrátí. Další rány jen prodlouží a přidají.
func _hitrag_hit(bone: int, point: Vector3, impulse: Vector3, region: String) -> void:
	if not _hitrag_on and not _hitrag_want:
		# zapne se až v příštím fyzikálním kroku zombie, hned po animaci: tělesa začnou přesně
		# v póze, kterou animace právě vykreslí (jinak jeden snímek „zamrzne“ a pak poskočí)
		_hitrag_want=true
		_hitrag_ids.clear()
		for id in bodies:
			if not _gone(id): _hitrag_ids.append(id)
	_hitrag_setup_hit(bone,point,impulse,region)

func _hitrag_activate() -> void:
	_hitrag_want=false
	if _hitrag_on: return
	var names:=PackedStringArray()
	for id in _hitrag_ids: names.append("mixamorig_"+String(bodies[id].get_meta("part_name")))
	if true:
		var G:=_anim_globals()
		for id in bodies:
			var body: PhysicalBone3D=bodies[id]
			body.global_transform=(skeleton.global_transform*(G[id] as Transform3D)*body.body_offset).orthonormalized()
		# Pánev je taky simulovaná, ale řízená rychlostí přesně do animace (jako kinematická, jen
		# bez zpoždění o snímek, které má kinematické těleso – trup by jinak táhl za starou pánví).
		# Nohy zůstávají animované; jejich klouby k pánvi se po dobu zásahu vypnou.
		for id in _hitrag_ids:
			var body: PhysicalBone3D=bodies[id]
			# kloub bez omezení: polohu drží kloub, natočení svaly podle animace (omezení počítaná
			# z póze v okamžiku rány by animaci nedovolila dál ohnout loket ani trup)
			body.joint_type=PhysicalBone3D.JOINT_TYPE_PIN
			if _followed(id):
				# pánev a nohy: přesně podle animace (vč. škubnutí nohou), bez kloubů a srážek
				body.joint_type=PhysicalBone3D.JOINT_TYPE_NONE
			# Kužel s velkým rozsahem kolem pózy v okamžiku rány: silná rána tělem hodně hne, ale krk,
			# rameno ani páteř se nepřetočí „do zlomeniny“ (ani rameno kolem dlouhé osy). Loket je pant
			# v anatomickém rozsahu (natažený … ohnutý), takže se nikdy nepřelomí dozadu.
			var pn: String=body.get_meta("part_name")
			if pn.ends_with("ForeArm"): _configure_joint(id,true)
			elif HITRAG_SPAN.has(pn) and not _followed(id):
				_configure_joint(id,false)
				body.set("joint_constraints/swing_span",float(HITRAG_SPAN[pn][0]))
				body.set("joint_constraints/twist_span",float(HITRAG_SPAN[pn][1]))
			body.collision_layer=0
			body.collision_mask=0 if _followed(id) else 1
			body.gravity_scale=0.0          # svaly drží proti tíze: v krátké ráně by jen strhávala paže dolů
			body.linear_damp=0.4
			body.angular_damp=1.2
			body.linear_velocity=_velocity+Vector3(_pose_velocity.get(id,Vector3.ZERO))
			body.angular_velocity=Vector3(_pose_spin.get(id,Vector3.ZERO))
			# Pánev jde přesně podle animace: pro kloub páteře je „nehybná“ (těžká), jinak by ji silná
			# rána do břicha přes kloub škubla o celé stupně za snímek.
			if _part(id)=="Hips": PhysicsServer3D.body_set_param(body.get_rid(),PhysicsServer3D.BODY_PARAM_MASS,body.mass*60.0)
		_anim_prev.clear()
		_anim_prev_pos.clear()
		simulator.active=true
		simulator.influence=1.0
		simulator.physical_bones_start_simulation(names)
		_hitrag_on=true

func _hitrag_setup_hit(bone: int, point: Vector3, impulse: Vector3, region: String) -> void:
	var heavy:=clampf((_frame_force-0.3)/(TIER_HEAVY-0.3),0.0,1.0)
	_hitrag_heavy=heavy
	_hitrag_t=lerpf(1.0,1.6,heavy)
	_hitrag_fade=-1.0
	simulator.influence=1.0
	var part:=_part(bone)
	var spine2: int=_ids.get("Spine2",-1)
	var spine: int=_ids.get("Spine",-1)
	var target:=bone
	# Každé místo reaguje jinak (svaly na chvíli povolí, rána jde do správného tělesa):
	if region=="arm":
		# paže odletí ve směru střely a chvíli visí volně, trup se v rameni stočí
		var side:="Left" if part.begins_with("Left") else "Right"
		var upper:=part==side+"Arm"
		for nm in ["Arm","ForeArm"]: _slack(_ids.get(side+nm,-1),lerpf(0.7,1.1,heavy),0.02 if nm=="ForeArm" or upper else 0.15)
		_slack(spine2,0.45,0.25 if upper else 0.6)
		if upper: _pending_hits.append([spine2,point,impulse*0.6])
	elif region=="head":
		# hlava cukne dozadu (krk povolí), trup ji o kus později následuje
		_slack(_ids.get("Head",-1),lerpf(0.55,0.9,heavy),0.02)
		_slack(_ids.get("Neck",-1),lerpf(0.55,0.9,heavy),0.03)
		_slack(spine2,0.5,0.25)
		_pending_hits.append([spine2,point,impulse*0.45])
	else:
		if part=="Hips" or part=="Spine":
			# rána do břicha: tělo se kolem ní přeloží dopředu
			target=spine
			_slack(spine,lerpf(0.55,0.9,heavy),0.03)
			_slack(spine2,lerpf(0.55,0.9,heavy),0.1)
		else:
			_slack(spine2,lerpf(0.5,0.85,heavy),0.03)
			_slack(spine,lerpf(0.4,0.7,heavy),0.15)
		# hlava a paže dobíhají setrvačností
		for nm in ["LeftArm","RightArm","LeftForeArm","RightForeArm"]: _slack(_ids.get(nm,-1),0.6,0.2)
		# hlava se zhoupne (bič), ale krk ji udrží – žádný „zlomený vaz“
		for nm in ["Head","Neck"]: _slack(_ids.get(nm,-1),0.5,0.4)
	_pending_hits.append([target,point,impulse,part=="Hips" or part=="Spine"])
	# paže sebou při ráně škubnou (nervy), každá jinak; těžká rána víc
	for nm in ["LeftForeArm","RightForeArm","LeftArm","RightArm","Head"]:
		var id: int=_ids.get(nm,-1)
		if _hitrag_ids.has(id): _pending_spin.append([id,Vector3(randf_range(-1,1),randf_range(-1,1),randf_range(-1,1))*lerpf(1.5,3.0,heavy)*(1.4 if nm.ends_with("ForeArm") else 1.0)])

func _update_hitrag(dt: float) -> void:
	# rány do stejného tělesa v jednom snímku (broky) sečíst a omezit dohromady
	var agg:={}
	for h in _pending_hits:
		var id: int=h[0]
		if not _hitrag_ids.has(id): id=_ids.get("Spine2",-1)
		if not bodies.has(id): continue
		if not agg.has(id): agg[id]=[Vector3.ZERO,Vector3.ZERO,0.0,false]
		var a: Array=agg[id]
		a[0]=(a[0] as Vector3)+(h[2] as Vector3)
		a[1]=(a[1] as Vector3)+(h[1] as Vector3)*(h[2] as Vector3).length()
		a[2]=float(a[2])+(h[2] as Vector3).length()
		a[3]=a[3] or (h.size()>3 and h[3])
	_pending_hits.clear()
	for id in agg:
		var a: Array=agg[id]
		var body: PhysicalBone3D=bodies[id]
		var part:=_part(id)
		var reg:="hand" if (part.ends_with("ForeArm") or part.ends_with("Hand")) else _region(id)
		var point: Vector3=(a[1] as Vector3)/maxf(float(a[2]),0.0001)
		# rána podle hmotnosti: lehké předloktí nesmí dostat stejný impulz jako trup; těžká zbraň víc
		var imp: Vector3=(a[0] as Vector3).limit_length(body.mass*float(HIT_VMAX.get(reg,2.0))*(1.0+0.7*_hitrag_heavy))
		# tělo se v ráně prohne (rotace kolem osy kolmé ke směru střely), i když kulka jde středem;
		# rána do břicha ho naopak přeloží dopředu; hlava cukne nejvíc
		var t_imp:=Vector3.ZERO
		var axis:=Vector3.UP.cross(imp.normalized())
		if axis.length()>0.1:
			var st:=PhysicsServer3D.body_get_direct_state(body.get_rid())
			var k:=0.45 if reg=="head" else (0.18 if reg=="torso" else 0.09)
			t_imp=axis.normalized()*imp.length()*k*(-1.0 if a[3] else 1.0)
			if st: t_imp=t_imp.limit_length((16.0+10.0*_hitrag_heavy)/maxf(st.inverse_inertia_tensor.get_scale().length()/1.732,0.001))
		# Ránu rozložit do tří snímků (50/32/18 %): tělo „dostane ránu“ a těžce se do ní zhoupne,
		# místo aby jeden snímek cuklo a hned se zastavilo.
		_pushes.append([id,imp,(point-body.global_position).limit_length(0.3),t_imp,0])
	var left:=[]
	for pq in _pushes:
		var b2: PhysicalBone3D=bodies.get(pq[0])
		if b2==null or not _hitrag_ids.has(pq[0]): continue
		var wgt: float=[0.5,0.32,0.18][int(pq[4])]
		b2.apply_impulse((pq[1] as Vector3)*wgt,pq[2])
		if not (pq[3] as Vector3).is_zero_approx(): PhysicsServer3D.body_apply_torque_impulse(b2.get_rid(),(pq[3] as Vector3)*wgt)
		pq[4]=int(pq[4])+1
		if int(pq[4])<3: left.append(pq)
	_pushes=left
	for sp in _pending_spin:
		var b: PhysicalBone3D=bodies.get(sp[0])
		if b: b.angular_velocity+=sp[1]
	_pending_spin.clear()
	var muscles:=[]
	for id in _hitrag_ids:
		if _followed(id): _follow_anim(id,dt)
		else: muscles.append(id)
	_drive_to_anim(muscles,1.0,dt,true)
	for id in _hitrag_ids:
		var b: PhysicalBone3D=bodies[id]
		if b.angular_velocity.length()>16.0: b.angular_velocity=b.angular_velocity.limit_length(16.0)
	_hitrag_t-=dt
	if _hitrag_t<=0.0 and _hitrag_fade<0.0:
		# vracet do animace, až je tělo zpátky blízko pózy (nejvýš o 0,4 s později)
		var far:=0.0
		var G:=_anim_globals()
		var sb:=skeleton.global_basis.orthonormalized()
		for id in _hitrag_ids:
			var b: PhysicalBone3D=bodies[id]
			var tgt:=(sb*(G[id] as Transform3D).basis.orthonormalized()*b.body_offset.basis.orthonormalized()).orthonormalized()
			far=maxf(far,_rotation_error(tgt,b.global_basis).length())
		if far<0.2 or _hitrag_t<-0.4:
			_hitrag_fade=0.0
			# co zbývá dorovnat, dorovnat rychlostí nejvýš ~3 rad/s
			_hitrag_fade_len=clampf(far/3.0,HITRAG_FADE,0.6)
	if _hitrag_fade>=0.0:
		# návrat do animace: fyzika už je skoro v animační póze, prolnutí jen dorovná zbytek
		_hitrag_fade+=dt
		simulator.influence=1.0-smoothstep(0.0,_hitrag_fade_len,_hitrag_fade)
		if _hitrag_fade>=_hitrag_fade_len: _hitrag_stop()

## Pánev a nohy při fyzikálním zásahu jen přesně sledují animaci (kinematické těleso by se
## vykreslovalo o snímek pozadu – nohy by při každé ráně zaškobrtly).
func _followed(id: int) -> bool:
	var part:=_part(id)
	return part=="Hips" or part.ends_with("Leg") or part.ends_with("Foot")

## Těleso přesně do animační pózy během příštího kroku (rychlostí, ne teleportem).
func _follow_anim(id: int, dt: float) -> void:
	var body: PhysicalBone3D=bodies.get(id)
	if body==null: return
	var G:=_anim_globals()
	var tgt:=(skeleton.global_transform*(G[id] as Transform3D)*body.body_offset).orthonormalized()
	body.linear_velocity=(tgt.origin-body.global_position)/maxf(dt,0.001)
	body.angular_velocity=_rotation_error(tgt.basis,body.global_basis)/maxf(dt,0.001)

func _hitrag_restore(id: int) -> void:
	var body: PhysicalBone3D=bodies[id]
	if _part(id)=="Hips": PhysicsServer3D.body_set_param(body.get_rid(),PhysicsServer3D.BODY_PARAM_MASS,body.mass)
	body.gravity_scale=1.0
	body.collision_layer=0
	body.collision_mask=1|32
	body.linear_damp=0.03
	body.angular_damp=0.25

func _hitrag_stop() -> void:
	if not _hitrag_on: return
	_hitrag_on=false
	simulator.physical_bones_stop_simulation()
	simulator.active=false
	simulator.influence=1.0
	for id in _hitrag_ids: _hitrag_restore(id)
	for id in bodies: _configure_joint(id,false)
	_hitrag_slack.clear()
	_pushes.clear()
	_pending_hits.clear()
	_pending_spin.clear()

## Pád / smrt během fyzikálního zásahu: simulovaná tělesa zůstanou, jak jsou (poloha i rychlost),
## jen se jim vrátí tíha. Vrací jejich seznam.
func _hitrag_take_over() -> Array:
	if _hitrag_want:
		# zásah se ještě nestihl zapnout: rány půjdou rovnou do ragdollu
		_hitrag_want=false
		for h in _pending_hits: _pending_impacts.append(h)
		_pending_hits.clear()
		_pending_spin.clear()
		_hitrag_slack.clear()
	if not _hitrag_on: return []
	var live:=_hitrag_ids.duplicate()
	_hitrag_on=false
	for id in live:
		if _part(id)=="Hips": PhysicsServer3D.body_set_param(bodies[id].get_rid(),PhysicsServer3D.BODY_PARAM_MASS,bodies[id].mass)
		bodies[id].gravity_scale=1.0
		bodies[id].collision_mask=1|32
		bodies[id].collision_layer=0
	for h in _pending_hits: _pending_impacts.append(h)
	# nedoručené zbytky rozložených ran dostane ragdoll najednou
	for pq in _pushes:
		if int(pq[4])==1: _pending_impacts.append([pq[0],bodies[pq[0]].global_position+(pq[2] as Vector3),(pq[1] as Vector3)*0.5])
		elif int(pq[4])==2: _pending_impacts.append([pq[0],bodies[pq[0]].global_position+(pq[2] as Vector3),(pq[1] as Vector3)*0.18])
	_pushes.clear()
	_pending_hits.clear()
	_pending_spin.clear()
	_hitrag_slack.clear()
	return live

# ------------------------------------------------------------------ útoky

func _start_attack(distance: float) -> void:
	var kind_now:="swipe"
	if distance>0.85 and distance<1.55 and randf()<0.3: kind_now="grab"
	if force_attack!="": kind_now=force_attack
	_atk=ATTACKS[kind_now]
	var anims: Array=_atk.anims
	var anim: String=anims[1] if (anims.size()>1 and (randf()<0.5)) else anims[0]
	_clip="attack"
	_clip_speed=float(_atk.speed)
	_animation.play("z/"+anim,0.12)
	_animation.seek(float(_atk.from),true)
	_attack_left=(float(_atk.end)-float(_atk.from))/float(_atk.speed)
	_attack_time=0.0
	_attack_hit=false
	_atk_hit_i=0
	_lunge=0.6 if distance<1.4 else float(SPEEDS[tier])*0.8*_gait_factor
	_say("zombie_attack",-5.0 if _lunge<1.0 else -2.5)

# ------------------------------------------------------------------ krmení u těla

## Zombie se krmí u mrtvoly (podřep, žere). Vyruší ji hráč nablízku, výstřel (noise) nebo zásah.
func feed() -> void:
	feeding=true
	ai=false
	_clip=""
	_play("bite2",randf_range(0.85,1.1))
	_animation.seek(randf()*2.0,true)

func _feed_rise() -> void:
	if not feeding: return
	feeding=false
	_feed_rise_t=(6.9-5.3)/1.25
	_clip="bite"
	_clip_speed=1.25
	_animation.play("z/bite",0.25)
	_animation.seek(5.3,true)
	_say("zombie_attack",-4.0)

func _update_feeding(dt: float) -> void:
	_move(Vector3.ZERO)
	if feeding:
		if is_instance_valid(target):
			var d: Vector3=target.global_position-global_position
			if Vector2(d.x,d.z).length()<5.0 and absf(d.y)<2.0: _feed_rise()
		return
	_feed_rise_t-=dt
	if is_instance_valid(target):
		var to: Vector3=target.global_position-global_position
		rotation.y=lerp_angle(rotation.y,atan2(to.x,to.z),1.0-exp(-4.0*dt))
	if _feed_rise_t<=0.0:
		_feed_rise_t=0.0
		_clip=""
		alert(randf()<0.6)
		if _clip=="": _play("idle",1.0)

## Výstřel / hluk: krmící se zombie v okolí zvednou hlavu a jdou se podívat.
static func noise(at: Vector3, radius: float) -> void:
	for z in crowd:
		if is_instance_valid(z) and z.feeding and z.global_position.distance_to(at)<radius: z._feed_rise()

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
	_sinking=true
	corpses.erase(self)
	if not _frozen: _freeze()
	for body in bodies.values():
		body.collision_layer=0
		body.collision_mask=0
	process_mode=Node.PROCESS_MODE_INHERIT
	set_physics_process(false)
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

## Svalové napětí živého těla při pádu: zpočátku drží (ruce se snaží zachytit), po dopadu povolí.
func _alive_tone(id: int) -> float:
	var region:=_region(id)
	var k:=clampf(_rag_t/1.1,0.0,1.0)
	var tone:=lerpf(0.55,0.22,k)
	if region=="leg": tone=lerpf(0.3,0.08,k)
	elif region=="arm": tone=lerpf(0.45,0.2,k)
	elif region=="head": tone=lerpf(0.6,0.3,k)
	if id==_injured_bone: tone*=0.3
	return tone

func _drive_muscles(alive: bool=false) -> void:
	if _resting and not alive: return
	var dt:=get_physics_process_delta_time()
	for muscle in _muscles:
		var body: PhysicalBone3D=bodies[muscle.bone]
		var parent: PhysicalBone3D=bodies[muscle.parent]
		var region:=_region(muscle.bone)
		var i_c: float=_inertia[muscle.bone]
		var i_p: float=_inertia[muscle.parent]
		var i_eff:=i_c*i_p/(i_c+i_p)
		var omega:=11.0 if region=="torso" else (9.0 if region=="leg" else 7.0)
		var k:=omega*omega*i_eff*(_alive_tone(muscle.bone) if alive else _tone(muscle.bone))
		# Trvalé tření v kloubech dává tělu váhu: končetiny nelétají jako špagety.
		var friction:=(9.0 if region=="torso" else (7.0 if region=="head" else 4.5))*i_eff
		var c:=2.0*sqrt(k*i_eff)+friction
		var denom:=1.0+(k*dt*dt+c*dt)/i_eff
		var error:=_rotation_error(parent.global_basis*muscle.target,body.global_basis)
		var velocity:=body.angular_velocity-parent.angular_velocity
		var torque:=((error*k-velocity*(k*dt+c))/denom).limit_length(120.0 if region in ["torso","leg"] else 40.0)
		PhysicsServer3D.body_apply_torque(body.get_rid(),torque)
		PhysicsServer3D.body_apply_torque(parent.get_rid(),-torque)
	if alive or _death_time<1.5: return
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
	# Zapečené tělo jde dál trefit (vrstva 32): zásah ho znovu rozpohybuje (_unfreeze).
	for id in bodies:
		bodies[id].collision_layer=0 if _gone(id) else 32
		bodies[id].collision_mask=0
	# Odstřelené části zůstanou smrštěné napořád; úprava pózy už není potřeba.
	for cut in _severed: skeleton.set_bone_pose_scale(cut,Vector3(0.001,0.001,0.001))
	_gib.active=false
	_frozen=true
	set_physics_process(false)
	# Zapečená mrtvola nepotřebuje žádné zpracování (kostra, animace, modifikátory) – jen se kreslí.
	process_mode=Node.PROCESS_MODE_DISABLED
	if not keep_corpse and not _sink_queued:
		_sink_queued=true
		get_tree().create_timer(CORPSE_TIME).timeout.connect(_sink)

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

var _sink_queued:=false
var _yaw_prev:=0.0
var _wall_n:=Vector3.ZERO
var _wall_hold:=0.0
var _turn_stuck:=0.0
var _sinking:=false

func _gone(id: int) -> bool:
	for cut in _severed:
		if id==cut or _is_descendant(id,cut): return true
	return false

## Žádná část těla ve zdi: po animaci (výpad, plazení, otáčení u stěny) se tělo, hlava a nohy
## vytlačí posunem celé zombie (kontrolovaným proti kolizím), paže se o zeď ohnou v rameni
## a když za zády není místo (úzká chodba), zakloní se trup.
func _keep_out_of_walls() -> void:
	if _emerge>0.0: return
	if is_instance_valid(target) and global_position.distance_squared_to(target.global_position)>900.0: return
	var space:=get_world_3d().direct_space_state
	var low:=_is_low()
	var c:=global_position+Vector3.UP*(0.42 if low else 0.95)
	var floor_y:=global_position.y+0.08
	var q:=PhysicsRayQueryParameters3D.new()
	q.collision_mask=1
	var push:=Vector3.ZERO
	var head_hit: Array=[]
	var body_hits: Array=[]
	var arm_hits:={}
	var to_world:=skeleton.global_transform
	for probe in WALL_PROBES:
		var id: int=_ids.get(probe[0],-1)
		if not bodies.has(id) or _gone(id): continue
		var body: PhysicalBone3D=bodies[id]
		var t: Transform3D=to_world*bone_pose(id)*body.body_offset
		var p: Vector3=t.origin+t.basis.y.normalized()*float(body.get_meta("half"))*float(probe[1])
		p.y=maxf(p.y,floor_y)
		var dir:=p-c
		var dist:=dir.length()
		if dist<0.05: continue
		dir/=dist
		var r: float=probe[2]
		var flat:=Vector3(dir.x,0.0,dir.z)
		q.from=c
		q.to=p+(flat.normalized()*r if flat.length_squared()>1e-4 else Vector3.ZERO)
		var hit:=space.intersect_ray(q)
		if hit.is_empty(): continue
		var n: Vector3=hit.normal
		if absf(n.y)>0.65: continue
		n.y=0.0
		n=n.normalized()
		# Hloubka koule (střed p, poloměr r) za rovinou zdi.
		var depth: float=(p-hit.position).dot(-n)+r
		if depth<=0.003: continue
		# Paže mířící do zdi zhruba kolmo se ohnutím nevyřeší: couvne celá zombie (ruce se opřou o zeď).
		var into: bool=probe[3]=="body"
		if not into:
			var shoulder: Vector3=(to_world*bone_pose(_ids[str(probe[3])+"Arm"])).origin
			into=(p-shoulder).normalized().dot(-n)>0.55
		if into:
			body_hits.append([n,depth])
			if probe[0]=="Head" and depth>(0.0 if head_hit.is_empty() else float(head_hit[2])): head_hit=[p,n,depth]
		if probe[3]!="body" and depth>float(arm_hits.get(probe[3],[null,null,0.0])[2]):
			arm_hits[probe[3]]=[p,n,depth]
	# Posun, který vyhoví všem zdem najednou (kout, úzká chodba): uvolněné promítání.
	# Protilehlé zdi se tak vyrovnají uprostřed místo přeskakování z jedné na druhou.
	for it in 8:
		for h in body_hits:
			var viol: float=float(h[1])-push.dot(h[0])
			if viol>0.0: push+=(h[0] as Vector3)*viol*(1.0 if it==0 else 0.5)
	var moved:=Vector3.ZERO
	if push.length_squared()>1e-6:
		push=push.limit_length(0.3)
		_sweep.shape=_capsule_low if low else _capsule
		_sweep.transform=Transform3D(Basis.IDENTITY,c)
		_sweep.motion=push
		var allowed: float=space.cast_motion(_sweep)[0]
		moved=push*allowed
		global_position+=moved
		_wall_n=push.normalized()
		_wall_hold=0.25
	# Tělo nemá kam couvnout (úzká chodba, kout): otočku z tohoto snímku zrušit, ať se zombie
	# neotočí napříč přes zeď. Kdyby se zasekla, po 2 s se otočit nechá.
	var left_max:=0.0
	for h in body_hits: left_max=maxf(left_max,float(h[1])-moved.dot(h[0]))
	if left_max>0.02 and absf(angle_difference(rotation.y,_yaw_prev))>0.0001 and _turn_stuck<2.0:
		_turn_stuck+=get_physics_process_delta_time()
		rotation.y=_yaw_prev
		return
	if left_max<=0.02: _turn_stuck=0.0
	if not head_hit.is_empty():
		var left: float=float(head_hit[2])-moved.dot(head_hit[1])
		if left>0.01: _bend_away(_ids["Spine"],head_hit[0]+moved,head_hit[1],left,0.7)
	for side in arm_hits:
		var h: Array=arm_hits[side]
		var left: float=float(h[2])-moved.dot(h[1])
		if left>0.005: _bend_away(_ids[side+"Arm"],h[0]+moved,h[1],left,1.4)

## Otočí kost tak, aby se bod `p` (svět) posunul o `depth` ve směru normály zdi.
func _bend_away(bone: int, p: Vector3, n: Vector3, depth: float, max_angle: float) -> void:
	if bone<0: return
	var pivot: Vector3=(skeleton.global_transform*bone_pose(bone)).origin
	var arm: Vector3=p-pivot
	var length:=arm.length()
	if length<0.08: return
	var axis:=arm.cross(n)
	if axis.length_squared()<1e-6: return
	var angle:=minf(depth*1.1/length,max_angle)
	_rotate_bone(bone,skeleton.global_basis.inverse()*axis.normalized(),angle)

## Pojistka při přechodu do fyziky: těleso, které by začalo za zdí, se vrátí před ni
## (jinak se zasekne ve zdi nebo ho fyzika vystřelí).
func _pull_bodies_out_of_walls() -> void:
	var space:=get_world_3d().direct_space_state
	var c:=global_position+Vector3.UP*(0.42 if _is_low() else 0.95)
	var q:=PhysicsRayQueryParameters3D.new()
	q.collision_mask=1
	for id in bodies:
		var body: PhysicalBone3D=bodies[id]
		var r:=float(body.get_meta("radius"))
		var p:=body.global_position
		var d:=p-c
		var length:=d.length()
		if length<0.05: continue
		d/=length
		q.from=c
		q.to=p+d*r
		var hit:=space.intersect_ray(q)
		if hit.is_empty() or absf(hit.normal.y)>0.65: continue
		body.global_position=hit.position-d*(r+0.02)

## Mrtvé tělo ve vodě: vztlak a odpor. Pád do bazénu zbrzdí hladina, tělo se pomalu snese ke dnu.
func _water_forces() -> void:
	var wl:=_wl()
	for id in bodies:
		var body: PhysicalBone3D=bodies[id]
		if body.collision_mask==0: continue
		var r:=float(body.get_meta("radius"))
		var sub:=clampf((wl-body.global_position.y+r)/(2.0*r),0.0,1.0)
		if sub<=0.0: continue
		var rid:=body.get_rid()
		PhysicsServer3D.body_apply_central_force(rid,(Vector3.UP*9.8*WATER_LIFT-body.linear_velocity*WATER_DRAG)*body.mass*sub)
		PhysicsServer3D.body_apply_torque(rid,-body.angular_velocity*float(_inertia[id])*WATER_DRAG*1.5*sub)

## Zapečená mrtvola dostala ránu: znovu zapnout fyziku z její pózy.
func _unfreeze() -> bool:
	if not _frozen or _sinking or not is_inside_tree(): return false
	_frozen=false
	_resting=false
	_rest_timer=0.0
	_death_time=1.6                     # svaly už dávno povolily
	_impact_count=maxi(_impact_count,4)
	process_mode=Node.PROCESS_MODE_INHERIT
	set_physics_process(true)
	_gib.active=true
	simulator.active=true
	simulator.influence=1.0
	simulator.physical_bones_start_simulation()
	for id in bodies:
		var body: PhysicalBone3D=bodies[id]
		body.global_transform=(skeleton.global_transform*bone_pose(id)*body.body_offset).orthonormalized()
		body.linear_velocity=Vector3.ZERO
		body.angular_velocity=Vector3.ZERO
		if _gone(id):
			body.collision_layer=0
			body.collision_mask=0
		else:
			body.collision_layer=32
			body.collision_mask=1|32
	return true

## Výbuch: živé zabije a s každým tělem (i ležícím) mrští od středu podle vzdálenosti.
func blast(center: Vector3, radius: float, speed: float) -> void:
	if _death_anim!="": _death_handoff(global_position+Vector3.UP,Vector3.ZERO,_ids["Spine2"])
	if not dead and not _death_pending:
		hit(_ids["Spine2"],global_position+Vector3.UP,(global_position-center).normalized(),2.8,99999.0)
	elif _frozen and not _unfreeze():
		return
	_wake()
	for id in bodies:
		if _gone(id): continue
		var body: PhysicalBone3D=bodies[id]
		var at: Vector3=body.global_position if dead and not _death_pending else (skeleton.global_transform*bone_pose(id)*body.body_offset).origin
		var away:=at-center
		var fall:=clampf(1.0-away.length()/radius,0.15,1.0)
		var dir:=(away.normalized()+Vector3.UP*0.7).normalized()
		_pending_impacts.append([id,at,dir*speed*fall*body.mass])
