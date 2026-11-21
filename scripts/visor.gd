extends Node
## VISOR (experiment) – hledí helmy ve vlastním pohledu. Nastavení → Kamera, klávesa H = otřít hledí.
##
## Sklo hledí je mezi okem a světem, takže se na něm drží to, co by se na skutečné helmě drželo:
## - krev: cákance při úderu pažbou nebo výstřelu zblízka, otisk dlaně, když zombie udeří,
##   pomalu stéká dolů,
## - kapky vody: po plavání a šplouchnutí, větší pomalu stékají a samy oschnou,
## - zamlžení zevnitř: po sprintu a při zadýchání (s výdechem se dole u úst orosí víc);
##   to je uvnitř helmy, rukou nejde setřít – zmizí, až se postava vydýchá,
## - rám hledí, lom na zakřiveném okraji, jemné šmouhy (kolem světel záře).
##
## Otření: levá ruka pustí zbraň, přejede dlaní po hledí zleva doprava a vrátí se.
## Kde dlaň přejela, je sklo čisté (krev zůstane rozmazaná do pruhů a pomalu zmizí).
## Spustí se samo, když je hledí špinavé (lze vypnout), a vždy klávesou H.
##
## Všechno je v tomhle souboru a v shaders/visor.gdshader. Ve hře jsou jen háčky označené „VISOR“
## (main.gd, menu.gd, weapon_rig.gd, player_weapon.gd, player_body.gd, zombie_mode.gd).
## Vypnuto = hra beze změny.

const MASK_W := 128
const MASK_H := 72
const MAX_SPLATS := 8
const AUTO_COOLDOWN := 2.5

var main: Node
var player: Node
var enabled := false
var auto_wipe := true
var rect: ColorRect
var copy: BackBufferCopy
var mat: ShaderMaterial
var _mask_img: Image
var _mask_tex: ImageTexture
var _wipes := 0                 # kolik otření už proběhlo (hodnota v masce)
var _now := 0.0
var _splats: Array = []         # {pos, size, rot, birth, alpha, cell, k, wiped, run, seed}
var _wet := 0.0
var _wet_k := 0.0
var _wet_seed := 0.0
var _wet_t := -100.0            # kdy bylo hledí naposledy namočené
var _wet_age := 0.0
var _exert := 0.0
var _breath_ph := 0.0
var _dirty_t := -100.0          # kdy naposledy přibyla špína (auto otření chvíli počká)
var _last_wipe := -100.0
var _last_shot := -100.0
var _prev_rect := Rect2i()
var _painting := false
var _snd: AudioStreamPlayer

func setup(m: Node, layer: Node, p: Node) -> void:
	main = m
	player = p
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/visor.gdshader")
	mat.set_shader_parameter("blood_atlas", load("res://assets/visor/visor_blood_atlas.png"))
	_mask_img = Image.create(MASK_W, MASK_H, false, Image.FORMAT_R8)
	_mask_img.fill(Color(0, 0, 0))
	_mask_tex = ImageTexture.create_from_image(_mask_img)
	mat.set_shader_parameter("wipe_mask", _mask_tex)
	# pořadí ve vrstvě postprocesu: hledí -> kopie obrazovky -> (bodycam) -> běžný postproces
	rect = ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.material = mat
	rect.visible = false
	layer.add_child(rect)
	layer.move_child(rect, 0)
	copy = BackBufferCopy.new()
	copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	copy.visible = false
	layer.add_child(copy)
	layer.move_child(copy, 1)
	_snd = AudioStreamPlayer.new()
	_snd.stream = load("res://audio/visor_wipe.wav")
	_snd.volume_db = -7.0
	add_child(_snd)

func set_enabled(v: bool) -> void:
	enabled = v
	if not v:
		clear()

func active() -> bool:
	if not enabled or player == null or not is_instance_valid(player): return false
	return not player.camera_uses_third_person and player.camera.is_current()

