extends Node
## Režisér misí – společný pro všechny archetypy map (bažina, bazény, metro…).
## Vybere náhodnou misi, ukazuje úkol v HUD, řeší interakce (podržet E), nošení věcí (G položit),
## zaměřovač (T), rádiové hlášky, volání vrtulníku z vysílačky u výsadku, odlet a konec mise.
##
## Rozhraní, které musí mapa nabídnout:
##   player, cam, sfx, waves, rng, R, WATER_Y
##   ground(x, z) -> float
##   mission_points(n, opts) -> Array[Vector3]   (viz swamp.gd)
##   mission_theme() -> Dictionary               (cesty k modelům pro mise)
##   extraction_point() -> Vector3               (místo odletu)
##   radio_pos: Vector3                          (vysílačka pro přivolání vrtulníku)
##   cargo_drop: Vector3                         (kam se skládají přinesené věci)
##   mission_pool() -> Array                     (volitelné: které mise na mapě můžou padnout)
##   _say(text)

const MISSIONS := {
	"crew": "res://scripts/missions/m_crew.gd",
	"clear": "res://scripts/missions/m_clear.gd",
	"cargo": "res://scripts/missions/m_cargo.gd",
	"probes": "res://scripts/missions/m_probes.gd",
	"alpha": "res://scripts/missions/m_alpha.gd",
}
const HELI_WAIT := 45.0
const MISSION_NAMES := {"crew": "Najdi předchozí četu", "clear": "Vyčisti oblast", "cargo": "Vyzvedni náklad", "probes": "Měřicí sondy", "alpha": "Hon na alfu"}
# testovací panel (F3): přežijí znovunačtení scény
static var next_mission := ""
static var next_seed := -1
const BOARD_R := 7.0

var main: Node3D
var player: CharacterBody3D
var waves: Node
var mission: Node
var mission_id := ""
var state := "wait_nav"          # wait_nav | active | extract | wait_heli | board | done | failed
var t := 0.0
var carrying: Node3D = null
var tracker := true

var _acts: Array = []
var _focus: Dictionary = {}
var _hold := 0.0
var _radio_act: Dictionary
var _carry_drop: Callable
var _heli_t := 0.0
var _heli: Node3D
var _heli_light: SpotLight3D
var _heli_blink: OmniLight3D
var _heli_snd: AudioStreamPlayer3D
var _heli_from := Vector3.ZERO
var _beep: AudioStreamPlayer
var _beep_t := 0.0
var _static: AudioStreamPlayer
var _flicker: Array = []          # [světlo, základní energie, fáze]
var _sub_t := 0.0
var _subs: Array = []             # fronta titulků [text, doba]
var _end_t := 0.0

var _obj: Label
var _prompt: Label
var _bar_bg: ColorRect
var _bar: ColorRect
var _sub: Label
var _end: Control
var _end_title: Label
var _end_info: Label

## Jen rozmístí věci mise (náhledy bez hráče: SWAMP_NOPLAYER + SWAMP_SHOTS).
var preview := false
func setup_preview(m: Node3D) -> void:
	preview = true
	main = m
	var forced := OS.get_environment("HLADINA_MISSION")
	mission_id = forced if MISSIONS.has(forced) else "crew"
	mission = load(MISSIONS[mission_id]).new()
	mission.director = self
	mission.main = m
	add_child(mission)
	mission.place()

func setup(m: Node3D) -> void:
	main = m
	player = m.player
	waves = m.waves
	waves.director = self
	var forced := OS.get_environment("HLADINA_MISSION")
	if next_mission != "": forced = next_mission
	next_mission = ""
	var pool: Array = m.mission_pool() if m.has_method("mission_pool") else MISSIONS.keys()
	mission_id = forced if MISSIONS.has(forced) else pool[m.rng.randi() % pool.size()]
	mission = load(MISSIONS[mission_id]).new()
	mission.director = self
	mission.main = m
	add_child(mission)
	mission.place()
	waves.mode = mission.waves_mode
	waves.ambient_cap = mission.ambient_cap
	waves.max_rounds = mission.max_rounds
	if OS.get_environment("SWAMP_NOZOMBIES") == "1": waves.mode = "off"      # snímky v kontejneru
	if waves.alpha:
		waves.alpha.enabled = mission.wants_alpha or m.rng.randf() < 0.15
	_radio_act = add_action(m.radio_pos, "Zavolat vrtulník", 2.0, _call_heli, false)
	_build_ui()
	_build_sounds()
	print("Mise: ", mission_id, " (", mission.title, ")")

# ------------------------------------------------------------------ API pro mise

## Interakce „podrž E“ u bodu. Vrací slovník (dá se měnit: on, pos, text).
func add_action(pos: Vector3, text: String, hold: float, cb: Callable, on := true, r := 2.3) -> Dictionary:
	var a := {"pos": pos, "text": text, "hold": hold, "cb": cb, "on": on, "r": r}
	_acts.append(a)
	return a

