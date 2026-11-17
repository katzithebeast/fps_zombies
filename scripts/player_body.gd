extends Node3D
signal action_started(kind: String, data: Array)
## Společně animované celé tělo; vlastní pohled vynechává pouze hlavu.
const MODEL := preload("res://assets/scientist/ScientistRigged.fbx")
const LIBRARY := preload("res://assets/scientist/locomotion.res")
const FIRST_PERSON := preload("res://assets/scientist/closed_first_person_mesh.res")
const FIRST_SKIN := preload("res://assets/scientist/first_person_skin.res")

var skeleton: Skeleton3D
var first_skeleton: Skeleton3D
var tree: AnimationTree
var model: Node3D
var first_mesh: MeshInstance3D
var blend_speed := 0.0
var body_yaw := 0.0
var crouch_amount := 0.0
var swim_amount := 0.0
var swim_motion := 0.0
var direction := Vector2(0.0, 1.0)
var using_sprint_strafe := false
var _initialized := false
var _pickup_cancel_requested := false
var jump_airborne := false
var _jump_rate := 1.0
var _jump_elapsed := 0.0
var _turning := false
var _turn_from := 0.0
var _turn_target := 0.0
var _turn_elapsed := 0.0
var _turn_duration := 1.0
var _pickup_facing := INF
var first_person_turn_amount := 0.0
var _last_look_yaw := 0.0
var _fp_turn_velocity := 0.0
var weapon: Node

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	model = MODEL.instantiate()
	model.name = "Scientist"
	model.scale = Vector3.ONE * 0.86
	add_child(model)
	skeleton = model.get_node("Skeleton3D")
	var full: MeshInstance3D = skeleton.get_node("ScientistBody")
	full.layers = 4
	full.extra_cull_margin = 3.0
	full.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	for surface in full.mesh.get_surface_count():
		var original: StandardMaterial3D = full.get_active_material(surface)
		var material := ShaderMaterial.new()
		material.shader = preload("res://shaders/scientist.gdshader")
		material.set_shader_parameter("albedo_tex", original.albedo_texture)
		material.set_shader_parameter("tint", original.albedo_color)
		material.set_shader_parameter("roughness", original.roughness)
		material.set_shader_parameter("metallic", original.metallic)
		full.set_surface_override_material(surface, material)
	first_mesh = MeshInstance3D.new()
	first_mesh.name = "FullFirstPersonBody"
	first_mesh.mesh = FIRST_PERSON
	first_mesh.skin = FIRST_SKIN
	first_mesh.skeleton = NodePath("..")
	first_mesh.layers = 8
	first_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	first_mesh.extra_cull_margin = 3.0
	first_mesh.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	first_skeleton=Skeleton3D.new()
	first_skeleton.name="FirstPersonSkeleton"
	model.add_child(first_skeleton)
	for bone in skeleton.get_bone_count():
		first_skeleton.add_bone(skeleton.get_bone_name(bone))
		first_skeleton.set_bone_parent(bone,skeleton.get_bone_parent(bone))
		first_skeleton.set_bone_rest(bone,skeleton.get_bone_rest(bone))
	first_skeleton.add_child(first_mesh)
	var animations := AnimationPlayer.new()
	animations.name = "LocomotionPlayer"
	model.add_child(animations)
	animations.add_animation_library("", LIBRARY)
	var forward := AnimationNodeBlendSpace1D.new()
	forward.min_space = 2.2
	forward.max_space = 4.0
	forward.sync_mode = AnimationNodeBlendSpace1D.SYNC_MODE_INDEPENDENT
	forward.add_blend_point(clip("slow_run"), 2.2, -1, "walk")
	forward.add_blend_point(clip("fast_run"), 4.0, -1, "run")
	var walking := AnimationNodeBlendSpace2D.new()
	walking.sync_mode = AnimationNodeBlendSpace2D.SYNC_MODE_INDEPENDENT
	walking.auto_triangles = false
	walking.add_blend_point(forward, Vector2(0, 1), -1, "forward")
	walking.add_blend_point(clip("backward"), Vector2(0, -1), -1, "backward")
	walking.add_blend_point(clip("strafe_left"), Vector2(-1, 0), -1, "left")
	walking.add_blend_point(clip("strafe_right"), Vector2(1, 0), -1, "right")
	walking.add_triangle(0, 2, 3)
	walking.add_triangle(1, 3, 2)
	var graph := AnimationNodeBlendTree.new()
	graph.add_node("walk", walking)
	graph.add_node("walk_pace", AnimationNodeTimeScale.new())
	graph.add_node("idle", clip("idle"))
	graph.add_node("moving", AnimationNodeBlend2.new())
	graph.connect_node("walk_pace", 0, "walk")
	graph.connect_node("moving", 0, "idle")
	graph.connect_node("moving", 1, "walk_pace")
	graph.add_node("crouch_idle", clip("crouch_idle"))
	graph.add_node("crouch_walk", clip("crouch_walk"))
	graph.add_node("crouch_pace", AnimationNodeTimeScale.new())
	graph.add_node("crouch_moving", AnimationNodeBlend2.new())
	graph.connect_node("crouch_pace", 0, "crouch_walk")
	graph.connect_node("crouch_moving", 0, "crouch_idle")
	graph.connect_node("crouch_moving", 1, "crouch_pace")
	graph.add_node("fp_turn_clip", clip("turn_loop"))
	graph.add_node("fp_turn_rate", AnimationNodeTimeScale.new())
	graph.connect_node("fp_turn_rate", 0, "fp_turn_clip")
	graph.add_node("fp_turn", AnimationNodeBlend2.new())
	graph.connect_node("fp_turn", 0, "moving")
	graph.connect_node("fp_turn", 1, "fp_turn_rate")
	graph.add_node("stance", AnimationNodeBlend2.new())
	graph.connect_node("stance", 0, "fp_turn")
	graph.connect_node("stance", 1, "crouch_moving")
	graph.add_node("tread", clip("tread_water"))
	graph.add_node("swim", clip("swim"))
	graph.add_node("swim_pace", AnimationNodeTimeScale.new())
	graph.connect_node("swim_pace", 0, "swim")
	graph.add_node("water", AnimationNodeBlend2.new())
	graph.connect_node("water", 0, "tread")
	graph.connect_node("water", 1, "swim_pace")
	graph.add_node("environment", AnimationNodeBlend2.new())
	graph.connect_node("environment", 0, "stance")
	graph.connect_node("environment", 1, "water")
	graph.add_node("turn_clip", clip("turn"))
	graph.add_node("turn_rate", AnimationNodeTimeScale.new())
	graph.connect_node("turn_rate", 0, "turn_clip")
	var turning := AnimationNodeOneShot.new()
	turning.fadein_time = 0.10
	turning.fadeout_time = 0.15
	graph.add_node("turning", turning)
	graph.connect_node("turning", 0, "environment")
	graph.connect_node("turning", 1, "turn_rate")
	graph.add_node("jump_clip", clip("jump"))
	graph.add_node("jump_seek", AnimationNodeTimeSeek.new())
	graph.add_node("jump_rate", AnimationNodeTimeScale.new())
	graph.connect_node("jump_seek", 0, "jump_clip")
	graph.connect_node("jump_rate", 0, "jump_seek")
	var jumping := AnimationNodeOneShot.new()
	jumping.fadein_time = 0.06
	jumping.fadeout_time = 0.12
	graph.add_node("jumping", jumping)
	graph.connect_node("jumping", 0, "turning")
	graph.connect_node("jumping", 1, "jump_rate")
	graph.add_node("pickup_clip", clip("pick_up"))
	var pickup := AnimationNodeOneShot.new()
	pickup.fadein_time = 0.22
	pickup.fadeout_time = 0.28
	graph.add_node("pickup", pickup)
	graph.connect_node("pickup", 0, "jumping")
	graph.connect_node("pickup", 1, "pickup_clip")
	graph.connect_node("output", 0, "pickup")
	tree = AnimationTree.new()
	tree.name = "LocomotionTree"
	model.add_child(tree)
	tree.anim_player = tree.get_path_to(animations)
	tree.tree_root = graph
	tree.callback_mode_process = AnimationMixer.ANIMATION_CALLBACK_MODE_PROCESS_MANUAL
	tree.active = true
	weapon=preload("res://scripts/weapon_rig.gd").new()
	weapon.avatar=self
	add_child(weapon)

