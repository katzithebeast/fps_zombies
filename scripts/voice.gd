extends Node
# Hlasy: velitel přes vysílačku (Control) a hlavní postava (Lantern) – odpovědi do vysílačky i myšlenky.
# Každá událost zazní jen jednou; vše jde přes frontu, aby se repliky nepřekrývaly ani s rozhlasem.

const LINES := {
	# id: [soubor, druh (radio = velitel, plr = Lantern do vysílačky, think = myšlenka), český titulek]
	"radio_check_c1": ["radio/radio_check_c1", "radio", "Velitelství Lanternovi. Zkouška spojení. Slyšíš mě?"],
	"plr_check": ["voice/plr_check", "plr", "Slyším dobře, velitelství."],
	"radio_check_c2": ["radio/radio_check_c2", "radio", "Dobře. Za vstupní halou je tma. Použij baterku… a nenech ji tam dole zhasnout."],
	"radio_check_c3": ["radio/radio_check_c3", "radio", "Lanterne. Světlo. Rozsviť ho."],
	"ctrl_first_zombie": ["radio/ctrl_first_zombie", "radio", "Lanterne, co to bylo? Popiš, co vidíš."],
	"plr_first_zombie": ["voice/plr_first_zombie", "plr", "Člověk. …Byl to člověk."],
	"ctrl_first_note": ["radio/ctrl_first_note", "radio", "Tohle si nech. Cokoli se jmény nebo daty chceme."],
	"ctrl_notes_3": ["radio/ctrl_notes_3", "radio", "Data v těch lístcích nesedí s našimi záznamy. Někdo to tu provozoval i po zavření."],
	"ctrl_angel": ["radio/ctrl_angel", "radio", "Ztrácíš signál… Lanterne, voda je tam hlubší, než říkají plány."],
	"ctrl_low_hp": ["radio/ctrl_low_hp", "radio", "Životní funkce ti letí nahoru. Najdi místo, odkud vidíš na východy."],
	"ctrl_round5": ["radio/ctrl_round5", "radio", "Pořád nám mizíš. Mluv se mnou!"],
	"ctrl_pa_phase3": ["radio/ctrl_pa_phase3", "radio", "Lanterne… to hlášení. Ten systém nemá proud už devět let."],
	"plr_copy": ["voice/plr_copy", "plr", "Rozumím."],
	"plr_still_here": ["voice/plr_still_here", "plr", "Pořád tu jsem."],
	"plr_control": ["voice/plr_control", "plr", "Velitelství? …Velitelství, slyšíte mě?!"],
	"think_pool": ["voice/think_pool", "think", "Smrdí to chlórem… a něčím pod tím."],
	"think_angel": ["voice/think_angel", "think", "Kdo sakra staví tak hluboký bazén?"],
	"think_terrace": ["voice/think_terrace", "think", "Prázdný. Proč je zrovna tenhle prázdný, kurva?"],
	"think_maze": ["voice/think_maze", "think", "Tady už jsem byl. Ne? Ach, seru na to."],
	"think_corridor": ["voice/think_corridor", "think", "Nedívej se na tu vodu moc dlouho."],
	"think_first_kill": ["voice/think_first_kill", "think", "Oni nezůstanou ležet… že ne."],
	"think_distant": ["voice/think_distant", "think", "Hmm… nejsem tu sám."],
	"think_low_ammo": ["voice/think_low_ammo", "think", "Počítej rány, kámo."],
}
# Myšlenky při vstupu do části mapy: index části -> [id, kolik sekund tam hráč musí být]
const AREA_THOUGHTS := {2: ["think_pool", 3.0], 6: ["think_angel", 4.0], 7: ["think_terrace", 3.0], 4: ["think_corridor", 5.0], 12: ["think_maze", 40.0]}
const THINK_GAP := 45.0

