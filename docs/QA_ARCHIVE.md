# QA-архив: что в git, что остаётся локально

Цель: правила, документация, отчёты и evidence проверок не теряются; тяжёлая QA-свалка
кадров остаётся локальной и воспроизводится командами из `docs/AI_CHAT_RULES.md` §6.

## В git (постоянно)

- `docs/` — вся проектная документация; правила агентов — `AGENTS.md`, `docs/AI_CHAT_RULES.md`.
- `Отчеты/` — ежедневные docx-отчёты; корневые docx — постановка задачи и итоговые отчёты.
- `images/` — референсы и сгенерированные материалы; `blender/`, `future/new_ship.blend` —
  исходники моделей.
- `tests/` — регресс-проверки: `verify_radio_no_spin.gd`, `test_eva.gd`, `show_hatch_closed.gd`.
- `.codex_qa/shipassemble/*.gd` (`build_ship.gd`, `build_and_save.gd`, `save_sky.gd`) —
  канонический генератор интерьера; пересобирает `scenes/ship_interior.tscn`.
- **Evidence аудита геометрии (12.11):**
  - `.codex_qa/model_audit/` — `report.md` (аудит наложений/z-fighting, реестр F1–F31),
    `fixes.csv`, `decal_fixes.csv`, `overlaps.csv`, `analyze.py`, `audit.gd`,
    `confirm_shots.gd`, `make_report.py`, метрики `meta/lights/probes/nodes.json`;
  - `.codex_qa/zfight_fix/` — `report.md` (что внедрено), `apply_fixes.py`
    (детерминированный патч, `--dry-run`/`--apply`/`--root`), `out/scan*.json`, `out/metrics.txt`,
    сжатые before/after — `compare/*.jpg`;
  - `.codex_qa/zfight/` — сканер наложений `scan_overlaps.gd`, `compare_metrics.py`, JSON сканов
    до/после;
  - `.codex_qa/ship_rebuild/capture_final.gd` — финальные кадры корабля.

## Локально (вне git, воспроизводимо)

- `.godot/` — кэш импорта (~340 МБ), пересоздаётся Godot автоматически.
- Остальной `.codex_qa/` — QA-скриншоты, кадры, черновики (~1,5 ГБ). Воспроизводится:
  проверки — командами §6, аудит — `audit.gd` + `analyze.py`, фиксы — `apply_fixes.py --dry-run`.
- Скриншоты before/after полного размера — `.codex_qa/zfight_fix/shots_before|shots_after`
  (в git только сжатые `compare/*.jpg`).