## Hráč vezme věc do rukou (zbraň schová, jde pomaleji). on_drop(node, pos) se zavolá při položení.
func carry(node: Node3D, on_drop: Callable) -> void:
	carrying = node
	_carry_drop = on_drop
	player.weapon.holster()
	node.reparent(player.camera, false)
	node.position = Vector3(0.05, -0.62, -0.78)
	node.rotation = Vector3(0.35, 0.0, 0.0)
	player.speed_scale = 0.72
	snd("res://audio/crate_open.wav", -8.0, 0.8)

## Položí nesenou věc před hráče.
func drop() -> void:
	if carrying == null: return
	var n := release()
	var f: Vector3 = -player.camera.global_basis.z
	f.y = 0.0
	var p: Vector3 = player.global_position + f.normalized() * 1.1
	p.y = main.ground(p.x, p.z)
	_carry_drop.call(n, p)
	snd("res://audio/crate_close.wav", -6.0, 0.8)

## Vrátí nesenou věc do světa (mise ji sama umístí) a hráč znovu vytáhne zbraň.
func release() -> Node3D:
	var n := carrying
	carrying = null
	player.speed_scale = 1.0
	n.reparent(main, true)
	player.weapon.switch_to(player.weapon.current)
	return n

## Animace sebrání: předmět přiletí před obličej, chvíli ho hráč drží a pak ho schová (nebo vrátí zpátky).
## face = natočení předmětu před kamerou (Eulerovy úhly, rad).
func show_item(node: Node3D, hold := 2.0, done := Callable(), put_back := false, face := Vector3(0.15, 0, 0)) -> void:
	var start := node.global_transform
	var was_armed: bool = player.weapon.equipped
	player.weapon.holster()
	node.reparent(player.camera, true)
	var near := Transform3D(Basis.from_euler(face), Vector3(0.0, -0.07, -0.36))
	var tw := create_tween()
	tw.tween_property(node, "transform", near, 0.6).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tw.tween_interval(hold)
	if put_back:
		tw.tween_callback(func(): node.reparent(main, true))
		tw.tween_property(node, "global_transform", start, 0.5).set_trans(Tween.TRANS_SINE)
	else:
		tw.tween_property(node, "position", Vector3(0.18, -0.75, -0.2), 0.45).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		tw.tween_callback(node.queue_free)
	tw.tween_callback(func():
		if was_armed and carrying == null: player.weapon.switch_to(player.weapon.current)
		if done.is_valid(): done.call())

## Zkumavka se svítícím vzorkem (hon na alfu, test).
func make_vial(pos: Vector3) -> Node3D:
	var vial := Node3D.new()
	main.add_child(vial)
	vial.global_position = pos
	box(vial, Vector3(0.025, 0.11, 0.025), Vector3.ZERO, Color(0.3, 0.9, 0.35), 2.5)
	box(vial, Vector3(0.03, 0.025, 0.03), Vector3(0, 0.065, 0), Color(0.6, 0.1, 0.08))
	var l := OmniLight3D.new()
	l.light_color = Color(0.35, 1.0, 0.4)
	l.light_energy = 0.5
	l.omni_range = 1.2
	vial.add_child(l)
	return vial

## Rádiová hláška (titulky + šum).
func radio(text: String, dur := 6.0) -> void:
	_subs.append([text, dur, true])
	if _subs.size() == 1: _show_sub()

## Přehrání záznamu (diktafon): několik titulků za sebou se šumem.
func play_log(parts: Array) -> void:
	for p in parts: _subs.append([p, 4.5, true])
	if _subs.size() == parts.size(): _show_sub()

## Blikající / poblikávající světlo (baterky, světýlka).
func flicker(l: Light3D) -> void:
	_flicker.append([l, l.light_energy, randf() * 10.0])

func mission_complete() -> void:
	state = "extract"
	_radio_act.on = true
	main.sfx.play("round_end", -4.0)
	radio("Centrála: Výborně, máme to. Vraťte se k vysílačce u výsadku a zavolejte vrtulník.", 7.0)

func player_died() -> void:
	if state == "done" or state == "failed": return
	get_tree().create_timer(3.0).timeout.connect(_finish.bind(false))

## Model z .glb: nejdelší rozměr = size, spodek na pos.y, střed na pos.xz. rot = natočení modelu (např. tělo na zádech).
static func place_model(parent: Node3D, path: String, size: float, pos: Vector3, yaw := 0.0, rot := Vector3.ZERO) -> Node3D:
	var pivot := Node3D.new()
	parent.add_child(pivot)
	pivot.global_position = pos
	pivot.rotation.y = yaw
	var inner := Node3D.new()
	inner.rotation = rot
	pivot.add_child(inner)
	var m: Node3D = (load(path) as PackedScene).instantiate()
	inner.add_child(m)
	var inv := pivot.global_transform.affine_inverse()
	var bb := AABB()
	var first := true
	for mi in m.find_children("*", "MeshInstance3D", true, false):
		var b: AABB = (inv * (mi as MeshInstance3D).global_transform) * (mi as MeshInstance3D).get_aabb()
		bb = b if first else bb.merge(b)
		first = false
	var k := size / maxf(maxf(bb.size.x, bb.size.y), maxf(bb.size.z, 0.001))
	inner.scale = Vector3.ONE * k
	var c := bb.get_center()
	inner.position = Vector3(-c.x * k, -bb.position.y * k, -c.z * k)
	pivot.set_meta("size", bb.size * k)
	return pivot

