# Sources — финальные звуки катсцены intro

Проект: **ECHOES OF THE VOID**. Каталог: `res://assetss/audio/intro/`.
Дата интеграции: 2026-10-26. Все файлы найдены в интернете агентами
`sfx-engine` (двигатели/старт) и `sfx-mech` (механика/тревога/электрика),
проверены и приведены к контракту пайплайном `.codex_qa/sfx_final/process.py`.

Итоговый формат всех файлов: **WAV, 44.1 кГц, 16-bit PCM, stereo, пик −4 dBFS**.
Лицензии (подробно — в [LICENSE_SFX.md](LICENSE_SFX.md)): Mixkit Sound Effects
Free License (атрибуция не требуется) — 8 файлов; SoundBible Public Domain
(атрибуция не требуется) — 1 файл (`hull_groan.wav`). Ничего с YouTube, рипов,
платных ассетов или AI-генерации не использовалось.

## Таблица финальных файлов

| Файл в игре | Слот в `intro_cutscene.gd` | Название звука в источнике | Страница | Прямая ссылка | Автор / издатель | Лицензия | Атрибуция | Обработка |
|---|---|---|---|---|---|---|---|---|
| `power_up.wav` | power_up | Mixkit #3160 “Sci fi power up” | https://mixkit.co/free-sound-effects/discover/sci-fi-power-up-3160/ | https://assets.mixkit.co/active_storage/sfx/3160/3160.wav | Mixkit (Envato) | Mixkit Sound Effects Free License | не требуется | исходник 2.00 s (staging `mech/final_power_up.wav`) → подрезана тишина 0.10/0.57 s → 1.32 s, нормализация −4 dBFS |
| `alarm_loop.wav` | alarm_loop | Mixkit #1653 “Sci fi ship siren alert” | https://mixkit.co/free-sound-effects/discover/sci-fi-ship-siren-alert-1653/ | https://assets.mixkit.co/active_storage/sfx/1653/1653.wav | Mixkit (Envato) | Mixkit Sound Effects Free License | не требуется | из записи вырезано 2 периода сирены (3.34 s) мех-агентом, затем бесшовный кроссфейд-луп 60 мс → 3.27 s |
| `engine_sputter.wav` | engine_sputter | Mixkit #1540 “Failed car ignition” | https://mixkit.co/free-sound-effects/car/ | https://assets.mixkit.co/active_storage/sfx/1540/1540-preview.mp3 | Mixkit (Envato) | Mixkit Sound Effects Free License | не требуется | 2.73 s, подрезка хвоста, нормализация −4 dBFS |
| `engine_ignition.wav` | engine_ignition | Mixkit #1717 “Space Shuttle rocket ignition start” | https://mixkit.co/free-sound-effects/rocket/ | https://assets.mixkit.co/active_storage/sfx/1717/1717-preview.mp3 | Mixkit (Envato) | Mixkit Sound Effects Free License | не требуется | 3.79 s, нормализация −4 dBFS (клиппинга нет: 0 сэмплов на потолке) |
| `engine_rumble_loop.wav` | engine_rumble_loop | Mixkit #1720 “Space rocket full power turbine” | https://mixkit.co/free-sound-effects/rocket/ | https://assets.mixkit.co/active_storage/sfx/1720/1720-preview.mp3 | Mixkit (Envato) | Mixkit Sound Effects Free License | не требуется | 8.28 s, бесшовный кроссфейд-луп 60 мс (стык −19.2 dB ниже p99.9 шагов) |
| `sparks.wav` | sparks | Mixkit #2598 “Futuristic electricity sparks” | https://mixkit.co/free-sound-effects/discover/futuristic-electricity-sparks-2598/ | https://assets.mixkit.co/active_storage/sfx/2598/2598.wav | Mixkit (Envato) | Mixkit Sound Effects Free License | не требуется | исходник 2.00 s → подрезка хвоста → 1.67 s, нормализация −4 dBFS |
| `clunk.wav` | clunk | Mixkit #2980 “Factory metal hard hit” | https://mixkit.co/free-sound-effects/discover/factory-metal-hard-hit-2980/ | https://assets.mixkit.co/active_storage/sfx/2980/2980.wav | Mixkit (Envato) | Mixkit Sound Effects Free License | не требуется | исходник 1.76 s → подрезка тишины 0.46 s → 1.21 s, нормализация −4 dBFS |
| `whoosh_flyby.wav` | whoosh_flyby | Mixkit #1714 “Fast rocket whoosh” | https://mixkit.co/free-sound-effects/rocket/ | https://assets.mixkit.co/active_storage/sfx/1714/1714-preview.mp3 | Mixkit (Envato) | Mixkit Sound Effects Free License | не требуется | исходник 3.65 s → 3.29 s (подрезка краёв), нормализация −4 dBFS |
| `hull_groan.wav` | hull_groan | SoundBible #1625 “Submarine Creaking” (реальная запись корпуса подлодки) | https://soundbible.com/1625-Submarine-Creaking.html | https://soundbible.com/grab.php?id=1625&type=wav | stephan (SoundBible.com) | Public Domain | не требуется | вырезан лучший фрагмент 2.60 s мех-агентом, нормализация −4 dBFS |

