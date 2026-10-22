# Промпт-пак: хоррор-текстура двери B-3

Генерация вручную в **Google AI Studio** (модель с генерацией изображений,
Nano Banana / Gemini Image). Формат вывода — PNG 1:1. Промпты писать на
английском: с русским текстурные генераторы путаются сильнее.

## Что решили

| Вопрос | Решение |
|---|---|
| Дверь | **B-3** в конце коридора (`assetss/shipkit/equip/door_b3.glb`) |
| Палитра | **Холодный тёмный металл + ржавчина**; красного в текстуре нет — красная лампа над дверью остаётся единственным красным акцентом |
| Формат | **Бесшовный тайл-база + отдельные декали истории** |
| История | **Царапины изнутри + кровь** и **авария / разгерметизация** |
| Стиль | PS1-era 1997: пиксельно, мутная ограниченная палитра, без перспективы и запечённого света |

## Почему именно так (техника)

- У `door_b3.glb` **нет UV-развёртки и нет картинок внутри**: материалы идут
  по именам (`metal_panel`, `metal_dark`, `paint_worn`, `hazard_y`, `hazard_k`,
  `rust`, `crt_green`, `red_lamp`, `glass_grime`, `paint_red`), а
  `scripts/ship_dresser.gd` накладывает текстуры трипланаром по имени
  материала.
- У главного полотна материал **`paint_red`** с базовым цветом
  `(0.254, 0.028, 0.019)`, и в `TILE_FOR_KEY` для него **нет пары** — поэтому
  сейчас полотно плоское тёмно-красное, без грязи.
- Важно: `paint_red` **не уникален для двери** — он же используется в
  `pipe_valves.glb`, `poster.glb`, `suit_rack.glb` (и в `radio.glb`, но там
  другая система материалов). Поэтому нельзя просто добавить глобальную
  пару `"paint_red": "door_b3_steel"` — покраснеют/посереют вентили и
  стойка. В `ship_dresser.gd` сделаю **спец-случай по узлу `door_b3`**:
  внутри двери `paint_red` получает новую текстуру, у остальных пропсов
  остаётся как было.
- Трипланар = текстура повторяется на панелях произвольно, поэтому база
  должна быть **бесшовной и без «приметных» объектов** (никакой целой двери,
  окна, ручки, надписей — их даёт геометрия и отдельные декали).
- Сюжет — **декалями** (квады с альфой, как `b3_number` и плакаты): их можно
  двигать, масштабировать и компоновать по месту, не трогая тайл.

## Технические параметры

| Файл | Назначение | Параметры |
|---|---|---|
| `assetss/tex_gemini/tiles/door_b3_steel.png` | база полотна | 1:1, генерить 1024, в игре 512, бесшовный тайл |
| `assetss/tex_gemini/decals/door_b3_claw_blood.png` | борозды от когтей + кровь | 1:1, чёрный фон (пойдёт в альфу) |
| `assetss/tex_gemini/decals/door_b3_blood_hands.png` | кровавые отпечатки + мазок | 1:1, чёрный фон |
| `assetss/tex_gemini/decals/door_b3_decomp.png` | иней/потёки/коррозия (разгерметизация) | 1:1, чёрный фон, опционально |

Палитра (из `docs/ART_DIRECTION_V2.md`): металл `#22262a`–`#343a38`,
ржавчина `#6b3c22`–`#8a4a26`, грязно-серые сколы. Красный `#d33a2c` —
только лампа, в текстуре его быть не должно.

## Общий хвост стиля (добавлять в конец каждого промпта)

> PS1-era 1997 video game texture, pixelated, limited muted palette, grimy
> industrial derelict spaceship, flat orthographic view, no perspective, no
> baked lighting, no shadows, no text, no watermark, square 1:1.

Для базы в начало обязательно: `seamless tileable`.

---

## 1. База полотна: холодная сталь, пережившая разгерметизацию

**Файл:** `door_b3_steel.png` (1024×1024, потом 512, бесшовный тайл).

**Промпт:**

> Seamless tileable texture of a cold dark steel armored door panel of a
> derelict spaceship, damaged by decompression: chipped blue-grey paint
> revealing bare steel, rust bleeding from seams and bolt holes, vertical
> dirty water streaks, dried condensation stains, pitting corrosion, fine
> scratches and scuffs, subtle shallow dents, dust and grime packed into
> crevices, thin frost residue in the corroded areas. Cold desaturated
> palette only: dark blue-grey steel #22262a to #343a38, rust browns
> #6b3c22 to #8a4a26, dirty grey scuffs. No red, no warm colors. Uniform wear
> distribution, no single obvious feature, no rivet rows, no bolts pattern,
> no warning stripes, no labels, no window, no handle. Flat orthographic
> surface texture, even diffuse lighting, no directional shadows, no specular
> highlights. Seamless tileable, PS1-era 1997 video game texture, pixelated,
> limited muted palette, grimy industrial derelict spaceship, flat
> orthographic view, no perspective, no baked lighting, no shadows, no text,
> no watermark, square 1:1.

**Опционально, если захочется намёка на прошлое:** добавь в конец
`faint traces of old faded dark red paint peeling only at the panel seams` —
но это уже не «красный», а еле уловимый след.

**Чего добиваемся:** от двери не должен идти «пластиковый» ровный цвет;
должны читаться грязная сталь, ржавые языки от кромок и швов, затёки.
Крупных деталей нет — они множатся трипланаром и выдают повтор.

---

## 2. Декаль: царапины изнутри + кровь

**Файл:** `door_b3_claw_blood.png` (1:1, чёрный фон → альфа).

**Промпт:**

