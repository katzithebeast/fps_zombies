extends CanvasLayer
## Úvodní briefing: velitel přes vysílačku, ilustrace s pomalým posunem/zoomem
## a přechodem „inkoust ve vodě“. Mezerník / Enter / Esc přeskočí.

signal finished

const VOICE := "res://audio/briefing_voice.wav"
# [obrázek, začátek (s), zoom od, zoom do, střed od, střed do]
const SHOTS := [
	["01", 0.0, 1.0, 1.07, Vector2(0.5, 0.5), Vector2(0.46, 0.47), 0.85],
	["02", 10.2, 1.06, 1.08, Vector2(0.46, 0.5), Vector2(0.54, 0.5), 0.85],
	["03", 16.0, 1.0, 1.09, Vector2(0.5, 0.5), Vector2(0.52, 0.46), 0.85],
	["04", 22.4, 1.06, 1.08, Vector2(0.5, 0.46), Vector2(0.5, 0.53), 0.8],
	["06", 26.8, 1.0, 1.07, Vector2(0.5, 0.5), Vector2(0.53, 0.54), 0.8],
	["05", 31.8, 1.1, 1.0, Vector2(0.5, 0.5), Vector2(0.5, 0.5), 0.8],
	["07", 41.3, 1.0, 1.08, Vector2(0.5, 0.5), Vector2(0.47, 0.56), 0.75],
	["08", 50.3, 1.0, 1.1, Vector2(0.5, 0.5), Vector2(0.5, 0.48), 0.62],
]
const SUBS := [
	[0.6, 4.2, "Jednotko sedm, tady centrála. Slyšíte mě?"],
	[4.3, 6.4, "…Dobře. Poslouchejte pozorně."],
	[6.5, 9.1, "Jste u starých městských lázní."],
	[9.2, 11.1, "Zavřených od srpna '74."],
	[11.2, 14.5, "Oficiální zpráva mluví o technické závadě."],
	[14.6, 16.7, "Oficiální zpráva lže."],
	[16.8, 21.6, "V té budově zmizelo dvacet tři lidí."],
	[21.7, 25.0, "Personál, plavci… děti."],
	[25.1, 27.3, "Těla se nikdy nenašla."],
	[27.4, 32.6, "Váš úkol: jděte dovnitř a zjistěte, co se stalo. Záznamy, vzkazy, cokoli tam zůstalo."],
	[32.7, 36.7, "Musíme vědět, co je v té vodě."],
	[36.8, 41.0, "Nebojujte, pokud nemusíte. Nevypouštějte bazény."],
	[41.1, 42.1, "Ať tam dole najdete cokoli… zdokumentujte to."],
	[42.2, 48.9, "Ještě jedna věc. Poslední tým přestal hlásit po čtyřiceti minutách."],
	[49.0, 51.2, "Jejich poslední vysílání bylo… jen něčí smích."],
	[51.3, 54.6, "Zůstaňte na příjmu, jednotko sedm. Konec."],
]
const TRANSITION := 3.4         # pomalé rozpíjení inkoustu
const END := 58.5

var _rect: ColorRect
var _mat: ShaderMaterial
var _post: ShaderMaterial
var _sub: Label
var _hint: Label
var _voice: AudioStreamPlayer
var _tex := {}
var _t := 0.0
var _shown_a := -1
var _shown_b := -1
var _ending := false
var _done := false
var _fade_in := 0.0

func _ready() -> void:
	layer = 60
	process_mode = Node.PROCESS_MODE_ALWAYS
	for s in SHOTS: _tex[s[0]] = load("res://textures/briefing/briefing_%s.jpg" % s[0])
	_rect = ColorRect.new()
	_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/briefing_ink.gdshader")
	var noise := FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.012
	noise.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = 512
	nt.height = 512
	nt.seamless = true
	nt.noise = noise
	_mat.set_shader_parameter("noise_tex", nt)
	_rect.material = _mat
	add_child(_rect)
	# Stejný VHS post-process, jaký má hra (čte obraz pod sebou).
	var post_rect := ColorRect.new()
	post_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	post_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post = ShaderMaterial.new()
	_post.shader = load("res://shaders/post.gdshader")
	_post.set_shader_parameter("vhs", 1.0)
	_post.set_shader_parameter("fisheye", 0.0)
	_post.set_shader_parameter("vignette", 0.25)
	_post.set_shader_parameter("sharpen", 0.0)
	_post.set_shader_parameter("vhs_band", 0.0)
	_post.set_shader_parameter("vhs_bottom", 0.0)
	post_rect.material = _post
	add_child(post_rect)
	_sub = Label.new()
	_sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_sub.add_theme_color_override("font_color", Color(0.95, 0.93, 0.86))
	_sub.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.9))
	_sub.add_theme_constant_override("shadow_offset_x", 2)
	_sub.add_theme_constant_override("shadow_offset_y", 2)
	add_child(_sub)
	_hint = Label.new()
	_hint.text = "Mezerník — přeskočit"
	_hint.add_theme_color_override("font_color", Color(1, 1, 1, 0.35))
	add_child(_hint)
	_voice = AudioStreamPlayer.new()
	_voice.stream = load(VOICE)
	add_child(_voice)
	_voice.play()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		var k := (event as InputEventKey).physical_keycode
		if k in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER, KEY_ESCAPE]:
			get_viewport().set_input_as_handled()
			_finish()

