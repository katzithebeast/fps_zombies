extends PanelContainer
## Menu Customize: barvy obleku, rukavic a bot, hledí a vzory. Vlevo volby, vpravo živý náhled
## postavy (vlastní 3D svět, otáčí se, dá se točit myší). Hodnoty jsou v nastavení (klíče look_*).

signal changed(key: String, value: Variant)
signal closed

const PlayerBodyScript := preload("res://scripts/player_body.gd")
const PATTERNS := [["Žádný", 0], ["Maskáč", 1], ["Digitální maskáč", 2], ["Výstražné pruhy", 3],
	["Reflexní pásy", 4], ["Cákance barvy", 5], ["Tygří pruhy", 6]]
const PRESETS := [
	["Původní", Color(0.352, 0.552, 0.948), Color(0.209, 0.209, 0.209), Color(0.863, 0.688, 0.19), 0, Color(0.1, 0.12, 0.08), 1.0],
	["Laboratoř", Color(0.9, 0.9, 0.87), Color(0.78, 0.62, 0.12), Color(0.72, 0.76, 0.8), 0, Color(0.1, 0.1, 0.1), 1.0],
	["Toxický", Color(0.95, 0.76, 0.08), Color(0.06, 0.06, 0.06), Color(0.25, 0.48, 0.2), 3, Color(0.05, 0.05, 0.05), 1.0],
	["Noc", Color(0.08, 0.08, 0.09), Color(0.12, 0.12, 0.12), Color(0.75, 0.1, 0.07), 2, Color(0.17, 0.17, 0.19), 1.0],
	["Les", Color(0.34, 0.38, 0.2), Color(0.2, 0.15, 0.1), Color(0.8, 0.55, 0.15), 1, Color(0.14, 0.16, 0.08), 1.0],
	["Hasič", Color(0.82, 0.26, 0.07), Color(0.07, 0.07, 0.07), Color(0.86, 0.68, 0.2), 4, Color(0.88, 0.88, 0.82), 1.0],
	["Tygr", Color(0.95, 0.5, 0.08), Color(0.08, 0.08, 0.08), Color(0.2, 0.2, 0.22), 6, Color(0.05, 0.04, 0.03), 1.0],
]
var s: Dictionary
var _refresh: Array[Callable] = []
var _muting := false
var _viewport: SubViewport
var _avatar: Node3D
var _body: GeometryInstance3D
var _turn := 0.6
var _turn_speed := 0.35
var _dragging := false

func _init(settings: Dictionary) -> void:
	s = settings

func _ready() -> void:
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 26)
	add_child(root)
	var left := VBoxContainer.new()
	left.custom_minimum_size = Vector2(560, 0)
	left.add_theme_constant_override("separation", 12)
	root.add_child(left)
	var head := Label.new()
	head.text = "Customize"
	head.add_theme_font_size_override("font_size", 40)
	left.add_child(head)
	var sub := Label.new()
	sub.text = "Vzhled obleku – uvidí ho i ostatní hráči."
	sub.modulate = Color(0.75, 0.85, 0.85, 0.8)
	left.add_child(sub)
	_section(left, "Barvy")
	_color(left, "Oblek", "look_suit")
	_color(left, "Rukavice, boty a maska", "look_rubber")
	_color(left, "Sklo hledí", "look_visor")
	_section(left, "Vzor na obleku")
	var h := _row(left, "Vzor")
	var o := OptionButton.new()
	o.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for p in PATTERNS: o.add_item(p[0], p[1])
	o.item_selected.connect(func(i: int): _set_look("look_pattern", o.get_item_id(i)))
	h.add_child(o)
	_refresh.append(func(): o.select(o.get_item_index(int(s["look_pattern"]))))
	_color(left, "Barva vzoru", "look_pattern_color")
	h = _row(left, "Velikost vzoru")
	var sl := HSlider.new()
	sl.min_value = 0.4
	sl.max_value = 2.5
	sl.step = 0.05
	sl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sl.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sl.value_changed.connect(func(v: float): _set_look("look_pattern_scale", 1.0 / v))
	h.add_child(sl)
	_refresh.append(func(): sl.set_value_no_signal(1.0 / maxf(float(s["look_pattern_scale"]), 0.2)))
	_section(left, "Hotové styly")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	left.add_child(grid)
	for p in PRESETS:
		var b := Button.new()
		b.text = p[0]
		b.custom_minimum_size = Vector2(132, 46)
		b.pressed.connect(func(): _preset(p))
		grid.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	left.add_child(spacer)
	var back := Button.new()
	back.text = "Zpět"
	back.custom_minimum_size = Vector2(220, 52)
	back.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	back.pressed.connect(func(): closed.emit())
	left.add_child(back)
	# --- náhled postavy
	var frame := SubViewportContainer.new()
	frame.custom_minimum_size = Vector2(420, 760)
	frame.stretch = true
	frame.mouse_filter = Control.MOUSE_FILTER_STOP
	frame.gui_input.connect(_preview_input)
	frame.tooltip_text = "Táhni myší pro otočení"
	root.add_child(frame)
	_viewport = SubViewport.new()
	_viewport.own_world_3d = true
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	frame.add_child(_viewport)
	_build_preview()
	refresh()

