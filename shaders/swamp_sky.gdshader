shader_type sky;
// Zatažená noční obloha nad bažinou: skoro černá, jen tušené mraky. Při blesku se rozsvítí.

uniform float flash = 0.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}

void sky() {
	vec3 d = EYEDIR;
	float up = clamp(d.y, 0.0, 1.0);
	vec2 cp = d.xz / max(d.y, 0.06) * 0.9 + vec2(TIME * 0.006, TIME * 0.002);
	float cl = vnoise(cp) * 0.55 + vnoise(cp * 2.1) * 0.3 + vnoise(cp * 4.7) * 0.15;
	vec3 col = mix(vec3(0.0025, 0.003, 0.004), vec3(0.0012, 0.0014, 0.002), pow(up, 0.5));
	col *= 0.7 + cl * 0.6;
	// blesk: prosvítí mraky zevnitř, nejvíc u obzoru
	float lit = flash * (0.35 + cl * 0.9) * (0.6 + 0.4 * (1.0 - up));
	col += vec3(0.55, 0.6, 0.78) * lit;
	COLOR = col;
}