var main: Node
var _streams := {}
var _player: AudioStreamPlayer
var _click: AudioStreamPlayer
var _queue: Array = []          # {id, wait, cond}
var _current := ""
var _wait := 0.0
var _pending := ""
var _done := {}
var _clock := 0.0
var _scan := 0.0
var _last_think := -1000.0
var _area := -1
var _area_t := 0.0
var _flash_wait := -1.0
var _intro_over := false     # dokud neskončí zkouška spojení a výzva k baterce, nic dalšího se neozve
var _prompt_on := false
var _pa_last := 0.0
var _pa3_at := -1.0
var _ammo_next := 0.0

var _static: AudioStreamPlayer
var _text_left := 0.0
var _pending_text: Dictionary = {}

var _layer: CanvasLayer
var _sub: RichTextLabel
var _prompt: Label

func setup(main_node: Node) -> void:
	main = main_node
	for id in LINES:
		var s: AudioStream = load("res://audio/%s.wav" % LINES[id][0])
		if s: _streams[id] = s
	_player = AudioStreamPlayer.new()
	add_child(_player)
	_player.finished.connect(_on_line_end)
	_click = AudioStreamPlayer.new()
	_click.stream = load("res://audio/radio/radio_click.wav")
	_click.volume_db = -4.0
	add_child(_click)
	_static = AudioStreamPlayer.new()
	var st: AudioStreamWAV = load("res://audio/radio/radio_static.wav")
	if st:
		st.loop_mode = AudioStreamWAV.LOOP_FORWARD
		st.loop_end = int(st.get_length() * st.mix_rate)
	_static.stream = st
	_static.volume_db = -16.0
	add_child(_static)
	_build_ui()

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 7
	add_child(_layer)
	_sub = RichTextLabel.new()
	_sub.bbcode_enabled = true
	_sub.fit_content = true
	_sub.scroll_active = false
	_sub.add_theme_font_size_override("normal_font_size", 26)
	_sub.add_theme_constant_override("outline_size", 7)
	_sub.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_sub.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_sub.modulate.a = 0.0
	_layer.add_child(_sub)
	_prompt = Label.new()
	_prompt.text = "[F]   Rozsviť baterku"
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.add_theme_font_size_override("font_size", 30)
	_prompt.add_theme_constant_override("outline_size", 8)
	_prompt.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.9))
	_prompt.add_theme_color_override("font_color", Color(1.0, 0.92, 0.72))
	_prompt.modulate.a = 0.0
	_layer.add_child(_prompt)

# ------------------------------------------------------------------ fronta
func say(ids: Array, first_wait := 0.0, cond: Callable = Callable()) -> void:
	for i in ids.size():
		var id: String = ids[i]
		if not _streams.has(id): continue
		_queue.append({"id": id, "wait": first_wait if i == 0 else (0.45 if LINES[id][1] == "plr" else 0.6), "cond": cond})

func say_text(speaker: String, text: String) -> void:
	# Hláška bez nahrávky (zatím jen titulek se šumem vysílačky), dokud nebude namluvená.
	_queue.append({"id": "", "text": text, "speaker": speaker, "wait": 0.6, "cond": Callable()})

func once(key: String, ids: Array, first_wait := 0.0, cond: Callable = Callable()) -> bool:
	if _done.has(key): return false
	_done[key] = true
	say(ids, first_wait, cond)
	return true

func think(id: String, wait := 0.0) -> bool:
	# Myšlenky jen v klidu a s odstupem, ať postava není ukecaná.
	if _done.has(id) or _clock - _last_think < THINK_GAP: return false
	if main.sfx and main.sfx.tension > 0.5: return false
	if _queue.size() > 1: return false
	_done[id] = true
	_last_think = _clock
	say([id], wait)
	return true

func heard_distant() -> void:
	# Volá main při vzdáleném zvuku zombie.
	if _clock > 60.0: think("think_distant", 1.4)

func busy() -> bool:
	return _current != "" or _pending != "" or not _queue.is_empty()

func _pa_playing() -> bool:
	return main.pa != null and float(main.pa.playing_until) > Time.get_ticks_msec() / 1000.0