func _section(parent: Control, title: String) -> void:
	var l := Label.new()
	l.text = title
	l.add_theme_font_size_override("font_size", 22)
	l.add_theme_color_override("font_color", Color(1.0, 0.85, 0.6))
	parent.add_child(l)

func _row(parent: Control, label: String) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.custom_minimum_size = Vector2(0, 46)
	var l := Label.new()
	l.text = label
	l.custom_minimum_size = Vector2(260, 0)
	h.add_child(l)
	parent.add_child(h)
	return h

func _color(parent: Control, label: String, key: String) -> void:
	var h := _row(parent, label)
	var c := ColorPickerButton.new()
	c.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	c.edit_alpha = false
	c.custom_minimum_size = Vector2(0, 40)
	c.color_changed.connect(func(v: Color): _set_look(key, v))
	c.picker_created.connect(func():
		var picker := c.get_picker()
		picker.presets_visible = true
		picker.color_modes_visible = true)
	h.add_child(c)
	_refresh.append(func(): c.color = s[key])

func _set_look(key: String, value: Variant) -> void:
	if _muting: return
	s[key] = value
	_update_preview()
	changed.emit(key, value)

func _preset(p: Array) -> void:
	var keys := ["look_suit", "look_rubber", "look_visor", "look_pattern", "look_pattern_color", "look_pattern_scale"]
	for i in keys.size():
		s[keys[i]] = p[i + 1]
	refresh()
	for k in keys: changed.emit(k, s[k])

func refresh() -> void:
	_muting = true
	for r in _refresh: r.call()
	_muting = false
	_update_preview()

func look() -> Array:
	return [s["look_suit"], s["look_rubber"], s["look_visor"], int(s["look_pattern"]), s["look_pattern_color"], float(s["look_pattern_scale"])]

func _update_preview() -> void:
	if _body: PlayerBodyScript.apply_look_to(_body, look())

func _build_preview() -> void:
	var env := Environment.new()
	var sky := Sky.new()
	var sm := ProceduralSkyMaterial.new()
	sm.sky_top_color = Color(0.5, 0.52, 0.5)
	sm.sky_horizon_color = Color(0.82, 0.8, 0.7)
	sm.ground_bottom_color = Color(0.2, 0.22, 0.22)
	sm.ground_horizon_color = Color(0.55, 0.56, 0.52)
	sky.sky_material = sm
	env.sky = sky
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.045, 0.06, 0.065)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.5
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	var we := WorldEnvironment.new()
	we.environment = env
	_viewport.add_child(we)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-28, 32, 0)
	key.light_energy = 1.3
	key.light_color = Color(1.0, 0.94, 0.82)
	key.shadow_enabled = true
	_viewport.add_child(key)
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(-15, 200, 0)
	rim.light_energy = 0.9
	rim.light_color = Color(0.6, 0.85, 1.0)
	_viewport.add_child(rim)
	var floor := MeshInstance3D.new()
	var disc := CylinderMesh.new()
	disc.top_radius = 0.9
	disc.bottom_radius = 0.9
	disc.height = 0.02
	floor.mesh = disc
	var fm := StandardMaterial3D.new()
	fm.albedo_color = Color(0.7, 0.72, 0.7)
	fm.roughness = 0.25
	floor.material_override = fm
	floor.position.y = -0.01
	_viewport.add_child(floor)
	_avatar = (load("res://assets/hazmat/hazmat_player.tscn") as PackedScene).instantiate()
	_avatar.scale = Vector3.ONE * 0.86
	_viewport.add_child(_avatar)
	var lib: AnimationLibrary = load("res://assets/hazmat/locomotion.res")
	var ap := AnimationPlayer.new()
	_avatar.add_child(ap)
	ap.add_animation_library("", lib)
	if lib.has_animation("idle"): ap.play("idle")
	_body = _avatar.get_node_or_null("Skeleton3D/Body")
	var cam := Camera3D.new()
	cam.fov = 30
	cam.position = Vector3(0, 1.0, 4.3)
	_viewport.add_child(cam)
	cam.look_at(Vector3(0, 0.88, 0))
	cam.current = true

func _preview_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_dragging = event.pressed
	elif event is InputEventMouseMotion and _dragging:
		_turn += event.relative.x * 0.01
		_turn_speed = 0.0

func _process(dt: float) -> void:
	if not is_visible_in_tree():
		if _viewport: _viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
		return
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	if not _dragging: _turn_speed = move_toward(_turn_speed, 0.35, dt * 0.3)
	_turn += _turn_speed * dt
	if _avatar: _avatar.rotation.y = _turn
