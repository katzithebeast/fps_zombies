extends Control
## Digitální minimapa: drž M (nebo Tab) a vpravo nahoře se vysune přiblížený výřez plánu,
## natočený podle pohledu. Neprozkoumané části jsou skryté, ukáže se jen bedna a zbraně na zdi.

const TEX_ORIGIN := Vector2(-36.0, -62.0)     # svět (x, z) levého horního rohu textury
const TEX_PX_PER_M := 15.0                    # 3 px na buňku 0,2 m
const SIZE := 300.0                           # výchozí velikost (nastavení „mini_size“)
const MARGIN := 28.0

var main: Node
var _tex: Texture2D
var _texs: Array[Texture2D] = []
var _size := SIZE
var _shown := 0.0
var _font: Font
var _pulse := 0.0
var force_show := false        # pro testy

func setup(main_node: Node) -> void:
	main = main_node
	for i in range(1, 6): _texs.append(load("res://textures/minimap_%d.png" % i))
	_tex = _texs[1]
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true          # otočená mapa nesmí přesahovat čtverec
	var font := SystemFont.new()
	font.font_names = PackedStringArray(["Bahnschrift", "Segoe UI", "Helvetica Neue", "Arial", "DejaVu Sans"])
	font.font_weight = 500
	_font = font
	modulate.a = 0.0

func _process(dt: float) -> void:
	var _perf_t0:=Time.get_ticks_usec()
	_process_timed(dt)
	PerfMon.add("Minimapa",Time.get_ticks_usec()-_perf_t0)

func _process_timed(dt: float) -> void:
	if main == null or main.player == null: return
	var menu_open: bool = main.menu != null and main.menu.is_open
	# Při úpravě minimapy v nastavení se ukáže nad menu a mění se živě.
	# Ve hře pod post-processem (vrstva 6 < 10), aby na ni působilo VHS i rybí oko;
	# v menu nad ním (41), aby byl vidět živý náhled.
	var layer := get_parent() as CanvasLayer
	if layer: layer.layer = 41 if menu_open else 6
	var preview: bool = menu_open and Time.get_ticks_msec() < int(main.menu.mini_preview_until)
	var want: bool = force_show or preview or ((Input.is_physical_key_pressed(KEY_M) or Input.is_physical_key_pressed(KEY_TAB)) \
		and not menu_open and main.player.control_enabled)
	_shown = move_toward(_shown, 1.0 if want else 0.0, dt * (7.0 if want else 5.0))
	_pulse += dt
	var view := get_viewport().get_visible_rect().size
	var s := view.y / 1080.0
	scale = Vector2(s, s)
	var st: Dictionary = main.settings
	_size = float(st.get("mini_size", SIZE))
	_tex = _texs[clampi(int(st.get("mini_line", 2)) - 1, 0, _texs.size() - 1)]
	size = Vector2(_size, _size)
	var ease: float = 1.0 - pow(1.0 - _shown, 3.0)
	# Pozice: 0 vpravo nahoře, 1 vlevo nahoře, 2 vlevo dole, 3 vpravo dole,
	# 4 nahoře uprostřed, 5 vlevo uprostřed, 6 dole uprostřed, 7 vpravo uprostřed.
	var anchor: Vector2 = [Vector2(1, 0), Vector2(0, 0), Vector2(0, 1), Vector2(1, 1),
		Vector2(0.5, 0), Vector2(0, 0.5), Vector2(0.5, 1), Vector2(1, 0.5)][clampi(int(st.get("mini_pos", 0)), 0, 7)]
	var box := Vector2(_size, _size) * s
	# Odsazení od okrajů (nastavení); ve VHS aspoň tolik, co má text kamery, ať to sedí do jednoho rámu.
	var m := float(st.get("mini_margin", 110.0))
	var vhs: float = float(main.get("_vhs")) if main.get("_vhs") != null else 0.0
	var margin := Vector2(maxf(m, lerpf(m, 200.0, vhs)), maxf(m * 0.6, lerpf(m * 0.6, 140.0, vhs)))
	var free := view - box - margin * s * 2.0
	var base := margin * s + free * anchor
	# Vysune se od nejbližšího okraje.
	var away := Vector2(anchor.x - 0.5, anchor.y - 0.5).sign()
	if away == Vector2.ZERO: away = Vector2(0, -1)
	position = base + away * (1.0 - ease) * 30.0 * s
	modulate.a = ease
	visible = _shown > 0.001
	if visible: queue_redraw()