## Jednoduchý kvádr (sondy, kolíky, bedny).
static func box(parent: Node3D, size: Vector3, pos: Vector3, color: Color, emit := 0.0) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.45
	if emit > 0.0:
		mat.emission_enabled = true
		mat.emission = color
		mat.emission_energy_multiplier = emit
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	parent.add_child(mi)
	return mi

## Statická kolize (vrstva 1 – započítá se do navigace, když vznikne před jejím pečením).
static func collider(parent: Node3D, size: Vector3, xf: Transform3D) -> void:
	var sb := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	sb.add_child(cs)
	parent.add_child(sb)
	sb.global_transform = xf

## Upuštěná baterka na zemi: kužel světla je v mlze vidět zdálky.
func dropped_light(pos: Vector3, yaw: float) -> SpotLight3D:
	var root := Node3D.new()
	main.add_child(root)
	root.global_position = pos
	root.rotation = Vector3(0, yaw, 0)
	var body := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.03
	cm.bottom_radius = 0.025
	cm.height = 0.24
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.05, 0.05, 0.05)
	mat.roughness = 0.4
	cm.material = mat
	body.mesh = cm
	body.rotation.x = PI * 0.5
	body.position.y = 0.04
	root.add_child(body)
	var l := SpotLight3D.new()
	l.light_color = Color(1.0, 0.88, 0.68)
	l.light_energy = 3.2
	l.spot_range = 11.0
	l.spot_angle = 24.0
	l.spot_attenuation = 1.2
	l.shadow_enabled = true
	l.light_volumetric_fog_energy = 1.6
	l.position = Vector3(0, 0.06, -0.13)
	l.rotation.x = deg_to_rad(4.0)
	root.add_child(l)
	flicker(l)
	return l

# ------------------------------------------------------------------ průběh

func _process(dt: float) -> void:
	if not is_inside_tree() or _leaving: return
	if preview:
		_update_flicker(dt)
		return
	_update_subs(dt)
	_update_flicker(dt)
	if state == "done" or state == "failed":
		_end_t += dt
		_end.modulate.a = clampf(_end_t / 1.5, 0.0, 1.0)
		if _end_t > 2.0 and _snaps.size() > 0 and OS.get_environment("SWAMP_OUT") != "":
			get_viewport().get_texture().get_image().save_png(OS.get_environment("SWAMP_OUT") + "/hud_end.png")
			_snaps.clear()
		return
	if state == "wait_nav":
		if waves._nav_ready:
			state = "active"
			mission.start()
			radio_sequence()
		_update_ui()
		return
	t += dt
	if god:
		waves.health = 100.0
	if _dbg_test and t > 1.0: _run_debug_test()
	if _autotest: _run_autotest(dt)
	if _snaps.size() > 0 and t >= float(_snaps[0]):
		get_viewport().get_texture().get_image().save_png(OS.get_environment("SWAMP_OUT") + "/hud_%s.png" % _snaps[0])
		_snaps.remove_at(0)
	mission.tick(dt)
	_update_actions(dt)
	_update_tracker(dt)
	match state:
		"wait_heli":
			_heli_t -= dt
			_update_heli(dt)
			if _heli_t <= 0.0: _heli_arrive()
		"board":
			_update_heli(dt)
			var e: Vector3 = main.extraction_point()
			if Vector2(player.global_position.x - e.x, player.global_position.z - e.z).length() < BOARD_R and not waves._dead:
				_finish(true)
	_update_ui()

func radio_sequence() -> void:
	radio("Centrála FÚLZZ, četa 3: " + mission.brief, 9.0)
	radio("Zaměřovač: T zapne/vypne pípání (rychlejší = blíž). Podrž E u předmětů.", 6.0)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed and not event.echo): return
	match event.physical_keycode:
		KEY_ENTER, KEY_KP_ENTER:
			if state == "done" or state == "failed": get_tree().reload_current_scene()

func toggle_tracker() -> void:
	tracker = not tracker
	main._say("Zaměřovač: " + ("zapnuto" if tracker else "vypnuto"))

func _update_actions(dt: float) -> void:
	_focus = {}
	if carrying == null and player.control_enabled:
		var eye: Vector3 = player.camera.global_position
		var fwd: Vector3 = -player.camera.global_basis.z
		var best := 99.0
		for a in _acts:
			if not a.on: continue
			var p: Vector3 = a.pos
			var flat := Vector2(p.x - eye.x, p.z - eye.z).length()
			if flat > a.r or absf(p.y - player.global_position.y) > 2.2: continue
			var to := (p - eye).normalized()
			if flat > 1.0 and to.dot(fwd) < 0.45: continue
			if flat < best:
				best = flat
				_focus = a
	if _focus.is_empty() or not (Input.is_physical_key_pressed(KEY_E) or _test_e):
		_hold = 0.0
		return
	_hold += dt
	if _hold >= _focus.hold:
		_hold = 0.0
		_focus.on = false
		var cb: Callable = _focus.cb
		_focus = {}
		snd("res://audio/item_pickup.wav", -6.0)
		cb.call()

