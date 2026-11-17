shader_type canvas_item;
// Finální průchod obrazu: fisheye (soudkové zkreslení objektivu), chromatická aberace,
// vinětace, filmové zrno a plynule zapínatelný VHS vzhled.

uniform sampler2D screen_tex : hint_screen_texture, filter_linear, repeat_disable;
uniform float fisheye = 0.0;        // 0..1
uniform float vhs = 0.0;            // 0..1
uniform float vignette = 0.32;
uniform float grain = 0.035;
uniform float aberration = 0.0018;
uniform float sharpen = 0.25;
uniform float contrast = 1.0;
uniform float gamma = 1.0;
uniform float vhs_band = 1.0;       // putující pruh rušení (0 = vypnuto)
uniform float vhs_bottom = 1.0;     // zrnitý pruh dole od přepínání hlav (0 = vypnuto)

float hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}
float vnoise(vec2 p) {
	vec2 i = floor(p), f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x), mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0, 1.0)), f.x), f.y);
}
vec3 rgb2yiq(vec3 c) { return vec3(dot(c, vec3(0.299, 0.587, 0.114)), dot(c, vec3(0.596, -0.274, -0.322)), dot(c, vec3(0.211, -0.523, 0.312))); }
vec3 yiq2rgb(vec3 c) { return vec3(c.x + 0.956 * c.y + 0.621 * c.z, c.x - 0.272 * c.y - 0.647 * c.z, c.x - 1.106 * c.y + 1.703 * c.z); }

