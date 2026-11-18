shader_type spatial;
render_mode specular_schlick_ggx;

// Tinted automotive glass with a procedural reflected environment. No alpha
// sorting or screen readback: also works in the offline mobile sprite bake.
uniform vec3 tint : source_color = vec3(0.026, 0.046, 0.061);

void fragment() {
	vec3 n = normalize(NORMAL);
	vec3 v = normalize(VIEW);
	vec3 world_n = normalize((INV_VIEW_MATRIX * vec4(n, 0.0)).xyz);
	vec3 world_v = normalize((INV_VIEW_MATRIX * vec4(v, 0.0)).xyz);
	vec3 reflected = reflect(-world_v, world_n);
	float fresnel = 0.04 + 0.96 * pow(1.0 - clamp(dot(n, v), 0.0, 1.0), 5.0);
	vec3 sky = mix(vec3(0.23, 0.32, 0.42), vec3(0.45, 0.60, 0.73),
		smoothstep(0.04, 0.90, reflected.y));
	vec3 environment = mix(vec3(0.085, 0.125, 0.165), sky,
		smoothstep(-0.16, 0.16, reflected.y));
	float box_a = pow(max(dot(reflected, normalize(vec3(0.35, 0.88, 0.32))), 0.0), 42.0);
	float box_b = pow(max(dot(reflected, normalize(vec3(-0.75, 0.50, -0.35))), 0.0), 64.0);
	environment += vec3(0.65, 0.76, 0.83) * (box_a * 0.40 + box_b * 0.20);
	float wall_box = (pow(abs(reflected.x), 10.0) + pow(abs(reflected.z), 10.0))
		* exp(-pow((reflected.y + 0.12) / 0.25, 2.0));
	environment += vec3(0.38, 0.46, 0.51) * wall_box;
	float edge = min(min(UV.x, 1.0 - UV.x), min(UV.y, 1.0 - UV.y));
	float frit = smoothstep(0.005, 0.024, edge);
	vec3 interior = tint * mix(0.72, 1.10, COLOR.r);
	ALBEDO = mix(vec3(0.007, 0.010, 0.013), interior, frit);
	EMISSION = environment * (0.48 + 0.90 * fresnel) * frit;
	METALLIC = 0.0;
	ROUGHNESS = mix(0.46, 0.16, frit);
	SPECULAR = 0.52 * frit;
}