## Альтернативы в staging (в игру не входят)

Агенты положили по 2 варианта на слот в `assetss/audio/intro_staging/`.
Ниже — только для истории выбора; **в финальном каталоге игры их нет**.

| Файл staging | Слот | Источник | Лицензия | Почему не выбран |
|---|---|---|---|---|
| `engine/final_engine_ignition.wav` | engine_ignition | Mixkit #1717 | Mixkit Free | **выбран** |
| `engine/alt_engine_ignition.wav` | engine_ignition | Mixkit #1725 “Rocket ignition flames” | Mixkit Free | альтернатива |
| `engine/final_engine_rumble_loop.wav` | engine_rumble_loop | Mixkit #1720 | Mixkit Free | **выбран** |
| `engine/alt_engine_rumble_loop.wav` | engine_rumble_loop | Mixkit #2741 “Large drone engine” | Mixkit Free | альтернатива |
| `engine/final_engine_sputter.wav` | engine_sputter | Mixkit #1540 | Mixkit Free | **выбран** |
| `engine/alt_engine_sputter.wav` | engine_sputter | Mixkit #2941 “Futuristic electronic engine fail” | Mixkit Free | альтернатива |
| `engine/final_whoosh_flyby.wav` | whoosh_flyby | Mixkit #1714 | Mixkit Free | **выбран** |
| `engine/alt_whoosh_flyby.wav` | whoosh_flyby | Mixkit #2623 “Ghostly whoosh passing” | Mixkit Free | альтернатива |
| `engine/final_liftoff_roar.wav` | (не используется сценой) | Mixkit #1719 “Space rocket traveling in distance” | Mixkit Free | сценой не загружается |
| `mech/final_power_up.wav` | power_up | Mixkit #3160 | Mixkit Free | **выбран** |
| `mech/alt_power_up.wav` | power_up | Mixkit #2600 “Electricity static power up” | Mixkit Free | альтернатива |
| `mech/final_alarm_loop.wav` | alarm_loop | Mixkit #1653 | Mixkit Free | **выбран** (loop уже 3.34 s) |
| `mech/alt_alarm_loop.wav` | alarm_loop | SoundBible #1577 “Siren Noise” (KevanGC) | Public Domain | альтернатива |
| `mech/final_sparks.wav` | sparks | Mixkit #2598 | Mixkit Free | **выбран** |
| `mech/alt_sparks.wav` | sparks | Mixkit #1455 “Static electric crackles” | Mixkit Free | альтернатива |
| `mech/final_clunk.wav` | clunk | Mixkit #2980 | Mixkit Free | **выбран** |
| `mech/alt_clunk.wav` | clunk | SoundBible #947 “Metal Bang” (Mike Koenig) | **CC BY 3.0 — нужна атрибуция** | не выбран, чтобы не тащить обязательную атрибуцию |
| `mech/final_hull_groan.wav` | hull_groan | SoundBible #1625 “Submarine Creaking” (stephan) | Public Domain | **выбран** |
| `mech/alt_hull_groan.wav` | hull_groan | Mixkit #3099 “Sci-fi morph moan” | Mixkit Free | альтернатива |

Полные исходные таблицы агентов (включая прямые ссылки и заметки о скачивании):
`assetss/audio/intro_staging/engine/sources.md`,
`assetss/audio/intro_staging/mech/sources.md`.

## Воспроизводимость

```powershell
# пересобрать из staging (строгий лицензионный режим: sources.md обязателен)
& C:\Users\arseni\.dsh\dsh-runtimes\dsh-primary-runtime\dependencies\python\python.exe `
  D:\4\.codex_qa\sfx_final\process.py build
# посмотреть отчёт
D:\4\.codex_qa\sfx_final\report\qa_report.md
# поставить в игру (с бэкапом старого assetss/audio/intro в .codex_qa/sfx_final/backup/)
& ... same python ... D:\4\.codex_qa\sfx_final\process.py install
```

Если staging-папки удалить (рекомендуется перед шиппингом), пайплайн при
`build` автоматически откатится на текущие файлы из `assetss/audio/intro/`
как project-owned fallback — то есть пересборка без staging не ломается.
Сейчас staging уже закрыт `assetss/audio/intro_staging/.gdignore` (добавил Лид
2026-10-26): Godot его не импортирует и в экспорт сырьё не попадёт, но как
источник для повторной сборки папка остаётся на месте.
