shader_type spatial;
render_mode cull_back;
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(1.0);
uniform float roughness = 0.7;
uniform float metallic = 0.0;
varying float world_y;
void vertex() {
	world_y = (MODEL_MATRIX * vec4(VERTEX, 1.0)).y;
}
void fragment() {
	// Stejné oříznutí jako dlaždice: zrcadlová kamera pod vodou nesmí
	// odrážet ponořenou část těla zpět nad hladinu.
	if (CAMERA_POSITION_WORLD.y < 0.0 && world_y < -0.004) discard;
	ALBEDO = texture(albedo_tex, UV).rgb * tint.rgb;
	ROUGHNESS = roughness;
	METALLIC = metallic;
}
