shader_type spatial;
// Kalná stojatá voda bažiny: hnědozelená, neprůhledná (nevidíš, co je pod tebou),
// v dešti plná kroužků od kapek. Svítí v ní jen odlesk baterky.
render_mode blend_mix, cull_disabled, depth_draw_opaque, specular_schlick_ggx;

uniform sampler2D wave_normal : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D weed_noise : filter_linear_mipmap, repeat_enable;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_linear_mipmap;
uniform vec3 murk_color : source_color = vec3(0.05, 0.045, 0.028);
uniform vec3 weed_color : source_color = vec3(0.07, 0.09, 0.025);
uniform float weed_amount = 0.55;
uniform float rain = 1.0;

varying vec3 wpos;

float h21(vec2 p) {
	return fract(sin(dot(p, vec2(41.3, 289.1))) * 43758.5453);
}

// kroužky od dešťových kapek (dvě vrstvy buněk, každá kapka má jiný čas)
vec2 ripples(vec2 uv, float t) {
	vec2 acc = vec2(0.0);
	for (int l = 0; l < 3; l++) {
		vec2 p = uv * (3.2 + float(l) * 1.7) + vec2(float(l) * 7.3, float(l) * 3.1);
		vec2 id = floor(p);
		vec2 f = fract(p) - 0.5;
		float h = h21(id);
		vec2 o = (vec2(h21(id + 3.1), h21(id + 7.7)) - 0.5) * 0.5;
		float tt = fract(t * (1.1 + h * 0.6) + h);
		vec2 dv = f - o;
		float r = length(dv);
		float front = tt * 0.45;
		float ring = sin((r - front) * 55.0) * smoothstep(0.08, 0.0, abs(r - front + 0.02));
		float amp = (1.0 - tt) * (1.0 - tt);
		acc += dv / (r + 0.001) * ring * amp;
	}
	return acc;
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
	vec3 n = normalize(vec3((n1.xy + n2.xy) * 0.18 + rip * 0.55, 1.0));
	// okřehek a špína na hladině
	float w = texture(weed_noise, uv * 0.035).r;
	float w2 = texture(weed_noise, uv * 0.4 + vec2(0.3, 0.1)).r;
	float weed = smoothstep(1.0 - weed_amount * 0.55, 1.0 - weed_amount * 0.4, w) * smoothstep(0.25, 0.6, w2);
	float silt = texture(weed_noise, uv * 0.15 + vec2(0.7, 0.2)).r;
	// u břehu o něco průhlednější
	float depth = texture(DEPTH_TEXTURE, SCREEN_UV).r;
	vec4 p = INV_PROJECTION_MATRIX * vec4(SCREEN_UV * 2.0 - 1.0, depth, 1.0);
	p.xyz /= p.w;
	float thick = clamp(VERTEX.z - p.z, 0.0, 10.0);
	ALBEDO = mix(murk_color * (0.75 + silt * 0.5), weed_color, weed);
	ROUGHNESS = mix(0.06, 0.8, weed);
	SPECULAR = mix(0.5, 0.2, weed);
	METALLIC = 0.0;
	NORMAL_MAP = n * 0.5 + 0.5;
	NORMAL_MAP_DEPTH = 1.0;
	ALPHA = max(clamp(0.8 + thick * 1.5, 0.8, 0.985), weed);
}
