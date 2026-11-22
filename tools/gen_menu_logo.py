"""Генератор пиксельного логотипа NELVAR для главного меню.

Буквы — светлый камень с фаской, тёмной обводкой и падающей тенью.
По камню идут трещины; под надписью — орнамент с ромбом.
Сохраняются два слоя одинакового размера:
  logo.png         — сам логотип (фиксированные цвета);
  logo_accent.png  — светящиеся трещины и орнамент (белые, меню
                     окрашивает их в цвет текущей стихии и складывает аддитивно).

Запуск из корня проекта:
    python3 tools/gen_menu_logo.py
"""

import math
import random
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "textures" / "menu"

LETTER_W, LETTER_H = 12, 18
GAP = 3
STROKE = 1.55
MARGIN = 3

# Буквы как ломаные в координатах центров пикселей.
GLYPHS = {
    "N": [[(1.5, 17.5), (1.5, 0.5)], [(1.5, 0.5), (10.5, 17.5)], [(10.5, 17.5), (10.5, 0.5)]],
    "E": [[(10.5, 0.5), (1.5, 0.5), (1.5, 17.5), (10.5, 17.5)], [(1.5, 8.5), (8.0, 8.5)]],
    "L": [[(1.5, 0.5), (1.5, 17.5), (10.5, 17.5)]],
    "V": [[(0.8, 0.5), (6.0, 17.5), (11.2, 0.5)]],
    "A": [[(0.8, 17.5), (6.0, 0.5), (11.2, 17.5)], [(3.2, 11.5), (8.8, 11.5)]],
    "R": [[(1.5, 17.5), (1.5, 0.5), (7.5, 0.5), (10.3, 2.8), (10.3, 6.2), (7.5, 8.5), (1.5, 8.5)],
          [(6.0, 8.5), (10.8, 17.5)]],
}
# Засечки на концах штрихов — «высеченный» вид.
SERIFS = {
    "N": [((0.0, 17.5), (3.0, 17.5)), ((9.0, 0.5), (12.0, 0.5))],
    "L": [((0.0, 0.5), (3.0, 0.5))],
    "R": [((0.0, 17.5), (3.0, 17.5))],
    "E": [((10.5, 0.5), (10.5, 2.0)), ((10.5, 17.5), (10.5, 16.0))],
    "V": [((0.0, 0.5), (2.2, 0.5)), ((9.8, 0.5), (12.0, 0.5))],
    "A": [((0.0, 17.5), (2.2, 17.5)), ((9.8, 17.5), (12.0, 17.5))],
}

# Кернинг пар с «пустыми» углами (L и V иначе разваливают слово надвое).
KERNING = {("L", "V"): -4, ("V", "A"): -2}

STONE = [(112, 98, 92), (156, 140, 124), (198, 184, 160), (230, 220, 198), (250, 244, 228)]
OUTLINE = (24, 20, 28)
SHADOW = (10, 8, 14, 150)
CRACK = (70, 52, 50)


def seg_dist(px, py, a, b):
    ax, ay = a
    bx, by = b
    dx, dy = bx - ax, by - ay
    length2 = dx * dx + dy * dy
    t = 0.0 if length2 == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length2))
    return math.hypot(px - (ax + t * dx), py - (ay + t * dy))


def glyph_mask(ch):
    pts = set()
    lines = [(p[i], p[i + 1]) for p in GLYPHS[ch] for i in range(len(p) - 1)]
    for x in range(LETTER_W):
        for y in range(LETTER_H):
            if any(seg_dist(x + 0.5, y + 0.5, a, b) <= STROKE for a, b in lines):
                pts.add((x, y))
            elif any(seg_dist(x + 0.5, y + 0.5, a, b) <= 0.9 for a, b in SERIFS.get(ch, [])):
                pts.add((x, y))
    return pts


def main():
    text = "NELVAR"
    offsets = []
    x = MARGIN
    for i, ch in enumerate(text):
        if i > 0:
            x += LETTER_W + GAP + KERNING.get((text[i - 1], ch), 0)
        offsets.append(x)
    letters_w = offsets[-1] + LETTER_W - MARGIN
    orn_y = MARGIN + LETTER_H + 5
    w = letters_w + MARGIN * 2
    h = orn_y + 3 + MARGIN
    fill = set()
    for ch, ox in zip(text, offsets):
        fill |= {(x + ox, y + MARGIN) for x, y in glyph_mask(ch)}

    # Орнамент: линия с разрывами у центрального ромба и маленькими ромбами по краям.
    cx = w // 2
    ornament = set()
    for x in range(MARGIN + 4, w - MARGIN - 4):
        if abs(x - cx) > 5:
            ornament.add((x, orn_y))
    for r, ox in ((3, cx), (1, MARGIN + 2), (1, w - MARGIN - 3)):
        for dx in range(-r, r + 1):
            for dy in range(-r, r + 1):
                if abs(dx) + abs(dy) <= r:
                    ornament.add((ox + dx, orn_y + dy))

    base = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    accent = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    bp, ap = base.load(), accent.load()
    solid = fill | ornament
    around = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]
    outline = {(x + dx, y + dy) for x, y in solid for dx, dy in around} - solid
    body = solid | outline

    # Падающая тень всего силуэта.
    for x, y in body:
        sx, sy = x + 1, y + 2
        if (sx, sy) not in body and 0 <= sx < w and 0 <= sy < h:
            bp[sx, sy] = SHADOW
    for x, y in outline:
        if 0 <= x < w and 0 <= y < h:
            bp[x, y] = OUTLINE + (255,)

    # Камень: вертикальный градиент + фаска (свет сверху-слева).
    for x, y in fill:
        t = 0.85 - (y - MARGIN) / LETTER_H * 0.55
        if (x, y - 1) not in fill or (x - 1, y) not in fill:
            t += 0.3
        if (x, y + 1) not in fill or (x + 1, y) not in fill:
            t -= 0.3
        t += ((x * 7 + y * 13) % 5 - 2) * 0.03  # лёгкая фактура
        idx = max(0, min(len(STONE) - 1, int(t * len(STONE))))
        bp[x, y] = STONE[idx] + (255,)

    # Трещины: случайные блуждания внутри букв, светятся в акцентном слое.
    rng = random.Random(7)
    cracks = set()
    starts = sorted(p for p in fill if p[1] < MARGIN + 7)
    for _ in range(7):
        x, y = rng.choice(starts)
        for _ in range(rng.randint(7, 13)):
            if (x, y) in fill:
                cracks.add((x, y))
            x += rng.choice((-1, 0, 1))
            y += rng.choice((-1, 1, 1))
    for x, y in cracks:
        bp[x, y] = CRACK + (255,)
        ap[x, y] = (255, 255, 255, 255)
    for x, y in cracks:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            p = (x + dx, y + dy)
            if p in fill and p not in cracks:
                ap[p] = (255, 255, 255, 70)

    for x, y in ornament:
        bp[x, y] = CRACK + (255,)
        ap[x, y] = (255, 255, 255, 255)
    # Блик на центральном ромбе.
    ap[cx, orn_y - 2] = (255, 255, 255, 255)
    bp[cx, orn_y - 2] = STONE[-1] + (255,)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    base.save(OUT_DIR / "logo.png")
    accent.save(OUT_DIR / "logo_accent.png")
    print(f"saved logo.png and logo_accent.png ({w}x{h})")


if __name__ == "__main__":
    main()
