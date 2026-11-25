shader_type spatial;
// Voda bažiny: postavená na klasické vodě z lázní (shaders/water.gdshader), jen obarvená do kalné
// hnědozelené břečky. Světlo do ní vniká a pohltí se (žádná šedá plocha pod baterkou),
// dno je vidět jen u břehu. Odraz z zrcadlové kamery (planární), vlny ze simulace pohybu hráče
// (brodění), navíc kroužky od deště, plující listí, okřehek a pěna.
render_mode blend_mix, cull_back, depth_draw_never, specular_schlick_ggx, ambient_light_disabled, fog_disabled;

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D depth_tex : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D refl_tex : filter_linear, repeat_disable;
uniform sampler2D sim_tex : filter_linear, repeat_disable;
uniform sampler2D weed_noise : filter_linear_mipmap, repeat_enable;

uniform vec2 sim_origin = vec2(-80.0, -80.0);
uniform float sim_size = 160.0;
uniform float sim_res = 2048.0;
uniform float height_scale = 0.05;
uniform vec3 absorb = vec3(15.0, 12.0, 19.0);              // pohlcování na metr: kalná voda, dno jen u břehu
uniform vec3 silt_color : source_color = vec3(0.009, 0.0075, 0.0035);   // kal ve vodě, osvětlí ho jen baterka
uniform float refract_strength = 0.03;
uniform float refl_distort = 0.035;
uniform float planar_mix = 1.0;
uniform vec3 fallback_refl : source_color = vec3(0.01, 0.012, 0.015);
uniform float refl_gain = 0.85;
uniform float rain = 1.0;
uniform vec3 weed_color : source_color = vec3(0.05, 0.065, 0.018);
uniform vec3 scum_color : source_color = vec3(0.12, 0.11, 0.08);
uniform float weed_amount = 0.55;

varying vec3 wpos;

float simh(vec2 xz) {
	vec2 uv = (xz - sim_origin) / sim_size;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 0.0;
	return textureLod(sim_tex, uv, 0.0).r;
}

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

// kroužky od dešťových kapek (tři vrstvy buněk, každá kapka v jiný čas)
vec2 ripples(vec2 uv, float t) {
	vec2 acc = vec2(0.0);
	for (int l = 0; l < 3; l++) {
		vec2 p = uv * (3.0 + float(l) * 1.9) + vec2(float(l) * 7.3, float(l) * 3.1);
		vec2 id = floor(p);
		vec2 f = fract(p) - 0.5;
		float h = h21(id);
		vec2 o = (vec2(h21(id + 3.1), h21(id + 7.7)) - 0.5) * 0.5;
		float tt = fract(t * (1.2 + h * 0.7) + h);
		vec2 dv = f - o;
		float r = length(dv);
		float front = tt * 0.45;
		float ring = sin((r - front) * 60.0) * smoothstep(0.07, 0.0, abs(r - front + 0.015));
		float amp = (1.0 - tt) * (1.0 - tt);
		acc += dv / (r + 0.001) * ring * amp;
	}
	return acc;
}

