shader_type canvas_item;
render_mode unshaded;
// VISOR (experiment) – hledí helmy ve vlastním pohledu (scripts/visor.gd).
// Na skle zvenku: krev (cákance, otisk dlaně zombie), kapky vody. Zevnitř: zamlžení od dechu.
// Rám hledí, lom na zakřiveném okraji, šmouhy, které kolem světel dělají jemnou záři.
// Otření rukou: wipe_mask drží pro každé místo číslo posledního otření; skvrna, která vznikla
// dřív, je tam pryč (zbude rozmazaná šmouha ve směru tahu).

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D screen_mip : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D wipe_mask : filter_linear, repeat_disable;
uniform sampler2D blood_atlas : source_color, filter_linear_mipmap, repeat_disable;
uniform vec4 splat_a[8];          // střed (uv), velikost (podíl výšky obrazu), natočení
uniform vec4 splat_b[8];          // čas vzniku, síla, buňka atlasu (0–7), číslo otření při vzniku
uniform vec4 splat_c[8];          // kdy byla otřena (<0 = ne), rychlost stékání, náhoda, -
uniform int splat_count = 0;
uniform float now = 0.0;
uniform float wet = 0.0;          // 0..1 kapky vody na skle
uniform float wet_k = 0.0;        // číslo otření, kdy se hledí naposledy namočilo
uniform float wet_seed = 0.0;
uniform float wet_age = 0.0;      // jak dlouho od namočení (kapky stékají)
uniform float fog = 0.0;          // zamlžení zevnitř
uniform float breath = 0.0;       // právě vydechuje (0..1)
uniform float frame_amt = 1.0;    // rám hledí
uniform vec3 tint = vec3(1.0);    // barva hledí (velmi slabě)
uniform float smudge = 0.35;
uniform float dark_drops = 0.0;     // 1 = lesk kapek jen ve světle (bažina v noci)
uniform float wipe_now = 0.0;     // právě se otírá (0..1) – šmouhy se roztírají

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
vec2 hash2(vec2 p) {
	return vec2(hash(p), hash(p + 17.31));
}
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
float fbm(vec2 p) {
	return vnoise(p) * 0.55 + vnoise(p * 2.13 + 7.1) * 0.3 + vnoise(p * 4.7 + 3.3) * 0.15;
}

