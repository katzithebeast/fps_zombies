shader_type spatial;
// Vodopád: průsvitné stékající pruhy vody.
render_mode cull_disabled, depth_draw_never, specular_schlick_ggx;
uniform vec4 tint : source_color = vec4(0.75, 0.88, 0.92, 1.0);
uniform float speed = 1.6;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float noise(vec2 p) {
	vec2 i = floor(p); vec2 f = fract(p); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
void fragment() {
	vec2 uv = UV * vec2(14.0, 3.0);
	uv.y -= TIME * speed;
	float n = noise(uv) * 0.6 + noise(uv * 2.3 + 7.0) * 0.4;
	float streak = smoothstep(0.35, 0.9, n);
	float edge = smoothstep(0.0, 0.08, UV.x) * smoothstep(1.0, 0.92, UV.x);
	ALBEDO = tint.rgb * (0.7 + streak * 0.5);
	ROUGHNESS = 0.08;
	SPECULAR = 0.8;
	ALPHA = (0.25 + streak * 0.6) * edge;
}
