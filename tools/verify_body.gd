extends SceneTree
## Godot --headless --path . --script res://tools/verify_body.gd
## Regrese: celý trup/paže v první osobě a skutečně běžící klipy i kosti.
var failures := 0

func _initialize() -> void:
	call_deferred("verify")

func check(ok: bool, message: String) -> void:
	if ok:
		print("PASS ", message)
	else:
		failures += 1
		push_error("FAIL " + message)

func verify() -> void:
	var player := Player.new()
	root.add_child(player)
	player.set_process(false)
	player.set_physics_process(false)
	var body: Node3D = player.body
	var arrays: Array = body.first_mesh.mesh.surface_get_arrays(0)
	var bones: PackedInt32Array = arrays[Mesh.ARRAY_BONES]
	var weights: PackedFloat32Array = arrays[Mesh.ARRAY_WEIGHTS]
	var skin: Skin = body.first_mesh.skin
	var left := 0
	var right := 0
	var torso := 0
	for i in bones.size():
		if weights[i] < 0.1:
			continue
		var name := String(skin.get_bind_name(bones[i]))
		if "LeftArm" in name or "LeftForeArm" in name or "LeftHand" in name: left += 1
		if "RightArm" in name or "RightForeArm" in name or "RightHand" in name: right += 1
		if "Spine" in name: torso += 1
	check(left > 300 and right > 300 and torso > 300, "first person contains both complete arms and torso")
	check(body.first_mesh.mesh.get_surface_count() == 3, "neck closure and equipment are present")
	var closure: Array = body.first_mesh.mesh.surface_get_arrays(1)
	check(closure[Mesh.ARRAY_VERTEX][0].y > 1.6, "closure is at neck, not across waist")
	var scenarios := [
		["idle", Vector3.ZERO, false, false],
		["walk", Vector3(0,0,-2.2), false, false],
		["sprint", Vector3(0,0,-4.0), false, false],
		["backward", Vector3(0,0,2.2), false, false],
		["left", Vector3(-2.2,0,0), false, false],
		["right", Vector3(2.2,0,0), false, false],
		["crouch", Vector3(0,0,-1.05), true, false],
		["tread", Vector3.ZERO, false, true],
		["swim", Vector3(0,0,-1.5), false, true]]
	var observed := [0, 8, 9, 20, 21, 31, 32, 37, 38]
	for scenario in scenarios:
		body.reset(0.0)
		for frame in 40:
			body.update_body(1.0/60.0, Vector3.ZERO, 0.0, scenario[1], scenario[2], scenario[3], true)
		var initial: Array[Quaternion] = []
		for bone in observed:
			initial.append(body.skeleton.get_bone_pose_rotation(bone))
		var maximum := 0.0
		var maximum_eye_step := 0.0
		var last_eye: Vector3 = body.first_person_eye(0.0)
		for frame in 75:
			body.update_body(1.0/60.0, Vector3.ZERO, 0.0, scenario[1], scenario[2], scenario[3], true)
			for i in observed.size():
				maximum = maxf(maximum, initial[i].angle_to(body.skeleton.get_bone_pose_rotation(observed[i])))
			var eye: Vector3 = body.first_person_eye(0.0)
			maximum_eye_step = maxf(maximum_eye_step, eye.distance_to(last_eye))
			last_eye = eye
		check(maximum > (0.001 if scenario[0] == "idle" else 0.03), "%s bones move over time (%.3f rad)" % [scenario[0], maximum])
		check(maximum_eye_step < 0.20, "%s eye follows pose continuously" % scenario[0])
		check(body.first_mesh.visible, "%s keeps complete first-person body visible" % scenario[0])
	# Zvednutí musí skutečně hýbat kostmi a zase vrátit řízení základnímu pohybu.
	body.reset(0.0)
	for frame in 90:
		body.update_body(1.0/60.0, Vector3.ZERO, 0.0, Vector3.ZERO, false, false, true)
	check(body.pick_up(), "pickup starts")
	var hand_before: Quaternion = body.skeleton.get_bone_pose_rotation(9)
	var changed := 0.0
	for frame in 180:
		body.update_body(1.0/60.0, Vector3.ZERO, 0.0, Vector3.ZERO, false, false, true)
		changed = maxf(changed, hand_before.angle_to(body.skeleton.get_bone_pose_rotation(9)))
	check(changed > 0.1, "pickup actually animates hand")
	for frame in 60:
		body.update_body(1.0/60.0, Vector3.ZERO, 0.0, Vector3(0,0,-2.2), false, false, true)
	check(not bool(body.tree.get("parameters/pickup/active")), "moving cancels pickup once and resumes locomotion")
	# Boční sprintové klipy se nesmějí spouštět při obyčejném A/D ani jen
	# kvůli setrvačnosti. Přechod po uvolnění Shift musí skončit běžnou chůzí.
	for side in [-1.0, 1.0]:
		body.reset(0.0)
		for frame in 45:
			body.update_body(1.0/60.0, Vector3.ZERO, 0.0, Vector3(side*2.2,0,0), false, false, true, false, false)
		check(not body.using_sprint_strafe and absf(body.direction.x) < 0.001, "ordinary side walking excludes sprint strafe")
		for frame in 45:
			body.update_body(1.0/60.0, Vector3.ZERO, 0.0, Vector3(side*4.0,0,0), false, false, true, true, false)
		check(body.using_sprint_strafe and body.direction.x * side > 0.99, "side sprint selects correct strafe clip")
		var leg: Quaternion = body.skeleton.get_bone_pose_rotation(31)
		var strafe_motion := 0.0
		for frame in 30:
			body.update_body(1.0/60.0, Vector3.ZERO, 0.0, Vector3(side*4.0,0,0), false, false, true, true, false)
			strafe_motion = maxf(strafe_motion, leg.angle_to(body.skeleton.get_bone_pose_rotation(31)))
		check(strafe_motion > 0.1, "sprint strafe actually animates leg")
		for frame in 30:
			body.update_body(1.0/60.0, Vector3.ZERO, 0.0, Vector3(side*4.0,0,0), false, false, true, false, false)
		check(not body.using_sprint_strafe and absf(body.direction.x) < 0.001, "releasing side-sprint input returns to walking despite residual speed")
	body.reset(0.37)
	for frame in 180:
		body.update_body(1.0/60.0, Vector3.ZERO, 0.37+TAU*frame/180.0, Vector3.ZERO, false, false, true, false, true)
	check(absf(wrapf(body.body_yaw-0.37, -PI, PI)) < 0.00001, "idle full orbit leaves character facing unchanged")
	for frame in 60:
		body.update_body(1.0/60.0, Vector3.ZERO, PI/2, Vector3(-2.2,0,0), false, false, true, false, true)
	check(absf(wrapf(body.body_yaw-PI/2, -PI, PI)) < 0.001 and absf(body.direction.x) < 0.001, "third-person walking faces movement using normal walking clip")
	var stopped_facing: float = body.body_yaw
	for frame in 60:
		body.update_body(1.0/60.0, Vector3.ZERO, -PI/2, Vector3.ZERO, false, false, true, false, true)
	check(absf(wrapf(body.body_yaw-stopped_facing, -PI, PI)) < 0.00001, "idle orbit preserves last movement facing")
	for frame in 60:
		body.update_body(1.0/60.0, Vector3.ZERO, -PI/2, Vector3.ZERO, false, false, true, false, false)
	check(absf(wrapf(body.body_yaw+PI/2, -PI, PI)) < 0.001, "first-person facing continues to follow mouse")
	body.reset(0.0)
	body.start_jump(3.7, 11.5)
	var leg_before: Quaternion = body.skeleton.get_bone_pose_rotation(31)
	var jump_motion := 0.0
	for frame in 30:
		body.update_body(1.0/60.0, Vector3.ZERO, 0.0, Vector3.ZERO, false, false, true)
		jump_motion = maxf(jump_motion, leg_before.angle_to(body.skeleton.get_bone_pose_rotation(31)))
	check(body.jump_airborne and bool(body.tree.get("parameters/jumping/active")) and jump_motion > 0.1, "jump action animates leg during flight")
	for frame in 120:
		body.update_body(1.0/60.0, Vector3.ZERO, 0.0, Vector3.ZERO, false, false, true)
	check(bool(body.tree.get("parameters/jumping/active")), "long fall holds airborne pose until physical landing")
	body.land_jump()
	for frame in 45:
		body.update_body(1.0/60.0, Vector3.ZERO, 0.0, Vector3.ZERO, false, false, true)
	check(not body.jump_airborne and not bool(body.tree.get("parameters/jumping/active")), "physical landing completes jump recovery")
	body.reset(0.0)
	check(body.turn_to(PI/2), "stationary turn starts")
	var turn_before: Quaternion = body.skeleton.get_bone_pose_rotation(31)
	var turn_motion := 0.0
	for frame in 80:
		body.update_body(1.0/60.0, Vector3.ZERO, PI/2, Vector3.ZERO, false, false, true, false, true)
		turn_motion = maxf(turn_motion, turn_before.angle_to(body.skeleton.get_bone_pose_rotation(31)))
	check(absf(body.body_yaw-PI/2) < 0.001 and turn_motion > 0.05, "turn reaches camera heading with animated footwork")
	check(body.turn_to(-PI/2), "second turn starts")
	for frame in 40:
		body.update_body(1.0/60.0, Vector3.ZERO, 0.0, Vector3(0,0,-2.2), false, false, true, false, true)
	check(not bool(body.tree.get("parameters/turning/active")) and absf(wrapf(body.body_yaw,-PI,PI))<0.001, "walking interrupts turn and resumes movement facing")
	body.start_jump(3.7, 11.5)
	body.update_body(0.1, Vector3.ZERO, 0.0, Vector3.ZERO, false, false, true)
	body.reset(0.0)
	check(not body.jump_airborne and not bool(body.tree.get("parameters/jumping/active")) and not bool(body.tree.get("parameters/turning/active")), "reset aborts all transient actions")
	verify_first_person_turn(body)
	player.free()
	print("BODY REGRESSION FINISHED failures=", failures)
	quit(1 if failures else 0)

