# -*- coding: utf-8 -*-
"""Склеивает пары «до | после» в одну картинку для визуальной проверки."""
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(r"D:\4\.codex_qa\zfight_fix")
OUT = ROOT / "compare"
OUT.mkdir(exist_ok=True)

PAIRS = [
    ("my", "01_joint_bridge_floor"),
    ("my", "02_joint_bridge_ceiling"),
    ("my", "03_joint_airlock_floor"),
    ("my", "04_decal_pair_airlock"),
    ("my", "05_quarters_floor_seam"),
    ("agent", "05_quarters_floor_seam"),
    ("agent", "08_bridge_window"),
    ("agent", "09_workbench_decals"),
    ("agent", "11_bridge_console"),
    ("agent", "14_corridor_ceiling_pipe"),
    ("agent", "15_corridor_trim"),
]

for kind, name in PAIRS:
    if kind == "my":
        b = ROOT / "my_before" / (name + ".png")
        a = ROOT / "my_after" / (name + ".png")
    else:
        b = ROOT / "shots_before" / (name + ".png")
        a = ROOT / "shots_after" / (name + ".png")
    if not (b.is_file() and a.is_file()):
        print("skip (нет файла):", kind, name)
        continue
    ib, ia = Image.open(b).convert("RGB"), Image.open(a).convert("RGB")
    w = 880
    hb = round(ib.height * w / ib.width)
    ha = round(ia.height * w / ia.width)
    ib = ib.resize((w, hb), Image.LANCZOS)
    ia = ia.resize((w, ha), Image.LANCZOS)
    h = min(hb, ha)
    ib = ib.crop((0, 0, w, h))
    ia = ia.crop((0, 0, w, h))
    canvas = Image.new("RGB", (w * 2 + 8, h + 28), (18, 18, 18))
    canvas.paste(ib, (0, 28))
    canvas.paste(ia, (w + 8, 28))
    d = ImageDraw.Draw(canvas)
    d.text((8, 8), "ДО  /  " + name, fill=(255, 210, 120))
    d.text((w + 16, 8), "ПОСЛЕ  /  " + name, fill=(150, 255, 170))
    out = OUT / (kind + "_" + name + ".jpg")
    canvas.save(out, quality=88)
    print("saved", out.name)
