shader_type canvas_item;

// Пост-обработка «жёсткий VHS / камкордер 1997».
// База: грейдинг, PS1-дизеринг и квантование палитры из atmosphere.gdshader.
// Сверху — аналоговый слой: хроматическая аберрация R/B, сильные скан-линии,
// дрожание строк и кадра, зерно ленты, ползущие полосы трекинга,
// редкие горизонтальные разрывы (tape tear) и «прыжки» кадра.
//
// Использование: CanvasLayer > ColorRect (anchors full) с ShaderMaterial.
// Только экранный сэмпл (3 тапа по hint_screen_texture), без доп. текстур —
// работает в GL Compatibility.
//
// Пресеты (preset): 0 = soft (35% артефактов), 1 = medium (65%),
// 2 = hard (100%, значения uniform по умолчанию). Грейдинг, дизеринг и
// виньетка от пресета не зависят — их крутят отдельными параметрами.
// Жёсткий пресет — игровой по умолчанию.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

// --- общая сила и пресет ---
uniform float strength : hint_range(0.0, 2.0) = 1.0;
uniform int preset : hint_enum("Soft", "Medium", "Hard") = 2;

// --- PS1-дизеринг и квантование палитры ---
uniform float dither_size : hint_range(1.0, 8.0, 1.0) = 3.0;
uniform float color_depth : hint_range(4.0, 64.0, 1.0) = 18.0;

// --- VHS-артефакты ---
uniform float chroma_shift : hint_range(0.0, 8.0) = 2.0;   // сдвиг R/B в пикселях
uniform float scanline : hint_range(0.0, 1.0) = 0.28;      // затемнение чётных строк
uniform float grain : hint_range(0.0, 0.3) = 0.060;        // зерно ленты
uniform float tracking : hint_range(0.0, 1.0) = 0.55;      // полосы трекинга
uniform float tear : hint_range(0.0, 1.0) = 0.45;          // горизонтальные разрывы
uniform float jitter : hint_range(0.0, 4.0) = 1.0;         // дрожание в пикселях
uniform float jump : hint_range(0.0, 1.0) = 0.5;           // редкие прыжки кадра

// --- грейдинг и виньетка ---
uniform float vignette : hint_range(0.0, 1.5) = 0.68;
uniform float vignette_softness : hint_range(0.1, 1.0) = 0.60;
uniform vec3 cold_tint = vec3(0.80, 0.94, 1.14);           // холодные тени
uniform vec3 warm_tint = vec3(1.16, 0.96, 0.82);           // тёплые/красные света
uniform float contrast : hint_range(0.5, 2.0) = 1.10;
uniform float brightness : hint_range(0.5, 2.0) = 1.14;
uniform float saturation : hint_range(0.0, 2.0) = 0.78;
uniform float black_crush : hint_range(0.0, 0.2) = 0.018;  // провал чёрных
uniform float flicker : hint_range(0.0, 0.1) = 0.012;      // просадка питания
uniform float fade_amount : hint_range(0.0, 1.0) = 0.0;    // для переходов между сценами

const mat4 bayer_matrix = mat4(
	vec4(0.0, 8.0, 2.0, 10.0),
	vec4(12.0, 4.0, 14.0, 6.0),
	vec4(3.0, 11.0, 1.0, 9.0),
	vec4(15.0, 7.0, 13.0, 5.0)
) / 16.0;

// Лента «обновляется» на 24 кадрах в секунду: артефакты не мельтешат
// на 60/144 Гц и выглядят как запись камкордера.
const float VHS_FPS = 24.0;


float preset_scale() {
	if (preset == 0) {
		return 0.35;
	}
	if (preset == 1) {
		return 0.65;
	}
	return 1.0;
}


float hash11(float p) {
	p = fract(p * 0.1031);
	p *= p + 33.33;
	p *= p + p;
	return fract(p);
}


float hash21(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}


