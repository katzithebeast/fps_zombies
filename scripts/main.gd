extends Node3D
const Props := preload("res://scripts/props.gd")
## HLADINA: poolrooms tech demo. Celá úroveň se staví v kódu (žádné externí modely).
## Rozměry jsou v metrech, hladina vody je v y = 0.

const WATER_Y := 0.0
# Půdorys všech místností a chodeb (pro rozmístění krve, nepořádku a mrtvol).
const MAP_RECTS := [
	Rect2(-2.6, -1.2, 5.2, 12.0), Rect2(2.6, -1.2, 10.0, 12.0), Rect2(-12.6, -26.6, 25.2, 25.4),
	Rect2(-22.6, -19.8, 10.0, 9.4), Rect2(-31.2, -22.8, 18.6, 3.0), Rect2(12.0, -15.6, 8.0, 3.2),
	Rect2(20.0, -34.6, 27.2, 33.2), Rect2(23.4, -1.4, 19.2, 19.0), Rect2(42.6, 11.4, 10.0, 12.6),
	Rect2(45.4, 23.4, 17.2, 17.2), Rect2(37.4, 17.6, 8.0, 11.0), Rect2(-13.2, -46.6, 26.4, 20.6),
	Rect2(-33.8, -59.4, 20.6, 36.6), Rect2(-10.6, -59.4, 15.2, 12.8), Rect2(4.6, -53.5, 9.2, 3.0),
	Rect2(13.2, -56.6, 17.4, 22.6), Rect2(12.0, 1.4, 7.6, 7.6), Rect2(-12.0, -0.6, 9.4, 10.6)]
const SPAWN := Vector3(0.0, 0.52, 8.6)
const GRID := 0.2                      # hustota sítě vodní hladiny

const C_WALL := Color(0.955, 0.965, 0.955)
const C_FLOOR := Color(0.93, 0.95, 0.94)
const C_CEIL := Color(0.90, 0.915, 0.91)
const C_POOL := Color(0.64, 0.86, 0.93)
const C_BLUE := Color(0.07, 0.20, 0.46)
const C_TUNNEL := Color(0.50, 0.55, 0.53)

var tile_mat: ShaderMaterial
var water_mat: ShaderMaterial
var post_mat: ShaderMaterial
var bodycam: Node            # BODYCAM (experiment): scripts/bodycam.gd
var visor: Node              # VISOR (experiment): scripts/visor.gd – hledí helmy, otření klávesou H
var chrome_mat: StandardMaterial3D
# Paleta místnosti: nahrazuje výchozí barvy dlaždic (každá síň má vlastní charakter).
var _palette := {}
var _tile_mul := 1.0
var dark_mat: StandardMaterial3D
var void_mat: StandardMaterial3D       # tmavé otvory galerií (tma, ne kov)
var _surfaces := {}
var env: Environment
var refl_env: Environment
var cam_attr: CameraAttributesPractical
var sun: DirectionalLight3D
var sim: WaterSim
var sfx: Sfx
var player: Player
var refl_vp: SubViewport
var _refl_frame := 0
var _refl_last_basis := Basis()
var _refl_last_origin := Vector3.ZERO
var refl_cam: Camera3D
var world_body: StaticBody3D

var solids: Array[AABB] = []
var water_rects: Array[Rect2] = []
var skylights: Array[Dictionary] = []      # {rect: Rect2 (x,z), top: float, bottom: float, floor: float}
var dust: Array[GPUParticles3D] = []
var light_shafts: Array[FogVolume] = []
const MenuScript := preload("res://scripts/menu.gd")
const PickupScript := preload("res://scripts/pickup_prop.gd")
const NetScript := preload("res://scripts/network_session.gd")
const RemoteScript := preload("res://scripts/remote_player.gd")
const ZombieScript := preload("res://scripts/zombie.gd")
const ModeScript := preload("res://scripts/zombie_mode.gd")
var flashlight: SpotLight3D
var mode: Node
var zombie: Node3D
var network: Node
var remote_players := {}
var _remote_root: Node3D
var _network_label: Label
var _intro_fade: Tween
var _ammo_label: Label
var _crosshair: Label
var _impact_marks: Array[Node3D] = []
const PICKUP_REACH := 1.35
var pickup_prop: Node3D
var collected_samples := 0
var _pickup_pending := false
var _pickup_serial := 0
var _interaction_label: Label
var menu: MenuScript
var sun_dir := Vector3(0.30, -1.0, 0.40).normalized()
const BASE_EXPOSURE := 1.0
const MENU_VIEW := [Vector3(8.6, -0.35, -4.6), 52.0, -3.0]      # pozadí hlavního menu: pohled na bazén
const SETTINGS_PATH := "user://settings.cfg"
var settings := {
	"window": 0, "vsync": true, "upscale": 0, "sharpen": 0.4, "brightness": 1.0, "fov": 75.0, "show_fps": false, "crosshair_on": false, "hitmarker": true, "hit_sound": true, "water_glow": true,
	"preset": 2, "gi": true, "ssr": true, "planar": 1, "volumetric": true, "dust": true, "shadows": 3, "ao": true,
	"bloom": 0.3, "dof": true, "grain": 0.35, "vignette": 0.5,
	"mouse": 1.0, "bob": 1.0, "gun_sway": 1.0, "aim_sway": 0.1, "shake": 1.0, "vhs": false, "fisheye": false, "volume": 0.8, "music": 0.35, "flash_size": 30.0, "flash_flicker": true, "horror": false, "intro": true, "mini_range": 20.0, "mini_size": 300.0, "mini_pos": 0, "mini_line": 2, "mini_margin": 110.0, "recoil": 1.0, "gun_master": 0.0, "gun_bass": 0.0, "gun_echo": 1.0, "gun_ak_vol": 0.0, "gun_ak_bass": 0.0, "gun_ak_echo": 0.35, "gun_ak_pitch": 1.0, "gun_mp40_vol": 0.0, "gun_mp40_bass": 0.0, "gun_mp40_echo": 0.35, "gun_mp40_pitch": 1.0, "gun_izh54_vol": 0.0, "gun_izh54_bass": 0.0, "gun_izh54_echo": 0.35, "gun_izh54_pitch": 1.0, "gun_deagle_vol": 0.0, "gun_deagle_bass": 0.0, "gun_deagle_echo": 0.35, "gun_deagle_pitch": 1.0,
	"fisheye_strength": 0.35, "bodycam": false, "bodycam_blur": 1.0, "visor": false, "visor_auto": true, "contrast": 1.0, "gamma": 1.0, "camera_motion": 0.65,
	"resolution_scale": 100.0, "fps_limit": 0, "rays_strength": 1.0,
	"perspective": 0, "tp_distance": 2.8, "tp_offset": 0.5, "tp_height": 1.45,
	"tp_side": 0, "tp_fov": 70.0, "tp_smoothing": 0.55,
	"player_name": "Hráč", "server_address": "", "server_port": 24567, "automatic_port": true,
	# vzhled obleku (menu Customize)
	"look_suit": Color(0.352, 0.552, 0.948), "look_rubber": Color(0.209, 0.209, 0.209), "look_visor": Color(0.863, 0.688, 0.19),
	"look_pattern": 0, "look_pattern_color": Color(0.1, 0.12, 0.08), "look_pattern_scale": 1.0, "look_rubber_fx": 0,
}
var lamps: Array[Dictionary] = []
var splashes: Array[GPUParticles3D] = []
var _splash_i := 0

var vhs_on := false
var fisheye_on := false
var _vhs := 0.0
var _fish := 0.0
var _time := 0.0
var _ending := false
var _fade_rect: ColorRect
var _end_label: Label
var _help: Label
var _fps: Label
var _osd: Control
var _osd_time: Label
var _osd_sp: Label
var _toast: Label
var _toast_t := 0.0
var _help_t := 14.0
var _buzz: AudioStreamPlayer3D
var areas: Node3D
var minimap: Control
var notes: Node3D
var pa: Node3D
var quest: Node3D
var inventory: Node
# Místa s jinou hladinou než WATER_Y (vypouštěná Síň anděla, Nádrž): [{rect, level}]
var water_zones: Array = []
var water_meshes: Array = []       # pro každý water_rect uzel jeho skupiny hladiny
var water_groups: PackedInt32Array = []
var _floor_tiles: Array = []       # [Rect2, barva, měřítko dlaždic] podlah ve výšce FLOOR_Y
const FLOOR_Y := -0.35
const WATER_GRID := 0.2            # rozteč vrcholů hladiny (společná světová mřížka)
const WATER_INTO_WALL := 0.2       # o kolik hladina zajede pod zeď (bez škvír u stěn)
var voice: Node
var _briefing_shown := false
var _menu_cam: Camera3D
var _menu_lights: Node3D
var _menu_t := 0.0
var _test := {}

func _ready() -> void:
	process_priority = 100          # až po hráči: zrcadlová kamera pak nemá snímek zpoždění
	_parse_args()
	_make_materials()
	Player.water_at = water_level_at
	ZombieScript.water_at = water_level_at
	world_body = StaticBody3D.new()
	world_body.collision_layer = 1
	add_child(world_body)
	_build_level()
	_build_east_wing()
	_build_cistern()
	_build_toilets()
	_build_west_showers()
	_build_north_wing()
	_build_south_wing()
	# Detaily bazénů: dělicí lana, startovní bloky, žebříky, záchranné kruhy, hloubky, mřížky.
	load("res://scripts/architecture.gd").build(self)
	_scatter_blood.call_deferred()
	# Vázy s kytkami: kousek života v opuštěných prostorách.
	for v in [[Vector3(36.6, 1.45, 16.6), 1.3], [Vector3(24.6, 1.45, 16.4), 1.3], [Vector3(3.0, 0.5, 1.9), 1.0], [Vector3(60.8, -0.35, 39.2), 1.4], [Vector3(14.5, -0.35, -35.0), 1.3]]:
		var vase := Props.vase()
		add_child(vase)
		vase.position = v[0]
		vase.scale = Vector3.ONE * v[1]
		vase.rotation.y = randf() * TAU
		_vases.append(vase)
	# Podlaha v tloušťce zdí u průchodů mezi novými částmi (jinak tam zela černá škvíra).
	for gap in [[12.6, 13.8, -42.0, -40.0], [-13.2, -12.6, -38.8, -36.8],
			[-4.0, -2.0, -46.6, -46.0], [24.0, 26.0, -34.6, -34.0], [-21.2, -19.2, -22.8, -22.2], [32.0, 35.0, -2.0, -1.4],
			[-13.2, -12.6, -52.8, -50.8], [-10.6, -10.0, -52.8, -50.8]]:
		_gap_floor(gap[0], gap[1], gap[2], gap[3])
	_merge_world()
	_settle_vases.call_deferred()
	_build_water()
	_build_lights()
	_build_environment()
	_setup_sim()
	sfx = Sfx.new()
	add_child(sfx)
	_spawn_player()
	_setup_reflection()
	_setup_ui()
	_build_pickup_prop()
	_build_zombie()
	_combat_fx().prewarm.call_deferred(Vector3(2.3, 0.8, -9.5))      # v záběru kamery hlavního menu, ještě za úvodním zatmíváním
	get_tree().create_timer(1.5).timeout.connect(_optimize_details)
	_buzz = sfx.make_loop_3d("buzz", Vector3(-21.6, 2.5, -21.0), -18.0)
	# Každá část mapy má své jméno, mlhu, akcentové světlo a zvukový podkres.
	areas = load("res://scripts/area_identity.gd").new()
	add_child(areas)
	areas.setup(self)
	# Digitální minimapa (drž M nebo Tab).
	var mini_layer := CanvasLayer.new()
	mini_layer.layer = 41          # nad menu (40), kvůli živému náhledu v nastavení
	add_child(mini_layer)
	minimap = load("res://scripts/minimap.gd").new()
	mini_layer.add_child(minimap)
	minimap.setup(self)
	minimap.process_mode = Node.PROCESS_MODE_ALWAYS
	# Vzkazy na zdech: příběh lázní.
	notes = load("res://scripts/notes.gd").new()
	add_child(notes)
	notes.setup(self)
	# Rozhlas lázní: reproduktory pod stropy a občasná hlášení.
	pa = load("res://scripts/pa_system.gd").new()
	add_child(pa)
	pa.setup(self)
	# Hlasy: velitel přes vysílačku a hlavní postava (odpovědi, myšlenky) s titulky.
	voice = load("res://scripts/voice.gd").new()
	add_child(voice)
	voice.setup(self)
	# Každá blikající zářivka bzučí; při výpadku bzukot povolí a při nahození občas jiskří.
	for L in lamps:
		if not L.flicker: continue
		var hum := sfx.make_loop_3d("lamp_hum", (L.light as OmniLight3D).global_position + Vector3(0, 0.3, 0), -15.0)
		hum.unit_size = 1.3
		hum.max_distance = 11.0
		hum.pitch_scale = randf_range(0.94, 1.06)
		hum.play(randf_range(0.0, 6.0))
		L["hum"] = hum
	get_viewport().size_changed.connect(_on_resize)
	_load_settings()
	menu = MenuScript.new(settings)
	add_child(menu)
	menu.changed.connect(_on_setting_changed)
	menu.play_pressed.connect(_on_play)
	menu.resume_pressed.connect(_on_resume)
	menu.quit_pressed.connect(func(): get_tree().quit())
	_setup_network()
	_apply_look()
	mode = ModeScript.new()
	mode.main = self
	add_child(mode)
	# Hlavní linka secretů (materiály, stupně zbraní, hádanky, Nádrž a konec).
	quest = load("res://scripts/quest.gd").new()
	add_child(quest)
	quest.setup(self)
	# Záložka Testování v nastavení.
	var debug_tools: Node = load("res://scripts/debug_tools.gd").new()
	debug_tools.main = self
	add_child(debug_tools)
	debug_tools.build(menu.add_tab("Testování"))
	# Inventář jako v DayZ (Tab) a rychlý panel 1–9.
	inventory = load("res://scripts/inventory.gd").new()
	add_child(inventory)
	inventory.setup(self)
	for k in settings:
		apply_setting(k)
	if _test.has("preset"):
		menu._change("preset", int(_test["preset"]))
	if not _test.has("shots"):
		_open_main_menu()
	if _test.has("shots") or _test.has("menu"):
		_run_test()
	elif _test.has("mp-host"):
		network.host_game(str(_test.get("mp-name", "Host")), int(_test["mp-host"]), false)
	elif _test.has("mp-join"):
		network.join_game(str(_test.get("mp-name", "Host")), str(_test["mp-join"]), int(_test.get("mp-port", "24567")))

# =============================================================== nastavení a menu
func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load(SETTINGS_PATH) != OK:
		return
	for k in settings:
		if cf.has_section_key("s", k):
			settings[k] = type_convert(cf.get_value("s", k), typeof(settings[k]))
	if not cf.has_section_key("s", "resolution_scale"):
		settings["resolution_scale"] = [100.0, 100.0, 77.0, 67.0, 50.0][clampi(int(settings["upscale"]), 0, 4)]

func _save_settings() -> void:
	var cf := ConfigFile.new()
	for k in settings:
		cf.set_value("s", k, settings[k])
	cf.save(SETTINGS_PATH)

## Vzhled obleku ze slovníku nastavení (pořadí jako PlayerBody.valid_look).
func current_look() -> Array:
	return [settings["look_suit"], settings["look_rubber"], settings["look_visor"], int(settings["look_pattern"]),
		settings["look_pattern_color"], clampf(float(settings["look_pattern_scale"]), 0.2, 4.0), int(settings["look_rubber_fx"])]

func _apply_look() -> void:
	var look := current_look()
	if player and player.body: player.body.apply_look(look)
	if network: network.set_local_look(look)

func _on_setting_changed(key: String) -> void:
	if key.begins_with("look_"):
		_apply_look()
		_save_settings()
		return
	apply_setting(key)
	_save_settings()

func apply_setting(key: String) -> void:
	var v: Variant = settings[key]
	var vp := get_viewport()
	match key:
		"window":
			if _test.is_empty():
				get_window().mode = Window.MODE_FULLSCREEN if int(v) == 0 else Window.MODE_WINDOWED
		"vsync":
			DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED if v else DisplayServer.VSYNC_DISABLED)
		"upscale", "resolution_scale":
			var m := clampi(int(settings["upscale"]), 0, 5)
			var custom := m == 5
			var fsr := m > 0 and not custom
			vp.use_taa = false
			vp.scaling_3d_mode = Viewport.SCALING_3D_MODE_FSR2 if fsr else Viewport.SCALING_3D_MODE_BILINEAR
			vp.scaling_3d_scale = clampf(float(settings["resolution_scale"]) / 100.0, 0.5, 2.0) if custom else [1.0, 1.0, 0.77, 0.67, 0.5][m]
			vp.use_taa = not fsr
		"fps_limit":
			Engine.max_fps = clampi(int(v), 0, 360)
		"sharpen":
			post_mat.set_shader_parameter("sharpen", float(v) * 0.6)
			vp.fsr_sharpness = lerpf(2.0, 0.0, float(v))
		"brightness":
			env.tonemap_exposure = BASE_EXPOSURE * float(v)
		"contrast":
			post_mat.set_shader_parameter("contrast", clampf(float(v), 0.6, 1.6))
		"gamma":
			post_mat.set_shader_parameter("gamma", clampf(float(v), 0.6, 1.6))
		"show_fps":
			_fps.visible = v
		"water_glow":
			# Odlesky a prosvítání vody na stěnách (svítí i ve tmě).
			tile_mat.set_shader_parameter("caustic_strength", 1.0 if v else 0.0)
			tile_mat.set_shader_parameter("bounce_strength", 0.09 if v else 0.0)
		"gi":
			env.sdfgi_enabled = v
		"ssr":
			env.ssr_enabled = v
		"planar":
			refl_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if int(v) > 0 else SubViewport.UPDATE_DISABLED
			_on_resize()
		"volumetric":
			env.volumetric_fog_enabled = v
		"rays_strength":
			for shaft in light_shafts:
				(shaft.material as ShaderMaterial).set_shader_parameter("strength", clampf(float(v), 0.0, 2.0))
		"dust":
			for d in dust:
				d.visible = v
		"shadows":
			var q: int = [RenderingServer.SHADOW_QUALITY_HARD, RenderingServer.SHADOW_QUALITY_SOFT_LOW, RenderingServer.SHADOW_QUALITY_SOFT_MEDIUM,
				RenderingServer.SHADOW_QUALITY_SOFT_HIGH, RenderingServer.SHADOW_QUALITY_SOFT_ULTRA][int(v)]
			RenderingServer.directional_soft_shadow_filter_set_quality(q)
			RenderingServer.positional_soft_shadow_filter_set_quality(q)
		"ao":
			env.ssao_enabled = v
			env.ssil_enabled = v
		"bloom":
			env.glow_enabled = float(v) > 0.01
			env.glow_intensity = float(v) * 0.8
		"dof":
			cam_attr.dof_blur_far_enabled = v
			cam_attr.dof_blur_near_enabled = v
		"grain":
			post_mat.set_shader_parameter("grain", float(v) * 0.1)
		"vignette":
			post_mat.set_shader_parameter("vignette", float(v) * 0.6)
		"mouse":
			player.mouse_scale = float(v)
		"bob":
			player.bob_scale = float(v)
		"gun_sway":
			if player.body and player.body.weapon: player.body.weapon.sway_scale = clampf(float(v), 0.0, 2.0)
		"aim_sway":
			player.aim_sway = clampf(float(v), 0.0, 1.0)
		"shake":
			player.shake_scale = float(v)
		"camera_motion":
			player.motion_scale = clampf(float(v), 0.0, 1.5)
		"perspective":
			player.third_person = int(v) == 1
			player._boom_length = player.shoulder_distance
		"tp_distance":
			player.shoulder_distance = clampf(float(v), 1.2, 5.0)
		"tp_offset":
			player.shoulder_offset = clampf(float(v), 0.0, 1.0)
		"tp_height":
			player.shoulder_height = clampf(float(v), 0.9, 1.9)
		"tp_side":
			player.shoulder_side = 1.0 if int(v) == 0 else -1.0
		"tp_fov":
			player.shoulder_fov = clampf(float(v), 55.0, 95.0)
		"tp_smoothing":
			player.shoulder_smoothing = clampf(float(v), 0.0, 1.0)
		"vhs":
			vhs_on = v
		"fisheye":
			fisheye_on = v
		"bodycam":      # BODYCAM (experiment)
			if bodycam: bodycam.set_enabled(bool(v))
		"visor":        # VISOR (experiment)
			if visor: visor.set_enabled(bool(v))
		"visor_auto":   # VISOR (experiment)
			if visor: visor.auto_wipe = bool(v)
		"volume":
			AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(v), 0.0001)))
		"music":
			if sfx: sfx.music_volume = float(v)
		"flash_size":
			if flashlight:
				# Jádro baterky; široký slabý rozptyl kolem má vlastní světlo.
				flashlight.spot_angle = clampf(float(v) * 1.2, 14.0, 85.0)
				if _flash_spill: _flash_spill.spot_angle = clampf(float(v) * 2.1, 30.0, 89.0)
				# Širší kužel = světlo rozložené do větší plochy, proto trochu víc energie, ať není zhasnutý.
				_flash_energy = 9.0 * clampf(pow(float(v) / 30.0, 0.8), 0.6, 2.2)
				flashlight.light_energy = _flash_energy
		_ when key.begins_with("gun_"):
			if sfx: sfx.apply_gun_settings(settings)

func _open_main_menu() -> void:
	player.control_enabled = false
	player.teleport(MENU_VIEW[0], deg_to_rad(MENU_VIEW[1]), deg_to_rad(MENU_VIEW[2]))
	_menu_scene(true)
	_help_t = 0.0
	menu.open(false)

# Pozadí hlavního menu: živý pohled do hlavní haly s bazénem, pomalý filmový pohyb kamery
# a vlastní světla (měsíc ze světlíků, studená zář nad vodou, blikající lampa).
const MENU_CAM_POS := Vector3(7.0, 1.8, -7.0)      # volné místo u kraje bazénu (u vchodu stojí skluzavka)
const MENU_CAM_LOOK := Vector3(-1.5, -0.5, -16.5)

func _menu_scene(on: bool) -> void:
	if _menu_cam == null:
		_menu_cam = Camera3D.new()
		_menu_cam.fov = 58.0
		# Bez interpolace fyziky: jinak kamera první snímky „přijíždí“ z počátku světa skrz zdi.
		_menu_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
		_menu_cam.attributes = player.camera.attributes
		add_child(_menu_cam)
		_menu_lights = Node3D.new()
		add_child(_menu_lights)
		for spec in [[Vector3(0.0, 7.5, -14.0), Color(0.55, 0.7, 1.0), 2.4, 20.0, true], [Vector3(-3.0, 1.2, -14.0), Color(0.35, 0.75, 0.85), 0.9, 10.0, false],
				[Vector3(7.5, 3.0, -9.0), Color(1.0, 0.72, 0.42), 0.8, 9.0, true]]:
			var l := OmniLight3D.new()
			l.position = spec[0]
			l.light_color = spec[1]
			l.light_energy = spec[2]
			l.omni_range = spec[3]
			l.shadow_enabled = spec[4]
			l.light_volumetric_fog_energy = 1.5
			_menu_lights.add_child(l)
	_menu_lights.visible = on
	if on:
		_menu_t = 0.0
		_menu_cam.look_at_from_position(MENU_CAM_POS, MENU_CAM_LOOK)
		_menu_cam.make_current()
	elif player and player.camera:
		player.camera.make_current()

func _menu_camera(dt: float) -> void:
	if _menu_cam == null or not _menu_cam.current: return
	_menu_t += dt
	# Velmi pomalý drift jako steadicam: kousek do strany, mírný náklon, dech.
	var t := _menu_t
	var pos := MENU_CAM_POS + Vector3(sin(t * 0.045) * 0.8, sin(t * 0.07) * 0.1, sin(t * 0.035) * 0.3)
	var look := MENU_CAM_LOOK + Vector3(sin(t * 0.03) * 1.5, sin(t * 0.05) * 0.2, 0.0)
	_menu_cam.look_at_from_position(pos, look)
	_menu_cam.rotate_object_local(Vector3.FORWARD, sin(t * 0.06) * 0.012)
	# Lampa u kamery občas zabliká.
	var lamp: OmniLight3D = _menu_lights.get_child(2)
	lamp.light_energy = 0.8 if fmod(t, 9.0) < 8.6 or randf() < 0.4 else 0.1

func _on_play() -> void:
	if network.active or network.connecting:
		network.leave()
	_clear_remote_players()
	player.input_suspended = false
	get_tree().paused = false
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, 0.5)
	tw.tween_callback(func():
		menu.close()
		_menu_scene(false)
		mode.reset()
		_reset_pickup()
		get_tree().create_timer(1.2).timeout.connect(_optimize_details)
		player.teleport(SPAWN, 0.0, -0.03)
		player.control_enabled = true
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
		_help_t = 12.0
		# Úvodní briefing velitele (jednou za spuštění hry, dá se vypnout v nastavení).
		if bool(settings.get("intro", true)) and not _briefing_shown:
			_briefing_shown = true
			get_tree().paused = true
			var brief: CanvasLayer = load("res://scripts/briefing.gd").new()
			add_child(brief)
			brief.finished.connect(func():
				get_tree().paused = false
				_help_t = 12.0))
	tw.tween_interval(0.3)
	tw.tween_property(_fade_rect, "color:a", 0.0, 1.6)

