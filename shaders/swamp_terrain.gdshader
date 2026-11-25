shader_type spatial;
// Zem bažiny: bláto dole u vody, kamenitá hlína výš. Pod hladinou a u ní mokré a tmavé.
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D mud_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mud_orm : filter_linear_mipmap, repeat_enable;
uniform sampler2D soil_albedo : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_orm : filter_linear_mipmap, repeat_enable;
uniform sampler2D noise : filter_linear_mipmap, repeat_enable;
uniform float water_y = 0.0;
uniform vec3 moss_color : source_color = vec3(0.16, 0.19, 0.08);

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}

void fragment() {
	vec2 uv_m = wpos.xz / 3.2;
	vec2 uv_s = wpos.xz / 2.4;
	float n = texture(noise, wpos.xz * 0.025).r;
	float n2 = texture(noise, wpos.xz * 0.11 + vec2(0.37, 0.71)).r;
	float h = wpos.y - water_y;
	// suchá hlína jen na vyvýšených místech, s roztřepeným okrajem
	float dry = smoothstep(0.35, 1.1, h + (n - 0.5) * 1.2);
	vec3 ma = texture(mud_albedo, uv_m).rgb;
	vec3 sa = texture(soil_albedo, uv_s).rgb * vec3(0.85, 0.82, 0.78);
	vec3 alb = mix(ma, sa, dry);
	// mech na mírných svazích nad vodou
	float moss = smoothstep(0.55, 0.75, n2) * smoothstep(0.05, 0.3, h) * (1.0 - dry * 0.6) * smoothstep(0.75, 0.95, wnrm.y);
	alb = mix(alb, moss_color * (0.6 + n2 * 0.6), moss * 0.85);
	vec3 orm = mix(texture(mud_orm, uv_m).rgb, texture(soil_orm, uv_s).rgb, dry);
	vec3 nm = mix(texture(mud_normal, uv_m).rgb, texture(soil_normal, uv_s).rgb, dry);
	// mokro: u vody a pod ní tmavší a lesklé
	float wet = 1.0 - smoothstep(-0.05, 0.4 + n * 0.3, h);
	alb *= mix(0.78, 0.45, wet);           // prší: i suchá místa jsou nasáklá
	float rough = mix(mix(orm.g, 0.38, 0.55), 0.26, wet);
	ALBEDO = alb;
	ROUGHNESS = clamp(rough, 0.05, 1.0);
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.4;
	NORMAL_MAP = nm;
	NORMAL_MAP_DEPTH = mix(1.0, 0.5, wet);
	SPECULAR = mix(0.4, 0.6, wet);
}
