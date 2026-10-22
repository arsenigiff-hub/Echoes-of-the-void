shader_type canvas_item;

// Пост-обработка «мёртвый корабль»:
//  - дизеринг + квантование палитры (PS1-стиль);
//  - холодный грейдинг: тени синие, света тусклые;
//  - виньетка, скан-линии, зерно, очень лёгкое мерцание.
// Наложение: CanvasLayer > ColorRect (anchors full) с этим материалом.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

uniform float dither_size : hint_range(1.0, 8.0, 1.0) = 3.0;
uniform float color_depth : hint_range(4.0, 64.0, 1.0) = 18.0;

uniform float desaturation : hint_range(0.0, 1.0) = 0.25;
uniform float contrast : hint_range(0.5, 2.0) = 1.10;
uniform float brightness : hint_range(0.5, 2.0) = 0.98;
uniform vec3 cold_tint = vec3(0.88, 0.96, 1.10);

uniform float vignette_strength : hint_range(0.0, 1.5) = 0.85;
uniform float vignette_softness : hint_range(0.1, 1.0) = 0.55;
uniform float grain_amount : hint_range(0.0, 0.2) = 0.045;
uniform float scanline_amount : hint_range(0.0, 0.2) = 0.030;
uniform float flicker_amount : hint_range(0.0, 0.1) = 0.008;
uniform float fade_amount : hint_range(0.0, 1.0) = 0.0;

const mat4 bayer_matrix = mat4(
	vec4(0.0, 8.0, 2.0, 10.0),
	vec4(12.0, 4.0, 14.0, 6.0),
	vec4(3.0, 11.0, 1.0, 9.0),
	vec4(15.0, 7.0, 13.0, 5.0)
) / 16.0;

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453);
}

void fragment() {
	vec4 src = texture(screen_tex, SCREEN_UV);
	vec3 color = src.rgb;

	// 1. Грейдинг: немного убрать цвет, охладить, поднять контраст на тенях.
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	color = mix(vec3(luma), color, 1.0 - desaturation);
	color *= cold_tint;
	color = (color - 0.5) * contrast + 0.5;
	color *= brightness;
	color = max(color, vec3(0.0));

	// 2. Дизеринг + квантование (Матрица Байера 4x4).
	ivec2 cell = ivec2(FRAGCOORD.xy / dither_size) % 4;
	float dither = bayer_matrix[cell.x][cell.y] - 0.5;
	color += vec3(dither / color_depth);
	color = floor(color * color_depth + 0.5) / color_depth;

	// 3. Скан-линии: каждая третья строка чуть темнее.
	float scan = 0.5 + 0.5 * sin(FRAGCOORD.y * 2.0943951);
	color *= 1.0 - scanline_amount * scan;

	// 4. Зерно (живое, на каждый кадр новое).
	float grain = hash(FRAGCOORD.xy + vec2(TIME * 37.0, TIME * 17.0)) - 0.5;
	color += grain * grain_amount;

	// 5. Лёгкое мерцание экрана — как будто питание проседает.
	color *= 1.0 - flicker_amount * (0.5 + 0.5 * sin(TIME * 11.0));

	// 6. Виньетка.
	vec2 d = SCREEN_UV - 0.5;
	float vignette = smoothstep(0.80, 0.80 - vignette_softness, length(d * vec2(1.0, 1.15)));
	color *= mix(1.0, vignette, vignette_strength);

	// 7. Затемнение/вспышка для переходов.
	color *= 1.0 - fade_amount;

	COLOR = vec4(color, src.a);
}
