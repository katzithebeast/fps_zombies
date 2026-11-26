extends Node
## Bažina – test boje: vlny zombie, střelba, úder pažbou a zdraví hráče.
## Zombie, zbraně a efekty jsou z hlavní hry (zombie.gd, player_weapon.gd, combat_fx.gd);
## tady je jen jednoduchá správa kol, navigační síť bažiny a HUD.
## Kolo: N zombie (víc a rychlejší s každým kolem), chodí ze tmy z míst, kam se hráč nedívá.
## Smrt hráče: chvíle tmy a začíná se znovu od 1. kola u místa výsadku.

const ZombieScript := preload("res://scripts/zombie.gd")
const MAX_ALIVE := 14
const NAV_CELL := 0.3

var main: Node3D
var player: CharacterBody3D
var round_now := 0
var health := 100.0
var kills := 0
var _to_spawn := 0
var _spawn_t := 0.0
var _pause := 8.0
var _regen := 0.0
var _dead := false
var _fx: Node3D
var alpha: Node3D
var director: Node                 # režisér misí (missions/mission_director.gd); bez něj nekonečné vlny
var mode := "rounds"               # rounds = vlny | ambient = pár zombie pořád kolem | off
var max_rounds := 0                # 0 = nekonečno
var ambient_cap := 6
var _amb_t := 6.0
var _elapsed := 0.0
signal rounds_done
var _nav_ready := false
var _nav_region: RID
var _hud: Label
var _hurt_rect: ColorRect
var _hurt := 0.0
var _hit_snd: AudioStreamPlayer
var _debug := OS.get_environment("SWAMP_DEBUG") == "1"
var _debug_t := 0.0
var _kill_snd: AudioStreamPlayer

func setup(m: Node3D) -> void:
	main = m
	player = m.player
	_fx = preload("res://scripts/combat_fx.gd").new()
	_fx.water_y = m.WATER_Y
	m.add_child(_fx)
	# statické háčky zombie (hladina, efekty, zvuky, vlny na vodě); _exit_tree bažiny je vrátí
	ZombieScript.water_at = Callable()
	ZombieScript.water_level = m.WATER_Y
	ZombieScript.fx = _fx
	ZombieScript.sfx = m.sfx
	ZombieScript.sim = m.sim
	ZombieScript.splash = Callable()
	player.weapon.fired.connect(_fired)
	player.weapon.melee_hit.connect(_melee)
	_build_hud()
	_bake_navigation.call_deferred()
	# bažinák (alfa): hýbe se, jen když se nedíváš
	alpha = preload("res://scripts/swamp_alpha.gd").new()
	m.add_child(alpha)
	alpha.setup(m, self)

static func reset_statics() -> void:
	ZombieScript.fx = null
	ZombieScript.sfx = null
	ZombieScript.sim = null
	ZombieScript.water_at = Callable()
	ZombieScript.splash = Callable()
	ZombieScript.water_level = -1000.0
	ZombieScript.crowd.clear()
	ZombieScript.corpses.clear()

# ------------------------------------------------------------------ navigace

## Síť pro zombie z kolizí bažiny (terén i pod vodou, kmeny, kameny, bunkr). Peče se na vlákně.
func _bake_navigation() -> void:
	if OS.get_environment("SWAMP_NOZOMBIES") == "1":      # snímky v kontejneru (málo paměti na pečení i vykreslování)
		_nav_ready = true
		return
	var mesh := NavigationMesh.new()
	mesh.cell_size = NAV_CELL
	mesh.cell_height = 0.1
	mesh.agent_radius = 0.4
	mesh.agent_height = 0.9
	mesh.agent_max_climb = 0.35
	mesh.agent_max_slope = 45.0
	mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	mesh.geometry_collision_mask = 1
	var src := NavigationMeshSourceGeometryData3D.new()
	NavigationServer3D.parse_source_geometry_data(mesh, src, main)
	NavigationServer3D.bake_from_source_geometry_data_async(mesh, src, func(): _baked.call_deferred(mesh))

