shader_type spatial;
// Obrys zvýrazněného předmětu: zvětšená zadní strana ploch, svítivá barva.
render_mode unshaded, cull_front, depth_draw_opaque;
uniform vec4 color : source_color = vec4(1.0, 0.86, 0.55, 1.0);
uniform float width = 0.012;
void vertex() {
	float s = length(MODEL_MATRIX[0].xyz);
	VERTEX += NORMAL * width / max(s, 0.00001);
}
void fragment() {
	ALBEDO = color.rgb;
	EMISSION = color.rgb * 0.6;
}
