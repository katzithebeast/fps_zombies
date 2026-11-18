shader_type spatial;
render_mode cull_back;
// Hazmat oblek, realistický PBR: povlakovaná PVC tkanina (lesklá vrstva, jemně zmačkaná fólie),
// gumové rukavice / boty / maska, zlaté reflexní hledí. Opotřebení z upečených masek
// (tools/bake_hazmat_wear.py): bahno a usazeniny z bazénů zespodu, špína v záhybech, šmouhy,
// odřené hrany, zaschlá krev a stopy vody. Za běhu: mokrý oblek pod čarou ponoření (wet_line).
// Stejné oříznutí pod hladinou jako dlaždice: zrcadlová kamera neodráží ponořenou část těla.
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap_anisotropic;
uniform sampler2D wear_tex : hint_default_black, filter_linear_mipmap_anisotropic;
uniform sampler2D zones_tex : hint_default_black, filter_linear_mipmap;
uniform sampler2D detail_tex : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grime_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform vec4 tint : source_color = vec4(0.80, 0.85, 0.90, 1.0);
uniform vec4 grime_color : source_color = vec4(0.24, 0.22, 0.17, 1.0);   // bazénové bahno, usazeniny
uniform vec4 algae_color : source_color = vec4(0.22, 0.26, 0.17, 1.0);   // řasy u bot
uniform vec4 blood_color : source_color = vec4(0.17, 0.045, 0.03, 1.0);
uniform float grime = 0.85;
uniform float blood = 0.8;
uniform float normal_strength = 1.0;
uniform float detail_strength = 0.22;
uniform float detail_scale = 24.0;
uniform float wet = 0.0;                 // celkové navlhnutí (déšť, sprcha)
instance uniform float wet_line = -100.0;  // světová výška, kam je oblek mokrý (ponoření)
varying vec3 world_pos;
varying vec3 world_n;
void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
vec3 udn(vec3 a, vec3 b) {   // spojení dvou normálových map (tečný prostor, 0..1)
	vec3 n1 = a * 2.0 - 1.0;
	vec3 n2 = b * 2.0 - 1.0;
	return normalize(vec3(n1.xy + n2.xy, n1.z)) * 0.5 + 0.5;
}
void fragment() {
	if ((CAMERA_VISIBLE_LAYERS & 2u) == 0u && CAMERA_POSITION_WORLD.y < 0.0 && world_pos.y < -0.004) discard;
	vec3 orm = texture(orm_tex, UV).rgb;
	vec4 w = texture(wear_tex, UV);
	vec3 z = texture(zones_tex, UV).rgb;
	float suit = z.r;
	float rubber = z.g;
	float visor = z.b;
	float other = clamp(1.0 - suit - rubber - visor, 0.0, 1.0);   // filtry, přezky
	vec3 g = texture(grime_tex, UV * 3.0).rgb;
	vec3 base = texture(albedo_tex, UV).rgb;
	// oblek: lehce vybledlá a nestejnoměrná barva (UV, pot, chemikálie)
	float fade = g.b * 0.5 + g.r * 0.3;
	vec3 suit_col = base * tint.rgb * mix(0.93, 1.05, fade);
	suit_col = mix(suit_col, vec3(dot(suit_col, vec3(0.33))) * vec3(0.95, 1.0, 1.05), 0.03 + fade * 0.06);
	base = mix(base, suit_col, suit);
	base = mix(base, base * vec3(0.55, 0.5, 0.42), visor);   // hledí: tmavé zlacené zrcadlo
	base = mix(base, base * 0.7, rubber);
	// --- špína: z upečené masky + jemný rozptyl, guma a hledí méně
	float dirt = clamp(w.r * (0.75 + 0.5 * g.g) - 0.05, 0.0, 1.0) * grime * (1.0 - visor * 0.85);
	float low = 1.0 - smoothstep(0.0, 0.75, world_pos.y - NODE_POSITION_WORLD.y);
	vec3 mud = mix(grime_color.rgb, algae_color.rgb, low * 0.45 * g.r);
	vec3 col = mix(base, mud * (0.65 + 0.5 * g.g), dirt * 0.85);
	// odřené hrany: na obleku světlejší a matné, na gumě sedavé
	float edge = w.g * (1.0 - visor);
	col = mix(col, col * 1.18 + vec3(0.03), edge * 0.35 * suit);
	col = mix(col, vec3(0.32, 0.31, 0.3), edge * 0.25 * rubber);
	// stopy vody: vápenaté okraje kapek a čar hladiny
	col = mix(col, col * 0.86 + vec3(0.06, 0.06, 0.055), w.a * 0.55 * (1.0 - visor));
	// zaschlá krev
	float bl = smoothstep(0.2, 0.55, w.b) * blood * (1.0 - visor);
	col = mix(col, col * vec3(0.45, 0.32, 0.28), smoothstep(0.0, 0.5, bl));
	col = mix(col, blood_color.rgb * (0.6 + 0.5 * g.r), pow(bl, 0.7) * 0.9);
	// --- mokro pod čarou ponoření (+ stékající kapky nad ní)
	float drip = w.a * (1.0 - smoothstep(wet_line, wet_line + 0.25, world_pos.y));
	float soak = max(1.0 - smoothstep(wet_line - 0.04, wet_line + 0.03, world_pos.y), max(wet, drip * 0.7));
	// nasáklá špína a oblek: tmavší a sytější barva, voda stéká po obleku
	vec3 wet_col = col * col * 1.35;
	col = mix(col, wet_col, soak * (1.0 - visor) * 0.85);
	// --- drsnost, kov, lesk
	float rough_suit = mix(0.4, 0.55, g.g) + dirt * 0.35 + edge * 0.2 + w.a * 0.15;
	float rough_rubber = 0.6 + dirt * 0.25 + edge * 0.1;
	float rough_visor = 0.035 + dirt * 0.25 + g.b * 0.05;   // otisky prstů a šmouhy
	float rough = rough_suit * suit + rough_rubber * rubber + rough_visor * visor + orm.g * other;
	rough = mix(rough, 0.45, bl * 0.4);
	rough = mix(rough, 0.07, soak * (1.0 - visor));
	ALBEDO = col;
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = max(orm.b * other, visor * 0.95);
	SPECULAR = 0.5;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.55;
	// lakovaná vrstva PVC: ostrý odlesk navrch, slábne pod špínou; mokrý oblek se leskne celý
	CLEARCOAT = clamp(suit * (0.28 - dirt * 0.25) + soak * 0.9 + rubber * 0.08, 0.0, 1.0);
	CLEARCOAT_ROUGHNESS = mix(0.3, 0.05, soak);
	// měkký lesk na hranách záhybů (látka), na gumě slabší
	RIM = 0.18 * suit + 0.08 * rubber;
	RIM_TINT = 0.55;
	vec3 detail = texture(detail_tex, UV * detail_scale).rgb;
	detail = mix(vec3(0.5, 0.5, 1.0), detail, detail_strength * (suit + rubber * 0.35) * (1.0 - soak * 0.6));
	NORMAL_MAP = udn(texture(normal_tex, UV).rgb, detail);
	NORMAL_MAP_DEPTH = normal_strength;
}