func _baked(mesh: NavigationMesh) -> void:
	if not is_inside_tree(): return
	var map: RID = main.get_world_3d().navigation_map
	NavigationServer3D.map_set_cell_size(map, NAV_CELL)
	NavigationServer3D.map_set_cell_height(map, 0.1)
	_nav_region = NavigationServer3D.region_create()
	NavigationServer3D.region_set_map(_nav_region, map)
	NavigationServer3D.region_set_navigation_mesh(_nav_region, mesh)
	# dotazy na mapu fungují až po její synchronizaci (další fyzikální snímek)
	while NavigationServer3D.map_get_iteration_id(map) == 0:
		await get_tree().physics_frame
	await get_tree().physics_frame
	_nav_ready = true
	print("Bažina: navigace hotová, polygonů ", mesh.get_polygon_count())

func _exit_tree() -> void:
	if _nav_region.is_valid(): NavigationServer3D.free_rid(_nav_region)

# ------------------------------------------------------------------ kola

func _alive() -> int:
	var n := 0
	for z in ZombieScript.crowd:
		if is_instance_valid(z) and not z.dead: n += 1
	return n

func _start_round() -> void:
	round_now += 1
	_to_spawn = 5 + round_now * 3
	_spawn_t = 1.0
	main.sfx.play("round_start", -4.0)
	main._say("Kolo %d" % round_now)

func _kind() -> String:
	var pool := {"classic": 30.0, "cop": 22.0, "girl": 22.0, "ch10": 8.0}
	if round_now >= 2: pool["kid"] = 9.0
	if round_now >= 3: pool["parasite"] = minf(8.0 + 3.0 * (round_now - 3), 26.0)
	if round_now >= 5: pool["alpha"] = 2.0
	var sum := 0.0
	for k in pool: sum += pool[k]
	var roll := randf() * sum
	for k in pool:
		roll -= pool[k]
		if roll <= 0.0: return k
	return "classic"

func _spawn_one() -> bool:
	var map: RID = main.get_world_3d().navigation_map
	var here := player.global_position
	var look: Vector3 = -player.camera.global_basis.z
	for attempt in 14:
		var a := randf() * TAU
		var p := here + Vector3(cos(a), 0.0, sin(a)) * randf_range(15.0, 26.0)
		if absf(p.x) > main.R - 6.0 or absf(p.z) > main.R - 6.0: continue
		# přednostně z míst, kam se hráč nedívá
		var to: Vector3 = p - player.camera.global_position
		to.y = 0.0
		if to.normalized().dot(Vector3(look.x, 0, look.z).normalized()) > 0.3 and attempt < 10: continue
		p.y = main.ground(p.x, p.z)
		var q := NavigationServer3D.map_get_closest_point(map, p)
		if q.distance_to(p) > 2.5: continue
		var z: Node3D = ZombieScript.new()
		z.kind = _kind()
		var info: Dictionary = ZombieScript.TYPES[z.kind]
		z.max_health = (100.0 + 45.0 * (round_now - 1)) * float(info.hp)
		z.health = z.max_health
		z.attack_damage *= float(info.dmg)
		var roll := randf()
		if round_now <= 2: z.tier = "walk"
		elif round_now <= 4: z.tier = "jog" if roll < 0.4 else "walk"
		else: z.tier = "sprint" if roll < 0.3 else ("jog" if roll < 0.75 else "walk")
		if z.kind == "alpha": z.tier = "walk"
		z.target = player
		z.attacked.connect(func(damage: float): hurt(damage, z))
		z.died.connect(func(_p: Vector3, _i: Vector3, _b: int): kills += 1)
		z.position = q
		z.rotation.y = atan2(here.x - q.x, here.z - q.z)
		main.add_child(z)
		z.alert(randf() < 0.3)
		return true
	return false

