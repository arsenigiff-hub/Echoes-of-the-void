#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""apply_fixes.py — детерминированно вносит фиксы наложений/z-fighting (аудит
.codex_qa/model_audit, реестр F1–F31) в канонические сборщики интерьера.

Правит ТОЛЬКО три файла:
  * .codex_qa/shipassemble/build_ship.gd   — геометрия корабля
  * .codex_qa/shipassemble/build_and_save.gd — POLISH_PROPS, оболочка, декали
  * scripts/ship_dresser.gd                — позиции 16 декалей (F21/F22)

Использование:
  python apply_fixes.py                  # dry-run: unified diff, ничего не пишет
  python apply_fixes.py --apply          # применить правки к D:\\4
  python apply_fixes.py --dry-run --root <корень>   # тест на копиях

Требования: stdlib, идемпотентность, падение при несовпадении якоря.

Фиксы, которые НЕ вносятся (зафиксировано в отчёте):
  * F2  — устарел: шлюз уже собран из GLB-модуля airlock_room ровно 3.8 м встык
          с коридором, «мокрых плиток» в коде нет. Смена X_AIR_AFT на -8.0
          создала бы 0.1-м щели в полу/потолке шлюза.
  * F25 — чистка мёртвых sub_resource в scenes/main.tscn: правится вручную
          в редакторе (сцена вне зоны ответственности этого скрипта).
  * F27–F30 — по аудиту не баги (ложные AABB / штатная посадка).
