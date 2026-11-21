shader_type canvas_item;
// BODYCAM (experiment): obraz jako z kamery na helmě.
// Širokoúhlý objektiv se soudkovým zkreslením, chromatická vada a vinětace, rozmazání pohybem
// a rolling shutter při rychlém otočení, přepálená světla s odlesky objektivu, šum senzoru
// ve tmě, přeostření a stopy po kompresi videa. Když je režim zapnutý, běží před běžným průchodem
// (ten pak přidá už jen VHS, je-li zapnuté) – scripts/bodycam.gd; při zrušení experimentu smazat oba soubory.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform sampler2D screen_mip : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform float distort = 0.34;       // soudkové zkreslení (0 = rovný obraz)
uniform float aberration = 0.0045;  // barevné lemy k okrajům
uniform float vignette = 0.5;
uniform float sharpen = 0.75;       // přeostřený obraz levné kamery
uniform float noise = 0.05;         // šum senzoru (víc ve tmě)
uniform float bloom = 0.55;         // přepálená světla se rozlévají
uniform float flare = 0.4;          // odlesky objektivu od lamp
uniform float chroma_sub = 0.35;    // barva v blocích 8×8 (komprese videa)
uniform vec2 motion = vec2(0.0);    // rozmazání pohybem (UV za dobu expozice)
uniform float shutter = 0.0;        // zkosení obrazu při otáčení (rolling shutter)
uniform float codec = 0.0;          // 0..1 rychlý pohyb = video ztrácí detail
uniform float contrast = 1.0;
uniform float gamma = 1.0;

const float GHOST_S[4] = {0.55, 1.0, 1.45, 0.28};
const float GHOST_W[4] = {0.9, 0.5, 0.35, 0.7};
const vec3 GHOST_C[4] = {vec3(0.5, 0.8, 1.0), vec3(1.0, 0.7, 0.4), vec3(0.8, 0.5, 1.0), vec3(1.0, 0.9, 0.7)};

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float luma(vec3 c) { return dot(c, vec3(0.299, 0.587, 0.114)); }

// Výstupní bod -> bod v (širším) vykresleném obraze. Rohy zůstávají v rozích, střed se zvětší,
// okraje se stlačí: rovné hrany dlaždic se u kraje prohnou jako u akční kamery.
vec2 lens(vec2 uv, float k, float aspect) {
	vec2 c = uv * 2.0 - 1.0;
	vec2 a = c * vec2(aspect, 1.0);
	float r2 = dot(a, a) / (aspect * aspect + 1.0);
	float f = (1.0 + k * r2 + 0.3 * k * r2 * r2) / (1.0 + 1.3 * k);
	return c * f * 0.5 + 0.5;
}

vec3 sample_ca(vec2 uv, vec2 dir, float amt) {
	return vec3(texture(screen_tex, uv - dir * amt).r, texture(screen_tex, uv).g, texture(screen_tex, uv + dir * amt).b);
}

