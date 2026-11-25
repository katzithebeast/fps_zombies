extends Node3D
## Bažina v noci (prototyp): temná voda, mrtvé stromy, rákos, mlha a tma.
## Mapa se generuje pokaždé jinak (seed), jako v hotové hře: terén z šumu, rozmístění stromů,
## keřů a kamenů, lávka z prken od místa výsadku k polozatopenému sovětskému bunkru.
## Test s pevným seedem: SWAMP_SEED=123. Náhledy bez hráče: SWAMP_NOPLAYER=1 SWAMP_SHOTS=...

const R := 80.0                 # polovina strany mapy (m)
const STEP := 1.0               # rozestup bodů terénu
const WATER_Y := 0.0
const CHUNK := 32.0             # velikost bloku pro MultiMesh (ořez podle vzdálenosti)
const MD := "res://assets/swamp/models/"
const TX := "res://assets/swamp/tex/"
const LM := "res://assets/lobby/mats/"

## Modely a jak je rozdělit na varianty: whole = celý soubor, each = každý mesh zvlášť,
## pairs = po dvou (kmen + větve ve trees.glb).
const MODELS := {
	"dead": ["trees.glb", "pairs"],
	"ancient": ["ancient_tree.glb", "whole"],
	"white": ["tree_big.glb", "whole"],
	"oak": ["tree_gn.glb", "whole"],
	"pine": ["pine_tree.glb", "whole"],
	"fern": ["green_bush.glb", "whole"],
	"plant": ["plant_bush.glb", "whole"],
	"grass": ["real_bush.glb", "each"],
	"pbush": ["pine_bushes.glb", "each"],
	"boulder": ["rocks.glb", "each"],
	"rock": ["river_rocks.glb", "each"],
}

var settings := {"mouse": 1.0, "fov": 75.0, "volume": 0.8, "bob": 1.0, "bodycam": true, "bodycam_blur": 1.0, "contrast": 1.0, "gamma": 1.0}
var rng := RandomNumberGenerator.new()
var seed_used := 0
var noise := FastNoiseLite.new()
var detail := FastNoiseLite.new()
var islands := FastNoiseLite.new()
const THUNDER := true             # bouřka v dálce (blesk + hrom); false = jen déšť

var spawn := Vector3.ZERO
var goal := Vector3.ZERO
var path: PackedVector2Array = []
var _n := 0
var _hs: PackedFloat32Array
var _path_mask: PackedByteArray
var _occupied := {}                 # mřížka 2.5 m: kde už stojí strom

var _variants := {}
var _batches := {}
var _materials_done := {}
var _colliders: StaticBody3D
var _mats := {}

var player: CharacterBody3D
var cam: Camera3D
var flashlight: SpotLight3D
var _prompt: Label
var _toast: Label
var _toast_t := 0.0
var _goal_said := false
var _steps_mud := []
var _steps_water := []
var _swims := []
var _cracks := []
var _crack_t := 25.0
var _wisps := []
var _red_lamp: OmniLight3D
var _red_mesh: MeshInstance3D
var _time := 0.0
var _moon: DirectionalLight3D

func _ready() -> void:
	add_to_group("swamp_main")
	_load_settings()
	var env_seed := OS.get_environment("SWAMP_SEED")
	seed_used = int(env_seed) if env_seed != "" else int(Time.get_unix_time_from_system()) % 1000000
	rng.seed = seed_used
	noise.seed = seed_used
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = 0.022
	noise.fractal_octaves = 4
	detail.seed = seed_used + 17
	detail.frequency = 0.09
	detail.fractal_octaves = 2
	islands.seed = seed_used + 31
	islands.frequency = 0.05
	islands.fractal_octaves = 2
	print("Bažina: seed ", seed_used)
	_layout()
	_build_environment()
	_build_terrain()
	_build_water()
	_colliders = StaticBody3D.new()
	_colliders.name = "Kolize_stromy"
	add_child(_colliders)
	_load_variants()
	_build_boardwalk()
	_scatter()
	_flush_batches()
	_build_bunker()
	_build_barrels()
	_build_signs()
	_build_bounds()
	_build_rain()
	_build_mist_banks()
	_build_wisps()
	_build_sound()
	_build_player()
	_build_splashes()
	_build_post()
	_build_hud()
	if OS.get_environment("SWAMP_SHOTS") != "":
		_run_shots.call_deferred()

# =================================================================== rozvržení a terén

func _layout() -> void:
	var a := rng.randf() * TAU
	var s := Vector2.from_angle(a) * 56.0
	var g := Vector2.from_angle(a + PI + rng.randf_range(-0.6, 0.6)) * 54.0
	spawn = Vector3(clampf(s.x, -R + 18, R - 18), 0.0, clampf(s.y, -R + 18, R - 18))
	goal = Vector3(clampf(g.x, -R + 18, R - 18), 0.0, clampf(g.y, -R + 18, R - 18))
	# klikatá lávka mezi nimi (na koncích přímo do mýtin)
	var pa := Vector2(spawn.x, spawn.z)
	var pb := Vector2(goal.x, goal.z)
	var L := pa.distance_to(pb)
	var dir := (pb - pa) / L
	var perp := Vector2(-dir.y, dir.x)
	var k := rng.randf_range(1.2, 2.4)
	var ph := rng.randf() * TAU
	var amp := rng.randf_range(6.0, 13.0)
	var cnt := int(L / 0.5)
	for i in cnt + 1:
		var t := float(i) / cnt
		var off := sin(t * PI * k + ph) * amp * sin(t * PI)
		off += detail.get_noise_2d(t * 60.0, 3.0) * 2.0 * sin(t * PI)
		path.append(pa + dir * L * t + perp * off)

func height(x: float, z: float) -> float:
	var n := noise.get_noise_2d(x, z)
	var d := detail.get_noise_2d(x, z)
	var i := islands.get_noise_2d(x, z)
	# dno bažiny: skoro všude kalná voda po kolena
	var h := -0.5 + n * 0.22 + d * 0.12
	# ostrůvky a bulty nad hladinou
	h = lerpf(h, 0.22 + d * 0.25, smoothstep(0.38, 0.6, i))
	# hlubší tůně (až po pás)
	h = lerpf(h, -1.05 + d * 0.1, smoothstep(0.42, 0.62, -n))
	# ostrůvek u výsadku a u bunkru
	for c in [spawn, goal]:
		var k := 1.0 - smoothstep(4.5, 9.0, Vector2(x - c.x, z - c.z).length())
		h = lerpf(h, 0.35 + d * 0.1, k)
	return h

## Výška terénu (stejná interpolace jako mesh).
func ground(x: float, z: float) -> float:
	var fx := clampf((x + R) / STEP, 0.0, _n - 1.001)
	var fz := clampf((z + R) / STEP, 0.0, _n - 1.001)
	var ix := int(fx)
	var iz := int(fz)
	var tx := fx - ix
	var tz := fz - iz
	var h00 := _hs[iz * _n + ix]
	var h10 := _hs[iz * _n + ix + 1]
	var h01 := _hs[(iz + 1) * _n + ix]
	var h11 := _hs[(iz + 1) * _n + ix + 1]
	# stejné dělení čtverce na trojúhelníky jako v meshi (úhlopříčka b–c)
	if tx + tz <= 1.0:
		return h00 + (h10 - h00) * tx + (h01 - h00) * tz
	return h11 + (h01 - h11) * (1.0 - tx) + (h10 - h11) * (1.0 - tz)

func _build_terrain() -> void:
	_n = int(2.0 * R / STEP) + 1
	var n := _n
	_hs = PackedFloat32Array()
	_hs.resize(n * n)
	for iz in n:
		for ix in n:
			_hs[iz * n + ix] = height(-R + ix * STEP, -R + iz * STEP)
	var verts := PackedVector3Array()
	var nrms := PackedVector3Array()
	var tans := PackedFloat32Array()
	verts.resize(n * n)
	nrms.resize(n * n)
	tans.resize(n * n * 4)
	for iz in n:
		for ix in n:
			var i := iz * n + ix
			var hl := _hs[iz * n + maxi(ix - 1, 0)]
			var hr := _hs[iz * n + mini(ix + 1, n - 1)]
			var hd := _hs[maxi(iz - 1, 0) * n + ix]
			var hu := _hs[mini(iz + 1, n - 1) * n + ix]
			verts[i] = Vector3(-R + ix * STEP, _hs[i], -R + iz * STEP)
			nrms[i] = Vector3(hl - hr, 2.0 * STEP, hd - hu).normalized()
			var t := Vector3(2.0 * STEP, hr - hl, 0.0).normalized()
			tans[i * 4] = t.x
			tans[i * 4 + 1] = t.y
			tans[i * 4 + 2] = t.z
			tans[i * 4 + 3] = -1.0
	var idx := PackedInt32Array()
	idx.resize((n - 1) * (n - 1) * 6)
	var j := 0
	for iz in n - 1:
		for ix in n - 1:
			var a := iz * n + ix
			var b := a + 1
			var c := a + n
			var d := c + 1
			idx[j] = a; idx[j + 1] = b; idx[j + 2] = c
			idx[j + 3] = b; idx[j + 4] = d; idx[j + 5] = c
			j += 6
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrms
	arr[Mesh.ARRAY_TANGENT] = tans
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	var sm := ShaderMaterial.new()
	sm.shader = load("res://shaders/swamp_terrain.gdshader")
	sm.set_shader_parameter("mud_albedo", load(TX + "mud_albedo.jpg"))
	sm.set_shader_parameter("mud_normal", load(TX + "mud_normal.jpg"))
	sm.set_shader_parameter("mud_orm", load(TX + "mud_orm.jpg"))
	sm.set_shader_parameter("soil_albedo", load(TX + "soil_albedo.jpg"))
	sm.set_shader_parameter("soil_normal", load(TX + "soil_normal.jpg"))
	sm.set_shader_parameter("soil_orm", load(TX + "soil_orm.jpg"))
	sm.set_shader_parameter("noise", _noise_tex(256, 0.02, seed_used + 3))
	sm.set_shader_parameter("water_y", WATER_Y)
	mesh.surface_set_material(0, sm)
	var mi := MeshInstance3D.new()
	mi.name = "Teren"
	mi.mesh = mesh
	add_child(mi)
	var body := StaticBody3D.new()
	body.name = "Teren_kolize"
	var shape := HeightMapShape3D.new()
	shape.map_width = n
	shape.map_depth = n
	shape.map_data = _hs
	var cs := CollisionShape3D.new()
	cs.shape = shape
	body.add_child(cs)
	add_child(body)
	# maska lávky: v jejím okolí nic neroste
	_path_mask = PackedByteArray()
	_path_mask.resize(n * n)
	for p in path:
		for dz in range(-1, 2):
			for dx in range(-1, 2):
				var gx := int(round((p.x + R) / STEP)) + dx
				var gz := int(round((p.y + R) / STEP)) + dz
				if gx >= 0 and gz >= 0 and gx < n and gz < n:
					_path_mask[gz * n + gx] = 1

