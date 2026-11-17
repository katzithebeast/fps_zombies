extends Node3D
## Příběh lázní: vzkazy připíchnuté na zdech. E = přečíst, E / Esc = zavřít.
## Svět se při čtení nezastaví – zombie mohou přijít i teď.

const NOTES := [
	# [index části mapy (main.MAP_RECTS), nadpis, text]
	[0, "Vyhláška", "MĚSTSKÉ LÁZNĚ\n\nBazény jsou od 12. 8. 1974 z technických důvodů UZAVŘENY.\nDo odvolání.\n\nVstup do prostor bazénů je přísně zakázán.\nVodu nevypouštět.\n\n— Ředitelství lázní"],
	[1, "Lístek ve skříňce", "Jardo,\n\nten kluk ze skříňky 14 se pořád nevrátil z vody. Prohledal jsem celý bazén i sprchy. Nikde.\n\nAle jeho věci jsou tady. Mokré. Jako by si je někdo před chvílí oblékal.\n\n— Mirek"],
	[3, "Provozní deník", "15. 8.\nFiltry hlásí organický zákal. Chlór na maximu, pořád nic.\n\n17. 8.\nVoda je teplá, i když ohřev nejede od pondělí.\n\n18. 8.\nNěco tam dole dýchá. Čerpadla to přehluší jen přes den."],
	[5, "Napsáno na zrcadle", "Zavřel jsem všechny kohouty.\nRáno byly zase otevřené.\n\nNa zrcadle bylo prstem napsáno:\n\nNEJSOU UTOPENÍ.\nJEN SPÍ."],
	[13, "Kuchař", "Lidi se vracejí z bazénu hladoví. Strašně hladoví.\n\nPaní Nováková snědla syrové maso přímo z lednice. Pak kousla Pavla do ruky a nepustila ho.\n\nZamykám se ve skladu. Ten zvuk ze dveří není klepání."],
	[10, "Údržbář", "Pustil jsem kotel naplno, aby se to v potrubí uvařilo. Nepomohlo.\n\nSlyším je škrábat v trubkách.\n\nJestli tohle někdo najde: odtokový kanál vede k řece. Tudy se dá ven. Klíč od mříže měl Mirek."],
	[9, "Hlášení pro MNV", "Počet pohřešovaných: 23.\n\nDoporučuji lázně trvale uzavřít a bazény v žádném případě nevypouštět.\n\nVoda je drží v klidu.\nDokud je voda, spí.\n\n— ředitel Hroch"],
	[15, "Dětské písmo", "mami\n\nten pán ve vodě mi mával\nměl otevřený oči pod vodou\na vůbec nebublal\n\nřekl že tam dole je teplo\na že tam jsou všichni"],
	[4, "Poslední vzkaz", "Kanál je zatopený až ke stropu. Na konci je mříž.\n\nKlíč měl Mirek.\n\nMirek je teď dole s ostatními. Viděl jsem ho. Díval se na mě skrz vodu a usmíval se."],
]

var main: Node
var items: Array = []      # {pos, node, index}
var _layer: CanvasLayer
var _paper: TextureRect
var _title: Label
var _text: Label
var _dim: ColorRect
var _open := -1
var _read := {}
var _key_held := true
var _tween: Tween
var closed_frame := -100

func setup(main_node: Node) -> void:
	main = main_node
	_build_ui()
	_place.call_deferred()

func _place() -> void:
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space: PhysicsDirectSpaceState3D = main.get_world_3d().direct_space_state
	var tex: Texture2D = load("res://textures/note_paper.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = 1974
	for i in NOTES.size():
		var rect: Rect2 = main.MAP_RECTS[NOTES[i][0]]
		var spot := _wall_spot(space, rect, rng)
		if spot.is_empty(): continue
		var n: Vector3 = spot.normal
		var quad := QuadMesh.new()
		quad.size = Vector2(0.21, 0.28)
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = tex
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
		mat.alpha_scissor_threshold = 0.4
		mat.roughness = 0.95
		quad.material = mat
		var mi := MeshInstance3D.new()
		mi.mesh = quad
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(mi)
		# Papír na zdi, lehce nakřivo a odchlíplý.
		var basis := Basis.looking_at(-n, Vector3.UP).rotated(n, rng.randf_range(-0.15, 0.15))
		mi.global_transform = Transform3D(basis, spot.pos + n * 0.012)
		# Špendlík.
		var pin := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.008
		sphere.height = 0.016
		var pm := StandardMaterial3D.new()
		pm.albedo_color = Color(0.7, 0.08, 0.06)
		pm.roughness = 0.3
		sphere.material = pm
		pin.mesh = sphere
		mi.add_child(pin)
		pin.position = Vector3(0, 0.12, 0.006)
		items.append({"pos": spot.pos + n * 0.4, "node": mi, "index": i})
		# Vzkaz se chová jako ostatní předměty (popisek, zvýraznění, E).
		if main.mode and main.mode.stations:
			main.mode.stations.items.append({"kind": "note", "node": mi, "pos": spot.pos + n * 0.35 - Vector3(0, 0.75, 0), "top": 0.0,
				"state": "idle", "t": 0.0, "gun": "", "prize": "", "show": null, "open": 0.0, "note": i})

func _wall_spot(space: PhysicsDirectSpaceState3D, rect: Rect2, rng: RandomNumberGenerator) -> Dictionary:
	for attempt in 40:
		var p := Vector2(rng.randf_range(rect.position.x + 0.8, rect.end.x - 0.8), rng.randf_range(rect.position.y + 0.8, rect.end.y - 0.8))
		var floor_hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(Vector3(p.x, 2.5, p.y), Vector3(p.x, -4.0, p.y), 1))
		if floor_hit.is_empty() or (floor_hit.normal as Vector3).y < 0.8: continue
		var fy: float = floor_hit.position.y
		if fy < main.WATER_Y - 0.6: continue
		var from := Vector3(p.x, maxf(fy, main.WATER_Y) + 1.45, p.y)
		var dir := Vector3.FORWARD.rotated(Vector3.UP, rng.randf() * TAU)
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(from, from + dir * 8.0, 1))
		if hit.is_empty() or absf((hit.normal as Vector3).y) > 0.1: continue
		var n: Vector3 = hit.normal
		# Zeď musí patřit téhle části (ne sousední místnosti) a nesmí být u jiného vzkazu.
		if not rect.grow(0.6).has_point(Vector2(hit.position.x, hit.position.z)): continue
		var crowded := false
		for other in items:
			if (other.pos as Vector3).distance_to(hit.position) < 3.0: crowded = true
		if crowded: continue
		# Rovná zeď kolem papíru a volno před ní.
		var ok := true
		var side := n.cross(Vector3.UP).normalized()
		for o in [side * 0.15, -side * 0.15, Vector3.UP * 0.18, Vector3.DOWN * 0.18]:
			var t: Vector3 = hit.position + o
			var h2 := space.intersect_ray(PhysicsRayQueryParameters3D.create(t + n * 0.3, t - n * 0.1, 1))
			if h2.is_empty() or (h2.normal as Vector3).dot(n) < 0.97: ok = false
		if ok and space.intersect_ray(PhysicsRayQueryParameters3D.create(hit.position + n * 0.05, hit.position + n * 1.0, 1)).is_empty():
			return {"pos": hit.position, "normal": n}
	return {}