func _on_resume() -> void:
	get_tree().paused = false
	player.input_suspended = false
	menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED

# =============================================================== materiály
func _tex(n: String) -> Texture2D:
	return load("res://textures/" + n)

func _make_materials() -> void:
	tile_mat = ShaderMaterial.new()
	tile_mat.shader = load("res://shaders/tile.gdshader")
	tile_mat.set_shader_parameter("albedo_tex", _tex("tiles_albedo.png"))
	tile_mat.set_shader_parameter("normal_tex", _tex("tiles_normal.png"))
	tile_mat.set_shader_parameter("orm_tex", _tex("tiles_orm.png"))
	tile_mat.set_shader_parameter("caustic_tex", _tex("caustics.png"))
	tile_mat.set_shader_parameter("macro_tex", _tex("macro_noise.png"))
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/water.gdshader")
	chrome_mat = StandardMaterial3D.new()
	chrome_mat.albedo_color = Color(0.92, 0.93, 0.95)
	chrome_mat.metallic = 1.0
	chrome_mat.roughness = 0.14
	chrome_mat.metallic = 0.75
	chrome_mat.roughness = 0.22
	chrome_mat.normal_enabled = true
	chrome_mat.normal_texture = _noise_tex(0.06, true, 0.6)
	chrome_mat.uv1_triplanar = true
	# Dříve černý kov: natřená průmyslová ocel s oprýskanou barvou a rzí.
	dark_mat = null        # dřív natřený kov; teď obyčejné kachle jako zbytek zdí
	void_mat = StandardMaterial3D.new()
	void_mat.albedo_color = Color(0.02, 0.02, 0.025)
	void_mat.roughness = 1.0

func _emissive(color: Color, energy: float) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.9, 0.9, 0.9)
	m.emission_enabled = true
	m.emission = color
	m.emission_energy_multiplier = energy
	return m

# =============================================================== baterka
var _flash_energy := 9.0
var _flash_spill: SpotLight3D
var _flash_dust: GPUParticles3D
var _lamp_scan := 0.0
var _flick_wait := 25.0
var _flick_seq: Array = []      # [čas, síla] – krátká sekvence problikávání

func _flashlight_flicker(dt: float) -> void:
	# Baterka sem tam zakolísá: krátké záškuby a výpadky, jako když se uvolní kontakt baterie.
	if flashlight == null or not flashlight.visible or not bool(settings.get("flash_flicker", true)):
		if flashlight: flashlight.light_energy = _flash_energy
		_flick_seq.clear()
		return
	if _flick_seq.is_empty():
		_flick_wait -= dt
		if _flick_wait <= 0.0:
			_flick_wait = randf_range(18.0, 55.0)
			var t := 0.0
			for i in randi_range(2, 7):
				t += randf_range(0.03, 0.12)
				_flick_seq.append([t, randf_range(0.0, 0.35) if randf() < 0.7 else randf_range(0.5, 0.8)])
				t += randf_range(0.03, 0.14)
				_flick_seq.append([t, 1.0])
			if randf() < 0.25:      # občas delší výpadek, pak se chytne
				t += 0.05
				_flick_seq.append([t, 0.0])
				t += randf_range(0.4, 0.9)
				_flick_seq.append([t, 1.0])
			_flick_seq.push_front([0.0, 1.0])
			_flick_seq.push_front(0.0)     # běžící čas sekvence
		flashlight.light_energy = _flash_energy
		return
	_flick_seq[0] += dt
	var now: float = _flick_seq[0]
	var level := 1.0
	for i in range(1, _flick_seq.size()):
		if now >= _flick_seq[i][0]:
			level = _flick_seq[i][1]
	flashlight.light_energy = _flash_energy * level
	if now > (_flick_seq[_flick_seq.size() - 1][0] as float) + 0.05:
		_flick_seq.clear()
		flashlight.light_energy = _flash_energy

# =============================================================== atmosféra
# Náhodné události, které dělají z prázdného bazénu živé (a nepříjemné) místo:
# bouřka s blesky ve světlících, sténání kovové konstrukce, hrací skříňka v opuštěném bufetu,
# vzdálený pláč a ozvěny dávno zaniklého davu u bazénu.
const MUSIC_BOX_POS := Vector3(-3.0, 1.0, -53.0)
var _atmo := {"thunder": 25.0, "creak": 14.0, "crowd": 90.0, "voice": 150.0, "box": 8.0, "chain": 10.0, "drip": 3.0, "plop": 12.0, "groan": 9.0, "breath": 60.0, "scare": 200.0}
var _atmo_gap := 0.0
var _flash := []          # časy záblesků blesku

func _distant_zombies(around: Callable) -> void:
	# Zombie, které nejsou vidět ani nejsou blízko: jen zvuk odněkud z budovy.
	# Mění se, co je slyšet – sténání, chrčení, bouchání do dveří, škrábání, šplouchání kroků, výkřik.
	var roll := randf()
	if voice: voice.heard_distant()
	if roll < 0.38:
		sfx.play_at("zombie_groan", around.call(14.0, 30.0, 1.6), -3.0, randf_range(0.72, 0.98))
	elif roll < 0.52:
		sfx.play_at("zombie_gurgle", around.call(10.0, 22.0, 1.2), -6.0, randf_range(0.75, 0.95))
	elif roll < 0.66:
		# Několik úderů za sebou, jako by něco bušilo do dveří.
		var at: Vector3 = around.call(12.0, 26.0, 1.2)
		for i in randi_range(2, 4):
			get_tree().create_timer(i * randf_range(0.45, 0.8)).timeout.connect(func(): sfx.play_at("zombie_bang", at, -8.0, randf_range(0.8, 0.95)))
	elif roll < 0.76:
		sfx.play_at("wall_scratch", around.call(8.0, 16.0, 1.0), -7.0, randf_range(0.8, 1.0))
	elif roll < 0.9:
		# Šouravé kroky ve vodě, které se vzdalují.
		var start: Vector3 = around.call(12.0, 22.0, 0.0)
		var dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		for i in randi_range(4, 7):
			var at2 := start + dir * i * 0.7
			get_tree().create_timer(i * randf_range(0.7, 0.95)).timeout.connect(func(): sfx.play_at("step_water", at2, -12.0 - i, randf_range(0.7, 0.85)))
	else:
		sfx.play_at("zombie_attack", around.call(20.0, 34.0, 1.6), -9.0, randf_range(0.7, 0.85))

func _atmosphere(dt: float) -> void:
	if not player.control_enabled or (menu and menu.is_open):
		return
	var p := player.global_position
	# Během hlášení rozhlasu ostatní atmosféra mlčí, ať je hlas slyšet.
	if pa and Time.get_ticks_msec() / 1000.0 < float(pa.playing_until): return
	_atmo_gap=maxf(0.0,_atmo_gap-dt)
	for k in _atmo:
		# V boji nevrstvit falešné hrozby na skutečné kroky a útoky.
		if k in ["voice","crowd","chain","breath","scare","groan"]:
			if sfx.tension>0.65 or _atmo_gap>0.0: continue
		_atmo[k] -= dt
		if _atmo[k]<=0.0 and k in ["voice","crowd","chain","breath","scare","groan"]:
			_atmo_gap=randf_range(2.5,5.0)
	# bouřka: záblesk ve světlících, hrom o chvíli později
	if _atmo.thunder <= 0.0:
		_atmo.thunder = randf_range(55.0, 140.0)
		var delay := randf_range(0.6, 3.0)
		_flash = [0.0, 0.09, 0.22, 0.3]
		get_tree().create_timer(delay).timeout.connect(func(): sfx.play("thunder", -9.0 + randf_range(-3.0, 1.0), randf_range(0.9, 1.05)))
	if not _flash.is_empty():
		_flash[0] += dt
		var t: float = _flash[0]
		var on: bool = (t > 0.0 and t < _flash[1]) or (t > _flash[2] and t < _flash[3])
		sun.light_energy = 1.4 if on else 0.035
		if t > 0.5:
			_flash = []
			sun.light_energy = 0.035
	# sténání konstrukce někde v okolí
	if _atmo.creak <= 0.0:
		_atmo.creak = randf_range(8.0, 22.0)
		var dir := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		sfx.play_at("creak", p + dir * randf_range(9.0, 20.0) + Vector3.UP * 3.0, -7.0, randf_range(0.82, 1.1))
	# ozvěny davu: jen ve velkých bazénových síních
	if _atmo.crowd <= 0.0:
		_atmo.crowd = randf_range(55.0, 120.0)
		var in_hall := (absf(p.x) < 12.6 and p.z < -1.2 and p.z > -26.6) or (p.x > 20.0 and p.x < 47.2 and p.z < -1.4 and p.z > -34.6)
		if in_hall:
			sfx.play("ghost_crowd", -17.0, randf_range(0.92, 1.0))
	# vzdálený pláč / smích – vzácně a daleko
	if _atmo.voice <= 0.0:
		_atmo.voice = randf_range(80.0, 170.0)
		var dir2 := Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU)
		sfx.play_at("cry" if randf() < 0.7 else "laugh", p + dir2 * randf_range(18.0, 28.0) + Vector3.UP, -6.0, randf_range(0.88, 1.0))
	var around := func(lo: float, hi: float, h: float) -> Vector3:
		return p + Vector3.FORWARD.rotated(Vector3.UP, randf() * TAU) * randf_range(lo, hi) + Vector3.UP * h
	# řetězy a kovové chrastění někde ve tmě
	if _atmo.chain <= 0.0:
		_atmo.chain = randf_range(8.0, 20.0)
		sfx.play_at("chain", around.call(8.0, 20.0, 2.5), -6.0, randf_range(0.85, 1.1))
	# kapající voda kolem hráče
	if _atmo.drip <= 0.0:
		_atmo.drip = randf_range(1.5, 5.0)
		sfx.play_at("drip", around.call(2.0, 7.0, 2.2), -14.0, randf_range(0.8, 1.2))
	# žbluňknutí a bublání v bazénu (ve velkých síních)
	var in_pool_hall := (absf(p.x) < 12.6 and p.z < -1.2 and p.z > -26.6) or (p.x > 20.0 and p.x < 47.2 and p.z < -1.4 and p.z > -34.6)
	if _atmo.plop <= 0.0:
		_atmo.plop = randf_range(4.0, 11.0)
		if in_pool_hall:
			var spot: Vector3 = around.call(5.0, 14.0, 0.0)
			spot.y = WATER_Y
			sfx.play_at("water_plop", spot, -8.0, randf_range(0.8, 1.15))
	# vzdálení zombie: sténání a vrčení odněkud z dálky, i když zrovna žádný není vidět
	if _atmo.groan <= 0.0:
		_atmo.groan = randf_range(3.5, 9.0)
		_distant_zombies(around)
	# těžký dech za zdí
	if _atmo.breath <= 0.0:
		_atmo.breath = randf_range(35.0, 80.0)
		sfx.play_at("breather", around.call(6.0, 12.0, 1.4), -10.0, randf_range(0.85, 1.0))
	# vzácný děsivý zvuk
	if _atmo.scare <= 0.0:
		_atmo.scare = randf_range(120.0, 240.0)
		sfx.play("scare", -14.0, randf_range(0.9, 1.0))
	# hrací skříňka v bufetu
	if _atmo.box <= 0.0:
		_atmo.box = randf_range(22.0, 48.0)
		if p.distance_to(MUSIC_BOX_POS) < 30.0:
			if randf() < 0.35:
				sfx.play_at("music_box_wind", MUSIC_BOX_POS, -9.0)
				get_tree().create_timer(1.7).timeout.connect(func(): sfx.play_at("music_box", MUSIC_BOX_POS, -7.0, randf_range(0.94, 1.0)))
			else:
				sfx.play_at("music_box", MUSIC_BOX_POS, -7.0, randf_range(0.94, 1.0))

# =============================================================== optimalizace detailů
var _shadow_lights: Array[Light3D] = []
var _shadow_t := 0.0
const SHADOW_BUDGET := 6          # kolik nejbližších lamp smí najednou vrhat stín
const DETAIL_LAYER := 1 << 17      # drobnosti: nekreslí se do odrazu vody

func _water_clip_sweep() -> void:
	# Vše, co sahá pod hladinu (žebříky, skluzavky, socha, hračky, věci na dně), dostane materiál,
	# který se v odrazu vody pod hladinou nekreslí – jinak by podvodní části v odrazu
	# vystupovaly jako světlé desky a zdvojené obrysy.
	var wc := preload("res://scripts/water_clip.gd")
	wc.water_level = WATER_Y
	var n := 0
	for g in find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = g
		if not (gi is MeshInstance3D) or gi.layers & 2 or not gi.is_visible_in_tree():
			continue
		if wc.crosses(gi, WATER_Y):
			wc.apply(gi)
			n += 1
	print("water clip: %d objektů" % n)

func _optimize_details() -> void:
	_water_clip_sweep()
	# Drobné předměty (náboje, peníze, lahvičky, suť...) nevrhají stín a nekreslí se do odrazu hladiny –
	# v rozvlněném odrazu ani ve stínu by nebyly poznat, ale každý stál draw call v každém průchodu.
	var small := 0
	for g in find_children("*", "GeometryInstance3D", true, false):
		var gi: GeometryInstance3D = g
		if gi.layers != 1 or _is_actor(gi):
			continue
		var bb := gi.get_aabb()
		var sc := gi.global_transform.basis.get_scale()
		var longest := maxf(bb.size.x * sc.x, maxf(bb.size.y * sc.y, bb.size.z * sc.z))
		if longest < 0.35:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			gi.layers = DETAIL_LAYER
			small += 1
	# Stínové lampy pro rozpočet stínů.
	_shadow_lights.clear()
	for l in find_children("*", "Light3D", true, false):
		if l is DirectionalLight3D or l == flashlight or not (l as Light3D).shadow_enabled:
			continue
		_shadow_lights.append(l)
	print("optimize: %d drobností, %d stínových lamp" % [small, _shadow_lights.size()])

func _is_actor(n: Node) -> bool:
	var p := n.get_parent()
	for i in 8:
		if p == null or p == self:
			return false
		if p is Skeleton3D or p is CharacterBody3D or p is RigidBody3D or p == player:
			return true
		p = p.get_parent()
	return false

func _update_shadow_budget(dt: float) -> void:
	# Stín počítá jen pár lamp nejblíž hráči (každá stínová lampa = celá scéna kolem ní znovu, 6× pro kostku).
	_shadow_t -= dt
	if _shadow_t > 0.0 or _shadow_lights.is_empty():
		return
	_shadow_t = 0.25
	var o := player.camera.global_position
	var fwd := -player.camera.global_transform.basis.z
	var scored := []
	for l in _shadow_lights:
		if not is_instance_valid(l) or not l.is_visible_in_tree():
			continue
		var d := l.global_position - o
		var dist := d.length()
		var rng := (l as OmniLight3D).omni_range if l is OmniLight3D else (l as SpotLight3D).spot_range
		# Lampy za zády se počítají jako dál – jejich stín je vidět méně.
		var behind := 0.0 if dist < rng or d.dot(fwd) > 0.0 else 6.0
		scored.append([dist - rng * 0.5 + behind, l])
	scored.sort_custom(func(a, b): return a[0] < b[0])
	for i in scored.size():
		var l: Light3D = scored[i][1]
		var on: bool = i < SHADOW_BUDGET and scored[i][0] < 18.0
		if l.shadow_enabled != on:
			l.shadow_enabled = on

# =============================================================== stavebnice
func _merge_world() -> void:
	# Stovky samostatných kvádrů zdí, podlah a lišt se slijí do pár desítek meshů:
	# stejný materiál + odstín + měřítko dlaždic, rozdělené do buněk 12 m, aby fungovalo ořezávání
	# mimo záběr a za zdmi. Dlaždice se mapují ve světových souřadnicích, takže vzhled zůstane stejný.
	const CELL := 12.0
	var groups := {}
	for c in get_children():
		if not (c is MeshInstance3D):
			continue
		var mi: MeshInstance3D = c
		if not (mi.mesh is PrimitiveMesh) or mi.get_child_count() > 0 or mi.material_override == null or not mi.visible:
			continue
		if mi.get_meta_list().size() > 0 or mi.layers != 1:
			continue
		var cell := (mi.position / CELL).floor()
		var key := [mi.material_override, mi.get_instance_shader_parameter("tint"), mi.get_instance_shader_parameter("tile_scale"),
			mi.cast_shadow, mi.visibility_range_end, cell]
		var id := str(key)
		if not groups.has(id):
			groups[id] = {"key": key, "items": []}
		groups[id].items.append(mi)
	var before := 0
	var after := 0
	for id in groups:
		var items: Array = groups[id].items
		before += items.size()
		after += 1
		if items.size() < 2:
			continue
		var st := SurfaceTool.new()
		for mi in items:
			st.append_from((mi as MeshInstance3D).mesh, 0, (mi as MeshInstance3D).transform)
		var merged := MeshInstance3D.new()
		merged.mesh = st.commit()
		var key: Array = groups[id].key
		merged.material_override = key[0]
		merged.cast_shadow = key[3]
		merged.visibility_range_end = key[4]
		add_child(merged)
		if key[1] != null: merged.set_instance_shader_parameter("tint", key[1])
		if key[2] != null: merged.set_instance_shader_parameter("tile_scale", key[2])
		for mi in items:
			remove_child(mi)
			(mi as Node).queue_free()
	print("merge_world: %d -> %d meshů" % [before, after])

func box(x0: float, x1: float, y0: float, y1: float, z0: float, z1: float, tint := C_WALL, solid := true, scale := 1.0, mat: Material = null) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(x1 - x0, y1 - y0, z1 - z0)
	mi.mesh = bm
	mi.position = Vector3((x0 + x1) * 0.5, (y0 + y1) * 0.5, (z0 + z1) * 0.5)
	if mat:
		mi.material_override = mat
	else:
		mi.material_override = tile_mat
		mi.set_instance_shader_parameter("tint", _palette.get(tint, tint))
		mi.set_instance_shader_parameter("tile_scale", scale * _tile_mul)
		if absf(y1 - FLOOR_Y) < 0.01:
			_floor_tiles.append([Rect2(x0, z0, x1 - x0, z1 - z0), _palette.get(tint, tint), scale * _tile_mul])
	add_child(mi)
	if solid:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = bm.size
		cs.shape = bs
		cs.position = mi.position
		world_body.add_child(cs)
		solids.append(AABB(Vector3(x0, y0, z0), bm.size))
		# Velké zdi a podlahy zakrývají, co je za nimi: GPU pak nekreslí okolní místnosti.
		var dims := [bm.size.x, bm.size.y, bm.size.z]
		dims.sort()
		if dims[1] >= 2.0 and dims[0] >= 0.3:
			var occ := OccluderInstance3D.new()
			var bo := BoxOccluder3D.new()
			bo.size = bm.size
			occ.occluder = bo
			occ.position = mi.position
			add_child(occ)
	return mi

func slab_with_holes(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, holes: Array[Rect2], tint: Color, scale: float) -> void:
	var xs: Array[float] = [x0, x1]
	for h in holes:
		xs.append(h.position.x)
		xs.append(h.end.x)
	xs.sort()
	for i in xs.size() - 1:
		var a := xs[i]
		var b := xs[i + 1]
		if b - a < 0.001:
			continue
		var mid := (a + b) * 0.5
		var hs: Array[Rect2] = []
		for h in holes:
			if mid > h.position.x and mid < h.end.x:
				hs.append(h)
		hs.sort_custom(func(p: Rect2, q: Rect2) -> bool: return p.position.y < q.position.y)
		var z := z0
		for h in hs:
			if h.position.y > z:
				box(a, b, y0, y1, z, h.position.y, tint, true, scale)
			z = h.end.y
		if z < z1:
			box(a, b, y0, y1, z, z1, tint, true, scale)

func tube(points: Array[Vector3], radius: float, mat: Material, seg := 10, sub := 8) -> void:
	var pts: Array[Vector3] = []
	for i in points.size() - 1:
		var p0 := points[maxi(i - 1, 0)]
		var p1 := points[i]
		var p2 := points[i + 1]
		var p3 := points[mini(i + 2, points.size() - 1)]
		for s in sub:
			pts.append(p1.cubic_interpolate(p2, p0, p3, float(s) / sub))
	pts.append(points[-1])
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for i in pts.size():
		var t := (pts[mini(i + 1, pts.size() - 1)] - pts[maxi(i - 1, 0)]).normalized()
		var n1 := Vector3.RIGHT
		if absf(t.dot(n1)) > 0.9:
			n1 = Vector3.UP
		n1 = (n1 - t * t.dot(n1)).normalized()
		var n2 := t.cross(n1)
		for j in seg:
			var a := TAU * j / seg
			var n := n1 * cos(a) + n2 * sin(a)
			st.set_normal(n)
			st.add_vertex(pts[i] + n * radius)
	for i in pts.size() - 1:
		for j in seg:
			var a := i * seg + j
			var b := i * seg + (j + 1) % seg
			var c := a + seg
			var d := b + seg
			st.add_index(a); st.add_index(c); st.add_index(b)
			st.add_index(b); st.add_index(c); st.add_index(d)
	var mi := MeshInstance3D.new()
	mi.mesh = st.commit()
	mi.material_override = mat
	add_child(mi)

func water_level_at(p: Vector3) -> float:
	for z in water_zones:
		if (z.rect as Rect2).has_point(Vector2(p.x, p.z)): return float(z.level)
	# Hluboko pod lázněmi (tunel do Nádrže) žádná voda není.
	return WATER_Y if p.y > -5.0 else -1000.0

func add_water_zone(rect: Rect2, level: float) -> Dictionary:
	var zone := {"rect": rect, "level": level}
	water_zones.append(zone)
	return zone

func water_mesh_for(xz: Vector2) -> Node3D:
	for i in water_rects.size():
		if water_rects[i].has_point(xz) and i < water_meshes.size(): return water_meshes[i]
	return null

## Vodní obdélník. Skupina > 0 = samostatná hladina, kterou jde posouvat (vypouštění bazénu).
func water(x0: float, x1: float, z0: float, z1: float, group := 0) -> void:
	water_rects.append(Rect2(x0, z0, x1 - x0, z1 - z0))
	water_groups.append(group)

func _floor_at(xz: Vector2) -> Array:
	for i in range(_floor_tiles.size() - 1, -1, -1):
		if (_floor_tiles[i][0] as Rect2).has_point(xz): return _floor_tiles[i]
	return []

func _is_wet(xz: Vector2) -> bool:
	for r in water_rects:
		if r.has_point(xz): return true
	return false

## Podlaha v tloušťce zdi u průchodu: každá polovina má barvu a dlaždice místnosti, ke které patří,
## a když jsou mokré obě strany, vede pod průchodem i voda (jinak suchý světlý pruh mezi místnostmi).
func _gap_floor(x0: float, x1: float, z0: float, z1: float) -> void:
	var along_x := (x1 - x0) < (z1 - z0)          # tenká osa = směr průchodu
	var mid := (x0 + x1) * 0.5 if along_x else (z0 + z1) * 0.5
	var c := Vector2((x0 + x1) * 0.5, (z0 + z1) * 0.5)
	var probe_a := Vector2(x0 - 0.15, c.y) if along_x else Vector2(c.x, z0 - 0.15)
	var probe_b := Vector2(x1 + 0.15, c.y) if along_x else Vector2(c.x, z1 + 0.15)
	var fa := _floor_at(probe_a)
	var fb := _floor_at(probe_b)
	if fa.is_empty(): fa = fb
	if fb.is_empty(): fb = fa
	var halves := [[x0, mid, z0, z1], [mid, x1, z0, z1]] if along_x else [[x0, x1, z0, mid], [x0, x1, mid, z1]]
	for k in 2:
		var h: Array = halves[k]
		var f: Array = fa if k == 0 else fb
		if f.is_empty():
			box(h[0], h[1], -1.0, FLOOR_Y, h[2], h[3], C_FLOOR)
		else:
			_floor_tiles.append([Rect2(h[0], h[2], h[1] - h[0], h[3] - h[2]), f[1], f[2]])
			var mi := box(h[0], h[1], -1.0, FLOOR_Y, h[2], h[3], f[1])
			mi.set_instance_shader_parameter("tile_scale", f[2])
	if _is_wet(probe_a) and _is_wet(probe_b) and not _is_wet(c):
		water(x0, x1, z0, z1)