func clear() -> void:
	_splats.clear()
	_wet = 0.0
	_exert = 0.0
	_wipes = 0
	if _mask_img:
		_mask_img.fill(Color(0, 0, 0))
		_mask_tex.update(_mask_img)

func _rig() -> Node:
	return player.body.weapon if player and player.body else null

# ------------------------------------------------------------------ události ze hry

## Zásah zombie (main._strike_effects). Zblízka krev odletí i na hledí.
func on_strike(point: Vector3, direction: Vector3, lethal: bool, melee: bool) -> void:
	if not active(): return
	if not melee: _last_shot = _now
	var cam: Camera3D = player.camera
	var to: Vector3 = point - cam.global_position
	var dist := to.length()
	var reach := 1.9 if melee else (1.7 if lethal else 1.35)
	if dist > reach or (-cam.global_basis.z).dot(to.normalized()) < 0.2: return
	var chance := (0.9 if melee else 0.5) * (1.0 - dist / reach * 0.6) + (0.2 if lethal else 0.0)
	if randf() > chance: return
	var at := _screen_uv(point)
	var near := 1.0 - dist / reach
	var cells := [0, 1, 2, 5] if (melee or lethal) else [3, 4, 3, 0]
	_add_splat(at + Vector2(randf_range(-0.12, 0.12), randf_range(-0.1, 0.1)), lerpf(0.28, 0.62, near) * (1.15 if melee else 1.0),
		cells[randi() % cells.size()], lerpf(0.55, 0.95, near))
	if melee and randf() < 0.5:
		_add_splat(at + Vector2(randf_range(-0.3, 0.3), randf_range(-0.2, 0.2)), randf_range(0.15, 0.3), 3, 0.7)

## Zombie udeřila hráče (zombie_mode.hurt): otisk dlaně nebo šmouha z té strany, odkud přišla rána.
func on_hurt(_damage: float, source: Node3D) -> void:
	if not active(): return
	var side := randf_range(-0.2, 0.2)
	if source and is_instance_valid(source):
		var local: Vector3 = player.camera.global_basis.inverse() * (source.global_position - player.camera.global_position)
		side = clampf(local.x * 0.6, -0.3, 0.3)
	var at := Vector2(0.5 + side + randf_range(-0.08, 0.08), randf_range(0.35, 0.6))
	if randf() < 0.6:
		_add_splat(at, randf_range(0.75, 1.0), 6 + randi() % 2, randf_range(0.75, 0.95), randf_range(-0.6, 0.6) + side)
	else:
		_add_splat(at, randf_range(0.45, 0.7), [0, 2, 5][randi() % 3], 0.85)
	if randf() < 0.4:
		_add_splat(Vector2(randf_range(0.2, 0.8), randf_range(0.2, 0.8)), randf_range(0.2, 0.35), 3, 0.7)
	_exert = minf(1.0, _exert + 0.15)

func _aspect() -> float:
	var vs: Vector2 = get_viewport().get_visible_rect().size
	return vs.x / maxf(vs.y, 1.0)

func _screen_uv(world: Vector3) -> Vector2:
	var cam: Camera3D = player.camera
	if cam.is_position_behind(world): return Vector2(0.5, 0.5)
	var px: Vector2 = cam.unproject_position(world)
	var vs: Vector2 = get_viewport().get_visible_rect().size
	return (px / vs).clamp(Vector2(0.08, 0.1), Vector2(0.92, 0.9))

