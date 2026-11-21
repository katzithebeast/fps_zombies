extends Node
## BODYCAM (experiment) – přepínač v Nastavení → Kamera, klávesa B.
##
## Obraz i pohyb jako z kamery připevněné na helmě:
## - objektiv: širokoúhlý (pevné zorné pole, při míření se nepřibližuje), zkreslení, vady, šum,
##   pomalá automatická expozice, rozmazání pohybem (shaders/bodycam.gdshader),
## - kamera nesleduje myš dokonale: tělo se otáčí se zpožděním, každý krok s ní cukne,
##   po sprintu se zadýchává,
## - volné míření: myš hýbe zbraní v malém okně, kamera ji dohání; zaměřovač se skryje
##   a střely letí ve směru hlavně. Při míření zbraň „přijde“ do středu.
##
## Posuvník „Bodycam – rozmazání pohybem“ řídí sílu rozmazání; VHS kamera (V) jde přes bodycam
## jako další průchod (bodycam -> kopie obrazovky -> běžný post.gdshader jen s VHS).
##
## Všechno je v tomhle souboru a v shaderu. Ve hře jsou jen háčky označené „BODYCAM“
## (main.gd, player.gd, player_weapon.gd, zombie_mode.gd, menu.gd). Vypnuto = hra beze změny.

const LENS_FOV := 98.0          # svislé zorné pole objektivu (střed po zkreslení odpovídá ~77°)
const LAG_HZ := 6.5             # jak rychle kamera dotáhne pohyb těla
const LAG_DAMP := 0.82
const DEAD_YAW := 0.085         # volné míření: jak daleko zbraň může odbočit bez otočení kamery (rad)
const DEAD_PITCH := 0.06
const RECENTER := 0.9           # jak rychle se kamera sama srovná za zbraní (1/s)
const SHUTTER_TIME := 1.0 / 70.0
const READOUT := 0.022          # čtení senzoru shora dolů (s) -> rolling shutter

var main: Node
var enabled := false
var mat: ShaderMaterial
var post_rect: CanvasItem
var post_mat: Material
var bc_rect: ColorRect          # vlastní průchod bodycamu (před běžným postprocesem)
var bc_copy: BackBufferCopy     # aby VHS navrch viděl už obraz z bodycamu
var vhs_mat: ShaderMaterial     # běžný post.gdshader jen s VHS (ostatní efekty má bodycam vlastní)

var _reset := true
var _base_yaw := 0.0
var _base_pitch := 0.0
var _s_yaw := 0.0
var _s_pitch := 0.0
var _v_yaw := 0.0
var _v_pitch := 0.0
var _jolt := Vector3.ZERO       # pitch, roll, výška
var _jolt_v := Vector3.ZERO
var _foot := 0
var _exert := 0.0
var _t := 0.0
var _noise := FastNoiseLite.new()
var _exposure_saved := {}
var ang_vel := Vector2.ZERO     # rad/s otáčení kamery (pro rozmazání)

func setup(m: Node, rect: CanvasItem, normal_mat: Material) -> void:
	main = m
	post_rect = rect
	post_mat = normal_mat
	mat = ShaderMaterial.new()
	mat.shader = load("res://shaders/bodycam.gdshader")
	# pořadí ve vrstvě postprocesu: bodycam -> kopie obrazovky -> VHS (běžný průchod)
	var layer: Node = rect.get_parent()
	bc_rect = ColorRect.new()
	bc_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	bc_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	bc_rect.material = mat
	bc_rect.visible = false
	layer.add_child(bc_rect)
	layer.move_child(bc_rect, rect.get_index())
	bc_copy = BackBufferCopy.new()
	bc_copy.copy_mode = BackBufferCopy.COPY_MODE_VIEWPORT
	bc_copy.visible = false
	layer.add_child(bc_copy)
	layer.move_child(bc_copy, rect.get_index())
	vhs_mat = ShaderMaterial.new()
	vhs_mat.shader = (normal_mat as ShaderMaterial).shader
	for k in ["fisheye", "vignette", "grain", "aberration", "sharpen"]:
		vhs_mat.set_shader_parameter(k, 0.0)
	vhs_mat.set_shader_parameter("contrast", 1.0)
	vhs_mat.set_shader_parameter("gamma", 1.0)
	_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	_noise.frequency = 1.0

func set_enabled(v: bool) -> void:
	if v == enabled: return
	enabled = v
	_reset = true
	_apply_exposure()

func active() -> bool:
	var p: Node = main.player if main else null
	return enabled and p != null and not p.third_person and p.camera.is_current()