func _update_tracker(dt: float) -> void:
	if not tracker: return
	var ts: Array = []
	if state == "active": ts = mission.targets() if mission.tracker_hint else []
	elif state in ["extract", "wait_heli", "board"]: ts = [main.extraction_point()]
	if carrying and state == "active": ts = [main.cargo_drop]
	if ts.is_empty(): return
	var eye: Vector3 = player.camera.global_position
	var best := 1e9
	var bp := Vector3.ZERO
	for p in ts:
		var d := Vector2((p as Vector3).x - eye.x, (p as Vector3).z - eye.z).length()
		if d < best:
			best = d
			bp = p
	_beep_t -= dt
	if _beep_t > 0.0: return
	_beep_t = clampf(best / 22.0, 0.18, 2.4)
	var f: Vector3 = -player.camera.global_basis.z
	var flat := Vector2(f.x, f.z).normalized()
	var to := Vector2(bp.x - eye.x, bp.z - eye.z).normalized()
	var facing := flat.dot(to) > 0.93
	_beep.pitch_scale = 1.4 if facing else 1.0
	_beep.volume_db = -11.0 if facing else -16.0
	_beep.play()

func _call_heli() -> void:
	state = "wait_heli"
	_radio_act.on = false
	if main.get("radio_node"): show_item(main.radio_node, 4.0, Callable(), true, Vector3(0.1, -0.35, 0.12))
	_heli_t = float(OS.get_environment("HLADINA_HELI_T")) if OS.get_environment("HLADINA_HELI_T") != "" else HELI_WAIT
	snd("res://audio/radio/radio_click.wav", -2.0)
	radio("Centrála: Rozumím, vrtulník je na cestě, odhad %d sekund. Držte se u výsadku." % int(_heli_t), 7.0)
	waves.surge(8)
	# vrtulník: zdálky se blíží (zatím jen zvuk, světlo se rozsvítí na konci)
	var e: Vector3 = main.extraction_point()
	var a: float = main.rng.randf() * TAU
	_heli_from = e + Vector3(cos(a) * 170.0, 55.0, sin(a) * 170.0)
	_heli = Node3D.new()
	main.add_child(_heli)
	_heli.global_position = _heli_from
	_heli_snd = AudioStreamPlayer3D.new()
	_heli_snd.stream = _rotor_stream()
	_heli_snd.unit_size = 30.0
	_heli_snd.max_db = 6.0
	_heli_snd.volume_db = 4.0
	_heli.add_child(_heli_snd)
	_heli_snd.play()
	_heli_light = SpotLight3D.new()
	_heli_light.light_color = Color(0.92, 0.95, 1.0)
	_heli_light.light_energy = 0.0
	_heli_light.spot_range = 70.0
	_heli_light.spot_angle = 11.0
	_heli_light.shadow_enabled = true
	_heli_light.light_volumetric_fog_energy = 2.5
	_heli.add_child(_heli_light)
	_heli_blink = OmniLight3D.new()
	_heli_blink.light_color = Color(1.0, 0.1, 0.05)
	_heli_blink.omni_range = 9.0
	_heli.add_child(_heli_blink)

func _update_heli(_dt: float) -> void:
	if _heli == null: return
	var e: Vector3 = main.extraction_point()
	var hover := e + Vector3(0, 24.0, 0) + Vector3(sin(t * 0.4) * 2.0, sin(t * 0.7) * 0.6, cos(t * 0.33) * 2.0)
	var k := 1.0 if state == "board" else clampf(1.0 - _heli_t / maxf(HELI_WAIT, 1.0), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k)
	_heli.global_position = _heli_from.lerp(hover, k)
	var to := e - _heli.global_position
	if to.length() > 0.1:
		_heli_light.look_at(_heli.global_position + to.normalized() + Vector3(sin(t * 1.3) * 0.06, 0, cos(t * 1.1) * 0.06), Vector3.FORWARD if absf(to.normalized().y) > 0.99 else Vector3.UP)
	_heli_light.light_energy = 14.0 * clampf((0.85 - _heli_t / maxf(HELI_WAIT, 1.0)) * 4.0, 0.0, 1.0) if state == "wait_heli" else 14.0
	_heli_blink.light_energy = 3.0 if fmod(t, 1.2) < 0.12 else 0.0

func _heli_arrive() -> void:
	state = "board"
	radio("Pilot: Jsme nad vámi! Do světla, rychle!", 5.0)

func _finish(ok: bool) -> void:
	state = "done" if ok else "failed"
	if carrying: release()
	player.control_enabled = false
	_end.visible = true
	_end_t = 0.0
	_end_title.text = "MISE SPLNĚNA" if ok else "MISE SELHALA"
	_end_title.add_theme_color_override("font_color", Color(0.75, 0.95, 0.7) if ok else Color(0.95, 0.35, 0.3))
	_end_info.text = "%s\n%s\n\nčas %d:%02d   zabitých %d\n\nEnter – další výjezd (nová mapa a mise)      Esc – menu" % [
		main.get("map_name") if main.get("map_name") else "", mission.title, int(t) / 60, int(t) % 60, waves.kills]
	if ok:
		main.sfx.play("round_end", 0.0)
		if _heli_snd: _heli_snd.volume_db = 8.0
	print("Mise ", mission_id, ": ", "splněna" if ok else "selhala", " za ", int(t), " s")

