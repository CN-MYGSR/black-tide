shader_type spatial;
render_mode diffuse_burley, cull_disabled;

uniform sampler2D atlas : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D detail_roughness : filter_linear_mipmap, repeat_enable;
uniform float tile_meters = 2.0;
uniform vec4 tint : source_color = vec4(1.0);
varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
	vec3 base = texture(atlas, UV).rgb * tint.rgb;
	vec3 w = pow(abs(world_normal), vec3(5.0));
	w /= max(w.x + w.y + w.z, 0.0001);
	vec3 p = world_pos / tile_meters;
	vec3 detail = texture(detail_color, p.zy).rgb * w.x
		+ texture(detail_color, p.xz).rgb * w.y
		+ texture(detail_color, p.xy).rgb * w.z;
	float rough = texture(detail_roughness, p.zy).r * w.x
		+ texture(detail_roughness, p.xz).r * w.y
		+ texture(detail_roughness, p.xy).r * w.z;
	float grain = dot(detail, vec3(0.299, 0.587, 0.114));
	// Preserve atlas paint, camouflage, windows and road markings.
	ALBEDO = base * clamp(grain * 1.8 + 0.35, 0.62, 1.35);
	vec3 nx = texture(detail_normal, p.zy).xyz * 2.0 - 1.0;
	vec3 ny = texture(detail_normal, p.xz).xyz * 2.0 - 1.0;
	vec3 nz = texture(detail_normal, p.xy).xyz * 2.0 - 1.0;
	// Reorient tangent normals per projection, so lighting follows each rock/wall face.
	vec3 bump = vec3(0.0, nx.y, nx.x) * w.x
		+ vec3(ny.x, 0.0, ny.y) * w.y
		+ vec3(nz.x, nz.y, 0.0) * w.z;
	vec3 surface_normal = normalize(world_normal + bump * 0.30);
	NORMAL = normalize((VIEW_MATRIX * vec4(surface_normal, 0.0)).xyz);
	ROUGHNESS = clamp(rough, 0.65, 1.0);
	SPECULAR = 0.2;
}
