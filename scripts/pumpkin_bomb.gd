extends RigidBody3D
## Dýňová bomba (jako opička v CoD): hozená dýně dopadne, rozesměje se, hraje,
## přitáhne k sobě zombie z okolí a po pár sekundách bouchne.

const ZombieScript := preload("res://scripts/zombie.gd")
const LURE_TIME := 6.5        # jak dlouho láká, než bouchne
const LURE_RADIUS := 30.0     # odkud ještě zombie slyší
const BLAST_RADIUS := 7.0     # kdo je blíž, toho to roztrhá
const PLAYER_RADIUS := 2.8    # hráče jen škrábne, když stojí moc blízko

var main: Node
var state := "fly"            # fly → lure → boom
var _t := 0.0
var _lure_t := 0.0
var _model: Node3D
var _light: OmniLight3D
var _music: AudioStreamPlayer3D
var _tick_next := 0.0
var _lured: Array = []
var _scan := 0.0

static func throw_from(main_node: Node, from: Vector3, velocity: Vector3) -> Node:
	var bomb: RigidBody3D = load("res://scripts/pumpkin_bomb.gd").new()
	bomb.main = main_node
	main_node.add_child(bomb)
	bomb.global_position = from
	bomb.linear_velocity = velocity
	bomb.angular_velocity = Vector3(randf_range(-6, 6), randf_range(-4, 4), randf_range(-6, 6))
	return bomb

func _ready() -> void:
	mass = 1.2
	collision_layer = 0
	collision_mask = 1
	continuous_cd = true
	contact_monitor = true
	max_contacts_reported = 2
	var pm := PhysicsMaterial.new()
	pm.bounce = 0.3
	pm.friction = 0.9
	physics_material_override = pm
	angular_damp = 1.5
	var cs := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.07
	cs.shape = sphere
	add_child(cs)
	_model = Props.make("pumpkin")
	_model.scale = Vector3.ONE * 0.42
	_model.position.y = -0.068
	add_child(_model)
	for m in _model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_light = OmniLight3D.new()
	_light.light_color = Color(1.0, 0.55, 0.12)
	_light.light_energy = 0.5
	_light.omni_range = 3.0
	_light.shadow_enabled = false
	add_child(_light)
	body_entered.connect(func(_b): if state == "fly" and _t > 0.05 and linear_velocity.length() > 2.0: _sfx_at("ball_hit", -8.0, 0.55))
	_light.position.y = 0.15

func _sfx_at(group: String, vol: float, pitch: float) -> void:
	if main and main.get("sfx"): main.sfx.play_at(group, global_position, vol, pitch)

func _physics_process(dt: float) -> void:
	_t += dt
	if state == "fly":
		var wl: float = main.water_level_at(global_position) if main and main.has_method("water_level_at") else -1000.0
		if global_position.y < wl:
			# Ve vodě vyplave na hladinu a láká odtud.
			linear_velocity = linear_velocity * 0.85 + Vector3.UP * 0.6
		# Po prvním dopadu se dýně rychle utlumí (je těžká a hranatá, nekutálí se daleko).
		if get_contact_count() > 0 and _t > 0.15:
			linear_damp = 4.0
			angular_damp = 6.0
		if (_t > 0.35 and linear_velocity.length() < 0.35) or _t > 2.2 or global_position.y < -40.0:
			_start_lure()
	elif state == "lure":
		_lure_tick(dt)

func _start_lure() -> void:
	state = "lure"
	freeze = true
	linear_velocity = Vector3.ZERO
	rotation = Vector3(0, rotation.y, 0)
	_music = AudioStreamPlayer3D.new()
	var file := "res://audio/music_box_%d.wav" % (randi() % 3 + 1)
	if ResourceLoader.exists(file): _music.stream = load(file)
	_music.volume_db = 2.0
	_music.unit_size = 6.0
	_music.max_distance = 45.0
	_music.pitch_scale = 1.05
	_music.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	add_child(_music)
	_music.play()
	_laugh()

