extends Control
## Menu Customize: uprostřed jen postava. Na částech těla svítí tečky; po najetí se tečka rozvine
## do čáry s názvem, kliknutím se kamera přiblíží na tu část a vedle se objeví volby (barvy, vzory,
## prestižní skiny). Bez panelů a rámečků – vše leží přímo na scéně. Hodnoty: nastavení look_*.

signal changed(key: String, value: Variant)
signal closed

const PlayerBodyScript := preload("res://scripts/player_body.gd")
const ACCENT := Color(1.0, 0.85, 0.6)
# části těla: název, kost, posun od kosti (v souřadnicích postavy), strana čáry, záběr kamery
const PARTS := {
	"visor": {"name": "Hledí", "bone": "mixamorig_Head", "off": Vector3(0.0, 0.1, 0.13), "side": 1.0,
		"cam": [1.2, 26.0], "keys": ["look_visor"]},
	"suit": {"name": "Oblek", "bone": "mixamorig_Spine2", "off": Vector3(0.0, 0.0, 0.16), "side": -1.0,
		"cam": [2.9, 30.0], "keys": ["look_suit"]},
	"gloves": {"name": "Rukavice", "bone": "mixamorig_RightHand", "off": Vector3(0.0, 0.0, 0.0), "side": -1.0,
		"cam": [1.05, 30.0, Vector3(-0.75, 0.25, 0.65)], "keys": ["look_rubber"]},
	"boots": {"name": "Boty", "bone": "mixamorig_LeftFoot", "off": Vector3(0.0, -0.02, 0.06), "side": 1.0,
		"cam": [1.4, 30.0, Vector3(0.35, 0.35, 1.0)], "keys": ["look_rubber"]},
}
const OVERVIEW := [Vector3(0.0, 1.0, 4.6), Vector3(0.0, 0.9, 0.0), 30.0]
const PALETTE := [Color(0.352, 0.552, 0.948), Color(0.9, 0.9, 0.87), Color(0.95, 0.76, 0.08), Color(0.82, 0.26, 0.07),
	Color(0.62, 0.05, 0.05), Color(0.34, 0.38, 0.2), Color(0.12, 0.3, 0.18), Color(0.1, 0.45, 0.5), Color(0.35, 0.2, 0.55),
	Color(0.85, 0.35, 0.55), Color(0.5, 0.5, 0.52), Color(0.08, 0.08, 0.09), Color(0.863, 0.688, 0.19), Color(0.209, 0.209, 0.209)]
const PATTERNS := [["Žádný", 0], ["Maskáč", 1], ["Digitál", 2], ["Výstražné pruhy", 3], ["Reflexní pásy", 4], ["Cákance", 5], ["Tygr", 6]]
const PRESTIGE := [["Zlato", 7, Color(1.0, 0.78, 0.35)], ["Platina", 8, Color(0.85, 0.87, 0.9)], ["Diamant", 9, Color(0.7, 0.92, 1.0)],
	["Obsidián", 10, Color(0.65, 0.35, 1.0)], ["Krvavý měsíc", 11, Color(0.95, 0.2, 0.2)], ["Láva", 12, Color(1.0, 0.5, 0.1)],
	["Galaxie", 13, Color(0.55, 0.45, 1.0)], ["Elektro", 14, Color(0.45, 0.7, 1.0)], ["Toxický", 15, Color(0.45, 1.0, 0.2)],
	["Hologram", 16, Color(0.3, 0.95, 1.0)], ["Mráz", 17, Color(0.75, 0.92, 1.0)], ["Duha", 18, Color(1.0, 0.55, 0.8)], ["Éter", 19, Color(0.85, 0.45, 1.0)]]

