class_name Player
extends CharacterBody3D
## Pohyb z první osoby: chůze, brodění, plavání (vztlak), plazení, skok.
## Kamera NENÍ potomek fyzikálního těla. Každý vykreslený snímek se staví
## z interpolované pozice těla, takže se neseká při žádném FPS, a myš se
## aplikuje okamžitě (bez čekání na fyzikální tik).

signal footstep(kind: String, strength: float)     # "tile" | "water" | "swim"
signal splashed(strength: float)
signal interact_requested

const WATER_Y := 0.0
static var water_at: Callable       # hladina podle místa (vypuštěné bazény, nádrž)
var water_y := 0.0
const R := 0.3
const H_STAND := 1.75
const H_CROUCH := 0.78
const EYE_STAND := 1.64
const EYE_CROUCH := 0.6
const WALK := 2.2
const SPRINT := 4.0
const CROUCH_SPEED := 1.05
const SWIM := 1.5
const SWIM_FAST := 2.2
const GRAVITY := 11.5
const MOUSE_SENS := 0.0021
const BodyScript := preload("res://scripts/player_body.gd")

var sim: WaterSim
var head: Node3D
var camera: Camera3D
var control_enabled := true
var input_suspended := false       # multiplayer menu nepozastavuje svět ani síť
var interaction_locked := false
var sprint_lock := false               # střelba a míření ruší sprint
var handheld := 0.0            # 0..1 síla "ruční kamery" (VHS / fisheye režim ji zvedá)
var base_fov := 75.0
var auto_walk := Vector2.ZERO  # jen pro testy
var mouse_scale := 1.0
var bob_scale := 1.0
var aim_sway := 0.1        # nastavení: kolik houpání zůstane při míření / drženém R (0 = žádné)
var steady := 0.0          # 0..1, nastavuje zbraň (míření, držené R, přebíjení)
var shake_scale := 1.0
var motion_scale := 0.65       # pružná kamera reagující na pohyb těla (0 = vypnuto)
var body: Node3D
var weapon: Node
var third_person := false
var shoulder_distance := 2.8
var shoulder_offset := 0.5
var shoulder_height := 1.45
var shoulder_side := 1.0
var shoulder_fov := 70.0
var shoulder_smoothing := 0.55
var camera_eye_height := EYE_STAND
var camera_uses_third_person := false
var _boom_length := 3.0
var _headroom := 3.0
var _shoulder_pivot_height := 1.45
var _camera_probe := SphereShape3D.new()

var yaw := 0.0
var pitch := 0.0
var crouching := false
var swimming := false
var submersion := 0.0          # jak hluboko jsou chodidla pod hladinou (m)

var _yaw_s := 0.0
var _pitch_s := 0.0
var _eye := EYE_STAND
var _bob_phase := 0.0
var _bob_amt := 0.0
var _step_acc := 0.0
var _roll := 0.0
var _land := 0.0
var _land_v := 0.0
var _climb_t := 0.0
var _was_on_floor := true
var _fall_speed := 0.0
var _time := 0.0
var _shape: CapsuleShape3D
var _col: CollisionShape3D
var _noise := FastNoiseLite.new()
var _input := Vector2.ZERO
var _sprint := false
var _wake_acc := 0.0
var _was_in_water := false
var _ctrl_crouch := false
var _last_velocity := Vector3.ZERO
var _acceleration := Vector3.ZERO
var _motion_angles := Vector3.ZERO
var _motion_velocity := Vector3.ZERO

func _ready() -> void:
	collision_layer = 2
	collision_mask = 1
	floor_snap_length = 0.3
	floor_max_angle = deg_to_rad(50.0)
	_shape = CapsuleShape3D.new()
	_shape.radius = R
	_shape.height = H_STAND
	_col = CollisionShape3D.new()
	_col.shape = _shape
	_col.position.y = H_STAND * 0.5
	add_child(_col)

	head = Node3D.new()
	head.top_level = true
	head.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	add_child(head)
	camera = Camera3D.new()
	camera.fov = base_fov
	camera.near = 0.04
	camera.far = 200.0
	camera.cull_mask = 0xFFFFF & ~4   # celé tělo jen do odrazů; vlastní pohled má oříznutou kopii
	camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	head.add_child(camera)
	camera.make_current()
	_camera_probe.radius = 0.18
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0
	_yaw_s = yaw
	_pitch_s = pitch
	body = BodyScript.new()
	body.top_level = true
	add_child(body)
	weapon=preload("res://scripts/player_weapon.gd").new()
	weapon.player=self
	add_child(weapon)