func _process(dt: float) -> void:
	_hurt = maxf(0.0, _hurt - dt * 1.6)
	_hurt_rect.color.a = _hurt * 0.35 + (clampf(1.0 - health / 100.0, 0.0, 1.0) * 0.25 if not _dead else 0.6)
	_update_hud()
	if _dead or not _nav_ready or player == null: return
	if _test: _combat_test(dt)
	if _debug:
		_debug_t -= dt
		if _debug_t <= 0.0:
			_debug_t = 5.0
			var d := 999.0
			for z in ZombieScript.crowd:
				if is_instance_valid(z) and not z.dead: d = minf(d, z.global_position.distance_to(player.global_position))
			if alpha: print("bažinák ", alpha.state, " hp ", int(alpha.hp), " vzdálenost ", snappedf(alpha.global_position.distance_to(player.global_position), 0.1))
			print("kolo ", round_now, " naživu ", _alive(), " zbývá ", _to_spawn, " zdraví ", int(health), " nejbližší ", snappedf(d, 0.1))
	_regen -= dt
	if _regen <= 0.0: health = minf(100.0, health + dt * 18.0)
	_elapsed += dt
	if mode == "off" and _to_spawn <= 0: return
	if mode == "ambient":
		# pár zombie pořád kolem; časem jich přibývá a jsou silnější
		round_now = 1 + int(_elapsed / 150.0)
		_amb_t -= dt
		var cap := mini(ambient_cap, 2 + int(_elapsed / 50.0))
		if _amb_t <= 0.0 and _to_spawn <= 0 and _alive() < cap:
			_amb_t = randf_range(4.0, 9.0)
			_to_spawn = 1
	elif _to_spawn <= 0 and _alive() == 0:
		if max_rounds > 0 and round_now >= max_rounds:
			mode = "ambient"
			_elapsed = 0.0
			rounds_done.emit()
			return
		if round_now > 0 and _pause == 8.0:
			main.sfx.play("round_end", -4.0)
		_pause -= dt
		if _pause <= 0.0:
			_pause = 8.0
			_start_round()
		return
	if _to_spawn > 0 and _alive() < MAX_ALIVE:
		_spawn_t -= dt
		if _spawn_t <= 0.0:
			_spawn_t = randf_range(0.8, 2.2) / (1.0 + round_now * 0.08)
			if _spawn_one(): _to_spawn -= 1
	# zombie zaseklá daleko za hráčem (hluboko ve tmě) se přesune blíž
	for z in ZombieScript.crowd:
		if is_instance_valid(z) and not z.dead and z.global_position.distance_to(player.global_position) > 45.0:
			var map: RID = main.get_world_3d().navigation_map
			var a := randf() * TAU
			var p := player.global_position + Vector3(cos(a), 0, sin(a)) * 20.0
			p.y = main.ground(p.x, p.z)
			z.global_position = NavigationServer3D.map_get_closest_point(map, p)
			break

# ------------------------------------------------------------------ zdraví hráče

func hurt(damage: float, source: Node3D) -> void:
	if _dead: return
	health -= damage
	_regen = 4.5
	_hurt = 1.0
	main.sfx.play("player_hurt", -2.0)
	if main.visor: main.visor.on_hurt(damage, source)      # krev na hledí
	player.pitch = clampf(player.pitch + randf_range(0.03, 0.07), -1.5, 1.5)
	if health <= 0.0: _die()

## Nával zombie (volání vrtulníku, sonda…).
func surge(n: int) -> void:
	if OS.get_environment("SWAMP_NOZOMBIES") == "1": return
	_to_spawn += n
	_spawn_t = minf(_spawn_t, 1.5)

func _die() -> void:
	_dead = true
	health = 0.0
	player.control_enabled = false
	main.sfx.play("game_over", -2.0)
	if director:
		director.player_died()
		return
	main._say("Padl jsi v kole %d (%d zabitých). Začíná se znovu…" % [round_now, kills])
	get_tree().create_timer(5.0).timeout.connect(_restart)

