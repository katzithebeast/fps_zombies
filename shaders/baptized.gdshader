// Pokřtěná zbraň (náš Pack-a-Punch): přes původní texturu se kreslí tekoucí
// „andělova voda“ – tmavý mokrý kov s pomalu se vlnícími zářícími žilkami a okrajovou září.
shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled;

uniform float pattern_scale = 8.0;
uniform vec4 base_color : source_color = vec4(0.015, 0.07, 0.085, 1.0);
uniform vec4 vein_color : source_color = vec4(0.32, 1.0, 0.92, 1.0);
uniform float vein_energy = 3.4;
uniform float strength = 1.0;      // 0..1 (náběh efektu po křtu)
uniform float surge = 0.0;         // krátké rozzáření při výstřelu
uniform float flow_speed = 1.0;    // jak rychle žilky tečou (vyšší stupeň = živější)
uniform float detail = 1.0;        // 0..1 druhá vrstva jemných žilek
uniform float halo_amt = 1.0;      // měkká záře kolem žilek
uniform float iri_amt = 1.0;       // duhový nádech kovu

varying vec3 lp;

float hash(vec3 p) {
	p = fract(p * 0.3183099 + 0.1);
	p *= 17.0;
	return fract(p.x * p.y * p.z * (p.x + p.y + p.z));
}

float noise(vec3 x) {
	vec3 i = floor(x);
	vec3 f = fract(x);
	f = f * f * (3.0 - 2.0 * f);
	return mix(
		mix(mix(hash(i), hash(i + vec3(1, 0, 0)), f.x), mix(hash(i + vec3(0, 1, 0)), hash(i + vec3(1, 1, 0)), f.x), f.y),
		mix(mix(hash(i + vec3(0, 0, 1)), hash(i + vec3(1, 0, 1)), f.x), mix(hash(i + vec3(0, 1, 1)), hash(i + vec3(1, 1, 1)), f.x), f.y),
		f.z);
}

float fbm(vec3 p) {
	float a = 0.5;
	float r = 0.0;
	for (int i = 0; i < 4; i++) {
		r += a * noise(p);
		p *= 2.03;
		a *= 0.5;
	}
	return r;
}

void vertex() {
	// Vzor v metrech modelu, aby měl na všech zbraních stejnou velikost.
	float s = length(MODEL_MATRIX[0].xyz);
	lp = VERTEX * s;
	VERTEX += NORMAL * (0.0012 / max(s, 0.0001));
}

void fragment() {
	float t = TIME * flow_speed;
	vec3 p = lp * pattern_scale;
	vec3 q = vec3(
		fbm(p + vec3(0.0, t * 0.22, 0.0)),
		fbm(p + vec3(5.2, 1.3, t * 0.18)),
		fbm(p + vec3(t * 0.14, 9.1, 2.7)));
	float n = fbm(p + q * 2.4 + vec3(0.0, 0.0, t * 0.3));
	// Žilky = tenké vrstevnice tekoucího šumu (šířka v pixelech, ať jsou ostré na blízko i daleko).
	float d1 = abs(n - 0.5);
	float l1 = 1.0 - smoothstep(0.6, 2.2, d1 / max(fwidth(n), 0.0001));
	float m = fbm(p * 2.6 + q * 3.0 - vec3(0.0, t * 0.45, 0.0));
	float d2 = abs(m - 0.47);
	float l2 = 1.0 - smoothstep(0.5, 1.8, d2 / max(fwidth(m), 0.0001));
	float halo = (exp(-d1 * 38.0) * 0.38 + exp(-d2 * 60.0) * 0.2 * detail) * halo_amt;
	float pulse = 0.7 + 0.3 * sin(t * 2.0 + n * 9.0);
	float fres = pow(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0), 4.0);
	// Podklad: tmavý mokrý kov s jemnou duhou podle úhlu pohledu.
	vec3 iri = 0.5 + 0.5 * cos(6.2831 * (vec3(0.0, 0.33, 0.67) + fres * 0.6 + n * 0.4));
	ALBEDO = base_color.rgb * (0.7 + 0.8 * n) + iri * 0.012 * iri_amt;
	METALLIC = 0.92;
	ROUGHNESS = 0.16 + 0.2 * m;
	float glow_amt = (l1 * 1.0 + l2 * 0.55 * detail + halo) * pulse * (1.0 + surge * 2.0);
	EMISSION = vein_color.rgb * (glow_amt * vein_energy * 0.55 + fres * 0.18);
	ALPHA = strength * clamp(0.86 + l1 * 0.14, 0.0, 1.0);
}
