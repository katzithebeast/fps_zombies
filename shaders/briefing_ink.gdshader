shader_type canvas_item;
// Úvodní briefing: ilustrace s pomalým posunem/zoomem, přechod „inkoust ve vodě“
// a vzhled přehrávané VHS kazety (na začátku se páska „chytá“).
uniform sampler2D tex_a : filter_linear_mipmap;
uniform sampler2D tex_b : filter_linear_mipmap;
uniform sampler2D noise_tex : repeat_enable, filter_linear;
uniform float progress = 0.0;       // 0 = jen A, 1 = jen B
uniform vec4 kb_a = vec4(1.0, 0.5, 0.5, 1.0);   // zoom, střed x, střed y, jas
uniform vec4 kb_b = vec4(1.0, 0.5, 0.5, 1.0);
uniform float aspect_fix = 1.0;     // poměr stran obrazovky / obrázku
uniform float screen_aspect = 1.777;
uniform float time = 0.0;
uniform float fade = 1.0;           // 0 = černá

vec2 frame(vec2 uv, vec4 kb) {
	vec2 p = uv - 0.5;
	if (aspect_fix > 1.0) p.y /= aspect_fix; else p.x *= aspect_fix;
	return p / kb.x + kb.yz;
}


vec3 picture(vec2 uv) {
	vec3 a = texture(tex_a, frame(uv, kb_a)).rgb * kb_a.w;
	vec3 b = texture(tex_b, frame(uv, kb_b)).rgb * kb_b.w;
	vec3 col = a;
	if (progress > 0.0) {
		// Inkoust: proudící šum zkřivený jiným šumem, rozpíjí se od středu ven.
		vec2 q = uv * vec2(screen_aspect, 1.0);
		vec2 warp = texture(noise_tex, q * 0.35 + vec2(time * 0.025, -time * 0.018)).rg - 0.5;
		float n = texture(noise_tex, q * 0.55 + warp * 0.9).r * 0.62
			+ texture(noise_tex, q * 1.9 + warp * 1.6 + vec2(0.37, 0.11)).r * 0.28
			+ texture(noise_tex, q * 6.0 + warp * 2.5).r * 0.10;
		float radial = length((uv - 0.5) * vec2(screen_aspect, 1.0)) / (0.5 * screen_aspect);
		float v = clamp(n * 0.7 + radial * 0.3, 0.0, 1.0);
		float thr = progress * 1.3 - 0.15;
		float reveal = smoothstep(v - 0.025, v + 0.025, thr);
		col = mix(a, b, reveal);
		float edge = 1.0 - smoothstep(0.0, 0.09, abs(thr - v));
		float wisps = smoothstep(0.55, 0.9, texture(noise_tex, q * 3.0 + warp * 3.0 + time * 0.05).g);
		col = mix(col, vec3(0.02, 0.03, 0.035), clamp(edge * (0.75 + 0.25 * wisps), 0.0, 1.0) * step(0.001, progress) * (1.0 - step(0.999, progress)));
	}
	return col;
}

void fragment() {
	// VHS dělá stejný post-process jako ve hře (vrstva nad tímto obrazem).
	vec2 uv = UV;
	vec3 col = picture(uv);
	col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), 0.2);
	col = pow(max(col, vec3(0.0)), vec3(1.12)) * vec3(1.02, 0.97, 0.88);
	float r = length((uv - 0.5) * vec2(1.3, 1.0));
	col *= mix(0.2, 1.0, 1.0 - smoothstep(0.2, 0.95, r));
	COLOR = vec4(col * fade, 1.0);
}