# ------------------------------------------------------------------ UI

func _label(parent: Control, size: int, col := Color(0.92, 0.88, 0.8, 0.95)) -> Label:
	var l := Label.new()
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", col)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _build_ui() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 21
	add_child(cl)
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(root)
	_obj = _label(root, 20)
	_obj.position = Vector2(40, 36)
	_obj.size = Vector2(700, 200)
	_prompt = _label(root, 22)
	_prompt.set_anchors_preset(Control.PRESET_CENTER)
	_prompt.position = Vector2(-300, 48)
	_prompt.size = Vector2(600, 30)
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_bar_bg = ColorRect.new()
	_bar_bg.color = Color(0, 0, 0, 0.55)
	_bar_bg.set_anchors_preset(Control.PRESET_CENTER)
	_bar_bg.position = Vector2(-90, 84)
	_bar_bg.size = Vector2(180, 6)
	_bar_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_bar_bg)
	_bar = ColorRect.new()
	_bar.color = Color(0.9, 0.85, 0.6, 0.95)
	_bar.size = Vector2(0, 6)
	_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_bg.add_child(_bar)
	_sub = _label(root, 22, Color(0.85, 0.95, 0.8, 0.95))
	_sub.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	_sub.position = Vector2(-560, -250)
	_sub.size = Vector2(1120, 90)
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# konec mise
	_end = Control.new()
	_end.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end.visible = false
	cl.add_child(_end)
	var bg := ColorRect.new()
	bg.color = Color(0, 0, 0, 0.82)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_end.add_child(bg)
	_end_title = _label(_end, 64)
	_end_title.set_anchors_preset(Control.PRESET_CENTER)
	_end_title.position = Vector2(-500, -150)
	_end_title.size = Vector2(1000, 80)
	_end_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_info = _label(_end, 24)
	_end_info.set_anchors_preset(Control.PRESET_CENTER)
	_end_info.position = Vector2(-500, -50)
	_end_info.size = Vector2(1000, 260)
	_end_info.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

func _update_ui() -> void:
	var s := "MISE: %s\n" % mission.title
	match state:
		"wait_nav": s += "  příprava…"
		"active":
			for l in mission.lines(): s += "  • %s\n" % l
		"extract": s += "  • Úkol splněn\n  • Zavolej vrtulník z vysílačky u výsadku\n"
		"wait_heli": s += "  • Vrtulník za %d s – drž se u výsadku\n" % ceili(maxf(_heli_t, 0.0))
		"board": s += "  • Vrtulník je tu – běž do světla!\n"
	var keys := "[T] zaměřovač %s" % ("zap" if tracker else "vyp")
	if carrying: keys += "   [G] položit"
	_obj.text = s + "\n" + keys
	var vs := get_viewport().get_visible_rect().size
	_obj.position = Vector2(vs.x * 0.058, vs.y * 0.16)      # pod nápisem PLAY ► z VHS
	if _focus.is_empty():
		_prompt.text = ""
		_bar_bg.visible = false
	else:
		_prompt.text = ("[E] " if _focus.hold < 0.3 else "[podrž E] ") + str(_focus.text)
		_bar_bg.visible = _hold > 0.0
		_bar.size.x = 180.0 * clampf(_hold / maxf(_focus.hold, 0.01), 0.0, 1.0)

func _show_sub() -> void:
	if _subs.is_empty():
		_sub.text = ""
		_static.stop()
		return
	_sub.text = _subs[0][0]
	_sub_t = _subs[0][1]
	if _subs[0][2]:
		if not _static.playing: _static.play()
		snd("res://audio/radio/radio_click.wav", -6.0)

## Krátký zvuk bez prostoru (UI, rádio, ruce).
func snd(path: String, db := 0.0, pitch := 1.0) -> void:
	if not ResourceLoader.exists(path): return
	var a := AudioStreamPlayer.new()
	a.stream = load(path)
	a.volume_db = db
	a.pitch_scale = pitch
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)

func _update_subs(dt: float) -> void:
	if _subs.is_empty(): return
	_sub_t -= dt
	_sub.modulate.a = clampf(_sub_t * 2.0, 0.0, 1.0)
	if _sub_t <= 0.0:
		_subs.pop_front()
		_show_sub()

func _update_flicker(dt: float) -> void:
	for f in _flicker:
		var l: Light3D = f[0]
		if not is_instance_valid(l): continue
		f[2] += dt
		var k := 1.0
		var ph: float = f[2]
		if fmod(ph, 7.3) < 0.35: k = 0.15 + 0.85 * absf(sin(ph * 40.0))
		l.light_energy = f[1] * k * (0.95 + 0.05 * sin(ph * 13.0))

# ------------------------------------------------------------------ zvuky