func _add_splat(uv: Vector2, size: float, cell: int, alpha: float, rot := INF) -> void:
	if _splats.size() >= MAX_SPLATS:
		# nejdřív zmizí otřené, pak nejstarší
		var drop := 0
		for i in _splats.size():
			if _splats[i].wiped >= 0.0:
				drop = i
				break
		_splats.remove_at(drop)
	var heavy := cell in [0, 2, 5, 6]
	_splats.append({"pos": Vector2(uv.x * _aspect(), uv.y), "size": size, "rot": rot if rot != INF else randf_range(-PI, PI) * (0.25 if cell >= 6 else 1.0),
		"birth": _now, "alpha": alpha, "cell": cell, "k": float(_wipes), "wiped": -1.0,
		"run": randf_range(0.03, 0.08) if heavy else randf_range(0.0, 0.025), "seed": randf()})
	_dirty_t = _now

## Otřít hledí (klávesa H nebo automaticky). Vrátí false, když ruka teď nemůže.
func wipe() -> bool:
	if not active(): return false
	var rig := _rig()
	if rig == null or player.swimming: return false
	var pw: Node = player.weapon
	if pw.reload_left > 0.0 or pw.melee_left > 0.0: return false
	if not rig.start_wipe(): return false
	_wipes += 1
	if _wipes >= 250:
		# maska počítá otření do 255: po dlouhé hře začít znovu s čistým hledím
		clear()
		_wipes = 1
	_last_wipe = _now
	_painting = false
	_snd.pitch_scale = randf_range(0.92, 1.08)
	_snd.play()
	return true

# ------------------------------------------------------------------ každý snímek

func _process(dt: float) -> void:
	_now += dt
	var on := active()
	rect.visible = on
	copy.visible = on
	if player == null or not is_instance_valid(player): return
	var rig := _rig()
	if not on:
		return
	_update_wet(dt)
	_update_fog(dt)
	if rig: _paint_wipe(rig)
	_update_splats()
	if auto_wipe and rig and _wants_wipe(): wipe()
	_push_uniforms(rig)

func _update_wet(dt: float) -> void:
	var cam_y: float = player.camera.global_position.y
	var soaked: bool = player.swimming and cam_y < float(player.water_y) + 0.3
	if soaked:
		if _wet < 0.3 or _wet_k < float(_wipes):
			_wet_seed = randf() * 100.0
		_wet = 1.0
		_wet_k = float(_wipes)
		_wet_t = _now
		_dirty_t = _now
	else:
		# kapky pomalu oschnou a stečou
		_wet = maxf(0.0, _wet - dt / 22.0)
	_wet_age = _now - _wet_t

func _update_fog(dt: float) -> void:
	var v: Vector3 = player.velocity
	var speed := Vector2(v.x, v.z).length()
	var sprinting: bool = player._sprint and speed > 4.0
	if sprinting: _exert = minf(1.0, _exert + dt / 7.0)
	else: _exert = maxf(0.0, _exert - dt / (16.0 if speed > 1.0 else 11.0))
	_breath_ph += dt * TAU * lerpf(0.22, 0.6, _exert)

func _paint_wipe(rig: Node) -> void:
	if float(rig.wipe_contact) < 0.5:
		_painting = false
		return
	var cam: Camera3D = player.camera
	var pts: Array = [rig.wipe_wrist, rig.wipe_palm, rig.wipe_tip]
	var vs: Vector2 = get_viewport().get_visible_rect().size
	var lo := Vector2(INF, INF)
	var hi := Vector2(-INF, -INF)
	for w in pts:
		var wp: Vector3 = w
		if cam.is_position_behind(wp): continue
		var s: Vector2 = cam.unproject_position(wp) / vs * Vector2(MASK_W, MASK_H)
		lo = lo.min(s)
		hi = hi.max(s)
	if lo.x == INF: return
	# šířka dlaně (rukavice ~9 cm) promítnutá na obraz
	var palm: Vector3 = rig.wipe_palm
	var side: Vector3 = cam.global_basis.x * 0.05
	var half := absf((cam.unproject_position(palm + side) - cam.unproject_position(palm)).x) / vs.x * MASK_W
	lo.x -= half
	hi.x += half
	lo.y -= half * 0.5
	hi.y = maxf(hi.y, lo.y)
	var r := Rect2i(Vector2i(floori(lo.x), floori(lo.y)), Vector2i(ceili(hi.x - lo.x) + 1, ceili(hi.y - lo.y) + 1))
	# spojit s minulým snímkem, ať při rychlém tahu nezůstanou mezery
	var paint := r.merge(_prev_rect) if _painting else r
	_prev_rect = r
	_painting = true
	paint = paint.intersection(Rect2i(0, 0, MASK_W, MASK_H))
	if paint.size.x <= 0 or paint.size.y <= 0: return
	_mask_img.fill_rect(paint, Color(float(_wipes) / 255.0, 0, 0))
	_mask_tex.update(_mask_img)