# =============================================================== úroveň
func _build_level() -> void:
	# --- vstupní místnost (suchá, vyvýšená)
	box(-2, 2, -1.0, 0.5, 0, 10.6, C_FLOOR)
	box(-2, 2, -0.35, 0.2875, -0.6, 0, C_FLOOR, false)
	box(-2, 2, -0.35, 0.075, -1.2, -0.6, C_FLOOR, false)
	box(-2, 2, -0.35, -0.1375, -1.8, -1.2, C_FLOOR, false)
	solids.append(AABB(Vector3(-2, -0.35, -1.2), Vector3(4, 0.7, 1.2)))      # schody nad hladinou (pro masku vln)
	_ramp()
	box(-2.6, -2, -1.0, 3.6, -1.2, 3.6)                              # západní stěna s dveřmi do dámských šaten
	box(-2.6, -2, -1.0, 3.6, 5.2, 10.6)
	box(-2.6, -2, 2.6, 3.6, 3.6, 5.2)
	box(2, 2.6, -1.0, 3.6, -1.2, 4)
	box(2, 2.6, -1.0, 3.6, 6, 10.6)
	box(2, 2.6, 2.4, 3.6, 4, 6)                               # dveře do šaten
	box(-2.6, 2.6, -1.0, 3.6, 10, 10.6)
	var start_holes: Array[Rect2] = [Rect2(-0.9, 5.4, 1.8, 1.5), Rect2(-0.9, 1.4, 1.8, 1.5)]
	slab_with_holes(-2.6, 2.6, -1.2, 10.6, 3.0, 3.6, start_holes, C_CEIL, 0.5)
	for h in start_holes:
		skylights.append({"rect": h, "top": 3.6, "bottom": 3.0, "floor": 0.5})
	# zábradlí u schodů
	for sx in [-1.9, 1.9]:
		tube([Vector3(sx, 0.5, 1.0), Vector3(sx, 1.42, 0.98), Vector3(sx, 1.45, 0.7), Vector3(sx, 0.62, -1.75), Vector3(sx, 0.55, -2.0), Vector3(sx, -0.35, -2.02)], 0.022, chrome_mat)

	# --- hala: dno mělké části a bazén
	box(-12.6, 12.6, -3.2, -0.35, -8, -1.8, C_FLOOR)
	box(-12.6, 12.6, -3.2, -0.35, -26.6, -20, C_FLOOR)
	box(-12.6, -6, -3.2, -0.35, -20, -8, C_FLOOR)
	box(6, 12.6, -3.2, -0.35, -20, -8, C_FLOOR)
	box(-6, 6, -3.2, -2.6, -20, -8, C_POOL, true, 2.0)
	box(-6, -5.985, -2.6, -0.36, -20, -8, C_POOL, false, 2.0)
	box(5.985, 6, -2.6, -0.36, -20, -8, C_POOL, false, 2.0)
	box(-6, 6, -2.6, -0.36, -8.015, -8, C_POOL, false, 2.0)
	box(-6, 6, -2.6, -0.36, -20, -19.985, C_POOL, false, 2.0)
	for lx in [-3.2, 0.0, 3.2]:
		box(lx - 0.1, lx + 0.1, -2.6, -2.592, -19, -9, C_BLUE, false, 2.0)         # plavecké dráhy
	box(-6.2, 6.2, -0.36, -0.342, -8.01, -7.8, C_BLUE, false)                         # lem bazénu
	box(-6.2, 6.2, -0.36, -0.342, -20.2, -19.99, C_BLUE, false)
	box(-6.2, -5.99, -0.36, -0.342, -20, -8, C_BLUE, false)
	box(5.99, 6.2, -0.36, -0.342, -20, -8, C_BLUE, false)

	# --- hala: stěny
	box(12, 12.6, -0.35, 9.6, -26.6, -15)
	box(12, 12.6, -0.35, 9.6, -13, -1.2)
	box(12, 12.6, 2.6, 9.6, -15, -13)                        # průchod do východního křídla (brána)
	box(-12.6, -12, -0.35, 9.6, -26.6, -22.2)
	box(-12.6, -12, -0.35, 9.6, -19.8, -16)
	box(-12.6, -12, -0.35, 9.6, -14, -1.2)
	box(-12.6, -12, 2.6, 9.6, -16, -14)                      # průchod do technické místnosti
	box(-12.6, -12, 2.6, 9.6, -22.2, -19.8)
	box(-12.6, -1.2, -0.35, 9.6, -26.6, -26)
	box(1.2, 12.6, -0.35, 9.6, -26.6, -26)
	box(-1.2, 1.2, 2.6, 9.6, -26.6, -26)                     # průchod do lesa sloupů (brána)
	box(-12, -2, -0.35, 9.6, -1.8, -1.2)
	box(2, 7, -0.35, 9.6, -1.8, -1.2)
	box(9, 12, -0.35, 9.6, -1.8, -1.2)
	box(7, 9, 2.6, 9.6, -1.8, -1.2)                          # průchod do šaten
	box(7, 9, -1.0, -0.35, -1.8, -1.2, C_FLOOR)
	box(-2, 2, 3.0, 9.6, -1.8, -1.2)
	# pruh tmavě modrých dlaždic ve výšce očí
	box(11.99, 12, 1.2, 1.4, -26, -15, C_BLUE, false)
	box(11.99, 12, 1.2, 1.4, -13, -1.8, C_BLUE, false)
	box(-12, -11.99, 1.2, 1.4, -26, -22.2, C_BLUE, false)
	box(-12, -11.99, 1.2, 1.4, -19.8, -16, C_BLUE, false)
	box(-12, -11.99, 1.2, 1.4, -14, -1.8, C_BLUE, false)
	box(-12, -1.2, 1.2, 1.4, -26, -25.99, C_BLUE, false)
	box(1.2, 12, 1.2, 1.4, -26, -25.99, C_BLUE, false)
	box(-12, -2, 1.2, 1.4, -1.81, -1.8, C_BLUE, false)
	box(2, 7, 1.2, 1.4, -1.81, -1.8, C_BLUE, false)
	box(9, 12, 1.2, 1.4, -1.81, -1.8, C_BLUE, false)
	# sloupy
	for cx in [-9.0, 9.0]:
		for cz in [-5.0, -11.0, -17.0, -23.0]:
			box(cx - 0.4, cx + 0.4, -0.35, 9.0, cz - 0.4, cz + 0.4)

	# --- strop se světlíky
	var hall_holes: Array[Rect2] = []
	for zc in [-10.5, -14.0, -17.5]:
		hall_holes.append(Rect2(-2, zc - 1.2, 4, 2.4))
	for zc in [-8.0, -14.0, -20.0]:
		hall_holes.append(Rect2(-10.6, zc - 1.0, 3.2, 2.0))
		hall_holes.append(Rect2(7.4, zc - 1.0, 3.2, 2.0))
	slab_with_holes(-12.6, 12.6, -26.6, -1.2, 5.5, 9.6, hall_holes, C_CEIL, 0.5)
	for h in hall_holes:
		skylights.append({"rect": h, "top": 9.6, "bottom": 5.5, "floor": -0.35})

	# --- galerie pod stropem: hráč se na ně nedostane, zombie z nich vycházejí ze tmy a padají dolů
	box(10.4, 12, 4.0, 4.2, -24.6, -4, C_FLOOR)
	box(-10, 10.4, 4.0, 4.2, -26, -24.6, C_FLOOR)
	for gz in [-8.0, -14.0, -20.0]:
		box(11.97, 12, 4.2, 6.4, gz - 0.65, gz + 0.65, C_WALL, false, 1.0, void_mat)
	for gx in [-5.0, 0.0, 5.0]:
		box(gx - 0.65, gx + 0.65, 4.2, 6.4, -26, -25.97, C_WALL, false, 1.0, void_mat)

	# --- šatny (suché, východně od vstupní místnosti) a rampa dolů do haly: okruh vstup -> šatny -> hala
	box(2, 2.6, -1.0, 0.5, 4, 6, C_FLOOR)
	box(2.6, 11.4, -1.0, 0.5, 1.4, 9, C_FLOOR)
	box(2.6, 12, 0.5, 3.6, 9, 9.6)
	box(11.4, 12, 0.5, 3.6, 0.8, 6.2)                                # východní stěna s dveřmi na toalety
	box(11.4, 12, 0.5, 3.6, 7.4, 9)
	box(11.4, 12, 2.6, 3.6, 6.2, 7.4)
	box(2.6, 7, -0.35, 3.6, 0.8, 1.4)
	box(9, 12, -0.35, 3.6, 0.8, 1.4)
	box(7, 9, 2.6, 3.6, 0.8, 1.4)
	box(6.4, 7, -0.35, 3.6, -1.2, 0.8)
	box(9, 9.6, -0.35, 3.6, -1.2, 0.8)
	box(7, 9, -1.0, -0.35, -1.2, 1.4, C_FLOOR)
	box(2.6, 12, 3.0, 3.6, -1.2, 9, C_CEIL)
	for step in 4:
		box(7, 9, -0.35, 0.5 - 0.2125 * (step + 1), 1.4 - 0.65 * (step + 1), 1.4 - 0.65 * step, C_FLOOR, false)
	var slope := CollisionShape3D.new()
	var wedge := ConvexPolygonShape3D.new()
	wedge.points = PackedVector3Array([Vector3(7, 0.5, 1.45), Vector3(9, 0.5, 1.45), Vector3(7, -0.36, 1.45), Vector3(9, -0.36, 1.45), Vector3(7, -0.36, -1.2), Vector3(9, -0.36, -1.2)])
	slope.shape = wedge
	world_body.add_child(slope)
	# skříňky: modely ze zombie_mode (PLACES "deco")
	_bench(Vector3(5.4, 0.5, 5.2), 2.4, 0.0)                                                 # lavice

	# --- zatopená technická místnost (západ): okruh chodba -> technická -> hala
	box(-22, -12.6, -1.0, -0.35, -19.8, -11, C_FLOOR)
	box(-22.6, -12.6, -0.35, 3.4, -11, -10.4, C_TUNNEL)
	box(-22.6, -22, -0.35, 3.4, -19.2, -11, C_TUNNEL)
	box(-22.6, -12.6, 2.8, 3.4, -19.2, -11, C_TUNNEL)
	box(-21.6, -20.2, -0.35, 1.9, -12.6, -11.3, C_WALL, true, 1.0, dark_mat)               # nádrž
	box(-16.2, -15.4, -0.35, 2.8, -11.9, -11.1, C_WALL, true, 1.0, dark_mat)               # potrubí
	box(-21.9, -21.5, 1.6, 1.9, -18.5, -13.2, C_WALL, false, 1.0, dark_mat)
	_spot(Vector3(-21.7, -0.35, -18.6), "TAJNÝ PRŮCHOD", Color(1.0, 0.2, 0.15))
	# --- chodba k východu (západ)
	box(-24.6, -12.6, -1.0, -0.35, -22.2, -19.8, C_FLOOR)
	box(-24.6, -21.2, -0.35, 3.2, -22.8, -22.2)
	box(-19.2, -12.6, -0.35, 3.2, -22.8, -22.2)
	box(-21.2, -19.2, 2.6, 3.2, -22.8, -22.2)                 # průchod do bludiště (brána)
	box(-24.6, -19, -0.35, 3.2, -19.8, -19.2)
	box(-17, -12.6, -0.35, 3.2, -19.8, -19.2)
	box(-19, -17, 2.4, 3.2, -19.8, -19.2)                     # dveře do technické místnosti
	var corr_holes: Array[Rect2] = [Rect2(-17.6, -21.7, 1.9, 1.4)]
	slab_with_holes(-24.6, -12.6, -22.2, -19.8, 2.6, 3.2, corr_holes, C_CEIL, 0.5)
	for h in corr_holes:
		skylights.append({"rect": h, "top": 3.2, "bottom": 2.6, "floor": -0.35})
	box(-24.6, -24, -0.35, 2.6, -22.2, -21.6)
	box(-24.6, -24, -0.35, 2.6, -20.4, -19.8)
	box(-24.6, -24, 0.55, 2.6, -21.6, -20.4)
	# rám větracího otvoru
	box(-24.0, -23.97, -0.35, 0.61, -21.66, -21.6, C_WALL, false, 1.0, _surface("steel"))
	box(-24.0, -23.97, -0.35, 0.61, -20.4, -20.34, C_WALL, false, 1.0, _surface("steel"))
	box(-24.0, -23.97, 0.55, 0.61, -21.66, -20.34, C_WALL, false, 1.0, _surface("steel"))
	# --- průlez
	box(-31.2, -24.6, -1.0, -0.35, -21.6, -20.4, C_TUNNEL)
	box(-31.2, -24.6, -0.35, 0.85, -21.9, -21.6, C_TUNNEL)
	box(-31.2, -24.6, -0.35, 0.85, -20.4, -20.1, C_TUNNEL)
	box(-31.2, -24.6, 0.55, 0.85, -21.9, -20.1, C_TUNNEL)
	box(-31.5, -31.2, -0.35, 0.85, -21.9, -20.1, C_TUNNEL)
	box(-31.21, -31.19, -0.1, 0.36, -21.2, -20.8, C_WALL, false, 1.0, _emissive(Color(0.45, 0.85, 1.0), 2.2))

	# --- rámy a příčky světlíků (vrhají stíny do světelných kuželů)
	for sk in skylights:
		var r: Rect2 = sk.rect
		var yt: float = sk.top
		var n := maxi(int(round(r.size.x / 0.8)), 2)
		for i in range(1, n):
			var bx := r.position.x + r.size.x * i / n
			box(bx - 0.025, bx + 0.025, yt - 0.08, yt, r.position.y, r.end.y, C_WALL, false, 1.0, _surface("steel"))
		var mz := r.position.y + r.size.y * 0.5
		box(r.position.x, r.end.x, yt - 0.08, yt, mz - 0.025, mz + 0.025, C_WALL, false, 1.0, _surface("steel"))

	# --- odtokové mřížky
	for g in [Vector2(-9, -8), Vector2(9, -14), Vector2(-9, -20), Vector2(0, -23.5), Vector2(-18, -21)]:
		box(g.x - 0.2, g.x + 0.2, -0.36, -0.343, g.y - 0.2, g.y + 0.2, C_WALL, false, 1.0, _surface("steel"))

	# --- žebříky do bazénu
	for lx in [-3.0, 3.0]:
		for dx in [-0.26, 0.26]:
			tube([Vector3(lx + dx, -0.35, -7.45), Vector3(lx + dx, 0.5, -7.5), Vector3(lx + dx, 0.78, -7.8),
				Vector3(lx + dx, 0.5, -8.1), Vector3(lx + dx, 0.0, -8.13), Vector3(lx + dx, -2.3, -8.13)], 0.022, chrome_mat)
		for ry in [-0.55, -0.95, -1.35, -1.75]:
			tube([Vector3(lx - 0.26, ry, -8.11), Vector3(lx + 0.26, ry, -8.11)], 0.018, chrome_mat, 8, 1)

	# --- vodní plochy
	water(-12, 12, -8, -1.8)
	water(-12, 12, -26, -20)
	water(-12, -6, -20, -8)
	water(6, 12, -20, -8)
	water(-6, 6, -20, -8)
	water(-2, 2, -1.8, -0.6)
	water(-24, -12, -22.2, -19.8)
	water(-31.2, -24, -21.6, -20.4)
	water(-22, -12.6, -19.2, -11)
	water(-19, -17, -19.8, -19.2)
	water(-12.6, -12, -16, -14)
	water(7, 9, -1.8, 0.4)

func _spot(pos: Vector3, text: String, color: Color) -> void:
	# Připravené místo pro budoucí bednu, nákup nebo tajemství: bedna se slabým světlem a popiskem.
	var crate := box(pos.x - 0.55, pos.x + 0.55, pos.y, pos.y + 0.55, pos.z - 0.32, pos.z + 0.32, Color(0.32, 0.22, 0.12), true)
	crate.set_meta("spot", text)
	var caption := Label3D.new()
	caption.text = text
	caption.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	caption.font_size = 40
	caption.outline_size = 10
	caption.pixel_size = 0.003
	caption.modulate = Color(color.r, color.g, color.b, 0.75)
	caption.position = pos + Vector3(0, 1.05, 0)
	add_child(caption)
	var glow := OmniLight3D.new()
	glow.position = pos + Vector3(0, 0.9, 0)
	glow.light_color = color
	glow.light_energy = 0.18
	glow.omni_range = 2.6
	glow.shadow_enabled = false
	add_child(glow)

func _ramp() -> void:
	# neviditelná rampa přes schody: plynulý pohyb kamery bez cukání
	var cs := CollisionShape3D.new()
	var sh := ConvexPolygonShape3D.new()
	sh.points = PackedVector3Array([
		Vector3(-2, 0.5, 0.05), Vector3(2, 0.5, 0.05), Vector3(-2, -0.36, 0.05), Vector3(2, -0.36, 0.05),
		Vector3(-2, -0.36, -2.45), Vector3(2, -0.36, -2.45)])
	cs.shape = sh
	world_body.add_child(cs)

func _build_water() -> void:
	# Hladina jako sjednocení vodních obdélníků v JEDNÉ společné mřížce (souřadnice všech hran
	# + světová mřížka WATER_GRID). Díky tomu:
	#  - se plochy nepřekrývají (dvojitá průhlednost dělala světlejší pásy),
	#  - sousední buňky sdílejí přesně stejné vrcholy (žádné T-spoje → při vlnění se hladina netrhá),
	#  - hladina zajede kousek pod zdi, takže u stěn nezůstává suchá škvíra.
	if water_rects.is_empty(): return
	var bound := water_rects[0].grow(WATER_INTO_WALL + 0.01)
	for r in water_rects: bound = bound.merge(r.grow(WATER_INTO_WALL + 0.01))
	var snap := func(v: float) -> float: return snappedf(v, 0.001)
	var xs_d := {}
	var zs_d := {}
	for r in water_rects:
		for v in [r.position.x, r.end.x, r.position.x - WATER_INTO_WALL, r.end.x + WATER_INTO_WALL]: xs_d[snap.call(v)] = true
		for v in [r.position.y, r.end.y, r.position.y - WATER_INTO_WALL, r.end.y + WATER_INTO_WALL]: zs_d[snap.call(v)] = true
	# hrany zdí v dosahu: buňka pod zdí pak nikdy nepřečnívá do volného prostoru
	for sa in solids:
		var a: AABB = sa
		if a.position.y > WATER_Y - 0.01 or a.end.y < WATER_Y + 0.01: continue
		for v in [a.position.x, a.end.x]:
			if v > bound.position.x and v < bound.end.x: xs_d[snap.call(v)] = true
		for v in [a.position.z, a.end.z]:
			if v > bound.position.y and v < bound.end.y: zs_d[snap.call(v)] = true
	var g0 := floorf(bound.position.x / WATER_GRID)
	while g0 * WATER_GRID < bound.end.x:
		xs_d[snap.call(g0 * WATER_GRID)] = true
		g0 += 1.0
	g0 = floorf(bound.position.y / WATER_GRID)
	while g0 * WATER_GRID < bound.end.y:
		zs_d[snap.call(g0 * WATER_GRID)] = true
		g0 += 1.0
	var xs: Array = xs_d.keys()
	var zs: Array = zs_d.keys()
	xs.sort()
	zs.sort()
	var nx := xs.size() - 1
	var nz := zs.size() - 1
	var cells := PackedInt32Array()
	cells.resize(nx * nz)
	cells.fill(-1)
	var wall := PackedByteArray()
	wall.resize(nx * nz)
	# zdi a sloupy, které protínají hladinu
	for sa in solids:
		var a: AABB = sa
		if a.position.y > WATER_Y - 0.01 or a.end.y < WATER_Y + 0.01: continue
		var i0: int = maxi(xs.bsearch(a.position.x) - 1, 0)
		var i1: int = mini(xs.bsearch(a.end.x) + 1, nx)
		var j0: int = maxi(zs.bsearch(a.position.z) - 1, 0)
		var j1: int = mini(zs.bsearch(a.end.z) + 1, nz)
		for j in range(j0, j1):
			var cz: float = (zs[j] + zs[j + 1]) * 0.5
			if cz <= a.position.z or cz >= a.end.z: continue
			for i in range(i0, i1):
				var cx: float = (xs[i] + xs[i + 1]) * 0.5
				if cx > a.position.x and cx < a.end.x: wall[j * nx + i] = 1
	var fill := func(x0: float, x1: float, z0: float, z1: float, g: int, only_wall: bool) -> void:
		var i0: int = xs.bsearch(snap.call(x0))
		var i1: int = xs.bsearch(snap.call(x1))
		var j0: int = zs.bsearch(snap.call(z0))
		var j1: int = zs.bsearch(snap.call(z1))
		for j in range(j0, j1):
			for i in range(i0, i1):
				var k: int = j * nx + i
				if only_wall:
					if cells[k] < 0 and wall[k] == 1: cells[k] = g
				else:
					cells[k] = g
	for n in water_rects.size():
		var r := water_rects[n]
		fill.call(r.position.x, r.end.x, r.position.y, r.end.y, water_groups[n], false)
	var d := WATER_INTO_WALL
	for n in water_rects.size():
		var r := water_rects[n]
		var g := water_groups[n]
		fill.call(r.position.x - d, r.position.x, r.position.y - d, r.end.y + d, g, true)
		fill.call(r.end.x, r.end.x + d, r.position.y - d, r.end.y + d, g, true)
		fill.call(r.position.x, r.end.x, r.position.y - d, r.position.y, g, true)
		fill.call(r.position.x, r.end.x, r.end.y, r.end.y + d, g, true)
	# meshe: skupina → kousky 16×16 m (ořez mimo záběr kamery)
	const CHUNK := 16.0
	var chunks := {}
	for j in nz:
		for i in nx:
			var g := cells[j * nx + i]
			if g < 0: continue
			var key := Vector3i(g, int(floorf(xs[i] / CHUNK)), int(floorf(zs[j] / CHUNK)))
			if not chunks.has(key): chunks[key] = []
			(chunks[key] as Array).append(j * nx + i)
	var group_nodes := {}
	var tris := 0
	for key in chunks:
		var g: int = key.x
		if not group_nodes.has(g):
			var gn := Node3D.new()
			gn.name = "Water%d" % g
			add_child(gn)
			group_nodes[g] = gn
		var verts := PackedVector3Array()
		var normals := PackedVector3Array()
		var idx := PackedInt32Array()
		var vmap := {}
		for ck in chunks[key]:
			var i: int = ck % nx
			var j: int = ck / nx
			var q: Array[int] = []
			for c in [Vector2i(i, j), Vector2i(i + 1, j), Vector2i(i, j + 1), Vector2i(i + 1, j + 1)]:
				if not vmap.has(c):
					vmap[c] = verts.size()
					verts.append(Vector3(xs[c.x], WATER_Y, zs[c.y]))
					normals.append(Vector3.UP)
				q.append(vmap[c])
			idx.append_array(PackedInt32Array([q[0], q[1], q[2], q[1], q[3], q[2]]))
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts
		arr[Mesh.ARRAY_NORMAL] = normals
		arr[Mesh.ARRAY_INDEX] = idx
		var m := ArrayMesh.new()
		m.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		var mi := MeshInstance3D.new()
		mi.mesh = m
		mi.material_override = water_mat
		mi.layers = 2                       # vrstva 2: zrcadlová kamera a sondy vodu nevidí
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.extra_cull_margin = 0.5
		mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
		(group_nodes[g] as Node3D).add_child(mi)
		tris += idx.size() / 3
	water_meshes.clear()
	for n in water_rects.size(): water_meshes.append(group_nodes.get(water_groups[n]))
	print("voda: %d kousků, %d trojúhelníků, mřížka %d×%d" % [chunks.size(), tris, nx, nz])
	for i in 4:
		splashes.append(_make_splash())
	_build_dust()

func _build_dust() -> void:
	var sh: Shader = load("res://shaders/dust.gdshader")
	var slope := Vector2(sun_dir.x, sun_dir.z) / -sun_dir.y
	for sk in skylights:
		var r: Rect2 = sk.rect
		var h: float = sk.bottom - sk.floor
		var p := GPUParticles3D.new()
		var pm := ParticleProcessMaterial.new()
		pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
		pm.emission_box_extents = Vector3(r.size.x * 0.5 + absf(slope.x) * h * 0.5, h * 0.5, r.size.y * 0.5 + absf(slope.y) * h * 0.5)
		pm.gravity = Vector3(0, -0.004, 0)
		pm.direction = Vector3(0.3, -0.2, 0.2)
		pm.spread = 180.0
		pm.initial_velocity_min = 0.005
		pm.initial_velocity_max = 0.035
		pm.turbulence_enabled = true
		pm.turbulence_noise_strength = 0.04
		pm.turbulence_noise_scale = 2.5
		pm.turbulence_noise_speed_random = 0.3
		p.process_material = pm
		var qm := QuadMesh.new()
		qm.size = Vector2(0.011, 0.011)
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mat.set_shader_parameter("to_sun", -sun_dir)
		qm.material = mat
		p.draw_pass_1 = qm
		p.amount = int(clampf(r.get_area() * h * 55.0, 150.0, 1400.0))
		p.lifetime = 14.0
		p.preprocess = 14.0
		p.randomness = 1.0
		p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		p.position = Vector3(r.get_center().x + slope.x * h * 0.5, sk.floor + h * 0.5, r.get_center().y + slope.y * h * 0.5)
		p.visibility_aabb = AABB(-pm.emission_box_extents - Vector3.ONE, pm.emission_box_extents * 2.0 + Vector3.ONE * 2.0)
		add_child(p)
		dust.append(p)

func _build_flash_dust() -> void:
	# Prach a drobné částice ve vzduchu kolem hráče. Jsou stínované, takže je vidět jen tam,
	# kam svítí baterka nebo lampa – v kuželu světla se třpytí, ve tmě zmizí.
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(4.5, 1.6, 4.5)
	pm.gravity = Vector3(0, -0.006, 0)
	pm.spread = 180.0
	pm.initial_velocity_min = 0.005
	pm.initial_velocity_max = 0.03
	pm.turbulence_enabled = true
	pm.turbulence_noise_strength = 0.05
	pm.turbulence_noise_scale = 2.0
	pm.scale_min = 0.5
	pm.scale_max = 1.4
	p.process_material = pm
	var qm := QuadMesh.new()
	qm.size = Vector2(0.013, 0.013)
	var mat := StandardMaterial3D.new()
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_VERTEX
	mat.backlight_enabled = true          # svítí i proti světlu (třpyt v kuželu baterky)
	mat.backlight = Color(1, 1, 1)
	mat.albedo_color = Color(1.0, 0.98, 0.94, 0.75)
	mat.albedo_texture = _combat_fx()._dot()
	mat.roughness = 1.0
	mat.disable_receive_shadows = true
	qm.material = mat
	p.draw_pass_1 = qm
	p.amount = 1300
	p.lifetime = 12.0
	p.preprocess = 12.0
	p.randomness = 1.0
	p.local_coords = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	p.visibility_aabb = AABB(Vector3(-8, -4, -8), Vector3(16, 8, 16))
	p.layers = 1 << 17
	add_child(p)
	_flash_dust = p

