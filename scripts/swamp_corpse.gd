extends Node3D
## Mrtvý voják s ragdollem (model z Blenderu: tools v /tmp/rig/ragdoll.py, kosti hips…foot.R).
## Spadne do bahna pokaždé trochu jinak a po zásahu sebou cukne. Fyzikální kosti: vrstva 64
## (zasáhne je střela), maska 1 (terén, kmeny, bunkr).

const MODEL := "res://assets/swamp/models/soldier_ragdoll.glb"
# [kost, koncová kost (nebo délka), poloměr, hmotnost]
const PARTS := [
	["hips", "spine", 0.15, 12.0], ["spine", "chest", 0.14, 9.0], ["chest", "neck", 0.16, 13.0],
	["head", 0.24, 0.11, 4.5],
	["upperarm.L", "forearm.L", 0.065, 2.8], ["forearm.L", "hand.L", 0.055, 1.8],
	["upperarm.R", "forearm.R", 0.065, 2.8], ["forearm.R", "hand.R", 0.055, 1.8],
	["thigh.L", "shin.L", 0.085, 7.0], ["shin.L", "foot.L", 0.065, 4.0],
	["thigh.R", "shin.R", 0.085, 7.0], ["shin.R", "foot.R", 0.065, 4.0],
]

const HINGE_FLIP := false      # kdyby se kolena ohýbala dopředu

var skeleton: Skeleton3D
var sim: PhysicalBoneSimulator3D
var bodies := {}            # jméno kosti -> PhysicalBone3D

## pose: 0 = na zádech, 1 = na břiše, 2 = na boku. Uzel musí být ve stromu a na místě (nad zemí).
func setup(pose: int, rng: RandomNumberGenerator) -> void:
	add_to_group("swamp_corpse")
	var m: Node3D = (load(MODEL) as PackedScene).instantiate()
	add_child(m)
	skeleton = m.find_children("*", "Skeleton3D", true, false)[0]
	match pose:
		0: rotation = Vector3(-PI * 0.5, rotation.y, 0)
		1: rotation = Vector3(PI * 0.5, rotation.y, 0)
		_: rotation = Vector3(0, rotation.y, PI * 0.5 * (1.0 if rng.randf() < 0.5 else -1.0))
	# ruce a nohy trochu jinak, ať každé tělo dopadne jinak
	for b in ["upperarm.L", "upperarm.R", "thigh.L", "thigh.R", "head"]:
		var i := skeleton.find_bone(b)
		var q := Quaternion(Vector3(rng.randf_range(-1, 1), rng.randf_range(-1, 1), rng.randf_range(-1, 1)).normalized(), rng.randf_range(0.1, 0.6))
		skeleton.set_bone_pose_rotation(i, skeleton.get_bone_pose_rotation(i) * q)
	sim = PhysicalBoneSimulator3D.new()
	skeleton.add_child(sim)
	for p in PARTS: _part(p[0], p[1], p[2], p[3])
	for n in bodies:
		var parent := _phys_parent(n)
		if parent != "":
			bodies[n].add_collision_exception_with(bodies[parent])
			bodies[parent].add_collision_exception_with(bodies[n])
	sim.physical_bones_start_simulation()

func _phys_parent(n: String) -> String:
	var i := skeleton.get_bone_parent(skeleton.find_bone(n))
	while i >= 0:
		var pn := skeleton.get_bone_name(i)
		if bodies.has(pn): return pn
		i = skeleton.get_bone_parent(i)
	return ""

func _part(bone_name: String, end, radius: float, mass: float) -> void:
	var bone := skeleton.find_bone(bone_name)
	if bone < 0: return
	var rest := skeleton.get_bone_global_rest(bone)
	var to_end: Vector3
	if end is String:
		to_end = rest.affine_inverse() * skeleton.get_bone_global_rest(skeleton.find_bone(end)).origin
	else:
		to_end = rest.basis.inverse() * (Vector3.UP * float(end))
	var length := to_end.length()
	var offset := Transform3D(Basis(Quaternion(Vector3.UP, to_end.normalized())), to_end * 0.5)
	var shape := CapsuleShape3D.new()
	shape.radius = radius
	shape.height = maxf(length + radius * 0.6, radius * 2.0 + 0.01)
	var body := PhysicalBone3D.new()
	body.name = "Phys_" + bone_name.replace(".", "_")
	sim.add_child(body)
	body.bone_name = bone_name
	body.body_offset = offset
	body.joint_offset = offset.affine_inverse()
	body.mass = mass
	body.friction = 0.95
	body.bounce = 0.0
	body.linear_damp = 0.6          # bahno: pohyb rychle utlumí
	body.angular_damp = 1.6
	body.collision_layer = 64
	body.collision_mask = 1
	body.set_meta("corpse", self)
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	bodies[bone_name] = body
	_joint(body, bone_name)

