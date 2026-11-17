## Převod StandardMaterial3D na ekvivalentní ShaderMaterial, který v odrazu hladiny
## (zrcadlová kamera pod vodou) nekreslí části pod hladinou. Výsledky jsou v cache: sdílené
## materiály se převádějí jen jednou.

const SHADER_PATH := "res://shaders/water_clip.gdshader"
static var _cache := {}
static var _shaders := {}
static var water_level := 0.0

static func _shader(cull: int, alpha: bool) -> Shader:
	var key := "%d_%s" % [cull, alpha]
	if _shaders.has(key):
		return _shaders[key]
	var code: String = (load(SHADER_PATH) as Shader).code
	var cull_name: String = ["cull_back", "cull_front", "cull_disabled"][clampi(cull, 0, 2)]
	code = code.replace("render_mode CULL_MODE_PLACEHOLDER;", "render_mode %s%s;" % [cull_name, ", depth_draw_opaque" if alpha else ""])
	code = code.replace("ALPHA_PLACEHOLDER", "ALPHA = alb.a;" if alpha else "")
	var sh := Shader.new()
	sh.code = code
	_shaders[key] = sh
	return sh

static func clip_material(m: Material) -> Material:
	if m == null or not (m is StandardMaterial3D):
		return m
	if _cache.has(m):
		return _cache[m]
	var s: StandardMaterial3D = m
	var alpha := s.transparency != BaseMaterial3D.TRANSPARENCY_DISABLED
	var out := ShaderMaterial.new()
	out.shader = _shader(s.cull_mode, alpha)
	out.set_shader_parameter("albedo_color", s.albedo_color)
	if s.albedo_texture:
		out.set_shader_parameter("albedo_tex", s.albedo_texture)
		out.set_shader_parameter("use_albedo_tex", true)
	out.set_shader_parameter("use_vertex_color", s.vertex_color_use_as_albedo)
	out.set_shader_parameter("roughness", s.roughness)
	if s.roughness_texture:
		out.set_shader_parameter("roughness_tex", s.roughness_texture)
		out.set_shader_parameter("use_roughness_tex", true)
	out.set_shader_parameter("metallic", s.metallic)
	if s.metallic_texture:
		out.set_shader_parameter("metallic_tex", s.metallic_texture)
		out.set_shader_parameter("use_metallic_tex", true)
	out.set_shader_parameter("specular", s.metallic_specular)
	if s.normal_enabled and s.normal_texture:
		out.set_shader_parameter("normal_tex", s.normal_texture)
		out.set_shader_parameter("use_normal_tex", true)
		out.set_shader_parameter("normal_scale", s.normal_scale)
	if s.emission_enabled:
		out.set_shader_parameter("emission_color", s.emission)
		out.set_shader_parameter("emission_energy", s.emission_energy_multiplier)
		if s.emission_texture:
			out.set_shader_parameter("emission_tex", s.emission_texture)
			out.set_shader_parameter("use_emission_tex", true)
	out.set_shader_parameter("uv1_scale", s.uv1_scale)
	out.set_shader_parameter("uv1_offset", s.uv1_offset)
	out.set_shader_parameter("water_level", water_level)
	out.render_priority = s.render_priority
	_cache[m] = out
	return out

static func apply(mi: GeometryInstance3D) -> void:
	# Převede všechny materiály instance (override, povrchové overridy i materiály z meshe).
	if mi is MeshInstance3D:
		var m: MeshInstance3D = mi
		if m.material_override:
			m.material_override = clip_material(m.material_override)
			return
		if m.mesh == null:
			return
		for i in m.mesh.get_surface_count():
			var src := m.get_surface_override_material(i)
			if src == null:
				src = m.mesh.surface_get_material(i)
			var c: Material = clip_material(src)
			if c != src:
				m.set_surface_override_material(i, c)
	elif mi.material_override:
		mi.material_override = clip_material(mi.material_override)

static func crosses(mi: GeometryInstance3D, level: float, margin := 0.01) -> bool:
	# Cokoli, co má aspoň kus pod hladinou (i úplně ponořené věci na dně zakrývají odraz).
	var b := mi.global_transform * mi.get_aabb()
	return b.position.y < level - margin
