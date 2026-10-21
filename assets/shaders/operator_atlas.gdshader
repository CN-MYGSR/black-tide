shader_type spatial;
render_mode cull_disabled;
uniform sampler2D atlas_color : source_color, filter_linear_mipmap_anisotropic;
uniform sampler2D atlas_normal : hint_normal, filter_linear_mipmap_anisotropic;
uniform sampler2D atlas_surface : filter_linear_mipmap;
uniform sampler2D atlas_emission : source_color, filter_linear_mipmap;
uniform vec4 tint : source_color = vec4(1.0);

void fragment() {
	ALBEDO = texture(atlas_color, UV).rgb * tint.rgb;
	NORMAL_MAP = texture(atlas_normal, UV).rgb;
	vec4 surface = texture(atlas_surface, UV);
	ROUGHNESS = surface.g;
	METALLIC = surface.b;
	SPECULAR = surface.a * 0.5;
	EMISSION = texture(atlas_emission, UV).rgb;
}
