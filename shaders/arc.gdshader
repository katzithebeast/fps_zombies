shader_type spatial;
// Elektrický výboj: pásek natočený ke kameře, jádro bílé, okraj v barvě stupně.
render_mode unshaded, blend_add, depth_draw_never, cull_disabled, shadows_disabled, fog_disabled;
uniform vec4 tint : source_color = vec4(1.0, 0.2, 0.15, 1.0);
uniform float energy = 6.0;
void fragment() {
	float x = abs(UV.x * 2.0 - 1.0);
	float core = pow(1.0 - x, 6.0);
	float glow = pow(1.0 - x, 1.6);
	vec3 c = mix(tint.rgb, vec3(1.0, 0.92, 0.9), core * UV.y);
	// strop jasu: výboj mířící ke kameře se překrývá sám se sebou (aditivně) a bloom by z něj udělal kouli
	ALBEDO = min(c * energy * (glow * 0.6 + core) * COLOR.a, vec3(2.2));
}