func teleport(pos: Vector3, new_yaw: float, new_pitch := 0.0) -> void:
	global_position = pos
	velocity = Vector3.ZERO
	yaw = new_yaw
	pitch = new_pitch
	_yaw_s = yaw
	_pitch_s = pitch
	_set_crouch(false, true)
	swimming = false
	_last_velocity = Vector3.ZERO
	_acceleration = Vector3.ZERO
	_motion_angles = Vector3.ZERO
	_motion_velocity = Vector3.ZERO
	_land = 0.0
	_land_v = 0.0
	_roll = 0.0
	_bob_amt = 0.0
	_bob_phase = 0.0
	_eye = EYE_STAND
	_headroom = 3.0
	_shoulder_pivot_height = shoulder_height
	_boom_length = shoulder_distance
	if body:
		body.reset(yaw)
	reset_physics_interpolation()

func _unhandled_input(event: InputEvent) -> void:
	if input_suspended:
		return
	if event is InputEventMouseMotion and Input.mouse_mode == Input.MOUSE_MODE_CAPTURED and control_enabled:
		yaw -= event.relative.x * MOUSE_SENS * mouse_scale
		pitch = clampf(pitch - event.relative.y * MOUSE_SENS * mouse_scale, -1.5, 1.5)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_C and control_enabled:
		if not swimming and not interaction_locked:
			_set_crouch(not crouching)
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_E and control_enabled:
		if not interaction_locked:
			interact_requested.emit()
	elif event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_R and control_enabled:
		if weapon.equipped:
			pass      # krátké R = přebít, držené R = kontrola zásobníku (player_weapon.gd)
		elif third_person and is_on_floor() and not crouching and not swimming and not interaction_locked:
			body.turn_to(yaw)

func _key(k: Key) -> bool:
	return Input.is_physical_key_pressed(k)

func _ground_y() -> float:
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0, 0.6, 0)
	var q := PhysicsRayQueryParameters3D.create(from, from + Vector3(0, -8.0, 0), 1)
	var hit := space.intersect_ray(q)
	return hit.position.y if hit else -100.0

func _can_stand() -> bool:
	var s := CapsuleShape3D.new()
	s.radius = R - 0.02
	s.height = H_STAND - 0.06
	var q := PhysicsShapeQueryParameters3D.new()
	q.shape = s
	q.collision_mask = 1
	q.transform = Transform3D(Basis(), global_position + Vector3(0, H_STAND * 0.5 + 0.04, 0))
	return get_world_3d().direct_space_state.intersect_shape(q, 1).is_empty()

func _set_crouch(v: bool, force := false) -> void:
	if v == crouching:
		return
	if not v and not force and not _can_stand():
		return
	crouching = v
	var h := H_CROUCH if v else H_STAND
	_shape.height = h
	_col.position.y = h * 0.5

func _physics_process(dt: float) -> void:
	var _perf_t0:=Time.get_ticks_usec()
	_physics_process_timed(dt)
	PerfMon.add("Hráč fyzika",Time.get_ticks_usec()-_perf_t0)