func _tick_queue(dt: float) -> void:
	if _current != "": return
	if _wait > 0.0:
		_wait -= dt
		return
	if _pending != "":
		_start(_pending)
		_pending = ""
		return
	if not _pending_text.is_empty():
		_start_text(_pending_text)
		_pending_text = {}
		return
	if _queue.is_empty() or _pa_playing(): return
	var item: Dictionary = _queue[0]
	if float(item.wait) > 0.0:
		item.wait = float(item.wait) - dt
		return
	_queue.pop_front()
	var cond: Callable = item.cond
	if cond.is_valid() and not bool(cond.call()): return
	if item.has("text"):
		_click.play()
		_pending_text = item
		_wait = 0.12
		return
	var id: String = item.id
	if LINES[id][1] == "radio":
		# Cvaknutí vysílačky, pak hlas.
		_click.play()
		_pending = id
		_wait = 0.12
	else:
		_start(id)

func _start(id: String) -> void:
	_current = id
	var kind: String = LINES[id][1]
	_player.stream = _streams[id]
	_player.volume_db = -1.5 if kind == "think" else 0.0
	_player.play()
	var text: String = LINES[id][2]
	match kind:
		"radio": _sub.text = "[center][color=#a8d8b0]VELITEL:[/color]  %s[/center]" % text
		"plr": _sub.text = "[center][color=#e8c88a]LANTERN:[/color]  %s[/center]" % text
		_: _sub.text = "[center][color=#c8c8c8]%s[/color][/center]" % text
	var tw := create_tween()
	tw.tween_property(_sub, "modulate:a", 1.0, 0.2)

func _start_text(item: Dictionary) -> void:
	_current = "__text"
	_text_left = 1.4 + String(item.text).length() * 0.06
	_static.play()
	var who: String = "VELITEL" if String(item.speaker) == "Control" else String(item.speaker).to_upper()
	_sub.text = "[center][color=#a8d8b0]%s:[/color]  %s[/center]" % [who, item.text]
	create_tween().tween_property(_sub, "modulate:a", 1.0, 0.2)

func _on_line_end() -> void:
	var id := _current
	_current = ""
	if id == "__text":
		_static.stop()
		_click.play()
		id = ""
	if id != "" and LINES[id][1] == "radio": _click.play()
	if id == "radio_check_c2":
		var lit: bool = main.flashlight != null and main.flashlight.visible
		_flash_wait = -1.0 if lit else 10.0
		_intro_over = lit
	elif id == "radio_check_c3":
		_intro_over = true
	if _queue.is_empty():
		var tw := create_tween()
		tw.tween_interval(0.6)
		tw.tween_property(_sub, "modulate:a", 0.0, 0.5)

# ------------------------------------------------------------------ události
func _ready_to_talk() -> bool:
	if main == null or main.player == null: return false
	if main.menu and main.menu.is_open: return false
	if not main.player.control_enabled: return false
	if main.notes and main.notes.is_open(): return false
	return true

func _process(dt: float) -> void:
	var vs := get_viewport().get_visible_rect().size
	var s := vs.y / 1080.0
	_sub.size = Vector2(vs.x * 0.7 / s, 0.0)
	_sub.scale = Vector2(s, s)
	_sub.position = Vector2(vs.x * 0.15, vs.y - 190.0 * s)
	_prompt.size = Vector2(vs.x / s, 0.0)
	_prompt.scale = Vector2(s, s)
	_prompt.position = Vector2(0.0, vs.y * 0.62)
	var flash_on: bool = main != null and main.flashlight != null and main.flashlight.visible
	if flash_on: _prompt_on = false
	var show_prompt := _prompt_on and _ready_to_talk()
	_prompt.modulate.a = move_toward(_prompt.modulate.a, (0.75 + 0.25 * sin(_clock * 4.0)) if show_prompt else 0.0, dt * 3.0)
	_layer.visible = not (main and main.menu and main.menu.is_open)
	if not _ready_to_talk(): return
	_clock += dt
	if _current == "__text":
		_text_left -= dt
		if _text_left <= 0.0: _on_line_end()
	_tick_queue(dt)
	if _flash_wait > 0.0:
		_flash_wait -= dt
		if flash_on:
			_flash_wait = -1.0
			_intro_over = true
		elif _flash_wait <= 0.0:
			once("c3", ["radio_check_c3"])
	_scan -= dt
	if _scan > 0.0: return
	_scan = 0.25
	_events(0.25, flash_on)

