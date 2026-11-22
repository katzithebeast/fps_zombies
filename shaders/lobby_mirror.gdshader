shader_type spatial;
render_mode unshaded, cull_back;
// Skutečné zrcadlo: obraz z odražené kamery (SubViewport), přes něj slepé okraje a skvrny.
uniform sampler2D reflection : source_color, filter_linear;
uniform sampler2D wear : source_color, filter_linear_mipmap;
uniform float flip = 1.0;
void fragment() {
	vec2 uv = vec2(flip > 0.5 ? 1.0 - UV.x : UV.x, UV.y);
	vec3 refl = texture(reflection, uv).rgb;
	vec3 w = texture(wear, UV).rgb;
	// světlé místo textury = čisté sklo, tmavé = oloupaný stříbrný nástřik
	float clean = smoothstep(0.25, 0.85, dot(w, vec3(0.333)));
	ALBEDO = refl * mix(0.18, 0.92, clean) * vec3(0.98, 0.97, 0.94) + w * 0.03;
}