vec2 lens(vec2 uv, float k, float aspect) {
	vec2 c = uv * 2.0 - 1.0;
	vec2 a = c * vec2(aspect, 1.0);
	// Poloměr normalizovaný úhlopříčkou: stejná síla i na širokém monitoru.
	// Rohy zůstávají uvnitř obrazu; střed se při zapnutí nepřiblíží k singularitě.
	float r2 = dot(a, a) / (aspect * aspect + 1.0);
	float f = (1.0 + k * r2 + k * 0.15 * r2 * r2) / (1.0 + k * 1.15);
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

	// --- objektiv
	float k = fisheye * 0.65;
	vec2 luv = lens(uv, k, aspect);

	// --- VHS geometrie obrazu
	float line = floor(uv.y * 288.0);
	float jit = (hash(vec2(line, floor(t * 50.0))) - 0.5) * 0.0022;
	float wob = sin(uv.y * 9.0 + t * 1.7) * 0.0006 + sin(uv.y * 43.0 - t * 5.1) * 0.0003;
	// pás "trackingu", který pomalu putuje obrazem
	float bandpos = fract(t * 0.07 + 0.3);
	float band = smoothstep(0.035, 0.0, abs(uv.y - bandpos)) * step(0.55, vnoise(vec2(t * 0.35, 3.1))) * vhs_band;
	float tear = band * (hash(vec2(line, floor(t * 30.0))) - 0.3) * 0.03;
	// přepínání hlav u spodního okraje
	float hs = smoothstep(0.972, 1.0, uv.y) * vhs_bottom;
	float hsx = hs * (0.02 + 0.03 * sin(t * 11.0 + uv.y * 300.0));
	luv.x += (jit + wob + tear + hsx) * vhs;
	luv.y += (vnoise(vec2(t * 2.3, 0.0)) - 0.5) * 0.0025 * vhs;

	vec2 dir = luv - 0.5;
	float ca = aberration * (1.0 + fisheye * 2.5) + vhs * 0.0015;
	vec3 col = sample_ca(luv, dir, ca * 2.0);

	// lehké doostření (jen mimo VHS)
	vec3 blur4 = (texture(screen_tex, luv + vec2(px.x, 0.0)).rgb + texture(screen_tex, luv - vec2(px.x, 0.0)).rgb
		+ texture(screen_tex, luv + vec2(0.0, px.y)).rgb + texture(screen_tex, luv - vec2(0.0, px.y)).rgb) * 0.25;
	col += (col - blur4) * sharpen * (1.0 - vhs);

	// --- VHS barva: nízké vodorovné rozlišení jasu, ještě nižší u barvy (rozmazání chroma)
	if (vhs > 0.001) {
		vec2 vpx = vec2(1.0 / (480.0 * aspect), 1.0 / 480.0);      // "rozlišení" pásky nezávislé na monitoru
		vec3 acc = vec3(0.0);
		float wsum = 0.0;
		for (int i = -3; i <= 3; i++) {
			float w = 1.0 - abs(float(i)) / 4.0;
			acc += rgb2yiq(texture(screen_tex, luv + vec2(float(i) * vpx.x * 0.75, 0.0)).rgb) * w;
			wsum += w;
		}
		vec3 soft = acc / wsum;
		vec3 chroma = vec3(0.0);
		float csum = 0.0;
		for (int i = -6; i <= 6; i++) {
			float w = 1.0 - abs(float(i)) / 7.0;
			chroma += rgb2yiq(texture(screen_tex, luv + vec2((float(i) * 1.5 + 1.6) * vpx.x, vpx.y * 0.4)).rgb) * w;
			csum += w;
		}
		chroma /= csum;
		vec3 yiq = vec3(soft.x, chroma.y * 1.12, chroma.z * 1.12);
		yiq.x += (hash(vec2(uv.x * 400.0 + t * 91.0, line)) - 0.5) * 0.045;            // šum jasu
		yiq.yz += (vec2(vnoise(vec2(uv.x * 60.0 + t * 37.0, line * 0.5)), vnoise(vec2(uv.x * 60.0 - t * 29.0, line * 0.5 + 7.0))) - 0.5) * 0.05;
		vec3 v = yiq2rgb(yiq);
		v = mix(v, vec3(dot(v, vec3(0.299, 0.587, 0.114))), 0.12);
		v = v * vec3(1.04, 1.0, 0.95) * 1.02 + vec3(0.035, 0.03, 0.045);                 // zvednuté černé, teplejší bílá
		v *= 0.94 + 0.06 * sin(uv.y * 288.0 * 3.14159 * 2.0);                           // řádky
		// bílé "dropouty" a šum v pásu trackingu
		float drop = step(0.99975 - band * 0.02, hash(vec2(floor(uv.x * 70.0 + t * 13.0), line + floor(t * 24.0))));
		v += drop * 0.45;
		v = mix(v, vec3(hash(uv * 700.0 + t)), clamp(band * 0.55 + hs * 0.8, 0.0, 1.0));
		col = mix(col, v, vhs);
	}

	// --- kontrast s pevnou černou a bílou, pak gama (1 = beze změny)
	// Použije se i na vodu a její odraz; menu se vykresluje až nad tímto průchodem.
	vec3 graded = clamp(col, vec3(0.0), vec3(1.0));
	vec3 low = pow(graded, vec3(contrast));
	vec3 high = pow(vec3(1.0) - graded, vec3(contrast));
	col = pow(low / max(low + high, vec3(0.0001)), vec3(1.0 / gamma));

	// --- vinětace (silnější s rybím okem), zrno
	vec2 vc = (uv - 0.5) * vec2(mix(1.0, aspect * 0.75, fisheye), 1.0);
	float r2 = dot(vc, vc);
	float vig = vignette + fisheye * 0.15 + vhs * 0.08;
	col *= 1.0 - vig * smoothstep(0.05, 0.62, r2);
	col *= 1.0 - fisheye * 0.35 * smoothstep(0.36, 0.62, r2);       // jemný okraj objektivu
	col += (hash(uv * vec2(1920.0, 1080.0) + fract(t * 7.31) * 100.0) - 0.5) * grain;
	// mimo obraz po zkreslení
	float inside = step(0.0, luv.x) * step(luv.x, 1.0) * step(0.0, luv.y) * step(luv.y, 1.0);
	COLOR = vec4(col * inside, 1.0);
}