var s: Dictionary
var _viewport: SubViewport
var _cam: Camera3D
var _avatar: Node3D
var _skeleton: Skeleton3D
var _body: GeometryInstance3D
var _hud: Control
var _editor: VBoxContainer
var _scroll: ScrollContainer   # editor se posouvá kolečkem (hodně prestižních efektů)
var _back: Button
var _hover := ""
var _selected := ""
var _open := {}                 # část → 0..1 rozvinutí čáry
var _turn := 0.35
var _turn_goal := 0.35
var _dragging := false
var _drag_moved := 0.0
var _cam_from: Array = OVERVIEW
var _cam_to: Array = OVERVIEW
var _cam_t := 1.0
var _time := 0.0

func _init(settings: Dictionary) -> void:
	s = settings

func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var frame := SubViewportContainer.new()
	frame.set_anchors_preset(Control.PRESET_FULL_RECT)
	frame.stretch = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(frame)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.transparent_bg = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	frame.add_child(_viewport)
	_build_scene()
	_hud = Control.new()
	_hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	_hud.mouse_filter = Control.MOUSE_FILTER_STOP
	_hud.draw.connect(_draw_hud)
	_hud.gui_input.connect(_hud_input)
	add_child(_hud)
	var title := Label.new()
	title.text = "Customize"
	title.add_theme_font_size_override("font_size", 52)
	title.position = Vector2(140, 90)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(title)
	var hint := Label.new()
	hint.text = "Najeď na tečku a klikni · táhni myší pro otočení · uvidí to i ostatní hráči"
	hint.modulate = Color(0.75, 0.85, 0.85, 0.7)
	hint.position = Vector2(142, 158)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.modulate.a = 0.0
	_scroll.visible = false
	add_child(_scroll)
	_editor = VBoxContainer.new()
	_editor.add_theme_constant_override("separation", 10)
	_editor.custom_minimum_size = Vector2(500, 0)
	_scroll.add_child(_editor)
	_back = _flat_button("‹  Zpět", 26)
	_back.position = Vector2(132, 930)
	_back.pressed.connect(func(): back())
	add_child(_back)
	for k in PARTS: _open[k] = 0.0

## Esc / Zpět: z detailu na celou postavu, z celé postavy pryč.
func back() -> void:
	if _selected != "": _select("")
	else: closed.emit()

func refresh() -> void:
	_update_look()
	if _selected != "": _build_editor(_selected)

func look() -> Array:
	return [s["look_suit"], s["look_rubber"], s["look_visor"], int(s["look_pattern"]), s["look_pattern_color"], float(s["look_pattern_scale"]), int(s.get("look_rubber_fx", 0))]

func _update_look() -> void:
	if _body: PlayerBodyScript.apply_look_to(_body, look())

func _set_look(key: String, value: Variant) -> void:
	s[key] = value
	_update_look()
	changed.emit(key, value)

# --------------------------------------------------------------- scéna
func _build_scene() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.5, 0.52, 0.5)
	sm.sky_horizon_color = Color(0.85, 0.82, 0.72)
	sm.ground_bottom_color = Color(0.18, 0.2, 0.2)
	sm.ground_horizon_color = Color(0.55, 0.56, 0.52)
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.6
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, 32, 0)
	key.light_energy = 1.3
	key.light_color = Color(1.0, 0.94, 0.82)
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-12, 200, 0)
	rim.light_energy = 1.1
	rim.light_color = Color(0.55, 0.85, 1.0)
	_viewport.add_child(rim)
	var fill := OmniLight3D.new()
	fill.position = Vector3(-1.5, 0.6, 1.8)
	fill.light_energy = 0.6
	fill.omni_range = 5.0
	_viewport.add_child(fill)
	_avatar = (load("res://assets/hazmat/hazmat_player.tscn") as PackedScene).instantiate()
	_avatar.scale = Vector3.ONE * 0.86
	_viewport.add_child(_avatar)
	var lib: AnimationLibrary = load("res://assets/hazmat/locomotion.res")
	var ap := AnimationPlayer.new()
	_avatar.add_child(ap)
	ap.add_animation_library("", lib)
	if lib.has_animation("idle"): ap.play("idle")
	_skeleton = _avatar.get_node_or_null("Skeleton3D")
	_body = _avatar.get_node_or_null("Skeleton3D/Body")
	_cam = Camera3D.new()
	_viewport.add_child(_cam)
	_cam.current = true
	_apply_cam(OVERVIEW)

