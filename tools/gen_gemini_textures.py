"""Генерация текстур через Gemini (image model) + приведение к PS1-стилю игры.

Ключ НЕ хранится в проекте. Скрипт берёт его из:
  1) переменной окружения GEMINI_API_KEY (рекомендуется), либо
  2) файла C:\\Users\\arseni\\.dsh\\gemini_key.txt (вне репозитория).

Запуск:
  python tools/gen_gemini_textures.py --dry-run     # проверить промпты без сети
  python tools/gen_gemini_textures.py               # сгенерировать всё
  python tools/gen_gemini_textures.py --only metal_wall floor_grate
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

import numpy as np
from PIL import Image, ImageFilter, ImageOps

ROOT = Path(r"D:\4")
RAW = ROOT / ".codex_qa" / "gemini" / "raw"
OUT = ROOT / "assetss" / "tex_gemini"
QA = ROOT / ".codex_qa" / "gemini"
KEY_FILE = Path.home() / ".dsh" / "gemini_key.txt"

MODELS = [
    "gemini-3.1-flash-lite-image",
    "gemini-nano-banana-2.1",
    "gemini-3.1-flash-image",
    "gemini-2.5-flash-image",
    "gemini-3-pro-image",
]


def endpoint(model: str) -> str:
    return f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent"

# kind: tile — бесшовная поверхность, decal — с альфой, crt — экран
SPECS = [
    {
        "name": "metal_wall",
        "kind": "tile",
        "size": 256,
        "prompt": "Seamless tileable video game texture, 1990s PS1 sci-fi spaceship interior wall panels, dark gunmetal steel plates with rivets and seams, scratches, rust streaks and grime, flat top-down orthographic view, no perspective, no baked lighting, no shadows, pixelated retro low-res look, limited muted palette",
    },
    {
        "name": "metal_wall_dark",
        "kind": "tile",
        "size": 256,
        "prompt": "Seamless tileable video game texture, very dark worn steel wall panels of a derelict spaceship, heavy grime, oil stains, scratches, bolts, flat orthographic top-down, no perspective, no lighting, pixelated PS1 retro look, limited dark palette",
    },
    {
        "name": "floor_grate",
        "kind": "tile",
        "size": 256,
        "prompt": "Seamless tileable metal grating walkway floor texture, industrial spaceship deck, rusty worn edges, oil stains, dirt in the gaps, flat top-down orthographic, no perspective, no lighting, pixelated PS1 retro game texture",
    },
    {
        "name": "floor_wet",
        "kind": "tile",
        "size": 256,
        "prompt": "Seamless tileable dirty wet metal floor plates of a spaceship, puddles of dark water, grime, scratches, flat top-down orthographic, no perspective, no baked lighting, pixelated PS1 retro game texture",
    },
    {
        "name": "hazard_stripes",
        "kind": "tile",
        "size": 128,
        "prompt": "Seamless tileable yellow and black diagonal warning hazard stripes, chipped and worn paint, dirty metal underneath, flat orthographic, no lighting, pixelated PS1 retro game texture",
    },
    {
        "name": "stencil_deckb",
        "kind": "decal",
        "size": 256,
        "prompt": "White worn stencil paint text 'DECK B' on a dark metal plate, scratched and chipped paint, grime, centered composition, square image, pure black background, flat orthographic, no lighting",
    },
    {
        "name": "sign_warning",
        "kind": "decal",
        "size": 256,
        "prompt": "Yellow triangular warning sign with black exclamation mark on a riveted metal plate, worn and dirty industrial style, centered, square image, pure black background, flat view, no lighting",
    },
    {
        "name": "poster_keepcalm",
        "kind": "decal",
        "size": 256,
        "prompt": "Retro dark sci-fi poster with worn text 'KEEP CALM AND STAY ALIVE', aged paper, grime and scratches, centered, square image, pure black background, flat view",
    },
    {
        "name": "door_b3",
        "kind": "tile",
        "size": 256,
        "prompt": "Worn dark red metal spaceship door panel with stenciled 'B-3' text, rivets, yellow-black hazard stripe along the bottom, grime and scratches, flat front view, square image, no lighting",
    },
    {
        "name": "crt_telemetry",
        "kind": "crt",
        "size": 256,
        "prompt": "Green phosphor CRT computer screen of a 1990s spaceship terminal, dark background, horizontal scanlines, subtle glow, no readable text, blank telemetry screen, pixelated retro look, square image",
    },
    {
        "name": "crt_radar",
        "kind": "crt",
        "size": 256,
        "prompt": "Green phosphor CRT radar screen, circular grid with rings and radial lines, scanlines, dark background, 1990s spaceship terminal, pixelated retro look, square image",
    },
    {
        "name": "crt_waveform",
        "kind": "crt",
        "size": 256,
        "prompt": "Green phosphor CRT oscilloscope screen with a waveform line and grid, scanlines, dark background, 1990s spaceship terminal, pixelated retro look, square image",
    },
    {
        "name": "crt_radio",
        "kind": "crt",
        "size": 256,
        "prompt": "Retro radio LCD display, cyan-green glow, dark background, frequency scale ticks and VU meter segments, no readable text, scanlines, pixelated retro look, square image",
    },
]


# ------------------------------------------------------------------ ключ -----

def load_key() -> str:
    key = os.environ.get("GEMINI_API_KEY", "").strip()
    if key:
        return key
    if KEY_FILE.exists():
        return KEY_FILE.read_text(encoding="utf-8").strip()
    print("НЕТ КЛЮЧА: задай GEMINI_API_KEY или положи ключ в", KEY_FILE)
    sys.exit(2)


# ---------------------------------------------------------------- запрос -----

def generate_one(key: str, prompt: str, model: str, retries: int = 3) -> Image.Image | None:
    bodies = [
        {"contents": [{"parts": [{"text": prompt}]}],
         "generationConfig": {"responseModalities": ["IMAGE"]}},
        {"contents": [{"parts": [{"text": prompt}]}],
         "generationConfig": {"responseModalities": ["TEXT", "IMAGE"]}},
    ]
    url = endpoint(model) + f"?key={key}"
    for attempt in range(1, retries + 1):
        for bi, body in enumerate(bodies):
            data = json.dumps(body).encode("utf-8")
            req = urllib.request.Request(url, data=data, headers={"Content-Type": "application/json"})
            try:
                with urllib.request.urlopen(req, timeout=120) as resp:
                    payload = json.loads(resp.read().decode("utf-8"))
                parts = payload["candidates"][0]["content"]["parts"]
                for part in parts:
                    inline = part.get("inlineData") or part.get("inline_data")
                    if inline and inline.get("data"):
                        raw = base64.b64decode(inline["data"])
                        import io
                        return Image.open(io.BytesIO(raw)).convert("RGBA")
                print("  нет картинки в ответе, попытка", attempt)
            except urllib.error.HTTPError as e:
                detail = e.read().decode("utf-8", "ignore")[:500]
                print(f"  HTTP {e.code} ({model}, тело {bi + 1}): {detail}")
                if e.code in (400, 403, 404):
                    break  # это не про тело запроса: модель недоступна/нет прав
            except Exception as e:  # сеть/таймаут
                print("  ошибка:", type(e).__name__, str(e)[:200])
        time.sleep(2.0 * attempt)
    return None


# ------------------------------------------------------------ обработка -----

def mirror_seamless(img: Image.Image, size: int) -> Image.Image:
    """Идеальная бесшовность зеркальной укладкой 2x2 (PS1-приём)."""
    half = img.resize((size // 2, size // 2), Image.Resampling.LANCZOS)
    tile = Image.new("RGB", (size, size))
    tile.paste(half, (0, 0))
    tile.paste(ImageOps.mirror(half), (size // 2, 0))
    tile.paste(ImageOps.flip(half), (0, size // 2))
    tile.paste(ImageOps.mirror(ImageOps.flip(half)), (size // 2, size // 2))
    return tile


def ps1_quantize(img: Image.Image, colors: int = 28) -> Image.Image:
    q = img.convert("RGB").quantize(colors=colors, method=Image.Quantize.MEDIANCUT,
                                    dither=Image.Dither.NONE)
    return q.convert("RGB")


def process(spec: dict, raw: Image.Image) -> Image.Image:
    kind = spec["kind"]
    size = spec["size"]
    if kind == "tile":
        return ps1_quantize(mirror_seamless(raw, size))
    if kind == "decal":
        rgb = raw.convert("RGB")
        arr = np.asarray(rgb, dtype=np.float32) / 255.0
        lum = arr @ np.array([0.299, 0.587, 0.114], dtype=np.float32)
        alpha = np.clip(lum * 1.4, 0.0, 1.0) ** 0.8
        rgba = np.dstack([arr, alpha])
        img = Image.fromarray((rgba * 255).astype(np.uint8), "RGBA")
        img = img.resize((size, size), Image.Resampling.LANCZOS)
        img = img.crop(img.getbbox())
        img = img.resize((size, max(1, int(size * img.height / img.width))),
                         Image.Resampling.LANCZOS)
        return img
    # crt: скан-линии + лёгкое свечение
    img = raw.convert("RGB").resize((size, size), Image.Resampling.LANCZOS)
    arr = np.asarray(img, dtype=np.float32) / 255.0
    arr *= 0.9
    arr[::2] *= 0.86
    glow = np.asarray(img.filter(ImageFilter.GaussianBlur(6)), dtype=np.float32) / 255.0
    arr = np.clip(arr + glow * 0.25, 0, 1)
    return ps1_quantize(Image.fromarray((arr * 255).astype(np.uint8)), 24)


def probe_models(key: str) -> None:
    url = "https://generativelanguage.googleapis.com/v1beta/models?key=" + key + "&pageSize=100"
    try:
        with urllib.request.urlopen(url, timeout=60) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
        models = payload.get("models", [])
        ids = [m.get("name", "").split("/")[-1] for m in models]
        image_ids = [i for i in ids if "image" in i or "imagen" in i]
        print("моделей всего:", len(ids))
        if not image_ids:
            print("image-моделей НЕ НАЙДЕНО")
        for m in models:
            name = m.get("name", "").split("/")[-1]
            if name in image_ids:
                print(" ", name, "| методы:", ",".join(m.get("supportedGenerationMethods", [])))
    except urllib.error.HTTPError as e:
        print("HTTP", e.code, e.read().decode("utf-8", "ignore")[:400])
    except Exception as e:
        print("ошибка:", type(e).__name__, str(e)[:200])


def contact_sheet(paths: list[Path]) -> None:
    if not paths:
        return
    cell = 256
    cols = 4
    rows = (len(paths) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (cell + 4) + 4, rows * (cell + 20) + 4), (14, 16, 18))
    from PIL import ImageDraw
    d = ImageDraw.Draw(sheet)
    for i, p in enumerate(paths):
        img = Image.open(p).convert("RGB").resize((cell, cell), Image.Resampling.NEAREST)
        x = 4 + (i % cols) * (cell + 4)
        y = 4 + (i // cols) * (cell + 20)
        sheet.paste(img, (x, y))
        d.text((x + 2, y + cell + 2), p.stem, fill=(220, 220, 210))
    sheet.save(QA / "contact_sheet.png")
    print("контактный лист:", QA / "contact_sheet.png")


# ---------------------------------------------------------------- запуск ----

def main() -> None:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--probe", action="store_true")
    ap.add_argument("--only", nargs="*", default=[])
    args = ap.parse_args()

    if args.probe:
        probe_models(load_key())
        return
    specs = [s for s in SPECS if not args.only or s["name"] in args.only]
    print(f"текстур в пачке: {len(specs)}")
    if args.dry_run:
        for s in specs:
            print(f"  {s['name']:<16} {s['kind']:<6} {s['size']}px  {s['prompt'][:60]}...")
        return

    RAW.mkdir(parents=True, exist_ok=True)
    OUT.mkdir(parents=True, exist_ok=True)
    QA.mkdir(parents=True, exist_ok=True)
    key = load_key()

    working_model = None
    results: list[Path] = []
    for spec in specs:
        print("генерирую:", spec["name"])
        raw = None
        for model in ([working_model] if working_model else MODELS):
            raw = generate_one(key, spec["prompt"], model)
            if raw is not None:
                working_model = model
                print("  модель:", model)
                break
            print("  не подошла модель:", model)
        if raw is None:
            print("  ПРОПУСК (нет результата)")
            continue
        raw_path = RAW / f"{spec['name']}_raw.png"
        raw.save(raw_path)
        out = process(spec, raw)
        out_path = OUT / f"{spec['name']}.png"
        out.save(out_path)
        print("  сохранено:", out_path)
        results.append(out_path)

    contact_sheet(results)
    print("готово, файлов:", len(results))


if __name__ == "__main__":
    main()
