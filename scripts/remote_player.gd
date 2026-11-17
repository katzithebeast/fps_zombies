extends Node3D
## Vzdálená postava nemá vlastní kameru ani vstup. 100 ms buffer vyhlazuje síťové snímky.
const BodyScript := preload("res://scripts/player_body.gd")
const Net := preload("res://scripts/network_session.gd")
var body: Node3D
var _samples: Array = []
var _actions: Array = []
var _has_state := false
var last_state: Array = []

func _ready() -> void:
	physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	body = BodyScript.new()
	add_child(body)
	body.skeleton.get_node("ScientistBody").layers = 16
	body.first_mesh.layers = 0
	body.first_mesh.visible = false
	body.weapon.set_remote_layers()
	body.visible = false

func set_display_name(value: String) -> void:
	var label := Label3D.new()
	label.text = value
	label.position.y = 2.0
	label.font_size = 38
	label.pixel_size = 0.0025
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.modulate = Color(0.6, 0.95, 1.0)
	label.layers = 16
	add_child(label)

func push_state(state: Array) -> void:
	last_state = state
	_samples.append({"time": Time.get_ticks_msec() / 1000.0, "state": state})
	while _samples.size() > 12: _samples.pop_front()
	if not _has_state:
		_has_state = true
		global_position = state[1]
		body.reset(state[6])
		for action in _actions: play_action(action[0], action[1])
		_actions.clear()

func play_action(kind: String, data: Array) -> void:
	if not _has_state:
		if _actions.size() < 12: _actions.append([kind, data])
		return
	match kind:
		"jump": body.start_jump(data[0], data[1])
		"land": body.land_jump()
		"turn": body.turn_to(data[0])
		"pickup": body.pick_up(data[0], true)
		"shot": body.weapon.kick()
		"reload": body.weapon.begin_reload()

func _process(dt: float) -> void:
	if not _has_state: return
	var target := Time.get_ticks_msec() / 1000.0 - 0.10
	while _samples.size() > 2 and float(_samples[1].time) <= target:
		_samples.pop_front()
	var a: Array = _samples[0].state
	var b: Array = _samples[-1].state
	var factor := 1.0
	if _samples.size() > 1:
		factor = clampf((target - float(_samples[0].time)) / maxf(float(_samples[-1].time) - float(_samples[0].time), 0.001), 0.0, 1.0)
	var position_now: Vector3 = a[1].lerp(b[1], factor)
	var velocity_now: Vector3 = a[2].lerp(b[2], factor)
	# Zpoždění krátce překlenout rychlostí, při delším výpadku postavu zastavit.
	var extra := clampf(target - float(_samples[-1].time), 0.0, 0.10)
	position_now += velocity_now * extra
	if target - float(_samples[-1].time) > 1.0: velocity_now = Vector3.ZERO
	var look_yaw := lerp_angle(float(a[3]), float(b[3]), factor)
	var facing := lerp_angle(float(a[6]), float(b[6]), factor)
	var flags: int = b[5] if factor > 0.5 else a[5]
	global_position = position_now
	body.weapon.equipped=bool(flags & Net.FLAG_ARMED)
	body.weapon.aim=lerpf(body.weapon.aim,1.0 if flags & Net.FLAG_AIM else 0.0,1.0-exp(-14.0*dt))
	body.weapon.pitch=lerpf(float(a[4]),float(b[4]),factor)
	body.update_body(dt, position_now, look_yaw, velocity_now, bool(flags & Net.FLAG_CROUCH), bool(flags & Net.FLAG_SWIM), true, bool(flags & Net.FLAG_STRAFE), bool(flags & Net.FLAG_ORBIT), bool(flags & Net.FLAG_GROUNDED))
	# Směr dodává vlastník postavy, i když právě orbituje kamerou nebo se otáčí na R.
	body.body_yaw = facing
	body.rotation.y = facing + PI
	body.first_mesh.visible = false
