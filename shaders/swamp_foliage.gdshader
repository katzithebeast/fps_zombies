shader_type spatial;
// Mokrá vegetace bažiny: přebarvení do zemitých tónů, lesk od deště, kapky, které se
// třpytí v kuželu baterky, prosvítání listů a houpání ve větru.
// Nahrazuje původní materiály stromů, keřů a kamenů (scripts/swamp.gd, _fix_materials).
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D drip_noise : filter_linear_mipmap, repeat_enable;
uniform bool has_normal = false;
uniform bool use_alpha = false;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform float alpha_cut = 0.4;
uniform float leaf = 0.0;            // 1 = listí a tráva (prosvítá), 0 = kůra a kámen
uniform float sway = 0.0;            // síla větru
uniform vec3 grade : source_color = vec3(0.86, 0.9, 0.72);
uniform float saturation = 0.8;
uniform float bright = 0.75;
uniform float wet = 1.0;
uniform float base_rough = 0.7;

varying vec3 wpos;
varying vec3 wnrm;

void vertex() {
	if (sway > 0.0) {
		vec3 origin = MODEL_MATRIX[3].xyz;
		vec3 wp = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
		float above = clamp(wp.y - origin.y, 0.0, 2.5);
		float t = TIME * 1.6 + dot(origin.xz, vec2(0.37, 0.23));
		float gust = 0.6 + 0.4 * sin(TIME * 0.35 + origin.x * 0.05);
		vec3 off = vec3(sin(t) + 0.35 * sin(t * 2.7), 0.0, 0.6 * cos(t * 0.8)) * sway * gust * above * above * 0.16;
		VERTEX += inverse(mat3(MODEL_MATRIX)) * off;
	}
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	wnrm = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec4 a = texture(albedo_tex, UV) * albedo_color;
	if (use_alpha && a.a < alpha_cut) {
		discard;
	}
	vec3 c = a.rgb;
	float l = dot(c, vec3(0.299, 0.587, 0.114));
	c = mix(vec3(l), c, saturation) * grade * bright;
	// mokro: tmavší, sytější
	c = mix(c, c * c * 1.6, 0.35 * wet);
	// kapky a stružky vody: stékají dolů, třpytí se ve světle
	vec2 duv = vec2(wpos.x * 0.9 + wpos.z * 0.7, wpos.y * 0.45 + TIME * 0.12);
	float drip = texture(drip_noise, duv).r;
	float drops = texture(drip_noise, wpos.xz * 1.7 + wpos.yy * 0.9).r;
	float shine = max(smoothstep(0.66, 0.8, drip) * (1.0 - leaf * 0.5), smoothstep(0.74, 0.86, drops) * leaf);
	ALBEDO = c;
	ROUGHNESS = mix(base_rough, 0.08, clamp(shine * wet + wet * 0.25, 0.0, 1.0));
	SPECULAR = 0.5 + 0.35 * shine * wet;
	if (has_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
	}
	BACKLIGHT = c * leaf * 0.7;
	AO = 1.0;
}