// Гладкий шум для смещения строк внутри полосы трекинга:
// без него края деталей превращаются в «цифровую лесенку».
float vnoise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	f = f * f * (3.0 - 2.0 * f);
	float a = hash21(i);
	float b = hash21(i + vec2(1.0, 0.0));
	float c = hash21(i + vec2(0.0, 1.0));
	float d = hash21(i + vec2(1.0, 1.0));
	return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}


void fragment() {
	// prescale — общий множитель всех плёночных артефактов.
	float prescale = preset_scale() * strength;
	float vhs_t = floor(TIME * VHS_FPS);

	vec2 uv = SCREEN_UV;

	// 1. Дрожание всего кадра: пара пикселей на «кадр» ленты.
	vec2 shake = vec2(hash11(vhs_t * 1.71 + 3.1) - 0.5,
			hash11(vhs_t * 2.37 + 7.9) - 0.5);
	uv += shake * (1.6 * jitter * prescale) * SCREEN_PIXEL_SIZE;

	// 2. Построчное дрожание: соседние пары строк «плывут» влево-вправо.
	float line_id = floor(FRAGCOORD.y * 0.5);
	float line_wob = hash21(vec2(line_id, vhs_t)) - 0.5;
	uv.x += line_wob * (jitter * prescale) * 1.2 * SCREEN_PIXEL_SIZE.x;

	// 3. Полосы трекинга: две узкие зоны медленно ползут вверх по кадру.
	// Ширина и амплитуда подобраны так, чтобы лента «дышала», но картинка
	// не разваливалась на куски во время игры.
	float band1_y = fract(TIME * 0.037 + 0.27);
	float band2_y = fract(TIME * 0.061 + 0.71);
	float band1 = 1.0 - smoothstep(0.0, 0.045, abs(SCREEN_UV.y - band1_y));
	float band2 = 1.0 - smoothstep(0.0, 0.025, abs(SCREEN_UV.y - band2_y));
	float band = clamp(band1 * 0.85 + band2 * 0.55, 0.0, 1.0) * tracking * prescale;

	// В полосе строки плавно уезжают в сторону — срыв трекинга ленты.
	float band_line = 0.0;
	if (band > 0.001) {
		band_line = vnoise(vec2(SCREEN_UV.y * 160.0, vhs_t * 0.55)) - 0.5;
	}
	uv.x += band_line * band * 0.016;

	// 4. Редкие горизонтальные разрывы (tape tear).
	// Событие длится ~0.13 с раз в несколько секунд, внутри — 3 рваные строки.
	float tear_len = 1.9;
	float tear_seg = floor(TIME / tear_len);
	float tear_phase = fract(TIME / tear_len);
	float tear_roll = hash11(tear_seg * 3.71 + 1.7);
	float tear_on = step(1.0 - 0.32 * tear * prescale, tear_roll)
			* step(tear_phase, 0.07) * step(0.001, tear);
	if (tear_on > 0.001) {
		for (int i = 0; i < 3; i++) {
			float seed = tear_seg * 13.7 + float(i) * 5.31;
			float y0 = 0.04 + hash11(seed) * 0.92;
			float h = 0.0015 + hash11(seed + 1.9) * 0.012;
			float line = 1.0 - smoothstep(0.0, h, abs(SCREEN_UV.y - y0));
			uv.x += (hash11(seed + 2.7) - 0.5) * 0.06 * line * prescale;
			uv.y += (hash11(seed + 4.1) - 0.5) * 0.002 * line * prescale;
		}
	}

	// 5. Редкий «прыжок» кадра: изображение дёргается целиком.
	float jump_len = 3.1;
	float jump_seg = floor(TIME / jump_len);
	float jump_phase = fract(TIME / jump_len);
	float jump_roll = hash11(jump_seg * 1.37 + 9.1);
	float jump_on = step(1.0 - 0.30 * jump * prescale, jump_roll)
			* step(jump_phase, 0.07) * step(0.001, jump);
	if (jump_on > 0.001) {
		vec2 jump_off = vec2(hash11(jump_seg + 4.2) - 0.5,
				hash11(jump_seg + 7.7) - 0.5) * vec2(0.03, 0.08);
		uv += jump_off * jump_on;
	}

	// 6. Хроматическая аберрация: R и B расходятся по горизонтали,
	// сильнее к краям кадра и внутри полос трекинга.
	float ca = chroma_shift * prescale * (1.0 + 0.8 * length(SCREEN_UV - 0.5));
	ca += chroma_shift * band * 0.6;
	vec2 ca_off = vec2(ca, ca * 0.12) * SCREEN_PIXEL_SIZE;

	vec3 col;
	col.r = texture(screen_tex, uv + ca_off).r;
	col.g = texture(screen_tex, uv).g;
	col.b = texture(screen_tex, uv - ca_off * 1.15).b;

	// 7. Внутри полосы трекинга — вымывание цвета и шум ленты.
	float band_noise = hash21(FRAGCOORD.xy + vec2(vhs_t * 19.0, vhs_t * 7.0)) - 0.5;
	col += band_noise * band * 0.08;
	float band_luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(col, vec3(band_luma) * 0.85 + 0.04, band * 0.20);

	// 8. Нижняя полоса head switching — тонкий шум у самого низа кадра.
	float head = 1.0 - smoothstep(0.972, 1.0, SCREEN_UV.y);
	col += (hash21(vec2(FRAGCOORD.x, vhs_t)) - 0.5) * head * 0.08 * tracking * prescale;

	// 9. Грейдинг: приглушить цвет, холодные тени, тёплые/красные света.
	float luma = dot(col, vec3(0.299, 0.587, 0.114));
	col = mix(vec3(luma), col, saturation);
	// Тёплый оттенок включается только у действительно ярких участков,
	// иначе кабина целиком уходит в сепию.
	float tone_t = smoothstep(0.35, 0.92, luma);
	tone_t *= tone_t;
	col *= mix(cold_tint, warm_tint, tone_t);

	// Провал чёрных: тени уходят в настоящий ноль.
	col = max(col - black_crush, vec3(0.0)) / max(1.0 - black_crush, 0.001);

	col = (col - 0.5) * contrast + 0.5;
	col *= brightness;
	col = max(col, vec3(0.0));

	// 10. PS1-дизеринг Байера 4x4 + квантование палитры.
	ivec2 cell = ivec2(FRAGCOORD.xy / dither_size) % 4;
	float dither = bayer_matrix[cell.x][cell.y] - 0.5;
	col += vec3(dither / color_depth);
	col = floor(col * color_depth + 0.5) / color_depth;

	// 11. Сильные скан-линии: каждая вторая строка темнее.
	float scan = 0.5 + 0.5 * sin(FRAGCOORD.y * 3.14159265);
	col *= 1.0 - scanline * prescale * scan;

	// 12. Зерно ленты: сильнее в тенях, с цветным оттенком.
	float grain_seed = hash21(FRAGCOORD.xy + vec2(vhs_t * 37.0, vhs_t * 17.0));
	float grain_val = grain_seed - 0.5;
	float grain_w = 0.55 + 0.45 * (1.0 - luma);
	col += grain_val * grain * prescale * grain_w;
	col += vec3(grain_val, -grain_val * 0.6, grain_val * 0.8) * grain * prescale * 0.18;

	// 13. Проседание питания.
	col *= 1.0 - flicker * prescale * (0.5 + 0.5 * sin(TIME * 11.0));

	// 14. Виньетка.
	vec2 d = SCREEN_UV - 0.5;
	float vig = 1.0 - smoothstep(0.80 - vignette_softness, 0.80,
			length(d * vec2(1.0, 1.15)));
	col *= mix(1.0, vig, vignette);

	// 15. Затемнение для переходов между сценами.
	col *= 1.0 - fade_amount;

	COLOR = vec4(col, 1.0);
}