## Automatická expozice jako u kamery: z tmy do světla na chvíli přepálí a pak se srovná.
func _apply_exposure() -> void:
	var a: CameraAttributesPractical = main.cam_attr if main else null
	if a == null: return
	if enabled:
		if _exposure_saved.is_empty():
			_exposure_saved = {"on": a.auto_exposure_enabled, "scale": a.auto_exposure_scale, "speed": a.auto_exposure_speed,
				"min": a.auto_exposure_min_sensitivity, "max": a.auto_exposure_max_sensitivity}
		a.auto_exposure_enabled = true
		# úzký rozsah: ve tmě obraz jen trochu zesílí (hra má zůstat temná), ve světle na chvíli přepálí
		a.auto_exposure_scale = 0.2
		a.auto_exposure_speed = 0.5
		a.auto_exposure_min_sensitivity = 60.0
		a.auto_exposure_max_sensitivity = 120.0
	elif not _exposure_saved.is_empty():
		a.auto_exposure_enabled = _exposure_saved.on
		a.auto_exposure_scale = _exposure_saved.scale
		a.auto_exposure_speed = _exposure_saved.speed
		a.auto_exposure_min_sensitivity = _exposure_saved.min
		a.auto_exposure_max_sensitivity = _exposure_saved.max
		_exposure_saved = {}

static func _spring(x: float, v: float, goal: float, w: float, z: float, dt: float) -> Vector2:
	var sub := maxi(1, ceili(dt * w / 0.35))
	var h := dt / sub
	for i in sub:
		v += ((goal - x) * w * w - v * 2.0 * z * w) * h
		x += v * h
	return Vector2(x, v)

## Volá player.gd po nastavení kamery (fyzikální krok, jen v první osobě).
func apply_camera(p: Node, dt: float) -> void:
	var on := active()
	p.body.weapon.bodycam = on
	if not on:
		_reset = true
		ang_vel = Vector2.ZERO
		return
	var head: Node3D = p.head
	var cam: Camera3D = p.camera
	var t_yaw: float = head.rotation.y          # pohled podle myši včetně jemného pohybu kamery hry
	var t_pitch: float = cam.rotation.x
	if _reset:
		_reset = false
		_base_yaw = p.yaw
		_base_pitch = p.pitch
		_s_yaw = t_yaw
		_s_pitch = t_pitch
		_v_yaw = 0.0
		_v_pitch = 0.0
	_t += dt
	# volné míření: kamera míří na „základnu“, která zbraň následuje jen mimo malé okno
	var aim: float = p.weapon.aim_amount
	var zy := lerpf(DEAD_YAW, 0.0, aim)
	var zp := lerpf(DEAD_PITCH, 0.0, aim)
	var dy := wrapf(p.yaw - _base_yaw, -PI, PI)
	_base_yaw = p.yaw - clampf(dy, -zy, zy)
	_base_pitch = p.pitch - clampf(p.pitch - _base_pitch, -zp, zp)
	var rc := 1.0 - exp(-(RECENTER + aim * 8.0) * dt)
	_base_yaw += wrapf(p.yaw - _base_yaw, -PI, PI) * rc
	_base_pitch += (p.pitch - _base_pitch) * rc
	var goal_yaw: float = t_yaw - wrapf(p.yaw - _base_yaw, -PI, PI)
	var goal_pitch: float = t_pitch - (p.pitch - _base_pitch)
	# tělo s kamerou dotahuje pohyb se zpožděním (kriticky tlumená pružina)
	var w := TAU * LAG_HZ
	var gy := _s_yaw + wrapf(goal_yaw - _s_yaw, -PI, PI)
	var r := _spring(_s_yaw, _v_yaw, gy, w, LAG_DAMP, dt)
	_s_yaw = wrapf(r.x, -PI, PI)
	_v_yaw = r.y
	r = _spring(_s_pitch, _v_pitch, goal_pitch, w, LAG_DAMP, dt)
	_s_pitch = r.x
	_v_pitch = r.y
	ang_vel = Vector2(_v_yaw, _v_pitch)
	# kroky: při každém došlapu kamera na helmě cukne dolů a ke straně nohy
	var speed := Vector2(p.velocity.x, p.velocity.z).length()
	var grounded: bool = p.is_on_floor()
	var foot := floori((float(p._bob_phase) - PI * 0.5) / PI)
	if foot != _foot:
		var forward_step := foot > _foot
		_foot = foot
		if forward_step and grounded and speed > 0.6:
			var k := clampf(speed / 4.0, 0.25, 1.2)
			var side := 1.0 if foot % 2 == 0 else -1.0
			_jolt_v += Vector3(-0.32 * k, 0.16 * side * k, -0.22 * k)
	var wj := 17.0
	for i in 3:
		_jolt_v += ((-_jolt) * wj * wj - _jolt_v * 2.0 * 0.45 * wj) * (dt / 3.0)
		_jolt += _jolt_v * (dt / 3.0)
	# dech: po sprintu se kamera zhoupe víc a rychleji, pomalu se uklidní
	var sprinting: bool = p._sprint and speed > 4.0 and grounded
	_exert = move_toward(_exert, 1.0, dt * 0.22) if sprinting else move_toward(_exert, 0.0, dt * 0.07)
	var e := _exert * _exert
	var bf := lerpf(0.27, 0.62, e) * TAU
	var br_pitch := sin(_t * bf) * lerpf(0.0035, 0.017, e)
	var br_roll := sin(_t * bf * 0.5 + 0.7) * lerpf(0.002, 0.008, e)
	var br_y := sin(_t * bf) * lerpf(0.002, 0.009, e)
	# helma se nikdy nedrží úplně klidně
	var move := clampf(speed / 3.0, 0.0, 1.0)
	var hh := 0.0022 + 0.003 * move
	var n_yaw := _noise.get_noise_2d(_t * 1.3, 5.0) * hh + _noise.get_noise_2d(_t * 9.0, 40.0) * 0.0005
	var n_pitch := _noise.get_noise_2d(_t * 1.3, 17.0) * hh + _noise.get_noise_2d(_t * 9.0, 60.0) * 0.0005
	head.rotation.y = _s_yaw + n_yaw
	cam.rotation.x = _s_pitch + n_pitch + br_pitch + _jolt.x * 0.1
	cam.rotation.z += br_roll + _jolt.y * 0.1
	cam.position.y += br_y + _jolt.z * 0.1
	cam.fov = LENS_FOV

