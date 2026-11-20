# ECHOES OF THE VOID

Прототип психологического космического хоррора от первого лица на Godot 4.7
(GDScript, рендерер — GL Compatibility).

## Документы

- **Сюжет: `docs/PLOT.md`.** Старые подробные главы и roadmap в §7/§12 помечены как ожидающие переработки.
- **Новая игровая петля и механики: `docs/MECHANICS_REWORK.md` — рабочий документ, не утверждённая финальная спецификация.**
- Правила работы для агентов: `AGENTS.md`, `docs/AI_CHAT_RULES.md`.
- Арт-дирекшн и атмосфера: `docs/ART_DIRECTION.md`.
- Новый интерьер и его сборка: `docs/INTERIOR_LAYOUT_B.md`.
- Отчёт о состоянии прототипа: `.codex_qa/work_report/report.md`.
- Схемы механик: `Документы курсовой/03_Спецификация и проектирование/Схемы/`.
- Отчёты и материалы: `Отчеты/` (ежедневные docx), `Документы курсовой/`
  (требования, постановка, отчёты и схемы), референсы `images/`, исходники моделей `blender/`.
- Аудит геометрии и его фиксы: `.codex_qa/model_audit/report.md` (F1–F31, метрики, CSV),
  `.codex_qa/zfight_fix/report.md` (что внедрено, before/after), `docs/QA_ARCHIVE.md`
  (что в git, что локально).

## Запуск

Открыть `project.godot` в Godot 4.7. Маршрут меню: `scenes/main_menu.tscn` →
`scenes/intro_cutscene.tscn` → `scenes/main.tscn`.

Проверки (headless/консоль):

```powershell
$godot = "D:\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path "D:\Echoes-of-the-void-main" --quit
& $godot --headless --path "D:\Echoes-of-the-void-main" --script "res://tests/verify_radio_no_spin.gd"
& $godot --headless --path "D:\Echoes-of-the-void-main" --script "res://tests/test_ship_layout_b.gd"
```

## Управление

WASD — движение, мышь — обзор, Space — прыжок, E — взаимодействие, F — фонарь.
В EVA: WASD — тяга относительно взгляда, Space/Ctrl — вверх/вниз, инерция и торможение;
взаимодействие с люком — E.

## Статус

Готово: новый интерьер планировки Б (общий отсек, Г-образный проход, мостик, каюта, шлюз), игрок, радио (фокус камеры,
ползунки, диск), фонарь, меню, вступление с процедурной стартовой площадкой, VHS-пост-обработка,
внешний корабль с люком, цикл EVA (выход → невесомость → возврат), атмосферный звук и интро-SFX.

Не реализовано: главы, радиосистема с частотами и пакетами, сохранения, чёрная дыра, ремонт.
План и критерии приёмки — `docs/PLOT.md` §12 (ближайший этап — M0 → M1).