func _process(dt: float) -> void:
	if _done: return
	# Čas podle zvuku, aby obrázky a titulky seděly přesně na dabing.
	if _voice.playing: _t = _voice.get_playback_position() + AudioServer.get_time_since_last_mix()
	else: _t += dt
	var view := get_viewport().get_visible_rect().size
	var s := view.y / 1080.0
	_mat.set_shader_parameter("screen_aspect", view.x / view.y)
	_mat.set_shader_parameter("aspect_fix", (view.x / view.y) / (16.0 / 9.0))
	_mat.set_shader_parameter("time", _t)
	# VHS jako ve hře; na začátku se páska chvíli „chytá“ (víc zrna a chvění).
	_post.set_shader_parameter("grain", 0.04 + 0.08 * (1.0 - smoothstep(0.0, 2.5, _t)))
	# Který obrázek je teď a jestli právě probíhá přechod.
	var i := 0
	for k in SHOTS.size():
		if _t >= float(SHOTS[k][1]): i = k
	var since: float = _t - float(SHOTS[i][1])
	var a := i
	var b := i
	var prog := 0.0
	if i > 0 and since < TRANSITION:
		a = i - 1
		var x := since / TRANSITION
		prog = x * x * (3.0 - 2.0 * x)
	_set_tex(a, b)
	_mat.set_shader_parameter("progress", prog)
	_mat.set_shader_parameter("kb_a", _kb(a))
	_mat.set_shader_parameter("kb_b", _kb(b))
	_fade_in = minf(1.0, _fade_in + dt / 1.2)
	var fade := _fade_in
	if _t > END - 2.5: fade = minf(fade, clampf((END - _t) / 2.5, 0.0, 1.0))
	_mat.set_shader_parameter("fade", fade)
	# Titulky.
	var text := ""
	for sub in SUBS:
		if _t >= float(sub[0]) and _t < float(sub[1]): text = sub[2]
	_sub.text = text
	_sub.add_theme_font_size_override("font_size", int(30 * s))
	_sub.size = Vector2(view.x * 0.7, 120 * s)
	_sub.position = Vector2(view.x * 0.15, view.y - 170 * s)
	_hint.add_theme_font_size_override("font_size", int(18 * s))
	_hint.position = Vector2(view.x - 260 * s, view.y - 50 * s)
	if _t >= END: _finish()

func _set_tex(a: int, b: int) -> void:
	if a != _shown_a:
		_shown_a = a
		_mat.set_shader_parameter("tex_a", _tex[SHOTS[a][0]])
	if b != _shown_b:
		_shown_b = b
		_mat.set_shader_parameter("tex_b", _tex[SHOTS[b][0]])

func _kb(i: int) -> Vector4:
	# Pomalý zoom a posun přes celou dobu, kdy je obrázek vidět (včetně přechodů).
	var start: float = SHOTS[i][1]
	var stop: float = SHOTS[i + 1][1] + TRANSITION if i + 1 < SHOTS.size() else END
	var k := clampf((_t - start) / maxf(stop - start, 0.1), 0.0, 1.0)
	k = k * k * (3.0 - 2.0 * k) * 0.35 + k * 0.65
	var zoom: float = lerpf(SHOTS[i][2], SHOTS[i][3], k)
	var c: Vector2 = (SHOTS[i][4] as Vector2).lerp(SHOTS[i][5], k)
	# Střed tak, aby se nikdy neukázal okraj obrázku.
	var half := 0.5 / zoom
	c.x = clampf(c.x, half, 1.0 - half)
	c.y = clampf(c.y, half, 1.0 - half)
	return Vector4(zoom, c.x, c.y, float(SHOTS[i][6]) if SHOTS[i].size() > 6 else 1.0)

func _finish() -> void:
	if _done or _ending: return
	_ending = true
	var tw := create_tween()
	tw.tween_method(func(v: float): _mat.set_shader_parameter("fade", v), 1.0 if _t < END - 1.5 else 0.0, 0.0, 0.6)
	tw.parallel().tween_property(_voice, "volume_db", -40.0, 0.6)
	tw.parallel().tween_property(_sub, "modulate:a", 0.0, 0.4)
	tw.tween_callback(func():
		_done = true
		finished.emit()
		queue_free())