func _build_sounds() -> void:
	_beep = AudioStreamPlayer.new()
	_beep.stream = _tone(1500.0, 0.07)
	add_child(_beep)
	_static = AudioStreamPlayer.new()
	var st: AudioStreamWAV = load("res://audio/radio/radio_static.wav")
	st = st.duplicate()
	st.loop_mode = AudioStreamWAV.LOOP_FORWARD
	st.loop_end = st.data.size() / (2 * (2 if st.stereo else 1))
	_static.stream = st
	_static.volume_db = -20.0
	add_child(_static)

static func _tone(freq: float, dur: float) -> AudioStreamWAV:
	var rate := 22050
	var n := int(rate * dur)
	var data := PackedByteArray()
	data.resize(n * 2)
	for i in n:
		var env := minf(1.0, minf(i / 120.0, (n - i) / 400.0))
		var v := int(sin(TAU * freq * i / rate) * 0.5 * env * 32767.0)
		data.encode_s16(i * 2, v)
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = rate
	w.data = data
	return w

## Rotor vrtulníku: hnědý šum s údery listů (smyčka).
static func _rotor_stream() -> AudioStreamWAV:
	var rate := 22050
	var f := 4.4
	var n := int(rate * 14.0 / f)
	var data := PackedByteArray()
	data.resize(n * 2)
	var b := 0.0
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in n:
		b = clampf(b + rng.randf_range(-1.0, 1.0) * 0.08, -1.0, 1.0) * 0.995
		var w := rng.randf_range(-1.0, 1.0)
		lp += (w - lp) * 0.12
		var ph := fmod(i * f / rate, 1.0)
		var thump := pow(maxf(0.0, 1.0 - ph * 4.0), 2.0)
		var v := b * 0.55 + lp * (0.25 + thump * 1.3) + sin(TAU * 38.0 * i / rate) * thump * 0.35
		data.encode_s16(i * 2, int(clampf(v * 0.7, -1.0, 1.0) * 32767.0))
	var s := AudioStreamWAV.new()
	s.format = AudioStreamWAV.FORMAT_16_BITS
	s.mix_rate = rate
	s.data = data
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_end = n
	return s

# ------------------------------------------------------------------ automatický test (HLADINA_MISSION_TEST=1)
# Projde misi sám: dojde k cílům, podrží E, donese bedny, zavolá vrtulník a nastoupí. Vypisuje průběh.

var _snaps: Array = Array(OS.get_environment("HLADINA_SNAP").split(",", false))
var _autotest := OS.get_environment("HLADINA_MISSION_TEST") == "1"
var _test_e := false
var _at_t := 0.0
var _at_last := ""

## Teleport z testovacího panelu: kousek od cíle, pohled na něj.
func _tp(p: Vector3) -> void:
	_goto(p, 3.2, -0.3)

func _goto(p: Vector3, dist := 1.15, pitch := -0.75) -> void:
	var from := p + Vector3(1.1, 0, 0.3).normalized() * dist
	from.y = main.ground(from.x, from.z)
	var yaw := atan2(-(p.x - from.x), -(p.z - from.z))
	player.teleport(Vector3(from.x, maxf(from.y, main.WATER_Y - 0.6) + 0.05, from.z), yaw, pitch)
	player.velocity = Vector3.ZERO

func _run_autotest(dt: float) -> void:
	if OS.get_environment("HLADINA_TEST_DIE") == "1" and t > 4.0:
		if not waves._dead: waves.hurt(999.0, player)
		return
	waves.health = 100.0
	_at_t -= dt
	if _at_t > 0.0: return
	_at_t = 1.2
	_test_e = false
	var line := "%s  %s" % [state, str(mission.lines())]
	if line != _at_last:
		print("TEST ", int(t), " s: ", line, "  focus=", _focus.get("text", "-"))
		_at_last = line
	match state:
		"active":
			if carrying:
				_goto(main.cargo_drop)
				return
			if mission_id == "clear":
				for z in waves.ZombieScript.crowd:
					if is_instance_valid(z) and not z.dead: z.queue_free()
				waves.ZombieScript.crowd.clear()
				waves._to_spawn = 0
				waves._pause = 0.1
				return
			if mission_id == "alpha" and not mission.dead:
				var a: Node3D = waves.alpha
				if a.state == "hidden": a._t = 0.0
				elif a.state == "stalk": a.shot(a.global_position + Vector3.UP, Vector3.FORWARD, 500.0)
				return
			if mission_id == "probes":
				for pr in mission.probes:
					if pr.state == "measure":
						_goto(pr.pos)
						pr.k = minf(pr.k + 0.3, 0.99)      # zrychlené měření
						return
			for a in _acts:
				if a.on and a != _radio_act:
					_goto(a.pos)
					_test_e = true
					_at_t = 3.6
					return
		"extract":
			_goto(main.radio_pos)
			_test_e = true
			_at_t = 3.0
		"board":
			_goto(main.extraction_point() + Vector3(2, 0, 0))

# ------------------------------------------------------------------ testovací panel (F3)
# Přepnutí mise (stejná / nová mapa), teleport ke všem cílům a cheaty na kontrolu.