func _draw() -> void:
	# Co nejjednodušší: tmavé pozadí, svítící zdi, hráč jako tečka. Mapa se točí podle pohledu.
	var _range: float = float(main.settings.get("mini_range", 20.0))
	var c := Vector2(_size, _size) * 0.5
	var bg := Color(0.0, 0.0, 0.0, 0.55)
	draw_rect(Rect2(Vector2.ZERO, Vector2(_size, _size)), bg)
	var cam: Camera3D = main.player.camera
	var p: Vector3 = main.player.global_position
	var fwd := -cam.global_basis.z
	var heading := atan2(fwd.x, -fwd.z)
	var k := ((_size * 0.5) / _range) / TEX_PX_PER_M
	var tex_player := (Vector2(p.x, p.z) - TEX_ORIGIN) * TEX_PX_PER_M
	draw_set_transform_matrix(Transform2D(-heading, Vector2(k, k), 0.0, c) * Transform2D(0.0, -tex_player))
	# Kreslí se jen prozkoumané části (s okrajem 1,5 m, ať jsou vidět i dveře a stěny na hranici).
	var view := Rect2(tex_player - Vector2.ONE * _range * 1.5 * TEX_PX_PER_M, Vector2.ONE * _range * 3.0 * TEX_PX_PER_M)
	var seen: Dictionary = main.areas.visited if main.areas else {}
	var tex_rect := Rect2(Vector2.ZERO, _tex.get_size())
	var done: Array[Rect2] = []
	for i in seen:
		var r: Rect2 = (main.MAP_RECTS[i] as Rect2).grow(1.5)
		var px := Rect2((r.position - TEX_ORIGIN) * TEX_PX_PER_M, r.size * TEX_PX_PER_M).intersection(tex_rect).intersection(view)
		if px.size.x <= 0.0 or px.size.y <= 0.0: continue
		# Překryv se sousední místností nekreslit dvakrát (záře by zesvětlala).
		var parts: Array[Rect2] = [px]
		for d in done: parts = _subtract(parts, d)
		for part in parts:
			if part.size.x > 0.5 and part.size.y > 0.5:
				draw_texture_rect_region(_tex, part, part, Color(0.85, 0.95, 1.0, 0.9))
		done.append(px)
	draw_set_transform_matrix(Transform2D.IDENTITY)
	draw_circle(c, 7.0, Color(1, 1, 1, 0.18))
	draw_circle(c, 4.0, Color(1, 1, 1, 1))

func _subtract(parts: Array[Rect2], cut: Rect2) -> Array[Rect2]:
	var out: Array[Rect2] = []
	for r in parts:
		var hit := r.intersection(cut)
		if hit.size.x <= 0.0 or hit.size.y <= 0.0:
			out.append(r)
			continue
		if hit.position.y > r.position.y: out.append(Rect2(r.position.x, r.position.y, r.size.x, hit.position.y - r.position.y))
		if hit.end.y < r.end.y: out.append(Rect2(r.position.x, hit.end.y, r.size.x, r.end.y - hit.end.y))
		if hit.position.x > r.position.x: out.append(Rect2(r.position.x, hit.position.y, hit.position.x - r.position.x, hit.size.y))
		if hit.end.x < r.end.x: out.append(Rect2(hit.end.x, hit.position.y, r.end.x - hit.end.x, hit.size.y))
	return out
