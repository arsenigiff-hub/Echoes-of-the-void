# ECHOES OF THE VOID

Прототип психологического космического хоррора от первого лица на Godot 4.7
(GDScript, рендерер — GL Compatibility).

## Документы

- **Сюжет: `docs/PLOT.md`.** Старые подробные главы и roadmap в §7/§12 помечены как ожидающие переработки.
- **Новая игровая петля и механики: `docs/MECHANICS_REWORK.md` — рабочий документ, не утверждённая финальная спецификация.**
- Правила работы для агентов: `AGENTS.md`, `docs/AI_CHAT_RULES.md`.
- Арт-дирекшн и атмосфера: `docs/ART_DIRECTION.md`.
- Новый интерьер и его сборка: `docs/INTERIOR_LAYOUT_B.md`.
- Отчёт о состоянии прототипа (старый корабль): `.codex_qa/work_report/report.md`.
- Схемы механик: `Документы курсовой/03_Спецификация и проектирование/Схемы/`.
- Отчёты и материалы: `Отчеты/` (ежедневные docx), `Документы курсовой/`
  (требования, постановка, отчёты и схемы), референсы `images/`, исходники моделей `blender/`.
- Аудит геометрии и его фиксы: `.codex_qa/model_audit/report.md` (F1–F31, метрики, CSV),
  `.codex_qa/zfight_fix/report.md` (что внедрено, before/after), `docs/QA_ARCHIVE.md`
  (что в git, что локально).

## Запуск

Открыть `project.godot` в Godot 4.7. Маршрут: `scenes/main_menu.tscn` →
`scenes/intro_cutscene.tscn` → `scenes/shuttle_blockout.tscn` (новый шаттл «Ариадна»).

Проверки (headless/консоль):

```powershell
$godot = "D:\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path "D:\Echoes-of-the-void-main" --quit
& $godot --headless --path "D:\Echoes-of-the-void-main" --script "res://tests/test_shuttle_blockout.gd"
& $godot --headless --path "D:\Echoes-of-the-void-main" --script "res://tests/test_game_flow.gd"
# или всё сразу
powershell -ExecutionPolicy Bypass -File tests/run_regression.ps1
```

## Управление

WASD — движение, мышь — обзор, E — осмотреть/взаимодействовать, F — фонарь.

## Статус (2026-11-23)

Остались: главное меню с профилями (SQLite), вступительная катсцена и **новый шаттл** —
линейный, 33 м, 7 отсеков (пилотская, экипаж, камбуз, медотсек, груз, реактор, шлюз), текстуры
из ChatGPT (`assetss/shuttle_textures`), пиксельный PS1-фильтр (`shaders/pixel_psx.gdshader`),
окно в космос, свет и звук по отсекам, переключатель питания (щит автоматов в реакторном отсеке),
осмотр предметов (E) с подсказками.

Старый корабль (интерьер B, верхняя палуба, EVA, радио, сюжетная цепочка, прежние тесты) вынесен
из проекта в архив `D:\Echoes-of-the-void-main_old_ship` (структура папок сохранена).

План и спецификации: `docs/SHUTTLE_LEVEL_DESIGN.md` (отсеки, предметы, свет, звук),
`docs/TRIPO_MODEL_BRIEF.md` (бриф для моделей Tripo3D), сюжет — `docs/PLOT.md`.
Документы про старый корабль (`INTERIOR_LAYOUT_B`, `SHIP_REBUILD_SPEC`, `DOOR_SPEC` и др.) —
исторические.