func _physics_process_timed(dt: float) -> void:
	_input = Vector2.ZERO
	_sprint = false
	if control_enabled and not input_suspended and not interaction_locked:
		_input = Vector2(float(_key(KEY_D)) - float(_key(KEY_A)), float(_key(KEY_W)) - float(_key(KEY_S)))
		_sprint = _key(KEY_SHIFT) and not sprint_lock
		# Ctrl = držet pro přikrčení, C = přepnout
		if _key(KEY_CTRL):
			if not crouching and not swimming:
				_set_crouch(true)
				_ctrl_crouch = true
		elif _ctrl_crouch:
			_set_crouch(false)
			_ctrl_crouch = crouching
	if auto_walk != Vector2.ZERO and not input_suspended:
		_input = auto_walk
	if interaction_locked:
		_input = Vector2.ZERO
		_sprint = false
	if _input.length() > 1.0:
		_input = _input.normalized()
	var wish := Basis(Vector3.UP, yaw) * Vector3(_input.x, 0.0, -_input.y)

	water_y = float(water_at.call(global_position)) if water_at.is_valid() else WATER_Y
	submersion = water_y - global_position.y
	var deep := (water_y - _ground_y()) > 1.3
	var was_swimming := swimming
	swimming = deep and submersion > (0.75 if was_swimming else 1.0)
	if swimming and crouching:
		_set_crouch(false, true)
	var on_floor := is_on_floor()
	var hv := Vector3(velocity.x, 0.0, velocity.z)

	if swimming:
		var sp := SWIM_FAST if _sprint else SWIM
		hv = hv.lerp(wish * sp, 1.0 - exp(-2.4 * dt))
		# vztlak: rovnováha, když jsou chodidla ~1.38 m pod hladinou
		velocity.y += (submersion - 1.38) * 16.0 * dt
		velocity.y *= exp(-3.2 * dt)
		# vylézání přes okraj bazénu
		if is_on_wall() and wish.length() > 0.3 and wish.dot(-get_wall_normal()) > 0.35:
			_climb_t = 0.12
	else:
		var sp := CROUCH_SPEED if crouching else (SPRINT if _sprint else WALK)
		if submersion > 0.03:
			sp *= 1.0 - clampf(submersion, 0.0, 1.1) * 0.42       # odpor vody při brodění
		var acc := 9.0 if on_floor else 2.0
		if submersion > 0.15:
			acc *= 0.6
		hv = hv.lerp(wish * sp, 1.0 - exp(-acc * dt))
		if not on_floor:
			var g := GRAVITY
			if submersion > 0.4:
				g *= 0.35
				velocity.y *= exp(-2.5 * dt)
			velocity.y -= g * dt
		elif control_enabled and not input_suspended and not interaction_locked and _key(KEY_SPACE) and not crouching:
			velocity.y = 3.7 * (1.0 - clampf(submersion, 0.0, 0.8) * 0.5)
			body.start_jump(velocity.y, GRAVITY)
	if _climb_t > 0.0:
		_climb_t -= dt
		if submersion > 0.3:
			velocity.y = maxf(velocity.y, 2.1)        # nohy ještě pod úrovní okraje: táhni se nahoru
		hv = hv.lerp(wish * 1.6, 0.3)
	velocity.x = hv.x
	velocity.z = hv.z
	if not on_floor:
		_fall_speed = minf(_fall_speed, velocity.y)
	move_and_slide()
	var ceiling_from := global_position + Vector3(0, 0.05, 0)
	var ceiling_query := PhysicsRayQueryParameters3D.create(ceiling_from, ceiling_from + Vector3(0, 2.25, 0), 1)
	var ceiling := get_world_3d().direct_space_state.intersect_ray(ceiling_query)
	_headroom = ceiling.position.y - global_position.y if ceiling else 3.0

	# --- dopad / šplouchnutí
	var now_floor := is_on_floor()
	if now_floor and not _was_on_floor:
		body.land_jump()
	if now_floor and not _was_on_floor and _fall_speed < -2.0:
		_land_v -= minf(-_fall_speed * 0.05, 0.35)
		footstep.emit("water" if submersion > 0.03 else "tile", 1.4)
		if submersion > 0.03 and sim:
			sim.add_impulse(_xz(), 0.35, -0.5)
	if now_floor:
		_fall_speed = 0.0
	_was_on_floor = now_floor
	var in_water := submersion > 0.45
	if in_water and not _was_in_water and velocity.y < -2.2:
		splashed.emit(clampf(-velocity.y / 5.0, 0.4, 1.5))
		if sim:
			sim.add_impulse(_xz(), 0.55, -1.6)
			sim.add_impulse(_xz(), 0.25, -1.2)
	_was_in_water = in_water

	# --- kroky a brázda ve vodě
	var speed := Vector2(velocity.x, velocity.z).length()
	if sim and submersion > 0.02 and submersion < 2.2:
		# průběžné rozrážení vody: síla roste s rychlostí a hloubkou ponoru
		var depth_k := clampf(submersion, 0.08, 1.0)
		var rad := 0.16 + 0.22 * clampf(submersion, 0.0, 1.0)
		var fwd := Vector2(velocity.x, velocity.z).normalized() if speed > 0.05 else Vector2.ZERO
		if speed > 0.15:
			sim.add_impulse(_xz() + fwd * rad * 0.9, rad, 0.060 * speed * depth_k)      # vlna před tělem
			sim.add_impulse(_xz() - fwd * rad * 0.6, rad, -0.075 * speed * depth_k)     # prohlubeň za ním
	if swimming and speed > 0.15:
		_step_acc += dt
		if _step_acc > 1.05:
			_step_acc = 0.0
			footstep.emit("swim", 1.0 if speed > 0.4 else 0.5)
			if sim:
				var side := Basis(Vector3.UP, yaw) * Vector3(0.45, 0, -0.3)
				sim.add_impulse(_xz() + Vector2(side.x, side.z), 0.22, -0.5)
				sim.add_impulse(_xz() + Vector2(-side.x, side.z), 0.22, -0.5)
	elif not swimming and now_floor and speed > 0.25:
		var step_len := 0.5 if crouching else (0.95 if _sprint else 0.72)
		_step_acc += speed * dt
		if _step_acc > step_len:
			_step_acc = 0.0
			var k := 0.5 if crouching else (1.2 if _sprint else 0.85)
			if submersion > 0.03:
				footstep.emit("water", k)
				if sim:
					var side := Basis(Vector3.UP, yaw) * Vector3(0.13 * (1.0 if randf() > 0.5 else -1.0), 0, 0)
					sim.add_impulse(_xz() + Vector2(side.x, side.z), 0.14, -0.55 * k)
			else:
				footstep.emit("tile", k)

