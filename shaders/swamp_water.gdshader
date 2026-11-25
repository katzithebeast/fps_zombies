shader_type spatial;
// Kalná stojatá voda bažiny: skoro černá hnědozelená břečka, nevidíš, co je pod hladinou.
// Plná kroužků od deště, s plujícím spadaným listím, okřehkem a špinavou pěnou.
// Neprůhledná, takže v ní funguje zrcadlení (SSR): odráží se v ní, co osvítí baterka.
render_mode cull_disabled, specular_schlick_ggx;

uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D weed_noise : filter_linear_mipmap, repeat_enable;
uniform vec3 murk_color : source_color = vec3(0.028, 0.026, 0.016);
uniform vec3 weed_color : source_color = vec3(0.06, 0.075, 0.022);
uniform vec3 scum_color : source_color = vec3(0.16, 0.15, 0.11);
uniform float weed_amount = 0.55;
uniform float rain = 1.0;

varying vec3 wpos;

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

// spadané listí plovoucí po hladině (jedna vrstva buněk = nejvýš jeden list v buňce)
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
	float m = smoothstep(0.2, 0.16, e) * step(0.62, h);
	float vein = smoothstep(0.02, 0.0, abs(q.y)) * 0.4;
	col = mix(vec3(0.15, 0.07, 0.025), vec3(0.24, 0.15, 0.04), h21(id + seed + 9.0)) * (1.0 - vein);
	return m;
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 uv = wpos.xz;
	float t = TIME;
	vec3 n1 = texture(wave_normal, uv * 0.06 + vec2(t * 0.003, t * 0.002)).rgb * 2.0 - 1.0;
	vec3 n2 = texture(wave_normal, uv * 0.11 - vec2(t * 0.002, -t * 0.0025)).rgb * 2.0 - 1.0;
	vec2 rip = ripples(uv, t) * rain;
	// okřehek, pěna a listí se pomalu unášejí
	vec2 drift = uv + vec2(t * 0.012, t * 0.006);
	float w = texture(weed_noise, drift * 0.035).r;
	float w2 = texture(weed_noise, drift * 0.4 + vec2(0.3, 0.1)).r;
	float weed = smoothstep(1.0 - weed_amount * 0.55, 1.0 - weed_amount * 0.4, w) * smoothstep(0.25, 0.6, w2);
	float sc = texture(weed_noise, drift * 0.09 + vec2(0.5, 0.8)).r;
	float scum = smoothstep(0.62, 0.66, sc) * smoothstep(0.72, 0.66, sc) * 0.8 + smoothstep(0.7, 0.8, sc) * 0.25;
	vec3 lc1;
	vec3 lc2;
	float l1 = leaf_layer(drift, 1.4, 11.0, lc1);
	float l2 = leaf_layer(drift + 0.37, 2.3, 23.0, lc2);
	float silt = texture(weed_noise, uv * 0.15 + vec2(0.7, 0.2)).r;
	vec3 col = murk_color * (0.7 + silt * 0.6);
	col = mix(col, scum_color, scum);
	col = mix(col, weed_color, weed);
	col = mix(col, lc2, l2);
	col = mix(col, lc1, l1);
	float solid = clamp(max(max(weed, l1), max(l2, scum * 0.6)), 0.0, 1.0);
	// na listí a okřehku kroužky nejsou, hladina kolem se leskne
	vec3 n = normalize(vec3((n1.xy + n2.xy) * 0.16 + rip * 0.75 * (1.0 - solid), 1.0));
	ALBEDO = col;
	ROUGHNESS = mix(0.02, 0.6, solid);
	SPECULAR = mix(0.6, 0.25, solid);
	METALLIC = 0.0;
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
}