func _near_path(x: float, z: float) -> bool:
	var gx := int(round((x + R) / STEP))
	var gz := int(round((z + R) / STEP))
	if gx < 0 or gz < 0 or gx >= _n or gz >= _n: return false
	return _path_mask[gz * _n + gx] == 1

func _in_clearing(x: float, z: float, r := 9.0) -> bool:
	return Vector2(x - spawn.x, z - spawn.z).length() < r or Vector2(x - goal.x, z - goal.z).length() < r

func _noise_tex(size: int, freq: float, s: int) -> NoiseTexture2D:
	var fn := FastNoiseLite.new()
	fn.seed = s
	fn.frequency = freq
	fn.fractal_octaves = 4
	var nt := NoiseTexture2D.new()
	nt.width = size
	nt.height = size
	nt.seamless = true
	nt.noise = fn
	return nt

## Voda: kalná neprůhledná hladina s vlnami ze simulace brodění (jako v lázních) a odrazy SSR
## (shaders/swamp_water.gdshader).
var water_mat: ShaderMaterial
var sim: WaterSim
var refl_vp: SubViewport
var refl_cam: Camera3D

func _build_water() -> void:
	water_mat = ShaderMaterial.new()
	water_mat.shader = load("res://shaders/swamp_water.gdshader")
	water_mat.set_shader_parameter("weed_noise", _noise_tex(512, 0.012, seed_used + 9))
	var pm := PlaneMesh.new()
	pm.size = Vector2(2.0 * R + 8.0, 2.0 * R + 8.0)
	pm.subdivide_width = 320            # jemná síť: vlny ze simulace hýbou i hladinou
	pm.subdivide_depth = 320
	var mi := MeshInstance3D.new()
	mi.name = "Voda"
	mi.mesh = pm
	mi.material_override = water_mat
	mi.layers = 2                       # vrstva 2: zrcadlová kamera vodu nevidí
	mi.position.y = WATER_Y
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	add_child(mi)
	_build_sim()
	# odrazy: zrcadlení obrazovky (SSR v prostředí). Zrcadlová kamera z lázní tu dělala chyby:
	# v bažině je pod hladinou terén a ponořené kmeny, které se v ní objevovaly.

## Simulace hladiny (scripts/water_sim.gd) přes celou bažinu, ostrůvky jsou v masce pevné.
func _build_sim() -> void:
	if RenderingServer.get_rendering_device() == null: return      # headless test bez GPU
	sim = WaterSim.new()
	sim.fit(Rect2(-R, -R, 2.0 * R, 2.0 * R))
	add_child(sim)
	var small := Image.create(_n, _n, false, Image.FORMAT_L8)
	for iz in _n:
		for ix in _n:
			small.set_pixel(ix, iz, Color.WHITE if _hs[iz * _n + ix] < WATER_Y - 0.03 else Color.BLACK)
	# maska v rozlišení simulace (terén má bod po metru, simulace po ~5 cm)
	small.resize(sim.res, sim.res, Image.INTERPOLATE_BILINEAR)
	small.convert(Image.FORMAT_R8)
	sim.setup(small)
	water_mat.set_shader_parameter("sim_tex", sim.texture)
	water_mat.set_shader_parameter("sim_origin", sim.origin)
	water_mat.set_shader_parameter("sim_size", sim.size)
	water_mat.set_shader_parameter("sim_res", float(sim.res))

## Zrcadlová kamera pro odraz na hladině (jako v lázních): odráží se, co osvítí baterka.
func _build_reflection() -> void:
	var renv: Environment = _env.duplicate()
	renv.ssr_enabled = false
	renv.ssao_enabled = false
	renv.glow_enabled = false
	renv.volumetric_fog_enabled = false
	renv.adjustment_enabled = false
	renv.tonemap_mode = Environment.TONE_MAPPER_LINEAR
	renv.tonemap_exposure = 1.0
	renv.fog_density = 0.14          # v odrazu se vzdálené věci ztratí ve tmě dřív
	renv.fog_light_color = Color(0, 0, 0)
	renv.fog_sky_affect = 1.0
	refl_vp = SubViewport.new()
	refl_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	refl_vp.use_hdr_2d = true
	refl_vp.positional_shadow_atlas_size = 0
	refl_vp.mesh_lod_threshold = 6.0
	refl_vp.msaa_3d = Viewport.MSAA_DISABLED
	refl_vp.size = Vector2i(640, 360)
	add_child(refl_vp)
	refl_cam = Camera3D.new()
	refl_cam.environment = renv
	refl_cam.cull_mask = 0xFFFFF & ~2 & ~8 & ~(1 << 19)     # bez vody, vlastního těla a krve
	refl_vp.add_child(refl_cam)
	refl_cam.make_current()
	water_mat.set_shader_parameter("refl_tex", refl_vp.get_texture())

func _update_reflection() -> void:
	if refl_cam == null or cam == null: return
	var vs := get_viewport().get_visible_rect().size
	var want := Vector2i(maxi(int(vs.x * 0.5), 64), maxi(int(vs.y * 0.5), 64))
	if refl_vp.size != want: refl_vp.size = want
	var ct := cam.global_transform
	var b := ct.basis
	var o := ct.origin
	var mx := Vector3(b.x.x, -b.x.y, b.x.z)
	var my := Vector3(b.y.x, -b.y.y, b.y.z)
	var mz := Vector3(b.z.x, -b.z.y, b.z.z)
	refl_cam.global_transform = Transform3D(Basis(mx, -my, mz), Vector3(o.x, 2.0 * WATER_Y - o.y, o.z))
	refl_cam.fov = cam.fov
	refl_cam.near = cam.near
	refl_cam.far = 18.0
	# kouká-li hráč vzhůru, hladinu nevidí: odraz se nekreslí
	refl_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if -b.z.y < 0.6 else SubViewport.UPDATE_DISABLED

# =================================================================== tma, déšť, mlha, bouřka

var _sky_mat: ShaderMaterial
var _env: Environment
var _rain: GPUParticles3D
var _thunder_t := 30.0
var _flash := []                 # průběh blesku: [[čas, síla], ...]
var _flash_t := -1.0
var _thunders := []