func _laugh() -> void:
	var laugh := AudioStreamPlayer3D.new()
	if ResourceLoader.exists("res://audio/laugh_1.wav"): laugh.stream = load("res://audio/laugh_1.wav")
	laugh.volume_db = 0.0
	laugh.pitch_scale = randf_range(1.15, 1.3)
	laugh.unit_size = 5.0
	laugh.bus = "World" if AudioServer.get_bus_index("World") >= 0 else "Master"
	add_child(laugh)
	laugh.play()
	laugh.finished.connect(laugh.queue_free)

func _lure_tick(dt: float) -> void:
	_lure_t += dt
	var k: float = _lure_t / LURE_TIME
	# Dýně poskakuje a kroutí se do rytmu, záře bliká čím dál rychleji.
	var beat: float = absf(sin(_lure_t * (5.0 + k * 9.0)))
	_model.position.y = -0.068 + beat * 0.03
	_model.rotation.y += dt * (1.5 + k * 5.0)
	_model.scale = Vector3(1.0 + beat * 0.08, 1.0 - beat * 0.06, 1.0 + beat * 0.08) * 0.42
	_light.light_energy = 0.6 + beat * (1.2 + k * 2.5)
	_light.omni_range = 3.0 + k * 2.0
	# Tikání zrychluje, poslední vteřina skoro souvislé.
	_tick_next -= dt
	if _tick_next <= 0.0 and k > 0.45:
		_tick_next = lerpf(0.5, 0.07, (k - 0.45) / 0.55)
		_sfx_at("tick", -4.0, 1.3 + k * 0.5)
	if _lure_t > LURE_TIME * 0.55 and _lure_t - dt <= LURE_TIME * 0.55: _laugh()
	_scan -= dt
	if _scan <= 0.0:
		_scan = 0.4
		_pull_zombies()
	if _lure_t >= LURE_TIME: _boom()

func _pull_zombies() -> void:
	for z in ZombieScript.crowd:
		if not is_instance_valid(z) or z.dead or z in _lured: continue
		if z.global_position.distance_to(global_position) > LURE_RADIUS: continue
		if z.has_meta("quest_boss"): continue
		_lured.append(z)
		z.set_meta("lure_prev", z.target)
		z.target = self

func _release() -> void:
	var player: Node = main.get("player") if main else null
	for z in _lured:
		if not is_instance_valid(z): continue
		var prev = z.get_meta("lure_prev") if z.has_meta("lure_prev") else null
		z.target = prev if is_instance_valid(prev) else player
		z.remove_meta("lure_prev")
	_lured.clear()

func _boom() -> void:
	state = "boom"
	var center := global_position + Vector3.UP * 0.2
	_release()
	if _music: _music.stop()
	_sfx_at("gib", 2.0, 0.55)
	_sfx_at("whoomp", 4.0, 0.45)
	_sfx_at("splash_big", -6.0, 0.6)
	var mode: Node = main.get("mode") if main else null
	var kills := 0
	for z in ZombieScript.crowd.duplicate():
		if not is_instance_valid(z) or z.dead: continue
		if (z.global_position + Vector3.UP).distance_to(center) > BLAST_RADIUS: continue
		# Dřív náhodná kost 0–7: část z nich nemá fyzikální těleso a zombie výbuch přežila.
		z.blast(center, BLAST_RADIUS, 7.5)
		kills += 1
	# Ležící těla výbuch rozhází taky.
	for z in ZombieScript.corpses.duplicate():
		if is_instance_valid(z) and (z.global_position + Vector3.UP * 0.3).distance_to(center) < BLAST_RADIUS:
			z.blast(center, BLAST_RADIUS, 6.0)
	if mode and kills > 0:
		mode.points += 60 * kills
		mode._popup("+%d" % (60 * kills), true)
	var player: Node3D = main.get("player") if main else null
	if player and mode and mode.active:
		var pd: float = player.global_position.distance_to(global_position)
		if pd < PLAYER_RADIUS: mode.hurt(30.0 * (1.0 - pd / PLAYER_RADIUS) + 5.0, self)
		if pd < 14.0:
			player.pitch = clampf(player.pitch + randf_range(0.03, 0.08) * (1.0 - pd / 14.0), -1.5, 1.5)
			player.yaw += randf_range(-0.04, 0.04) * (1.0 - pd / 14.0)
	_explosion_fx(center)
	_model.visible = false
	_light.visible = false
	var t := get_tree().create_timer(2.2)
	t.timeout.connect(queue_free)