func _apply_cam(c: Array) -> void:
	_cam.position = c[0]
	_cam.fov = c[2]
	_cam.look_at(c[1])

func _part_world(k: String) -> Vector3:
	var p: Dictionary = PARTS[k]
	var b := _skeleton.find_bone(p.bone)
	if b < 0: return Vector3.ZERO
	return _skeleton.global_transform * _skeleton.get_bone_global_pose(b).origin + _avatar.global_transform.basis.orthonormalized() * (p.off as Vector3)

## Záběr na část těla: kamera zepředu (lehce shora a z boku), část vlevo od středu, vpravo volby.
func _part_cam(k: String) -> Array:
	var target := _part_world(k)
	var dist: float = PARTS[k].cam[0]
	var fov: float = PARTS[k].cam[1]
	var dir: Vector3 = (PARTS[k].cam[2] if (PARTS[k].cam as Array).size() > 2 else Vector3(0.18, 0.12, 1.0)).normalized()
	var aspect := size.x / maxf(size.y, 1.0)
	# posun do strany kolmo na směr pohledu: část těla vlevo od středu, vpravo zůstane místo na volby
	var right := Vector3.UP.cross(dir).normalized()
	var shift := right * dist * tan(deg_to_rad(fov) * 0.5) * aspect * 0.36
	return [target + dir * dist + shift, target + shift, fov]

func _part_screen(k: String) -> Vector2:
	var p: Dictionary = PARTS[k]
	var b := _skeleton.find_bone(p.bone)
	if b < 0: return Vector2(-1000, -1000)
	var world: Vector3 = _skeleton.global_transform * _skeleton.get_bone_global_pose(b).origin + _avatar.global_transform.basis.orthonormalized() * (p.off as Vector3)
	if _cam.is_position_behind(world): return Vector2(-1000, -1000)
	# viewport má stejnou velikost jako tento ovládací prvek (stretch 1:1)
	return _cam.unproject_position(world) * (size / Vector2(_viewport.size))

# --------------------------------------------------------------- vstup
func _hud_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		if _dragging:
			_turn_goal += event.relative.x * 0.008
			_drag_moved += absf(event.relative.x)
		var h := ""
		if _selected == "":
			for k in PARTS:
				if (event.position as Vector2).distance_to(_part_screen(k)) < 26.0: h = k
		if h != _hover:
			_hover = h
			mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if h != "" else Control.CURSOR_ARROW
			_hud.mouse_default_cursor_shape = mouse_default_cursor_shape
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_dragging = true
			_drag_moved = 0.0
		else:
			_dragging = false
			if _drag_moved < 6.0:
				if _hover != "": _select(_hover)
				elif _selected != "": _select("")

func _select(k: String) -> void:
	_selected = k
	_hover = ""
	_cam_from = [_cam.position, _cam.position + (-_cam.global_transform.basis.z), _cam.fov]
	_cam_to = OVERVIEW
	_cam_t = 0.0
	# postava se natočí tak, aby vybraná část byla ke kameře
	_turn_goal = {"": 0.35, "visor": 0.15, "suit": 0.1, "gloves": -0.35, "boots": 0.3}[k]
	var tw := create_tween()
	if k == "":
		tw.tween_property(_scroll, "modulate:a", 0.0, 0.18)
		tw.tween_callback(func(): _scroll.visible = false)
	else:
		_build_editor(k)
		_scroll.visible = true
		_scroll.scroll_vertical = 0
		_scroll.modulate.a = 0.0
		tw.tween_interval(0.25)
		tw.tween_property(_scroll, "modulate:a", 1.0, 0.35)

# --------------------------------------------------------------- editor
func _flat_button(text: String, font := 20) -> Button:
	var b := Button.new()
	b.text = text
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.add_theme_font_size_override("font_size", font)
	b.add_theme_color_override("font_hover_color", ACCENT)
	b.add_theme_color_override("font_pressed_color", ACCENT)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	return b