func clip(name: String) -> AnimationNodeAnimation:
	var node := AnimationNodeAnimation.new()
	node.animation = name
	return node

func reset(look_yaw: float) -> void:
	body_yaw = look_yaw
	blend_speed = 0.0
	crouch_amount = 0.0
	swim_amount = 0.0
	swim_motion = 0.0
	direction = Vector2(0, 1)
	using_sprint_strafe = false
	jump_airborne = false
	_turning = false
	_pickup_facing = INF
	_pickup_cancel_requested = false
	first_person_turn_amount = 0.0
	_last_look_yaw = look_yaw
	_fp_turn_velocity = 0.0
	_initialized = true
	if tree:
		tree.set("parameters/fp_turn/blend_amount", 0.0)
		tree.set("parameters/pickup/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		tree.set("parameters/jumping/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		tree.set("parameters/turning/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
		tree.advance(0.0)

func pick_up(facing := INF, stop_for_interaction := false) -> bool:
	if tree == null or jump_airborne:
		return false
	if not stop_for_interaction and (blend_speed > 0.25 or crouch_amount > 0.1 or swim_amount > 0.1):
		return false
	if tree.get("parameters/pickup/active"):
		return false
	_cancel_turn()
	_pickup_facing = facing
	tree.set("parameters/pickup/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	_pickup_cancel_requested = false
	action_started.emit("pickup", [facing if is_finite(facing) else body_yaw])
	return true

func is_picking_up() -> bool:
	return bool(tree.get("parameters/pickup/active")) and not _pickup_cancel_requested

func start_jump(launch_speed: float, gravity: float) -> void:
	jump_airborne = true
	_jump_elapsed = 0.0
	_jump_rate = 0.64 / maxf(2.0 * launch_speed / gravity, 0.15)
	_cancel_turn()
	tree.set("parameters/pickup/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_ABORT)
	tree.set("parameters/jump_rate/scale", _jump_rate)
	tree.set("parameters/jumping/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	action_started.emit("jump", [launch_speed, gravity])

func land_jump() -> void:
	if not jump_airborne:
		return
	jump_airborne = false
	# Dokončit tlumení dopadu podle skutečného kontaktu s podlahou.
	tree.set("parameters/jump_seek/seek_request", 0.64)
	tree.set("parameters/jump_rate/scale", 1.0)
	action_started.emit("land", [])

func turn_to(target_yaw: float) -> bool:
	if blend_speed > 0.25 or crouch_amount > 0.1 or swim_amount > 0.1 or jump_airborne or is_picking_up() or _turning:
		return false
	var angle := wrapf(target_yaw - body_yaw, -PI, PI)
	if absf(angle) < 0.12:
		return false
	_turn_from = body_yaw
	_turn_target = body_yaw + angle
	_turn_elapsed = 0.0
	_turn_duration = clampf(absf(angle) / (PI * 0.5) * 0.85, 0.45, 1.4)
	_turning = true
	tree.set("parameters/turn_rate/scale", 1.0 / _turn_duration)
	tree.set("parameters/turning/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FIRE)
	action_started.emit("turn", [target_yaw])
	return true

func _cancel_turn() -> void:
	if _turning:
		tree.set("parameters/turning/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		_turning = false

func update_body(dt: float, feet: Vector3, look_yaw: float, movement: Vector3, crouched: bool, swimming: bool, enabled: bool, side_sprint := false, orbit_mode := false, grounded := true) -> void:
	visible = enabled
	if not enabled:
		_last_look_yaw = look_yaw
		_fp_turn_velocity = 0.0
		return
	if not _initialized:
		reset(look_yaw)
	var speed := Vector2(movement.x, movement.z).length()
	if speed > 0.25 or crouched or swimming or not orbit_mode:
		_cancel_turn()
	if swimming and jump_airborne:
		jump_airborne = false
		tree.set("parameters/jumping/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
	if jump_airborne:
		_jump_elapsed += dt * _jump_rate
		# Při seskoku z hrany podržet letovou pózu až do skutečného dopadu.
		tree.set("parameters/jump_rate/scale", _jump_rate if _jump_elapsed < 0.61 else 0.0)
	blend_speed = lerpf(blend_speed, speed, 1.0 - exp(-10.0 * dt))
	crouch_amount = lerpf(crouch_amount, 1.0 if crouched else 0.0, 1.0 - exp(-9.0 * dt))
	swim_amount = lerpf(swim_amount, 1.0 if swimming else 0.0, 1.0 - exp(-6.0 * dt))
	swim_motion = lerpf(swim_motion, smoothstep(0.12, 1.0, speed) if swimming else 0.0, 1.0 - exp(-6.0 * dt))
	# Myš v první osobě natáčí tělo přímo; animace proto sleduje změnu pohledu,
	# nikoli jen klávesu R nebo malou zbývající odchylku natočení těla.
	var yaw_velocity := clampf(wrapf(look_yaw - _last_look_yaw, -PI, PI) / maxf(dt, 0.001), -8.0, 8.0)
	_last_look_yaw = look_yaw
	_fp_turn_velocity = lerpf(_fp_turn_velocity, yaw_velocity, 1.0 - exp(-18.0 * dt))
	var can_step := not orbit_mode and grounded and speed < 0.15 and blend_speed < 0.25 and not crouched and not swimming and not jump_airborne and not is_picking_up()
	var turn_weight := smoothstep(0.05, 0.30, absf(_fp_turn_velocity)) if can_step else 0.0
	first_person_turn_amount = lerpf(first_person_turn_amount, turn_weight, 1.0 - exp(-14.0 * dt))
	tree.set("parameters/fp_turn/blend_amount", first_person_turn_amount)
	if absf(_fp_turn_velocity) > 0.03:
		# Dodaný klip zatáčí doprava; opačný směr přehrává stejné kroky pozpátku.
		tree.set("parameters/fp_turn_rate/scale", -signf(_fp_turn_velocity) * clampf(absf(_fp_turn_velocity) / 1.5, 0.6, 2.4))
	var local := Basis(Vector3.UP, -look_yaw) * movement
	using_sprint_strafe = side_sprint and not crouched and not swimming and speed > 0.15 and absf(local.x) > 0.1
	var animation_direction := Vector2(0.0, -1.0 if local.z > 0.15 and not orbit_mode else 1.0)
	if using_sprint_strafe:
		animation_direction = Vector2(local.x, -local.z).normalized()
	# Chůze už vůbec nevstupuje do bočních sprintových klipů. Směrové
	# prolínání zůstává pro Shift+A/D; ostatní pohyb používá chůzi/běh.
	direction = direction.move_toward(animation_direction, dt * 10.0)
	var facing := look_yaw
	if orbit_mode:
		# Stojící postava si ponechá směr nezávisle na myši. Běžný pohyb
		# ji natáčí podle skutečné světové rychlosti, ovládání zůstává relativní ke kameře.
		facing = body_yaw
		if speed > 0.15:
			facing = look_yaw if using_sprint_strafe else atan2(-movement.x, -movement.z)
	if _turning:
		_turn_elapsed += dt
		body_yaw = lerpf(_turn_from, _turn_target, smoothstep(0.0, _turn_duration, _turn_elapsed))
		if _turn_elapsed >= _turn_duration:
			_turning = false
	else:
		if is_picking_up() and is_finite(_pickup_facing):
			facing = _pickup_facing
		body_yaw = lerp_angle(body_yaw, facing, 1.0 - exp(-16.0 * dt))
	global_position = feet
	rotation.y = body_yaw + PI
	# Náklon nese dodaný klip; pouze vyrovnáme polohu hlavy u hladiny.
	model.position = Vector3(0.0, swim_amount * swim_motion * 0.65, -swim_amount * swim_motion * 0.75)
	# Objektiv je před hrudí. Celý trup a paže zůstávají viditelné i v přikrčení.
	first_mesh.position = Vector3(0.0, 0.0, -0.35)
	first_mesh.visible = true
	tree.set("parameters/walk/blend_position", direction)
	tree.set("parameters/walk/forward/blend_position", clampf(blend_speed, 2.2, 4.0))
	tree.set("parameters/walk_pace/scale", clampf(blend_speed / 2.2, 0.25, 1.0))
	tree.set("parameters/moving/blend_amount", smoothstep(0.02, 0.7, blend_speed))
	tree.set("parameters/crouch_pace/scale", clampf(blend_speed / 1.05, 0.2, 1.4) * (-1.0 if local.z > 0.2 else 1.0))
	tree.set("parameters/crouch_moving/blend_amount", smoothstep(0.02, 0.4, blend_speed))
	tree.set("parameters/stance/blend_amount", crouch_amount)
	tree.set("parameters/swim_pace/scale", clampf(blend_speed / 1.5, 0.65, 1.5))
	tree.set("parameters/water/blend_amount", swim_motion)
	tree.set("parameters/environment/blend_amount", swim_amount)
	var pickup_active := bool(tree.get("parameters/pickup/active"))
	if not pickup_active:
		_pickup_cancel_requested = false
	if pickup_active and not _pickup_cancel_requested and (speed > 0.25 or crouched or swimming):
		tree.set("parameters/pickup/request", AnimationNodeOneShot.ONE_SHOT_REQUEST_FADE_OUT)
		_pickup_cancel_requested = true
	# Nejdřív vyhodnotit pózu, pak teprve umístit kameru. Automatický update
	# po kameře nechával objektiv při běhu o snímek uvnitř pohybujícího se trupu.
	tree.advance(dt)
	weapon.pose(dt,swimming)
	weapon.pose_first_person()

func first_person_eye(look_yaw: float) -> Vector3:
	var head_bone := skeleton.find_bone("mixamorig_Head")
	var eye: Vector3 = first_mesh.global_transform * (weapon.bone_pose(head_bone).origin + weapon.head_offset)
	var forward := Basis(Vector3.UP, look_yaw) * Vector3.FORWARD
	return eye + forward * lerpf(0.28,0.20,weapon.weight) + Vector3(0.0, 0.07, 0.0)
