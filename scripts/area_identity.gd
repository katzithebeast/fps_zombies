extends Node3D
## Osobnost jednotlivých částí mapy: jméno a podtitul při vstupu, vlastní mlha (pára, prach,
## čistý vzduch), barevné akcentové světlo a zvukový podkres (lednice v bufetu, stroje v kotelně).
## Indexy odpovídají main.MAP_RECTS.

const AREAS := {
	0:  {"name": "Vstupní hala", "sub": "Pokladna zavřena"},
	1:  {"name": "Šatny", "sub": "Ztracené věci vyzvedněte u plavčíka"},
	2:  {"name": "Hlavní bazén", "sub": "Hloubka 2,6 m  ·  skoky zakázány"},
	3:  {"name": "Strojovna filtrace", "sub": "Nepovolaným vstup zakázán"},
	4:  {"name": "Odtokový kanál", "sub": "Kam to vlastně vede?",
		"fog": [0.02, Color(0.4, 0.46, 0.42)]},
	5:  {"name": "Staré sprchy", "sub": "Voda tu teče pořád",
		"fog": [0.02, Color(0.55, 0.7, 0.6)], "loop": ["amb_water", -17.0, 10.0]},
	6:  {"name": "Síň anděla", "sub": "Nedívej se mu do očí"},
	7:  {"name": "Terasy", "sub": "Léto 1974",
		"light": [Color(1.0, 0.55, 0.28), 0.45, 14.0, "steady"]},
	8:  {"name": "Hořčicová chodba", "sub": "Pozor, kluzká podlaha"},
	9:  {"name": "Kulatá síň", "sub": "Lustr visí na posledním řetězu",
		"fog": [0.008, Color(0.5, 0.6, 0.85)]},
	10: {"name": "Kotelna", "sub": "Teplota stoupá",
		"fog": [0.025, Color(0.7, 0.4, 0.3)], "light": [Color(1.0, 0.12, 0.06), 0.9, 8.0, "beacon"],
		"loop": ["boiler_hum", -9.0, 18.0]},
	11: {"name": "Les sloupů", "sub": "Drž se světla",
		"fog": [0.03, Color(0.42, 0.52, 0.58)]},
	12: {"name": "Bludiště", "sub": "Všechny chodby vypadají stejně",
		"fog": [-0.007, Color(1, 1, 1)]},
	13: {"name": "Bufet", "sub": "Kuchyně zavřena  ·  zboží neprodejné",
		"fog": [0.01, Color(0.75, 0.68, 0.5)], "light": [Color(0.6, 0.85, 1.0), 0.5, 6.0, "fridge"],
		"loop": ["fridge_hum", -13.0, 14.0]},
	14: {"name": "Kulatý tunel", "sub": ""},
	15: {"name": "Atrium", "sub": "Vodopád nikdy nepřestal",
		"fog": [0.018, Color(0.8, 0.86, 0.86)]},
	16: {"name": "Toalety", "sub": "Mimo provoz"},
	17: {"name": "Dámské šatny", "sub": "Teplá voda jen do osmi večer",
		"fog": [0.012, Color(0.82, 0.88, 0.9)]},
}

var main: Node
var _current := -1
var visited := {}                 # prozkoumané části (pro minimapu)
var _candidate := -1
var _dwell := 0.0
var _last_shown := {}
var _accents: Array = []          # [OmniLight3D, styl, základní energie]
var _layer: CanvasLayer
var _box: Control
var _name: Label
var _sub: Label
var _tween: Tween
var _time := 0.0
var _vhs_style := false
var _font_clean: Font
var _line: ColorRect

func setup(main_node: Node) -> void:
	main = main_node
	_build_ui()
	_build_world.call_deferred()