> Isolated cluster of deep parallel claw gouges torn through cold dark grey
> painted steel, ragged raised metal lips, flaking chipped paint, grooves
> filled with old dried dark red-brown blood that smears and runs down in
> thin dried streaks, a few scattered dark blood droplets, grime and dust
> around the damage. Pure black background, isolated object, roughly
> centered, flat orthographic front view, no door, no frame, no window, no
> handle, no perspective, no shadows. Cold desaturated palette, dried blood
> is dark red-brown but clearly readable against pure black, never pure
> black. PS1-era 1997 video game texture, pixelated, limited muted palette,
> grimy industrial derelict spaceship, flat orthographic view, no
> perspective, no baked lighting, no shadows, no text, no watermark, square
> 1:1.

**Смысл:** следы должны читаться как *изнутри*: борозды с рваными краями
металла, кровь тянется по ним вниз. Замазывать весь кадр не надо — это
декаль, её поставим на 1/3 полотна.

---

## 3. Декаль: кровавые отпечатки и мазок

**Файл:** `door_b3_blood_hands.png` (1:1, чёрный фон).

**Промпт:**

> Two dried dark red-brown handprints and a long smeared drag trail of old
> blood on a flat worn dark grey metal surface, broken fingerprint ridges,
> chipped paint under the smear, thin dried drips running downward, grime
> and dust. Pure black background, isolated, centered, flat orthographic
> front view, no door, no frame, no window, no handle, no perspective, no
> shadows. Cold desaturated palette, dried blood dark red-brown but clearly
> readable against pure black, never pure black. PS1-era 1997 video game
> texture, pixelated, limited muted palette, grimy industrial derelict
> spaceship, flat orthographic view, no perspective, no baked lighting, no
> shadows, no text, no watermark, square 1:1.

**Смысл:** «кто-то упирался ладонями и сползал» — ставится ниже смотрового
окна или у края полотна. Отпечатки — не ярко-алые: тёмная бурная кровь.

---

## 4. Декаль: разгерметизация (иней, потёки, коррозия) — по желанию

**Файл:** `door_b3_decomp.png` (1:1, чёрный фон).

**Промпт:**

> Jagged frost creep and dried condensation on flat cold dark steel, pale
> blue-white ice crystal fringes, dirty water stains and salt-like residue
> damaging chipped paint, pitted rust-brown corrosion spots, thin dried
> streaks running downward. Pure black background, isolated, flat
> orthographic front view, no door, no frame, no window, no handle, no
> perspective, no shadows. Cold desaturated palette, pale frost is readable
> against pure black, no warm colors, no red. PS1-era 1997 video game
> texture, pixelated, limited muted palette, grimy industrial derelict
> spaceship, flat orthographic view, no perspective, no baked lighting, no
> shadows, no text, no watermark, square 1:1.

**Смысл:** кладётся узкой полосой у кромки полотна/вокруг окна — намёк, что
дверь держала давление и травила. Если декаль выйдет слишком шумной — можно
не использовать: база уже несёт потёки и ржавчину.

---

## Негатив (общий, добавлять к каждому промпту)

> photo, photorealism, 3D render, CGI, perspective, vanishing point, whole
> door, door frame, handle, window, porthole, lettering, numbers, logo,
> watermark, signature, bright red, saturated colors, warm lighting, orange
> glow, glossy reflections, bloom, vignette, depth of field, blur, cartoon,
> anime, painting, concept art, canvas texture, walls, floor, background
> objects, baked shadows, directional light, collage, multiple objects,
> grid, UI.

## Как генерить в AI Studio

1. Playground → модель с генерацией изображений (Nano Banana). Формат
   кадра — 1:1.
2. Вставь промпт целиком. Сгенерируй **3–4 варианта** базы, а не один:
   первый почти всегда «слишком чистый».
3. Если результат не тот — не переписывай промпт с нуля, а проси правку:
   * «грязнее, темнее, больше ржавых потёков, меньше контраста»;
   * «убери повторяющиеся заклёпки/рисунок, сделай распределение
     равномерным»;
   * «только плоская текстура поверхности, не дверь»;
   * «мрачнее, палитра холоднее, никакого красного».
4. Декали генерить **по одной штуке на кадр**, не просить «набор» — иначе
   модель нарисует коллаж.
5. Скачать PNG с именами файлов **ровно как в таблице выше** (латиницей) и
   прислать сюда пачкой.

## Критерии приёмки

- **База:** с 2–3 метров под фонарём полотно читается как грязная сталь,
  а не ровное красное пятно; повтор тайла не бросается в глаза; нет
  красного, нет «приметных» пятен, которые будут множиться.
- **Декали:** кровь и борозды видны на 512 px; чёрный фон чистый (легко
  уйдёт в альфу); края рваные, без ровных «рамок» и без следов двери.
- **Вместе:** дверь остаётся самой «рассказывающей» точкой коридора, но не
  выбивается из палитры корабля.

## Что я сделаю с файлами

1. Тайл: ужму в 512, палитра ~28 цветов → `assetss/tex_gemini/tiles/`,
   в `scripts/ship_dresser.gd` добавлю дверной материал для `paint_red`
   только внутри узла `door_b3` (остальные `paint_red`-пропсы не трогаю).
2. Декали: чёрный фон → альфа, обрезка, 512 → `assetss/tex_gemini/decals/`,
   добавлю в `DECALS` постановки у двери B-3 (с отступом 0.07 м от
   плоскости, чтобы не было z-fighting).
3. Проверка: `D:\Godot_v4.7.2-stable_win64.exe --headless --path D:\4 --import`,
   без ошибок; рендеры «до/после» из коридора и вблизи под фонарём →
   `.codex_qa/door_b3/`, покажу сюда.