var debug_open := false
var god := false
var _dbg: CanvasLayer

func toggle_debug() -> void:
	debug_open = not debug_open
	if debug_open:
		_build_debug()
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		player.control_enabled = false
	else:
		if _dbg: _dbg.queue_free()
		_dbg = null
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		if state != "done" and state != "failed" and not waves._dead: player.control_enabled = true

func _btn(box: Container, text: String, cb: Callable, col := Color(0.92, 0.9, 0.85)) -> void:
	var b := Button.new()
	b.text = text
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", 17)
	b.add_theme_color_override("font_color", col)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(func():
		cb.call()
		if debug_open: _build_debug())      # obnovit (stav, nové cíle)
	box.add_child(b)

func _head(box: Container, text: String) -> void:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", 15)
	l.add_theme_color_override("font_color", Color(0.65, 0.8, 0.6))
	box.add_child(l)

func _build_debug() -> void:
	if _dbg: _dbg.queue_free()
	_dbg = CanvasLayer.new()
	_dbg.layer = 40
	add_child(_dbg)
	var panel := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.04, 0.05, 0.04, 0.9)
	sb.border_color = Color(0.4, 0.55, 0.35, 0.8)
	sb.set_border_width_all(1)
	sb.set_content_margin_all(12)
	panel.add_theme_stylebox_override("panel", sb)
	panel.set_anchors_preset(Control.PRESET_RIGHT_WIDE)
	panel.offset_left = -430
	panel.offset_right = -20
	panel.offset_top = 20
	panel.offset_bottom = -20
	_dbg.add_child(panel)
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(sc)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 3)
	sc.add_child(box)
	_head(box, "TEST  (F3 / Esc zavřít)   mapa %d, mise %s, stav %s" % [main.seed_used if main.get("seed_used") != null else 0, mission_id, state])
	# mise
	_head(box, "Přepnout misi – stejná mapa")
	for id in MISSIONS:
		_btn(box, ("▶ " if id == mission_id else "   ") + MISSION_NAMES.get(id, id), _restart_with.bind(id, true))
	_btn(box, "   Nová mapa (stejná mise)", _restart_with.bind(mission_id, false))
	_btn(box, "   Nová mapa, náhodná mise", _restart_with.bind("", false))
	# teleporty
	_head(box, "Teleport")
	_btn(box, "Tábor (výsadek, vysílačka)", func(): _tp(main.radio_pos))
	if main.get("goal") != null: _btn(box, "Bunkr", func(): _tp(main.goal))
	if mission.get("wreck_pos") != null: _btn(box, "Vrak vrtulníku", func(): _tp(mission.wreck_pos))
	var i := 0
	for a in _acts:
		if a == _radio_act: continue
		i += 1
		var p: Vector3 = a.pos
		var d := int(Vector2(p.x - player.global_position.x, p.z - player.global_position.z).length())
		_btn(box, "%d) %s%s  (%d m)" % [i, a.text, "" if a.on else "  ✓", d], func(): _tp(p), Color(0.92, 0.9, 0.85) if a.on else Color(0.55, 0.55, 0.5))
	if mission_id == "alpha" or waves.alpha.enabled:
		_btn(box, "Bažinák: vynořit hned", func():
			waves.alpha.enabled = true
			if waves.alpha.state == "hidden": waves.alpha._t = 0.0)
		if waves.alpha.state == "stalk": _btn(box, "Bažinák: teleport k němu", func(): _tp(waves.alpha.global_position))
	# novinky: ragdoll a animace sebrání
	_head(box, "Novinky – ragdoll a sebrání")
	_btn(box, "Tělo: shodit přede mě", _test_corpse_ahead)
	_btn(box, "Těla: všechna znovu shodit (%d)" % get_tree().get_nodes_in_group("swamp_corpse").size(), _test_redrop)
	_btn(box, "Tělo: kopnout do nejbližšího", _test_kick)
	_btn(box, "Teleport k nejbližšímu tělu", func():
		var c := _nearest_corpse()
		if c: _tp(c.center()))
	_btn(box, "Animace: diktafon k obličeji", func(): _test_item("dictaphone"))
	_btn(box, "Animace: zkumavka se vzorkem", func(): _test_item("vial"))
	_btn(box, "Animace: vysílačka (teleport do tábora)", func():
		_tp(main.radio_pos)
		get_tree().create_timer(0.3).timeout.connect(func(): if main.get("radio_node"): show_item(main.radio_node, 2.5, Callable(), true, Vector3(0.1, -0.35, 0.12))))
	_btn(box, "Rádiová hláška (titulky)", func(): radio("Centrála: Testovací hlášení, slyšíte nás? Příjem.", 4.0))
	# cheaty
	_head(box, "Cheaty")
	_btn(box, "Nesmrtelnost: " + ("ZAP" if god else "vyp"), func(): god = not god)
	_btn(box, "Zaměřovač: " + ("zap" if tracker else "vyp"), func(): tracker = not tracker)
	_btn(box, "Zombie: " + ("vypnuté" if waves.mode == "off" else "zapnuté"), func():
		waves.mode = mission.waves_mode if waves.mode == "off" else "off"
		_kill_zombies())
	_btn(box, "Zabít všechny zombie", _kill_zombies)
	if state == "active": _btn(box, "Splnit úkol mise", func(): mission.complete())
	if state in ["active", "extract"]: _btn(box, "Přivolat vrtulník hned (5 s)", func():
		if state == "active": mission.finished = true
		_call_heli()
		_heli_t = 5.0)
	_btn(box, "Doplnit zdraví a náboje", func():
		waves.health = 100.0
		player.weapon.refill())
	_btn(box, "Zpět do menu", func(): get_tree().change_scene_to_file("res://main.tscn"))

