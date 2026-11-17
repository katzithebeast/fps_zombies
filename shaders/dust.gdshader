shader_type spatial;
// Zrnka prachu: svítí jen tam, kam dopadá slunce (přijímají stíny), takže kreslí světelné paprsky.
render_mode blend_add, depth_draw_never, cull_disabled, specular_disabled, ambient_light_disabled, fog_disabled;
uniform vec3 to_sun = vec3(0.0, 1.0, 0.0);
uniform float brightness = 0.5;
varying float tw;

void vertex() {
	tw = 0.6 + 0.4 * sin(TIME * (1.0 + fract(float(INSTANCE_ID) * 0.37) * 2.0) + float(INSTANCE_ID));
	MODELVIEW_MATRIX = VIEW_MATRIX * mat4(INV_VIEW_MATRIX[0], INV_VIEW_MATRIX[1], INV_VIEW_MATRIX[2], MODEL_MATRIX[3]);
	MODELVIEW_NORMAL_MATRIX = mat3(MODELVIEW_MATRIX);
}

void fragment() {
	float d = length(UV - 0.5) * 2.0;
	float fade = smoothstep(0.25, 1.2, length(VERTEX));        // těsně u kamery zmizí
	ALBEDO = vec3(1.0, 0.97, 0.9) * brightness * tw;
	ALPHA = smoothstep(1.0, 0.1, d) * fade;
	NORMAL = normalize(mat3(VIEW_MATRIX) * to_sun);
}