func _label(text: String, font: int, color := Color(1, 1, 1, 0.9)) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font)
	l.add_theme_color_override("font_color", color)
	return l

func _swatches(parent: Control, key: String) -> void:
	var grid := GridContainer.new()
	grid.columns = 7
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	parent.add_child(grid)
	for c in PALETTE:
		var sw := Control.new()
		sw.custom_minimum_size = Vector2(46, 46)
		sw.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		sw.draw.connect(func():
			var sel: bool = (s[key] as Color).is_equal_approx(c)
			var hov := sw.get_global_rect().has_point(sw.get_global_mouse_position())
			sw.draw_circle(Vector2(23, 23), 16.0 if not hov else 18.0, c)
			if sel: sw.draw_arc(Vector2(23, 23), 21.0, 0, TAU, 40, ACCENT, 2.0, true))
		sw.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_set_look(key, c)
				for other in grid.get_children(): other.queue_redraw())
		sw.mouse_entered.connect(func(): sw.queue_redraw())
		sw.mouse_exited.connect(func(): sw.queue_redraw())
		grid.add_child(sw)
	var custom := ColorPickerButton.new()
	custom.text = "Vlastní barva…"
	custom.flat = true
	custom.edit_alpha = false
	custom.color = s[key]
	custom.custom_minimum_size = Vector2(220, 34)
	custom.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	custom.add_theme_color_override("font_color", Color(1, 1, 1, 0.8))
	custom.color_changed.connect(func(v: Color):
		_set_look(key, v)
		for other in grid.get_children(): other.queue_redraw())
	parent.add_child(custom)

func _choice_row(parent: Control, items: Array, current: int, cb: Callable, tint_index := -1) -> void:
	var flow := HFlowContainer.new()
	flow.add_theme_constant_override("h_separation", 6)
	flow.add_theme_constant_override("v_separation", 2)
	parent.add_child(flow)
	for it in items:
		var b := _flat_button(("●  " if int(it[1]) == current else "") + str(it[0]), 24)
		if tint_index >= 0: b.add_theme_color_override("font_color", it[tint_index])
		b.pressed.connect(func(): cb.call(int(it[1])))
		flow.add_child(b)

func _build_editor(k: String) -> void:
	for c in _editor.get_children(): c.queue_free()
	var p: Dictionary = PARTS[k]
	_editor.add_child(_label(p.name, 44))
	var line := ColorRect.new()
	line.color = ACCENT
	line.custom_minimum_size = Vector2(160, 2)
	line.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_editor.add_child(line)
	if k == "gloves" or k == "boots":
		_editor.add_child(_label("Rukavice, boty a maska mají stejnou gumu.", 16, Color(0.75, 0.85, 0.85, 0.7)))
	_editor.add_child(_label("Barva", 26, ACCENT))
	_swatches(_editor, p["keys"][0])
	if k == "suit":
		var pk := int(s["look_pattern"])
		_editor.add_child(_label("Vzor", 26, ACCENT))
		_choice_row(_editor, PATTERNS, pk, func(v: int):
			_set_look("look_pattern", v)
			_build_editor("suit"))
		if pk >= 1 and pk <= 6:
			_editor.add_child(_label("Barva vzoru", 18, Color(1, 1, 1, 0.75)))
			_swatches(_editor, "look_pattern_color")
		if pk >= 1:
			var h := HBoxContainer.new()
			h.add_child(_label("Velikost", 18, Color(1, 1, 1, 0.75)))
			var sl := HSlider.new()
			sl.min_value = 0.4
			sl.max_value = 2.5
			sl.step = 0.05
			sl.value = 1.0 / maxf(float(s["look_pattern_scale"]), 0.2)
			sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			sl.value_changed.connect(func(v: float): _set_look("look_pattern_scale", 1.0 / v))
			h.add_child(sl)
			_editor.add_child(h)
		_editor.add_child(_label("Prestižní", 26, Color(1.0, 0.78, 0.35)))
		_choice_row(_editor, PRESTIGE, pk, func(v: int):
			_set_look("look_pattern", 0 if v == pk else v)
			_build_editor("suit"), 2)
	if k == "gloves" or k == "boots":
		var rk := int(s.get("look_rubber_fx", 0))
		_editor.add_child(_label("Prestižní efekt", 26, Color(1.0, 0.78, 0.35)))
		_choice_row(_editor, PRESTIGE, rk, func(v: int):
			_set_look("look_rubber_fx", 0 if v == rk else v)
			_build_editor(k), 2)