var _leaving := false

func _restart_with(id: String, same_map: bool) -> void:
	_leaving = true
	set_process(false)
	next_mission = id
	next_seed = main.seed_used if same_map else -1
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().reload_current_scene()

func _kill_zombies() -> void:
	for z in waves.ZombieScript.crowd:
		if is_instance_valid(z) and not z.dead: z.queue_free()
	waves.ZombieScript.crowd.clear()
	waves._to_spawn = 0

# test panelu (HLADINA_DEBUG_TEST=1): zmáčkne všechna tlačítka kromě restartů a menu, pak přepne misi na stejné mapě
var _dbg_test := OS.get_environment("HLADINA_DEBUG_TEST") == "1"
static var _dbg_test_round := 0

func _run_debug_test() -> void:
	_dbg_test = false
	print("PANEL: mise ", mission_id, " mapa ", main.seed_used, " (kolo testu ", _dbg_test_round, ")")
	if _dbg_test_round == 1:
		get_tree().quit()
		return
	toggle_debug()
	var idx := 0
	while idx < 60:
		var el := []
		for b in _dbg.find_children("*", "Button", true, false):
			var tx: String = (b as Button).text
			if "mapa" in tx.to_lower() or "menu" in tx.to_lower() or tx.begins_with("   ") or tx.begins_with("▶"): continue
			el.append(b)
		if idx >= el.size(): break
		var bt: Button = el[idx]
		var txt := bt.text.strip_edges()
		bt.pressed.emit()
		await get_tree().process_frame
		print("PANEL: ", txt, " -> stav ", state, " hráč ", player.global_position.snapped(Vector3.ONE * 0.1), " zombie ", waves._alive())
		idx += 1
	var tps := 0
	for b in _dbg.find_children("*", "Button", true, false):
		var tx3: String = (b as Button).text
		if tx3.contains(" m)") or tx3 in ["Tábor (výsadek, vysílačka)", "Bunkr", "Vrak vrtulníku"]:
			tps += 1
	print("PANEL: tlačítek teleportu ", tps)
	_dbg_test_round = 1
	_restart_with("cargo", true)

# ------------------------------------------------------------------ testy novinek (panel F3)

func _ahead(d: float) -> Vector3:
	var f: Vector3 = -player.camera.global_basis.z
	f.y = 0.0
	var p: Vector3 = player.global_position + f.normalized() * d
	p.y = main.ground(p.x, p.z)
	return p

func _new_corpse(p: Vector3, yaw: float) -> Node3D:
	var c := Node3D.new()
	c.set_script(load("res://scripts/swamp_corpse.gd"))
	main.add_child(c)
	c.global_position = p + Vector3(0, 0.6, 0)
	c.rotation.y = yaw
	c.setup(main.rng.randi() % 3, main.rng)
	return c

func _test_corpse_ahead() -> void:
	_new_corpse(_ahead(2.2), player.yaw)

func _test_redrop() -> void:
	for c in get_tree().get_nodes_in_group("swamp_corpse"):
		var p: Vector3 = c.center()
		p.y = main.ground(p.x, p.z)
		var yaw: float = main.rng.randf() * TAU
		c.remove_from_group("swamp_corpse")
		c.queue_free()
		_new_corpse(p, yaw)

func _nearest_corpse() -> Node3D:
	var best: Node3D = null
	var bd := 1e9
	for c in get_tree().get_nodes_in_group("swamp_corpse"):
		var d: float = c.center().distance_to(player.global_position)
		if d < bd:
			bd = d
			best = c
	return best

func _test_kick() -> void:
	var c := _nearest_corpse()
	if c == null: return
	var dir: Vector3 = (c.center() - player.global_position)
	dir.y = 0.0
	for n in ["chest", "hips", "thigh.L"]:
		c.bodies[n].apply_central_impulse(dir.normalized() * 30.0 + Vector3.UP * 14.0)

func _test_item(kind: String) -> void:
	var p := _ahead(0.9) + Vector3(0, 0.05, 0)
	if kind == "vial":
		show_item(make_vial(p + Vector3(0, 0.3, 0)), 1.6, Callable(), false, Vector3(0.1, 0, 0.3))
	else:
		var d := place_model(main, main.mission_theme().dictaphone, 0.15, p, 0.0, Vector3(-PI * 0.5, 0, 0))
		snd("res://audio/radio/radio_click.wav", -4.0, 1.3)
		show_item(d, 2.6, Callable(), false, Vector3(PI * 0.5 + 0.25, 0, 0))
