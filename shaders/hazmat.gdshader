shader_type spatial;
render_mode cull_back;
// Hazmat oblek: PBR (albedo, normála, AO/drsnost/kov). Stejné oříznutí pod hladinou jako
// dlaždice: zrcadlová kamera (nevidí vodu, vrstva 2) neodráží ponořenou část těla.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D grime_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.78, 0.83, 0.88, 1.0);
uniform vec4 grime_color : source_color = vec4(0.16, 0.15, 0.13, 1.0);
uniform float grime = 0.55;          // špína v záhybech a šmouhy (oblek nevypadá jako nový)
uniform float normal_strength = 1.0;
uniform float wet = 0.0;
varying float world_y;
void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
	if ((CAMERA_VISIBLE_LAYERS & 2u) == 0u && CAMERA_POSITION_WORLD.y < 0.0 && world_y < -0.004) discard;
	vec3 orm = texture(orm_tex, UV).rgb;
	vec3 g = texture(grime_tex, UV * 3.0).rgb;
	vec3 g2 = texture(grime_tex, UV * 11.0 + vec2(0.37, 0.71)).rgb;
	// víc špíny v záhybech (nízké AO), skvrny a jemné stékající šmouhy
	float dirt = clamp((1.0 - orm.r) * 1.6 * g.g + g.r * 0.35 + g2.b * 0.25 - 0.18, 0.0, 1.0) * grime;
	vec3 base = texture(albedo_tex, UV).rgb * tint.rgb;
	ALBEDO = mix(base, base * grime_color.rgb * 2.2, dirt);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.6;
	ROUGHNESS = clamp(orm.g + dirt * 0.25, 0.0, 1.0);
	METALLIC = orm.b;
	NORMAL_MAP = texture(normal_tex, UV).rgb;
	NORMAL_MAP_DEPTH = normal_strength;
}