func _make_splash() -> GPUParticles3D:
	var p := GPUParticles3D.new()
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	pm.emission_sphere_radius = 0.12
	pm.direction = Vector3.UP
	pm.spread = 55.0
	pm.initial_velocity_min = 1.0
	pm.initial_velocity_max = 3.2
	pm.gravity = Vector3(0, -9.8, 0)
	pm.scale_min = 0.4
	pm.scale_max = 1.3
	p.process_material = pm
	var sm := SphereMesh.new()
	sm.radius = 0.012
	sm.height = 0.03
	sm.radial_segments = 6
	sm.rings = 3
	var dm := StandardMaterial3D.new()
	dm.albedo_color = Color(0.85, 0.95, 0.97, 0.8)
	dm.roughness = 0.05
	dm.metallic = 0.2
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	sm.material = dm
	p.draw_pass_1 = sm
	p.amount = 60
	p.lifetime = 0.75
	p.one_shot = true
	p.explosiveness = 0.92
	p.emitting = false
	p.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(p)
	return p

func splash_at(pos: Vector3, strength: float) -> void:
	var p := splashes[_splash_i]
	_splash_i = (_splash_i + 1) % splashes.size()
	p.global_position = pos
	p.amount_ratio = clampf(strength, 0.15, 1.0)
	p.speed_scale = 1.0
	(p.process_material as ParticleProcessMaterial).initial_velocity_max = 1.5 + 2.6 * strength
	p.restart()
	p.emitting = true

# =============================================================== východní křídlo
const ANGEL_POOL := Rect2(26, -27, 15, 18)      # obří hluboký bazén se sochou (x, z)
const ANGEL_DEPTH := 14.4

func _build_east_wing() -> void:
	# Chodba z haly (brána 1) a obří síň s hlubokým bazénem (brána 2).
	# Chodba: staré sprchy, zelené dlaždice.
	_palette = {C_WALL: Color(0.42, 0.58, 0.48), C_FLOOR: Color(0.36, 0.5, 0.42), C_CEIL: Color(0.4, 0.5, 0.45), C_BLUE: Color(0.12, 0.22, 0.16)}
	box(12.6, 20.6, -1.0, -0.35, -15, -13, C_FLOOR)
	box(12.6, 20.0, -0.35, 3.0, -15.6, -15)
	box(12.6, 20.0, -0.35, 3.0, -13, -12.4)
	slab_with_holes(12.6, 20.0, -15.6, -12.4, 3.0, 3.6, [] as Array[Rect2], C_CEIL, 0.5)
	box(12.61, 20.0, 1.2, 1.4, -15.0, -14.99, C_BLUE, false)
	box(12.61, 20.0, 1.2, 1.4, -13.01, -13.0, C_BLUE, false)
	water(12, 20.6, -15, -13)
	for sz in [14.5, 17.0, 19.0]:
		_shower(Vector3(sz, 0.0, -15.0), 0.0)
		_shower(Vector3(sz - 1.2, 0.0, -13.0), PI)
	# síň: břidlicově šedá, tmavé hluboké dlaždice, velké desky
	_palette = {C_WALL: Color(0.36, 0.4, 0.42), C_FLOOR: Color(0.3, 0.34, 0.35), C_CEIL: Color(0.22, 0.24, 0.26), C_POOL: Color(0.18, 0.4, 0.42), C_BLUE: Color(0.45, 0.08, 0.06)}
	_tile_mul = 0.5
	var p := ANGEL_POOL
	box(20.6, 46.6, -1.0, -0.35, -34, p.position.y - 0.6, C_FLOOR)
	box(20.6, 46.6, -1.0, -0.35, p.end.y + 0.6, -2, C_FLOOR)
	box(20.6, p.position.x - 0.6, -1.0, -0.35, p.position.y - 0.6, p.end.y + 0.6, C_FLOOR)
	box(p.end.x + 0.6, 46.6, -1.0, -0.35, p.position.y - 0.6, p.end.y + 0.6, C_FLOOR)
	# bazén: stěny až na dno, dno hluboko pod hladinou
	box(p.position.x - 0.6, p.end.x + 0.6, -ANGEL_DEPTH - 0.6, -ANGEL_DEPTH, p.position.y - 0.6, p.end.y + 0.6, C_POOL, true, 2.0)
	box(p.position.x - 0.6, p.position.x, -ANGEL_DEPTH, -0.35, p.position.y, p.end.y, C_POOL, true, 2.0)
	box(p.end.x, p.end.x + 0.6, -ANGEL_DEPTH, -0.35, p.position.y, p.end.y, C_POOL, true, 2.0)
	# jižní stěna bazénu s průchodem u dna (mříž do Nádrže)
	box(p.position.x - 0.6, 32.5, -ANGEL_DEPTH, -0.35, p.position.y - 0.6, p.position.y, C_POOL, true, 2.0)
	box(34.5, p.end.x + 0.6, -ANGEL_DEPTH, -0.35, p.position.y - 0.6, p.position.y, C_POOL, true, 2.0)
	box(32.5, 34.5, -ANGEL_DEPTH + 2.6, -0.35, p.position.y - 0.6, p.position.y, C_POOL, true, 2.0)
	box(p.position.x - 0.6, p.end.x + 0.6, -ANGEL_DEPTH, -0.35, p.end.y, p.end.y + 0.6, C_POOL, true, 2.0)
	box(p.position.x - 0.8, p.end.x + 0.8, -0.36, -0.342, p.position.y - 0.8, p.position.y - 0.6, C_BLUE, false)
	box(p.position.x - 0.8, p.end.x + 0.8, -0.36, -0.342, p.end.y + 0.6, p.end.y + 0.8, C_BLUE, false)
	box(p.position.x - 0.8, p.position.x - 0.6, -0.36, -0.342, p.position.y - 0.6, p.end.y + 0.6, C_BLUE, false)
	box(p.end.x + 0.6, p.end.x + 0.8, -0.36, -0.342, p.position.y - 0.6, p.end.y + 0.6, C_BLUE, false)
	# stěny a strop
	box(20.0, 20.6, -0.35, 16, -34.6, -15)
	box(20.0, 20.6, -0.35, 16, -13, -1.4)
	box(20.0, 20.6, 2.6, 16, -15, -13)
	box(46.6, 47.2, -1.0, 16, -34.6, -1.4)
	box(20.0, 24.0, -1.0, 16, -34.6, -34)
	box(24.0, 26.0, 2.6, 16, -34.6, -34)                     # průchod do atria (brána)
	box(26.0, 30.0, -1.0, 4.15, -34.6, -34)
	box(26.0, 30.0, 6.5, 16, -34.6, -34)                     # okno z balkonu atria na anděla
	box(30.0, 47.2, -1.0, 16, -34.6, -34)
	box(20.0, 32.0, -1.0, 16, -2, -1.4)
	box(35.0, 47.2, -1.0, 16, -2, -1.4)
	box(32.0, 35.0, 2.6, 16, -2, -1.4)                        # průchod na terasy (brána 3)
	slab_with_holes(20.0, 47.2, -34.6, -1.4, 16, 16.6, [] as Array[Rect2], C_CEIL, 0.5)
	box(20.61, 24.0, 1.2, 1.4, -33.99, -33.98, C_BLUE, false)
	box(26.0, 46.59, 1.2, 1.4, -33.99, -33.98, C_BLUE, false)
	box(20.61, 32.0, 1.2, 1.4, -2.02, -2.01, C_BLUE, false)
	box(35.0, 46.59, 1.2, 1.4, -2.02, -2.01, C_BLUE, false)
	# sloupy po obvodu
	for cx in [23.0, 44.0]:
		for cz in [-30.0, -18.0, -6.0]:
			box(cx - 0.5, cx + 0.5, -0.35, 16, cz - 0.5, cz + 0.5)
	water(20.6, 46.6, -34, -2, 1)                     # skupina 1: Andělský bazén se dá vypustit
	# socha: obří hlava a ramena vyčnívají z vody
	var angel := Props.angel(ANGEL_DEPTH + 6.0)
	add_child(angel)
	angel.position = Vector3(p.get_center().x, -ANGEL_DEPTH, p.get_center().y)
	angel.rotation.y = -PI / 2
	_palette = {}
	_tile_mul = 1.0
	# padlé sloupy v mělké vodě a řetězy visící ze tmy
	# zřícený sloup: dva obložené kusy ležící v mělké vodě
	var slate := Color(0.36, 0.4, 0.42)
	box(20.8, 24.0, -0.35, 0.65, -25.5, -24.5, slate)
	box(24.3, 25.1, -0.35, 0.5, -26.6, -25.2, slate)
	box(43.6, 44.6, -0.35, 0.65, -14.0, -9.8, slate)
	for c in [Vector2(28, -30), Vector2(39, -31), Vector2(24, -5), Vector2(42, -4.5), Vector2(33.5, -6)]:
		_chain(Vector3(c.x, 16.0, c.y), randf_range(5.0, 9.0))
	# světla: pár starých lamp a studené světlo zespodu z bazénu
	_lamp(Vector3(16.3, 2.96, -14.0), 0.2, 0.4, 0.3, 5.0, true)
	_lamp(Vector3(24.0, 15.96, -14.0), 0.3, 0.7, 1.4, 20.0, true)
	_lamp(Vector3(43.0, 15.96, -26.0), 0.3, 0.7, 1.2, 20.0, false)
	var under := OmniLight3D.new()
	under.position = Vector3(p.get_center().x - 3.0, -5.0, p.get_center().y)
	under.light_color = Color(0.3, 0.8, 0.75)
	under.light_energy = 2.5
	under.omni_range = 14.0
	under.shadow_enabled = false
	add_child(under)
	var face := SpotLight3D.new()
	face.light_color = Color(0.85, 0.9, 1.0)
	face.light_energy = 1.4
	face.spot_range = 28.0
	face.spot_angle = 16.0
	face.shadow_enabled = true
	add_child(face)
	face.look_at_from_position(Vector3(24.0, 13.0, -18.0), Vector3(p.get_center().x, 1.5, p.get_center().y))

func _steps(x0: float, x1: float, z0: float, z1: float, y0: float, y1: float, count: int, along_x := false) -> void:
	# Schodiště: count stupňů z výšky y0 do y1 mezi z0 a z1 (nebo x0 a x1).
	for i in count:
		var top := y0 + (y1 - y0) * float(i + 1) / count
		var a := float(i) / count
		var b := float(i + 1) / count
		if along_x:
			var xa := lerpf(x0, x1, a)
			var xb := lerpf(x0, x1, b)
			box(minf(xa, xb), maxf(xa, xb), -1.0, top, z0, z1, C_FLOOR, false)
		else:
			var za := lerpf(z0, z1, a)
			var zb := lerpf(z0, z1, b)
			box(x0, x1, -1.0, top, minf(za, zb), maxf(za, zb), C_FLOOR, false)
	# Neviditelná rampa přes stupně: hráč i zombie po ní plynule vyjdou nahoru.
	var low := minf(y0, y1) - 0.6
	var pts := PackedVector3Array()
	if along_x:
		for zz in [z0, z1]:
			pts.append_array([Vector3(x0, y0, zz), Vector3(x1, y1, zz), Vector3(x0, low, zz), Vector3(x1, low, zz)])
	else:
		for xx in [x0, x1]:
			pts.append_array([Vector3(xx, y0, z0), Vector3(xx, y1, z1), Vector3(xx, low, z0), Vector3(xx, low, z1)])
	var ramp := CollisionShape3D.new()
	var hull := ConvexPolygonShape3D.new()
	hull.points = pts
	ramp.shape = hull
	world_body.add_child(ramp)

func _bench(pos: Vector3, length: float, yaw: float) -> void:
	# Jednoduchá lavice jako na koupališti: dřevěné latě na kovových nohách.
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.rotation.y = yaw
	var wood := _surface("wood")
	var steel := _surface("steel")
	for i in 3:
		var slat := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(length, 0.035, 0.11)
		slat.mesh = bm
		slat.material_override = wood
		slat.position = Vector3(0, 0.44, -0.13 + i * 0.13)
		root.add_child(slat)
	for lx in [-length * 0.5 + 0.15, length * 0.5 - 0.15]:
		for part in [[Vector3(lx, 0.21, -0.14), Vector3(0.04, 0.42, 0.04)], [Vector3(lx, 0.21, 0.14), Vector3(0.04, 0.42, 0.04)], [Vector3(lx, 0.41, 0.0), Vector3(0.04, 0.04, 0.36)]]:
			var leg := MeshInstance3D.new()
			var lm := BoxMesh.new()
			lm.size = part[1]
			leg.mesh = lm
			leg.material_override = steel
			leg.position = part[0]
			root.add_child(leg)
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(length, 0.46, 0.4)
	cs.shape = shape
	cs.position.y = 0.23
	Props.merge(root)
	body.add_child(cs)
	root.add_child(body)

func _rbox(center: Vector3, size: Vector3, yaw: float, tint: Color) -> void:
	# Natočený kvádr (zkosené rohy, šikmé stěny).
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = tile_mat
	mi.set_instance_shader_parameter("tint", _palette.get(tint, tint))
	mi.set_instance_shader_parameter("tile_scale", _tile_mul)
	mi.position = center
	mi.rotation.y = yaw
	add_child(mi)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = mi.transform
	world_body.add_child(cs)

func _noise_tex(freq: float, normal := false, bump := 1.0, ramp: Gradient = null, cellular := false, size := 512) -> NoiseTexture2D:
	var n := FastNoiseLite.new()
	n.seed = randi()
	n.frequency = freq
	n.fractal_octaves = 5
	if cellular:
		n.noise_type = FastNoiseLite.TYPE_CELLULAR
	var t := NoiseTexture2D.new()
	t.width = size
	t.height = size
	t.seamless = true
	t.noise = n
	if normal:
		t.as_normal_map = true
		t.bump_strength = bump
	if ramp:
		t.color_ramp = ramp
	return t

func _grad(colors: Array, offsets: Array) -> Gradient:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array(offsets)
	g.colors = PackedColorArray(colors)
	return g

func _surface(kind: String) -> StandardMaterial3D:
	# Procedurální PBR povrchy (šum: barevné skvrny, mikronormály, drsnost), triplanárně, bez UV.
	if _surfaces.has(kind):
		return _surfaces[kind]
	var m := StandardMaterial3D.new()
	m.uv1_triplanar = true
	m.normal_enabled = true
	m.roughness_texture_channel = BaseMaterial3D.TEXTURE_CHANNEL_GRAYSCALE
	match kind:
		"paint":
			m.albedo_texture = _noise_tex(0.02, false, 1.0, _grad([Color(0.2, 0.3, 0.27), Color(0.22, 0.33, 0.3), Color(0.38, 0.25, 0.15), Color(0.3, 0.17, 0.09)], [0.0, 0.55, 0.72, 1.0]))
			m.normal_texture = _noise_tex(0.05, true, 2.0)
			m.roughness_texture = _noise_tex(0.03, false, 1.0, _grad([Color(0.45, 0.45, 0.45), Color(0.9, 0.9, 0.9)], [0.0, 1.0]))
			m.metallic = 0.25
			m.uv1_scale = Vector3(0.6, 0.6, 0.6)
		"steel":
			m.albedo_texture = _noise_tex(0.03, false, 1.0, _grad([Color(0.42, 0.43, 0.45), Color(0.55, 0.56, 0.58), Color(0.4, 0.3, 0.22)], [0.0, 0.8, 1.0]))
			m.normal_texture = _noise_tex(0.12, true, 0.8)
			m.roughness_texture = _noise_tex(0.06, false, 1.0, _grad([Color(0.3, 0.3, 0.3), Color(0.65, 0.65, 0.65)], [0.0, 1.0]))
			m.metallic = 0.3
			m.uv1_scale = Vector3(1.5, 1.5, 1.5)
		"rust":
			m.albedo_texture = _noise_tex(0.04, false, 1.0, _grad([Color(0.28, 0.14, 0.07), Color(0.45, 0.24, 0.1), Color(0.3, 0.3, 0.3)], [0.0, 0.6, 1.0]))
			m.normal_texture = _noise_tex(0.08, true, 3.0)
			m.roughness = 0.9
			m.metallic = 0.2
		"wood":
			m.albedo_texture = _noise_tex(0.015, false, 1.0, _grad([Color(0.36, 0.21, 0.11), Color(0.52, 0.33, 0.18), Color(0.44, 0.27, 0.14), Color(0.58, 0.39, 0.22)], [0.0, 0.35, 0.6, 1.0]))
			m.normal_texture = _noise_tex(0.04, true, 1.2)
			m.roughness = 0.72
			m.uv1_scale = Vector3(0.4, 4.0, 0.4)       # protažené léta = dřevěná kresba
		"laminate":
			m.albedo_texture = _noise_tex(0.08, false, 1.0, _grad([Color(0.5, 0.16, 0.12), Color(0.58, 0.2, 0.15)], [0.0, 1.0]))
			m.normal_texture = _noise_tex(0.2, true, 0.3)
			m.roughness = 0.35
		"enamel":
			m.albedo_texture = _noise_tex(0.05, false, 1.0, _grad([Color(0.86, 0.85, 0.8), Color(0.92, 0.91, 0.87), Color(0.6, 0.5, 0.38)], [0.0, 0.85, 1.0]))
			m.normal_texture = _noise_tex(0.1, true, 0.4)
			m.roughness = 0.3
		"stone":
			m.albedo_texture = _noise_tex(0.03, false, 1.0, _grad([Color(0.48, 0.49, 0.47), Color(0.62, 0.62, 0.6)], [0.0, 1.0]))
			m.normal_texture = _noise_tex(0.06, true, 2.0)
			m.roughness = 0.9
	_surfaces[kind] = m
	return m

func _mat(color: Color, rough := 0.6, metal := 0.0) -> StandardMaterial3D:
	# Barevný povrch s jemnou nerovností a skvrnami, aby nic nebylo „plasticky hladké“.
	var m := StandardMaterial3D.new()
	m.albedo_color = color
	m.albedo_texture = _surfaces.get("_grime", null)
	if m.albedo_texture == null:
		_surfaces["_grime"] = _noise_tex(0.04, false, 1.0, _grad([Color(0.82, 0.8, 0.76), Color(1, 1, 1), Color(1, 1, 1)], [0.0, 0.45, 1.0]))
		_surfaces["_bumps"] = _noise_tex(0.1, true, 0.5)
		m.albedo_texture = _surfaces["_grime"]
	m.normal_enabled = true
	m.normal_texture = _surfaces["_bumps"]
	m.uv1_triplanar = true
	m.roughness = rough
	m.metallic = metal
	return m