func _joint(body: PhysicalBone3D, part: String) -> void:
	body.joint_type = PhysicalBone3D.JOINT_TYPE_NONE
	if part == "hips": return
	var frame := body.body_offset.affine_inverse()
	frame.basis = body.body_offset.basis.inverse() * Basis(Vector3.FORWARD, PI / 2)
	body.joint_offset = frame
	if part.begins_with("forearm") or part.begins_with("shin"):
		# pant: koleno a loket se ohýbají jen jedním směrem
		var leg := part.begins_with("shin")
		var bone := skeleton.find_bone(part)
		var rest := skeleton.get_bone_global_rest(bone)
		var dir := (rest.origin - skeleton.get_bone_global_rest(skeleton.get_bone_parent(bone)).origin).normalized()
		var axis_skel := Vector3.RIGHT if leg else dir.cross(Vector3.BACK).normalized()
		var axis_local := (rest.basis.inverse() * axis_skel).normalized()
		frame.basis = body.body_offset.basis.inverse() * Basis(Quaternion(Vector3.BACK, axis_local))
		body.joint_offset = frame
		body.joint_type = PhysicalBone3D.JOINT_TYPE_HINGE
		body.set("joint_constraints/angular_limit_enabled", true)
		var lo := -(110.0 if leg else 125.0)
		if HINGE_FLIP: body.set("joint_constraints/angular_limit_lower", -4.0); body.set("joint_constraints/angular_limit_upper", -lo)
		else: body.set("joint_constraints/angular_limit_lower", lo); body.set("joint_constraints/angular_limit_upper", 4.0)
		return
	body.joint_type = PhysicalBone3D.JOINT_TYPE_CONE
	var swing := 45.0
	var twist := 20.0
	if part in ["spine", "chest"]: swing = 16.0; twist = 10.0
	elif part == "head": swing = 30.0; twist = 30.0
	elif part.begins_with("thigh"): swing = 45.0; twist = 15.0
	elif part.begins_with("upperarm"): swing = 70.0; twist = 30.0
	body.set("joint_constraints/swing_span", swing)
	body.set("joint_constraints/twist_span", twist)

## Zásah střelou: tělo sebou cukne.
func shot(body: PhysicalBone3D, point: Vector3, direction: Vector3, strength := 1.0) -> void:
	body.apply_impulse(direction * 9.0 * strength, point - body.global_position)

## Pánev (pro teleporty, diktafon…).
func center() -> Vector3:
	return bodies["hips"].global_position if bodies.has("hips") else global_position

var _dbg_t := 0.0
func _physics_process(dt: float) -> void:
	if OS.get_environment("SWAMP_CORPSE_DEBUG") != "1": return
	_dbg_t += dt
	if absf(_dbg_t - 3.0) < dt * 0.5 and OS.get_environment("SWAMP_CORPSE_KICK") == "1":
		var fr: Vector3 = (skeleton.global_transform.basis * skeleton.get_bone_global_pose(0).basis * Vector3.BACK).normalized()
		bodies["shin.L"].apply_central_impulse(-fr * 25.0 + Vector3.UP * 10.0)
		bodies["forearm.R"].apply_central_impulse(Vector3.UP * 12.0)
	if absf(_dbg_t - 6.0) < dt * 0.5:
		var s := ""
		for n in ["hips", "head", "shin.L", "forearm.R"]:
			var p: Vector3 = bodies[n].global_position
			s += "%s %.2f  " % [n, p.y - get_parent().ground(p.x, p.z)]
		var front: Vector3 = bodies["hips"].global_basis.z
		for side in ["L", "R"]:
			var t: Vector3 = bodies["thigh." + side].global_basis.y
			var sh: Vector3 = bodies["shin." + side].global_basis.y
			var perp := sh - t * sh.dot(t)
			s += " koleno%s ohyb %d° směr %.2f" % [side, int(rad_to_deg(t.angle_to(sh))), perp.normalized().dot(front)]
		var ua: Vector3 = bodies["upperarm.R"].global_basis.y
		var fa: Vector3 = bodies["forearm.R"].global_basis.y
		s += " loket %d°" % int(rad_to_deg(ua.angle_to(fa)))
		print("TĚLO nad zemí: ", s, " rychlost ", snappedf(bodies["hips"].linear_velocity.length(), 0.01))
