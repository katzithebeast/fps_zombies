shader_type spatial;
// Glazované dlaždice: 4K PBR sada + variace každé dlaždice zvlášť (odstín, lesk, náklon),
// takže se vzor nikde neopakuje. Pod hladinou kaustiky (reagují i na simulaci vln),
// u hladiny vodní kámen a mokrý pás. Pohyb kaustik řídí pouze simulace vln.
render_mode cull_back;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D orm_tex : filter_linear_mipmap_anisotropic, repeat_enable;      // R = AO, G = roughness, B = height
uniform sampler2D caustic_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D macro_tex : filter_linear_mipmap, repeat_enable;
uniform sampler2D sim_tex : filter_linear, repeat_disable;

uniform vec2 sim_origin = vec2(-32.0, -28.0);
uniform float sim_size = 48.0;
uniform float sim_res = 2048.0;
uniform float water_level = 0.0;
uniform float tex_world = 1.6;            // kolik metrů pokryje jedna textura (8 x 8 dlaždic)
uniform float tiles_per_tex = 8.0;
uniform vec2 sun_slope = vec2(0.18, 0.28);
uniform float caustic_strength = 1.0;
uniform float bounce_strength = 0.09;
uniform vec4 hall_rect = vec4(-12.0, 12.0, -26.0, -1.8);
uniform float normal_flip_y = 0.0;
uniform float normal_depth = 1.0;

instance uniform vec3 tint : source_color = vec3(1.0);
instance uniform float tile_scale = 1.0;
instance uniform float mesh_uv = 0.0;     // 1 = mapování z modelu (zaoblené plochy: tunel), jinak podle směru plochy

varying vec3 wpos;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 an = abs(NORMAL);
	// BINORMAL míří proti směru V (konvence OpenGL normálových map, kterou Godot čeká)
	if (mesh_uv > 0.5) { /* UV v metrech a tečny bere z modelu */ }
	else if (an.y > 0.5) { UV = wpos.xz; TANGENT = vec3(1.0, 0.0, 0.0); BINORMAL = vec3(0.0, 0.0, -1.0); }
	else if (an.x > 0.5) { UV = wpos.zy; TANGENT = vec3(0.0, 0.0, 1.0); BINORMAL = vec3(0.0, -1.0, 0.0); }
	else { UV = wpos.xy; TANGENT = vec3(1.0, 0.0, 0.0); BINORMAL = vec3(0.0, -1.0, 0.0); }
}

vec3 caustic(vec2 uv) {
	vec3 c1 = texture(caustic_tex, uv * 0.23).rgb;
	vec3 c2 = texture(caustic_tex, uv * 0.19 + vec2(0.37, 0.61)).rgb;
	vec3 m = min(c1, c2);
	return m * m * 13.0;
}

void fragment() {
	float dy = wpos.y - water_level;
	// zrcadlová kamera (planární odraz) je pod hladinou: vše pod vodou oříznout
	if (CAMERA_POSITION_WORLD.y < water_level && dy < -0.004) discard;

	vec2 uv = UV / tex_world * tile_scale;
	vec2 id = floor(uv * tiles_per_tex);
	float r1 = hash12(id), r2 = hash12(id + 17.31), r3 = hash12(id + 41.77);

	vec3 orm = texture(orm_tex, uv).rgb;
	float is_tile = smoothstep(0.42, 0.58, orm.b);
	vec3 alb = texture(albedo_tex, uv).rgb;
	float macro = texture(macro_tex, wpos.xz * 0.037 + wpos.y * 0.023).r;
	float macro2 = texture(macro_tex, (wpos.zy + wpos.x) * 0.093 + 0.31).r;

	alb *= mix(mix(vec3(1.0), tint, 0.4), tint * (0.95 + 0.08 * r1), is_tile);
	alb *= 0.94 + 0.12 * macro;
	float rough = orm.g + ((r2 - 0.5) * 0.06 + (macro2 - 0.5) * 0.10) * is_tile;

	vec3 nm = texture(normal_tex, uv).rgb;
	nm.xy += (vec2(r2, r3) - 0.5) * 0.035 * is_tile;         // každá dlaždice je položená trochu jinak
	nm.y = mix(nm.y, 1.0 - nm.y, normal_flip_y);

	// --- voda
	float under = smoothstep(0.012, -0.03, dy);
	float band = smoothstep(0.09, 0.0, abs(dy - 0.015)) * (0.45 + 0.55 * macro2);
	alb = mix(alb, alb * vec3(0.80, 0.85, 0.74), band * 0.65);
	rough = mix(rough, 0.55, band * 0.6);
	float wet = smoothstep(0.22, 0.0, dy) * (1.0 - under);
	alb *= 1.0 - 0.10 * wet;
	rough *= 1.0 - 0.45 * wet;

	// kaustiky promítané ve směru slunce (plná síla jen v hale, kam svítí slunce)
	float in_hall = smoothstep(hall_rect.x - 0.5, hall_rect.x + 0.5, wpos.x) * smoothstep(hall_rect.y + 0.5, hall_rect.y - 0.5, wpos.x)
		* smoothstep(hall_rect.z - 0.5, hall_rect.z + 0.5, wpos.z) * smoothstep(hall_rect.w + 0.5, hall_rect.w - 0.5, wpos.z);
	vec2 cuv = wpos.xz - sun_slope * dy + wpos.y * 0.37;
	vec3 ca = caustic(cuv);
	float e = sim_size / sim_res * 2.0;
	vec2 sxz = wpos.xz - sun_slope * dy;
	vec2 suv = (sxz - sim_origin) / sim_size;
	float hc = textureLod(sim_tex, suv, 0.0).r;
	float lap = textureLod(sim_tex, suv + vec2(e, 0.0) / sim_size, 0.0).r + textureLod(sim_tex, suv - vec2(e, 0.0) / sim_size, 0.0).r
		+ textureLod(sim_tex, suv + vec2(0.0, e) / sim_size, 0.0).r + textureLod(sim_tex, suv - vec2(0.0, e) / sim_size, 0.0).r - 4.0 * hc;
	// mimo simulaci klidná voda (jinak by se krajní texely roztáhly do pruhů)
	float sin_ = step(0.0, suv.x) * step(suv.x, 1.0) * step(0.0, suv.y) * step(suv.y, 1.0);
	hc *= sin_;
	lap *= sin_;
	float focus = clamp(1.0 - lap * 9.0 * clamp(-dy * 2.0, 0.0, 1.5), 0.25, 3.5);     // hřeben vlny světlo soustředí
	float cfade = under * smoothstep(0.0, 0.22, -dy) * caustic_strength * mix(0.22, 1.0, in_hall);
	alb *= mix(vec3(1.0), (0.62 + 0.8 * ca) * focus, cfade);

	// odražené mihotání na stěnách a stropě nad vodou (jen v hale se sluncem)
	vec3 cb = caustic(UV * 1.6 + wpos.y * 0.21 + vec2(hc, lap) * 0.25);
	float bfade = (1.0 - under) * in_hall * exp(-max(dy, 0.0) * 0.28) * bounce_strength;

	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.035, 1.0);
	METALLIC = 0.0;
	SPECULAR = 0.5;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.35;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = normal_depth;
	EMISSION = alb * cb * vec3(0.85, 1.0, 0.98) * bfade;
}
