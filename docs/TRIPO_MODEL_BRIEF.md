# Бриф для генерации моделей в Tripo3D (шаттл «Ариадна»)

Источник списка — `docs/SHUTTLE_LEVEL_DESIGN.md` §6. Этот файл — единые правила и готовые
промты, чтобы все предметы выглядели одним набором. Всё ниже — предложение, не утверждено.

## 1. Единый стиль (добавляется к каждому промту)

> low-poly retro-industrial prop, 1990s space shuttle, worn matte paint, scuffed metal,
> chipped enamel, dull desaturated colors (olive green, dirty gray, faded cream, dark brown
> vinyl), PS1-era game asset, chunky simple shapes, no neon, no glowing blue, no holograms,
> no futuristic sci-fi, no text, single object, centered, neutral background

Негативные требования: никаких «синих киберпанк-устройств», светящихся панелей, хрома без
царапин, надписей.

## 2. Технические требования к результату

- Один объект на модель, origin у нижней грани (центр), 1 unit = 1 м, лицом +Z.
- Размеры (м) — по таблице ниже; если Tripo вернул другой масштаб, масштабируем в Godot.
- Треугольников: мелочь до 1000, мебель до 3000–5000.
- Формат GLB, текстура — запечённая в модель; затем при необходимости перекрашиваем
  в палитру корабля или накладываем текстуры из ChatGPT.
- Перед скачиванием показываю превью; скачиваю только после вашего «да» (имя, источник, размер).

## 3. Пробная партия (4 предмета) — сначала только они

| # | Предмет | Размер Ш×В×Г, м | Промт (после общего стиля) |
|---|---|---|---|
| 1 | Пилотское кресло | 0.6×1.2×0.7 | worn pilot seat of an old space shuttle, dark brown cracked vinyl, thin metal frame, headrest, lap belt hanging, simple chunky shapes |
| 2 | Радиоприёмник | 0.45×0.3×0.4 | 1990s military field radio receiver, olive green metal case, round knobs, two slider switches, small dark CRT window, antenna stub, scuffed paint |
| 3 | ЭЛТ-консоль | 0.6×0.5×0.5 | old shuttle cockpit console unit with a small CRT monitor, beige-gray plastic, rows of toggle switches, worn keys, thick cables, boxy and chunky |
| 4 | Капсула сна | 0.95×0.9×2.1 | single crew sleep capsule for a space shuttle, open lid, cream-gray enamel shell, thin worn mattress, seat belts, rounded rectangle, no electronics glow |

## 4. Остальные предметы (после одобрения пробной партии)

Очередь P1 и P2 — в `SHUTTLE_LEVEL_DESIGN.md` §6. Для каждого берётся общий стиль + одна
строка описания предмета с размерами. Группируем по отсекам, чтобы свет и палитра совпадали.

## 5. Процесс

1. Вы покупаете Tripo3D и входите в аккаунт во встроенном браузере (пароль я не ввожу).
2. Я генерирую пробную партию, показываю превью-кадры (в нескольких ракурсах).
3. Вы выбираете: стиль подходит / корректируем (темнее, грязнее, проще).
4. Массовая генерация по отсекам; импорт в Godot, расстановка по уровню, проверка масштаба,
   коллизий и мерцания тестами.
5. Если Tripo даёт слишком гладкие или «нейрослоп»-модели — упрощаем вручную или делаем
   предмет самим из простых форм (правило проекта).