func _build_world() -> void:
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	for index in AREAS:
		var info: Dictionary = AREAS[index]
		var rect: Rect2 = main.MAP_RECTS[index]
		var c := rect.get_center()
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(c.x, 2.5, c.y), Vector3(c.x, -5.0, c.y), 1))
		var floor_y: float = hit.position.y if not hit.is_empty() else 0.0
		floor_y = maxf(floor_y, main.WATER_Y - 0.4)
		if info.has("fog"):
			var fog := FogVolume.new()
			fog.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
			fog.size = Vector3(rect.size.x, 4.0, rect.size.y)
			var mat := FogMaterial.new()
			mat.density = float(info.fog[0])
			mat.albedo = info.fog[1]
			mat.edge_fade = 0.35        # okraje se slijí se sousední místností
			fog.material = mat
			add_child(fog)
			fog.global_position = Vector3(c.x, floor_y + 2.0, c.y)
		if info.has("light"):
			var l := OmniLight3D.new()
			l.light_color = info.light[0]
			l.light_energy = float(info.light[1])
			l.omni_range = float(info.light[2])
			l.omni_attenuation = 1.4
			l.shadow_enabled = false
			l.light_volumetric_fog_energy = 1.5
			l.distance_fade_enabled = true
			l.distance_fade_begin = 24.0
			l.distance_fade_length = 6.0
			add_child(l)
			l.global_position = Vector3(c.x, floor_y + 2.3, c.y)
			_accents.append([l, info.light[3], float(info.light[1])])
		if info.has("loop") and main.sfx:
			var loop: AudioStreamPlayer3D = main.sfx.make_loop_3d(info.loop[0], Vector3(c.x, floor_y + 1.5, c.y), float(info.loop[1]))
			loop.max_distance = float(info.loop[2])
			loop.unit_size = 3.0

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 6          # pod post-processem (10): titulek dostane VHS i rybí oko
	add_child(_layer)
	_box = Control.new()
	_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_box.modulate.a = 0.0
	_layer.add_child(_box)
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Helvetica Neue", "Arial", "DejaVu Sans"])
	font.font_weight = 300
	_font_clean = font
	_name = Label.new()
	_name.add_theme_font_override("font", font)
	_name.add_theme_font_size_override("font_size", 44)
	_name.add_theme_color_override("font_color", Color(0.93, 0.93, 0.88))
	_name.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_name.add_theme_constant_override("shadow_offset_x", 2)
	_name.add_theme_constant_override("shadow_offset_y", 2)
	_box.add_child(_name)
	var line := ColorRect.new()
	line.color = Color(0.93, 0.93, 0.88, 0.55)
	line.size = Vector2(320, 1.5)
	line.position = Vector2(2, 62)
	_box.add_child(line)
	_line = line
	_sub = Label.new()
	_sub.add_theme_font_override("font", font)
	_sub.add_theme_font_size_override("font_size", 21)
	_sub.add_theme_color_override("font_color", Color(0.78, 0.8, 0.76, 0.9))
	_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	_sub.add_theme_constant_override("shadow_offset_x", 1)
	_sub.add_theme_constant_override("shadow_offset_y", 1)
	_sub.position = Vector2(2, 70)
	_box.add_child(_sub)

func area_at(p: Vector3) -> int:
	for i in main.MAP_RECTS.size():
		if (main.MAP_RECTS[i] as Rect2).has_point(Vector2(p.x, p.z)): return i
	return -1

func _process(dt: float) -> void:
	var _perf_t0:=Time.get_ticks_usec()
	_process_timed(dt)
	PerfMon.add("Jména míst",Time.get_ticks_usec()-_perf_t0)