func _part(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	return mi

func _boxm(size: Vector3) -> BoxMesh:
	var b := BoxMesh.new()
	b.size = size
	return b

func _cyl(radius: float, height: float, seg := 12) -> CylinderMesh:
	var c := CylinderMesh.new()
	c.top_radius = radius
	c.bottom_radius = radius
	c.height = height
	c.radial_segments = seg
	return c

func _stair_ramp(x0: float, x1: float, za: float, ya: float, zb: float, yb: float, tint: Color) -> void:
	# Šikmá rampa (servisní schodiště) z bodu (za, ya) do (zb, yb); horní plocha je pochozí.
	var length := Vector2(zb - za, yb - ya).length()
	var angle := atan2(yb - ya, absf(zb - za)) * signf(za - zb)
	var t := Transform3D(Basis(Vector3.RIGHT, angle), Vector3((x0 + x1) * 0.5, (ya + yb) * 0.5 - 0.15, (za + zb) * 0.5))
	var size := Vector3(x1 - x0, 0.3, length)
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = _mat(tint, 0.6)
	mi.mesh = bm
	mi.transform = t
	add_child(mi)
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = t
	body.add_child(cs)
	add_child(body)
	# Zábradlí na volné straně.
	var rail := MeshInstance3D.new()
	var rm := BoxMesh.new()
	rm.size = Vector3(0.05, 0.05, length)
	rm.material = chrome_mat
	rail.mesh = rm
	rail.transform = t.translated_local(Vector3((x1 - x0) * 0.5 - 0.03, 1.0, 0))
	add_child(rail)

var _vases: Array = []

func _settle_vases() -> void:
	# Vázy postavit na to, co pod nimi skutečně je (pult, podlaha) – nic nesmí levitovat.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var space := get_world_3d().direct_space_state
	for vase in _vases:
		var p: Vector3 = (vase as Node3D).global_position
		var hit := space.intersect_ray(PhysicsRayQueryParameters3D.create(p + Vector3.UP * 1.2, p + Vector3.DOWN * 3.0, 1))
		if not hit.is_empty(): (vase as Node3D).global_position.y = (hit.position as Vector3).y

func _model_fit(path: String, fit: float, axis: int) -> Node3D:
	# Model zmenšený na velikost; počátek držáku = střed podstavy.
	var holder := Node3D.new()
	var pivot := Node3D.new()
	holder.add_child(pivot)
	pivot.add_child((load(path) as PackedScene).instantiate())
	var b: AABB = Props._bounds(pivot)
	var size: float = b.size[axis]
	var k := fit / maxf(size, 0.0001)
	pivot.scale = Vector3.ONE * k
	pivot.position = -Vector3(b.get_center().x, b.position.y, b.get_center().z) * k
	add_child(holder)
	return holder

func _solid_box(center: Vector3, size: Vector3, yaw := 0.0) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	body.add_child(cs)
	add_child(body)
	body.transform = Transform3D(Basis(Vector3.UP, yaw), center)

func _build_toilets() -> void:
	# Toalety za šatnami: čtyři kabinky, pisoáry a umyvadla se zrcadly. Podlaha 0,5 m jako šatny.
	var fy := 0.5
	_palette = {C_WALL: Color(0.84, 0.86, 0.8), C_FLOOR: Color(0.5, 0.53, 0.5), C_CEIL: Color(0.78, 0.79, 0.74)}
	box(11.4, 12, -1.0, 0.5, 6.2, 7.4, C_FLOOR)
	box(12, 19.6, -1.0, fy, 0.8, 9.6, C_FLOOR)
	box(19.6, 20.2, fy, 3.6, 0.8, 9.6)
	box(12, 20.2, fy, 3.6, 9, 9.6)
	box(12, 20.2, fy, 3.6, 0.8, 1.4)
	box(12, 20.2, 3.0, 3.6, 1.4, 9, C_CEIL)
	var panel := Color(0.36, 0.42, 0.38)
	var stalls := [2.0, 3.5, 5.0, 6.5, 8.0]
	for z in stalls:
		box(18.0, 19.6, fy + 0.15, fy + 2.0, z - 0.025, z + 0.025, panel)
	box(17.97, 18.03, fy + 1.95, fy + 2.05, 2.0, 8.0, panel, false)
	# dvířka: jedny zavřené (zevnitř zamčeno), ostatní pootevřené
	var door_mat := _mat(panel, 0.7)
	for i in 4:
		var z0: float = stalls[i]
		var hinge := Node3D.new()
		add_child(hinge)
		hinge.position = Vector3(18.0, fy + 0.15, z0 + 0.03)
		var open_a: float = [1.2, 0.0, 1.7, 0.6][i]
		hinge.rotation.y = -open_a
		var door := MeshInstance3D.new()
		var dm := BoxMesh.new()
		dm.size = Vector3(0.03, 1.8, 1.42)
		dm.material = door_mat
		door.mesh = dm
		door.position = Vector3(0, 0.9, 0.71)
		hinge.add_child(door)
		_solid_box(hinge.transform * Vector3(0, 0.9, 0.71), Vector3(0.04, 1.8, 1.42), hinge.rotation.y)
		# záchod v kabince, zády ke zdi
		var t := _model_fit("res://assets/toilets/toilet.glb", 0.8, 1)
		t.position = Vector3(19.2, fy, (z0 + float(stalls[i + 1])) * 0.5)
		t.rotation.y = PI
		_solid_box(Vector3(19.2, fy + 0.4, t.position.z), Vector3(0.7, 0.8, 0.5))
	# pisoáry na severní zdi
	for x in [13.2, 14.1, 15.0]:
		var u := _model_fit("res://assets/toilets/urinal.glb", 0.78, 1)
		u.position = Vector3(x, fy + 0.3, 8.86)
		u.rotation.y = PI / 2
		_solid_box(Vector3(x, fy + 0.7, 8.85), Vector3(0.3, 0.8, 0.3))
	# umyvadla se zrcadly na jižní zdi
	var mirror := _mat(Color(0.7, 0.74, 0.76), 0.06, 1.0)
	var cracked := _mat(Color(0.35, 0.37, 0.38), 0.4, 0.8)
	for i in 3:
		var x: float = [13.3, 14.8, 16.3][i]
		var sk := _model_fit("res://assets/toilets/sink.glb", 1.0, 1)
		sk.position = Vector3(x, fy, 1.4 + 0.36)
		sk.rotation.y = PI / 2
		_solid_box(Vector3(x, fy + 0.5, 1.72), Vector3(0.74, 1.0, 0.56))
		box(x - 0.3, x + 0.3, fy + 1.25, fy + 1.95, 1.4, 1.42, C_WALL, false, 1.0, cracked if i == 1 else mirror)
	_lamp(Vector3(14.5, 2.96, 5.2), 0.25, 0.5, 0.7, 7.0, true)
	_lamp(Vector3(18.8, 2.96, 5.2), 0.2, 0.4, 0.35, 5.0, true)
	_palette = {}

func _build_west_showers() -> void:
	# Dámské šatny a sprchy (západně od vstupní haly): plechové skříňky, lavice, šest sprch za příčkou.
	var fy := 0.5
	var top := 3.2
	_palette = {C_WALL: Color(0.7, 0.8, 0.82), C_FLOOR: Color(0.46, 0.52, 0.54), C_CEIL: Color(0.72, 0.76, 0.76)}
	box(-2.6, -2, -1.0, fy, 3.6, 5.2, C_FLOOR)
	box(-12.6, -2.6, -1.0, fy, -1.2, 10.6, C_FLOOR)
	box(-12.6, -12.0, fy, top + 0.4, -1.2, 10.6)
	box(-12.6, -2.6, fy, top + 0.4, 10.0, 10.6)
	box(-12.6, -2.6, fy, top + 0.4, -1.2, -0.6)
	box(-12.6, -2.6, top, top + 0.4, -0.6, 10.0, C_CEIL)
	# příčka mezi šatnou a sprchami s průchodem
	box(-7.6, -7.0, fy, top, -0.6, 6.4)
	box(-7.6, -7.0, fy, top, 8.2, 10.0)
	box(-7.6, -7.0, 2.6, top, 6.4, 8.2)
	# šatna: dvě řady školních skříněk a lavice
	for side in [[-0.6, -PI / 2, 1.0], [10.0, PI / 2, -1.0]]:
		var bank := _model_fit("res://assets/props2/school_locker.glb", 2.0, 1)
		bank.position = Vector3(-4.8, fy, float(side[0]) + float(side[2]) * 0.3)
		bank.rotation.y = side[1]
		_solid_box(Vector3(-4.8, fy + 1.0, float(side[0]) + float(side[2]) * 0.3), Vector3(3.0, 2.0, 0.55))
	_bench(Vector3(-4.8, fy, 3.3), 2.6, 0.0)
	_bench(Vector3(-4.8, fy, 6.3), 2.6, 0.0)
	# sprchy: šest růžic na západní zdi, nízké dělicí stěnky
	var tile := Color(0.58, 0.72, 0.74)
	for i in 6:
		var z := 0.3 + i * 1.6
		_shower(Vector3(-12.0, fy + 0.35, z), PI / 2)
		if i < 5: box(-12.0, -10.9, fy, fy + 1.9, z + 0.77, z + 0.83, tile)
	box(-10.2, -9.6, fy, fy + 0.012, 4.2, 4.8, C_WALL, false, 1.0, _surface("steel"))      # odtoková mřížka
	var steam := FogVolume.new()
	steam.size = Vector3(4.4, 2.6, 10.4)
	var fm := FogMaterial.new()
	fm.density = 0.06
	fm.albedo = Color(0.85, 0.9, 0.92)
	steam.material = fm
	add_child(steam)
	steam.position = Vector3(-9.8, fy + 1.3, 4.7)
	_lamp(Vector3(-4.8, top - 0.04, 4.8), 0.25, 0.5, 0.75, 8.0, true)
	_lamp(Vector3(-9.8, top - 0.04, 2.0), 0.2, 0.4, 0.45, 6.0, true)
	_lamp(Vector3(-9.8, top - 0.04, 7.6), 0.2, 0.4, 0.35, 6.0, false)
	_palette = {}

func _build_cistern() -> void:
	# Servisní schodiště podél západní stěny Síně anděla (pod vodou, dokud se nevypustí),
	# tunel ze dna za mříží a Nádrž: podzemní cisterna, kde lázně ukrývaly výzkum.
	var p := ANGEL_POOL
	var fl := -ANGEL_DEPTH
	var steel := Color(0.32, 0.34, 0.33)
	_stair_ramp(p.position.x, p.position.x + 1.4, p.end.y, -0.35, p.position.y + 2.4, -7.4, steel)
	box(p.position.x, p.position.x + 2.8, -7.7, -7.4, p.position.y + 0.2, p.position.y + 2.4, steel)
	_stair_ramp(p.position.x + 1.4, p.position.x + 2.8, p.position.y + 2.4, -7.4, p.end.y - 1.0, fl, steel)
	_palette = {C_WALL: Color(0.3, 0.33, 0.31), C_FLOOR: Color(0.24, 0.27, 0.25), C_CEIL: Color(0.17, 0.19, 0.18)}
	_tile_mul = 0.5
	# tunel
	box(32.0, 35.0, fl - 0.6, fl, -39.4, p.position.y - 0.6, C_FLOOR)
	box(32.0, 32.5, fl, fl + 3.1, -39.4, p.position.y - 0.6)
	box(34.5, 35.0, fl, fl + 3.1, -39.4, p.position.y - 0.6)
	box(32.0, 35.0, fl + 2.6, fl + 3.1, -39.4, p.position.y - 0.6, C_CEIL)
	# nádrž
	var c := Rect2(22.0, -62.0, 24.0, 22.0)
	var h := 8.0
	box(c.position.x - 0.6, c.end.x + 0.6, fl - 0.6, fl, c.position.y - 0.6, c.end.y + 0.6, C_FLOOR)
	box(c.position.x - 0.6, c.position.x, fl, fl + h, c.position.y, c.end.y)
	box(c.end.x, c.end.x + 0.6, fl, fl + h, c.position.y, c.end.y)
	box(c.position.x - 0.6, c.end.x + 0.6, fl, fl + h, c.position.y - 0.6, c.position.y)
	box(c.position.x - 0.6, 32.5, fl, fl + h, c.end.y, c.end.y + 0.6)
	box(34.5, c.end.x + 0.6, fl, fl + h, c.end.y, c.end.y + 0.6)
	box(32.5, 34.5, fl + 2.6, fl + h, c.end.y, c.end.y + 0.6)
	box(c.position.x - 0.6, c.end.x + 0.6, fl + h, fl + h + 0.6, c.position.y - 0.6, c.end.y + 0.6, C_CEIL)
	for q in [Vector2(26.5, -57), Vector2(26.5, -51), Vector2(26.5, -45), Vector2(41.5, -57), Vector2(41.5, -51), Vector2(41.5, -45),
			Vector2(30.5, -58.5), Vector2(37.5, -58.5), Vector2(30.5, -43.5), Vector2(37.5, -43.5)]:
		box(q.x - 0.5, q.x + 0.5, fl, fl + h, q.y - 0.5, q.y + 0.5)
	# laboratoř v rohu: stoly, police, sudy
	var lab := Color(0.42, 0.44, 0.42)
	box(22.0, 22.6, fl, fl + 2.2, -50.0, -46.0, lab)
	box(28.0, 29.6, fl, fl + 0.9, -42.6, -41.4, lab)
	for b in [Vector3(23.2, 0, -58.8), Vector3(24.4, 0, -60.6), Vector3(44.6, 0, -60.4), Vector3(44.8, 0, -42.0)]:
		var barrel := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.35
		cm.bottom_radius = 0.35
		cm.height = 1.0
		cm.material = _mat(Color(0.35, 0.3, 0.15), 0.7)
		barrel.mesh = cm
		barrel.position = Vector3(b.x, fl + 0.5, b.z)
		add_child(barrel)
	# kalná voda po kotníky
	var level := fl + 0.45
	var wm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(c.size.x, c.size.y)
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.09, 0.12, 0.08, 0.86)
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.roughness = 0.12
	wmat.metallic = 0.25
	pm.material = wmat
	wm.mesh = pm
	wm.position = Vector3(c.get_center().x, level, c.get_center().y)
	wm.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(wm)
	add_water_zone(c, level)
	# světla: pár blikajících zářivek a nouzová červená
	_lamp(Vector3(33.5, fl + 2.56, -33.5), 0.2, 0.4, 0.6, 6.0, true)
	_lamp(Vector3(28.0, fl + h - 0.04, -46.0), 0.3, 0.6, 0.9, 12.0, true)
	_lamp(Vector3(40.0, fl + h - 0.04, -57.0), 0.3, 0.6, 0.7, 12.0, false)
	for e in [Vector3(22.8, fl + 3.0, -55.0), Vector3(45.2, fl + 3.0, -48.0), Vector3(33.5, fl + 3.0, -39.0)]:
		var red := OmniLight3D.new()
		red.position = e
		red.light_color = Color(1.0, 0.12, 0.06)
		red.light_energy = 0.8
		red.omni_range = 7.0
		red.shadow_enabled = false
		add_child(red)
	_palette = {}
	_tile_mul = 1.0

func _shower(pos: Vector3, yaw: float) -> void:
	# Stará sprcha na zdi: trubka, růžice a kohoutek.
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.rotation.y = yaw
	_part(root, _cyl(0.025, 2.1), chrome_mat, Vector3(0, 1.05, 0.04))
	_part(root, _cyl(0.025, 0.35), chrome_mat, Vector3(0, 2.1, 0.2), Vector3(PI / 2, 0, 0))
	_part(root, _cyl(0.09, 0.04, 16), chrome_mat, Vector3(0, 2.05, 0.36))
	_part(root, _cyl(0.04, 0.08), chrome_mat, Vector3(0, 1.1, 0.09), Vector3(PI / 2, 0, 0))
	Props.merge(root)

func _fallen_column(pos: Vector3, yaw: float, length: float) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.rotation.y = yaw
	var stone := _mat(Color(0.55, 0.56, 0.54), 0.9)
	var col := _part(root, _cyl(0.45, length, 16), stone, Vector3(0, 0.3, 0), Vector3(0, 0, PI / 2 - 0.08))
	var body := StaticBody3D.new()
	var cs := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 0.45
	shape.height = length
	cs.shape = shape
	cs.transform = col.transform
	body.add_child(cs)
	root.add_child(body)
	_part(root, _cyl(0.6, 0.35, 16), stone, Vector3(-length * 0.5 - 0.1, 0.0, 0), Vector3(0.3, 0, 1.2))

func _chain(top: Vector3, length: float) -> void:
	var iron := _surface("rust")
	var link := _boxm(Vector3(0.05, 0.16, 0.02))
	var n := int(length / 0.13)
	var holder := Node3D.new()
	add_child(holder)
	for i in n:
		_part(holder, link, iron, top + Vector3(0, -0.07 - i * 0.13, 0), Vector3(0, (i % 2) * PI / 2, 0))
	_part(holder, _cyl(0.08, 0.3), iron, top + Vector3(0, -length - 0.1, 0))
	Props.merge(holder)

func _diving_board(pos: Vector3) -> void:
	# Skokanská věž nad vypuštěným bazénem (model diving.glb, naše materiály: beton, sklolaminát, chrom).
	var root := _model_fit("res://assets/props2/diving.glb", 3.05, 1)
	root.position = pos
	root.rotation.y = PI                   # prkno míří nad bazén (+x), žebřík ke zdi
	var concrete := _surface("stone")
	var board := _surface("enamel")
	for m in root.find_children("*", "MeshInstance3D", true, false):
		var mi: MeshInstance3D = m
		var n := String(mi.name)
		var mat: Material = concrete if n.begins_with("body") else (board if n.begins_with("board") else chrome_mat)
		mi.material_override = mat
		if n.begins_with("body") or n.begins_with("board"):
			var body := StaticBody3D.new()
			var cs := CollisionShape3D.new()
			cs.shape = mi.mesh.create_trimesh_shape()
			body.add_child(cs)
			mi.add_child(body)