func _explosion_fx(center: Vector3) -> void:
	var root := Node3D.new()
	main.add_child(root)
	root.global_position = center
	# Záblesk.
	var flash := OmniLight3D.new()
	flash.light_color = Color(1.0, 0.6, 0.25)
	flash.light_energy = 14.0
	flash.omni_range = 11.0
	flash.shadow_enabled = false
	root.add_child(flash)
	var tw := root.create_tween()
	tw.tween_property(flash, "light_energy", 0.0, 0.55).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_EXPO)
	# Ohnivá koule.
	var fire := GPUParticles3D.new()
	fire.amount = 48
	fire.lifetime = 0.7
	fire.one_shot = true
	fire.explosiveness = 0.95
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3.UP
	pm.spread = 180.0
	pm.initial_velocity_min = 2.0
	pm.initial_velocity_max = 6.5
	pm.gravity = Vector3(0, 2.0, 0)
	pm.damping_min = 6.0
	pm.damping_max = 9.0
	pm.scale_min = 0.6
	pm.scale_max = 1.6
	var curve := Curve.new()
	curve.add_point(Vector2(0.0, 0.4))
	curve.add_point(Vector2(0.2, 1.0))
	curve.add_point(Vector2(1.0, 0.0))
	var ct := CurveTexture.new()
	ct.curve = curve
	pm.scale_curve = ct
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.25, 0.6, 1.0])
	g.colors = PackedColorArray([Color(1, 0.95, 0.7, 1), Color(1, 0.55, 0.15, 0.95), Color(0.35, 0.12, 0.05, 0.6), Color(0.1, 0.1, 0.1, 0.0)])
	var gt := GradientTexture1D.new()
	gt.gradient = g
	pm.color_ramp = gt
	fire.process_material = pm
	var quad := QuadMesh.new()
	quad.size = Vector2(0.9, 0.9)
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.vertex_color_use_as_albedo = true
	var rg := Gradient.new()
	rg.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	var rt := GradientTexture2D.new()
	rt.gradient = rg
	rt.fill = GradientTexture2D.FILL_RADIAL
	rt.fill_from = Vector2(0.5, 0.5)
	rt.fill_to = Vector2(1.0, 0.5)
	mat.albedo_texture = rt
	quad.material = mat
	fire.draw_pass_1 = quad
	fire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	root.add_child(fire)
	fire.emitting = true
	# Kusy dýně se rozletí.
	var shell := StandardMaterial3D.new()
	shell.albedo_color = Color(0.95, 0.45, 0.08)
	shell.roughness = 0.7
	for i in 10:
		var chunk := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(randf_range(0.03, 0.07), randf_range(0.01, 0.025), randf_range(0.03, 0.06))
		bm.material = shell
		chunk.mesh = bm
		root.add_child(chunk)
		var dir := Vector3(randf_range(-1, 1), randf_range(0.3, 1.2), randf_range(-1, 1)).normalized()
		var end: Vector3 = dir * randf_range(1.2, 3.0) + Vector3.DOWN * randf_range(0.6, 1.2)
		var ct2 := root.create_tween().set_parallel()
		ct2.tween_property(chunk, "position", end, 0.8).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_QUAD)
		ct2.tween_property(chunk, "rotation", Vector3(randf_range(-9, 9), randf_range(-9, 9), randf_range(-9, 9)), 0.8)
		ct2.tween_property(chunk, "scale", Vector3.ZERO, 0.4).set_delay(0.9)
	var done := get_tree().create_timer(2.0)
	done.timeout.connect(root.queue_free)

func _exit_tree() -> void:
	if not _lured.is_empty(): _release()
