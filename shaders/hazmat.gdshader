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
// --- přizpůsobení hráče (menu Customize); výchozí = původní barvy modelu
instance uniform vec4 suit_col : source_color = vec4(0.352, 0.552, 0.948, 1.0);
instance uniform vec4 rubber_col : source_color = vec4(0.209, 0.209, 0.209, 1.0);
instance uniform vec4 visor_col : source_color = vec4(0.863, 0.688, 0.19, 1.0);
instance uniform vec4 pattern_col : source_color = vec4(0.1, 0.12, 0.08, 1.0);
instance uniform float pattern = 0.0;          // 0 nic, 1 maskáč, 2 digitál, 3 výstražné pruhy, 4 reflexní pásy, 5 cákance, 6 tygří pruhy
                                               // prestižní: 7 zlato, 8 platina, 9 diamant, 10 obsidián, 11 krvavý měsíc, 12 láva
instance uniform float pattern_scale = 1.0;
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
varying vec3 rest_pos;   // klidová poloha vrcholu (CUSTOM0, tools/bake_rest_pos.gd): vzory drží na obleku bez švů
void vertex() {
	rest_pos = CUSTOM0.xyz;
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_n = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
const vec3 SUIT_REF = vec3(0.352, 0.552, 0.948);   // průměrné barvy zón v textuře (sRGB)
const vec3 RUBBER_REF = vec3(0.209, 0.209, 0.209);
const vec3 VISOR_REF = vec3(0.863, 0.688, 0.19);
float lum(vec3 c) { return dot(c, vec3(0.2126, 0.7152, 0.0722)); }
vec3 lin(vec3 c) { return pow(c, vec3(2.2)); }
float hash3(vec3 p) { p = fract(p * 0.3183099 + 0.1); p *= 17.0; return fract(p.x * p.y * p.z * (p.x + p.y + p.z)); }
float vnoise(vec3 x) {
	vec3 i = floor(x); vec3 f = fract(x); f = f * f * (3.0 - 2.0 * f);
	return mix(mix(mix(hash3(i), hash3(i + vec3(1,0,0)), f.x), mix(hash3(i + vec3(0,1,0)), hash3(i + vec3(1,1,0)), f.x), f.y),
		mix(mix(hash3(i + vec3(0,0,1)), hash3(i + vec3(1,0,1)), f.x), mix(hash3(i + vec3(0,1,1)), hash3(i + vec3(1,1,1)), f.x), f.y), f.z);
}
float fbm(vec3 p) { return vnoise(p) * 0.55 + vnoise(p * 2.03 + 7.1) * 0.3 + vnoise(p * 4.1 + 3.3) * 0.15; }
// vyhlazený práh (antialiasing podle derivace v pixelu): ostré, ale nezubaté okraje
float aas(float v, float t, float soft) { float w = fwidth(v) * 0.75 + soft + 1e-5; return smoothstep(t - w, t + w, v); }
// tekutá deformace prostoru v čase (Pack-a-Punch styl: vzor proudí po obleku)
vec3 warp(vec3 q, float t) {
	vec3 w = vec3(fbm(q + vec3(0.0, t, 0.0)), fbm(q + vec3(5.2, 1.3 - t * 0.8, 2.1)), fbm(q + vec3(1.7, 9.2, t * 0.6)));
	return q + (w - 0.5) * 1.8;
}
// Vzor na obleku: [síla 0..1, odstín 0..1 (0 = barva vzoru, 1 = tmavší vzor)] v klidové poloze P.
vec2 suit_pattern(vec3 P, int kind, float sc) {
	if (kind == 1) {          // maskáč (woodland): dvě vrstvy skvrn
		float m1 = aas(fbm(P * 3.2 * sc), 0.5, 0.004);
		float m2 = aas(fbm(P * 5.5 * sc + 11.0), 0.58, 0.004);
		return vec2(max(m1, m2), m2);
	} else if (kind == 2) {   // digitální maskáč: pixely 2 velikostí
		float cs = 0.035 / sc;
		float a = fbm(floor(P / cs) * cs * 4.0);
		float b = fbm(floor(P / (cs * 2.0)) * cs * 2.0 * 4.0 + 5.0);
		float m1 = step(0.52, a);
		float m2 = step(0.6, b);
		return vec2(max(m1, m2), m2);
	} else if (kind == 3) {   // výstražné šikmé pruhy
		float d = abs(fract((P.x * 0.8 + P.y + P.z * 0.6) * 5.0 * sc) - 0.5);
		return vec2(1.0 - aas(d, 0.25, 0.0), 0.0);
	} else if (kind == 4) {   // reflexní pásy: holeně, stehna, předloktí, hruď
		float y = P.y;
		float legs = (1.0 - aas(min(abs(y - 0.33) - 0.03, abs(y - 0.5) - 0.025), 0.0, 0.0)) * (1.0 - aas(abs(P.x), 0.3, 0.0));
		float arms = (1.0 - aas(abs(abs(P.x) - 0.52), 0.03, 0.0)) * aas(y, 1.0, 0.0);
		float chest = (1.0 - aas(abs(y - 1.3), 0.025, 0.0)) * (1.0 - aas(abs(P.x), 0.25, 0.0));
		return vec2(max(legs, max(arms, chest)), 0.0);
	} else if (kind == 5) {   // cákance barvy
		float a = fbm(P * 7.0 * sc + 2.0);
		float d = vnoise(P * 60.0 * sc);
		return vec2(max(aas(a, 0.66, 0.003), aas(d, 0.93, 0.0) * aas(a, 0.45, 0.0)), 0.0);
	} else if (kind == 6) {   // tygří pruhy
		float w = fbm(P * 4.0 * sc) * 2.5;
		float s = sin((P.y * 22.0 + abs(P.x) * 6.0) * sc + w * 3.0);
		return vec2(aas(s, 0.58, 0.02), 0.0);
	}
	return vec2(0.0);
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
	// barvy z přizpůsobení: odstín z textury (záhyby, světlo), barva zvolená hráčem
	base = mix(base, suit_col.rgb * lum(base) / lum(lin(SUIT_REF)), suit);
	base = mix(base, rubber_col.rgb * lum(base) / lum(lin(RUBBER_REF)), rubber);
	base = mix(base, visor_col.rgb * lum(base) / lum(lin(VISOR_REF)), visor);
	vec3 P = rest_pos;
	vec2 pat = suit_pattern(P, int(pattern + 0.5), max(pattern_scale, 0.2)) * suit;
	vec3 pcol = mix(pattern_col.rgb, pattern_col.rgb * 0.45, pat.y) * lum(texture(albedo_tex, UV).rgb) / lum(lin(SUIT_REF));
	base = mix(base, pcol, pat.x);
	// oblek: lehce vybledlá a nestejnoměrná barva (UV, pot, chemikálie)
	float fade = g.b * 0.5 + g.r * 0.3;
	vec3 suit_shade = base * tint.rgb * mix(0.93, 1.05, fade);
	suit_shade = mix(suit_shade, vec3(dot(suit_shade, vec3(0.33))) * vec3(0.95, 1.0, 1.05), 0.03 + fade * 0.06);
	base = mix(base, suit_shade, suit);
	base = mix(base, base * vec3(0.55, 0.5, 0.42), visor);   // hledí: tmavé zlacené zrcadlo
	base = mix(base, base * 0.7, rubber);
	// --- prestižní skiny (jen oblek): kovy, diamant, tři prestižní maskáče
	int pk = int(pattern + 0.5);
	float prest = pk >= 7 ? suit : 0.0;
	vec3 p_alb = vec3(0.0);
	float p_metal = 0.0;
	float p_rough = 0.3;
	vec3 p_emit = vec3(0.0);
	if (prest > 0.0) {
		float shade = clamp(lum(texture(albedo_tex, UV).rgb) / lum(lin(SUIT_REF)), 0.4, 1.4);
		float sc = max(pattern_scale, 0.2);
		float t = TIME;
		float facing = clamp(dot(normalize(VIEW), NORMAL), 0.0, 1.0);
		float brushed = vnoise(P * vec3(5.0, 140.0, 5.0));
		// světelný pruh, který každé ~3 s přejede oblek zdola nahoru
		float sweep_y = fract(t * 0.3) * 3.2 - 0.6;
		float sweep = exp(-pow((P.y * 0.9 + P.x * 0.35 - sweep_y) * 8.0, 2.0));
		if (pk == 7) {            // zlato: tekuté zlato proudí po kartáčovaném kovu
			float f = fbm(warp(P * 2.6 * sc, t * 0.35));
			p_alb = mix(vec3(0.72, 0.42, 0.1), vec3(1.0, 0.84, 0.46), smoothstep(0.3, 0.75, f));
			p_metal = 1.0; p_rough = 0.08 + 0.14 * (1.0 - f) + brushed * 0.06;
			p_emit = vec3(1.0, 0.72, 0.3) * (sweep * 1.1 + pow(f, 6.0) * 0.6);
		} else if (pk == 8) {     // platina: chrom s duhovým olejovým filmem, který se přelévá
			float f = fbm(warp(P * 2.2 * sc, t * 0.3));
			vec3 irid = 0.5 + 0.5 * cos(6.2832 * (f * 1.6 + facing * 0.7 + t * 0.12 + vec3(0.0, 0.33, 0.67)));
			p_alb = mix(vec3(0.82, 0.83, 0.86), irid, 0.35 * smoothstep(0.35, 0.7, f));
			p_metal = 1.0; p_rough = 0.05 + brushed * 0.06;
			p_emit = vec3(0.9, 0.95, 1.0) * sweep * 1.5 + irid * pow(f, 4.0) * 0.35;
		} else if (pk == 9) {     // diamant: broušené plošky, lom duhy se točí, jiskry
			vec3 cell = floor(P * 24.0 * sc);
			float hcell = hash3(cell);
			vec3 prism = 0.6 + 0.4 * cos(6.2832 * (hcell + facing * 0.9 + t * 0.18 + vec3(0.0, 0.33, 0.67)));
			p_alb = mix(vec3(0.93, 0.96, 1.0), prism, 0.55); p_metal = 0.85; p_rough = 0.025 + hcell * 0.03;
			float tw = pow(max(sin(t * 2.6 + hcell * 43.0), 0.0), 40.0) * step(0.8, hash3(cell + 3.7));
			p_emit = vec3(3.0) * tw + prism * sweep * 1.6;
		} else if (pk == 10) {    // obsidián: černé sklo, fialová energie teče žilkami
			vec3 q = warp(P * 4.0 * sc, t * 0.2);
			float v = fbm(q);
			p_alb = mix(vec3(0.012), vec3(0.05, 0.035, 0.08), smoothstep(0.4, 0.7, v)); p_metal = 0.4; p_rough = 0.05;
			float vein = 1.0 - aas(abs(v - 0.5), 0.02, 0.01);
			float halo = 1.0 - smoothstep(0.0, 0.09, abs(v - 0.5));
			float pulse = pow(0.5 + 0.5 * sin(P.y * 14.0 - t * 4.0 + v * 12.0), 3.0);
			p_emit = vec3(0.55, 0.15, 1.0) * (vein * (0.5 + 2.2 * pulse) + halo * 0.25) + vec3(0.4, 0.2, 0.9) * sweep * 0.6;
		} else if (pk == 11) {    // krvavý měsíc: maskáč se pomalu přelévá, okraje skvrn rudě žhnou
			float a = fbm(P * 3.2 * sc + vec3(0.0, 0.0, t * 0.12));
			float b = fbm(P * 5.5 * sc + 11.0 - vec3(t * 0.09, 0.0, 0.0));
			float camo = max(aas(a, 0.5, 0.004), aas(b, 0.58, 0.004) * 0.7);
			p_alb = mix(vec3(0.42, 0.015, 0.02), vec3(0.05, 0.0, 0.005), camo); p_metal = 0.75;
			vec3 fc = floor(P * 300.0);
			p_rough = 0.2 + 0.15 * step(0.7, hash3(fc));
			float rim = (1.0 - aas(abs(a - 0.5), 0.012, 0.004)) + (1.0 - aas(abs(b - 0.58), 0.012, 0.004)) * 0.7;
			float flake = step(0.985, hash3(fc + floor(t * 5.0 + hash3(fc) * 5.0)));
			p_emit = vec3(1.6, 0.05, 0.03) * rim * (0.7 + 0.5 * sin(t * 2.5 + P.y * 6.0)) + vec3(2.0, 0.3, 0.25) * flake + vec3(1.0, 0.1, 0.08) * sweep * 0.35;
		} else {                  // láva: struska praská, magma proudí vzhůru a žhne
			vec3 q = warp(P * 3.5 * sc - vec3(0.0, t * 0.25, 0.0), t * 0.15);
			float v = fbm(q);
			float heat = fbm(q * 2.0 + vec3(0.0, -t * 0.8, 0.0));
			float crack = 1.0 - aas(abs(v - 0.5), 0.035, 0.012);
			float glow = 1.0 - smoothstep(0.0, 0.08, abs(v - 0.5));
			p_alb = mix(vec3(0.05, 0.04, 0.035), vec3(0.12, 0.075, 0.055), smoothstep(0.3, 0.7, heat)); p_metal = 0.0; p_rough = 0.8;
			p_alb = mix(p_alb, vec3(0.45, 0.08, 0.015), crack * 0.6);
			vec3 hot = mix(vec3(1.7, 0.28, 0.02), vec3(2.8, 1.05, 0.18), heat * heat);
			p_emit = hot * (crack * (0.55 + 0.6 * heat) + glow * 0.18 * (0.6 + 0.4 * sin(t * 3.0 + heat * 9.0)));
			p_rough = mix(p_rough, 0.35, crack);
		}
		p_alb *= mix(1.0, shade, 0.5);
		base = mix(base, p_alb, prest);
	}
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
	if (int(pattern + 0.5) == 4) rough_suit = mix(rough_suit, 0.15, pat.x);
	float rough_rubber = 0.6 + dirt * 0.25 + edge * 0.1;
	float rough_visor = 0.035 + dirt * 0.25 + g.b * 0.05;   // otisky prstů a šmouhy
	float rough = rough_suit * suit + rough_rubber * rubber + rough_visor * visor + orm.g * other;
	rough = mix(rough, 0.45, bl * 0.4);
	rough = mix(rough, 0.07, soak * (1.0 - visor));
	rough = mix(rough, p_rough + dirt * 0.3, prest);
	ALBEDO = col;
	EMISSION = p_emit * prest * (1.0 - dirt * 0.8) * (1.0 - soak * 0.3);
	ROUGHNESS = clamp(rough, 0.02, 1.0);
	METALLIC = max(max(orm.b * other, visor * 0.95), p_metal * prest * (1.0 - dirt * 0.7));
	SPECULAR = 0.5;
	AO = orm.r;
	AO_LIGHT_AFFECT = 0.55;
	// lakovaná vrstva PVC: ostrý odlesk navrch, slábne pod špínou; mokrý oblek se leskne celý
	CLEARCOAT = clamp(suit * (0.28 - dirt * 0.25) + soak * 0.9 + rubber * 0.08 + prest * 0.4, 0.0, 1.0);
	CLEARCOAT_ROUGHNESS = mix(0.3, 0.05, soak);
	// měkký lesk na hranách záhybů (látka), na gumě slabší
	RIM = 0.18 * suit + 0.08 * rubber;
	RIM_TINT = 0.55;
	vec3 detail = texture(detail_tex, UV * detail_scale).rgb;
	detail = mix(vec3(0.5, 0.5, 1.0), detail, detail_strength * (suit + rubber * 0.35) * (1.0 - soak * 0.6));
	NORMAL_MAP = udn(texture(normal_tex, UV).rgb, detail);
	NORMAL_MAP_DEPTH = normal_strength;
}