func _build_ui() -> void:
	_layer = CanvasLayer.new()
	_layer.layer = 25
	add_child(_layer)
	_dim = ColorRect.new()
	_dim.color = Color(0, 0, 0, 0.55)
	_dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_dim)
	_paper = TextureRect.new()
	_paper.texture = load("res://textures/note_paper.png")
	_paper.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_paper.stretch_mode = TextureRect.STRETCH_SCALE
	_paper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_paper)
	var hand := SystemFont.new()
	hand.font_names = PackedStringArray(["Ink Free", "Segoe Print", "Bradley Hand", "Comic Sans MS", "DejaVu Serif"])
	_title = Label.new()
	_title.add_theme_font_override("font", hand)
	_title.add_theme_font_size_override("font_size", 40)
	_title.add_theme_color_override("font_color", Color(0.12, 0.1, 0.16))
	_paper.add_child(_title)
	_text = Label.new()
	_text.add_theme_font_override("font", hand)
	_text.add_theme_font_size_override("font_size", 27)
	_text.add_theme_color_override("font_color", Color(0.1, 0.1, 0.2, 0.92))
	_text.add_theme_constant_override("line_spacing", 8)
	_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_paper.add_child(_text)
	var hint := Label.new()
	hint.text = "E  /  Esc  zavřít"
	hint.add_theme_font_size_override("font_size", 18)
	hint.add_theme_color_override("font_color", Color(0.25, 0.22, 0.18, 0.8))
	hint.name = "Hint"
	_paper.add_child(hint)
	_layer.visible = false

func is_open() -> bool:
	return _open >= 0

func open(i: int) -> void:
	_open = i
	_read[i] = true
	_title.text = NOTES[i][1]
	_text.text = NOTES[i][2]
	_layer.visible = true
	_key_held = true
	main.sfx.play("item_pickup", -10.0, 1.4)
	_paper.modulate.a = 0.0
	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.tween_property(_paper, "modulate:a", 1.0, 0.25)

func open_text(title: String, text: String, when_closed: Callable = Callable()) -> void:
	# Lístek mimo zeď (z hlavní linky secretů): stejný papír, vlastní text.
	_open = 999
	_title.text = title
	_text.text = text
	_on_close = when_closed
	_layer.visible = true
	_key_held = true
	main.sfx.play("item_pickup", -10.0, 1.4)
	_paper.modulate.a = 0.0
	if _tween: _tween.kill()
	_tween = create_tween()
	_tween.tween_property(_paper, "modulate:a", 1.0, 0.25)

var _on_close: Callable

func close() -> void:
	_open = -1
	if _on_close.is_valid():
		var cb := _on_close
		_on_close = Callable()
		cb.call_deferred()
	closed_frame = Engine.get_process_frames()
	_layer.visible = false
	main.sfx.play("item_pickup", -14.0, 1.1)

func _input(event: InputEvent) -> void:
	# Esc zavře vzkaz a nesmí zároveň otevřít menu.
	if _open >= 0 and event is InputEventKey and event.pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()

func _process(_dt: float) -> void:
	if not _layer.visible: return
	var view := get_viewport().get_visible_rect().size
	var s := view.y / 1080.0
	_dim.size = view
	var size := Vector2(640, 853) * s
	_paper.size = size
	_paper.position = (view - size) * 0.5
	_paper.rotation = -0.012
	_title.position = Vector2(70, 60) * s
	_title.add_theme_font_size_override("font_size", int(40 * s))
	_text.position = Vector2(70, 140) * s
	_text.size = Vector2(500, 640) * s
	_text.add_theme_font_size_override("font_size", int(27 * s))
	var hint: Label = _paper.get_node("Hint")
	hint.position = Vector2(420, 790) * s
	hint.add_theme_font_size_override("font_size", int(18 * s))
	var pressed := Input.is_physical_key_pressed(KEY_E)
	if pressed and not _key_held: close()
	_key_held = pressed
