shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform sampler2D grass_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D grass_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D soil_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rock_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_color : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D sand_normal : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;

varying vec3 world_pos;
varying vec3 world_normal;

float hash(vec2 p) {
	// Integer mixing keeps shared lattice corners identical after GPU optimization.
	uvec2 cell = uvec2(ivec2(p));
	uint h = cell.x * 1664525u ^ cell.y * 1013904223u;
	h = ((h >> 16u) ^ h) * 73244475u;
	h = ((h >> 16u) ^ h) * 73244475u;
	return float(((h >> 16u) ^ h) & 16777215u) / 16777215.0;
}

float noise(vec2 p) {
	vec2 cell = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash(cell), hash(cell + vec2(1, 0)), f.x),
		mix(hash(cell + vec2(0, 1)), hash(cell + vec2(1, 1)), f.x), f.y);
}

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
	TANGENT = normalize(vec3(NORMAL.y, -NORMAL.x, 0.0));
	BINORMAL = normalize(cross(TANGENT, NORMAL));
}

void fragment() {
	vec2 p = world_pos.xz;
	float patch = noise(p * 0.025) * 0.72 + noise(p * 0.08) * 0.28;
	float soil = max(COLOR.r, smoothstep(0.38, 0.88, patch) * 0.62);
	float stone = max(smoothstep(0.12, 0.38, 1.0 - normalize(world_normal).y),
		smoothstep(42.0, 58.0, world_pos.y) * 0.7);
	float beach = 1.0 - smoothstep(0.5, 3.1, world_pos.y + patch * 0.8);
	vec4 weights = vec4((1.0 - soil) * (1.0 - stone), soil * (1.0 - stone), stone, 0.0);
	weights.xyz *= 1.0 - beach;
	weights.w = beach;
	vec2 guv = p / 1.7;
	vec2 duv = p / 2.8;
	vec2 ruv = p / 4.5;
	vec2 suv = p / 3.5;
	// Explicit gradients keep mip levels continuous at layer boundaries.
	vec2 dx = dFdx(p);
	vec2 dy = dFdy(p);
	vec3 color = vec3(0.0);
	vec3 n = vec3(0.0);
	float rough = 0.0;
	if (weights.x > 0.0) {
		vec4 grass_detail = textureGrad(grass_color, guv, dx / 1.7, dy / 1.7);
		vec3 grass = mix(grass_detail.rgb,
			textureGrad(grass_color, p / 6.7 + vec2(0.37, 0.61), dx / 6.7, dy / 6.7).rgb, 0.23);
		color += grass * vec3(0.82, 0.86, 0.72) * weights.x;
		n += textureGrad(grass_normal, guv, dx / 1.7, dy / 1.7).rgb * weights.x;
		rough += grass_detail.a * weights.x;
	}
	if (weights.y > 0.0) {
		vec4 detail = textureGrad(soil_color, duv, dx / 2.8, dy / 2.8);
		color += detail.rgb * vec3(0.83, 0.81, 0.74) * weights.y;
		n += textureGrad(soil_normal, duv, dx / 2.8, dy / 2.8).rgb * weights.y;
		rough += detail.a * weights.y;
	}
	if (weights.z > 0.0) {
		vec4 detail = textureGrad(rock_color, ruv, dx / 4.5, dy / 4.5);
		color += detail.rgb * weights.z;
		n += textureGrad(rock_normal, ruv, dx / 4.5, dy / 4.5).rgb * weights.z;
		rough += detail.a * weights.z;
	}
	if (weights.w > 0.0) {
		vec4 detail = textureGrad(sand_color, suv, dx / 3.5, dy / 3.5);
		color += detail.rgb * weights.w;
		n += textureGrad(sand_normal, suv, dx / 3.5, dy / 3.5).rgb * weights.w;
		rough += detail.a * weights.w;
	}
	float macro = mix(0.84, 1.08, noise(p * 0.013));
	ALBEDO = color * macro;
	NORMAL_MAP = n;
	NORMAL_MAP_DEPTH = mix(0.4, 0.1, smoothstep(35.0, 130.0, length(VERTEX)));
	ROUGHNESS = clamp(rough, 0.65, 1.0);
	SPECULAR = 0.18;
}