# --------------------------------------------------------------- vykreslení teček a čar
func _draw_hud() -> void:
	if _selected != "": return
	var font := get_theme_default_font()
	for k in PARTS:
		var pt := _part_screen(k)
		if pt.x < -500: continue
		var t: float = _open[k]
		var pulse := 0.5 + 0.5 * sin(_time * 3.0 + pt.x * 0.01)
		_hud.draw_circle(pt, 18.0 + pulse * 7.0, Color(ACCENT, 0.16 * (1.0 - t)))
		_hud.draw_circle(pt, 7.5 + t * 2.0, Color(1, 1, 1, 0.97))
		_hud.draw_arc(pt, 13.0, 0, TAU, 40, Color(ACCENT, 0.7 + 0.3 * t), 2.0, true)
		if t <= 0.01: continue
		var side: float = PARTS[k].side
		var length := 190.0 * t
		var bend := pt + Vector2(side * 34.0, -34.0) * minf(t * 2.0, 1.0)
		_hud.draw_line(pt, bend, Color(ACCENT, t), 2.0, true)
		var tip := bend + Vector2(side * maxf(0.0, length - 48.0), 0)
		if t > 0.25: _hud.draw_line(bend, tip, Color(ACCENT, t), 2.0, true)
		var name: String = PARTS[k].name
		var fs := 26
		var tw := font.get_string_size(name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs).x
		var x := bend.x + (6.0 if side > 0.0 else -tw - 6.0)
		_hud.draw_string(font, Vector2(x, bend.y - 10.0), name, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(1, 1, 1, smoothstep(0.35, 1.0, t)))
		_hud.draw_string(font, Vector2(x, bend.y + 26.0), "klikni pro úpravu", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color(ACCENT, 0.8 * smoothstep(0.6, 1.0, t)))

func _process(dt: float) -> void:
	if not is_visible_in_tree():
		if _viewport: _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_time += dt
	# v přehledu se postava jemně pohupuje do stran; při úpravě stojí na místě
	if _selected == "" and not _dragging: _turn_goal = 0.35 + sin(_time * 0.35) * 0.35
	_turn = lerpf(_turn, _turn_goal, 1.0 - exp(-dt * 5.0))
	if _avatar: _avatar.rotation.y = _turn
	if _selected != "": _cam_to = _part_cam(_selected)
	if _cam_t < 1.0 or _selected != "":
		_cam_t = minf(1.0, _cam_t + dt / 0.75)
		var e := 1.0 - pow(1.0 - _cam_t, 3.0)
		var pos: Vector3 = (_cam_from[0] as Vector3).lerp(_cam_to[0], e)
		var at: Vector3 = (_cam_from[1] as Vector3).lerp(_cam_to[1], e)
		_apply_cam([pos, at, lerpf(float(_cam_from[2]), float(_cam_to[2]), e)])
	for k in PARTS:
		_open[k] = move_toward(_open[k], 1.0 if k == _hover else 0.0, dt * 4.0)
	# editor vedle postavy (vpravo), zpět dole vlevo
	_scroll.position = Vector2(size.x * 0.6, size.y * 0.14)
	_scroll.size = Vector2(minf(520.0, size.x * 0.38), size.y * 0.8)
	_back.position = Vector2(132, size.y - 150)
	_hud.queue_redraw()
