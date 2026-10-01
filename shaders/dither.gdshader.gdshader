shader_type canvas_item;

// Захватываем картинку 3D-экрана
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_nearest;

// Настройки размера точек и палитры в Инспекторе
uniform float dither_size : hint_range(1.0, 8.0, 1.0) = 2.0;
uniform float color_depth : hint_range(2.0, 64.0, 1.0) = 16.0;

// Матрица дизеринга 4x4 (Матрица Байера)
const mat4 bayer_matrix = mat4(
	vec4(0.0, 8.0, 2.0, 10.0),
	vec4(12.0, 4.0, 14.0, 6.0),
	vec4(3.0, 11.0, 1.0, 9.0),
	vec4(15.0, 7.0, 13.0, 5.0)
) / 16.0;

void fragment() {
	// 1. Берем исходный цвет пикселя 3D-мира
	vec4 screen_color = texture(SCREEN_TEXTURE, SCREEN_UV);
	
	// 2. Вычисляем пиксельную позицию сетки
	ivec2 screen_pos = ivec2(FRAGCOORD.xy / dither_size) % 4;
	float dither_value = bayer_matrix[screen_pos.x][screen_pos.y] - 0.5;
	
	// 3. Подмешиваем точечную сетку к цвету
	vec3 color = screen_color.rgb + vec3(dither_value / color_depth);
	
	// 4. Ограничиваем количество цветов (квантование палитры)
	color = floor(color * color_depth) / color_depth;
	
	COLOR = vec4(color, screen_color.a);
}