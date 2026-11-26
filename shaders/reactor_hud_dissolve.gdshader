shader_type canvas_item;
render_mode unshaded;

uniform vec2 panel_size = vec2(656.0, 159.0);
uniform vec4 plate_color : source_color = vec4(0.031, 0.028, 0.025, 0.97);

float cell_hash(vec2 id) {
	vec3 p = fract(vec3(id.xyx) * 0.1031);
	p += dot(p, p.yzx + 33.33);
	return fract((p.x + p.y) * p.z);
}

void fragment() {
	vec2 cell_id = floor(UV * panel_size / 4.0);
	vec2 cell_center = (cell_id + 0.5) * 4.0;
	vec2 to_edge = min(cell_center, panel_size - cell_center);
	float irregularity = (cell_hash(floor(cell_id / 7.0) + vec2(9.0, 31.0)) - 0.5) * 8.0;
	// Thin out the squares at the edge instead of fading individual squares.
	float density = smoothstep(3.0, 22.0, min(to_edge.x, to_edge.y) + irregularity);
	float pixel_alpha = cell_hash(cell_id) < density ? plate_color.a : 0.0;
	COLOR = vec4(plate_color.rgb, pixel_alpha);
}