func _xz() -> Vector2:
	return Vector2(global_position.x, global_position.z)

func _update_motion(target: Vector3, dt: float) -> void:
	# Přesné řešení kriticky tlumené pružiny: stejný průběh při různých FPS,
	# bez rozkmitání po dlouhém snímku. Úhly jsou jen malá příměs k pohledu myši.
	var omega := 15.0
	var offset := _motion_angles - target
	var j := _motion_velocity + offset * omega
	var decay := exp(-omega * dt)
	_motion_angles = target + (offset + j * dt) * decay
	_motion_velocity = (_motion_velocity - j * omega * dt) * decay

func _process(dt: float) -> void:
	var _perf_t0:=Time.get_ticks_usec()
	_process_timed(dt)
	PerfMon.add("Hráč a zbraň",Time.get_ticks_usec()-_perf_t0)

func _process_timed(dt: float) -> void:
	_time += dt
	weapon.update(dt)
	# --- virtuální tělo dohání pohled; samotný pohled myši se použije přímo
	var a := 1.0 - exp(-10.0 * dt)
	_yaw_s = lerp_angle(_yaw_s, yaw, a)
	_pitch_s = lerpf(_pitch_s, pitch, a)

	var xf := get_global_transform_interpolated()
	var speed := Vector2(velocity.x, velocity.z).length()
	var grounded := is_on_floor() and not swimming
	if body:
		body.update_body(dt, xf.origin, yaw, velocity, crouching, swimming, control_enabled,
			_sprint and absf(_input.x) > 0.1, third_person and not weapon.aiming, grounded)

	# --- výška očí
	var eye_target := minf(1.12, _headroom - 0.18) if crouching else EYE_STAND
	eye_target = maxf(eye_target, 0.5)
	_eye = lerpf(_eye, eye_target, 1.0 - exp(-9.0 * dt))
	# Při vstupu pod nízký strop se výška omezí hned; vyjetí zpět je plynulé.
	_eye = minf(_eye, _headroom - 0.14)
	camera_eye_height = _eye

	# --- houpání při chůzi
	var target_amt := clampf(speed / WALK, 0.0, 1.6) if grounded else 0.0
	_bob_amt = lerpf(_bob_amt, target_amt, 1.0 - exp(-7.0 * dt))
	var stride := 0.5 if crouching else (0.95 if _sprint else 0.72)
	if grounded:
		_bob_phase += speed * dt / stride * PI
	var amp := (0.014 if crouching else 0.024) * (0.75 if submersion > 0.1 else 1.0) * bob_scale * (1.0 - steady * (1.0 - aim_sway))
	var sb := sin(_bob_phase)
	var bob_y := -(sb * sb) * amp * 1.6 * _bob_amt + amp * 0.8 * _bob_amt       # sin²: hladký krok bez zlomu nahoře
	var bob_x := cos(_bob_phase) * amp * 0.8 * _bob_amt

	# --- pružina dopadu, stabilní i při nízkých FPS
	var land_j := _land_v + _land * 10.0
	var land_decay := exp(-10.0 * dt)
	_land = (_land + land_j * dt) * land_decay
	_land_v = (_land_v - land_j * 10.0 * dt) * land_decay

	# --- plavání: tělo se houpe s vodou
	var swim_bob := 0.0
	var swim_roll := 0.0
	if swimming:
		swim_bob = sin(_time * 1.5) * 0.03 + sin(_time * 2.6 + 1.0) * 0.012
		swim_roll = sin(_time * 1.1) * 0.014

	# --- náklon při úkroku + ruční kamera (šum)
	var local_v := Basis(Vector3.UP, -yaw) * velocity
	var acceleration := (velocity - _last_velocity) / maxf(dt, 0.001)
	_last_velocity = velocity
	_acceleration = _acceleration.lerp(acceleration.limit_length(18.0), 1.0 - exp(-8.0 * dt))
	var local_accel := Basis(Vector3.UP, -yaw) * _acceleration
	var turn := clampf(wrapf(yaw - _yaw_s, -PI, PI), -0.18, 0.18)
	var look := clampf(pitch - _pitch_s, -0.15, 0.15)
	var gait := _bob_amt * bob_scale * (1.0 - steady * (1.0 - aim_sway))
	var motion_target := Vector3(
		clampf(local_accel.z * 0.002 - look * 0.12 + sin(_bob_phase * 2.0) * 0.006 * gait, -0.05, 0.05),
		-turn * 0.14,
		clampf(turn * 0.32 - local_accel.x * 0.002 + sin(_bob_phase) * 0.010 * gait, -0.07, 0.07))
	_update_motion(motion_target if control_enabled else Vector3.ZERO, dt)
	var roll_target := -local_v.x * 0.0075 + swim_roll + sin(_bob_phase) * 0.004 * _bob_amt * (1.0 - steady * (1.0 - aim_sway))
	_roll = lerpf(_roll, roll_target, 1.0 - exp(-6.0 * dt))
	var hh := (0.0035 + handheld * 0.012) * shake_scale
	var nt := _time * (0.35 + handheld * 0.5)
	var n_pitch := _noise.get_noise_2d(nt, 0.0) * hh + sin(_time * 1.05) * 0.0018 * shake_scale
	var n_yaw := _noise.get_noise_2d(nt, 37.0) * hh
	var n_roll := _noise.get_noise_2d(nt, 91.0) * hh * 0.7

	var basis_yaw := Basis(Vector3.UP, yaw)
	head.global_position = xf.origin + Vector3(0.0, _eye + bob_y + _land + swim_bob, 0.0) + basis_yaw * Vector3(bob_x, 0.0, 0.0)
	if body and control_enabled:
		var nominal := xf.origin + Vector3(0.0, minf(_eye, _headroom - 0.22), 0.0)
		var eye: Vector3 = body.first_person_eye(yaw)
		eye.y = clampf(eye.y, xf.origin.y + 0.45, xf.origin.y + maxf(0.5, _headroom - 0.22))
		eye.y = maxf(eye.y, water_y + 0.14)
		# Objemová kolize chrání i předsazený objektiv před zdí a stropem.
		var query := PhysicsShapeQueryParameters3D.new()
		query.shape = _camera_probe
		query.transform = Transform3D(Basis(), nominal)
		query.collision_mask = 1
		query.motion = eye - nominal
		var fraction := get_world_3d().direct_space_state.cast_motion(query)
		head.global_position = nominal.lerp(eye, fraction[0])
		camera_eye_height = head.global_position.y - xf.origin.y
	# kamera nikdy pod hladinu (planární odraz i lom s tím počítají)
	if head.global_position.y < water_y + 0.12:
		head.global_position.y = water_y + 0.12
	head.rotation = Vector3(0.0, yaw + n_yaw + _motion_angles.y * motion_scale, 0.0)
	camera.rotation = Vector3(pitch + n_pitch + _motion_angles.x * motion_scale, 0.0,
		_roll + n_roll + _motion_angles.z * motion_scale)
	camera.position = Vector3.ZERO
	camera_uses_third_person = false
	if third_person and control_enabled and not (crouching and _headroom < 1.2):
		_update_shoulder_camera(dt, xf.origin)
	camera.cull_mask = (0xFFFFF & ~8) if camera_uses_third_person else (0xFFFFF & ~4)
	# Vlastní zbraň se při míření v pohybu přiblíží k oku i na ~1,5 cm; s rovinou ořezu 4 cm
	# se pak zadní část zbraně ořízla a hráč viděl „skrz“ AK. V první osobě proto 5 mm.
	camera.near = 0.04 if camera_uses_third_person else 0.005

	var fov_target := (shoulder_fov if camera_uses_third_person else base_fov) + (5.0 if (_sprint and speed > WALK + 0.5 and grounded) else 0.0)
	fov_target=lerpf(fov_target,50.0 if not camera_uses_third_person else 55.0,weapon.aim_amount)
	camera.fov = lerpf(camera.fov, fov_target, 1.0 - exp(-5.0 * dt))
	weapon.finish_frame()