func _restart() -> void:
	if not is_inside_tree(): return
	for z in ZombieScript.crowd.duplicate():
		if is_instance_valid(z): z.queue_free()
	for c in ZombieScript.corpses.duplicate():
		if is_instance_valid(c): c.queue_free()
	ZombieScript.crowd.clear()
	ZombieScript.corpses.clear()
	if alpha: alpha.reset()
	health = 100.0
	round_now = 0
	kills = 0
	_to_spawn = 0
	_pause = 6.0
	_dead = false
	player.teleport(Vector3(main.spawn.x, main._spawn_y(), main.spawn.z), player.yaw, -0.05)
	player.control_enabled = true
	player.weapon.refill()

# ------------------------------------------------------------------ střelba (jako v hlavní hře)

func _fired(origin: Vector3, hit: Vector3) -> void:
	var direction: Vector3 = (hit - origin).normalized()
	ZombieScript.noise(origin, 18.0)
	var muzzle: Vector3 = player.body.weapon.muzzle_global()
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var far := origin + direction * 100.0
	var from := origin
	var end := far
	var power := 1.0
	var solid := false
	var normal := Vector3.UP
	var exclude: Array[RID] = []
	# střela projde až dvěma těly; každé jí ubere sílu
	for pass_index in 3:
		var query := PhysicsRayQueryParameters3D.create(from, far, 1 | 32 | 64)
		query.collide_with_areas = true
		query.exclude = exclude
		var target := space.intersect_ray(query)
		if target.is_empty():
			end = far
			break
		end = target.position
		if target.collider.has_meta("corpse"):
			target.collider.get_meta("corpse").shot(target.collider, target.position, direction, maxf(power, 0.4))
			_fx.blood(target.position, direction, false)
			break
		if target.collider.has_meta("alpha"):
			target.collider.get_meta("alpha").shot(target.position, direction, float(player.weapon.damage) * maxf(power, 0.4))
			break
		if not target.collider.has_meta("zombie"):
			solid = true
			normal = target.normal
			break
		var victim: Node3D = target.collider.get_meta("zombie")
		var bone: int = target.collider.get_meta("bone")
		var was_dead: bool = victim.dead or victim._death_pending
		var strength := lerpf(1.0, 0.65, clampf(origin.distance_to(target.position) / 80.0, 0.0, 1.0)) * power
		var dmg: float = player.weapon.damage
		if int(player.weapon.stats().pellets) > 1:
			dmg *= clampf(1.25 - origin.distance_to(target.position) / 14.0, 0.15, 1.25)
			strength *= 0.45
		victim.hit(bone, target.position, direction, strength, dmg)
		_strike(victim, bone, target.position, direction, was_dead, false)
		for area in victim.hitboxes: exclude.append(area.get_rid())
		for body in victim.bodies.values(): exclude.append(body.get_rid())
		from = target.position
		power *= 0.6
	# střela do vody: šplouchnutí a vlny
	var wet := false
	if origin.y > main.WATER_Y and end.y < main.WATER_Y and direction.y < -0.001:
		var surface: Vector3 = origin + direction * ((main.WATER_Y - origin.y) / direction.y)
		if main.ground(surface.x, surface.z) < main.WATER_Y - 0.03:
			wet = true
			if main.sim: main.sim.add_impulse(Vector2(surface.x, surface.z), 0.2, -1.0)
			main.sfx.play_at("step_water", surface, -7.0, 1.35)
			end = surface
	if _fx.shot(muzzle, end, solid and not wet, normal, "prop"): main.sfx.play_at("tick", end, -7.0, randf_range(0.7, 1.1))
	if solid and not wet: _fx.hole(end, normal)

func _melee(origin: Vector3, direction: Vector3) -> void:
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	for angle in [0.0, -0.2, 0.2, -0.4, 0.4]:
		var aim: Vector3 = direction.rotated(Vector3.UP, angle)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + aim * 1.9, 64)
		query.collide_with_areas = true
		query.collide_with_bodies = false
		var target := space.intersect_ray(query)
		if target.is_empty() or not target.collider.has_meta("zombie"): continue
		var victim: Node3D = target.collider.get_meta("zombie")
		var bone: int = target.collider.get_meta("bone")
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(origin, target.position, 1)).is_empty():
			var was_dead: bool = victim.dead or victim._death_pending
			victim.hit(bone, target.position, direction, 1.0, 150.0, true)
			_strike(victim, bone, target.position, direction, was_dead, true)
			player.pitch = clampf(player.pitch - 0.015, -1.5, 1.5)
		return

