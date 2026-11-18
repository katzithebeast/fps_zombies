shader_type spatial;
// Obecný materiál (náhrada StandardMaterial3D) s jedinou změnou: zrcadlová kamera odrazu hladiny
// (je pod hladinou) nekreslí nic, co je pod vodou. Jinak by podvodní části předmětů (dno nafukovacího
// jednorožce, nohy zombie ve vodě, žebříky) zakrývaly odraz jako bílé desky a „duchové“.
render_mode CULL_MODE_PLACEHOLDER;

uniform vec4 albedo_color : source_color = vec4(1.0);
uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_albedo_tex = false;
uniform bool use_vertex_color = false;
uniform float roughness = 1.0;
uniform sampler2D roughness_tex : hint_roughness_r, filter_linear_mipmap, repeat_enable;
uniform bool use_roughness_tex = false;
uniform float metallic = 0.0;
uniform sampler2D metallic_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform bool use_metallic_tex = false;
uniform float specular = 0.5;
uniform sampler2D normal_tex : hint_roughness_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform bool use_normal_tex = false;
uniform float normal_scale = 1.0;
uniform vec3 emission_color : source_color = vec3(0.0);
uniform float emission_energy = 0.0;
uniform sampler2D emission_tex : source_color, hint_default_black, filter_linear_mipmap, repeat_enable;
uniform bool use_emission_tex = false;
uniform vec3 uv1_scale = vec3(1.0);
uniform vec3 uv1_offset = vec3(0.0);
uniform float water_level = 0.0;

varying vec3 wpos;

void vertex() {
	UV = UV * uv1_scale.xy + uv1_offset.xy;
	wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	// Jen kamery, které nevidí vodu (vrstva 2): zrcadlová kamera odrazu a sondy. Hráč ve vypuštěném
	// bazénu (kamera pod y=0) dřív nechal zmizet vše pod hladinou.
	if ((CAMERA_VISIBLE_LAYERS & 2u) == 0u && CAMERA_POSITION_WORLD.y < water_level && wpos.y < water_level - 0.004) discard;
	vec4 alb = albedo_color;
	if (use_albedo_tex) alb *= texture(albedo_tex, UV);
	if (use_vertex_color) alb *= COLOR;
	ALBEDO = alb.rgb;
	ALPHA_PLACEHOLDER
	ROUGHNESS = roughness * (use_roughness_tex ? texture(roughness_tex, UV).r : 1.0);
	METALLIC = metallic * (use_metallic_tex ? texture(metallic_tex, UV).r : 1.0);
	SPECULAR = specular;
	if (use_normal_tex) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
	vec3 em = emission_color * emission_energy;
	if (use_emission_tex) em *= texture(emission_tex, UV).rgb;
	EMISSION = em;
}