func _mask_at(uv: Vector2) -> float:
	var x := clampi(int(uv.x * MASK_W), 0, MASK_W - 1)
	var y := clampi(int(uv.y * MASK_H), 0, MASK_H - 1)
	return roundf(_mask_img.get_pixel(x, y).r * 255.0)

func _update_splats() -> void:
	var aspect := _aspect()
	for i in range(_splats.size() - 1, -1, -1):
		var s: Dictionary = _splats[i]
		if s.wiped < 0.0 and _mask_at(Vector2(s.pos.x / aspect, s.pos.y)) > s.k:
			s.wiped = _now
		# otřená šmouha po čase zmizí úplně
		if s.wiped >= 0.0 and _now - s.wiped > 40.0:
			_splats.remove_at(i)

func _dirt() -> float:
	var d := 0.0
	var aspect := _aspect()
	for s in _splats:
		if s.wiped < 0.0:
			d += float(s.alpha) * float(s.size) * (1.4 if absf(s.pos.x / aspect - 0.5) < 0.3 else 0.7)
	var wet_left := _wet if _wet_k >= float(_wipes) else 0.0
	return d + wet_left * 0.9

func _wants_wipe() -> bool:
	if _now - _last_wipe < AUTO_COOLDOWN: return false
	if _now - _dirty_t < 0.9 or _now - _last_shot < 0.8: return false
	if player.swimming or player.weapon.aiming: return false
	return _dirt() > 0.32

func _push_uniforms(rig: Node) -> void:
	var a := PackedVector4Array()
	var b := PackedVector4Array()
	var c := PackedVector4Array()
	a.resize(MAX_SPLATS)
	b.resize(MAX_SPLATS)
	c.resize(MAX_SPLATS)
	for i in _splats.size():
		var s: Dictionary = _splats[i]
		a[i] = Vector4(s.pos.x, s.pos.y, s.size, s.rot)
		b[i] = Vector4(s.birth, s.alpha, float(s.cell), s.k)
		c[i] = Vector4(s.wiped, s.run, s.seed, 0.0)
	mat.set_shader_parameter("splat_a", a)
	mat.set_shader_parameter("splat_b", b)
	mat.set_shader_parameter("splat_c", c)
	mat.set_shader_parameter("splat_count", _splats.size())
	mat.set_shader_parameter("now", _now)
	mat.set_shader_parameter("wet", _wet)
	mat.set_shader_parameter("wet_k", _wet_k)
	mat.set_shader_parameter("wet_seed", _wet_seed)
	mat.set_shader_parameter("wet_age", _wet_age)
	mat.set_shader_parameter("fog", smoothstep(0.3, 1.0, _exert) * 0.6)
	mat.set_shader_parameter("breath", smoothstep(0.15, 0.7, _exert) * pow(maxf(0.0, sin(_breath_ph)), 3.0))
	mat.set_shader_parameter("wipe_now", float(rig.wipe) if rig else 0.0)
	var look: Variant = main.settings.get("look_visor", Color(0.86, 0.69, 0.19)) if main and "settings" in main else Color(0.86, 0.69, 0.19)
	var tc: Color = look
	mat.set_shader_parameter("tint", Vector3(tc.r, tc.g, tc.b).normalized() * 1.7)