func _strike(victim: Node3D, bone: int, point: Vector3, direction: Vector3, was_dead: bool, melee: bool) -> void:
	var lethal: bool = victim.dead or victim._death_pending
	main.sfx.play_at("hit_flesh", point, -1.0 if melee else -4.0, randf_range(0.9, 1.15))
	_fx.blood(point, direction, lethal and not was_dead)
	if main.visor and not was_dead: main.visor.on_strike(point, direction, lethal, melee)
	if not was_dead:
		var s := _kill_snd if lethal else _hit_snd
		if s.stream:
			s.pitch_scale = (1.15 if victim._region(bone) == "head" else 1.0) * randf_range(0.97, 1.03)
			s.play()

# ------------------------------------------------------------------ HUD

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 20
	add_child(cl)
	_hurt_rect = ColorRect.new()
	_hurt_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hurt_rect.color = Color(0.45, 0.0, 0.0, 0.0)
	_hurt_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_hurt_rect)
	_hud = Label.new()
	_hud.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	_hud.position = Vector2(-560, -96)
	_hud.size = Vector2(530, 70)
	_hud.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_hud.add_theme_font_size_override("font_size", 22)
	_hud.add_theme_color_override("font_color", Color(0.9, 0.86, 0.78, 0.9))
	_hud.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_hud)
	_hit_snd = AudioStreamPlayer.new()
	_kill_snd = AudioStreamPlayer.new()
	for pair in [[_hit_snd, "hit_marker"], [_kill_snd, "hit_kill"]]:
		var p: AudioStreamPlayer = pair[0]
		if ResourceLoader.exists("res://audio/%s.wav" % pair[1]): p.stream = load("res://audio/%s.wav" % pair[1])
		p.volume_db = -8.0
		add_child(p)

func _update_hud() -> void:
	if player == null: return
	var w: Node = player.weapon
	var gun := ""
	if w.equipped:
		gun = "%s  %d/∞" % [w.stats().name, w.ammo]
	var r := "navigace se počítá…" if not _nav_ready else ("kolo %d   zombie %d" % [round_now, _alive() + _to_spawn] if round_now > 0 else "kolo začne za %d s" % ceili(_pause))
	if mode != "rounds" and _nav_ready: r = ""
	elif max_rounds > 0 and _nav_ready: r = ("vlna %d/%d   zombie %d" % [round_now, max_rounds, _alive() + _to_spawn]) if round_now > 0 else "vlna začne za %d s" % ceili(_pause)
	_hud.text = "%s   zdraví %d\n%s" % [r, maxi(0, ceili(health)), gun]

# ------------------------------------------------------------------ test (SWAMP_COMBAT_TEST=1, SWAMP_OUT)

var _test := OS.get_environment("SWAMP_COMBAT_TEST") == "1"
var _test_t := 0.0
var _test_z: Node3D

func _combat_test(dt: float) -> void:
	_test_t += dt
	_pause = 999.0
	if _test_z == null:
		var f: Vector3 = -player.camera.global_basis.z
		f.y = 0.0
		var p: Vector3 = player.global_position + f.normalized() * 5.0
		p.y = main.ground(p.x, p.z)
		_test_z = ZombieScript.new()
		_test_z.position = NavigationServer3D.map_get_closest_point(main.get_world_3d().navigation_map, p)
		_test_z.rotation.y = atan2(player.global_position.x - p.x, player.global_position.z - p.z)
		main.add_child(_test_z)
		_test_t = 0.0
	elif _test_t > 3.0:
		get_viewport().get_texture().get_image().save_png(OS.get_environment("SWAMP_OUT") + "/combat.png")
		get_tree().quit()
