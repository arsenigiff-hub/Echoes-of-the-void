# Солнце (low-poly, PS1/PS2-стиль)

Модель сделана генератором `D:\4\.codex_qa\sun\build_sun.py`
(Blockbench-проект + glTF + текстуры). Стиль — гранёная low-poly сфера
с лимб-даркенингом (центр диска светлый, край оранжевый), пиксельные текстуры
и аддитивная корона с лучами. Рассчитано на рендерер проекта (GL Compatibility),
где нет экранного bloom — поэтому свечение сделано спрайтами-квадами.

## Файлы

| файл | что это |
|---|---|
| `sun.bbmodel` | проект Blockbench (формат `free`, один **mesh**-элемент 320 треугольников, текстура встроена). Открывать: Blockbench → File → Open → `assetss/sun/sun.bbmodel` |
| `sun.glb` | готовый меш для Godot (плоские нормали, эмиссивный материал) |
| `sun.png` | атлас 512×256: 16 колонок × 8 рядов ячеек по 32 px. Ряды = лимб-даркенинг (центр → край), колонки = мозаика грануляции по граням |
| `sun_halo.png` | 256×256, мягкое радиальное свечение (используется в двух квадах разного размера) |
| `sun_corona.png` | 256×256, кольцо короны с пиком сразу за лимбом диска |
| `sun_rays.png` | 256×256, лучи-блики (4 длинных + 4 коротких) |
| `sun_0.png` | копия текстуры, которую Godot извлекает из `.glb` при импорте (не редактировать) |

Сцена: `res://scenes/sun.tscn` — `Sun` → `Disc` (инстанс GLB с material_override),
`Corona`, `Glow`, `HaloOuter`, `Rays` (аддитивные billboard-квады).

## Как это стоит в сцене

В `scenes/main.tscn`:

```
Sun      (инстанс scenes/sun.tscn)
    transform: scale 6.56, position (505.134, 73.235, 11.9)
SunLight (DirectionalLight3D)
    светит от солнца на корабль, тёплый, с тенями
```

- Радиус сферы в модели — **8 юнитов Godot** (128 px Blockbench / 16).
  Масштаб 6.56 → мировой радиус ≈ **52.5 м**.
- До кабины (точка глаз пилота ≈ `(9, 3.65, 11.9)`) ≈ **501 м**,
  угловой диаметр диска ≈ **12°** — то есть в окна кабины солнце видно крупно.
- Сторона диска, обращённая к кораблю, — локальная **−X** (там центр
  лимб-градиента). Поэтому солнце нельзя поворачивать без потери градиента.
- Высота 8° над линией глаз — из кабины видно, если чуть поднять взгляд;
  вплотную к окнам видно и без наклона.

## Почему свечение спрайтами

Проект использует `renderer/rendering_method="gl_compatibility"`, а в
Compatibility-рендерере Godot **не поддерживает Environment glow (bloom)**.
Поэтому корона и ореол — это отдельные аддитивные billboard-квады
(`blend_mode = ADD`, `billboard_mode = ENABLED`). Важно:
`billboard_keep_scale = true` — иначе billboard-материал игнорирует масштаб
инстанса, и на солнце в 500 м квады будут крошечными.

## Как подвинуть / настроить

Всё в `scenes/main.tscn` и `scenes/sun.tscn`:

1. **Направление** — двигай `Sun` по дуге вокруг кабины. Тогда поправь и
   `SunLight`: его `-Z` должен смотреть в сторону корабля
   (`Basis.looking_at(ship_center - sun_position)`).
2. **Размер** — масштаб инстанса `Sun`: угловой радиус ≈
   `atan(8 * scale / distance)`. Для 6° при 500 м нужен scale ≈ 6.56.
3. **Яркость диска** — `sun.tscn → StandardMaterial3D_sun → emission_energy_multiplier`
   (сейчас 1.35; больше — белее и «размытее» из-за ACES-тонмаппинга).
4. **Корона/гало** — размеры (`QuadMesh.size`) и прозрачность
   (`albedo_color.a`) у материалов `sun_corona_add`, `sun_glow_add`,
   `sun_halo_outer_add`, `sun_rays_add`.
5. **Свет** — `SunLight.light_energy`, `light_color`, включённые тени:
   свет проходит через настоящие проёмы окон кабины и греет раму.

## Перегенерация

```powershell
$py = "C:\Users\arseni\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe"
& $py D:\4\.codex_qa\sun\build_sun.py
& "D:\Godot_v4.7.2-stable_win64.exe" --headless --path D:\4 --import
& "D:\Godot_v4.7.2-stable_win64.exe" --headless --path D:\4 --script "res://.codex_qa/sun/verify_sun.gd"
```

`build_sun.py` заново генерирует `sun.png`, `sun.glb`, `sun.bbmodel`,
`sun_halo.png`, `sun_corona.png`, `sun_rays.png` и превью
`.codex_qa/sun/preview.png`. Пути/uid не меняются, поэтому `scenes/sun.tscn`
продолжает работать.

## Мелочи, которые легко забыть

* `.bbmodel` использует mesh-элемент формата `free`; UV в пикселях атласа,
  `texture` у граней — индекс текстуры (0).
* `sun_halo.png` и т.д. импортируются как lossless PNG без мипмапов;
  «пиксельность» включается материалом (`texture_filter = NEAREST`).
* Если солнце становится белым блином — уменьшай `emission_energy_multiplier`
  или альфу квадов, а не яркость света.
