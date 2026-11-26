extends Node3D
## Bažinák (alfa bažiny): hýbe se, jen když se na něj hráč nedívá.
## Model nemá kostru – je to „socha“ v jedné póze. Dokud je v záběru, není ničím zakrytý a svítí na něj
## baterka (nebo blesk, nebo je hodně blízko), stojí nehybně. Jinak se plíží k hráči, čvachtá ve vodě
## a je pokaždé o kus blíž a natočený jinak. U hráče udeří, ponoří se a vynoří se jinde.
## Střelba ho zraní; po každé ztracené třetině zdraví uteče pod hladinu. Zabitý padne do bahna.

const MODEL := "res://assets/swamp/models/swamp_monster.glb"
const HEIGHT := 2.5
const SPEED := 4.2               # m/s, když se nikdo nedívá
const MAX_HP := 2400.0

signal died(pos: Vector3)

var enabled := true               # režisér misí ho zapíná jen v honu na alfu (nebo vzácně jako bonus)
var main: Node3D
var waves: Node
var player: CharacterBody3D
var hp := MAX_HP
var state := "hidden"            # hidden | stalk | sink | dead
var _t := 30.0                   # odpočet do vynoření
var _model: Node3D
var _area: Area3D
var _seen := false
var _was_seen := false
var _step_t := 0.0
var _sink := 0.0
var _phase := 0                  # kolikrát už utekl (po třetinách zdraví)
var _path: PackedVector3Array = []
var _path_i := 0
var _repath := 0.0
var _stinger_cd := 0.0
var _steps := []

func setup(m: Node3D, w: Node) -> void:
	main = m
	waves = w
	player = m.player
	_model = (load(MODEL) as PackedScene).instantiate()
	add_child(_model)
	# výška a pata modelu (v souřadnicích bažináka; model ze Sketchfabu má otočené uzly)
	var inv := global_transform.affine_inverse()
	var bb := AABB()
	var first := true
	for mi in _model.find_children("*", "MeshInstance3D", true, false):
		var mm := mi as MeshInstance3D
		var b: AABB = (inv * mm.global_transform) * mm.get_aabb()
		bb = b if first else bb.merge(b)
		first = false
		for si in mm.mesh.get_surface_count():
			var mat := mm.mesh.surface_get_material(si)
			if mat is BaseMaterial3D:
				(mat as BaseMaterial3D).roughness = 0.32      # mokrý sliz
	var k := HEIGHT / maxf(bb.size.y, 0.01)
	_model.scale = Vector3.ONE * k
	_model.position = Vector3(-bb.get_center().x * k, -bb.position.y * k, -bb.get_center().z * k)
	_base_k = _model.position.y
	# zásahová oblast (střely z hry ji najdou: vrstva 32, meta "alpha")
	_area = Area3D.new()
	_area.collision_layer = 32
	_area.collision_mask = 0
	_area.set_meta("alpha", self)
	var cs := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.55
	cap.height = HEIGHT
	cs.shape = cap
	cs.position.y = HEIGHT * 0.5
	_area.add_child(cs)
	add_child(_area)
	for i in range(1, 7): _steps.append(load("res://audio/step_water_%d.wav" % i))
	visible = false
	_area.collision_layer = 0
	_t = randf_range(45.0, 70.0)
	if OS.get_environment("SWAMP_ALPHA_T") != "": _t = float(OS.get_environment("SWAMP_ALPHA_T"))     # test

## Hon na alfu: vynoří se dřív.
func hunt() -> void:
	_t = randf_range(20.0, 35.0)

func reset() -> void:
	hp = MAX_HP
	_phase = 0
	state = "hidden"
	visible = false
	_area.collision_layer = 0
	_t = randf_range(45.0, 70.0)

# ------------------------------------------------------------------ vidí ho hráč?

func _watched() -> bool:
	var cam: Camera3D = player.camera
	var eye := cam.global_position
	var d := eye.distance_to(global_position)
	var chest := global_position + Vector3.UP * HEIGHT * 0.6
	var head := global_position + Vector3.UP * HEIGHT * 0.92
	if not (cam.is_position_in_frustum(chest) or cam.is_position_in_frustum(head)): return false
	# zakrytý stromem / kamenem?
	var q := PhysicsRayQueryParameters3D.create(eye, chest, 1)
	q.exclude = [player.get_rid()]
	if not main.get_world_3d().direct_space_state.intersect_ray(q).is_empty(): return false
	if d < 4.5: return true                       # takhle blízko ho vidíš i ve tmě
	if main._flash_t >= 0.0: return true          # blesk
	var fl: SpotLight3D = main.flashlight
	if fl and fl.visible and d < fl.spot_range:
		var to := (chest - fl.global_position).normalized()
		if to.dot(-fl.global_basis.z) > cos(deg_to_rad(fl.spot_angle * 0.85)): return true
	return false

# ------------------------------------------------------------------ chování

