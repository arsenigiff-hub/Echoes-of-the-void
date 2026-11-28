shader_type canvas_item;
render_mode unshaded;

uniform float amount : hint_range(0.0, 1.0) = 0.0;
uniform float pulse : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 p = (UV - vec2(0.5)) * 2.0;
	float edge = smoothstep(0.38, 1.14, length(p * vec2(0.92, 1.05)));
	float alpha = edge * amount * (0.20 + 0.055 * pulse);
	COLOR = vec4(0.73, 0.023, 0.033, alpha);
}