func _update_shoulder_camera(dt: float, feet: Vector3) -> void:
	var target_height: float = shoulder_height - 0.35 * body.crouch_amount
	_shoulder_pivot_height = lerpf(_shoulder_pivot_height, target_height, 1.0 - exp(-10.0 * dt))
	# Přikrčení sleduje prolínání postoje, strop však dál chrání kameru okamžitě.
	_shoulder_pivot_height = clampf(_shoulder_pivot_height, 0.45, maxf(0.45, _headroom - 0.22))
	var pivot_height := _shoulder_pivot_height
	var pivot := feet + Vector3(0, pivot_height, 0)
	if swimming:
		pivot.y = maxf(pivot.y, water_y + 0.3)
	var orbit_pitch := clampf(pitch, -1.05, 1.05)
	var orbit := Basis.from_euler(Vector3(orbit_pitch, yaw, 0.0))
	var offset := orbit * Vector3(shoulder_offset * shoulder_side, 0.0, shoulder_distance)
	var desired := pivot + offset
	desired.y = maxf(desired.y, water_y + 0.14)
	offset = desired - pivot
	var length := offset.length()
	if length < 0.01:
		return
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = _camera_probe
	query.transform = Transform3D(Basis(), pivot)
	query.collision_mask = 1
	query.motion = offset
	var space := get_world_3d().direct_space_state
	if not space.intersect_shape(query, 1).is_empty():
		return
	var fraction := space.cast_motion(query)
	var safe := maxf(length * fraction[0] - 0.04, 0.0)
	# Překážka stáhne kameru okamžitě; do volného prostoru se vrací pozvolna.
	var rate := lerpf(30.0, 6.0, shoulder_smoothing)
	_boom_length = minf(safe, lerpf(_boom_length, safe, 1.0 - exp(-rate * dt)))
	if _boom_length < 0.75:
		return
	camera_uses_third_person = true
	head.global_position = pivot + offset.normalized() * _boom_length
	head.rotation = Vector3(0.0, yaw, 0.0)
	camera.rotation = Vector3(orbit_pitch, 0.0, 0.0)
