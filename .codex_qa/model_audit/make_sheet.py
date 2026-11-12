"""Контактный лист контрольных кадров аудита: .codex_qa/model_audit/shots/*.png"""
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(r"D:\4\.codex_qa\model_audit")
SHOTS = ROOT / "shots"
OUT = ROOT / "shots" / "sheet_overlaps.jpg"

TITLES = {
    "01_joint_bridge_floor": "1. Стык коридор-мостик: пол (двойная геометрия 0.6 м)",
    "02_joint_bridge_ceiling": "2. Стык коридор-мостик: потолок",
    "03_joint_airlock_floor": "3. Стык шлюз-коридор: wet x dry пол 0.2 м",
    "04_decal_pair_airlock": "4. Две декали друг на друге (шлюз)",
    "05_quarters_floor_seam": "5. Шов пола каюты (0.1 м нахлёст)",
}
TILE_W, TILE_H = 640, 402
PAD, LABEL_H = 10, 30


def font(size: int):
    for name in ("segoeui.ttf", "arial.ttf", "DejaVuSans.ttf"):
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def main() -> None:
    items = [(p.stem, p) for p in sorted(SHOTS.glob("*.png")) if not p.stem.startswith("sheet")]
    cols = 3
    rows = (len(items) + cols - 1) // cols
    width = PAD + cols * (TILE_W + PAD)
    height = PAD + rows * (TILE_H + LABEL_H + PAD)
    sheet = Image.new("RGB", (width, height), (16, 18, 22))
    draw = ImageDraw.Draw(sheet)
    for i, (name, path) in enumerate(items):
        col, row = i % cols, i // cols
        x = PAD + col * (TILE_W + PAD)
        y = PAD + row * (TILE_H + LABEL_H + PAD)
        draw.text((x + 2, y), TITLES.get(name, name), fill=(200, 215, 230), font=font(16))
        img = Image.open(path).convert("RGB").resize((TILE_W, TILE_H), Image.LANCZOS)
        sheet.paste(img, (x, y + LABEL_H))
    sheet.save(OUT, quality=92)
    print("saved", OUT)


if __name__ == "__main__":
    main()
