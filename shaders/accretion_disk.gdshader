shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha, fog_disabled;

void fragment() {
	float radial = UV.x;
	float angle = UV.y * 6.2831853;
	float spiral_angle = angle * 4.0 + radial * 19.0
		+ sin(angle * 3.0 - radial * 11.0) * 0.9 - TIME * 0.075;
	float turbulence = 0.5 + 0.5 * sin(spiral_angle + sin(angle * 11.0 + radial * 37.0) * 0.72);
	float filaments = smoothstep(0.28, 0.86, turbulence);
	float heat = 1.0 - radial;
	float inner_rim = smoothstep(0.03, 0.15, radial);
	float outer_fade = 1.0 - smoothstep(0.84, 1.0, radial);
	float density = inner_rim * outer_fade * (0.54 + filaments * 0.42);
	vec3 outer = vec3(0.34, 0.065, 0.018);
	vec3 ember = vec3(0.96, 0.30, 0.06);
	vec3 gold = vec3(1.0, 0.70, 0.30);
	vec3 pale_hot = vec3(1.0, 0.93, 0.77);
	vec3 color = mix(outer, ember, smoothstep(0.0, 0.68, heat));
	color = mix(color, gold, smoothstep(0.42, 0.95, heat) * (0.38 + filaments * 0.34));
	color = mix(color, pale_hot, smoothstep(0.78, 0.99, filaments) * smoothstep(0.08, 0.4, heat) * 0.28);
	float edge = inner_rim * outer_fade;
	ALBEDO = color;
	EMISSION = color * (1.0 + filaments * 1.6);
	ALPHA = edge * (0.60 + filaments * 0.35);
}