func _lifeguard_chair(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	var white := _mat(Color(0.92, 0.92, 0.9), 0.5)
	var red := _mat(Color(0.75, 0.12, 0.1), 0.5)
	for leg in [Vector3(-0.35, 0, -0.3), Vector3(0.35, 0, -0.3), Vector3(-0.35, 0, 0.3), Vector3(0.35, 0, 0.3)]:
		_part(root, _cyl(0.035, 2.0), white, leg + Vector3(0, 1.0, 0))
	for y in [0.5, 1.0, 1.5]:
		_part(root, _boxm(Vector3(0.75, 0.04, 0.12)), white, Vector3(0, y, 0.3))
	_part(root, _boxm(Vector3(0.8, 0.06, 0.7)), red, Vector3(0, 2.0, 0))
	_part(root, _boxm(Vector3(0.8, 0.6, 0.06)), red, Vector3(0, 2.3, -0.33))

func _lounger(pos: Vector3) -> void:
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	root.rotation.y = PI / 2
	var plastic := _mat(Color(0.95, 0.93, 0.88), 0.45)
	_part(root, _boxm(Vector3(1.4, 0.05, 0.6)), plastic, Vector3(0.1, 0.32, 0))
	_part(root, _boxm(Vector3(0.6, 0.05, 0.6)), plastic, Vector3(-0.85, 0.55, 0), Vector3(0, 0, -0.6))
	for lx in [-0.5, 0.65]:
		for lz in [-0.25, 0.25]:
			_part(root, _cyl(0.02, 0.32), plastic, Vector3(lx, 0.16, lz))

func _palm(pos: Vector3) -> void:
	# Uschlá palma v květináči.
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	var pot := _mat(Color(0.55, 0.32, 0.2), 0.8)
	var trunk := _mat(Color(0.42, 0.33, 0.22), 0.9)
	var leaf := _mat(Color(0.45, 0.42, 0.22), 0.8)
	leaf.cull_mode = BaseMaterial3D.CULL_DISABLED
	_part(root, _cyl(0.35, 0.6, 16), pot, Vector3(0, 0.3, 0))
	_part(root, _cyl(0.07, 2.2), trunk, Vector3(0, 1.6, 0), Vector3(0.05, 0, 0.04))
	for i in 7:
		var a := TAU * i / 7.0
		var frond := QuadMesh.new()
		frond.size = Vector2(0.35, 1.3)
		_part(root, frond, leaf, Vector3(cos(a) * 0.45, 2.55, sin(a) * 0.45), Vector3(1.1, -a + PI / 2, 0))
	Props.merge(root)

func _chandelier(pos: Vector3) -> void:
	# Kruhový lustr se žárovkami nad bazénem.
	var root := Node3D.new()
	add_child(root)
	root.position = pos
	var brass := _mat(Color(0.7, 0.55, 0.25), 0.35, 0.6)
	_part(root, _cyl(0.02, 2.0), brass, Vector3(0, -1.0, 0))
	var ring := TorusMesh.new()
	ring.inner_radius = 1.1
	ring.outer_radius = 1.16
	_part(root, ring, brass, Vector3(0, -2.0, 0))
	var bulb := _emissive(Color(1.0, 0.75, 0.45), 2.0)
	var sphere := SphereMesh.new()
	sphere.radius = 0.06
	sphere.height = 0.12
	for i in 10:
		var a := TAU * i / 10.0
		_part(root, sphere, bulb, Vector3(cos(a) * 1.13, -1.93, sin(a) * 1.13))
	Props.merge(root)
	var l := OmniLight3D.new()
	l.position = Vector3(0, -2.2, 0)
	l.light_color = Color(1.0, 0.72, 0.45)
	l.light_energy = 0.9
	l.omni_range = 11.0
	l.shadow_enabled = true
	l.distance_fade_enabled = true
	l.distance_fade_begin = 22.0
	l.distance_fade_length = 6.0
	root.add_child(l)

const MAZE := [
	"######.###",
	"#.......##",
	"#.##.##.##",
	"#.##.##...",
	"#....#..#.",
	"####.#.##.",
	"#....#....",
	"#.####.#..",
	"#.#....#.#",
	"#.#.##.#.#",
	"#...#..#.#",
	"###.#.##.#",
	"#...#....#",
	"#.###.####",
	"#.....#...",
	"#.#.#.#.##",
	"#...#...##",
	"##########",
]
const MAZE_X := -33.2
const MAZE_Z := -22.8
const MAZE_CELL := 2.0

func _prop(kind: String, pos: Vector3, yaw: float, collide := true) -> Node3D:
	# Model z assets/props postavený na zem, volitelně s kolizí podle jeho rozměrů.
	var model := Props.make(kind)
	add_child(model)
	model.position = pos
	model.rotation.y = yaw
	for m in model.find_children("*", "MeshInstance3D", true, false):
		(m as MeshInstance3D).visibility_range_end = 45.0
	if collide:
		var b := Props._bounds(model)
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = b.size * 0.92
		cs.shape = shape
		cs.position = b.get_center()
		body.add_child(cs)
		model.add_child(body)
	return model

func _solid(pos: Vector3, size: Vector3, mat: Material, rot := Vector3.ZERO) -> MeshInstance3D:
	# Nábytek: obyčejný materiál a kolize.
	var mi := _part(self, _boxm(size), mat, pos, rot)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.transform = mi.transform
	world_body.add_child(cs)
	return mi

func _collider(center: Vector3, size: Vector3) -> void:
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = size
	cs.shape = bs
	cs.position = center
	world_body.add_child(cs)

func _scatter_blood() -> void:
	# Stará krev po zdech: až po prvním fyzikálním snímku, kdy už existují kolize zdí.
	await get_tree().physics_frame
	await get_tree().physics_frame
	var blood: Node3D = load("res://scripts/blood_dressing.gd").new()
	add_child(blood)
	# Celá mapa po místnostech (vstup, šatny, hala, technická, chodby, síň s andělem, terasy,
	# severní křídlo, les sloupů, bludiště, bufet, tunel, atrium); body mimo podlahu se samy zahodí.
	var rects: Array = MAP_RECTS.duplicate()
	blood.scatter(rects)
	# Zanedbanost: vylomené kachle, praskliny, plíseň, zatečení, kaluže, papíry, trubky, cedule.
	var clutter: Node3D = load("res://scripts/clutter_dressing.gd").new()
	add_child(clutter)
	clutter.dress(rects, world_body, WATER_Y)

func _build_south_wing() -> void:
	# Jih: les sloupů, opuštěný bufet, bludiště chodeb, kulatý tunel a atrium s vodopádem a balkonem.
	# -- les sloupů: nízký strop, hustá mřížka tenkých sloupů, skoro tma
	_palette = {C_WALL: Color(0.8, 0.88, 0.9), C_FLOOR: Color(0.62, 0.78, 0.8), C_CEIL: Color(0.55, 0.62, 0.64), C_BLUE: Color(0.1, 0.3, 0.35)}
	_tile_mul = 1.4
	box(-12.6, 12.6, -1.0, -0.35, -46, -26.6, C_FLOOR)
	water(-12.6, 12.6, -46, -26.6)
	water(-1.2, 1.2, -26.6, -26)
	box(12.6, 13.2, -0.35, 2.9, -46.6, -42)
	box(12.6, 13.2, -0.35, 2.9, -40, -26)
	box(12.6, 13.2, 2.4, 2.9, -42, -40)
	box(-13.2, -4.0, -0.35, 2.9, -46.6, -46)
	box(-2.0, 13.2, -0.35, 2.9, -46.6, -46)
	box(-4.0, -2.0, 2.4, 2.9, -46.6, -46)
	slab_with_holes(-12.6, 12.6, -46.0, -26.6, 2.9, 3.5, [] as Array[Rect2], C_CEIL, 0.5)
	var px := -10.8
	while px < 11.0:
		var pz := -44.2
		while pz < -27.0:
			var near_door := (absf(px) < 1.8 and pz > -29.0) or (px > 10.0 and pz > -43.0 and pz < -39.0) or (px < -10.0 and pz > -39.6 and pz < -36.0) or (px > -4.6 and px < -1.4 and pz < -44.0)
			if not near_door:
				box(px - 0.17, px + 0.17, -0.35, 2.9, pz - 0.17, pz + 0.17)
			pz += 2.4
		px += 2.4
	_lamp(Vector3(-6.0, 2.86, -36.0), 0.15, 0.3, 0.25, 6.0, true)
	_lamp(Vector3(7.0, 2.86, -31.0), 0.15, 0.3, 0.2, 5.0, false)
	# -- bludiště: klasické bílé poolrooms chodby, místy snížený strop
	_palette = {C_WALL: Color(0.95, 0.96, 0.95), C_FLOOR: Color(0.88, 0.93, 0.93), C_CEIL: Color(0.86, 0.88, 0.88)}
	_tile_mul = 2.0
	var mx1: float = MAZE_X + MAZE_CELL * 10
	var mz1: float = MAZE_Z - MAZE_CELL * MAZE.size()
	box(MAZE_X, mx1, -1.0, -0.35, mz1, MAZE_Z, C_FLOOR)
	water(MAZE_X, mx1, mz1, MAZE_Z)
	water(-21.2, -19.2, -22.8, -22.2)
	for r in MAZE.size():
		var row: String = MAZE[r]
		var c := 0
		while c < row.length():
			if row[c] == "#":
				var start := c
				while c < row.length() and row[c] == "#":
					c += 1
				box(MAZE_X + start * MAZE_CELL, MAZE_X + c * MAZE_CELL, -0.35, 3.2, MAZE_Z - (r + 1) * MAZE_CELL, MAZE_Z - r * MAZE_CELL)
			else:
				c += 1
	box(MAZE_X - 0.6, MAZE_X, -1.0, 3.2, mz1 - 0.6, MAZE_Z)
	box(MAZE_X - 0.6, mx1 + 0.6, -1.0, 3.2, mz1 - 0.6, mz1)
	box(mx1, mx1 + 0.6, -1.0, 3.2, -36.8, MAZE_Z)
	box(mx1, mx1 + 0.6, -1.0, 3.2, -50.8, -38.8)
	box(mx1, mx1 + 0.6, -1.0, 3.2, mz1 - 0.6, -52.8)
	box(mx1, mx1 + 0.6, 2.4, 3.2, -38.8, -36.8)
	box(mx1, mx1 + 0.6, 2.4, 3.2, -52.8, -50.8)
	slab_with_holes(MAZE_X - 0.6, mx1 + 0.6, mz1 - 0.6, MAZE_Z, 3.2, 3.8, [] as Array[Rect2], C_CEIL, 0.5)
	box(MAZE_X + 2, MAZE_X + 8, 2.2, 3.2, -45.8, -40.8, C_CEIL)              # snížený strop
	box(MAZE_X + 10, MAZE_X + 18, 2.4, 3.2, -52.8, -50.8, C_CEIL)
	_lamp(Vector3(-25.2, 3.16, -25.8), 0.15, 0.4, 0.3, 6.0, true)
	_lamp(Vector3(-29.2, 3.16, -41.8), 0.15, 0.4, 0.25, 6.0, false)
	_lamp(Vector3(-19.2, 3.16, -55.8), 0.15, 0.4, 0.3, 6.0, true)
	# spojka z bludiště do bufetu a z lesa do bludiště
	box(-12.6, -10.6, -1.0, -0.35, -52.8, -50.8, C_FLOOR)
	box(-12.6, -10.6, -0.35, 3.0, -53.4, -52.8)
	box(-12.6, -10.6, -0.35, 3.0, -50.8, -50.2)
	box(-12.6, -10.6, 2.4, 3.0, -52.8, -50.8)
	water(-12.6, -10.6, -52.8, -50.8)
	# -- opuštěný bufet
	_palette = {C_WALL: Color(0.9, 0.86, 0.72), C_FLOOR: Color(0.55, 0.5, 0.42), C_CEIL: Color(0.75, 0.72, 0.62), C_BLUE: Color(0.6, 0.12, 0.1)}
	_tile_mul = 1.0
	box(-10.0, 4.0, -1.0, -0.35, -58.8, -46.6, C_FLOOR)
	water(-10.0, 4.0, -58.8, -46.6)
	water(-4.0, -2.0, -46.6, -46.0)
	box(-10.6, -10.0, -1.0, 3.0, -59.4, -52.8)
	box(-10.6, -10.0, -1.0, 3.0, -50.8, -46.6)
	# kruhový vstup do tunelu: otvor na celý průměr trubky, rohy zakryje čelní stěna tunelu
	box(4.0, 4.6, -1.0, 3.0, -59.4, -53.55)
	box(4.0, 4.6, -1.0, 3.0, -50.45, -46.6)
	box(4.0, 4.6, 2.3, 3.0, -53.55, -50.45)
	box(-10.6, 4.6, -1.0, 3.0, -59.4, -58.8)
	slab_with_holes(-10.6, 4.6, -59.4, -46.6, 3.0, 3.6, [] as Array[Rect2], C_CEIL, 0.5)
	box(-9.99, 3.99, 1.2, 1.4, -58.79, -58.78, C_BLUE, false)
	var wood := _surface("wood")
	var metal := _surface("steel")
	var counter_top := _surface("laminate")
	# Bufet: skutečné modely pokladny, regálů a automatu.
	# Kolize jen do výšky pultu: celá krabice přes stojan dělala ve 2 m neviditelnou poličku,
	# na které „levitovala“ váza a drobnosti.
	_prop("cashier", Vector3(-3.0, -0.35, -50.6), PI, false)
	_collider(Vector3(-3.0, 0.25, -50.6), Vector3(3.9, 1.2, 1.8))
	for sx in [-8.6, -7.45, -6.3]:
		_prop("shelves", Vector3(sx, -0.35, -54.2), 0.0)
		_prop("shelves", Vector3(sx, -0.35, -56.4), 0.0)
	var fallen := _prop("shelves", Vector3(0.6, -0.1, -54.0), 0.3, false)
	fallen.rotation.x = -1.35
	_collider(Vector3(0.6, -0.1, -54.6), Vector3(1.4, 0.6, 2.2))
	_prop("vending", Vector3(3.5, -0.35, -56.2), -PI / 2)
	_prop("vending", Vector3(3.5, -0.35, -57.5), -PI / 2)
	var goods := [Color(0.85, 0.2, 0.15), Color(0.95, 0.8, 0.2), Color(0.2, 0.5, 0.85), Color(0.3, 0.7, 0.3), Color(0.95, 0.95, 0.9)]
	var goods_mats := []
	for g in goods: goods_mats.append(_mat(g, 0.6))
	for k in 8:
		_part(self, _boxm(Vector3(0.18, 0.22, 0.14)), goods_mats[k % goods_mats.size()], Vector3(-0.2 + k * 0.35, -0.24, -52.6 + randf_range(-0.6, 0.6)), Vector3(randf(), randf() * 3, randf()))
	var prices := Label3D.new()
	prices.text = "ZMRZLINA ....... 12 Kč\nPÁREK V ROHLÍKU 18 Kč\nLIMONÁDA ....... 9 Kč"
	prices.font_size = 32
	prices.pixel_size = 0.004
	prices.modulate = Color(0.25, 0.22, 0.2)
	prices.position = Vector3(3.97, 1.6, -49.0)
	prices.rotation.y = -PI / 2
	add_child(prices)
	_lamp(Vector3(-3.0, 2.96, -52.0), 0.4, 0.15, 0.3, 7.0, true)
	# -- kulatý tunel z bufetu do atria
	_palette = {C_WALL: Color(0.7, 0.82, 0.86)}
	_tile_mul = 1.5
	box(4.0, 13.8, -1.0, -0.35, -53.1, -50.9, C_FLOOR)
	water(4.0, 13.8, -53.35, -50.65)                  # o kousek za stěnu trubky: žádné suché pruhy po stranách
	# Kulatá trubka s vlastním mapováním: dlaždice obíhají dokola (ve stropě se netáhnou)
	# a na obou koncích čelní stěna s kruhovým výřezem zakryje zbytek obdélníkového otvoru.
	var tunnel := MeshInstance3D.new()
	tunnel.mesh = _tube_mesh(TUNNEL_R, 4.0, 13.8, 64)
	tunnel.material_override = tile_mat
	tunnel.set_instance_shader_parameter("tint", Color(0.7, 0.82, 0.86))
	tunnel.set_instance_shader_parameter("tile_scale", 1.5)
	tunnel.set_instance_shader_parameter("mesh_uv", 1.0)
	tunnel.position = Vector3(0.0, TUNNEL_Y, -52.0)
	add_child(tunnel)
	# Čelní stěny přímo v líci zdí místností (dlaždice navazují): ve zdi je jen kulatý otvor.
	# [x, barva a měřítko dlaždic zdi té místnosti]: Bufet, Atrium
	for end in [[3.995, Color(0.9, 0.86, 0.72), 1.0], [13.805, Color(0.88, 0.9, 0.86), 0.8]]:
		var end_x: float = end[0]
		var cap := MeshInstance3D.new()
		cap.mesh = _tube_cap(TUNNEL_R, 1.57, -0.36 - TUNNEL_Y, 2.33 - TUNNEL_Y, 64)
		cap.material_override = tile_mat
		cap.set_instance_shader_parameter("tint", end[1])
		cap.set_instance_shader_parameter("tile_scale", end[2])
		cap.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF   # oboustranná plocha by stínila sama sebe (tmavý obdélník)
		cap.position = Vector3(end_x, TUNNEL_Y, -52.0)
		add_child(cap)
	_collider(Vector3(8.9, 0.8, -53.15), Vector3(9.8, 2.4, 0.3))
	_collider(Vector3(8.9, 0.8, -50.85), Vector3(9.8, 2.4, 0.3))
	_collider(Vector3(8.9, 2.25, -52.0), Vector3(9.8, 0.3, 2.6))
	_lamp(Vector3(8.9, TUNNEL_Y + TUNNEL_R - 0.06, -52.0), 0.12, 0.3, 0.2, 4.0, true)
	# -- atrium: vysoký sál s vodopádem, schody na balkon a oknem na anděla
	_palette = {C_WALL: Color(0.88, 0.9, 0.86), C_FLOOR: Color(0.8, 0.84, 0.8), C_CEIL: Color(0.6, 0.64, 0.62), C_BLUE: Color(0.18, 0.4, 0.3)}
	_tile_mul = 0.8
	box(13.8, 30.0, -1.0, -0.35, -56.0, -34.6, C_FLOOR)
	water(13.2, 30.0, -56.0, -34.0)
	water(12.6, 13.8, -42.0, -40.0)
	box(13.2, 13.8, -1.0, 12.0, -56.6, -53.55)
	box(13.2, 13.8, -1.0, 12.0, -50.45, -42.0)
	box(13.2, 13.8, -1.0, 12.0, -40.0, -34.6)
	box(13.2, 13.8, 2.3, 12.0, -53.55, -50.45)
	box(13.2, 13.8, 2.4, 12.0, -42.0, -40.0)
	box(30.0, 30.6, -1.0, 12.0, -56.6, -34.6)
	box(13.2, 30.6, -1.0, 12.0, -56.6, -56.0)
	box(13.2, 20.0, -1.0, 12.0, -34.6, -34.0)
	slab_with_holes(13.2, 30.6, -56.6, -34.6, 12.0, 12.6, [Rect2(19.0, -50.0, 4.0, 4.0)] as Array[Rect2], C_CEIL, 0.5)
	box(13.81, 29.99, 1.2, 1.4, -55.99, -55.98, C_BLUE, false)
	# balkon a schody podél východní zdi
	box(13.8, 30.0, 3.75, 4.15, -40.0, -34.6, C_FLOOR)
	_steps(27.0, 30.0, -52.0, -40.0, -0.35, 4.15, 22)
	box(13.8, 27.0, 4.15, 5.1, -40.1, -40.0, C_BLUE)                                  # zábradlí
	_solid(Vector3(28.0, 4.6, -34.3), Vector3(4.0, 0.9, 0.1), metal)                   # zábradlí v okně
	# vodopád ze zdi
	var outlet := box(19.0, 25.0, 10.2, 10.8, -56.0, -55.2, C_BLUE)
	var fall := MeshInstance3D.new()
	var fq := QuadMesh.new()
	fq.size = Vector2(5.6, 10.6)
	fall.mesh = fq
	var fall_mat := ShaderMaterial.new()
	fall_mat.shader = load("res://assets/props/waterfall.gdshader")
	fall.material_override = fall_mat
	fall.position = Vector3(22.0, 4.95, -55.6)
	fall.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(fall)
	var foam := MeshInstance3D.new()
	var fm := QuadMesh.new()
	fm.size = Vector2(6.4, 1.6)
	foam.mesh = fm
	var foam_mat: ShaderMaterial = fall_mat.duplicate()
	foam_mat.set_shader_parameter("speed", 0.4)
	foam.material_override = foam_mat
	foam.position = Vector3(22.0, 0.03, -54.9)
	foam.rotation.x = -PI / 2
	add_child(foam)
	var roar := AudioStreamPlayer3D.new()
	if ResourceLoader.exists("res://audio/amb_water.wav"):
		roar.stream = load("res://audio/amb_water.wav")
	roar.volume_db = 4.0
	roar.unit_size = 6.0
	roar.max_distance = 30.0
	roar.autoplay = true
	roar.position = Vector3(22.0, 1.0, -55.0)
	add_child(roar)
	var cold := OmniLight3D.new()
	cold.light_color = Color(0.6, 0.85, 1.0)
	cold.light_energy = 0.8
	cold.omni_range = 9.0
	cold.position = Vector3(22.0, 9.0, -54.0)
	cold.distance_fade_enabled = true
	cold.distance_fade_begin = 24.0
	add_child(cold)
	_lamp(Vector3(16.0, 11.96, -45.0), 0.3, 0.6, 0.8, 16.0, true)
	_bench(Vector3(17.0, -0.35, -36.0), 2.4, 0.0)
	_palette = {}
	_tile_mul = 1.0

func _build_north_wing() -> void:
	# Terasy (schody nahoru, vypuštěný bazén), stoupající a klesající chodba, kulatá síň s hlubokým bazénem.
	# -- terasy: lososové sedmdesátkové dlaždice, mátový vypuštěný bazén, skokanský můstek a plavčík
	_palette = {C_WALL: Color(0.86, 0.6, 0.54), C_FLOOR: Color(0.92, 0.8, 0.72), C_CEIL: Color(0.8, 0.62, 0.56), C_POOL: Color(0.6, 0.86, 0.74), C_BLUE: Color(0.85, 0.42, 0.14)}
	_tile_mul = 0.7
	box(24, 42, -1.0, -0.35, -1.4, 4, C_FLOOR)
	water(24, 42, -1.4, 5.2)
	water(32, 35, -2, -1.4)
	_steps(24, 42, 4, 9, -0.35, 1.45, 9)
	box(24, 42, 1.0, 1.45, 9, 11, C_FLOOR)
	box(24, 42, 1.0, 1.45, 15.5, 17, C_FLOOR)
	box(24, 28, 1.0, 1.45, 11, 15.5, C_FLOOR)
	box(36, 42, 1.0, 1.45, 11, 15.5, C_FLOOR)
	box(28, 36, 0.0, 0.3, 11, 15.5, C_POOL, true, 2.0)                       # vypuštěný bazén
	box(27.7, 28, 0.3, 1.0, 11, 15.5, C_POOL, true, 2.0)
	box(36, 36.3, 0.3, 1.0, 11, 15.5, C_POOL, true, 2.0)
	box(28, 36, 0.3, 1.0, 10.7, 11, C_POOL, true, 2.0)
	box(28, 36, 0.3, 1.0, 15.5, 15.8, C_POOL, true, 2.0)
	_steps(29.6, 28.0, 11.2, 12.8, 1.45, 0.32, 4, true)                      # schůdky dolů do bazénu
	box(23.4, 24, -1.0, 7.5, -1.4, 17.6)
	box(42, 42.6, -1.0, 7.5, -1.4, 12)
	box(42, 42.6, -1.0, 7.5, 14, 17.6)
	box(42, 42.6, -1.0, 1.45, 12, 14)
	box(42, 42.6, 3.8, 7.5, 12, 14)
	box(23.4, 38, -1.0, 7.5, 17, 17.6)
	box(40, 42.6, -1.0, 7.5, 17, 17.6)
	box(38, 40, 3.85, 7.5, 17, 17.6)                         # průchod do zadní chodby (okruh)
	box(38, 40, -1.0, 1.45, 17, 17.6, C_FLOOR)
	slab_with_holes(23.4, 42.6, -1.4, 17.6, 7.5, 8.1, [Rect2(30, 11.5, 4, 3.5)] as Array[Rect2], C_CEIL, 0.5)
	for cz in [10.0, 13.0, 16.0]:
		for cx in [25.2, 40.8]:
			box(cx - 0.3, cx + 0.3, 1.45, 7.5, cz - 0.3, cz + 0.3)
	box(24.01, 32.0, 1.2, 1.4, -1.39, -1.38, C_BLUE, false)
	box(35.0, 41.99, 1.2, 1.4, -1.39, -1.38, C_BLUE, false)
	_bench(Vector3(26.0, -0.35, 2.0), 2.4, PI / 2)
	_diving_board(Vector3(26.7, 1.45, 13.25))
	_prop("lifeguard", Vector3(37.6, 1.45, 13.0), -PI / 2)
	for lx in [25.4, 41.0]:
		_prop("lounger", Vector3(lx, 1.45, 16.3), PI / 2)
	# -- chodba: zažloutlé hořčicové dlaždice, potrubí pod stropem
	_palette = {C_WALL: Color(0.78, 0.68, 0.38), C_FLOOR: Color(0.62, 0.55, 0.36), C_CEIL: Color(0.55, 0.5, 0.36), C_BLUE: Color(0.3, 0.2, 0.08)}
	_tile_mul = 1.6
	# -- chodba: schody nahoru, odbočka a dlouhé schodiště dolů do vody
	box(42.6, 52, -1.0, 1.45, 12, 14, C_FLOOR)
	_steps(46, 49.2, 12, 14, 1.45, 2.45, 5, true)
	box(49.2, 52, -1.0, 2.45, 12, 14, C_FLOOR)
	box(42.6, 52.6, -1.0, 5.0, 11.4, 12)
	box(42.6, 50, -1.0, 5.0, 14, 14.6)
	box(52, 52.6, -1.0, 5.0, 11.4, 23.4)
	box(49.4, 50, -1.0, 5.0, 14.6, 23.4)
	_steps(50, 52, 14, 24, 2.45, -0.35, 14)
	water(50, 52, 21, 24)
	slab_with_holes(42.6, 52.6, 11.4, 23.4, 5.0, 5.6, [] as Array[Rect2], C_CEIL, 0.5)
	for off in [0.0, 0.22]:
		var pipe: Array[Vector3] = [Vector3(42.8, 4.7 - off, 13.6), Vector3(51.6 - off, 4.7 - off, 13.6), Vector3(51.6 - off, 4.7 - off, 23.8)]
		tube(pipe, 0.07, chrome_mat)
	# -- kulatá síň: hluboce modrá mozaika, zkosené rohy, lustr nad bazénem
	_palette = {C_WALL: Color(0.25, 0.4, 0.72), C_FLOOR: Color(0.78, 0.86, 0.95), C_CEIL: Color(0.16, 0.22, 0.4), C_POOL: Color(0.2, 0.36, 0.8), C_BLUE: Color(0.85, 0.68, 0.25)}
	_tile_mul = 2.6
	# -- kulatá síň
	var pool := Rect2(50, 28, 8, 8)
	box(46, 62, -1.0, -0.35, 24, pool.position.y - 0.6, C_FLOOR)
	box(46, 62, -1.0, -0.35, pool.end.y + 0.6, 40, C_FLOOR)
	box(46, pool.position.x - 0.6, -1.0, -0.35, pool.position.y - 0.6, pool.end.y + 0.6, C_FLOOR)
	box(pool.end.x + 0.6, 62, -1.0, -0.35, pool.position.y - 0.6, pool.end.y + 0.6, C_FLOOR)
	box(pool.position.x - 0.6, pool.end.x + 0.6, -3.6, -3.0, pool.position.y - 0.6, pool.end.y + 0.6, C_POOL, true, 2.0)
	box(pool.position.x - 0.6, pool.position.x, -3.0, -0.35, pool.position.y, pool.end.y, C_POOL, true, 2.0)
	box(pool.end.x, pool.end.x + 0.6, -3.0, -0.35, pool.position.y, pool.end.y, C_POOL, true, 2.0)
	box(pool.position.x - 0.6, pool.end.x + 0.6, -3.0, -0.35, pool.position.y - 0.6, pool.position.y, C_POOL, true, 2.0)
	box(pool.position.x - 0.6, pool.end.x + 0.6, -3.0, -0.35, pool.end.y, pool.end.y + 0.6, C_POOL, true, 2.0)
	box(pool.position.x - 0.8, pool.end.x + 0.8, -0.36, -0.342, pool.position.y - 0.8, pool.position.y - 0.6, C_BLUE, false)
	box(pool.position.x - 0.8, pool.end.x + 0.8, -0.36, -0.342, pool.end.y + 0.6, pool.end.y + 0.8, C_BLUE, false)
	water(46, 62, 24, 40)
	box(45.4, 46, -1.0, 7.0, 23.4, 26)
	box(45.4, 46, -1.0, 7.0, 28, 40.6)
	box(45.4, 46, 2.6, 7.0, 26, 28)
	box(62, 62.6, -1.0, 7.0, 23.4, 40.6)
	box(45.4, 62.6, -1.0, 7.0, 40, 40.6)
	box(45.4, 50, -1.0, 7.0, 23.4, 24)
	box(52, 62.6, -1.0, 7.0, 23.4, 24)
	box(50, 52, 2.6, 7.0, 23.4, 24)
	slab_with_holes(45.4, 62.6, 23.4, 40.6, 6.4, 7.0, [Rect2(52, 30, 4, 4)] as Array[Rect2], C_CEIL, 0.5)
	for c in [Vector2(47.6, 26.0), Vector2(60.4, 26.0), Vector2(47.6, 38.0), Vector2(60.4, 38.0)]:
		box(c.x - 0.4, c.x + 0.4, -0.35, 6.4, c.y - 0.4, c.y + 0.4)
	_bench(Vector3(54.0, -0.35, 38.9), 3.0, 0.0)
	for corner in [Vector3(46.0, 0, 24.0), Vector3(62.0, 0, 24.0), Vector3(46.0, 0, 40.0), Vector3(62.0, 0, 40.0)]:
		_rbox(Vector3(corner.x, 3.0, corner.z), Vector3(4.6, 8.0, 0.6), PI / 4 if (corner.x < 50) == (corner.z < 30) else -PI / 4, C_WALL)
	_chandelier(Vector3(54.0, 6.4, 32.0))
	_prop("vending", Vector3(61.4, -0.35, 33.0), -PI / 2)
	# -- zadní chodba (kotelna): z kulaté síně zpátky nahoru na terasy, takže se dá běhat dokola
	_palette = {C_WALL: Color(0.56, 0.3, 0.26), C_FLOOR: Color(0.46, 0.32, 0.28), C_CEIL: Color(0.32, 0.22, 0.2), C_BLUE: Color(0.15, 0.1, 0.08)}
	_tile_mul = 1.3
	box(38, 40, -1.0, 1.45, 17.6, 19, C_FLOOR)
	_steps(38, 40, 19, 25, 1.45, -0.35, 9)
	box(38, 45.4, -1.0, -0.35, 25, 28, C_FLOOR)
	box(45.4, 46, -1.0, -0.35, 26, 28, C_FLOOR)
	box(37.4, 38, -1.0, 4.2, 17.6, 28.6)
	box(40, 40.6, -1.0, 4.2, 17.6, 25.4)
	box(40, 45.4, -1.0, 4.2, 25.4, 26)
	box(37.4, 45.4, -1.0, 4.2, 28, 28.6)
	slab_with_holes(37.4, 45.4, 17.6, 28.6, 4.2, 4.8, [] as Array[Rect2], C_CEIL, 0.5)
	water(38, 45.4, 24.0, 28)
	water(45.4, 46, 26, 28)
	tube([Vector3(38.3, 3.9, 17.8), Vector3(38.3, 3.9, 27.6), Vector3(45.2, 3.9, 27.6)] as Array[Vector3], 0.09, chrome_mat)
	_lamp(Vector3(39.0, 4.16, 21.5), 0.2, 0.4, 0.35, 5.5, true)
	_lamp(Vector3(43.0, 4.16, 27.0), 0.2, 0.4, 0.3, 5.0, false)
	_palette = {}
	_tile_mul = 1.0
	_lamp(Vector3(33.0, 7.46, 4.0), 0.22, 0.5, 0.5, 9.0, true)
	_lamp(Vector3(47.0, 4.96, 13.0), 0.2, 0.4, 0.35, 5.0, true)
	_lamp(Vector3(51.0, 4.96, 19.0), 0.2, 0.4, 0.3, 5.0, false)
	_lamp(Vector3(48.5, 6.36, 32.0), 0.25, 0.5, 0.5, 9.0, true)

# =============================================================== světla
func _lamp(pos: Vector3, sx: float, sz: float, energy: float, rng: float, flicker := false) -> void:
	var m := _emissive(Color(1.0, 0.66, 0.3), 1.1)
	box(pos.x - sx, pos.x + sx, pos.y - 0.04, pos.y, pos.z - sz, pos.z + sz, C_WALL, false, 1.0, m)
	var l := OmniLight3D.new()
	l.position = pos + Vector3(0, -0.3, 0)
	l.light_color = Color(1.0, 0.68, 0.34)
	l.light_energy = energy
	l.omni_range = rng
	l.omni_attenuation = 1.2
	l.shadow_enabled = true
	l.shadow_blur = 2.0
	l.light_size = 0.12
	l.light_volumetric_fog_energy = 0.0
	l.light_specular = 0.35
	# Vzdálené lampy se nepočítají (ani jejich stíny).
	l.distance_fade_enabled = true
	l.distance_fade_begin = 22.0
	l.distance_fade_shadow = 12.0
	l.distance_fade_length = 6.0
	add_child(l)
	lamps.append({"light": l, "mat": m, "energy": energy, "flicker": flicker, "on": 1.0, "timer": 2.0, "seq": 0})

func _build_lights() -> void:
	sun = DirectionalLight3D.new()
	var dir := sun_dir
	add_child(sun)
	sun.look_at_from_position(Vector3.ZERO, dir, Vector3.RIGHT)
	# Noc: světlíky propouštějí jen slabé měsíční světlo.
	sun.light_color = Color(0.45, 0.55, 0.85)
	sun.light_energy = 0.035
	sun.light_angular_distance = 0.7
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 45.0
	sun.directional_shadow_blend_splits = true
	sun.shadow_bias = 0.03
	sun.shadow_normal_bias = 1.2
	sun.light_volumetric_fog_energy = 4.0
	tile_mat.set_shader_parameter("sun_slope", Vector2(dir.x, dir.z) / -dir.y)

	# jediná umělá lampa v demu: skomírající zářivka u průlezu
	_lamp(Vector3(-21.6, 2.6, -21), 0.22, 0.5, 0.45, 7.0, true)
	# Pár skomírajících světel jako ostrůvky ve tmě; zbytek ukáže jen svítilna.
	# Elektřina vypadla; proud teče už jen na třech místech.
	_lamp(Vector3(6.5, 2.96, 5.2), 0.2, 0.5, 0.3, 5.5, true)
	_lamp(Vector3(9.6, 8.96, -23.0), 0.25, 0.6, 0.7, 9.0, true)
	var alarm := OmniLight3D.new()
	alarm.position = Vector3(-17.5, 2.5, -12.2)
	alarm.light_color = Color(1.0, 0.12, 0.08)
	alarm.light_energy = 0.35
	alarm.omni_range = 6.0
	alarm.shadow_enabled = true
	add_child(alarm)

	# podvodní světla ve stěnách bazénu
	for z in [-11.0, -17.0]:
		for sx in [-1.0, 1.0]:
			var x: float = sx * 5.97
			var mi := MeshInstance3D.new()
			var cm := CylinderMesh.new()
			cm.top_radius = 0.16
			cm.bottom_radius = 0.16
			cm.height = 0.03
			mi.mesh = cm
			mi.rotation.z = PI * 0.5
			mi.position = Vector3(x, -1.45, z)
			mi.material_override = _emissive(Color(0.55, 0.75, 0.5), 0.9)
			add_child(mi)
			var l := OmniLight3D.new()
			l.position = Vector3(x - sx * 0.35, -1.45, z)
			l.light_color = Color(0.6, 1.0, 0.92)
			l.light_energy = 0.07
			l.omni_range = 4.0
			l.omni_attenuation = 1.4
			l.light_specular = 0.2
			l.light_volumetric_fog_energy = 0.0
			add_child(l)
	var tl := OmniLight3D.new()
	tl.position = Vector3(-30.7, 0.15, -21.0)
	tl.light_color = Color(0.5, 0.85, 1.0)
	tl.light_energy = 0.12
	tl.omni_range = 6.0
	add_child(tl)

	# sondy odrazů (lesk dlaždic mimo dosah SSR)
	_probe(Vector3(0, 2.6, -13.9), Vector3(24, 6.2, 24.2))
	_probe(Vector3(0, 1.7, 4.4), Vector3(4, 2.7, 11.2))
	_probe(Vector3(-18.3, 1.1, -21), Vector3(11.4, 3.0, 2.4))

func _probe(pos: Vector3, size: Vector3) -> void:
	var rp := ReflectionProbe.new()
	rp.position = pos
	rp.size = size
	rp.box_projection = true
	rp.interior = false
	rp.enable_shadows = true
	rp.update_mode = ReflectionProbe.UPDATE_ONCE
	rp.max_distance = 60.0
	rp.cull_mask = 1
	rp.ambient_mode = ReflectionProbe.AMBIENT_DISABLED
	add_child(rp)

# =============================================================== prostředí a postproces
func _build_environment() -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.012, 0.018, 0.04)
	sky_mat.sky_horizon_color = Color(0.04, 0.055, 0.09)
	sky_mat.ground_bottom_color = Color(0.01, 0.012, 0.02)
	sky_mat.ground_horizon_color = Color(0.04, 0.055, 0.09)
	sky_mat.sky_energy_multiplier = 0.03
	sky_mat.sun_angle_max = 0.0
	var sky := Sky.new()
	sky.sky_material = sky_mat

	env = Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_SKY
	env.ambient_light_energy = 0.0
	env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	env.tonemap_mode = Environment.TONE_MAPPER_ACES
	env.tonemap_white = 6.0
	env.tonemap_exposure = 1.0
	# globální osvětlení v reálném čase
	env.sdfgi_enabled = true
	env.sdfgi_use_occlusion = true
	env.sdfgi_read_sky_light = true
	env.sdfgi_bounce_feedback = 0.6
	env.sdfgi_cascades = 4
	env.sdfgi_min_cell_size = 0.2
	env.sdfgi_y_scale = Environment.SDFGI_Y_SCALE_75_PERCENT
	env.sdfgi_energy = 0.35
	# odrazy v prostoru obrazovky (lesklé dlaždice)
	env.ssr_enabled = true
	env.ssr_max_steps = 64
	env.ssr_fade_in = 0.15
	env.ssr_fade_out = 1.2
	# Malá tolerance: odraz se nebere z objektů, které jsou ve skutečnosti za jinými (jinak vznikaly
	# zdvojené „zrcadlové“ obrysy zombie a jiskřící tečky na tmavých stěnách).
	env.ssr_depth_tolerance = 0.06
	# ambient occlusion + nepřímé světlo v prostoru obrazovky
	env.ssao_enabled = true
	env.ssao_radius = 1.1
	env.ssao_intensity = 2.2
	env.ssao_power = 1.6
	env.ssao_detail = 0.6
	env.ssao_light_affect = 0.15
	env.ssil_enabled = true
	env.ssil_radius = 5.0
	env.ssil_intensity = 1.0
	# bloom
	env.glow_enabled = true
	env.glow_intensity = 0.24
	env.glow_strength = 1.0
	env.glow_bloom = 0.0
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SCREEN
	env.glow_hdr_threshold = 1.8
	env.glow_hdr_luminance_cap = 10.0
	env.glow_hdr_scale = 1.6
	for i in 7:
		env.set_glow_level(i, [0.0, 0.5, 1.0, 0.7, 0.35, 0.0, 0.0][i])
	# volumetrická mlha = viditelné kužely světla ze světlíků
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = 0.012
	env.volumetric_fog_albedo = Color(0.62, 0.58, 0.5)
	# Temná voda: rychle pohlcuje světlo, dno hlubokého bazénu se ztrácí v černi.
	# Voda zkalená krví: zelenou a modrou pohlcuje víc než červenou -> načervenale černá.
	water_mat.set_shader_parameter("absorb", Vector3(0.75, 1.45, 1.5))
	water_mat.set_shader_parameter("scatter_color", Color(0.08, 0.012, 0.01))
	water_mat.set_shader_parameter("scatter_energy", 0.08)
	water_mat.set_shader_parameter("fallback_refl", Color(0.03, 0.04, 0.05))
	env.volumetric_fog_anisotropy = 0.25
	env.volumetric_fog_length = 42.0
	env.volumetric_fog_detail_spread = 1.4
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_ambient_inject = 0.0
	env.volumetric_fog_temporal_reprojection_enabled = true
	env.volumetric_fog_temporal_reprojection_amount = 0.85
	_build_light_shafts()
	env.adjustment_enabled = true
	env.adjustment_contrast = 1.08
	env.adjustment_saturation = 1.08
	var we := WorldEnvironment.new()
	we.environment = env
	add_child(we)

	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = 16.0
	cam_attr.dof_blur_far_transition = 26.0
	cam_attr.dof_blur_near_enabled = true
	cam_attr.dof_blur_near_distance = 0.28
	cam_attr.dof_blur_near_transition = 0.25
	cam_attr.dof_blur_amount = 0.055
	cam_attr.auto_exposure_enabled = false
	cam_attr.auto_exposure_scale = 0.26
	cam_attr.auto_exposure_speed = 0.6
	cam_attr.auto_exposure_min_sensitivity = 70.0
	cam_attr.auto_exposure_max_sensitivity = 150.0

	# prostředí zrcadlové kamery: stejné světlo, bez efektů v prostoru obrazovky
	refl_env = env.duplicate()
	refl_env.ssr_enabled = false
	refl_env.ssao_enabled = false
	refl_env.ssil_enabled = false
	refl_env.glow_enabled = false
	refl_env.volumetric_fog_enabled = false
	refl_env.adjustment_enabled = false
	refl_env.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	refl_env.tonemap_exposure = 1.0
	# SDFGI by se pro zrcadlovou kameru počítalo podruhé (vlastní kaskády) – v odrazu ho nahradí slabé ambientní světlo.
	refl_env.sdfgi_enabled = false
	refl_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	refl_env.ambient_light_color = Color(0.55, 0.42, 0.3)
	refl_env.ambient_light_energy = 0.06

