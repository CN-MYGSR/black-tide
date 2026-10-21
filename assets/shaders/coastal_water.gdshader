shader_type spatial;
render_mode cull_disabled;

varying vec3 world_pos;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec2 p = world_pos.xz;
	float a = dot(p, vec2(0.72, 0.46)) + TIME * 0.7;
	float b = dot(p, vec2(-0.38, 1.1)) - TIME * 0.9;
	vec3 n = normalize(vec3(cos(a) * 0.045 + cos(b) * 0.026, 1.0,
		sin(a * 0.8) * 0.045 + sin(b) * 0.026));
	NORMAL = normalize((VIEW_MATRIX * vec4(n, 0.0)).xyz);
	float fresnel = pow(1.0 - max(dot(NORMAL, VIEW), 0.0), 4.0);
	ALBEDO = mix(vec3(0.025, 0.11, 0.13), vec3(0.12, 0.24, 0.28), fresnel);
	ROUGHNESS = 0.18;
	METALLIC = 0.15;
	SPECULAR = 0.65;
	ALPHA = mix(0.86, 0.98, fresnel);
}