// Tloušťka krve jedné skvrny v bodě (souřadnice obrazu s poměrem stran).
float splat_h(int i, vec2 q, float lod) {
	vec4 a = splat_a[i];
	vec4 b = splat_b[i];
	vec2 d = (q - a.xy) / a.z;
	// stékání: spodní polovina se s časem pomalu protahuje dolů
	float age = now - b.x;
	float run = splat_c[i].y * min(age, 10.0);
	if (d.y > 0.0) d.y /= 1.0 + run;
	float c = cos(a.w), s = sin(a.w);
	d = vec2(c * d.x - s * d.y, s * d.x + c * d.y);
	vec2 t = d * vec2(1.0, 320.0 / 360.0) + 0.5;
	if (t.x < 0.0 || t.y < 0.0 || t.x > 1.0 || t.y > 1.0) return 0.0;
	float cell = b.z;
	vec2 cuv = (vec2(mod(cell, 4.0), floor(cell / 4.0)) + t) / vec2(4.0, 2.0);
	return textureLod(blood_atlas, cuv, lod).a * b.y;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	vec2 q = vec2(uv.x * aspect, uv.y);          // jednotky výšky obrazu
	vec2 p = (uv - 0.5) * vec2(aspect, 1.0);

	// --- rám a zakřivení hledí: u okraje sklo láme a rozmazává
	vec2 e = p / vec2(aspect * 0.5 + 0.02, 0.56);
	float shape = pow(pow(abs(e.x), 5.0) + pow(abs(e.y), 4.0), 0.25);
	float rim = smoothstep(0.78, 1.04, shape);
	vec2 bend = -p * rim * rim * 0.018;

	// --- otření (číslo posledního otření v tomto místě); okraj tahu roztřepený, ne rovná hrana
	vec2 muv = uv + vec2((vnoise(vec2(uv.y * 26.0, uv.x * 3.0)) - 0.5) * 0.035, 0.0);
	float wk = (texture(wipe_mask, muv).r * 2.0 + texture(wipe_mask, muv + vec2(0.012, 0.0)).r + texture(wipe_mask, muv - vec2(0.012, 0.0)).r) * 0.25 * 255.0;

	// --- krev
	float bh = 0.0;        // tloušťka krve
	float smear = 0.0;     // rozmazaná šmouha po otření
	for (int i = 0; i < 8; i++) {
		if (i >= splat_count) break;
		float k = splat_b[i].w;
		float wiped = clamp(wk - k, 0.0, 1.0);
		float h = splat_h(i, q, 1.8);
		bh += h * (1.0 - wiped);
		if (wiped > 0.001) {
			// krev se rozetře ve směru tahu (zleva doprava): rozmazaný pruh s tenkými rýhami od prstů
			float hs = 0.0;
			for (int j = 0; j < 7; j++) hs += splat_h(i, q - vec2(0.01 + float(j) * 0.028, 0.0), 4.2);
			hs *= 0.16 * splat_a[i].z / (splat_a[i].z + 0.25);
			float streak = 0.4 + 0.6 * smoothstep(0.25, 0.85, vnoise(vec2(q.x * 1.5, q.y * 38.0 + float(i) * 13.0)));
			float since = splat_c[i].x >= 0.0 ? now - splat_c[i].x : 0.0;
			smear += hs * streak * wiped * exp(-since / 16.0);
		}
	}
	bh = clamp(bh, 0.0, 1.6);
	smear = clamp(smear * 0.45, 0.0, 0.28);
	float film = bh + smear;
	vec2 grad = vec2(dFdx(film), dFdy(film));

	// --- kapky vody (dvě vrstvy: drobné a větší, větší pomalu stékají)
	float wet_vis = 0.0;
	vec2 drop_n = vec2(0.0);
	float drop_h = 0.0;
	if (wet > 0.001) {
		float wiped_w = clamp(wk - wet_k, 0.0, 1.0);
		wet_vis = wet * (1.0 - wiped_w);
		for (int L = 0; L < 2; L++) {
			float n = L == 0 ? 26.0 : 11.0;
			vec2 g = q * n;
			// větší kapky stékají: posun buněk dolů s rozdílnou rychlostí ve sloupcích
			float col = floor(g.x);
			float slide = L == 1 ? wet_age * (0.15 + 0.5 * hash(vec2(col, wet_seed))) : 0.0;
			g.y -= slide;
			vec2 id = floor(g);
			vec2 f = fract(g) - 0.5;
			vec2 r2 = hash2(id + wet_seed * 3.7 + float(L) * 51.0);
			// hustota po skvrnách: někde kapky skoro souvisle, jinde sklo skoro suché
			float patch = smoothstep(0.25, 0.75, fbm(q * 1.7 + wet_seed));
			float exists = step(r2.x, (L == 0 ? 0.8 : 0.5) * wet_vis * (0.25 + 0.75 * patch));
			vec2 c = (hash2(id * 1.37 + 4.1 + wet_seed) - 0.5) * 0.55;
			float rs = hash(id + 9.1 + wet_seed);
			float rad = (L == 0 ? 0.09 : 0.14) + (L == 0 ? 0.2 : 0.24) * rs * rs;
			vec2 dd = (f - c) * vec2(1.0, L == 1 ? 0.8 : 1.0);
			float dl = length(dd) / rad;
			float h = exists * sqrt(max(0.0, 1.0 - dl * dl));
			if (h > drop_h) {
				drop_h = h;
				drop_n = dd / rad;
			}
		}
		// po otření tenké vodní pruhy
		float streaks = wet * wiped_w * smoothstep(0.55, 0.9, vnoise(vec2(q.x * 2.0, q.y * 70.0 + wet_seed))) * 0.5;
		drop_h = max(drop_h, streaks * 0.4);
	}

	// --- obraz za sklem
	vec2 suv = uv + bend + grad * 0.06 - drop_n * drop_h * 0.035;
	float blur = rim * 1.6 + wet_vis * 0.35 + film * 1.4 + drop_h * 1.2;
	vec3 col = mix(texture(screen_tex, suv).rgb, textureLod(screen_mip, suv, blur).rgb, smoothstep(0.0, 0.6, blur));
	// kapka: obrácená čočka, světlý okraj nahoře, tmavší dole
	if (drop_h > 0.0) {
		vec3 inv = textureLod(screen_mip, uv - drop_n * 0.06, 1.0).rgb;
		col = mix(col, inv * 1.05, smoothstep(0.0, 0.4, drop_h) * 0.55);
		float edge = smoothstep(0.75, 0.95, length(drop_n)) * step(0.01, drop_h);
		col *= 1.0 - edge * 0.35 * smoothstep(-0.2, 0.6, drop_n.y);
		float spec = pow(max(0.0, dot(normalize(vec3(-drop_n, 0.6)), normalize(vec3(-0.4, -0.6, 0.7)))), 18.0);
		// ve tmě se kapky nelesknou (lesk jen tam, kde je za sklem světlo; dark_drops = 1 v bažině)
		float lit = smoothstep(0.0, 0.25, dot(textureLod(screen_mip, uv, 3.0).rgb, vec3(0.333)));
		col += spec * 0.35 * drop_h * mix(1.0, lit, dark_drops);
	}

	// --- krev ze zadní strany: prosvítá rudě, silná vrstva je skoro černá
	vec3 absorb = vec3(1.05, 5.0, 5.6);
	float thick = bh * (1.2 + 1.6 * bh) + smear * 1.1;
	col *= exp(-absorb * thick);
	col += vec3(0.05, 0.005, 0.004) * smoothstep(0.0, 0.6, bh) * (0.6 + 0.4 * vnoise(q * 30.0));
	// lesk tlustých kapek krve (světlo shora)
	float gl = clamp(dot(normalize(vec3(-grad * 30.0, 1.0)), normalize(vec3(-0.3, -0.7, 0.65))), 0.0, 1.0);
	col += pow(gl, 24.0) * 0.12 * smoothstep(0.15, 0.6, bh);

	// --- šmouhy a mikro škrábance: kolem jasných míst jemná záře
	float sm = smoothstep(0.35, 0.85, fbm(q * 3.1 + 11.0)) * smudge;
	vec3 glow = max(textureLod(screen_mip, uv, 4.5).rgb - 0.45, vec3(0.0));
	col += glow * (0.18 + sm * 0.9);
	float lum_hi = max(dot(textureLod(screen_mip, uv, 2.5).rgb, vec3(0.333)) - 0.5, 0.0);
	float scratch = smoothstep(0.92, 1.0, vnoise(vec2(dot(q, vec2(0.8, 0.6)) * 90.0, dot(q, vec2(-0.6, 0.8)) * 1.5)));
	col += scratch * lum_hi * 0.35 * smudge;

	// --- zamlžení zevnitř (dech, námaha) – rozmaže a zesvětlí, nejvíc dole a u okrajů
	float fpat = fbm(q * 2.4 + vec2(0.0, now * 0.02));
	float edge_w = smoothstep(0.25, 1.0, shape);
	float mouth = exp(-(p.x * p.x * 5.0 + pow(max(uv.y - 0.55, 0.0) * 2.4, 2.0) * 4.0 + pow(min(uv.y - 0.55, 0.0) * 4.0, 2.0)));
	float fd = fog * (0.25 + 0.75 * edge_w) * (0.6 + 0.6 * fpat) + breath * mouth * 0.55;
	fd = clamp(fd, 0.0, 0.85);
	if (fd > 0.002) {
		vec3 hazy = textureLod(screen_mip, uv + bend, 4.0).rgb;
		vec3 fogc = hazy * 0.8 + vec3(0.06, 0.065, 0.07) + max(hazy - 0.5, vec3(0.0)) * 0.6;
		col = mix(col, fogc, fd);
	}

	// --- rám hledí (pryžové těsnění, jen lehce osvětlené okolím)
	vec3 amb = textureLod(screen_mip, vec2(0.5), 8.0).rgb;
	float frame_m = smoothstep(0.93, 1.12, shape) * frame_amt;
	vec3 frame_c = amb * 0.12 + vec3(0.006);
	col = mix(col, frame_c, frame_m * 0.92);
	col *= 1.0 - rim * 0.18 * frame_amt;
	// velmi slabý nádech barvy hledí a chromatická vada u okraje
	col *= mix(vec3(1.0), tint, 0.07);
	COLOR = vec4(col, 1.0);
}