func _build_light_shafts() -> void:
	# Šikmé objemy jen pod světlíky. Stíny rámů i sloupů dál počítá slunce.
	var shader: Shader = load("res://shaders/light_shaft.gdshader")
	var slope := Vector2(sun_dir.x, sun_dir.z) / -sun_dir.y
	for sk in skylights:
		var r: Rect2 = sk.rect
		var bottom: float = sk.floor
		var top: float = sk.top
		var height := top - bottom
		var shaft := FogVolume.new()
		shaft.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
		shaft.size = Vector3(r.size.x + absf(slope.x) * height + 0.5, height, r.size.y + absf(slope.y) * height + 0.5)
		shaft.position = Vector3(r.get_center().x + slope.x * height * 0.5, (top + bottom) * 0.5, r.get_center().y + slope.y * height * 0.5)
		var mat := ShaderMaterial.new()
		mat.shader = shader
		mat.set_shader_parameter("aperture", Vector4(r.position.x, r.position.y, r.end.x, r.end.y))
		mat.set_shader_parameter("sun_slope", slope)
		mat.set_shader_parameter("top_y", top)
		mat.set_shader_parameter("bottom_y", bottom)
		shaft.material = mat
		add_child(shaft)
		light_shafts.append(shaft)

func _setup_sim() -> void:
	sim = WaterSim.new()
	if not water_rects.is_empty():
		var area := water_rects[0]
		for r in water_rects: area = area.merge(r)
		sim.fit(area)
	add_child(sim)
	var n := sim.res
	var img := Image.create(n, n, false, Image.FORMAT_R8)
	img.fill(Color(0, 0, 0))
	var to_px := func(v: float, o: float) -> int: return int(round((v - o) / sim.size * n))
	for r in water_rects:
		var x0: int = to_px.call(r.position.x, sim.origin.x)
		var z0: int = to_px.call(r.position.y, sim.origin.y)
		var x1: int = to_px.call(r.end.x, sim.origin.x)
		var z1: int = to_px.call(r.end.y, sim.origin.y)
		img.fill_rect(Rect2i(x0, z0, x1 - x0, z1 - z0), Color(1, 1, 1))
	for a in solids:
		if a.position.y < WATER_Y - 0.01 and a.end.y > WATER_Y + 0.01:
			var x0: int = to_px.call(a.position.x, sim.origin.x)
			var z0: int = to_px.call(a.position.z, sim.origin.y)
			var x1: int = to_px.call(a.end.x, sim.origin.x)
			var z1: int = to_px.call(a.end.z, sim.origin.y)
			img.fill_rect(Rect2i(x0, z0, x1 - x0, z1 - z0).intersection(Rect2i(0, 0, n, n)), Color(0, 0, 0))
	sim.setup(img)
	for m in [tile_mat, water_mat]:
		m.set_shader_parameter("sim_tex", sim.texture)
		m.set_shader_parameter("sim_origin", sim.origin)
		m.set_shader_parameter("sim_size", sim.size)
		m.set_shader_parameter("sim_res", float(n))

func _spawn_player() -> void:
	player = Player.new()
	player.sim = sim
	add_child(player)
	player.teleport(SPAWN, 0.0, -0.03)
	player.camera.attributes = cam_attr
	player.footstep.connect(_on_footstep)
	player.splashed.connect(_on_splash)
	player.weapon.fired.connect(_weapon_fired)
	player.weapon.melee_hit.connect(_melee)
	# Svítilna na zbrani (F): jediný spolehlivý zdroj světla.
	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0.16, -0.14, -0.15)
	flashlight.light_color = Color(1.0, 0.86, 0.62)
	flashlight.light_energy = 9.0
	flashlight.spot_range = 30.0
	flashlight.spot_angle = 36.0
	# Skutečná baterka: horký střed s měkkým přechodem (silná atenuace k okraji kužele)…
	flashlight.spot_angle_attenuation = 3.5
	flashlight.spot_attenuation = 0.9
	flashlight.shadow_enabled = true
	flashlight.shadow_blur = 1.5
	# Vlastní tělo a zbraň (vrstvy 4 a 8) stín od svítilny nevrhají.
	flashlight.shadow_caster_mask = 0xFFFFF & ~(4 | 8)
	flashlight.light_volumetric_fog_energy = 0.9
	flashlight.light_specular = 0.6
	flashlight.visible = false
	player.camera.add_child(flashlight)
	# …a slabý široký rozptyl kolem (odlesk reflektoru), bez stínů. Zapíná se a bliká s baterkou.
	_flash_spill = SpotLight3D.new()
	_flash_spill.light_color = Color(1.0, 0.86, 0.62)
	_flash_spill.spot_range = 18.0
	_flash_spill.spot_angle = 62.0
	_flash_spill.spot_angle_attenuation = 1.5
	_flash_spill.spot_attenuation = 1.2
	_flash_spill.shadow_enabled = false
	_flash_spill.light_specular = 0.2
	_flash_spill.light_volumetric_fog_energy = 0.3
	flashlight.add_child(_flash_spill)
	_build_flash_dust()
	player.collision_mask = 1 | 128      # zombie jsou pro hráče pevná překážka
	player.interact_requested.connect(_try_pickup)

# =============================================================== multiplayer
func _setup_network() -> void:
	_remote_root = Node3D.new()
	_remote_root.name = "RemotePlayers"
	add_child(_remote_root)
	network = NetScript.new()
	network.name = "NetworkSession"
	add_child(network)
	network.local_state = _network_state
	network.started.connect(_network_started)
	network.closed.connect(_network_closed)
	network.status_changed.connect(func(_message: String): _update_network_ui())
	network.roster_changed.connect(_update_network_ui)
	network.remote_joined.connect(_remote_joined)
	network.remote_left.connect(_remote_left)
	network.state_received.connect(_remote_state)
	network.action_received.connect(_remote_action)
	network.water_received.connect(func(points: Array):
		for point in points:
			sim.apply_network_impulse(Vector2(point.x, point.y), point.z, point.w))
	network.pickup_requested.connect(_network_pickup_request)
	network.sample_changed.connect(_network_sample_changed)
	network.look_received.connect(func(id: int, look: Array):
		if remote_players.has(id): remote_players[id].body.apply_look(look))
	player.body.action_started.connect(network.send_action)
	sim.impulse_added.connect(network.queue_water)
	menu.host_pressed.connect(func(nick: String, port: int, automatic: bool):
		network.host_game(nick, port, automatic)
		_update_network_ui())
	menu.join_pressed.connect(func(nick: String, address: String, port: int):
		network.join_game(nick, address, port)
		_update_network_ui())
	menu.disconnect_pressed.connect(func():
		network.leave("Odpojeno od společné hry.")
		_network_closed("Odpojeno od společné hry."))
	menu.copy_connection_pressed.connect(func():
		DisplayServer.clipboard_set(network.connection_text())
		toast("Adresy zkopírovány"))

func _network_state(sequence: int) -> Array:
	var flags := 0
	if player.crouching: flags |= NetScript.FLAG_CROUCH
	if player.swimming: flags |= NetScript.FLAG_SWIM
	if player.body.using_sprint_strafe: flags |= NetScript.FLAG_STRAFE
	if player.third_person and not player.weapon.aiming: flags |= NetScript.FLAG_ORBIT
	if player.weapon.equipped: flags |= NetScript.FLAG_ARMED
	if player.weapon.aiming: flags |= NetScript.FLAG_AIM
	if player.weapon.examining: flags |= NetScript.FLAG_INSPECT
	if player.is_on_floor() and not player.swimming: flags |= NetScript.FLAG_GROUNDED
	return [sequence, player.global_position, player.velocity, wrapf(player.yaw, -PI, PI), player.pitch, flags, wrapf(player.body.body_yaw, -PI, PI), Time.get_ticks_msec()]

func _network_started(slot: int) -> void:
	get_tree().paused = false
	network.set_local_look(current_look())
	if _intro_fade and _intro_fade.is_valid(): _intro_fade.kill()
	_fade_rect.color.a = 0.0
	_end_label.modulate.a = 0.0
	_ending = false
	sfx.fade = 1.0
	_reset_pickup()
	var offsets := [Vector3.ZERO, Vector3(0.8, 0, -1.4), Vector3(-0.8, 0, -1.4), Vector3(0, 0, -2.8)]
	player.teleport(SPAWN + offsets[clampi(slot, 0, 3)], 0.0 if slot == 0 else PI, -0.03)
	player.input_suspended = false
	player.control_enabled = true
	menu.close()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_help_t = 12.0
	_update_network_ui()
	toast("Server založen" if multiplayer.is_server() else "Připojeno ke společné hře")

func _network_closed(_message: String) -> void:
	get_tree().paused = false
	player.input_suspended = false
	_clear_remote_players()
	_reset_pickup()
	_open_main_menu()
	menu._show_multiplayer(true)
	_update_network_ui()

func _clear_remote_players() -> void:
	for remote in remote_players.values(): remote.queue_free()
	remote_players.clear()

func _remote_joined(id: int, nick: String) -> void:
	if remote_players.has(id): return
	var remote := RemoteScript.new()
	remote.name = "Peer_%d" % id
	_remote_root.add_child(remote)
	remote.set_display_name(nick)
	remote_players[id] = remote
	if network.looks.has(id): remote.body.apply_look(network.looks[id])
	toast(nick + " se připojil")
	if network.active and multiplayer.is_server() and zombie.dead:
		_zombie_killed.rpc_id(id,zombie.global_position+Vector3.UP,Vector3.ZERO,zombie.skeleton.find_bone("mixamorig_Hips"))

func _remote_left(id: int) -> void:
	if remote_players.has(id):
		remote_players[id].queue_free()
		remote_players.erase(id)

func _remote_state(id: int, state: Array) -> void:
	if remote_players.has(id): remote_players[id].push_state(state)

func _remote_action(id: int, kind: String, data: Array) -> void:
	if not remote_players.has(id): return
	var remote: Node3D = remote_players[id]
	remote.play_action(kind, data)
	if kind == "shot":
		_weapon_fired(data[0],data[1])
		sfx.play_at("ak",remote.global_position,-9.0)
	if kind == "step":
		var group: String = {"tile":"step_tile", "water":"step_water", "swim":"swim"}[data[0]]
		sfx.play_at(group, remote.global_position + Vector3(0, 0.2, 0), -12.0)
	elif kind == "splash":
		sfx.play_at("splash_big", remote.global_position, -8.0)
		splash_at(Vector3(remote.global_position.x, 0.05, remote.global_position.z), data[0])

func _update_network_ui() -> void:
	if network == null: return
	menu.set_network_state(network.connection_text(), network.active, network.connecting)
	_network_label.visible = network.active
	_network_label.text = ("HOST" if multiplayer.is_server() else "ONLINE") + " · %d/%d hráči · Esc: spojení" % [network.names.size(), NetScript.MAX_PLAYERS]

func _network_pickup_request(id: int) -> void:
	if pickup_prop.collected or not network.active or not multiplayer.is_server(): return
	var position_now: Vector3
	if id == 1:
		position_now = player.global_position
	else:
		if not network.states.has(id): return
		var state: Array = network.states[id]
		if state[5] & (NetScript.FLAG_CROUCH | NetScript.FLAG_SWIM) or not (state[5] & NetScript.FLAG_GROUNDED): return
		position_now = state[1]
	if _position_reaches_pickup(position_now): network.collect_sample(id)

func _network_sample_changed(owner: int) -> void:
	if owner == multiplayer.get_unique_id(): player.weapon.equip()
	elif remote_players.has(owner): remote_players[owner].body.weapon.equipped=true
	pickup_prop.collect()
	collected_samples = 1
	toast("AK-47 sebrána" if owner == multiplayer.get_unique_id() else "%s sebral AK-47" % str(network.names.get(owner, "Hráč")))

func _build_pickup_prop() -> void:
	pickup_prop = PickupScript.new()
	pickup_prop.name = "AK47Pickup"
	add_child(pickup_prop)
	pickup_prop.position = Vector3(0.9, 0.58, 6.2)

func _build_zombie() -> void:
	if is_instance_valid(zombie):
		remove_child(zombie)
		zombie.queue_free()
	zombie=ZombieScript.new()
	zombie.name="TestZombie"
	add_child(zombie)
	zombie.position=Vector3(-0.45,0.52,2.8)
	zombie.attacked.connect(_zombie_attack)
	zombie.died.connect(func(point: Vector3,impulse: Vector3,bone: int):
		toast("Zombie zneškodněn")
		if network and network.active and multiplayer.is_server(): _zombie_killed.rpc(point,impulse,bone))

@rpc("authority","call_remote","reliable",0)
func _zombie_killed(point: Vector3,impulse: Vector3,bone: int) -> void:
	if network.active and not multiplayer.is_server() and is_instance_valid(zombie):
		zombie.kill.call_deferred(point,impulse,bone)

func _reset_pickup() -> void:
	_build_zombie()
	_pickup_serial += 1
	_pickup_pending = false
	player.interaction_locked = false
	player.weapon.reset()
	# Desert Eagle, MP 40 a dvojku má hráč od začátku (4, 2, 3); AK-47 je potřeba najít (1).
	player.weapon.give("deagle", true)
	player.weapon.give("mp40", false)
	player.weapon.give("izh54", false)
	collected_samples = 0
	pickup_prop.reset()

func _can_reach_pickup() -> bool:
	if pickup_prop == null or pickup_prop.collected or not player.control_enabled or _ending:
		return false
	if menu.is_open or player.crouching or player.swimming or not player.is_on_floor():
		return false
	return _position_reaches_pickup(player.global_position)

func _position_reaches_pickup(position_now: Vector3) -> bool:
	var delta := pickup_prop.global_position - position_now
	if Vector2(delta.x, delta.z).length() > PICKUP_REACH or absf(delta.y) > 0.6:
		return false
	var query := PhysicsRayQueryParameters3D.create(position_now + Vector3(0, 0.9, 0), pickup_prop.global_position, 1)
	return get_world_3d().direct_space_state.intersect_ray(query).is_empty()

func _try_pickup() -> void:
	if _pickup_pending or not _can_reach_pickup():
		return
	var delta := pickup_prop.global_position - player.global_position
	var facing := atan2(-delta.x, -delta.z) if player.third_person else INF
	if not player.body.pick_up(facing, true):
		return
	player.velocity.x = 0.0
	player.velocity.z = 0.0
	player.interaction_locked = true
	_pickup_pending = true
	_pickup_serial += 1
	var serial := _pickup_serial
	var animation: Animation = player.body.LIBRARY.get_animation("pick_up")
	var contact: float = animation.get_meta("contact_time")
	# Oba časovače se pozastaví s menu. Generace chrání nový začátek hry.
	await get_tree().create_timer(contact, false).timeout
	if serial != _pickup_serial:
		return
	if player.body.is_picking_up() and _position_reaches_pickup(player.global_position):
		if network.active:
			network.request_pickup()
		elif pickup_prop.collect():
			collected_samples += 1
			player.weapon.equip()
			toast("AK-47 sebrána")
			mode.begin()
	await get_tree().create_timer(animation.length - contact, false).timeout
	if serial == _pickup_serial:
		player.interaction_locked = false
		_pickup_pending = false

func _setup_reflection() -> void:
	refl_vp = SubViewport.new()
	refl_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	refl_vp.use_hdr_2d = true
	# Odraz je rozmazaný vlnami: stíny lamp, drobnosti a krev v něm nejsou poznat, takže je nekreslíme.
	refl_vp.positional_shadow_atlas_size = 0
	refl_vp.mesh_lod_threshold = 6.0
	refl_vp.msaa_3d = Viewport.MSAA_DISABLED
	add_child(refl_vp)
	refl_cam = Camera3D.new()
	refl_cam.environment = refl_env
	refl_cam.cull_mask = 0xFFFFF & ~2 & ~8 & ~(1 << 19)   # voda, tělo pro první osobu a krev na zdech
	refl_cam.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	refl_vp.add_child(refl_cam)
	refl_cam.make_current()
	water_mat.set_shader_parameter("refl_tex", refl_vp.get_texture())
	_on_resize()

func _on_resize() -> void:
	if refl_vp:
		var s := get_viewport().get_visible_rect().size
		var k := 1.0 if int(settings.get("planar", 1)) == 2 else 0.5
		refl_vp.size = Vector2i(maxi(int(s.x * k), 64), maxi(int(s.y * k), 64))