func _build_environment() -> void:
	_env = Environment.new()
	var sky := Sky.new()
	_sky_mat = ShaderMaterial.new()
	_sky_mat.shader = load("res://shaders/swamp_sky.gdshader")
	sky.sky_material = _sky_mat
	_env.background_mode = Environment.BG_SKY
	_env.sky = sky
	# skoro úplná tma: bez baterky jen tušíš siluety
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.03, 0.035, 0.05)
	_env.ambient_light_energy = 0.1
	_env.reflected_light_source = Environment.REFLECTION_SOURCE_SKY
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.tonemap_exposure = 1.1
	_env.glow_enabled = true
	_env.glow_intensity = 0.6
	_env.glow_bloom = 0.03
	_env.glow_hdr_threshold = 0.9
	_env.ssao_enabled = true
	_env.ssao_radius = 0.8
	_env.ssao_intensity = 1.4
	# mokrá voda a kameny zrcadlí, co osvítí baterka
	_env.ssr_enabled = true
	_env.ssr_max_steps = 64
	_env.ssr_fade_in = 0.1
	_env.ssr_fade_out = 1.5
	_env.ssr_depth_tolerance = 0.25
	# barevné podání: studené zelenomodré stíny, teplejší světla, víc kontrastu
	_env.adjustment_enabled = true
	_env.adjustment_contrast = 1.12
	_env.adjustment_saturation = 1.05
	var g := Gradient.new()
	g.set_color(0, Color(0.0, 0.012, 0.018))
	g.set_color(1, Color(1.0, 0.97, 0.9))
	g.add_point(0.18, Color(0.13, 0.17, 0.17))
	g.add_point(0.55, Color(0.56, 0.57, 0.52))
	var gt := GradientTexture1D.new()
	gt.gradient = g
	gt.width = 256
	_env.adjustment_color_correction = gt
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.002, 0.0025, 0.003)
	_env.fog_density = 0.05
	_env.fog_sky_affect = 0.85
	# hustá vlhká mlha: kužel baterky v ní je vidět
	_env.volumetric_fog_enabled = OS.get_environment("SWAMP_LITE") != "1"
	_env.volumetric_fog_density = 0.045
	_env.volumetric_fog_albedo = Color(0.26, 0.28, 0.28)
	_env.volumetric_fog_emission = Color(0, 0, 0)
	_env.volumetric_fog_anisotropy = 0.15
	_env.volumetric_fog_length = 36.0
	_env.volumetric_fog_detail_spread = 1.5
	_env.volumetric_fog_ambient_inject = 0.05
	_env.volumetric_fog_sky_affect = 0.0
	var we := WorldEnvironment.new()
	we.environment = _env
	add_child(we)
	# "měsíc" je jen světlo blesku: normálně zhasnuté
	_moon = DirectionalLight3D.new()
	_moon.name = "Blesk"
	_moon.rotation = Vector3(deg_to_rad(-40.0), rng.randf() * TAU, 0.0)
	_moon.light_color = Color(0.7, 0.78, 1.0)
	_moon.light_energy = 0.0
	_moon.shadow_enabled = true
	_moon.directional_shadow_max_distance = 60.0
	_moon.light_volumetric_fog_energy = 1.0
	_moon.sky_mode = DirectionalLight3D.SKY_MODE_LIGHT_ONLY
	add_child(_moon)
	# přízemní mlha nad vodou (hustší dole, cáry podle šumu)
	var fv := FogVolume.new()
	fv.name = "Prizemni_mlha"
	fv.size = Vector3(2.0 * R + 20.0, 2.2, 2.0 * R + 20.0)
	fv.position.y = 0.5
	var fm := FogMaterial.new()
	fm.density = 0.05
	fm.albedo = Color(0.32, 0.34, 0.34)
	fm.height_falloff = 0.9
	fm.edge_fade = 0.3
	var nt3 := NoiseTexture3D.new()
	nt3.width = 64
	nt3.height = 16
	nt3.depth = 64
	nt3.seamless = true
	var fn := FastNoiseLite.new()
	fn.seed = seed_used + 5
	fn.frequency = 0.06
	nt3.noise = fn
	fm.density_texture = nt3
	fv.material = fm
	add_child(fv)

## Déšť kolem hráče: tenké kapky, které jsou vidět hlavně v kuželu baterky.
func _build_rain() -> void:
	var qm := QuadMesh.new()
	qm.size = Vector2(0.009, 0.42)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_FIXED_Y
	m.billboard_keep_scale = true
	m.albedo_color = Color(0.6, 0.64, 0.7, 0.16)
	m.roughness = 0.25
	m.disable_receive_shadows = true
	qm.material = m
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(15.0, 0.5, 15.0)
	pm.direction = Vector3(0.06, -1.0, 0.03)
	pm.spread = 2.0
	pm.initial_velocity_min = 13.0
	pm.initial_velocity_max = 17.0
	pm.gravity = Vector3(0, -6.0, 0)
	_rain = GPUParticles3D.new()
	_rain.name = "Dest"
	_rain.amount = 7000
	_rain.lifetime = 0.9
	_rain.preprocess = 1.0
	_rain.local_coords = false
	_rain.process_material = pm
	_rain.draw_pass_1 = qm
	_rain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rain.visibility_aabb = AABB(Vector3(-18, -16, -18), Vector3(36, 20, 36))
	_rain.position = spawn + Vector3(0, 11, 0)
	add_child(_rain)

func _lightning() -> void:
	_moon.rotation = Vector3(deg_to_rad(rng.randf_range(-55.0, -25.0)), rng.randf() * TAU, 0.0)
	var big := rng.randf()
	_flash = [[0.0, 2.2 * big + 0.6], [0.07, 0.0], [0.13, 1.4 * big + 0.3], [0.2, 0.05], [0.32, 0.9 * big], [0.5, 0.0]]
	_flash_t = 0.0
	if not _thunders.is_empty():
		var delay := lerpf(4.0, 0.7, big)
		get_tree().create_timer(delay).timeout.connect(func():
			var a := AudioStreamPlayer.new()
			a.stream = _thunders.pick_random()
			a.volume_db = lerpf(-14.0, -2.0, big)
			a.pitch_scale = rng.randf_range(0.85, 1.0)
			add_child(a)
			a.play()
			a.finished.connect(a.queue_free))

func _flash_level() -> float:
	if _flash_t < 0.0: return 0.0
	for i in range(_flash.size() - 1):
		var a: Array = _flash[i]
		var b: Array = _flash[i + 1]
		if _flash_t >= a[0] and _flash_t < b[0]:
			return lerpf(a[1], b[1], (_flash_t - a[0]) / (b[0] - a[0]))
	_flash_t = -1.0
	return 0.0


# =================================================================== modely a rozmístění

func _load_variants() -> void:
	var tmp := Node3D.new()
	add_child(tmp)
	for key in MODELS:
		var file: String = MODELS[key][0]
		var mode: String = MODELS[key][1]
		var inst: Node3D = (load(MD + file) as PackedScene).instantiate()
		tmp.add_child(inst)
		var parts := []
		for mi in inst.find_children("*", "MeshInstance3D", true, false):
			var m := mi as MeshInstance3D
			if m.mesh == null: continue
			for s in m.mesh.get_surface_count():
				var ov := m.get_surface_override_material(s)
				if ov: m.mesh.surface_set_material(s, ov)
			_fix_materials(m.mesh, key)
			parts.append([m.mesh, m.global_transform])
		var groups := []
		match mode:
			"whole": groups = [parts]
			"each":
				for p in parts: groups.append([p])
			"pairs":
				for i in range(0, parts.size() - 1, 2): groups.append([parts[i], parts[i + 1]])
		var vs := []
		for g in groups:
			var bb := AABB()
			var first := true
			for p in g:
				var b: AABB = (p[1] as Transform3D) * (p[0] as Mesh).get_aabb()
				bb = b if first else bb.merge(b)
				first = false
			var base := Vector3(bb.get_center().x, bb.position.y, bb.get_center().z)
			var s := 1.0 / maxf(bb.size.y, 0.0001)
			var norm := Transform3D(Basis.from_scale(Vector3.ONE * s), -base * s)
			var ps := []
			for p in g: ps.append([p[0], norm * (p[1] as Transform3D)])
			vs.append({"parts": ps, "w": maxf(bb.size.x, bb.size.z) * s})
		_variants[key] = vs
		inst.queue_free()
	tmp.queue_free()

## Vítr podle druhu (tráva se houpe nejvíc, stromy skoro vůbec).
const SWAY := {"grass": 0.14, "plant": 0.1, "fern": 0.09, "pbush": 0.06, "ancient": 0.03, "oak": 0.03, "pine": 0.02, "dead": 0.015}
var _foliage_shader: Shader
var _drip_tex: NoiseTexture2D

## Původní materiály modelů nahradí shaderem mokré vegetace (shaders/swamp_foliage.gdshader).
func _fix_materials(mesh: Mesh, key: String) -> void:
	if _foliage_shader == null:
		_foliage_shader = load("res://shaders/swamp_foliage.gdshader")
		_drip_tex = _noise_tex(256, 0.06, seed_used + 21)
	for s in mesh.get_surface_count():
		var m := mesh.surface_get_material(s)
		if m == null: continue
		if _materials_done.has(m):
			mesh.surface_set_material(s, _materials_done[m])
			continue
		if not (m is BaseMaterial3D):
			_materials_done[m] = m
			continue
		var bm := m as BaseMaterial3D
		var leaf := bm.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
		var rock := key == "rock" or key == "boulder"
		var sm := ShaderMaterial.new()
		sm.shader = _foliage_shader
		sm.set_shader_parameter("albedo_tex", bm.albedo_texture)
		sm.set_shader_parameter("albedo_color", bm.albedo_color)
		sm.set_shader_parameter("use_alpha", leaf)
		sm.set_shader_parameter("alpha_cut", 0.4)
		if bm.normal_enabled and bm.normal_texture:
			sm.set_shader_parameter("normal_tex", bm.normal_texture)
			sm.set_shader_parameter("has_normal", true)
		sm.set_shader_parameter("drip_noise", _drip_tex)
		sm.set_shader_parameter("leaf", 1.0 if leaf else 0.0)
		sm.set_shader_parameter("sway", float(SWAY.get(key, 0.0)) if leaf else 0.0)
		if rock:
			sm.set_shader_parameter("grade", Color(0.9, 0.9, 0.86))
			sm.set_shader_parameter("saturation", 0.75)
			sm.set_shader_parameter("bright", 0.7)
			sm.set_shader_parameter("base_rough", 0.6)
		elif leaf:
			# listí: zemitější, méně křiklavé (bažina, podzim, déšť)
			sm.set_shader_parameter("grade", Color(0.88, 0.9, 0.66))
			sm.set_shader_parameter("saturation", 0.78)
			sm.set_shader_parameter("bright", 0.72)
			sm.set_shader_parameter("base_rough", 0.55)
		else:
			# kůra: tmavá, nasáklá vodou (bílý suchý strom ztmavený, ať ve tmě nesvítí)
			sm.set_shader_parameter("grade", Color(0.82, 0.8, 0.74))
			sm.set_shader_parameter("saturation", 0.85)
			sm.set_shader_parameter("bright", 0.3 if key == "white" else 0.48)
			sm.set_shader_parameter("base_rough", 0.75)
		_materials_done[m] = sm
		mesh.surface_set_material(s, sm)