## Směr střely: kam míří hlaveň (ne střed obrazu). Počátek zůstává v kameře, ať střela
## nezačíná za zdí, před kterou se zbraň zrovna odklání.
func aim_transform(p: Node) -> Transform3D:
	var rig: Node = p.body.weapon
	var holder: Node3D = rig.first
	var fwd: Vector3 = (holder.global_basis * Vector3(0, 0, -1)).normalized()
	if absf(fwd.dot(Vector3.UP)) > 0.98: return p.camera.global_transform
	return Transform3D(Basis.looking_at(fwd, Vector3.UP), p.camera.global_position)

func _process(_dt: float) -> void:
	if post_rect == null: return
	var on := active()
	bc_rect.visible = on
	bc_copy.visible = on
	if not on:
		if post_rect.material != post_mat: post_rect.material = post_mat
		post_rect.visible = true
		return
	# VHS kamera (klávesa V) jde i přes bodycam: běžný průchod pak dělá už jen VHS
	var vhs := float(post_mat.get_shader_parameter("vhs"))
	if post_rect.material != vhs_mat: post_rect.material = vhs_mat
	post_rect.visible = vhs > 0.001
	vhs_mat.set_shader_parameter("vhs", vhs)
	for k in ["vhs_band", "vhs_bottom"]:      # úvodní briefing je vypíná
		var pv: Variant = post_mat.get_shader_parameter(k)
		if pv != null: vhs_mat.set_shader_parameter(k, pv)
	var cam: Camera3D = main.player.camera
	var vp := get_viewport().get_visible_rect().size
	var fov_v := deg_to_rad(cam.fov)
	var fov_h := 2.0 * atan(tan(fov_v * 0.5) * vp.x / maxf(vp.y, 1.0))
	var blur := clampf(float(main.settings.get("bodycam_blur", 1.0)), 0.0, 3.0)     # posuvník v nastavení
	mat.set_shader_parameter("motion", Vector2(ang_vel.x * SHUTTER_TIME / fov_h, ang_vel.y * SHUTTER_TIME / fov_v) * blur)
	mat.set_shader_parameter("shutter", -ang_vel.x * READOUT / fov_h)
	var spd: float = Vector2(main.player.velocity.x, main.player.velocity.z).length()
	mat.set_shader_parameter("codec", clampf(ang_vel.length() / 3.5 + maxf(spd - 3.0, 0.0) * 0.08, 0.0, 1.0))
	mat.set_shader_parameter("contrast", post_mat.get_shader_parameter("contrast"))
	mat.set_shader_parameter("gamma", post_mat.get_shader_parameter("gamma"))
