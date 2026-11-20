shader_type spatial;
// First-person hands use controlled albedo so direct sunlight outside the
// ship cannot wash the graphite gloves back into skin-colored highlights.
render_mode unshaded, cull_back;

uniform sampler2D source_texture : source_color, filter_nearest;

void fragment() {
	vec4 texel = texture(source_texture, UV);
	// The derived texture paints both complete glove islands and the suit sleeves;
	// keep its folds readable without letting scene lighting wash the colors out.
	ALBEDO = texel.rgb * 1.35;
	ROUGHNESS = 0.92;
	METALLIC = 0.04;
}
