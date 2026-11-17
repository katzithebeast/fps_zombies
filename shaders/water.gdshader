shader_type spatial;
// Voda: lom podle hloubky, absorpce barvy ve sloupci vody, planární odraz
// (zrcadlová kamera), Fresnel a vlny výhradně ze simulace pohybu hráče.
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx, ambient_light_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D refl_tex : filter_linear, repeat_disable;
uniform sampler2D sim_tex : filter_linear, repeat_disable;

uniform vec2 sim_origin = vec2(-32.0, -28.0);
uniform float sim_size = 48.0;
uniform float sim_res = 2048.0;
uniform float height_scale = 0.05;
uniform vec3 absorb = vec3(0.40, 0.065, 0.05);          // pohlcování na metr (R nejvíc -> tyrkys)
uniform vec3 scatter_color : source_color = vec3(0.10, 0.52, 0.55);
uniform float scatter_energy = 0.22;
uniform float refract_strength = 0.035;
uniform float refl_distort = 0.03;
uniform float planar_mix = 1.0;
uniform vec3 fallback_refl : source_color = vec3(0.75, 0.82, 0.85);
uniform float refl_gain = 1.0;

varying vec3 wpos;

float simh(vec2 xz) {
	vec2 uv = (xz - sim_origin) / sim_size;
	// mimo simulaci klidná hladina (bez roztažených krajních texelů)
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 0.0;
	return textureLod(sim_tex, uv, 0.0).r;
}

void vertex() {
	vec3 w = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	VERTEX.y += simh(w.xz) * height_scale;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

vec3 view_pos(vec2 uv, float d, mat4 inv_proj) {
	vec4 p = inv_proj * vec4(uv * 2.0 - 1.0, d, 1.0);
	return p.xyz / p.w;
}

void fragment() {
	// --- normála pouze ze simulace; klidná hladina se sama nevlní
	float e = sim_size / sim_res;
	float hl = simh(wpos.xz - vec2(e, 0.0));
	float hr = simh(wpos.xz + vec2(e, 0.0));
	float hd = simh(wpos.xz - vec2(0.0, e));
	float hu = simh(wpos.xz + vec2(0.0, e));
	vec3 n = vec3(-(hr - hl) / (2.0 * e) * height_scale, 1.0, -(hu - hd) / (2.0 * e) * height_scale);
	float dist = length(VERTEX);
	n = normalize(n);
	vec3 vn = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 vup = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec2 bend = vn.xy - vup.xy;                      // odchylka od klidné hladiny v obrazovce
	NORMAL = vn;

	// --- hloubka vody ve směru pohledu
	float z0 = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec3 p0 = view_pos(SCREEN_UV, z0, INV_PROJECTION_MATRIX);
	float thick0 = max(length(p0) - dist, 0.0);

	// --- lom
	vec2 ruv = SCREEN_UV + bend * vec2(1.0, -1.0) * refract_strength * clamp(thick0 * 3.0, 0.0, 1.0);
	ruv = clamp(ruv, vec2(0.001), vec2(0.999));
	float z1 = textureLod(depth_tex, ruv, 0.0).r;
	float thick = length(view_pos(ruv, z1, INV_PROJECTION_MATRIX)) - dist;
	if (thick < 0.0) { ruv = SCREEN_UV; thick = thick0; }
	vec3 scene = textureLod(screen_tex, ruv, 0.0).rgb;
	vec3 trans = exp(-absorb * thick);
	vec3 refr = scene * trans + scatter_color * scatter_energy * (1.0 - trans.g);

	// --- odraz
	vec2 suv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + bend * vec2(1.0, 1.0) * refl_distort;
	suv = clamp(suv, vec2(0.001), vec2(0.999));
	vec3 refl = mix(fallback_refl, textureLod(refl_tex, suv, 0.0).rgb * refl_gain, planar_mix);

	float ndv = clamp(dot(vn, VIEW), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	vec3 col = mix(refr, refl, fres);

	// měkký přechod tam, kde hladina protíná geometrii
	float edge = smoothstep(0.0, 0.025, thick0);
	vec3 raw = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;

	ALBEDO = vec3(0.0);
	METALLIC = 0.0;
	ROUGHNESS = 0.035;
	SPECULAR = 0.5 * edge;
	EMISSION = mix(raw, col, edge);
}
