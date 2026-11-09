# Intro cutscene SFX — лицензии и происхождение

Проект: **ECHOES OF THE VOID** (Godot 4.7.2). Дата интеграции: 2026-10-26.

Каталог: `res://assetss/audio/intro/` — 9 WAV-файлов с фиксированными именами,
которые загружает `scripts/intro_cutscene.gd` (`_build_audio()`):

`power_up.wav`, `alarm_loop.wav`, `engine_sputter.wav`, `engine_ignition.wav`,
`engine_rumble_loop.wav`, `sparks.wav`, `clunk.wav`, `whoosh_flyby.wav`, `hull_groan.wav`.

Пайплайн и замеры: `.codex_qa/sfx_final/process.py`, отчёт:
`.codex_qa/sfx_final/report/qa_report.md`, полная построчная таблица источников:
[`sources.md`](sources.md) в этом же каталоге.

## Итог по лицензиям (коротко)

| Источник | Лицензия | Файлов в игре | Атрибуция |
|---|---|---|---|
| [Mixkit](https://mixkit.co/) (Envato) | **Mixkit Sound Effects Free License** | 8 из 9 | **не требуется** |
| [SoundBible](https://soundbible.com/) | **Public Domain** | 1 из 9 (`hull_groan.wav`) | **не требуется** |

Все 9 финальных файлов — свободные лицензии, разрешающие коммерческое
использование и модификацию, в том числе **в видеоиграх**. YouTube-рипы,
платные ассеты, «неясные» лицензии и AI-генерация не использовались.

## Текст лицензий

### Mixkit Sound Effects Free License

Страница: <https://mixkit.co/license/#sfxFree> (модалка:
<https://mixkit.co/license/modal/sfxFree/>).

> Items under the Mixkit Sound Effects Free License can be used in your
> commercial and non-commercial projects for free.

Разрешено: скачивать, копировать, модифицировать, распространять и публично
исполнять Item внутри End Product, в том числе **in video games** и
**commercial projects** (перечислены на странице лицензии).

Запрещено: **распространять Item отдельно** (как сток, в тулзе/шаблоне или
вместе с исходниками), выдавать за свои и регистрировать в rights management.
Поэтому:

* сами звуки можно использовать только внутри игры (они и используются — как
  части обработанных WAV, модифицированные, в составе End Product);
* **сырые и альтернативные файлы из `assetss/audio/intro_staging/` нельзя
  включать в публичную сборку/репозиторий** (см. `sources.md` и раздел
  «Что НЕ входит в сборку»).

Атрибуция не требуется. В титрах можно указать по желанию:
`Sound effects: Mixkit (mixkit.co)`.

### Public Domain (SoundBible)

Файл `hull_groan.wav` — SoundBible item #1625 “Submarine Creaking”
(https://soundbible.com/1625-Submarine-Creaking.html), автор указан как
**stephan**, статус на странице — **Public Domain**. Общественное достояние:
ограничений на использование и модификацию нет, атрибуция не требуется
(автор указан из уважения к источнику).

## Атрибуция в игре

Для текущего набора финальных файлов **атрибуция не обязательна**.
Рекомендуемая «вежливая» строка для титров (не обязательна):

> Sound effects: Mixkit (mixkit.co) and SoundBible.com — Mixkit Sound Effects
> Free License / Public Domain.

⚠️ В staging у механического агента лежит **неиспользуемая** альтернатива
`alt_clunk.wav` — SoundBible “Metal Bang” (**CC BY 3.0, автор Mike Koenig**).
Она **не входит** в игру (в `clunk.wav` стоит Mixkit #2980, атрибуция не
требуется). Если когда-нибудь заменить `clunk.wav` на этот альт, в титрах
обязательно появится: `"Metal Bang" by Mike Koenig, SoundBible.com, CC BY 3.0`.
Также в staging есть `alt_alarm_loop.wav` (SoundBible #1577, Public Domain,
автор KevanGC) — тоже не используется.

## Что НЕ входит в сборку (redistribution)

Внутри `res://` лежат папки, которые **не являются частью игры** и не должны
попасть в экспорт/публичный репозиторий:

* `assetss/audio/intro_staging/` — сырые скачанные mp3/wav (Mixkit-каталог,
  SoundBible-кандидаты) и альтернативные обработки. Скачивание/лицензии
  описаны в `intro_staging/engine/sources.md` и
  `intro_staging/mech/sources.md`;
* `.codex_qa/sfx_engine/`, `.codex_qa/sfx_mech/`, `.codex_qa/sfx_final/` —
  QA-скрипты, замеры, бэкапы старых черновиков.

Перед экспортом: `assetss/audio/intro_staging/` уже закрыт `.gdignore` (добавил
Лид 2026-10-26), поэтому staging не импортируется и не попадает в экспорт.
Для `.codex_qa/` стоит добавить `.gdignore` аналогично перед публичной сборкой.
В игре остаются только 9 обработанных WAV в `assetss/audio/intro/`.

## Как подготовлены финальные файлы

Скрипт: `.codex_qa/sfx_final/process.py` (numpy + soundfile, без ffmpeg).
Для всех 9 файлов:

* формат — **WAV, 44100 Hz, 16-bit PCM, stereo** (каналы реально различаются:
  L/R correlation 0.575–0.870, у `sparks` −0.022; полных дублей L=R нет);
* пик нормализован ровно в **−4.0 dBFS** (диапазон контракта −3…−6 dBFS),
  клиппинга нет;
* удалён DC/инфраниз, подрезана тишина по краям, короткие fade-in/out;
* `engine_rumble_loop.wav` и `alarm_loop.wav` — бесшовные лупы: кроссфейд
  **60 мс** (2646 сэмплов), проверка численная: скачок на стыке меньше
  p99.9 обычных шагов на 19.2 и 49.2 dB соответственно;
* для лупов Godot-импорт оставлен с `edit/loop_mode=2` (Forward), так что
  `AudioStreamWAV` играет их нативно без паузы.

Обработка выполнялась для всех файлов одинаково, исходные записи не
перезаписывались — оригиналы остались в staging и в бэкапе
`.codex_qa/sfx_final/backup/intro_20261026_171431/` (старые синтезированные
черновики fx-audio до замены).

## Проверки

* `Godot --headless --path D:\4 --import` — 0 ошибок;
* `.codex_qa/sfx_final/qa_audio.gd` — **PASS 9/9** (sr=44100, ch=2, bits=16,
  peak −4.00 dBFS, loop_mode=1 для двух лупов);
* короткий и полный headless-прогон `scenes/intro_cutscene.tscn` — без
  ошибок/варнингов в консоли.

## Известные ограничения окружения (не лицензии)

1. `project.godot` → `assetss/default_bus_layout.tres`: на Master-шине включён
   `AudioEffectFilter` (default = lowpass, cutoff 2000 Hz, resonance 0.5),
   громкость шины −2.31 dB. Он срезает верх всех звуков (включая эти SFX и
   уже playing mp3). Это pre-existing настройка проекта; bus layout не менялся.
   Если это не задумано как VHS-лоу-фай — Лид уточнит у пользователя, и тогда
   поднять `cutoff_hz` до ~12 кГц или выключить фильтр.
2. `scripts/intro_cutscene.gd` — **был баг**: `_play(key, volume_db, fade_in)`
   принимает третьим аргументом длительность фейд-ина, а передавались
   длительности звуков (`_play("clunk", -6.0, 2.5)` при файле 1.21 s и т.п.),
   поэтому часть SFX звучала внутри рампы от −60 dB. **Исправлено Лидом
   2026-10-26 17:25**: короткие fade-in (0.03–1.2 s), явные громкости
   (−7…−14 dB). Ассеты под фикс менять не потребовалось; уровни перепроверены
   `qa_levels.gd` (все SFX слышны).