# =============================================================== UI
func _label(parent: Node, text: String, size: int, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _setup_ui() -> void:
	# OSD kamery (pod postprocesem, takže se deformuje s obrazem)
	var osd_layer := CanvasLayer.new()
	osd_layer.layer = 5
	add_child(osd_layer)
	_osd = Control.new()
	_osd.set_anchors_preset(Control.PRESET_FULL_RECT)
	_osd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_osd.visible = false
	osd_layer.add_child(_osd)
	var play := _label(_osd, "PLAY ►", 46)
	play.position = Vector2(230, 150)
	_osd_sp = _label(_osd, "SP", 46)
	_osd_time = _label(_osd, "", 46)

	# postproces
	var post_layer := CanvasLayer.new()
	post_layer.layer = 10
	add_child(post_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/post.gdshader")
	rect.material = post_mat
	post_layer.add_child(rect)
	# BODYCAM (experiment): když je zapnutý, vymění materiál tohoto průchodu a řídí kameru
	bodycam = load("res://scripts/bodycam.gd").new()
	add_child(bodycam)
	bodycam.setup(self, rect, post_mat)
	player.cam_fx = bodycam
	# VISOR (experiment): hledí helmy jde před bodycam i běžný postproces
	visor = load("res://scripts/visor.gd").new()
	add_child(visor)
	visor.setup(self, post_layer, player)

	# nápověda a hlášky (nad postprocesem)
	var ui := CanvasLayer.new()
	ui.layer = 20
	add_child(ui)
	_help = _label(ui, "WASD  pohyb        Shift  běh        Mezerník  skok\nC / Ctrl  přikrčit se a plazit\nP  první / třetí osoba        Q  změna ramene\nR  přebít AK / otočit neozbrojenou postavu        N (držet)  prohlédnout zbraň\nE  sebrat AK        Levé tlačítko  střelba        Pravé  míření\nQ / kolečko myši  úder pažbou        Shift  sprint (sklopí zbraň)\nF  svítilna        V  VHS kamera        G  rybí oko        B  bodycam (experiment)        H  otřít hledí (experiment)        M / Tab  mapa (držet)\nI  inventář        1–5  rychlý panel (nastav v inventáři)   kolečko  další zbraň\nT  zahodit, co máš v ruce (v inventáři Shift + pravé tlačítko nebo přetáhnout mimo)\nZ  přivolat zombie na zkoušku        X  uklidit zombie\nEsc  menu a nastavení (záložka Testování)", 20, Color(1, 1, 1, 0.92))
	_help.position = Vector2(28, 22)
	_fps = _label(ui, "", 18, Color(1, 1, 1, 0.7))
	var perf: CanvasLayer = load("res://scripts/perf_monitor.gd").new()
	add_child(perf)
	perf.setup.call_deferred(self)
	_fps.visible = false
	_toast = _label(ui, "", 24)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.modulate.a = 0.0
	_interaction_label = _label(ui, "E — Sebrat AK-47", 25, Color(1.0, 0.88, 0.59))
	_interaction_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_interaction_label.visible = false
	_network_label = _label(ui, "", 20, Color(0.65, 0.94, 0.95))
	_network_label.visible = false
	_ammo_label=_label(ui,"",26,Color(0.9,0.95,1.0))
	_crosshair=_label(ui,"",24,Color(1,1,1,0.7))      # zaměřovač kreslí zombie_mode.gd; tady zůstává kotva pro značku zásahu
	_crosshair.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	_crosshair.vertical_alignment=VERTICAL_ALIGNMENT_CENTER

	var fade_layer := CanvasLayer.new()
	fade_layer.layer = 30
	add_child(fade_layer)
	_fade_rect = ColorRect.new()
	_fade_rect.color = Color(0, 0, 0, 1)
	_fade_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_fade_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	fade_layer.add_child(_fade_rect)
	_end_label = _label(fade_layer, "ÚROVEŇ 0\n\nProlezl jsi dál. Tady jednou začne úroveň 1.", 30, Color(0.8, 0.9, 0.9))
	_end_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_end_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_end_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_end_label.modulate.a = 0.0
	_intro_fade = create_tween()
	_intro_fade.tween_property(_fade_rect, "color:a", 0.0, 2.5).set_delay(0.4)

func toast(t: String) -> void:
	_toast.text = t
	_toast_t = 1.8

func _onoff(b: bool) -> String:
	return "zapnuto" if b else "vypnuto"

func _unhandled_input(event: InputEvent) -> void:
	if menu == null or menu.is_open:
		return
	if inventory and inventory.is_open:
		return
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	if not (event is InputEventKey and event.pressed and not event.echo):
		return
	match event.physical_keycode:
		KEY_ESCAPE:
			if not _ending:
				get_viewport().set_input_as_handled()
				if network.active:
					player.input_suspended = true
				else:
					get_tree().paused = true
				menu.open(true)
		KEY_F11:
			settings["window"] = 1 - int(settings["window"])
			_on_setting_changed("window")
		KEY_F3:
			settings["show_fps"] = not settings["show_fps"]
			_on_setting_changed("show_fps")
		KEY_Z:
			_spawn_zombie()
		KEY_X:
			_clear_zombies()
		KEY_V:
			settings["vhs"] = not settings["vhs"]
			_on_setting_changed("vhs")
			toast("VHS kamera: " + _onoff(vhs_on))
		KEY_F:
			if quest and quest.toggle_flash(): pass
			elif flashlight:
				flashlight.visible = not flashlight.visible
				sfx.play("tick", -6.0, 1.5 if flashlight.visible else 1.1)
		KEY_H:      # VISOR (experiment): otřít hledí
			if visor and visor.enabled:
				visor.wipe()
			else:
				toast("Hledí helmy je vypnuté (Nastavení → Kamera, experiment)")
		KEY_B:      # BODYCAM (experiment)
			settings["bodycam"] = not settings["bodycam"]
			_on_setting_changed("bodycam")
			toast("Bodycam (experiment): " + _onoff(bool(settings["bodycam"])))
		KEY_G:
			settings["fisheye"] = not settings["fisheye"]
			_on_setting_changed("fisheye")
			toast("Rybí oko: " + _onoff(fisheye_on))
		KEY_P:
			settings["perspective"] = 1 - int(settings["perspective"])
			_on_setting_changed("perspective")
			toast("Pohled z třetí osoby" if player.third_person else "Pohled z první osoby")
		KEY_Q:
			if player.third_person:
				settings["tp_side"] = 1 - int(settings["tp_side"])
				_on_setting_changed("tp_side")

# =============================================================== události
func _on_footstep(kind: String, k: float) -> void:
	if network: network.send_action("step", [kind, k])
	match kind:
		"tile":
			sfx.play("step_tile", -9.0 + 5.0 * (k - 1.0))
		"water":
			sfx.play("step_water", -8.0 + 5.0 * (k - 1.0), 1.05 - clampf(player.submersion, 0.0, 1.0) * 0.2)
			if k > 0.8:
				splash_at(player.global_position * Vector3(1, 0, 1) + Vector3(0, 0.03, 0), 0.25 * k)
		"swim":
			sfx.play("swim", -9.0 if k > 0.8 else -15.0)

var _fx: Node3D

func _combat_fx() -> Node3D:
	if _fx==null:
		_fx=preload("res://scripts/combat_fx.gd").new()
		_fx.water_y=WATER_Y
		add_child(_fx)
		ZombieScript.water_level=WATER_Y
		ZombieScript.fx=_fx
		ZombieScript.sfx=sfx
		ZombieScript.sim=sim
		ZombieScript.splash=splash_at
	return _fx

func _shot_effects(origin: Vector3, hit: Vector3, solid: bool, normal:=Vector3.ZERO, kind:="tile") -> void:
	if _combat_fx().shot(origin,hit,solid,normal,kind): sfx.play_at("tick",hit,-7.0,randf_range(0.7,1.1))

var _marker: Control
var _marker_tween: Tween
var _marker_sounds: Dictionary={}

func _hit_marker(lethal: bool, head: bool) -> void:
	var show_mark: bool=bool(settings.get("hitmarker",true))
	var play_sound: bool=bool(settings.get("hit_sound",true))
	if not show_mark and not play_sound: return
	if _marker==null:
		_marker=Control.new()
		_marker.set_anchors_preset(Control.PRESET_CENTER)
		_marker.mouse_filter=Control.MOUSE_FILTER_IGNORE
		_crosshair.get_parent().add_child(_marker)
		# Čtyři šikmé čárky kolem středu s mezerou uprostřed.
		for i in 4:
			var line:=ColorRect.new()
			line.size=Vector2(11,2.5)
			line.position=Vector2(7,-1.25)
			line.mouse_filter=Control.MOUSE_FILTER_IGNORE
			var arm:=Control.new()
			arm.rotation=PI/4+i*PI/2
			arm.add_child(line)
			_marker.add_child(arm)
		for name in ["hit_marker","hit_kill"]:
			var sound:=AudioStreamPlayer.new()
			if ResourceLoader.exists("res://audio/"+name+".wav"): sound.stream=load("res://audio/"+name+".wav")
			sound.volume_db=-7.0
			add_child(sound)
			_marker_sounds[name]=sound
	_marker.visible=show_mark
	_marker.modulate=Color(1.0,0.16,0.12,1.0) if lethal else Color(1,1,1,1)
	_marker.scale=Vector2.ONE*(1.7 if lethal else 1.35)
	if _marker_tween: _marker_tween.kill()
	_marker_tween=create_tween().set_parallel(true)
	_marker_tween.tween_property(_marker,"scale",Vector2.ONE,0.12).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	_marker_tween.tween_property(_marker,"modulate:a",0.0,0.5 if lethal else 0.28).set_delay(0.08)
	var sound: AudioStreamPlayer=_marker_sounds["hit_kill" if lethal else "hit_marker"]
	if play_sound and sound.stream:
		sound.pitch_scale=(1.15 if head else 1.0)*randf_range(0.97,1.03)
		sound.play()

func _spawn_zombie() -> void:
	mode.spawn_debug()

func _clear_zombies() -> void:
	mode.clear_debug()

func _zombie_attack(damage: float=34.0) -> void:
	mode.hurt(damage)

func _strike_effects(victim: Node3D, bone: int, point: Vector3, direction: Vector3, was_dead: bool, own: bool, melee: bool) -> void:
	var lethal: bool=victim.dead or victim._death_pending
	var region: String=victim._region(bone)
	sfx.play_at("hit_flesh",point,-1.0 if melee else -4.0,randf_range(0.9,1.15))
	_combat_fx().blood(point,direction,lethal and not was_dead)
	if visor and own and not was_dead: visor.on_strike(point, direction, lethal, melee)      # VISOR (experiment)
	if own and not was_dead:
		# Značka zásahu a body jen za vlastní rány do živé zombie; červená při zabití.
		_hit_marker(lethal,region=="head")
		mode.on_hit(victim,region,lethal,melee)

func _weapon_fired(_origin: Vector3, hit: Vector3) -> void:
	var direction: Vector3=(hit-_origin).normalized()
	var own: bool=player!=null and player.weapon.equipped and _origin.distance_to(player.camera.global_position)<0.3
	# Výstřel vyruší zombie, které se v okolí krmí u těl.
	preload("res://scripts/zombie.gd").noise(_origin,18.0)
	var muzzle: Vector3=player.body.weapon.muzzle_global() if own else _origin
	var space:=get_world_3d().direct_space_state
	# Hlaveň přes roh nesmí přeskočit zeď mezi kamerou a ústím.
	if own:
		var obstruction:=space.intersect_ray(PhysicsRayQueryParameters3D.create(_origin,muzzle,1))
		if not obstruction.is_empty():
			direction=(Vector3(obstruction.position)-_origin).normalized()
			muzzle=Vector3(obstruction.position)+Vector3(obstruction.normal)*0.02
	var far:=_origin+direction*100.0
	var from:=_origin
	var end:=far
	var power:=1.0
	var solid:=false
	var normal:=Vector3.UP
	var hit_kind:="tile"
	var exclude: Array[RID]=[]
	# Střela projde až dvěma těly; každé jí ubere sílu.
	for pass_index in 3:
		var query:=PhysicsRayQueryParameters3D.create(from,far,1|32|64)
		query.collide_with_areas=true
		query.exclude=exclude
		var target:=space.intersect_ray(query)
		if target.is_empty():
			end=far
			break
		end=target.position
		if target.collider.has_meta("shootable"):
			target.collider.get_meta("shootable").shot(target.collider,target.position,direction)
			break
		if not target.collider.has_meta("zombie"):
			solid=true
			normal=target.normal
			hit_kind="tile" if target.collider==world_body else "prop"
			break
		var victim: Node3D=target.collider.get_meta("zombie")
		var bone: int=target.collider.get_meta("bone")
		var was_dead: bool=victim.dead or victim._death_pending
		if not network.active or multiplayer.is_server():
			var strength:=lerpf(1.0,0.65,clampf(_origin.distance_to(target.position)/80.0,0.0,1.0))*power
			var damage_now:=50.0
			if own:
				damage_now=player.weapon.damage
				# Broky ztrácejí sílu se vzdáleností mnohem rychleji než kulky.
				if int(player.weapon.stats().pellets)>1:
					damage_now*=clampf(1.25-_origin.distance_to(target.position)/14.0,0.15,1.25)
					strength*=0.45
			victim.hit(bone,target.position,direction,strength,damage_now)
		_strike_effects(victim,bone,target.position,direction,was_dead,own,false)
		for area in victim.hitboxes: exclude.append(area.get_rid())
		for body in victim.bodies.values(): exclude.append(body.get_rid())
		from=target.position
		power*=0.6
	# Hladina: střela do vody vyhodí gejzír a rozvlní ji.
	var wet:=false
	if _origin.y>WATER_Y and end.y<WATER_Y and direction.y<-0.001:
		var surface:=_origin+direction*((WATER_Y-_origin.y)/direction.y)
		for rect in water_rects:
			if rect.has_point(Vector2(surface.x,surface.z)):
				wet=true
				splash_at(surface+Vector3(0,0.02,0),0.32)
				sim.add_impulse(Vector2(surface.x,surface.z),0.2,-1.0)
				sfx.play_at("step_water",surface,-7.0,1.35)
				break
	_shot_effects(muzzle,end,solid and not wet,normal,hit_kind)
	if solid: _combat_fx().hole(end,normal)

func _melee(origin: Vector3, direction: Vector3) -> void:
	# Úder pažbou: nejbližší zombie v dosahu před hráčem.
	var space:=get_world_3d().direct_space_state
	for angle in [0.0,-0.2,0.2,-0.4,0.4]:
		var aim:=direction.rotated(Vector3.UP,angle)
		var query:=PhysicsRayQueryParameters3D.create(origin,origin+aim*1.9,64)
		query.collide_with_areas=true
		query.collide_with_bodies=false
		var target:=space.intersect_ray(query)
		if target.is_empty() or not target.collider.has_meta("zombie"): continue
		var victim: Node3D=target.collider.get_meta("zombie")
		var bone: int=target.collider.get_meta("bone")
		if space.intersect_ray(PhysicsRayQueryParameters3D.create(origin,target.position,1)).is_empty():
			var was_dead: bool=victim.dead or victim._death_pending
			victim.hit(bone,target.position,direction,1.0,150.0,true)
			_strike_effects(victim,bone,target.position,direction,was_dead,true,true)
			player.pitch=clampf(player.pitch-0.015,-1.5,1.5)
		return

func _on_splash(strength: float) -> void:
	if network: network.send_action("splash", [strength])
	sfx.play("splash_big", -3.0 + 3.0 * (strength - 1.0))
	splash_at(player.global_position * Vector3(1, 0, 1) + Vector3(0, 0.05, 0), strength)

static func zone_of(p: Vector3) -> String:
	if p.x < -24.3:
		return "tunnel"
	if p.x < -12.3:
		return "corridor"
	if p.z > -1.5:
		return "start"
	return "hall"

func _start_ending() -> void:
	_ending = true
	player.control_enabled = false
	sfx.play("whoomp", -2.0)
	var tw := create_tween()
	tw.tween_property(_fade_rect, "color:a", 1.0, 2.6)
	tw.parallel().tween_property(sfx, "fade", 0.0, 3.2)
	tw.tween_property(_end_label, "modulate:a", 1.0, 1.0)
	tw.tween_interval(4.0)
	tw.tween_property(_end_label, "modulate:a", 0.0, 0.8)
	tw.tween_callback(func():
		player.teleport(SPAWN, 0.0, -0.03)
		player.control_enabled = true
		_ending = false)
	tw.tween_property(sfx, "fade", 1.0, 1.0)
	tw.parallel().tween_property(_fade_rect, "color:a", 0.0, 2.0)

# =============================================================== smyčka
func _process(dt: float) -> void:
	var _perf_t0:=Time.get_ticks_usec()
	_process_timed(dt)
	PerfMon.add("Hlavní smyčka",Time.get_ticks_usec()-_perf_t0)

func _process_timed(dt: float) -> void:
	_menu_camera(dt)
	_time += dt
	var cam: Camera3D = get_viewport().get_camera_3d() if get_viewport().get_camera_3d() else player.camera      # v menu kamera pozadí
	var ct := cam.global_transform

	_update_shadow_budget(dt)
	_atmosphere(dt)
	_flashlight_flicker(dt)
	if _flash_dust: _flash_dust.global_position = player.camera.global_position + Vector3(0, -0.4, 0)
	if _flash_spill: _flash_spill.light_energy = 0.8 * flashlight.light_energy / maxf(_flash_energy, 0.01) * clampf(_flash_energy / 9.0, 0.6, 2.2)
	# --- zrcadlová kamera pro odraz hladiny
	var planar_on := int(settings["planar"]) > 0
	if planar_on:
		var b := ct.basis
		var o := ct.origin
		var mx := Vector3(b.x.x, -b.x.y, b.x.z)
		var my := Vector3(b.y.x, -b.y.y, b.y.z)
		var mz := Vector3(b.z.x, -b.z.y, b.z.z)
		refl_cam.global_transform = Transform3D(Basis(mx, -my, mz), Vector3(o.x, 2.0 * WATER_Y - o.y, o.z))
		refl_cam.fov = cam.fov
		refl_cam.near = cam.near
		refl_cam.far = minf(cam.far, 48.0)      # 30 m uřízlo vzdálené zdi: v odrazu pak byl na hladině pruh pozadí
		# Kouká-li hráč vzhůru, hladinu nevidí: odraz se nemusí kreslit.
		var sees_water := -b.z.y < 0.6 and (o.y - WATER_Y) < 12.0
		# Při klidném pohledu stačí odraz obnovit každý druhý snímek (vlny ho stejně rozmývají);
		# při rychlém otáčení nebo pohybu se kreslí každý snímek, aby se neopožďoval.
		var turn := _refl_last_basis.z.angle_to(b.z) if dt > 0.0 else 1.0
		var moved := _refl_last_origin.distance_to(o)
		_refl_frame += 1
		var full_rate := turn > 0.012 or moved > 0.06 or Engine.get_frames_per_second() < 75
		if not sees_water:
			refl_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
		elif full_rate or _refl_frame % 2 == 0:
			refl_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
			_refl_last_basis = b
			_refl_last_origin = o
		else:
			refl_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	water_mat.set_shader_parameter("planar_mix", 1.0 if planar_on else 0.0)

	# --- režimy kamery
	_vhs = move_toward(_vhs, 1.0 if vhs_on else 0.0, dt * 2.5)
	var fish_target := clampf(float(settings["fisheye_strength"]), 0.0, 1.0) if fisheye_on else 0.0
	_fish = move_toward(_fish, fish_target, dt * 2.5)
	post_mat.set_shader_parameter("vhs", _vhs)
	post_mat.set_shader_parameter("fisheye", _fish)
	player.handheld = _vhs
	player.base_fov = float(settings["fov"]) + 12.0 * _fish
	_osd.visible = _vhs > 0.5
	if _osd.visible:
		var d := Time.get_datetime_dict_from_system()
		var months := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
		var h: int = d.hour % 12
		_osd_time.text = "%s %d:%02d\n%s. %d %d" % ["PM" if d.hour >= 12 else "AM", 12 if h == 0 else h, d.minute, months[d.month - 1], d.day, d.year]
	cam_attr.dof_blur_amount = lerpf(0.055, 0.085, _vhs)

	# --- blikající zářivka
	# Zombie v blízkosti lampy rozruší proud: světlo začne blikat dřív, než ji uvidíš.
	_lamp_scan -= dt
	if _lamp_scan <= 0.0:
		_lamp_scan = 0.3
		for L in lamps:
			var lp: Vector3 = (L.light as OmniLight3D).global_position
			var near := false
			for z in ZombieScript.crowd:
				if is_instance_valid(z) and not z.dead and (z.global_position + Vector3.UP).distance_to(lp) < 6.0:
					near = true
					break
			L["haunted"] = near
			if near and L.seq == 0 and randf() < 0.35:
				L.seq = 4 + randi() % 8
				L.timer = 0.02
	for L in lamps:
		if not L.flicker and not L.get("haunted", false) and L.seq == 0 and L.on >= 1.0:
			continue
		L.timer -= dt
		if L.seq > 0:
			if L.timer <= 0.0:
				L.on = (0.05 if randf() < 0.5 else 0.4) if L.on > 0.5 else 1.0
				L.seq -= 1
				L.timer = randf_range(0.03, 0.14)
				if L.on < 0.5:
					sfx.play_at("tick", (L.light as OmniLight3D).global_position, -10.0)
		elif L.timer <= 0.0:
			L.seq = 3 + randi() % 8
			L.timer = 0.05
		if L.seq == 0 and L.on < 1.0:
			L.on = 1.0
			L.timer = randf_range(3.0, 9.0)
			var lamp_pos: Vector3 = (L.light as OmniLight3D).global_position
			if randf() < 0.35 and lamp_pos.distance_to(player.global_position) < 14.0:
				sfx.play_at("lamp_spark", lamp_pos, -4.0, randf_range(0.9, 1.1))
		if L.has("hum"):
			(L.hum as AudioStreamPlayer3D).volume_db = lerpf((L.hum as AudioStreamPlayer3D).volume_db, -15.0 if L.on > 0.5 else -28.0, 0.5)
		(L.light as OmniLight3D).light_energy = L.energy * L.on
		(L.mat as StandardMaterial3D).emission_energy_multiplier = 1.4 * (0.04 + 0.96 * L.on)
		if _buzz:
			_buzz.volume_db = -18.0 if L.on > 0.5 else -12.0

	# --- zóny, konec úrovně
	var z := zone_of(player.global_position)
	sfx.set_zone(z)
	if not _ending and not network.active and not mode.active and player.global_position.x < -29.6:
		_start_ending()
	if not _ending and player.control_enabled and z == "corridor" and player.global_position.x < -21.5 and not player.crouching:
		if _toast_t <= 0.0:
			toast("C: přikrčit se a prolézt")

	# --- UI (rozložení počítané z velikosti okna, OSD v měřítku 1080p)
	var vs := get_viewport().get_visible_rect().size
	var sc := vs.y / 1080.0
	_osd.scale = Vector2(sc, sc)
	_osd_sp.position = Vector2(vs.x / sc - 330.0, 150.0)
	_osd_time.position = Vector2(230.0, 1080.0 - 290.0)
	_fps.position = Vector2(vs.x - (430.0 if _fps.text.contains("\n") else 110.0) * sc, 14.0)
	_fps.scale = Vector2(sc, sc)
	_network_label.scale = Vector2(sc, sc)
	_network_label.position = Vector2(24.0 * sc, vs.y - 42.0 * sc)
	_ammo_label.scale=Vector2(sc,sc)
	_ammo_label.position=Vector2(vs.x-250.0*sc,vs.y-75.0*sc)
	_ammo_label.visible=false      # bez HUD: náboje ukáže držené R
	_ammo_label.text="Přebíjení…" if player.weapon.reload_left>0 else "%s   %d / %s" % [player.weapon.display_name(),player.weapon.ammo,"∞" if player.weapon.infinite_reserve else str(player.weapon.reserve)]
	_crosshair.position=vs*0.5-Vector2(15,15)
	_crosshair.size=Vector2(30,30)
	_crosshair.visible=player.weapon.equipped and not menu.is_open and player.weapon.aim_amount<0.8
	_help.scale = Vector2(sc, sc)
	_toast.scale = Vector2(sc, sc)
	_toast.size.x = vs.x / sc
	_toast.position = Vector2(0.0, vs.y - 150.0 * sc)
	_interaction_label.scale = Vector2(sc, sc)
	_interaction_label.size.x = vs.x / sc
	_interaction_label.position = Vector2(0.0, vs.y - 100.0 * sc)
	var reachable := _can_reach_pickup()
	_interaction_label.visible = reachable and not _pickup_pending
	pickup_prop.set_highlight(reachable)
	_help_t -= dt
	_help.modulate.a = move_toward(_help.modulate.a, 1.0 if (_help_t > 0.0 and not menu.is_open) else 0.0, dt * 1.5)
	_toast_t -= dt
	_toast.modulate.a = move_toward(_toast.modulate.a, 1.0 if _toast_t > 0.0 else 0.0, dt * 4.0)
	if _fps.visible:
		# F3: FPS a rozpad času snímku, ať je vidět, co při boji brzdí.
		_fps.text = "%d FPS\nskripty %.1f ms   fyzika %.1f ms\n%d objektů, %d tis. trojúhelníků, %d vykreslení\nzombie %d" % [Engine.get_frames_per_second(),Performance.get_monitor(Performance.TIME_PROCESS)*1000.0,Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)*1000.0,int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),int(Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)/1000.0),int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),ZombieScript.crowd.size()]

# =============================================================== testovací režim (příkazová řádka)
# Příklad: godot --path . -- --shots="hala:0,-0.35,-3,0,0;..." --out=/tmp/shots --frames=40
func _parse_args() -> void:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--"):
			var kv := a.substr(2).split("=", true, 1)
			_test[kv[0]] = kv[1] if kv.size() > 1 else "1"

func _run_test() -> void:
	var frames := int(_test.get("frames", "30"))
	var out: String = _test.get("out", "user://")
	_help_t = 0.0
	_help.modulate.a = 0.0
	_fade_rect.visible = false
	var ws := String(_test.get("size", "640x360")).split("x")
	get_window().mode = Window.MODE_WINDOWED
	get_window().size = Vector2i(int(ws[0]), int(ws[1]))
	if _test.has("vhs"):
		vhs_on = true
	if _test.has("fisheye"):
		fisheye_on = true
	if _test.has("bodycam"):      # BODYCAM (experiment)
		settings["bodycam"] = true
		apply_setting("bodycam")
	if _test.has("visor"):        # VISOR (experiment)
		settings["visor"] = true
		apply_setting("visor")
	if _test.has("gun"):
		player.weapon.give(String(_test["gun"]), true)
	_fade_rect.color.a = 0.0
	if _test.has("flipn"):
		tile_mat.set_shader_parameter("normal_flip_y", 1.0)
	await get_tree().process_frame
	if _test.has("menu"):
		if _test.has("settings"):
			menu._show_settings(true)
		for i in frames:
			await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out.path_join("g_menu.png"))
		menu._change("preset", 0)
		menu._change("preset", 3)
		menu._change("bloom", 0.3)
		for k in [KEY_ESCAPE, KEY_ESCAPE]:
			var ev := InputEventKey.new()
			ev.physical_keycode = k
			ev.pressed = true
			Input.parse_input_event(ev)
			await get_tree().process_frame
		menu.play_pressed.emit()
		await get_tree().create_timer(3.0).timeout
		print("MENU ok open=", menu.is_open, " ctrl=", player.control_enabled, " preset=", settings.preset, " pos=", player.global_position)
	for shot in String(_test.get("shots", "")).split(";", false):
		var parts := shot.split(":")
		var v := parts[1].split_floats(",")
		player.teleport(Vector3(v[0], v[1], v[2]), deg_to_rad(v[3]), deg_to_rad(v[4]))
		player.auto_walk = Vector2(v[5], v[6]) if v.size() > 6 else Vector2.ZERO
		if v.size() > 7 and v[7] > 0.5:
			player._set_crouch(true)
		var t0 := Time.get_ticks_msec()
		for i in frames:
			await get_tree().process_frame
		print("ms/frame ", (Time.get_ticks_msec() - t0) / float(frames))
		var img := get_viewport().get_texture().get_image()
		img.save_png(out.path_join(parts[0] + ".png"))
		print("SHOT ", parts[0], " pos=", player.global_position, " swim=", player.swimming, " crouch=", player.crouching)
	get_tree().quit()


# --- kulatý tunel (Bufet → Atrium)
const TUNNEL_R := 1.5
const TUNNEL_Y := 0.75      # osa trubky; vrchol 2,25 m, u podlahy (-0,35) široká ~2 m

func _tube_mesh(r: float, x0: float, x1: float, seg: int) -> ArrayMesh:
	# Vnitřek trubky podél osy X. UV v metrech: u = oblouk dokola, v = délka.
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var rings := maxi(2, int(ceil((x1 - x0) / 0.5)) + 1)
	for i in seg:
		for j in rings - 1:
			var a0 := TAU * float(i) / seg
			var a1 := TAU * float(i + 1) / seg
			var xa := lerpf(x0, x1, float(j) / (rings - 1))
			var xb := lerpf(x0, x1, float(j + 1) / (rings - 1))
			var quad := [[a0, xa], [a1, xa], [a1, xb], [a0, xb]]
			for k in [0, 2, 1, 0, 3, 2]:
				var a: float = quad[k][0]
				var x: float = quad[k][1]
				var radial := Vector3(0, sin(a), cos(a))
				st.set_normal(-radial)
				st.set_uv(Vector2(a * r, x))
				st.add_vertex(Vector3(x, 0, 0) + radial * r)
	st.generate_tangents()
	return st.commit()

func _tube_cap(r: float, half_w: float, y0: float, y1: float, seg: int) -> ArrayMesh:
	# Čelní stěna konce tunelu: obdélník otvoru mínus kruh trubky (oboustranná).
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for side in [1.0, -1.0]:
		for i in seg:
			var pts: Array = []
			for a in [TAU * float(i) / seg, TAU * float(i + 1) / seg]:
				var d := Vector2(cos(a), sin(a))              # x = z, y = výška
				var t := INF
				if absf(d.x) > 0.0001: t = minf(t, half_w / absf(d.x))
				if d.y > 0.0001: t = minf(t, y1 / d.y)
				elif d.y < -0.0001: t = minf(t, y0 / d.y)
				var outer: Vector2 = d * maxf(t, r)
				var inner: Vector2 = d * r
				pts.append([inner, outer])
			var tri := [pts[0][0], pts[1][0], pts[1][1], pts[0][0], pts[1][1], pts[0][1]]
			if side < 0.0: tri.reverse()
			# Godot: přední strana = po směru hodin. Pořadí výše míří na -X pro side=1, proto normála -side.
			for p2 in tri:
				st.set_normal(Vector3(-side, 0, 0))
				st.add_vertex(Vector3(0, (p2 as Vector2).y, (p2 as Vector2).x))
	return st.commit()
