# Приборная панель (cockpit instrument panel)

Модель сделана генератором `D:\4\.codex_qa\panel\build_panel.py` (Blockbench-проект + glTF + текстура).

## Файлы

| файл | что это |
|---|---|
| `instrument_panel.bbmodel` | проект Blockbench (формат 5.0, текстура встроена) — открывать в Blockbench `D:\BlockBench\Blockbench.exe` |
| `instrument_panel.glb` | готовая модель для Godot (текстура внутри, 7 частей-групп) |
| `instrument_panel.png` | текстура 512x512, палитра взята из `shuttle_texture.png` корабля |
| `instrument_panel_0.png` | копия текстуры, которую Godot извлекает из `.glb` при импорте (не редактировать) |

## Размеры и ориентация

* 1 блок Blockbench = 16 юнитов = **1 юнит Godot**.
* Габарит: **52 x 24 x 12.6** юнита = **3.25 x 1.5 x 0.79** юнита Godot.
* Начало координат — **низ по центру**: модель ставится прямо на палубу (низ на `y = 0`).
* **Перед панели смотрит в -Z** (грань `north`). Пилот в корабле сидит в носу (больший X) и смотрит вперёд (+X), поэтому панель надо повернуть на **+90° по Y**, чтобы экран смотрел назад, на пилота.
* Экран и приборы выступают в -Z на ~1.5 юнита, блок РУД — в -Z на 7.6 юнита. Учитывай при расстановке, чтобы не упереться в пилота.

## Группы (можно двигать/скрывать по отдельности и в Blockbench, и в Godot)

`frame` (корпус, козырёк, плашки), `display` (МФД с авиагоризонтом), `gauges` (4 стрелочных прибора),
`indicators` (3 мини-прибора + 3 лампы), `radio` (пульт связи COMM), `switches` (12 тумблеров и ламп внизу),
`throttle` (пьедестал и РУД).

## Если Godot не подхватил модель

Редактор импортирует ресурсы при сканировании файловой системы (по фокусу окна). Если модель
не появилась — правый клик по `instrument_panel.glb` в панели «Файловая система» → **Reimport**.

## Перегенерация

```powershell
& 'C:\Users\arseni\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe' `
  D:\4\.codex_qa\panel\build_panel.py      # пересобрать модель и текстуру
& 'C:\Users\arseni\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe' `
  D:\4\.codex_qa\panel\test_panel.py       # проверки (структура, UV, намотка, габариты)
```
