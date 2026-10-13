shader_type spatial;
render_mode cull_disabled, diffuse_burley, specular_schlick_ggx;
// Player-chosen colours for the hero outfit (src/ui/menu/hero_colors.gd). Mirrors the
// StandardMaterial3D it replaces; the mask comes from tools/prepare_m1_textures.py:
// R = cloth weight, G = leather weight, B = luminance. Colours are sRGB, like ranger() there.

uniform sampler2D albedo_tex : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D mask_tex : hint_default_black, filter_linear_mipmap, repeat_enable;
uniform sampler2D normal_tex : hint_normal, filter_linear_mipmap, repeat_enable;
uniform sampler2D orm_tex : hint_default_white, filter_linear_mipmap, repeat_enable;
uniform vec4 albedo_color : source_color = vec4(1.0);
uniform vec3 cloth_color = vec3(0.5);
uniform vec3 leather_color = vec3(0.5);
uniform float cloth_amount = 0.0;
uniform float leather_amount = 0.0;
uniform float metallic = 0.0;
uniform float roughness = 1.0;
uniform float normal_scale = 1.0;
uniform bool use_normal = false;
uniform bool use_orm = false;

vec3 to_linear(vec3 c) {
	c = clamp(c, 0.0, 1.0);
	return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(vec3(0.04045), c));
}

void fragment() {
	vec3 base = texture(albedo_tex, UV).rgb * albedo_color.rgb;
	vec3 mask = texture(mask_tex, UV).rgb;
	float cloth = mask.r * cloth_amount;
	float leather = mask.g * leather_amount;
	vec3 recoloured = cloth * to_linear((0.30 + 1.6 * mask.b) * cloth_color)
		+ leather * to_linear((0.35 + 1.4 * mask.b) * leather_color);
	ALBEDO = base * max(0.0, 1.0 - cloth - leather) + recoloured;
	vec4 orm = use_orm ? texture(orm_tex, UV) : vec4(1.0);
	ROUGHNESS = roughness * orm.g;
	METALLIC = metallic * orm.b;
	SPECULAR = 0.5;
	if (use_normal) {
		NORMAL_MAP = texture(normal_tex, UV).rgb;
		NORMAL_MAP_DEPTH = normal_scale;
	}
}