func _events(dt: float, flash_on: bool) -> void:
	# 1) Zkouška spojení po příchodu.
	if _clock > 2.5 and once("check", ["radio_check_c1", "plr_check", "radio_check_c2"]):
		return
	if _current == "radio_check_c2" and not flash_on: _prompt_on = true
	if not _intro_over: return
	var mode: Node = main.mode
	var playing: bool = mode != null and mode.active
	# 2) První zombie na očích.
	if not _done.has("zombie") and _sees_zombie():
		once("zombie", ["ctrl_first_zombie", "plr_first_zombie"], 0.8)
	# 3) Lístky.
	if main.notes:
		var reads: int = main.notes._read.size()
		if reads >= 1: once("note1", ["ctrl_first_note", "plr_copy"], 0.8)
		if reads >= 3: once("note3", ["ctrl_notes_3"], 1.0)
	# 4) Části mapy.
	var here: int = main.areas.area_at(main.player.global_position) if main.areas else -1
	if here != _area:
		_area = here
		_area_t = 0.0
	_area_t += dt
	if here == 6 and _area_t > 9.0:
		if once("angel", ["ctrl_angel"]):
			# Po chvíli ticha se Lantern ozve sám – a nikdo neodpoví.
			say(["plr_control"], 22.0, func(): return main.areas.area_at(main.player.global_position) == 6)
	if AREA_THOUGHTS.has(here) and _area_t > float(AREA_THOUGHTS[here][1]):
		think(AREA_THOUGHTS[here][0])
	# 5) Zombie režim.
	if playing:
		if int(mode.kills) >= 1: think("think_first_kill", 1.5)
		if int(mode.round_now) >= 5: once("round5", ["ctrl_round5", "plr_still_here"], 2.0)
		if float(mode.health) < 35.0 and float(mode.health) > 0.0: once("lowhp", ["ctrl_low_hp", "plr_copy"])
		_check_ammo()
	# 6) Rozhlas ve fázi rozpadu → velitel zpozorní.
	if main.pa:
		var until := float(main.pa.playing_until)
		if until > _pa_last + 0.5:
			_pa_last = until
			if main.pa._phase() == 3 and not _done.has("pa3"): _pa3_at = until
		if _pa3_at > 0.0 and Time.get_ticks_msec() / 1000.0 > _pa3_at + 1.5:
			_pa3_at = -1.0
			once("pa3", ["ctrl_pa_phase3"])

func _check_ammo() -> void:
	var w = main.player.get("weapon")
	if w == null or _clock < _ammo_next: return
	var reserve := int(w.get("reserve")) if w.get("reserve") != null else 99
	var ammo := int(w.get("ammo")) if w.get("ammo") != null else 99
	if reserve <= 0 and ammo > 0:
		_done.erase("think_low_ammo")
		if think("think_low_ammo"): _ammo_next = _clock + 240.0

func _sees_zombie() -> bool:
	var cam := get_viewport().get_camera_3d()
	if cam == null: return false
	var from := cam.global_position
	var fwd := -cam.global_transform.basis.z
	var space := cam.get_world_3d().direct_space_state
	for z in load("res://scripts/zombie.gd").crowd:
		if not is_instance_valid(z) or z.dead: continue
		var chest: Vector3 = z.global_position + Vector3(0, 1.3, 0)
		var d := from.distance_to(chest)
		if d > 18.0 or d < 0.5: continue
		if fwd.dot((chest - from) / d) < 0.6: continue
		var q := PhysicsRayQueryParameters3D.create(from, chest, 1)
		var hit := space.intersect_ray(q)
		if hit.is_empty() or (hit.position as Vector3).distance_to(chest) < 1.0:
			return true
	return false