"""

from __future__ import annotations

import argparse
import difflib
import sys
from pathlib import Path

SHIP = ".codex_qa/shipassemble/build_ship.gd"
BSAVE = ".codex_qa/shipassemble/build_and_save.gd"
DRESSER = "scripts/ship_dresser.gd"

# ---------------------------------------------------------------- build_ship --

P_F1 = (
    "F1 X_CORR_FWD 9.4 -> 10.0 (коридор и мостик встык на x=10.0)",
    SHIP,
    "const X_CORR_FWD := 9.4\n",
    "const X_CORR_FWD := 10.0  # F1: стык с мостиком встык (было 9.4 — наложение 0.6 м)\n",
)

P_F89 = (
    "F8/F9 hazard-трим: не ставить в проёме каюты и на барельефе панелей b",
    SHIP,
    '\tx = X_CORR_AFT\n'
    '\tvar i := 0\n'
    '\twhile x < X_CORR_FWD:\n'
    '\t\tvar panel := "wall_panel_a.glb" if i % 2 == 0 else "wall_panel_b.glb"\n'
    '\t\t# проём в каюту на x≈5: эту панель не ставим\n'
    '\t\tif absf((x + 1.0) - ROOM_DOOR_X) > 0.1:\n'
    '\t\t\t_spawn(panel, Vector3(x + 1.0, FLOOR, Z0), Vector3(0, 0, 0), ship)\n'
    '\t\t_spawn(panel, Vector3(x + 1.0, FLOOR, Z1), Vector3(0, 180, 0), ship)\n'
    '\t\t# хазард-полоса у пола\n'
    '\t\t_spawn("trim_hazard.glb", Vector3(x + 1.0, FLOOR + 0.12, Z0 + 0.02), Vector3.ZERO, ship,\n'
    '\t\t\t\tVector3(2.0, 0.2, 0.05))\n'
    '\t\t_spawn("trim_hazard.glb", Vector3(x + 1.0, FLOOR + 0.12, Z1 - 0.02), Vector3(0, 180, 0), ship,\n'
    '\t\t\t\tVector3(2.0, 0.2, 0.05))\n'
    '\t\tx += 2.0\n'
    '\t\ti += 1\n',
    '\tx = X_CORR_AFT\n'
    '\tvar i := 0\n'
    '\twhile x < X_CORR_FWD:\n'
    '\t\tvar panel := "wall_panel_a.glb" if i % 2 == 0 else "wall_panel_b.glb"\n'
    '\t\t# F8: проём в каюту на x≈5 — панель и её трим не ставим (полоса висела в проёме)\n'
    '\t\tif absf((x + 1.0) - ROOM_DOOR_X) > 0.1:\n'
    '\t\t\t_spawn(panel, Vector3(x + 1.0, FLOOR, Z0), Vector3(0, 0, 0), ship)\n'
    '\t\t\t# F9 (вариант B): сплошная полоса, сдвинута на 18 мм от панелей: задняя кромка\n'
    '\t\t\t# трима в 4 мм перед выступающим барельефом панелей b (10.586/13.214)\n'
    '\t\t\t_spawn("trim_hazard.glb", Vector3(x + 1.0, FLOOR + 0.12, Z0 + 0.038), Vector3.ZERO, ship,\n'
    '\t\t\t\t\tVector3(2.0, 0.2, 0.05))\n'
    '\t\t_spawn(panel, Vector3(x + 1.0, FLOOR, Z1), Vector3(0, 180, 0), ship)\n'
    '\t\t_spawn("trim_hazard.glb", Vector3(x + 1.0, FLOOR + 0.12, Z1 - 0.038), Vector3(0, 180, 0), ship,\n'
    '\t\t\t\t\tVector3(2.0, 0.2, 0.05))\n'
    '\t\tx += 2.0\n'
    '\t\ti += 1\n',
)

P_F10 = (
    "F10 труба и кабель под потолком — вдоль коридора, не поперёк (пробивали стены)",
    SHIP,
    '\t# труба и кабели под потолком\n'
    '\t_spawn("pipe_run.glb", Vector3(mid_x, CEIL - 0.28, Z0 + 0.3), Vector3(0, 90, 0), ship,\n'
    '\t\t\tVector3(2.0, 0.1, 0.1))\n'
    '\t_spawn("cable_bundle.glb", Vector3(mid_x, CEIL - 0.22, Z1 - 0.3), Vector3(0, 90, 0), ship,\n'
    '\t\t\tVector3(2.0, 0.12, 0.12))\n',
    '\t# труба и кабели под потолком\n'
    '\t# F10: модули повёрнуты вдоль коридора (раньше rot 90° вёл их ПОПЕРЁК и пробивал\n'
    '\t# обе стены). Оба идут у stbd-стены под потолком (на port у x≈1.2 висит высокая\n'
    '\t# табличка sign_warning до потолка); старт с x=-2, чтобы не влезать в раму B-3.\n'
    '\tvar px := X_CORR_AFT + 2.0\n'
    '\twhile px < X_CORR_FWD:\n'
    '\t\t_spawn("pipe_run.glb", Vector3(px, CEIL - 0.18, Z1 - 0.091), Vector3(0, 180, 0), ship)\n'
    '\t\t_spawn("cable_bundle.glb", Vector3(px, CEIL - 0.05, Z1 - 0.318), Vector3(0, 180, 0), ship)\n'
    '\t\tpx += 2.0\n',
)

P_F13 = (
    "F13 бумаги: масштаб задавать через node.scale (5-й аргумент _spawn — fallback, не scale)",
    SHIP,
    '\t# бумаги на полу\n'
    '\tfor i in 10:\n'
    '\t\tvar px := rng.randf_range(X_CORR_AFT + 1.0, X_CORR_FWD - 1.0)\n'
    '\t\tvar pz := rng.randf_range(Z0 + 0.5, Z1 - 0.5)\n'
    '\t\t_spawn("equip_papers.glb", Vector3(px, FLOOR + 0.01, pz), Vector3(0, rng.randf_range(0, 360), 0), ship,\n'
    '\t\t\t\tVector3(0.3, 0.01, 0.4))\n',
    '\t# бумаги на полу\n'
    '\t# F13: 5-й аргумент _spawn — это fallback-размер для отсутствующего ассета, а не\n'
    '\t# scale. Без явного scale листы были 0.71×0.64 м и на 14 см уходили под пол.\n'
    '\tfor i in 10:\n'
    '\t\tvar px := rng.randf_range(X_CORR_AFT + 1.0, X_CORR_FWD - 1.0)\n'
    '\t\tvar pz := rng.randf_range(Z0 + 0.5, Z1 - 0.5)\n'
    '\t\tvar paper := _spawn("equip_papers.glb", Vector3(px, FLOOR + 0.003, pz),\n'
    '\t\t\t\tVector3(0, rng.randf_range(0, 360), 0), ship, Vector3(0.3, 0.01, 0.4))\n'
    '\t\tpaper.scale = Vector3(0.3, 0.01, 0.4)\n',
)

P_F11 = (
    "F11 кабель на полу коридора: низ на полу, хвост не врезается в stbd-стену",
    SHIP,
    '\t_spawn("cable_bundle.glb", Vector3(-0.5, FLOOR + 0.05, Z1 - 0.35), Vector3(0, 20, 0), ship,\n'
    '\t\t\tVector3(2.0, 0.12, 0.12))\n',
    '\t# F11: низ кабеля ровно на полу, поворот 20° больше не достаёт stbd-стены\n'
    '\t_spawn("cable_bundle.glb", Vector3(-0.5, FLOOR + 0.106, 12.72), Vector3(0, 20, 0), ship,\n'
    '\t\t\tVector3(2.0, 0.12, 0.12))\n',
)

P_F16 = (
    "F16 sign_warning (GLB): задняя грань в 5 мм перед деталями панели (было врезано)",
    SHIP,
    '\t_spawn("sign_warning.glb", Vector3(1.2, FLOOR + 1.5, Z0 + 0.12), Vector3(0, 0, 0), ship,\n'
    '\t\t\tVector3(0.4, 0.4, 0.05))\n',
    '\t# F16: z 10.62 -> 10.705; задняя грань таблички (10.535) в 5 мм перед рельефом\n'
    '\t_spawn("sign_warning.glb", Vector3(1.2, FLOOR + 1.5, Z0 + 0.205), Vector3(0, 0, 0), ship,\n'
    '\t\t\tVector3(0.4, 0.4, 0.05))\n',
)

P_F17 = (
    "F17 плакат poster (GLB): прижат к стене (z 13.18 -> 13.24)",
    SHIP,
    '\t_spawn("poster.glb", Vector3(-2.9, FLOOR + 1.6, Z1 - 0.12), Vector3(0, 180, 0), ship,\n'
    '\t\t\tVector3(0.5, 0.7, 0.03))\n',
    '\t# F17: задняя грань плаката 13.265 — 5 мм перед рельефом stbd-панели\n'
    '\t_spawn("poster.glb", Vector3(-2.9, FLOOR + 1.6, Z1 - 0.06), Vector3(0, 180, 0), ship,\n'
    '\t\t\tVector3(0.5, 0.7, 0.03))\n',
)

P_F31 = (
    "F31 красная лампа в коридоре: x -2.5 -> -3.1 (врезалась в плафон -2.0)",
    SHIP,
    '\t# лампы аварийные в коридоре\n\tfor lx in [-2.5, 6.5]:\n',
    '\t# лампы аварийные в коридоре (F31: -2.5 -> -3.1, была утоплена в плафон x=-2.0)\n'
    '\tfor lx in [-3.1, 6.5]:\n',
)

P_F18 = (
    "F18 консоль мостика №2: z 12.88 -> 12.78 (корма была в стене)",
    SHIP,
    '\t_spawn("console_section.glb", Vector3(11.35, FLOOR, 12.88), Vector3(0, 180, 0), ship)\n'
    '\t_collider(Vector3(1.7, 1.0, 1.0), Vector3(11.35, FLOOR + 0.5, 12.88))\n',
    '\t# F18: AABB консоли больше не заходит в stbd-стену (детали до z=13.264)\n'
    '\t_spawn("console_section.glb", Vector3(11.35, FLOOR, 12.78), Vector3(0, 180, 0), ship)\n'
    '\t_collider(Vector3(1.7, 1.0, 1.0), Vector3(11.35, FLOOR + 0.5, 12.78))\n',
)

P_F19 = (
    "F19 CRT-терминал мостика: z 10.72 -> 10.81 (задний угол торчал в port-стене)",
    SHIP,
    '\t_spawn("crt_terminal.glb", Vector3(12.55, FLOOR, 10.72), Vector3(0, -71, 0), ship)\n',
    '\t# F19: корпус перед плоскостью port-стены (требует визуального контроля посадки)\n'
    '\t_spawn("crt_terminal.glb", Vector3(12.55, FLOOR, 10.81), Vector3(0, -71, 0), ship)\n',
)

P_F20 = (
    "F20 кружка на консоли мостика: на полку рядом с клавиатурой (z=12.05, y как у клавиатуры)",
    SHIP,
    '\t_spawn("equip_mug.glb", Vector3(13.17, FLOOR + 0.674, 11.52), Vector3(0, 30, 0), ship,\n'
    '\t\t\tVector3(0.1, 0.1, 0.1))\n',
    '\t# F20: кружка убрана из наклонной панели на полку к клавиатуре; высота — как у\n'
    '\t# клавиатуры (аудит предлагал +0.78, но AABB консоли завышен наклонной панелью)\n'
    '\t_spawn("equip_mug.glb", Vector3(13.17, FLOOR + 0.68, 12.05), Vector3(0, 30, 0), ship,\n'
    '\t\t\tVector3(0.1, 0.1, 0.1))\n',
)

P_F23 = (
    "F23 окно мостика: одно стекло на весь проём вместо 4 панелей со щелями 0.12 м",
    SHIP,
    '\tvar z := Z_B0\n'
    '\tvar pane_w := 0.62\n'
    '\twhile z < Z_B1 - 0.3:\n'
    '\t\tvar pane_z := z + pane_w\n'
    '\t\tif pane_z > Z_B1 - 0.3:\n'
    '\t\t\tpane_z = Z_B1 - 0.3\n'
    '\t\t# простенок\n'
    '\t\t_box(ship, Vector3(0.2, win_top - win_bottom, 0.16), Vector3(front_x, (win_bottom + win_top) * 0.5, z + 0.02), m_metal)\n'
    '\t\t# стекло\n'
    '\t\tvar pane := _box(ship, Vector3(0.03, win_top - win_bottom, pane_z - z - 0.16), Vector3(front_x - 0.12,\n'
    '\t\t\t\t(win_bottom + win_top) * 0.5, (z + 0.08 + pane_z) * 0.5), m_glass)\n'
    '\t\tpane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF\n'
    '\t\tz = pane_z + 0.14\n'
    '\t_box(ship, Vector3(0.2, win_top - win_bottom, 0.16), Vector3(front_x, (win_bottom + win_top) * 0.5, Z_B1 - 0.28), m_metal)\n',
    '\tvar z := Z_B0\n'
    '\tvar pane_w := 0.62\n'
    '\twhile z < Z_B1 - 0.3:\n'
    '\t\tvar pane_z := z + pane_w\n'
    '\t\tif pane_z > Z_B1 - 0.3:\n'
    '\t\t\tpane_z = Z_B1 - 0.3\n'
    '\t\t# простенок\n'
    '\t\t_box(ship, Vector3(0.2, win_top - win_bottom, 0.16), Vector3(front_x, (win_bottom + win_top) * 0.5, z + 0.02), m_metal)\n'
    '\t\tz = pane_z + 0.14\n'
    '\t# F23: одно стекло на весь проём; между 4 старыми панелями и стойками были\n'
    '\t# щели 0.12 м, в которые был виден открытый космос\n'
    '\tvar pane := _box(ship, Vector3(0.03, win_top - win_bottom, Z_B1 - Z_B0), Vector3(front_x - 0.12,\n'
    '\t\t\t(win_bottom + win_top) * 0.5, (Z_B0 + Z_B1) * 0.5), m_glass)\n'
    '\tpane.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF\n'
    '\t_box(ship, Vector3(0.2, win_top - win_bottom, 0.16), Vector3(front_x, (win_bottom + win_top) * 0.5, Z_B1 - 0.28), m_metal)\n',
)

P_F3 = (
    "F3 каюта: пол/потолок — вторая плитка 5.95 + scale.x 0.95, без наложения 0.1 м",
    SHIP,
    '\t# пол и потолок\n'
    '\tfor tx in [4.0, 5.9]:\n'
    '\t\tvar ft := _spawn("floor_tile.glb", Vector3(tx, FLOOR - 0.008, mid_z), Vector3.ZERO, ship)\n'
    '\t\tft.scale.z = depth / 2.0\n'
    '\t\tvar cp := _spawn("ceil_panel.glb", Vector3(tx, CEIL + 0.012, mid_z), Vector3.ZERO, ship)\n'
    '\t\tcp.scale.z = depth / 2.0\n',
    '\t# пол и потолок (F3: вторая плитка 5.95/0.95 — стык встык на x=5.0)\n'
    '\tfor tx in [4.0, 5.95]:\n'
    '\t\tvar tile_w := 0.95 if tx > 5.0 else 1.0\n'
    '\t\tvar ft := _spawn("floor_tile.glb", Vector3(tx, FLOOR - 0.008, mid_z), Vector3.ZERO, ship)\n'
    '\t\tft.scale = Vector3(tile_w, 1.0, depth / 2.0)\n'
    '\t\tvar cp := _spawn("ceil_panel.glb", Vector3(tx, CEIL + 0.012, mid_z), Vector3.ZERO, ship)\n'
    '\t\tcp.scale = Vector3(tile_w, 1.0, depth / 2.0)\n',
)

P_F45 = (
    "F4/F5 каюта: задняя стена scale.x 0.8, боковые — центр 9.85 + scale.x 0.65",
    SHIP,
    '\t# задняя и боковые стены\n'
    '\tfor wx in [4.0, 5.8]:\n'
    '\t\t_spawn("wall_panel_a.glb", Vector3(wx, FLOOR, ROOM_Z0), Vector3.ZERO, ship)\n'
    '\tfor wz in [8.2, 9.9]:\n'
    '\t\t_spawn("wall_panel_a.glb", Vector3(ROOM_X0, FLOOR, wz), Vector3(0, 90, 0), ship)\n'
    '\t\t_spawn("wall_panel_b.glb", Vector3(ROOM_X1, FLOOR, wz), Vector3(0, -90, 0), ship)\n',
    '\t# задняя и боковые стены\n'
    '\t# F4: вторая панель задней стены 1.6 м (было наложение 0.2 м)\n'
    '\tfor wx in [4.0, 5.8]:\n'
    '\t\tvar back := _spawn("wall_panel_a.glb", Vector3(wx, FLOOR, ROOM_Z0), Vector3.ZERO, ship)\n'
    '\t\tif wx > 5.0:\n'
    '\t\t\tback.scale.x = 0.8\n'
    '\t# F5: вторая боковая панель 1.3 м, центр 9.85 — стык встык и без вылета 0.4 м в коридор\n'
    '\tfor wz in [8.2, 9.85]:\n'
    '\t\tvar side_a := _spawn("wall_panel_a.glb", Vector3(ROOM_X0, FLOOR, wz), Vector3(0, 90, 0), ship)\n'
    '\t\tvar side_b := _spawn("wall_panel_b.glb", Vector3(ROOM_X1, FLOOR, wz), Vector3(0, -90, 0), ship)\n'
    '\t\tif wz > 9.0:\n'
    '\t\t\tside_a.scale.x = 0.65\n'
    '\t\t\tside_b.scale.x = 0.65\n',
)

P_F7 = (
    "F7 каюта: перекладина двери 2.0 -> 1.76 (торцы мерцали на косяках)",
    SHIP,
    '\t_box(ship, Vector3(2.0, 0.22, 0.2), Vector3(ROOM_DOOR_X, CEIL - 0.11, Z0), m_metal)\n',
    '\t# F7: перекладина по ширине дверной рамы (1.76 м)\n'
    '\t_box(ship, Vector3(1.76, 0.22, 0.2), Vector3(ROOM_DOOR_X, CEIL - 0.11, Z0), m_metal)\n',
)

P_F5C = (
    "F5 каюта: коллайдеры боковых стен depth вместо depth+0.4 (торчали в коридор)",
    SHIP,
    '\t_collider(Vector3(0.16, CEIL - FLOOR, depth + 0.4),\n'
    '\t\t\tVector3(ROOM_X0 - 0.08, (FLOOR + CEIL) * 0.5, mid_z))\n'
    '\t_collider(Vector3(0.16, CEIL - FLOOR, depth + 0.4),\n'
    '\t\t\tVector3(ROOM_X1 + 0.08, (FLOOR + CEIL) * 0.5, mid_z))\n',
    '\t# F5: коллайдер боковых стен по глубине каюты (было depth+0.4 — невидимая стена в коридоре)\n'
    '\t_collider(Vector3(0.16, CEIL - FLOOR, depth),\n'
    '\t\t\tVector3(ROOM_X0 - 0.08, (FLOOR + CEIL) * 0.5, mid_z))\n'
    '\t_collider(Vector3(0.16, CEIL - FLOOR, depth),\n'
    '\t\t\tVector3(ROOM_X1 + 0.08, (FLOOR + CEIL) * 0.5, mid_z))\n',
)

P_F6 = (
    "F6 каюта: боковые shell-боксы depth вместо depth+0.9 (торчали в коридор)",
    SHIP,
    '\t_box(ship, Vector3(0.3, CEIL - FLOOR + 0.6, depth + 0.9),\n'
    '\t\t\tVector3(ROOM_X0 - 0.25, (FLOOR + CEIL) * 0.5, mid_z), m_wall_b)\n'
    '\t_box(ship, Vector3(0.3, CEIL - FLOOR + 0.6, depth + 0.9),\n'
    '\t\t\tVector3(ROOM_X1 + 0.25, (FLOOR + CEIL) * 0.5, mid_z), m_wall_b)\n',
    '\t# F6: боковые shell-боксы больше не вылезают на 0.45 м в коридор\n'
    '\t_box(ship, Vector3(0.3, CEIL - FLOOR + 0.6, depth),\n'
    '\t\t\tVector3(ROOM_X0 - 0.25, (FLOOR + CEIL) * 0.5, mid_z), m_wall_b)\n'
    '\t_box(ship, Vector3(0.3, CEIL - FLOOR + 0.6, depth),\n'
    '\t\t\tVector3(ROOM_X1 + 0.25, (FLOOR + CEIL) * 0.5, mid_z), m_wall_b)\n',
)

# ------------------------------------------------------------ build_and_save --

Q_F24 = (
    "F24 вернуть _build_shell() в _build_save (щели стыков просвечивали в скайбокс)",
    BSAVE,
    '\t_make_materials()\n\t_build_corridor()\n',
    '\t_make_materials()\n'
    '\t# F24: внешняя оболочка, как в кадрах сборщика, — закрывает щели стыков панелей\n'
    '\t_build_shell()\n'
    '\t_build_corridor()\n',
)

Q_F26 = (
    "F26 не сохранять легаси-декали старой сборки (их ставит ShipDresser)",
    BSAVE,
    '\t_apply_gemini_textures()\n\t_place_decals()\n\t# _apply_screen_textures()',
    '\t_apply_gemini_textures()\n'
    '\t# F26: легаси-декали в сохранённую сцену не кладём — их ставит ShipDresser в рантайме\n'
    '\t# _apply_screen_textures()',
)

Q_F12A = (
    "F12 кабель на мостике: rot 80 -> 0 (уходил сквозь port-стену в каюту)",
    BSAVE,
    '\t# кабель на полу мостика у левого борта\n'
    '\t{"glb": "res://assetss/shipkit/arch/cable_bundle.glb", "pos": Vector3(11.9, FLOOR + 0.041, 10.9),\n'
    '\t\t\t"rot": 80.0, "scale": Vector3(1.6, 0.10, 0.10)},\n',
    '\t# кабель на полу мостика у левого борта (F12: rot 80° уводил сквозь port-стену)\n'
    '\t{"glb": "res://assetss/shipkit/arch/cable_bundle.glb", "pos": Vector3(11.9, FLOOR + 0.06, 10.75),\n'
    '\t\t\t"rot": 0.0, "scale": Vector3(1.2, 0.10, 0.10)},\n',
)

Q_F14 = (
    "F14 POLISH-кружка на верстаке: scale 0.1 -> 1, y по верху столешницы",
    BSAVE,
    '\t# вторая кружка на верстаке\n'
    '\t{"glb": "res://assetss/shipkit/equip/equip_mug.glb", "pos": Vector3(3.95, FLOOR + 0.971, 12.75),\n'
    '\t\t\t"rot": -20.0, "scale": Vector3(0.1, 0.1, 0.1)},\n',
    '\t# вторая кружка на верстаке (F14: scale 0.1 давал кружку 1.4 см высотой)\n'
    '\t{"glb": "res://assetss/shipkit/equip/equip_mug.glb", "pos": Vector3(3.95, 3.105, 12.75),\n'
    '\t\t\t"rot": -20.0, "scale": Vector3.ONE},\n',
)

Q_F12B = (
    "F12 кабель у переборки B-3: scale 0.8/rot 0 — больше не пробивает переборку и стену",
    BSAVE,
    '\t# кабель у переборки B-3\n'
    '\t{"glb": "res://assetss/shipkit/arch/cable_bundle.glb", "pos": Vector3(-3.2, FLOOR + 0.041, 12.95),\n'
    '\t\t\t"rot": 15.0, "scale": Vector3(2.0, 0.12, 0.12)},\n',
    '\t# кабель у переборки B-3 (F12: 4-м кабель пробивал переборку x=-4 и stbd-стену)\n'
    '\t{"glb": "res://assetss/shipkit/arch/cable_bundle.glb", "pos": Vector3(-2.6, FLOOR + 0.06, 13.05),\n'
    '\t\t\t"rot": 0.0, "scale": Vector3(0.8, 0.12, 0.12)},\n',
)

Q_F15 = (
    "F15 POLISH-ящик в шлюзе: в свободный кормовой угол (не врезается в crate)",
    BSAVE,
    '\t# ящик в углу шлюза\n'
    '\t{"glb": "res://assetss/shipkit/equip/crate_small.glb", "pos": Vector3(-7.15, FLOOR, 12.95),\n'
    '\t\t\t"rot": 35.0, "scale": Vector3.ONE},\n',
    '\t# ящик в углу шлюза (F15: вынесен из наложения с crate в (-6.8, ..., 12.6))\n'
    '\t{"glb": "res://assetss/shipkit/equip/crate_small.glb", "pos": Vector3(-7.45, FLOOR, 12.25),\n'
    '\t\t\t"rot": 35.0, "scale": Vector3.ONE},\n',
)

# -------------------------------------------------------------- ship_dresser --

D_HEAD = (
    "F21 шапка DECALS: z = поверхность панели + 4 мм (не Z0+0.06)",
    DRESSER,
    '# реально видно; Z — 0.07 м от плоскости панелей, чтобы не проваливаться за\n'
    '# рёбра панелей.\n',
    '# реально видно. F21: z каждой декали — поверхность панели + 4 мм (лучевые замеры\n'
    '# аудита, .codex_qa/model_audit/decal_fixes.csv), а не Z0+0.06: наклейки парили.\n',
)

D_ITEMS = [
    (
        "F21 stencil_deckb: z 10.536 -> 10.512",
        DRESSER,
        '\t{"tex": "stencil_deckb", "pos": Vector3(2.0, 4.12, 10.536),\n',
        '\t{"tex": "stencil_deckb", "pos": Vector3(2.0, 4.12, 10.512),\n',
    ),
    (
        "F21 poster_keepcalm: z 13.264 -> 13.274",
        DRESSER,
        '\t{"tex": "poster_keepcalm", "pos": Vector3(1.0, 3.36, 13.264),\n',
        '\t{"tex": "poster_keepcalm", "pos": Vector3(1.0, 3.36, 13.274),\n',
    ),
    (
        "F21 poster_rec: z 13.264 -> 13.316 (парил 5.6 см)",
        DRESSER,
        '\t{"tex": "poster_rec", "pos": Vector3(1.55, 3.6486, 13.264),\n',
        '\t{"tex": "poster_rec", "pos": Vector3(1.55, 3.6486, 13.316),\n',
    ),
    (
        "F21 sign_warning: z 10.536 -> 10.4415 (парила 9.9 см)",
        DRESSER,
        '\t{"tex": "sign_warning", "pos": Vector3(7.4, 3.55, 10.536),\n',
        '\t{"tex": "sign_warning", "pos": Vector3(7.4, 3.55, 10.4415),\n',
    ),
    (
        "F21 poster_mng: z 10.536 -> 10.534",
        DRESSER,
        '\t{"tex": "poster_mng", "pos": Vector3(-5.4, 3.6986, 10.536),\n',
        '\t{"tex": "poster_mng", "pos": Vector3(-5.4, 3.6986, 10.534),\n',
    ),
    (
        "F21 sign_decompression: z 10.536 -> 10.498 (парила 4.2 см)",
        DRESSER,
        '\t{"tex": "sign_decompression", "pos": Vector3(-6.6, 3.5986, 10.536),\n',
        '\t{"tex": "sign_decompression", "pos": Vector3(-6.6, 3.5986, 10.498),\n',
    ),
    (
        "F22 hazard_labels: x -7.1 -> -7.35 (наложение на sign_decompression), z 10.516",
        DRESSER,
        '\t{"tex": "hazard_labels", "pos": Vector3(-7.1, 3.4486, 10.536),\n',
        '\t{"tex": "hazard_labels", "pos": Vector3(-7.35, 3.4486, 10.516),\n',
    ),
    (
        "F21 porthole: z 13.264 -> 13.316 (парил 5.6 см)",
        DRESSER,
        '\t{"tex": "porthole", "pos": Vector3(10.2, 3.6486, 13.264),\n',
        '\t{"tex": "porthole", "pos": Vector3(10.2, 3.6486, 13.316),\n',
    ),
    (
        "F21 b3_number: x -3.724 -> -3.797 на полотне двери B-3",
        DRESSER,
        '\t{"tex": "b3_number", "pos": Vector3(-3.724, 3.62, 11.9),\n',
        '\t{"tex": "b3_number", "pos": Vector3(-3.797, 3.62, 11.9),\n',
    ),
    (
        "F21 каюта poster_keepcalm: x 6.564 -> 6.602",
        DRESSER,
        '\t{"tex": "poster_keepcalm", "pos": Vector3(6.564, 3.85, 8.4),\n',
        '\t{"tex": "poster_keepcalm", "pos": Vector3(6.602, 3.85, 8.4),\n',
    ),
    (
        "F21 каюта note_handwritten: x 3.236 -> 3.184",
        DRESSER,
        '\t{"tex": "note_handwritten", "pos": Vector3(3.236, 3.65, 8.1),\n',
        '\t{"tex": "note_handwritten", "pos": Vector3(3.184, 3.65, 8.1),\n',
    ),
    (
        "F21 каюта sign_warning: z 7.236 -> 7.184",
        DRESSER,
        '\t{"tex": "sign_warning", "pos": Vector3(4.2, 3.9, 7.236),\n',
        '\t{"tex": "sign_warning", "pos": Vector3(4.2, 3.9, 7.184),\n',
    ),
    (
        "F21 stencil_deckb (полировка): z 13.264 -> 13.3585",
        DRESSER,
        '\t{"tex": "stencil_deckb", "pos": Vector3(8.9, 3.95, 13.264),\n',
        '\t{"tex": "stencil_deckb", "pos": Vector3(8.9, 3.95, 13.3585),\n',
    ),
    (
        "F21 sign_warning (полировка): z 10.536 -> 10.4415",
        DRESSER,
        '\t{"tex": "sign_warning", "pos": Vector3(3.1, 3.55, 10.536),\n',
        '\t{"tex": "sign_warning", "pos": Vector3(3.1, 3.55, 10.4415),\n',
    ),
    (
        "F21 hazard_labels (полировка): z 13.264 -> 13.28",
        DRESSER,
        '\t{"tex": "hazard_labels", "pos": Vector3(-3.1, 3.45, 13.264),\n',
        '\t{"tex": "hazard_labels", "pos": Vector3(-3.1, 3.45, 13.28),\n',
    ),
    (
        "F21+ прочие wall-декали: +4 мм от поверхности (убирает копланарность с AABB)",
        DRESSER,
        '\t{"tex": "airlock_stencils", "pos": Vector3(-5.15, 3.62, 10.695),\n',
        '\t{"tex": "airlock_stencils", "pos": Vector3(-5.15, 3.62, 10.699),\n',
    ),
    (
        "F21+ airlock_labels: +4 мм от поверхности",
        DRESSER,
        '\t{"tex": "airlock_labels", "pos": Vector3(-5.0, 3.02, 10.695),\n',
        '\t{"tex": "airlock_labels", "pos": Vector3(-5.0, 3.02, 10.699),\n',
    ),
    (
        "F21+ airlock_frost: +4 мм по нормали (rot 90 -> +X)",
        DRESSER,
        '\t{"tex": "airlock_frost", "pos": Vector3(-7.55, 3.5, 12.85),\n',
        '\t{"tex": "airlock_frost", "pos": Vector3(-7.546, 3.5, 12.85),\n',
    ),
]

PATCHES = [
    P_F1, P_F89, P_F10, P_F13, P_F11, P_F16, P_F17, P_F31,
    P_F18, P_F19, P_F20, P_F23, P_F3, P_F45, P_F7, P_F5C, P_F6,
    Q_F24, Q_F26, Q_F12A, Q_F14, Q_F12B, Q_F15,
    D_HEAD, *D_ITEMS,
]


class AnchorError(RuntimeError):
    pass


def read_text(path: Path) -> str:
    """Читает UTF-8, снимает BOM и приводит CRLF к LF (канон — CRLF)."""
    data = path.read_bytes()
    if data.startswith(b"\xef\xbb\xbf"):
        data = data[3:]
    return data.decode("utf-8").replace("\r\n", "\n")


def write_text(path: Path, text: str) -> None:
    data = text.replace("\r\n", "\n").replace("\n", "\r\n").encode("utf-8")
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_bytes(data)
    tmp.replace(path)


def process_file(root: Path, rel: str, patches: list) -> tuple[str, list[str], list[str], bool]:
    """Возвращает (новый текст, применённые id, пропущенные id, есть ли правки)."""
    path = root / rel
    if not path.is_file():
        raise AnchorError(f"нет файла: {path}")
    text = read_text(path)
    applied: list[str] = []
    skipped: list[str] = []
    for pid, _f, old, new in patches:
        if old in text:
            text = text.replace(old, new, 1)
            applied.append(pid)
        elif new in text:
            skipped.append(pid)
        else:
            raise AnchorError(
                f"{rel}: не найден якорь для {pid}.\n"
                f"  ожидался фрагмент (первые строки): {old.strip().splitlines()[0]!r}\n"
                "  Файл изменён после аудита? Правки не внесены (ничего не записано)."
            )
    return text, applied, skipped, bool(applied)


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description="Фиксы наложений/z-fighting корабля (F1–F31)")
    ap.add_argument("--root", default=r"D:\4", help="корень проекта (по умолчанию D:\\4)")
    ap.add_argument("--apply", action="store_true", help="записать правки (по умолчанию dry-run)")
    ap.add_argument("--dry-run", action="store_true", help="только показать diff (по умолчанию)")
    args = ap.parse_args(argv)

    if args.apply and args.dry_run:
        ap.error("--apply и --dry-run взаимоисключающие")

    root = Path(args.root)
    by_file: dict[str, list] = {}
    for patch in PATCHES:
        by_file.setdefault(patch[1], []).append(patch)

    # двухфазно: сначала валидируем и считаем all diffs, потом пишем
    results: dict[str, tuple[str, list[str], list[str], bool]] = {}
    originals: dict[str, str] = {}
    errors: list[str] = []
    for rel in (SHIP, BSAVE, DRESSER):
        try:
            new_text, applied, skipped, changed = process_file(root, rel, by_file[rel])
            results[rel] = (new_text, applied, skipped, changed)
            originals[rel] = read_text(root / rel)
        except AnchorError as exc:
            errors.append(str(exc))

    if errors:
        print("ОШИБКА: якоря не совпали, правки НЕ внесены.\n", file=sys.stderr)
        for err in errors:
            print(err, file=sys.stderr)
        return 2

    for rel in (SHIP, BSAVE, DRESSER):
        old_text = originals[rel]
        new_text, applied, skipped, changed = results[rel]
        if applied:
            diff = difflib.unified_diff(
                old_text.splitlines(), new_text.splitlines(),
                fromfile="a/" + rel, tofile="b/" + rel, lineterm="",
            )
            print("\n".join(diff))
        if not changed:
            print(f"== {rel}: уже применено (пропущено {len(skipped)} правок), изменений нет")

    if not args.apply:
        total = sum(len(results[rel][1]) for rel in results)
        print(f"\n[dry-run] Будет применено правок: {total}. Ничего не записано.")
        print("[dry-run] Запустите с --apply, чтобы внести изменения.")
        return 0

    changed_files = 0
    for rel in (SHIP, BSAVE, DRESSER):
        new_text, applied, skipped, changed = results[rel]
        if changed:
            write_text(root / rel, new_text)
            changed_files += 1
    print("\n=== ИТОГО ===")
    for rel in (SHIP, BSAVE, DRESSER):
        new_text, applied, skipped, changed = results[rel]
        state = "изменён" if changed else "без изменений"
        print(f"  {rel}: {state}; применено={len(applied)}, уже было={len(skipped)}")
        for pid in applied:
            print(f"    + {pid}")
    print(f"Файлов изменено: {changed_files}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
