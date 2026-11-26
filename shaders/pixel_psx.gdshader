shader_type canvas_item;

// Пиксельный PS1-фильтр для шаттла: крупные квадратные пиксели вместо
// полос VHS. Никаких скан-линий, трекинга и разрывов — только
// «низкое разрешение»: пикселизация, упорядоченный дизеринг (Bayer 4x4),
// ограниченная палитра, лёгкое зерно, холодный тон и виньетка.
// CanvasLayer > ColorRect (anchors full) с ShaderMaterial; работает в GL Compatibility.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

uniform float pixel_size : hint_range(1.0, 12.0, 1.0) = 4.0;   // размер пикселя в экранных px
uniform float color_levels : hint_range(4.0, 64.0, 1.0) = 24.0; // уровней на канал
uniform float dither : hint_range(0.0, 1.5) = 0.8;              // сила дизеринга
uniform float grain : hint_range(0.0, 0.2) = 0.035;             // зерно (по блокам)
uniform float vignette : hint_range(0.0, 1.5) = 0.55;
uniform float saturation : hint_range(0.0, 1.5) = 0.85;
uniform float brightness : hint_range(0.5, 2.0) = 1.15;
uniform vec3 tint = vec3(0.92, 0.98, 1.06);
uniform bool protect_black = false;

const mat4 bayer_matrix = mat4(
	vec4(0.0, 8.0, 2.0, 10.0),
	vec4(12.0, 4.0, 14.0, 6.0),
	vec4(3.0, 11.0, 1.0, 9.0),
	vec4(15.0, 7.0, 13.0, 5.0)
) / 16.0;


float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


void fragment() {
	vec2 screen_size = 1.0 / SCREEN_PIXEL_SIZE;
	vec2 block = floor(FRAGCOORD.xy / pixel_size);
	vec2 uv = (block * pixel_size + 0.5 * pixel_size) / screen_size;
	vec3 col = texture(screen_tex, uv).rgb * brightness;

	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation) * tint;

	// Зерно живёт блоками и обновляется 12 раз в секунду.
	float g = hash21(block + floor(TIME * 12.0) * 17.0) - 0.5;
	float grain_weight = protect_black ? smoothstep(0.0, 0.06, luma) : 1.0;
	col += g * grain * grain_weight;

	// Упорядоченный дизеринг по блокам и квантование палитры.
	int bx = int(mod(block.x, 4.0));
	int by = int(mod(block.y, 4.0));
	float threshold = bayer_matrix[bx][by] - 0.5;
	col = floor(col * color_levels + threshold * dither + 0.5) / color_levels;

	vec2 d = SCREEN_UV - 0.5;
	float v = 1.0 - smoothstep(0.35, 0.95, length(d) * 1.35) * vignette;
	col *= v;

	COLOR = vec4(clamp(col, 0.0, 1.0), 1.0);
}
