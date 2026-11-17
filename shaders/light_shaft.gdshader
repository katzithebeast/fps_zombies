shader_type fog;

uniform vec4 aperture;
uniform vec2 sun_slope;
uniform float top_y;
uniform float bottom_y;
uniform float strength = 1.0;

void fog() {
	float depth = max(top_y - WORLD_POSITION.y, 0.0);
	vec2 at_window = WORLD_POSITION.xz - sun_slope * depth;
	vec2 inset = min(at_window - aperture.xy, aperture.zw - at_window);
	float softness = 0.07 + depth * 0.024;
	float edge = smoothstep(-softness, softness, min(inset.x, inset.y));
	// Rozdělení světla příčkami rámu zůstává čitelné i ve vzdáleném froxel gridu.
	float width = aperture.z - aperture.x;
	float divisions = max(floor(width / 0.8 + 0.5), 2.0);
	float cell = fract((at_window.x - aperture.x) / width * divisions);
	float to_bar = min(cell, 1.0 - cell) * width / divisions;
	float slats = smoothstep(0.025, 0.10 + depth * 0.006, to_bar);
	float crossbar = smoothstep(0.025, 0.10, abs(at_window.y - (aperture.y + aperture.w) * 0.5));
	float ends = smoothstep(bottom_y, bottom_y + 0.35, WORLD_POSITION.y)
		* (1.0 - smoothstep(top_y - 0.10, top_y, WORLD_POSITION.y));
	// Jemná, pomalá změna hustoty vzduchu; hranice kužele zůstávají klidné.
	float air = 0.94 + 0.06 * sin(WORLD_POSITION.x * 1.7 + WORLD_POSITION.z * 1.3 + TIME * 0.12);
	float falloff = mix(1.0, 0.5, clamp(depth / max(top_y - bottom_y, 0.1), 0.0, 1.0));
	DENSITY = 0.018 * strength * edge * ends * air * falloff * mix(0.15, 1.0, slats * crossbar);
	ALBEDO = vec3(0.95, 0.97, 1.0);
}