func _process_timed(dt: float) -> void:
	_time += dt
	_update_accents()
	if main == null or main.player == null: return
	var view := get_viewport().get_visible_rect().size
	var s := view.y / 1080.0
	_box.scale = Vector2(s, s)
	# Ve VHS sedí pod „PLAY ►“ stejným písmem jako text kamery; jinak vlevo dole.
	_box.position = Vector2(230.0 * s, 225.0 * s) if _vhs_style else Vector2(120.0 * s, view.y - 330.0 * s)
	if _vhs_style and _box.modulate.a > 0.0:
		# Kamerový text lehce bliká a poskakuje jako na pásce.
		_name.modulate.a = 0.85 + 0.15 * signf(sin(_time * 9.0))
		_box.position.x += (1.0 if fmod(_time * 13.0, 1.0) > 0.92 else 0.0) * 3.0 * s
	_layer.visible = not (main.menu and main.menu.is_open)
	var here := area_at(main.player.global_position)
	if here >= 0: visited[here] = true
	if here == _current or here < 0:
		_candidate = -1
		return
	# Jméno se ukáže, až v nové části hráč chvíli zůstane (ne při každém přeběhnutí hranice).
	if here != _candidate:
		_candidate = here
		_dwell = 0.0
	_dwell += dt
	if _dwell < 0.8: return
	_current = here
	if not main.player.control_enabled: return
	if _time - float(_last_shown.get(here, -1000.0)) < 90.0: return
	_last_shown[here] = _time
	_show(AREAS.get(here, {}))

func _show(info: Dictionary) -> void:
	if info.is_empty(): return
	_vhs_style = float(main.get("_vhs")) > 0.5
	_apply_style()
	if _vhs_style:
		# Jako popisek kamerového záznamu: číslo kamery a místo, podtitul jako poznámka.
		_name.text = "CAM %02d  %s" % [_current + 1, String(info.name).to_upper()]
		_sub.text = ("» " + String(info.sub).to_upper()) if String(info.sub) != "" else ""
	else:
		_name.text = String(info.name).to_upper()
		_sub.text = info.sub
	if _tween: _tween.kill()
	_box.modulate.a = 0.0
	_name.position = Vector2(-12, 0)
	_tween = create_tween()
	_tween.tween_property(_box, "modulate:a", 1.0, 0.9).set_trans(Tween.TRANS_SINE)
	_tween.parallel().tween_property(_name, "position:x", 0.0, 1.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_tween.tween_interval(2.8)
	_tween.tween_property(_box, "modulate:a", 0.0, 1.4)

func _update_accents() -> void:
	for a in _accents:
		var l: OmniLight3D = a[0]
		match a[1]:
			"beacon":
				# Výstražný maják: pomalé tepání jako rotující siréna.
				var k := pow(0.5 + 0.5 * sin(_time * 4.2), 3.0)
				l.light_energy = a[2] * (0.15 + 0.85 * k)
			"fridge":
				# Studené světlo z otevřené lednice, občas zakolísá.
				var drop := 0.35 if fmod(_time * 0.37, 1.0) > 0.97 and randf() < 0.5 else 1.0
				l.light_energy = a[2] * drop * (0.95 + 0.05 * sin(_time * 50.0))
			_:
				pass

func _apply_style() -> void:
	if _vhs_style:
		# Stejný styl jako OSD kamery: výchozí písmo, velké, bílé, tvrdý stín, bez linky.
		_name.remove_theme_font_override("font")
		_sub.remove_theme_font_override("font")
		_name.add_theme_font_size_override("font_size", 40)
		_sub.add_theme_font_size_override("font_size", 26)
		_name.add_theme_color_override("font_color", Color(1, 1, 1))
		_sub.add_theme_color_override("font_color", Color(1, 1, 1, 0.85))
		_sub.position = Vector2(2, 56)
		_line.visible = false
	else:
		_name.add_theme_font_override("font", _font_clean)
		_sub.add_theme_font_override("font", _font_clean)
		_name.add_theme_font_size_override("font_size", 44)
		_sub.add_theme_font_size_override("font_size", 21)
		_name.add_theme_color_override("font_color", Color(0.93, 0.93, 0.88))
		_sub.add_theme_color_override("font_color", Color(0.78, 0.8, 0.76, 0.9))
		_sub.position = Vector2(2, 70)
		_line.visible = true
		_name.modulate.a = 1.0