func verify_first_person_turn(body: Node3D) -> void:
	# Držet otáčení déle než několik délek klipu, v obou směrech a přes ±PI.
	for fps in [30, 60, 144]:
		var dt: float = 1.0 / fps
		for side in [-1.0, 1.0]:
			body.reset(0.0)
			var yaw := 0.0
			var sample := Quaternion.IDENTITY
			var late_motion := 0.0
			var previous := Quaternion.IDENTITY
			var max_step := 0.0
			for frame in fps * 4:
				yaw = wrapf((frame+1)*dt*1.5*side, -PI, PI)
				body.update_body(dt, Vector3.ZERO, yaw, Vector3.ZERO, false, false, true)
				var leg: Quaternion = body.skeleton.get_bone_pose_rotation(31)
				if frame == fps * 2: sample = leg
				if frame > fps * 2:
					late_motion = maxf(late_motion, sample.angle_to(leg))
					max_step = maxf(max_step, previous.angle_to(leg))
				previous = leg
			check(body.first_person_turn_amount > 0.95 and late_motion > 0.08, "FP mouse turn keeps stepping at %d FPS, direction %+.0f (%.3f rad)" % [fps,side,late_motion])
			check(max_step < 0.35, "loop and angle wrap remain continuous at %d FPS" % fps)
			for frame in fps:
				body.update_body(dt, Vector3.ZERO, yaw, Vector3.ZERO, false, false, true)
			check(body.first_person_turn_amount < 0.001, "stopping mouse smoothly returns to idle at %d FPS" % fps)
	for state in ["orbit", "walking", "crouch", "swim", "airborne"]:
		body.reset(0.0)
		for frame in 90:
			body.update_body(1.0/60.0, Vector3.ZERO, frame*0.025, Vector3(0,0,-2.2) if state=="walking" else Vector3.ZERO, state=="crouch", state=="swim", true, false, state=="orbit", state!="airborne")
		check(body.first_person_turn_amount < 0.001, "FP stepping excluded during "+state)
	body.reset(0.0)
	for frame in 90:
		body.update_body(1.0/60.0, Vector3.ZERO, 0.00001 if frame%2 else -0.00001, Vector3.ZERO, false, false, true)
	check(body.first_person_turn_amount < 0.001, "tiny mouse jitter does not trigger stepping")