// spadané listí plovoucí po hladině
float leaf_layer(vec2 uv, float scale, float seed, out vec3 col) {
	vec2 p = uv * scale;
	vec2 id = floor(p);
	vec2 f = fract(p) - 0.5;
	float h = h21(id + seed);
	float a = h * 31.4;
	vec2 c = (vec2(h21(id + seed + 2.0), h21(id + seed + 5.0)) - 0.5) * 0.5;
	vec2 q = f - c;
	q = vec2(q.x * cos(a) - q.y * sin(a), q.x * sin(a) + q.y * cos(a));
	float e = length(q * vec2(1.0, 2.1));
	float rim = 0.17 + 0.03 * sin(atan(q.y, q.x) * 7.0 + h * 20.0);     // nepravidelný okraj
	float m = smoothstep(rim, rim - 0.03, e) * step(0.8, h);
	float vein = smoothstep(0.02, 0.0, abs(q.y)) * 0.4;
	col = mix(vec3(0.05, 0.028, 0.012), vec3(0.09, 0.055, 0.02), h21(id + seed + 9.0)) * (1.0 - vein);
	return m;
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
	// --- vlny: simulace (brodění) + kroužky od deště
	float e = sim_size / sim_res;
	float hl = simh(wpos.xz - vec2(e, 0.0));
	float hr = simh(wpos.xz + vec2(e, 0.0));
	float hd = simh(wpos.xz - vec2(0.0, e));
	float hu = simh(wpos.xz + vec2(0.0, e));
	vec2 drift = wpos.xz + vec2(TIME * 0.012, TIME * 0.006);
	// plovoucí věci na hladině (listí, okřehek, pěna)
	float w = texture(weed_noise, drift * 0.035).r;
	float w2 = texture(weed_noise, drift * 0.4 + vec2(0.3, 0.1)).r;
	float weed = smoothstep(1.0 - weed_amount * 0.55, 1.0 - weed_amount * 0.4, w) * smoothstep(0.25, 0.6, w2);
	float sc = texture(weed_noise, drift * 0.09 + vec2(0.5, 0.8)).r;
	float scum = smoothstep(0.62, 0.66, sc) * smoothstep(0.72, 0.66, sc) * 0.7 + smoothstep(0.7, 0.8, sc) * 0.2;
	vec3 lc1;
	vec3 lc2;
	float l1 = leaf_layer(drift, 1.4, 11.0, lc1);
	float l2 = leaf_layer(drift + 0.37, 2.3, 23.0, lc2);
	vec3 floatc = mix(mix(scum_color, weed_color, weed), lc2, l2);
	floatc = mix(floatc, lc1, l1);
	float solid = clamp(max(max(weed, l1), max(l2, scum)), 0.0, 1.0);
	vec2 rip = ripples(wpos.xz, TIME) * rain * (1.0 - solid);
	vec3 n = vec3(-(hr - hl) / (2.0 * e) * height_scale + rip.x * 0.06, 1.0, -(hu - hd) / (2.0 * e) * height_scale + rip.y * 0.06);
	float dist = length(VERTEX);
	n = normalize(n);
	vec3 vn = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 vup = normalize((VIEW_MATRIX * vec4(0.0, 1.0, 0.0, 0.0)).xyz);
	vec2 bend = vn.xy - vup.xy;
	NORMAL = vn;

	// --- hloubka vody ve směru pohledu
	float z0 = textureLod(depth_tex, SCREEN_UV, 0.0).r;
	vec3 p0 = view_pos(SCREEN_UV, z0, INV_PROJECTION_MATRIX);
	float thick0 = max(length(p0) - dist, 0.0);

	// --- lom: dno prosvítá jen tam, kde je mělko
	vec2 ruv = SCREEN_UV + bend * vec2(1.0, -1.0) * refract_strength * clamp(thick0 * 3.0, 0.0, 1.0);
	ruv = clamp(ruv, vec2(0.001), vec2(0.999));
	float z1 = textureLod(depth_tex, ruv, 0.0).r;
	float thick = length(view_pos(ruv, z1, INV_PROJECTION_MATRIX)) - dist;
	if (thick < 0.0) { ruv = SCREEN_UV; thick = thick0; }
	vec3 scene = textureLod(screen_tex, ruv, 0.0).rgb;
	vec3 trans = exp(-absorb * thick);
	vec3 refr = scene * trans;

	// --- odraz (zrcadlová kamera)
	vec2 suv = vec2(SCREEN_UV.x, 1.0 - SCREEN_UV.y) + bend * vec2(1.0, 1.0) * refl_distort;
	suv = clamp(suv, vec2(0.001), vec2(0.999));
	vec3 refl = mix(fallback_refl, textureLod(refl_tex, suv, 0.0).rgb * refl_gain, planar_mix);

	float ndv = clamp(dot(vn, VIEW), 0.0, 1.0);
	float fres = 0.02 + 0.98 * pow(1.0 - ndv, 5.0);
	vec3 col = mix(refr, refl, fres);

	// měkký přechod tam, kde hladina protíná břeh
	float edge = smoothstep(0.0, 0.025, thick0);
	vec3 raw = textureLod(screen_tex, SCREEN_UV, 0.0).rgb;
	vec3 emis = mix(raw, col, edge);

	// kal ve vodě a plovoucí věci svítí jen tam, kam dopadne světlo (baterka, blesk)
	float silt = 0.6 + 0.8 * texture(weed_noise, wpos.xz * 0.15 + vec2(0.7, 0.2)).r;
	vec3 kal = silt_color * silt * (1.0 - trans.g) * edge;
	ALBEDO = mix(kal, floatc, solid);
	EMISSION = emis * (1.0 - solid);
	METALLIC = 0.0;
	ROUGHNESS = mix(0.035, 0.7, solid);
	SPECULAR = mix(0.5, 0.2, solid) * edge;
}