void fragment() {
	vec2 px = SCREEN_PIXEL_SIZE;
	float aspect = px.y / px.x;
	vec2 uv = SCREEN_UV;
	float t = TIME;

	vec2 luv = lens(uv, distort, aspect);
	luv.x += shutter * (uv.y - 0.5);                       // řádky se čtou postupně shora dolů
	vec2 dir = luv - 0.5;
	float r2 = dot(dir * vec2(aspect, 1.0), dir * vec2(aspect, 1.0)) / (aspect * aspect * 0.25 + 0.25);
	float ca = aberration * (0.25 + 1.6 * r2);

	// --- obraz (při rychlém otočení rozmazaný ve směru pohybu)
	vec3 col;
	float ml = length(motion / px);
	if (ml > 1.5) {
		// náhodný posun vzorků po pixelech: místo schodovitých kopií měkká stopa se zrnem
		float j = hash(uv / px + fract(t) * 37.0);
		col = vec3(0.0);
		for (int i = 0; i < 12; i++) {
			float o = (float(i) + j) / 12.0 - 0.5;
			col += sample_ca(luv + motion * o, dir, ca);
		}
		col /= 12.0;
	} else {
		col = sample_ca(luv, dir, ca);
	}

	// --- přeostření (výrazné, s jemnými světlými lemy jako u levné kamery)
	vec3 blur4 = (texture(screen_tex, luv + vec2(px.x, 0.0) * 1.3).rgb + texture(screen_tex, luv - vec2(px.x, 0.0) * 1.3).rgb
		+ texture(screen_tex, luv + vec2(0.0, px.y) * 1.3).rgb + texture(screen_tex, luv - vec2(0.0, px.y) * 1.3).rgb) * 0.25;
	col += clamp(col - blur4, vec3(-0.12), vec3(0.12)) * sharpen * (1.0 - codec * 0.6);

	// --- komprese: barva se počítá po blocích 8×8, při rychlém pohybu ztrácí detail celé bloky
	vec2 res = 1.0 / px;
	vec2 blk = (floor(luv * res / 8.0) + 0.5) * 8.0 / res;
	vec3 blkc = textureLod(screen_mip, blk, 3.0).rgb;
	col = mix(col, vec3(luma(col)) + (blkc - vec3(luma(blkc))), chroma_sub);
	col = mix(col, mix(blkc, col, 0.45), codec * 0.55);

	// --- přepálená světla: záře kolem lamp a odlesky objektivu (duchové zrcadlení přes střed)
	vec3 glow = textureLod(screen_mip, luv, 4.0).rgb * 0.6 + textureLod(screen_mip, luv, 6.0).rgb * 0.4;
	col += max(glow - vec3(0.5), vec3(0.0)) * bloom * vec3(1.0, 0.93, 0.85);
	vec3 fl = vec3(0.0);
	vec2 to_c = vec2(0.5) - luv;
	for (int i = 0; i < 4; i++) {
		float s = GHOST_S[i];
		vec2 p = vec2(0.5) + to_c * s;
		vec3 g = max(textureLod(screen_mip, p, 5.0).rgb - vec3(0.62), vec3(0.0));
		float w = 1.0 - smoothstep(0.0, 0.55, length((p - 0.5) * vec2(aspect, 1.0)));
		fl += g * w * GHOST_W[i] * GHOST_C[i];
	}
	// prstenec (halo) kolem silného zdroje
	vec2 hd = normalize(dir + vec2(1e-5)) * 0.32;
	fl += max(textureLod(screen_mip, luv - hd, 5.0).rgb - vec3(0.7), vec3(0.0)) * 0.35 * vec3(0.7, 0.85, 1.0);
	col += fl * flare;

	// --- senzor: při slabém světle zvedne zesílení -> šum (jas i barva, trochu „flekatý“)
	float avg = luma(textureLod(screen_mip, vec2(0.5), 10.0).rgb);
	float gain = clamp(0.16 / max(avg, 0.01), 1.0, 5.0);
	float l = luma(col);
	float dark = 1.0 - smoothstep(0.04, 0.65, l) * 0.8;
	vec2 cell = floor(uv * res);
	float tf = fract(t * 7.31) * 100.0;
	float n1 = hash(cell + tf) - 0.5;
	float n2 = hash(floor(cell * 0.5) + tf * 1.7) - 0.5;
	vec3 nc = vec3(hash(cell + tf + 11.0), hash(cell + tf + 23.0), hash(cell + tf + 37.0)) - 0.5;
	float amt = noise * (0.4 + gain * 0.3) * dark;
	col += vec3(n1 * 0.6 + n2 * 0.4) * amt + nc * amt * 0.45;

	// --- tón kamery: přepalům se ztrácí barva, lehce chladnější a méně sytý obraz
	l = luma(col);
	col = mix(col, vec3(l), smoothstep(0.78, 1.08, l) * 0.65);
	col = mix(vec3(l), col, 0.88) * vec3(0.97, 1.0, 1.03);

	// --- kontrast a gama ze stejného nastavení jako běžný obraz
	vec3 graded = clamp(col, vec3(0.0), vec3(1.0));
	vec3 lo = pow(graded, vec3(contrast));
	vec3 hi = pow(vec3(1.0) - graded, vec3(contrast));
	col = pow(lo / max(lo + hi, vec3(0.0001)), vec3(1.0 / gamma));

	// --- vinětace objektivu
	col *= 1.0 - vignette * smoothstep(0.25, 1.05, r2);
	COLOR = vec4(col, 1.0);
}
