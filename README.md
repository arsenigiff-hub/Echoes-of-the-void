# ECHOES OF THE VOID

Прототип психологического космического хоррора от первого лица на Godot 4.7
(GDScript, рендерер — GL Compatibility).

## Документы

- **Сюжет, структура игры и roadmap: `docs/PLOT.md` — единственный источник истины по истории.**
  Задание на реализацию для ИИ и этапы M0–M6 — §12.
- Правила работы для агентов: `AGENTS.md`, `docs/AI_CHAT_RULES.md`.
- Арт-дирекшн и атмосфера: `docs/ART_DIRECTION.md`.
- Отчёт о состоянии прототипа: `.codex_qa/work_report/report.md`.
- Схемы механик: `diagrams_echoes_of_the_void.drawio`, `activity_*.xml`, `bpmn_*.xml`.
- Отчёты и материалы: `Отчеты/` (ежедневные docx), корневые docx («Постановка задачи»,
  итоговые отчёты), референсы `images/`, исходники моделей `blender/`, `future/new_ship.blend`.
- Аудит геометрии и его фиксы: `.codex_qa/model_audit/report.md` (F1–F31, метрики, CSV),
  `.codex_qa/zfight_fix/report.md` (что внедрено, before/after), `docs/QA_ARCHIVE.md`
  (что в git, что локально).

## Запуск

Открыть `project.godot` в Godot 4.7. Маршрут меню: `scenes/main_menu.tscn` →
`scenes/intro_cutscene.tscn` → `scenes/main.tscn`.

Проверки (headless/консоль):

```powershell
$godot = "D:\Godot_v4.7.2-stable_win64.exe"
& $godot --headless --path "D:\4" --quit                                   # проект грузится без ошибок
& $godot --headless --path "D:\4" --script "res://tests/verify_radio_no_spin.gd"   # радио-регресс
```

## Управление

WASD — движение, мышь — обзор, Space — прыжок, E — взаимодействие, F — фонарь.
В EVA: WASD — тяга относительно взгляда, Space/Ctrl — вверх/вниз, инерция и торможение;
взаимодействие с люком — E.

## Статус

Готово: интерьер корабля (коридор Deck B, мостик, каюта, шлюз), игрок, радио (фокус камеры,
ползунки, диск), фонарь, меню, вступление с процедурной стартовой площадкой, VHS-пост-обработка,
внешний корабль с люком, цикл EVA (выход → невесомость → возврат), атмосферный звук и интро-SFX.

Не реализовано: главы, радиосистема с частотами и пакетами, сохранения, чёрная дыра, ремонт.
План и критерии приёмки — `docs/PLOT.md` §12 (ближайший этап — M0 → M1).