func _process(dt: float) -> void:
	if player == null or (state == "dead" and _sink >= 1.0): return
	_stinger_cd = maxf(0.0, _stinger_cd - dt)
	match state:
		"hidden":
			if not enabled or waves._dead or not waves._nav_ready: return
			_t -= dt
			if _t <= 0.0: _emerge()
		"stalk":
			_stalk(dt)
		"sink":
			_sink = minf(1.0, _sink + dt * 0.7)
			_model.position.y = _base_y() - _sink * HEIGHT * 1.05
			if _sink >= 1.0:
				state = "hidden"
				visible = false
				_t = randf_range(25.0, 50.0)
		"dead":
			_sink = minf(1.0, _sink + dt * 0.25)
			rotation.x = lerpf(rotation.x, -1.35, dt * 1.5)
			_model.position.y = _base_y() - _sink * 0.9

var _base_k := 0.0

func _base_y() -> float:
	return _base_k

func _emerge() -> void:
	# vynoří se ve tmě za hráčem (mimo záběr), na vodě nebo v rákosí
	var map: RID = main.get_world_3d().navigation_map
	var here := player.global_position
	var look: Vector3 = -player.camera.global_basis.z
	for attempt in 20:
		var a := randf() * TAU
		var p := here + Vector3(cos(a), 0.0, sin(a)) * randf_range(22.0, 32.0)
		if absf(p.x) > main.R - main.WALL - 1.5 or absf(p.z) > main.R - main.WALL - 1.5: continue
		var dir := (p - here).normalized()
		if dir.dot(Vector3(look.x, 0, look.z).normalized()) > -0.2 and attempt < 15: continue
		p.y = main.ground(p.x, p.z)
		var q := NavigationServer3D.map_get_closest_point(map, p)
		if q.distance_to(p) > 3.0: continue
		global_position = q
		_model.position.y = _base_k
		_sink = 0.0
		rotation = Vector3(0, atan2(here.x - q.x, here.z - q.z), 0)
		visible = true
		_area.collision_layer = 32
		state = "stalk"
		_path = []
		return

func _stalk(dt: float) -> void:
	_seen = _watched()
	var to_player := player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	if _seen:
		# zamrzne; když ho hráč najednou uvidí zblízka, ozve se úlek
		if not _was_seen and dist < 12.0 and _stinger_cd <= 0.0:
			main.sfx.play("stinger", -6.0 if dist > 7.0 else -1.0)
			_stinger_cd = 8.0
		_was_seen = true
		return
	if _was_seen:
		# jen co se hráč otočí: jiné natočení a zrcadlení (pokaždé vypadá trochu jinak)
		_model.scale.x = absf(_model.scale.x) * (-1.0 if randf() < 0.5 else 1.0)
	_was_seen = false
	if dist < 1.7:
		_strike()
		return
	# po navigační síti k hráči
	_repath -= dt
	if _repath <= 0.0 or _path_i >= _path.size():
		_repath = 0.5
		_path = NavigationServer3D.map_get_path(main.get_world_3d().navigation_map, global_position, player.global_position, true)
		_path_i = 1
	var target := player.global_position
	if _path_i < _path.size():
		target = _path[_path_i]
		if Vector2(target.x - global_position.x, target.z - global_position.z).length() < 0.4: _path_i += 1
	var step := (target - global_position)
	step.y = 0.0
	if step.length() > 0.001:
		var mv := step.normalized() * minf(step.length(), SPEED * dt)
		global_position += mv
		global_position.y = main.ground(global_position.x, global_position.z)
		rotation.y = atan2(to_player.x, to_player.z) + randf_range(-0.05, 0.05)
	# čvachtání, když se blíží
	_step_t -= dt
	if _step_t <= 0.0 and dist < 22.0:
		_step_t = randf_range(0.35, 0.6)
		var a := AudioStreamPlayer3D.new()
		a.stream = _steps.pick_random()
		a.pitch_scale = randf_range(0.6, 0.75)
		a.volume_db = -2.0
		a.unit_size = 4.0
		main.add_child(a)
		a.global_position = global_position
		a.play()
		a.finished.connect(a.queue_free)
		if main.sim: main.sim.add_impulse(Vector2(global_position.x, global_position.z), 0.5, -1.2)

func _strike() -> void:
	main.sfx.play("scare", 0.0)
	waves.hurt(45.0, self)
	_go_under()

func _go_under() -> void:
	state = "sink"
	_area.collision_layer = 0
	main.sfx.play_at("splash_big", global_position, -3.0, 0.7)
	if main.sim: main.sim.add_impulse(Vector2(global_position.x, global_position.z), 0.9, -2.0)

## Zásah střelou (swamp_waves._fired).
func shot(point: Vector3, direction: Vector3, damage: float) -> void:
	if state != "stalk": return
	hp -= damage
	waves._fx.blood(point, direction, false)
	main.sfx.play_at("hit_flesh", point, -2.0, 0.7)
	if hp <= 0.0:
		state = "dead"
		_sink = 0.0
		_area.collision_layer = 0
		main.sfx.play("round_end", -2.0)
		main._say("Bažinák je mrtvý.")
		died.emit(global_position)
		return
	var phase := int((1.0 - hp / MAX_HP) * 3.0)
	if phase > _phase:
		_phase = phase
		main._say("Bažinák utekl pod hladinu…")
		_go_under()