func _place(key: String, pos: Vector3, h: float, yaw: float, tilt := 0.0, vis := 80.0, shadow := true, variant := -1) -> Dictionary:
	var vs: Array = _variants[key]
	var v: Dictionary = vs[variant if variant >= 0 else rng.randi() % vs.size()]
	var b := Basis(Vector3.UP, yaw)
	if tilt != 0.0:
		var ang := rng.randf() * TAU
		b = Basis(Vector3(cos(ang), 0.0, sin(ang)), tilt) * b
	var xf := Transform3D(b * Basis.from_scale(Vector3.ONE * h), pos)
	var cell := Vector2i(floori(pos.x / CHUNK), floori(pos.z / CHUNK))
	var parts: Array = v.parts
	for i in parts.size():
		var mesh: Mesh = parts[i][0]
		var k := "%s|%d|%d|%d|%d" % [key, mesh.get_instance_id(), i, cell.x, cell.y]
		if not _batches.has(k):
			_batches[k] = {"mesh": mesh, "xf": [], "vis": vis, "shadow": shadow}
		_batches[k].xf.append(xf * (parts[i][1] as Transform3D))
	return v

func _flush_batches() -> void:
	var root := Node3D.new()
	root.name = "Vegetace"
	add_child(root)
	for k in _batches:
		var b: Dictionary = _batches[k]
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = b.mesh
		mm.instance_count = b.xf.size()
		for i in b.xf.size():
			mm.set_instance_transform(i, b.xf[i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		mmi.visibility_range_end = b.vis
		mmi.visibility_range_end_margin = b.vis * 0.1
		mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_ON if b.shadow else GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mmi)
	_batches.clear()

func _rand_point() -> Vector2:
	return Vector2(rng.randf_range(-R + 3.0, R - 3.0), rng.randf_range(-R + 3.0, R - 3.0))

func _tree_free(x: float, z: float) -> bool:
	return not _occupied.has(Vector2i(floori(x / 2.5), floori(z / 2.5)))

func _mark_tree(x: float, z: float) -> void:
	_occupied[Vector2i(floori(x / 2.5), floori(z / 2.5))] = true

func _add_trunk(pos: Vector3, r: float, h := 5.0) -> void:
	var cs := CollisionShape3D.new()
	var c := CylinderShape3D.new()
	c.radius = r
	c.height = h
	cs.shape = c
	cs.position = pos + Vector3(0, h * 0.5 - 0.3, 0)
	_colliders.add_child(cs)

## Rozmístí `count` kusů do výšek terénu [lo, hi]. Vrací počet umístěných.
func _scatter_kind(key: String, count: int, lo: float, hi: float, hmin: float, hmax: float, opts := {}) -> int:
	var placed := 0
	var tries := count * 12
	var is_tree: bool = opts.get("tree", false)
	while placed < count and tries > 0:
		tries -= 1
		var p := _rand_point()
		if opts.has("rim") and maxf(absf(p.x), absf(p.y)) < R - float(opts.rim): continue
		var gy := ground(p.x, p.y)
		if gy < lo or gy > hi: continue
		if _near_path(p.x, p.y) or _in_clearing(p.x, p.y, opts.get("clear", 9.0)): continue
		if is_tree and not _tree_free(p.x, p.y): continue
		var sz := rng.randf_range(hmin, hmax)
		var pos := Vector3(p.x, gy - float(opts.get("sink", 0.15)), p.y)
		_place(key, pos, sz, rng.randf() * TAU, rng.randf_range(-1.0, 1.0) * float(opts.get("tilt", 0.0)), opts.get("vis", 80.0), opts.get("shadow", true))
		if is_tree:
			_mark_tree(p.x, p.y)
			if opts.has("trunk"): _add_trunk(pos, float(opts.trunk) * sz / 10.0)
		placed += 1
	return placed

func _scatter() -> void:
	# stromy: mrtvé ve vodě a na mokřinách, staré pokroucené, pár bílých suchých, duby na sušších místech
	# (ve tmě a dešti se dohlédne jen pár metrů, ořez vzdálenosti proto může být krátký)
	_scatter_kind("dead", 330, -1.2, 0.8, 6.0, 12.0, {"tree": true, "tilt": 0.14, "vis": 90.0, "trunk": 0.35, "sink": 0.3, "clear": 4.0})
	_scatter_kind("ancient", 24, -1.0, 1.4, 6.0, 9.0, {"tree": true, "tilt": 0.05, "vis": 90.0, "trunk": 0.9, "sink": 0.25})
	_scatter_kind("white", 6, -1.0, 1.2, 7.0, 10.0, {"tree": true, "tilt": 0.08, "vis": 90.0, "trunk": 0.5})
	_scatter_kind("oak", 30, 0.05, 4.0, 10.0, 15.0, {"tree": true, "vis": 90.0, "trunk": 0.45, "clear": 4.0})
	_scatter_kind("pine", 45, 0.05, 6.0, 8.0, 15.0, {"tree": true, "vis": 90.0, "trunk": 0.25, "clear": 4.0})
	# keře a kapradí: na ostrůvcích a v mělčině
	_scatter_kind("fern", 140, -0.1, 2.0, 0.7, 1.3, {"vis": 30.0, "clear": 3.0})
	_scatter_kind("plant", 260, -0.15, 1.5, 0.35, 0.8, {"vis": 26.0, "clear": 3.0, "shadow": false})
	_scatter_kind("pbush", 200, -0.2, 4.0, 0.6, 1.5, {"vis": 40.0, "clear": 3.0, "sink": 0.0})
	# rákos a trávy: shluky všude ve vodě
	var clusters := 0
	var tries := 4000
	while clusters < 300 and tries > 0:
		tries -= 1
		var c := _rand_point()
		var gy := ground(c.x, c.y)
		if gy < -0.85 or gy > 0.3 or _in_clearing(c.x, c.y, 4.0): continue
		clusters += 1
		for i in rng.randi_range(8, 20):
			var p := c + Vector2.from_angle(rng.randf() * TAU) * rng.randf_range(0.0, 3.2)
			var py := ground(p.x, p.y)
			if py < -1.0 or py > 0.5 or _near_path(p.x, p.y): continue
			_place("grass", Vector3(p.x, maxf(py, WATER_Y - 0.5) - 0.05, p.y), rng.randf_range(0.8, 1.7), rng.randf() * TAU, rng.randf_range(-0.08, 0.08), 42.0, false)
	# kameny: velké balvany a menší oblázky
	var nb := 0
	tries = 400
	while nb < 22 and tries > 0:
		tries -= 1
		var p := _rand_point()
		var gy := ground(p.x, p.y)
		if gy < -0.8 or _near_path(p.x, p.y) or _in_clearing(p.x, p.y): continue
		var sz := rng.randf_range(1.1, 2.4)
		var pos := Vector3(p.x, gy - sz * 0.3, p.y)
		var v := _place("boulder", pos, sz, rng.randf() * TAU, 0.0, 110.0)
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(v.w * sz * 0.7, sz * 0.9, v.w * sz * 0.7)
		cs.shape = bs
		cs.position = pos + Vector3(0, sz * 0.45, 0)
		_colliders.add_child(cs)
		nb += 1
	# kameny čouhající z vody i na ostrůvcích
	_scatter_kind("rock", 280, -0.8, 3.0, 0.3, 1.0, {"vis": 32.0, "clear": 3.0, "sink": 0.1})

# =================================================================== lávka, bunkr, sudy, cedule

func _mat(key: String, meters: float, tint := Color.WHITE) -> StandardMaterial3D:
	var id := "%s_%.2f_%s" % [key, meters, tint.to_html()]
	if _mats.has(id): return _mats[id]
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(LM + key + "_albedo.jpg")
	m.normal_enabled = true
	m.normal_texture = load(LM + key + "_normal.jpg")
	m.roughness_texture = load(LM + key + "_rough.jpg")
	m.albedo_color = tint
	m.uv1_triplanar = true
	m.uv1_world_triplanar = true
	m.uv1_scale = Vector3.ONE / meters
	_mats[id] = m
	return m

func _build_boardwalk() -> void:
	var wood := _mat("old_wood", 1.6, Color(0.62, 0.58, 0.52))
	var plank := BoxMesh.new()
	plank.size = Vector3(1.5, 0.05, 0.24)
	plank.material = wood
	var post := BoxMesh.new()
	post.size = Vector3(0.12, 1.0, 0.12)
	post.material = wood
	var planks := []
	var posts := []
	var root := StaticBody3D.new()
	root.name = "Lavka"
	add_child(root)
	# vzdálenost podél cesty
	var acc := 0.0
	var next_plank := 0.0
	var next_post := 0.0
	var seg_start := -1
	var tops := []
	for i in range(1, path.size()):
		var p0 := path[i - 1]
		var p1 := path[i]
		var d := p0.distance_to(p1)
		var dir := (p1 - p0) / d
		while next_plank <= acc + d:
			var t := (next_plank - acc) / d
			var p := p0.lerp(p1, t)
			var gy := ground(p.x, p.y)
			var top := maxf(gy + 0.08, WATER_Y + 0.26 + detail.get_noise_2d(p.x * 3.0, p.y * 3.0) * 0.06)
			# z lávky zbyly jen kusy (mezi nimi se brodí)
			var piece := detail.get_noise_2d(next_plank * 0.06, 77.0) > 0.05
			if gy < 0.3 and piece:
				tops.append([p, dir, top])
				if rng.randf() > 0.06:
					var yaw := atan2(dir.x, dir.y)
					var b := Basis(Vector3.UP, yaw)
					b = Basis(b.z, rng.randf_range(-0.05, 0.05)) * b
					planks.append(Transform3D(b, Vector3(p.x, top - 0.025, p.y)))
				if next_plank >= next_post:
					next_post = next_plank + 1.8
					var side := Vector2(-dir.y, dir.x) * 0.68
					for sgn in [-1.0, 1.0]:
						var q: Vector2 = p + side * sgn
						var bot := ground(q.x, q.y) - 0.4
						var len := top - bot + rng.randf_range(0.05, 0.4)
						posts.append(Transform3D(Basis.from_scale(Vector3(1, len, 1)), Vector3(q.x, bot + len * 0.5, q.y)))
			next_plank += 0.3
		acc += d
	# kolize lávky: kvádry po 1.5 m podél prken
	for i in range(0, tops.size(), 5):
		var p: Vector2 = tops[i][0]
		var j := mini(i + 5, tops.size() - 1)
		var q: Vector2 = tops[j][0]
		var mid := (p + q) * 0.5
		if p.distance_to(q) > 1.9:      # mezera mezi kusy lávky: jen krátký kus
			q = p
			mid = p
		var len := maxf(p.distance_to(q), 0.3) + 0.3
		var dir: Vector2 = (q - p).normalized() if q != p else tops[i][1]
		var top: float = (tops[i][2] + tops[j][2]) * 0.5
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = Vector3(1.5, 0.3, len)
		cs.shape = bs
		cs.transform = Transform3D(Basis(Vector3.UP, atan2(dir.x, dir.y)), Vector3(mid.x, top - 0.15, mid.y))
		root.add_child(cs)
	for pair in [[plank, planks], [post, posts]]:
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = pair[0]
		mm.instance_count = pair[1].size()
		for i in pair[1].size(): mm.set_instance_transform(i, pair[1][i])
		var mmi := MultiMeshInstance3D.new()
		mmi.multimesh = mm
		root.add_child(mmi)

func _box(parent: Node3D, size: Vector3, pos: Vector3, mat: Material, collide := true, rot := Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	bm.material = mat
	mi.mesh = bm
	mi.position = pos
	mi.rotation = rot
	parent.add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		bs.size = size
		cs.shape = bs
		body.add_child(cs)
		mi.add_child(body)
	return mi

func _build_bunker() -> void:
	var root := Node3D.new()
	root.name = "Bunkr"
	add_child(root)
	var gy := ground(goal.x, goal.z)
	root.position = Vector3(goal.x, gy - 0.6, goal.z)
	root.rotation.y = atan2(spawn.x - goal.x, spawn.z - goal.z)
	var con := _mat("peeling_paint", 2.5, Color(0.3, 0.32, 0.27))
	var rust := _mat("rusty_metal", 1.5)
	var W := 7.0
	var D := 5.5
	var H := 3.3
	var t := 0.45
	var fy := 0.6
	_box(root, Vector3(W, 0.3, D), Vector3(0, fy - 0.15, 0), con)
	_box(root, Vector3(W, H, t), Vector3(0, fy + H * 0.5, -D * 0.5 + t * 0.5), con)
	_box(root, Vector3(t, H, D), Vector3(-W * 0.5 + t * 0.5, fy + H * 0.5, 0), con)
	_box(root, Vector3(t, H, D), Vector3(W * 0.5 - t * 0.5, fy + H * 0.5, 0), con)
	var dw := 1.4
	var side := (W - dw) * 0.5
	_box(root, Vector3(side, H, t), Vector3(-(dw * 0.5 + side * 0.5), fy + H * 0.5, D * 0.5 - t * 0.5), con)
	_box(root, Vector3(side, H, t), Vector3(dw * 0.5 + side * 0.5, fy + H * 0.5, D * 0.5 - t * 0.5), con)
	_box(root, Vector3(dw, H - 2.3, t), Vector3(0, fy + 2.3 + (H - 2.3) * 0.5, D * 0.5 - t * 0.5), con)
	_box(root, Vector3(W + 0.6, 0.45, D + 0.6), Vector3(0, fy + H + 0.22, 0), con)
	# pootevřené rezavé dveře
	var hinge := Node3D.new()
	hinge.position = Vector3(-dw * 0.5, fy, D * 0.5)
	hinge.rotation.y = deg_to_rad(-72.0)
	root.add_child(hinge)
	_box(hinge, Vector3(1.32, 2.2, 0.06), Vector3(0.66, 1.1, 0.04), rust)
	# červené světlo nad vchodem (bliká)
	var lm := StandardMaterial3D.new()
	lm.albedo_color = Color(0.3, 0.02, 0.02)
	lm.emission_enabled = true
	lm.emission = Color(1.0, 0.08, 0.05)
	lm.emission_energy_multiplier = 4.0
	_red_mesh = _box(root, Vector3(0.22, 0.14, 0.12), Vector3(0, fy + 2.55, D * 0.5 + 0.06), lm, false)
	_red_lamp = OmniLight3D.new()
	_red_lamp.light_color = Color(1.0, 0.12, 0.06)
	_red_lamp.light_energy = 1.6
	_red_lamp.omni_range = 7.0
	_red_lamp.shadow_enabled = true
	_red_lamp.light_volumetric_fog_energy = 2.5
	_red_lamp.position = Vector3(0, fy + 2.45, D * 0.5 + 0.35)
	root.add_child(_red_lamp)
	# uvnitř: zelený svit z rozbité nádrže (náznak experimentu)
	var g := OmniLight3D.new()
	g.light_color = Color(0.35, 1.0, 0.45)
	g.light_energy = 0.9
	g.omni_range = 5.0
	g.position = Vector3(1.6, fy + 0.6, -1.4)
	root.add_child(g)
	var pm := StandardMaterial3D.new()
	pm.albedo_color = Color(0.05, 0.2, 0.06)
	pm.emission_enabled = true
	pm.emission = Color(0.3, 1.0, 0.35)
	pm.emission_energy_multiplier = 1.6
	pm.roughness = 0.1
	var puddle := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 1.1
	cyl.bottom_radius = 1.1
	cyl.height = 0.01
	cyl.material = pm
	puddle.mesh = cyl
	puddle.position = Vector3(1.4, fy + 0.01, -1.2)
	puddle.scale = Vector3(1.0, 1.0, 0.7)
	root.add_child(puddle)

var _barrel_mesh: CylinderMesh
var _barrel_mesh2: CylinderMesh

func _barrel(pos: Vector3, tipped := false, yaw := 0.0, collide := true) -> Node3D:
	if _barrel_mesh == null:
		_barrel_mesh = CylinderMesh.new()
		_barrel_mesh.top_radius = 0.29
		_barrel_mesh.bottom_radius = 0.29
		_barrel_mesh.height = 0.88
		_barrel_mesh.material = _mat("rusty_metal", 1.0)
		_barrel_mesh2 = _barrel_mesh.duplicate()
		_barrel_mesh2.material = _mat("painted_metal", 1.2, Color(0.36, 0.4, 0.24))
	var mi := MeshInstance3D.new()
	mi.mesh = _barrel_mesh if rng.randf() < 0.6 else _barrel_mesh2
	mi.position = pos + Vector3(0, 0.29 if tipped else 0.44, 0)
	mi.rotation = Vector3(0, yaw, PI * 0.5 + rng.randf_range(-0.1, 0.1) if tipped else rng.randf_range(-0.06, 0.06))
	add_child(mi)
	if collide:
		var body := StaticBody3D.new()
		var cs := CollisionShape3D.new()
		var c := CylinderShape3D.new()
		c.radius = 0.29
		c.height = 0.88
		cs.shape = c
		body.add_child(cs)
		mi.add_child(body)
	return mi

func _build_barrels() -> void:
	# hromádka u bunkru
	var fwd := Vector2(spawn.x - goal.x, spawn.z - goal.z).normalized()
	var right := Vector2(fwd.y, -fwd.x)
	for i in 9:
		var p := Vector2(goal.x, goal.z) + right * rng.randf_range(4.5, 7.0) * (1.0 if i < 5 else -1.0) + fwd * rng.randf_range(-2.0, 2.5)
		_barrel(Vector3(p.x, ground(p.x, p.y), p.y), rng.randf() < 0.3, rng.randf() * TAU)
	# rozházené v bažině: napůl potopené, nakloněné
	var n := 0
	var tries := 600
	while n < 14 and tries > 0:
		tries -= 1
		var p := _rand_point()
		var gy := ground(p.x, p.y)
		if gy < -0.7 or gy > 0.2 or _near_path(p.x, p.y): continue
		var b := _barrel(Vector3(p.x, gy - 0.25, p.y), rng.randf() < 0.5, rng.randf() * TAU, false)
		b.rotation.x += rng.randf_range(-0.35, 0.35)
		n += 1
		# některé ještě prosakují: zelený svit na hladině
		if n % 5 == 0:
			var gl := OmniLight3D.new()
			gl.light_color = Color(0.4, 1.0, 0.4)
			gl.light_energy = 0.5
			gl.omni_range = 3.5
			gl.light_volumetric_fog_energy = 0.3
			gl.position = Vector3(p.x, WATER_Y + 0.3, p.y)
			add_child(gl)

func _sign(pos: Vector3, yaw: float) -> void:
	var root := Node3D.new()
	root.position = pos
	root.rotation.y = yaw
	add_child(root)
	var wood := _mat("old_wood", 1.0, Color(0.5, 0.46, 0.4))
	_box(root, Vector3(0.09, 1.9, 0.09), Vector3(0, 0.95, -0.05), wood)
	var q := MeshInstance3D.new()
	var qm := QuadMesh.new()
	qm.size = Vector2(0.9, 0.56)
	var m := StandardMaterial3D.new()
	m.albedo_texture = load(TX + "sign_zakaz.jpg")
	m.roughness = 0.7
	qm.material = m
	q.mesh = qm
	q.position = Vector3(0, 1.55, 0.0)
	q.rotation.z = rng.randf_range(-0.12, 0.12)
	root.add_child(q)
	_box(root, Vector3(0.92, 0.58, 0.02), Vector3(0, 1.55, -0.015), _mat("rusty_metal", 1.0), false, Vector3(0, 0, q.rotation.z))

func _build_signs() -> void:
	for t in [0.06, 0.5, 0.93]:
		var i := clampi(int(t * path.size()), 1, path.size() - 2)
		var p := path[i]
		var dir := (path[i + 1] - path[i - 1]).normalized()
		var side := Vector2(-dir.y, dir.x) * 1.4
		var q := p + side
		# cedule kouká proti příchozímu
		_sign(Vector3(q.x, ground(q.x, q.y) - 0.1, q.y), atan2(-dir.x, -dir.y))

func _build_bounds() -> void:
	var body := StaticBody3D.new()
	body.name = "Okraj"
	add_child(body)
	for i in 4:
		var cs := CollisionShape3D.new()
		var bs := BoxShape3D.new()
		var horiz := i < 2
		bs.size = Vector3(2.0 * R + 4.0 if horiz else 2.0, 30.0, 2.0 if horiz else 2.0 * R + 4.0)
		cs.shape = bs
		var s := 1.0 if i % 2 == 0 else -1.0
		cs.position = Vector3(0.0 if horiz else s * (R - 2.0), 10.0, s * (R - 2.0) if horiz else 0.0)
		body.add_child(cs)

# =================================================================== bludičky

func _build_wisps() -> void:
	var sm := SphereMesh.new()
	sm.radius = 0.07
	sm.height = 0.14
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(0.7, 1.0, 0.95)
	m.emission_enabled = true
	m.emission = Color(0.5, 1.0, 0.9)
	m.emission_energy_multiplier = 5.0
	sm.material = m
	var n := 0
	var tries := 500
	while n < 3 and tries > 0:
		tries -= 1
		var p := _rand_point()
		if ground(p.x, p.y) > -0.3: continue
		if Vector2(p.x - spawn.x, p.y - spawn.z).length() < 25.0: continue
		var root := Node3D.new()
		var l := OmniLight3D.new()
		l.light_color = Color(0.55, 0.95, 0.88)
		l.light_energy = 0.9
		l.omni_range = 7.0
		l.light_volumetric_fog_energy = 0.6
		root.add_child(l)
		var mi := MeshInstance3D.new()
		mi.mesh = sm
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		root.add_child(mi)
		add_child(root)
		_wisps.append({"node": root, "light": l, "c": Vector3(p.x, 0.0, p.y), "ph": rng.randf() * TAU, "a": 1.0})
		n += 1

# =================================================================== zvuk

func _loop(s: AudioStream) -> AudioStream:
	if s is AudioStreamWAV:
		var w := s as AudioStreamWAV
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = int(w.get_length() * w.mix_rate)
	return s

func _build_sound() -> void:
	var bed := AudioStreamPlayer.new()
	bed.stream = _loop(load("res://audio/swamp/night_bed.wav"))
	bed.volume_db = -17.0
	bed.autoplay = true
	add_child(bed)
	var rain := AudioStreamPlayer.new()
	rain.stream = _loop(load("res://audio/amb_rain.wav"))
	rain.volume_db = -4.0
	rain.autoplay = true
	add_child(rain)
	if THUNDER:
		for i in range(1, 4): _thunders.append(load("res://audio/thunder_%d.wav" % i))
	var frog: AudioStream = _loop(load("res://audio/swamp/frog_loop.wav"))
	var n := 0
	var tries := 600
	while n < 7 and tries > 0:
		tries -= 1
		var p := _rand_point()
		var gy := ground(p.x, p.y)
		if gy < -0.3 or gy > 0.15: continue
		var a := AudioStreamPlayer3D.new()
		a.stream = frog
		a.pitch_scale = rng.randf_range(0.8, 1.25)
		a.volume_db = -3.0
		a.unit_size = 5.0
		a.max_distance = 45.0
		a.position = Vector3(p.x, WATER_Y + 0.2, p.y)
		a.autoplay = true
		add_child(a)
		a.play(rng.randf() * 10.0)
		n += 1
	for i in range(1, 5): _steps_mud.append(load("res://audio/swamp/step_mud_%d.wav" % i))
	for i in range(1, 7): _steps_water.append(load("res://audio/step_water_%d.wav" % i))
	for i in range(1, 5): _swims.append(load("res://audio/swim_%d.wav" % i))
	for i in range(1, 4): _cracks.append(load("res://audio/swamp/branch_crack_%d.wav" % i))

func _on_footstep(kind: String, strength: float) -> void:
	var a := AudioStreamPlayer.new()
	match kind:
		"water":
			a.stream = _steps_water.pick_random()
			a.volume_db = -12.0
		"swim":
			a.stream = _swims.pick_random()
			a.volume_db = -10.0
		_:
			# na lávce dřevo (tlumené dlaždice), jinde bláto
			if player and _on_boardwalk():
				a.stream = load("res://audio/step_tile_%d.wav" % rng.randi_range(1, 6))
				a.pitch_scale = 0.55
				a.volume_db = -16.0
			else:
				a.stream = _steps_mud.pick_random()
				a.volume_db = -13.0
	a.volume_db += linear_to_db(maxf(strength, 0.1)) * 0.5
	if a.pitch_scale == 1.0: a.pitch_scale = rng.randf_range(0.9, 1.08)
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)

func _on_boardwalk() -> bool:
	var p := player.global_position
	return _near_path(p.x, p.z) and p.y > ground(p.x, p.z) + 0.05

func _on_splash(strength: float) -> void:
	var a := AudioStreamPlayer.new()
	a.stream = load("res://audio/splash_big_%d.wav" % rng.randi_range(1, 2))
	a.volume_db = -10.0 + linear_to_db(clampf(strength, 0.1, 1.5))
	add_child(a)
	a.play()
	a.finished.connect(a.queue_free)

# =================================================================== hráč, baterka, HUD

func _load_settings() -> void:
	var cf := ConfigFile.new()
	if cf.load("user://settings.cfg") == OK:
		for k in ["mouse", "fov", "volume", "bob", "bodycam_blur"]:
			if cf.has_section_key("s", k): settings[k] = float(cf.get_value("s", k))
	AudioServer.set_bus_volume_db(0, linear_to_db(maxf(float(settings.volume), 0.001)))

## Kužel baterky jako u skutečné svítilny: horké jádro, světlejší kroužek od reflektoru,
## měkký okraj a drobné nerovnosti skla.
func _flash_cookie() -> ImageTexture:
	var n := 256
	var img := Image.create(n, n, false, Image.FORMAT_RGB8)
	var fn := FastNoiseLite.new()
	fn.frequency = 0.05
	for y in n:
		for x in n:
			var d := Vector2(x - n * 0.5 + 0.5, y - n * 0.5 + 0.5).length() / (n * 0.5)
			var core := exp(-d * d * 4.5)
			var ring := exp(-pow((d - 0.5) / 0.08, 2.0)) * 0.3
			var halo := (1.0 - smoothstep(0.4, 1.0, d)) * 0.45
			var v := (core + ring + halo) * (0.92 + 0.08 * fn.get_noise_2d(x, y))
			v *= 1.0 - smoothstep(0.88, 1.0, d)
			img.set_pixel(x, y, Color(v, v, v))
	return ImageTexture.create_from_image(img)

func _make_flashlight(parent: Node3D) -> void:
	flashlight = SpotLight3D.new()
	flashlight.position = Vector3(0.12, -0.12, -0.1)
	flashlight.light_color = Color(1.0, 0.9, 0.76)
	# dosvítí jen pár metrů, pak se kužel ztratí v mlze a tmě
	flashlight.light_energy = 16.0
	flashlight.spot_range = 17.0
	flashlight.spot_angle = 36.0
	flashlight.spot_angle_attenuation = 0.5
	flashlight.spot_attenuation = 1.9
	flashlight.light_projector = _flash_cookie()
	flashlight.shadow_enabled = true
	flashlight.shadow_blur = 1.2
	flashlight.shadow_caster_mask = 0xFFFFF & ~(4 | 8)
	flashlight.light_volumetric_fog_energy = 0.3
	flashlight.light_specular = 0.8
	parent.add_child(flashlight)
	# kapky deště v kuželu: kolem baterky se rozzáří, dál zmizí ve tmě
	var spill := SpotLight3D.new()
	spill.light_color = flashlight.light_color
	spill.light_energy = 0.3
	spill.spot_range = 7.0
	spill.spot_angle = 55.0
	spill.spot_angle_attenuation = 1.5
	spill.light_volumetric_fog_energy = 0.0
	spill.shadow_enabled = false
	flashlight.add_child(spill)

## Cákance kapek na hladině kolem hráče (osvětlené baterkou).
var _splash: GPUParticles3D

func _build_splashes() -> void:
	var qm := QuadMesh.new()
	qm.size = Vector2(0.014, 0.02)
	var m := StandardMaterial3D.new()
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(0.5, 0.52, 0.54, 0.3)
	m.roughness = 0.2
	qm.material = m
	var pm := ParticleProcessMaterial.new()
	pm.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	pm.emission_box_extents = Vector3(6.0, 0.0, 6.0)
	pm.direction = Vector3(0, 1, 0)
	pm.spread = 30.0
	pm.initial_velocity_min = 0.5
	pm.initial_velocity_max = 1.2
	pm.gravity = Vector3(0, -9.0, 0)
	var c := Curve.new()
	c.add_point(Vector2(0.0, 1.0))
	c.add_point(Vector2(1.0, 0.2))
	var ct := CurveTexture.new()
	ct.curve = c
	pm.scale_curve = ct
	_splash = GPUParticles3D.new()
	_splash.amount = 700
	_splash.lifetime = 0.16
	_splash.local_coords = false
	_splash.process_material = pm
	_splash.draw_pass_1 = qm
	_splash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_splash.visibility_aabb = AABB(Vector3(-10, -1, -10), Vector3(20, 3, 20))
	_splash.position = Vector3(spawn.x, WATER_Y + 0.02, spawn.z)
	add_child(_splash)

# ------------------------------------------------------------------ postproces: bodycam a VHS

var cam_attr: CameraAttributesPractical
var post_mat: ShaderMaterial
var bodycam: Node
var vhs_on := true
var _vhs := 1.0
var _osd: Control
var _osd_time: Label
var _osd_sp: Label

func _osd_label(parent: Node, text: String, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l

func _build_post() -> void:
	cam_attr = CameraAttributesPractical.new()
	cam_attr.dof_blur_far_enabled = true
	cam_attr.dof_blur_far_distance = 18.0
	cam_attr.dof_blur_far_transition = 22.0
	cam_attr.dof_blur_near_enabled = true
	cam_attr.dof_blur_near_distance = 0.28
	cam_attr.dof_blur_near_transition = 0.25
	cam_attr.dof_blur_amount = 0.06
	cam.attributes = cam_attr
	# OSD videokamery (pod postprocesem, deformuje se s obrazem)
	var osd_layer := CanvasLayer.new()
	osd_layer.layer = 5
	add_child(osd_layer)
	_osd = Control.new()
	_osd.set_anchors_preset(Control.PRESET_FULL_RECT)
	_osd.mouse_filter = Control.MOUSE_FILTER_IGNORE
	osd_layer.add_child(_osd)
	_osd_label(_osd, "PLAY ►", 46).position = Vector2(230, 150)
	_osd_sp = _osd_label(_osd, "SP", 46)
	_osd_time = _osd_label(_osd, "", 46)
	var post_layer := CanvasLayer.new()
	post_layer.layer = 10
	add_child(post_layer)
	var rect := ColorRect.new()
	rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	post_mat = ShaderMaterial.new()
	post_mat.shader = load("res://shaders/post.gdshader")
	post_mat.set_shader_parameter("grain", 0.05)
	post_mat.set_shader_parameter("vignette", 0.42)
	post_mat.set_shader_parameter("vhs", _vhs)
	rect.material = post_mat
	post_layer.add_child(rect)
	if player:
		# BODYCAM (experiment, scripts/bodycam.gd): kamera na helmě, zapnutá od začátku
		bodycam = load("res://scripts/bodycam.gd").new()
		add_child(bodycam)
		bodycam.setup(self, rect, post_mat)
		player.cam_fx = bodycam
		_set_bodycam(bool(settings.bodycam))
		# VISOR (experiment, scripts/visor.gd): hledí helmy, na které postupně napadá déšť; otírá se klávesou H
		visor = load("res://scripts/visor.gd").new()
		add_child(visor)
		visor.setup(self, post_layer, player)
		visor.set_enabled(true)
		visor.auto_wipe = false
		visor.mat.set_shader_parameter("dark_drops", 1.0)

## Bodycam s vlastní expozicí pro bažinu: ve tmě obraz nezesvětluje (tma má zůstat tmou).
func _set_bodycam(v: bool) -> void:
	if bodycam == null: return
	bodycam.set_enabled(v)
	if v and cam_attr:
		cam_attr.auto_exposure_scale = 0.12
		cam_attr.auto_exposure_min_sensitivity = 50.0
		cam_attr.auto_exposure_max_sensitivity = 80.0

# ------------------------------------------------------------------ cáry mlhy

## Hustší chuchvalce mlhy, které pomalu putují kolem hráče. Ve tmě nejsou vidět,
## ukáže je až baterka (nebo blesk).
var _mists := []

func _build_mist_banks() -> void:
	for i in 14:
		var fv := FogVolume.new()
		fv.shape = RenderingServer.FOG_VOLUME_SHAPE_ELLIPSOID
		fv.size = Vector3(rng.randf_range(7.0, 16.0), rng.randf_range(1.2, 2.6), rng.randf_range(7.0, 16.0))
		var fm := FogMaterial.new()
		fm.density = rng.randf_range(0.12, 0.28)
		fm.albedo = Color(0.42, 0.45, 0.46)
		fm.height_falloff = 0.6
		fm.edge_fade = 0.9
		fv.material = fm
		var a := rng.randf() * TAU
		var d := rng.randf_range(4.0, 30.0)
		fv.position = spawn + Vector3(cos(a) * d, 0.7, sin(a) * d)
		add_child(fv)
		_mists.append({"node": fv, "v": Vector3(cos(a + 1.3), 0, sin(a + 1.3)) * rng.randf_range(0.15, 0.4), "ph": rng.randf() * TAU})

func _update_mists(dt: float, eye: Vector3) -> void:
	for m in _mists:
		var fv: FogVolume = m.node
		fv.position += (m.v as Vector3) * dt
		fv.position.y = 0.7 + sin(_time * 0.2 + m.ph) * 0.25
		# daleko od hráče: přesune se zase kousek před něj (náhodně kolem)
		var off := fv.position - eye
		off.y = 0.0
		if off.length() > 34.0:
			var a := rng.randf() * TAU
			fv.position = eye + Vector3(cos(a), 0, sin(a)) * rng.randf_range(10.0, 26.0)


# ------------------------------------------------------------------ déšť na hledí

var visor: Node
const VISOR_FULL := 40.0          # za kolik sekund deště je hledí úplně pokapané
var _visor_seen_wipes := 0
var _visor_hint_t := 0.0

## Kapky deště na hledí: přibývají postupně (víc a víc kapek, větší stékají dolů).
## Po otření (H) se sklo vyčistí a začne pršet na čisté.
func _update_visor_rain(dt: float) -> void:
	if visor == null or not visor.active(): return
	var rig: Node = player.body.weapon if player.body else null
	var wiping: bool = rig != null and float(rig.wipe) > 0.0
	if visor._wipes != _visor_seen_wipes and not wiping:
		# otření doběhlo: nová vrstva kapek začíná od nuly
		_visor_seen_wipes = visor._wipes
		visor._wet = 0.0
		visor._wet_k = float(visor._wipes)
		visor._wet_seed = rng.randf() * 100.0
		visor._wet_t = visor._now
	if not wiping and not player.swimming:
		# visor sám kapky pomalu suší (dt / 22), déšť přidává rychleji
		visor._wet = minf(1.0, visor._wet + dt / 22.0 + dt / VISOR_FULL)
		visor._dirty_t = visor._now
	_visor_hint_t -= dt
	if visor._wet > 0.6 and _visor_hint_t <= 0.0 and _toast_t <= 0.0:
		_visor_hint_t = 45.0
		_say("Hledí je celé od deště. H = otřít.")


## Test hledí (SWAMP_VISOR_TEST=1 a SWAMP_OUT): rychle napadá déšť, snímek, otření, snímky, konec.
var _visor_test := OS.get_environment("SWAMP_VISOR_TEST") == "1"
var _vt_step := 0

func _run_visor_test() -> void:
	if visor == null: return
	var out := OS.get_environment("SWAMP_OUT")
	if _time < 5.0:
		visor._wet = minf(1.0, visor._wet + 0.02)
	var marks := [5.0, 5.35, 5.7, 7.5]
	if _vt_step < marks.size() and _time >= marks[_vt_step]:
		if _vt_step == 0:
			get_viewport().get_texture().get_image().save_png(out + "/visor_0.png")
			visor.wipe()
		else:
			get_viewport().get_texture().get_image().save_png(out + "/visor_%d.png" % _vt_step)
		_vt_step += 1
		if _vt_step == marks.size(): get_tree().quit()


func _update_post(dt: float) -> void:
	if post_mat == null: return
	_vhs = move_toward(_vhs, 1.0 if vhs_on else 0.0, dt * 2.5)
	post_mat.set_shader_parameter("vhs", _vhs)
	if player: player.handheld = _vhs
	_osd.visible = _vhs > 0.5
	if _osd.visible:
		var d := Time.get_datetime_dict_from_system()
		var months := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
		# na kazetě je pořád rok 1994
		var h: int = d.hour % 12
		_osd_time.text = "%s %d:%02d\n%s. %d %d" % ["PM" if d.hour >= 12 else "AM", 12 if h == 0 else h, d.minute, months[d.month - 1], d.day, 1994]
	var vs := get_viewport().get_visible_rect().size
	var sc := vs.y / 1080.0
	_osd.scale = Vector2(sc, sc)
	_osd_sp.position = Vector2(vs.x / sc - 330.0, 150.0)
	_osd_time.position = Vector2(230.0, 1080.0 - 290.0)
	cam_attr.dof_blur_amount = lerpf(0.06, 0.085, _vhs)

func _spawn_y() -> float:
	return ground(spawn.x, spawn.z) + 0.05

func _build_player() -> void:
	var look_at_goal := atan2(-(goal.x - spawn.x), -(goal.z - spawn.z))
	if OS.get_environment("SWAMP_NOPLAYER") == "1":
		cam = Camera3D.new()
		cam.fov = float(settings.fov)
		cam.far = 400.0
		add_child(cam)
		cam.current = true
		cam.position = Vector3(spawn.x, _spawn_y() + 1.65, spawn.z)
		cam.rotation = Vector3(-0.05, look_at_goal, 0)
		_make_flashlight(cam)
		return
	var P := preload("res://scripts/player.gd")
	preload("res://scripts/weapon_rig.gd").skip_gun_models = true
	P.water_at = func(_p: Vector3) -> float: return WATER_Y
	player = P.new()
	player.sim = sim        # brodění dělá vlny na hladině
	add_child(player)
	player.mouse_scale = float(settings.mouse)
	player.base_fov = float(settings.fov)
	player.bob_scale = float(settings.bob)
	player.teleport(Vector3(spawn.x, _spawn_y(), spawn.z), look_at_goal, -0.05)
	cam = player.camera
	cam.far = 400.0
	for f in ["set_process", "set_physics_process", "set_process_input", "set_process_unhandled_input"]:
		player.weapon.call(f, false)
	player.footstep.connect(_on_footstep)
	player.splashed.connect(_on_splash)
	_make_flashlight(cam)
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	get_tree().create_timer(0.2).timeout.connect(func(): Input.mouse_mode = Input.MOUSE_MODE_CAPTURED)

func _exit_tree() -> void:
	preload("res://scripts/weapon_rig.gd").skip_gun_models = false
	preload("res://scripts/player.gd").water_at = Callable()

func _build_hud() -> void:
	var cl := CanvasLayer.new()
	cl.layer = 20            # nad postprocesem (VHS / bodycam)
	add_child(cl)
	_toast = Label.new()
	_toast.set_anchors_preset(Control.PRESET_CENTER_TOP)       # nahoře: dole je datum VHS
	_toast.position = Vector2(-450, 90)
	_toast.size = Vector2(900, 40)
	_toast.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_toast.add_theme_font_size_override("font_size", 22)
	_toast.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	_toast.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(_toast)
	var dot := ColorRect.new()
	dot.color = Color(1, 1, 1, 0.4)
	dot.size = Vector2(3, 3)
	dot.set_anchors_preset(Control.PRESET_CENTER)
	dot.position = Vector2(-1.5, -1.5)
	dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cl.add_child(dot)
	if OS.get_environment("SWAMP_SHOTS") == "":
		_say("Bažina (prototyp). Najdi bunkr s červeným světlem. F baterka, H otřít hledí, V VHS, B bodycam, Esc menu.")

func _say(t: String) -> void:
	_toast.text = t
	_toast_t = 6.0

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and Input.mouse_mode != Input.MOUSE_MODE_CAPTURED:
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	elif event is InputEventKey and event.pressed and not event.echo:
		match event.physical_keycode:
			KEY_ESCAPE:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
				get_tree().change_scene_to_file("res://main.tscn")
			KEY_H:
				if visor and visor.enabled: visor.wipe()
			KEY_V:
				vhs_on = not vhs_on
				_say("VHS kamera: " + ("zapnuto" if vhs_on else "vypnuto"))
			KEY_B:
				settings.bodycam = not bool(settings.bodycam)
				_set_bodycam(bool(settings.bodycam))
				_say("Bodycam (experiment): " + ("zapnuto" if settings.bodycam else "vypnuto"))
			KEY_F:
				if flashlight:
					flashlight.visible = not flashlight.visible
					var a := AudioStreamPlayer.new()
					a.stream = load("res://audio/lamp_click.wav")
					a.volume_db = -8.0
					add_child(a)
					a.play()
					a.finished.connect(a.queue_free)

func _process(dt: float) -> void:
	_time += dt
	if _toast_t > 0.0:
		_toast_t -= dt
		_toast.modulate.a = clampf(_toast_t, 0.0, 1.0)
	# červené světlo u bunkru: nepravidelně pomrkává
	if _red_lamp:
		var f := 1.0 if fmod(_time, 3.7) > 0.25 else 0.2
		if fmod(_time * 7.3, 5.0) < 0.12: f = 0.05
		_red_lamp.light_energy = 1.6 * f
		(_red_mesh.mesh.surface_get_material(0) as StandardMaterial3D).emission_energy_multiplier = 4.0 * f
	var eye := cam.global_position if cam else spawn
	if _rain:
		_rain.global_position = eye + Vector3(0, 11.0, 0)
	if _splash:
		_splash.global_position = Vector3(eye.x, WATER_Y + 0.02, eye.z)
	_update_post(dt)
	_update_mists(dt, eye)
	_update_visor_rain(dt)
	if _visor_test: _run_visor_test()
	# bouřka: občas blesk v dálce, hrom se zpožděním
	if THUNDER:
		_thunder_t -= dt
		if _thunder_t <= 0.0:
			_thunder_t = rng.randf_range(40.0, 100.0)
			_lightning()
		if _flash_t >= 0.0:
			_flash_t += dt
			var f := _flash_level()
			_moon.light_energy = f * 0.5
			_sky_mat.set_shader_parameter("flash", f * 0.4)
			_env.ambient_light_energy = 0.1 + f * 0.25
	# bludičky: pomalu krouží nad vodou a zhasnou, když se přiblížíš
	for w in _wisps:
		var t: float = _time * 0.25 + w.ph
		var c: Vector3 = w.c
		var p := c + Vector3(sin(t) * 4.0 + sin(t * 2.3) * 1.5, 0.7 + sin(t * 1.7) * 0.25, cos(t * 0.8) * 4.0)
		(w.node as Node3D).position = p
		var target := 0.0 if eye.distance_to(p) < 11.0 else 1.0
		w.a = move_toward(w.a, target, dt * 0.6)
		(w.light as OmniLight3D).light_energy = 0.9 * w.a * (0.85 + 0.15 * sin(_time * 9.0 + w.ph))
		(w.node as Node3D).visible = w.a > 0.02
	# praskání větví v dálce (za zády)
	_crack_t -= dt
	if _crack_t <= 0.0 and cam:
		_crack_t = rng.randf_range(18.0, 45.0)
		var back := cam.global_basis.z
		var dir := Vector3(back.x, 0, back.z).normalized().rotated(Vector3.UP, rng.randf_range(-1.0, 1.0))
		var a := AudioStreamPlayer3D.new()
		a.stream = _cracks.pick_random()
		a.position = eye + dir * rng.randf_range(10.0, 22.0)
		a.unit_size = 8.0
		a.volume_db = 2.0
		add_child(a)
		a.play()
		a.finished.connect(a.queue_free)
	# cíl
	if player and not _goal_said and player.global_position.distance_to(goal) < 6.0:
		_goal_said = true
		_say("Bunkr. Dveře jsou pootevřené a uvnitř něco zeleně svítí… (pokračování příště)")

# =================================================================== náhledy

## SWAMP_SHOTS="spawn;goal;x,z,yaw,pitch;..." uloží PNG do SWAMP_OUT (výchozí user://).
func _run_shots() -> void:
	var out := OS.get_environment("SWAMP_OUT")
	if out == "": out = OS.get_user_data_dir()
	var list := OS.get_environment("SWAMP_SHOTS").split(";")
	var i := 0
	for s0 in list:
		var lit := s0.ends_with("!")        # "!" na konci = snímek ve chvíli blesku
		var s := s0.trim_suffix("!")
		var force_pitch := INF              # "@-30" = sklon pohledu ve stupních
		if s.contains("@"):
			force_pitch = deg_to_rad(float(s.get_slice("@", 1)))
			s = s.get_slice("@", 0)
		var pos: Vector3
		var yaw: float
		var pitch := -0.05
		if s == "spawn":
			pos = Vector3(spawn.x, _spawn_y() + 1.65, spawn.z)
			yaw = atan2(-(goal.x - spawn.x), -(goal.z - spawn.z))
		elif s == "goal":
			var p := path[path.size() - 22]
			pos = Vector3(p.x, ground(p.x, p.y) + 2.0, p.y)
			pos.y = maxf(pos.y, 2.0)
			yaw = atan2(-(goal.x - p.x), -(goal.z - p.y))
		elif s.begins_with("path"):
			var t := float(s.substr(4)) / 100.0
			var k := clampi(int(t * path.size()), 1, path.size() - 2)
			var p := path[k]
			var d := path[k + 1] - path[k - 1]
			pos = Vector3(p.x, maxf(ground(p.x, p.y), WATER_Y + 0.3) + 1.65, p.y)
			yaw = atan2(-d.x, -d.y)
		elif s.begins_with("top"):
			pos = Vector3(0, 70, R * 0.9)
			yaw = 0.0
			pitch = -0.75
		else:
			var v := s.split(",")
			pos = Vector3(float(v[0]), 0, float(v[1]))
			pos.y = maxf(ground(pos.x, pos.z), WATER_Y) + 1.65
			yaw = deg_to_rad(float(v[2]))
			pitch = deg_to_rad(float(v[3])) if v.size() > 3 else -0.05
		if force_pitch != INF: pitch = force_pitch
		cam.position = pos
		cam.rotation = Vector3(pitch, yaw, 0)
		if OS.get_environment("SWAMP_NOVHS") == "1": vhs_on = false
		flashlight.visible = not s.begins_with("top")
		_flash_t = -1.0
		_moon.light_energy = 1.0 if lit else 0.0
		_sky_mat.set_shader_parameter("flash", 0.8 if lit else 0.0)
		_env.ambient_light_energy = 0.5 if lit else 0.1
		_thunder_t = 9999.0
		for f in 40: await get_tree().process_frame
		get_viewport().get_texture().get_image().save_png(out + "/sw_%d.png" % i)
		i += 1
	get_tree().quit()
