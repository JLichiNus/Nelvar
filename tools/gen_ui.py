"""Генератор пиксельного интерфейса Nelvar.

Создаёт:
  assets/fonts/nelvar_pixel.fnt + .png — пиксельный шрифт (BMFont, кириллица
      и латиница), высота заглавных 7 px. В теме используется с целым
      масштабом (размеры шрифта кратны 11: 22 = x2, 33 = x3).
  assets/fonts/nelvar_<стихия>.fnt + .png — стилизованные цветные варианты
      того же шрифта для кнопок меню (земля, огонь, лёд, воздух).
  assets/textures/ui/*.png — рамки кнопок и панелей (9-slice, уже увеличены
      в UI_SCALE раз), переключатель, курсоры стихий.

Запуск из корня проекта:
    python3 tools/gen_ui.py
"""

import math
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
FONT_DIR = ROOT / "assets" / "fonts"
UI_DIR = ROOT / "assets" / "textures" / "ui"
UI_SCALE = 3

# --- Шрифт ------------------------------------------------------------------
# Ячейка 11 строк: 0-1 — диакритика, 2-8 — заглавные (базовая линия под
# строкой 8), 4-8 — строчные, 9-10 — выносные элементы.
# Формат: строка «символ верхняя_строка», затем ряды глифа, пустая строка.
CELL_H = 11
BASE = 9
SPACE_ADVANCE = 4
GLYPHS = r"""
А 2
.###.
#...#
#...#
#####
#...#
#...#
#...#

Б 2
#####
#....
#....
####.
#...#
#...#
####.

В 2
####.
#...#
#...#
####.
#...#
#...#
####.

Г 2
#####
#....
#....
#....
#....
#....
#....

Д 2
.####.
.#..#.
.#..#.
.#..#.
.#..#.
.#..#.
######
#....#

Е 2
#####
#....
#....
####.
#....
#....
#####

Ё 0
.#.#.
.....
#####
#....
#....
####.
#....
#....
#####

Ж 2
#..#..#
#..#..#
.#.#.#.
..###..
.#.#.#.
#..#..#
#..#..#

З 2
.###.
#...#
....#
..##.
....#
#...#
.###.

И 2
#...#
#...#
#..##
#.#.#
##..#
#...#
#...#

Й 0
.#.#.
..#..
#...#
#...#
#..##
#.#.#
##..#
#...#
#...#

К 2
#...#
#..#.
#.#..
##...
#.#..
#..#.
#...#

Л 2
..###
.#..#
.#..#
.#..#
.#..#
.#..#
#...#

М 2
#...#
##.##
#.#.#
#.#.#
#...#
#...#
#...#

Н 2
#...#
#...#
#...#
#####
#...#
#...#
#...#

О 2
.###.
#...#
#...#
#...#
#...#
#...#
.###.

П 2
#####
#...#
#...#
#...#
#...#
#...#
#...#

Р 2
####.
#...#
#...#
####.
#....
#....
#....

С 2
.###.
#...#
#....
#....
#....
#...#
.###.

Т 2
#####
..#..
..#..
..#..
..#..
..#..
..#..

У 2
#...#
#...#
#...#
.####
....#
#...#
.###.

Ф 2
..#..
.###.
#.#.#
#.#.#
.###.
..#..
..#..

Х 2
#...#
#...#
.#.#.
..#..
.#.#.
#...#
#...#

Ц 2
#..#.
#..#.
#..#.
#..#.
#..#.
#..#.
#####
....#

Ч 2
#...#
#...#
#...#
.####
....#
....#
....#

Ш 2
#..#..#
#..#..#
#..#..#
#..#..#
#..#..#
#..#..#
#######

Щ 2
#..#..#.
#..#..#.
#..#..#.
#..#..#.
#..#..#.
#..#..#.
########
.......#

Ъ 2
##....
.#....
.#....
.####.
.#...#
.#...#
.####.

Ы 2
#.....#
#.....#
#.....#
####..#
#...#.#
#...#.#
####..#

Ь 2
#....
#....
#....
####.
#...#
#...#
####.

Э 2
.###.
#...#
....#
.####
....#
#...#
.###.

Ю 2
#..###.
#.#...#
#.#...#
###...#
#.#...#
#.#...#
#..###.

Я 2
.####
#...#
#...#
.####
..#.#
.#..#
#...#

а 4
.###.
....#
.####
#...#
.####

б 2
.####
#....
####.
#...#
#...#
#...#
.###.

в 4
####.
#...#
####.
#...#
####.

г 4
####
#...
#...
#...
#...

д 4
.###.
.#.#.
.#.#.
.#.#.
#####
#...#

е 4
.###.
#...#
#####
#....
.###.

ё 2
.#.#.
.....
.###.
#...#
#####
#....
.###.

ж 4
#.#.#
#.#.#
.###.
#.#.#
#.#.#

з 4
.###.
#...#
..##.
#...#
.###.

и 4
#...#
#..##
#.#.#
##..#
#...#

й 2
.#.#.
..#..
#...#
#..##
#.#.#
##..#
#...#

к 4
#..#
#.#.
##..
#.#.
#..#

л 4
..###
.#..#
.#..#
.#..#
#...#

м 4
#...#
##.##
#.#.#
#...#
#...#

н 4
#...#
#...#
#####
#...#
#...#

о 4
.###.
#...#
#...#
#...#
.###.

п 4
#####
#...#
#...#
#...#
#...#

р 4
####.
#...#
#...#
#...#
####.
#....
#....

с 4
.####
#....
#....
#....
.####

т 4
#####
..#..
..#..
..#..
..#..

у 4
#...#
#...#
#...#
#...#
.####
....#
.###.

ф 3
..#..
.###.
#.#.#
#.#.#
#.#.#
.###.
..#..

х 4
#...#
.#.#.
..#..
.#.#.
#...#

ц 4
#..#.
#..#.
#..#.
#..#.
#####
....#

ч 4
#...#
#...#
.####
....#
....#

ш 4
#.#.#
#.#.#
#.#.#
#.#.#
#####

щ 4
#.#.#.
#.#.#.
#.#.#.
#.#.#.
######
.....#

ъ 4
##...
.#...
.###.
.#..#
.###.

ы 4
#....#
#....#
###..#
#..#.#
###..#

ь 4
#...
#...
###.
#..#
###.

э 4
.###.
#...#
..###
#...#
.###.

ю 4
#..##.
#.#..#
###..#
#.#..#
#..##.

я 4
.####
#...#
.####
.#..#
#...#

A 2
.###.
#...#
#...#
#####
#...#
#...#
#...#

B 2
####.
#...#
#...#
####.
#...#
#...#
####.

C 2
.###.
#...#
#....
#....
#....
#...#
.###.

D 2
####.
#...#
#...#
#...#
#...#
#...#
####.

E 2
#####
#....
#....
####.
#....
#....
#####

F 2
#####
#....
#....
####.
#....
#....
#....

G 2
.###.
#...#
#....
#.###
#...#
#...#
.###.

H 2
#...#
#...#
#...#
#####
#...#
#...#
#...#

I 2
###
.#.
.#.
.#.
.#.
.#.
###

J 2
..###
...#.
...#.
...#.
#..#.
#..#.
.##..

K 2
#...#
#..#.
#.#..
##...
#.#..
#..#.
#...#

L 2
#....
#....
#....
#....
#....
#....
#####

M 2
#...#
##.##
#.#.#
#.#.#
#...#
#...#
#...#

N 2
#...#
##..#
#.#.#
#..##
#...#
#...#
#...#

O 2
.###.
#...#
#...#
#...#
#...#
#...#
.###.

P 2
####.
#...#
#...#
####.
#....
#....
#....

Q 2
.###.
#...#
#...#
#...#
#.#.#
#..#.
.##.#

R 2
####.
#...#
#...#
####.
#.#..
#..#.
#...#

S 2
.###.
#...#
#....
.###.
....#
#...#
.###.

T 2
#####
..#..
..#..
..#..
..#..
..#..
..#..

U 2
#...#
#...#
#...#
#...#
#...#
#...#
.###.

V 2
#...#
#...#
#...#
#...#
.#.#.
.#.#.
..#..

W 2
#...#
#...#
#...#
#.#.#
#.#.#
##.##
#...#

X 2
#...#
#...#
.#.#.
..#..
.#.#.
#...#
#...#

Y 2
#...#
#...#
.#.#.
..#..
..#..
..#..
..#..

Z 2
#####
....#
...#.
..#..
.#...
#....
#####

a 4
.###.
....#
.####
#...#
.####

b 2
#....
#....
####.
#...#
#...#
#...#
####.

c 4
.####
#....
#....
#....
.####

d 2
....#
....#
.####
#...#
#...#
#...#
.####

e 4
.###.
#...#
#####
#....
.###.

f 2
..##
.#..
####
.#..
.#..
.#..
.#..

g 4
.####
#...#
#...#
#...#
.####
....#
.###.

h 2
#....
#....
####.
#...#
#...#
#...#
#...#

i 2
#
.
#
#
#
#
#

j 2
..#
...
..#
..#
..#
..#
..#
..#
##.

k 2
#...
#...
#..#
#.#.
##..
#.#.
#..#

l 2
#.
#.
#.
#.
#.
#.
.#

m 4
##.#.
#.#.#
#.#.#
#.#.#
#.#.#

n 4
####.
#...#
#...#
#...#
#...#

o 4
.###.
#...#
#...#
#...#
.###.

p 4
####.
#...#
#...#
#...#
####.
#....
#....

q 4
.####
#...#
#...#
#...#
.####
....#
....#

r 4
#.##
##..
#...
#...
#...

s 4
.####
#....
.###.
....#
####.

t 3
.#..
####
.#..
.#..
.#..
..##

u 4
#...#
#...#
#...#
#...#
.####

v 4
#...#
#...#
#...#
.#.#.
..#..

w 4
#...#
#...#
#.#.#
#.#.#
.#.#.

x 4
#...#
.#.#.
..#..
.#.#.
#...#

y 4
#...#
#...#
#...#
#...#
.####
....#
.###.

z 4
#####
...#.
..#..
.#...
#####

0 2
.###.
#...#
#..##
#.#.#
##..#
#...#
.###.

1 2
.#.
##.
.#.
.#.
.#.
.#.
###

2 2
.###.
#...#
....#
...#.
..#..
.#...
#####

3 2
####.
....#
....#
.###.
....#
....#
####.

4 2
...#.
..##.
.#.#.
#..#.
#####
...#.
...#.

5 2
#####
#....
####.
....#
....#
#...#
.###.

6 2
.###.
#....
#....
####.
#...#
#...#
.###.

7 2
#####
....#
...#.
..#..
..#..
..#..
..#..

8 2
.###.
#...#
#...#
.###.
#...#
#...#
.###.

9 2
.###.
#...#
#...#
.####
....#
....#
.###.

. 8
#

, 8
.#
#.

: 4
#
.
.
.
#

; 4
.#
..
..
.#
#.

! 2
#
#
#
#
#
.
#

? 2
.###.
#...#
....#
...#.
..#..
.....
..#..

- 6
###

— 6
######

/ 2
....#
...#.
...#.
..#..
.#...
.#...
#....

( 2
..#
.#.
#..
#..
#..
.#.
..#

) 2
#..
.#.
..#
..#
..#
.#.
#..

« 4
..#.#
.#.#.
#.#..
.#.#.
..#.#

» 4
#.#..
.#.#.
..#.#
.#.#.
#.#..

% 2
##..#
##.#.
...#.
..#..
.#...
.#.##
#..##

+ 4
..#..
..#..
#####
..#..
..#..

= 5
####
....
####

" 2
#.#
#.#

' 2
#
#

· 6
#

… 8
#.#.#

× 4
#...#
.#.#.
..#..
.#.#.
#...#

< 3
...#
..#.
.#..
#...
.#..
..#.
...#

> 3
#...
.#..
..#.
...#
..#.
.#..
#...

[ 2
##
#.
#.
#.
#.
#.
##

] 2
##
.#
.#
.#
.#
.#
##

_ 9
#####

| 2
#
#
#
#
#
#
#
"""


def parse_glyphs():
    glyphs = {}
    blocks = [b for b in GLYPHS.strip("\n").split("\n\n") if b.strip()]
    for block in blocks:
        lines = block.split("\n")
        head = lines[0]
        ch, top = head[0], int(head[2:])
        rows = lines[1:]
        glyphs[ch] = (top, rows)
    return glyphs


def make_font():
    glyphs = parse_glyphs()
    pad = 1
    cols = 16
    cell_w = max(len(r[0]) for _, r in glyphs.values()) + pad * 2
    cell_h = CELL_H + pad * 2
    chars = sorted(glyphs, key=ord)
    rows_n = (len(chars) + cols - 1) // cols
    atlas = Image.new("RGBA", (cols * cell_w, rows_n * cell_h), (0, 0, 0, 0))
    px = atlas.load()
    lines = []
    for i, ch in enumerate(chars):
        top, rows = glyphs[ch]
        w = len(rows[0])
        ax, ay = (i % cols) * cell_w + pad, (i // cols) * cell_h + pad
        for y, row in enumerate(rows):
            assert len(row) == w, f"glyph {ch!r}: ragged row {row!r}"
            for x, c in enumerate(row):
                if c == "#":
                    px[ax + x, ay + y] = (255, 255, 255, 255)
        lines.append(
            f"char id={ord(ch)} x={ax} y={ay} width={w} height={len(rows)} "
            f"xoffset=0 yoffset={top} xadvance={w + 1} page=0 chnl=15")
    lines.append(f"char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 "
                 f"xadvance={SPACE_ADVANCE} page=0 chnl=15")
    FONT_DIR.mkdir(parents=True, exist_ok=True)
    atlas.save(FONT_DIR / "nelvar_pixel.png")
    header = [
        f'info face="Nelvar Pixel" size={CELL_H} bold=0 italic=0 charset="" unicode=1 '
        f'stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1 outline=0',
        f"common lineHeight={CELL_H + 2} base={BASE} scaleW={atlas.width} scaleH={atlas.height} "
        f"pages=1 packed=0 alphaChnl=0 redChnl=4 greenChnl=4 blueChnl=4",
        'page id=0 file="nelvar_pixel.png"',
        f"chars count={len(lines)}",
    ]
    (FONT_DIR / "nelvar_pixel.fnt").write_text("\n".join(header + lines) + "\n", encoding="utf-8")
    print(f"font: {len(chars) + 1} glyphs")


# --- Текстуры интерфейса -----------------------------------------------------
OUTLINE = (20, 18, 26, 255)
STONE = (230, 220, 198, 255)
STONE_DARK = (156, 140, 124, 255)


def from_rows(rows, palette):
    h, w = len(rows), len(rows[0])
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    p = img.load()
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c in palette:
                p[x, y] = palette[c]
    return img


def save_scaled(img, name, scale=UI_SCALE):
    UI_DIR.mkdir(parents=True, exist_ok=True)
    img.resize((img.width * scale, img.height * scale), Image.NEAREST).save(UI_DIR / name)


def frame(w, h, fill, top, bottom, outline=OUTLINE, inner=None):
    """Рамка со срезанными углами: обводка, светлый верх, тёмный низ."""
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    p = img.load()
    for y in range(h):
        for x in range(w):
            corner = (x in (0, w - 1)) and (y in (0, h - 1))
            if corner:
                continue
            edge = x in (0, w - 1) or y in (0, h - 1) or ((x in (1, w - 2)) and (y in (1, h - 2)))
            if edge:
                p[x, y] = outline
            elif y == 1:
                p[x, y] = top
            elif y == h - 2:
                p[x, y] = bottom
            else:
                p[x, y] = fill
    if inner:
        for y in range(2, h - 2):
            for x in range(2, w - 2):
                if x in (2, w - 3) or y in (2, h - 3):
                    if not ((x in (2, w - 3)) and (y in (2, h - 3))):
                        p[x, y] = inner
    return img


def make_ui():
    # Кнопка: тёмный камень.
    save_scaled(frame(12, 10, (34, 38, 48, 225), (58, 64, 78, 235), (22, 24, 32, 235)), "button.png")
    # Выбранная кнопка остаётся тёмной: светлая (серая) только рамка, и меню
    # окрашивает её в цвет стихии через modulate — текст всегда на чёрном.
    save_scaled(frame(12, 10, (52, 52, 56, 235), (96, 96, 100, 245), (34, 34, 38, 240),
                      outline=(240, 240, 240, 255)), "button_hi.png")
    save_scaled(frame(12, 10, (40, 40, 44, 240), (28, 28, 32, 245), (70, 70, 74, 245),
                      outline=(200, 200, 200, 255)), "button_pressed.png")
    # Рамка фокуса для обычных кнопок (прозрачная середина).
    focus = Image.new("RGBA", (12, 10), (0, 0, 0, 0))
    fp = focus.load()
    for y in range(10):
        for x in range(12):
            if (x in (0, 11) or y in (0, 9)) and not ((x in (0, 11)) and (y in (0, 9))):
                fp[x, y] = STONE
    save_scaled(focus, "focus.png")
    # Панель: каменная двойная рамка с заклёпками в углах.
    panel = frame(16, 16, (16, 20, 28, 236), (30, 34, 44, 240), (12, 14, 20, 240),
                  inner=STONE_DARK)
    pp = panel.load()
    for x, y in ((2, 2), (13, 2), (2, 13), (13, 13)):
        pp[x, y] = STONE
    save_scaled(panel, "panel.png")

    # Переключатель.
    pal = {"o": OUTLINE, "d": (40, 44, 56, 255), "k": (150, 140, 130, 255), "K": (200, 190, 172, 255),
           "g": (120, 168, 96, 255), "G": (164, 206, 120, 255), "w": STONE, "s": (90, 84, 80, 255)}
    off = ["..oooooooooo..",
           ".oddddddddddo.",
           "oookkkoddddddo",
           "okKKKkoddddddo",
           "okKKKkoddddddo",
           "oskkksoddddddo",
           ".ooooooooooooo."[:14],
           ]
    on = ["..oooooooooo..",
          ".oggggggggggo.",
          "ogggggggoKKKoo",
          "oGggggggokwwKo",
          "oGggggggokwwKo",
          "ogggggggoskkso",
          ".oooooooooooo.",
          ]
    off[-1] = ".oooooooooooo."
    save_scaled(from_rows(off, pal), "toggle_off.png")
    save_scaled(from_rows(on, pal), "toggle_on.png")

    print("ui textures saved")


# --- Стилизованные шрифты стихий ------------------------------------------------
# Цвета вшиты в атлас: шрифт рисуется как есть и только затемняется font_color.
STYLE_SHIFT = 3  # запас сверху под языки пламени
EIGHT = [(dx, dy) for dx in (-1, 0, 1) for dy in (-1, 0, 1) if dx or dy]


def _h(*args):
    n = 2166136261
    for a in args:
        n = ((n ^ (a & 0xFFFFFFFF)) * 16777619) & 0xFFFFFFFF
    n ^= n >> 15
    return (n & 0xFFFF) / 65535.0


def _outlined(colors, outline):
    pix = set(colors)
    for x, y in {(x + dx, y + dy) for x, y in pix for dx, dy in EIGHT} - pix:
        colors[(x, y)] = outline
    return colors


def style_earth(mask, code):
    """Жирный камень, поросший мхом сверху."""
    bold = mask | {(x + 1, y) for x, y in mask}
    colors = {}
    for x, y in bold:
        top = (x, y - 1) not in bold
        if top and y <= 5:
            colors[(x, y)] = (128, 178, 78) if _h(code, x, y) > 0.4 else (88, 140, 60)
        elif (x - 1, y) not in bold:
            colors[(x, y)] = (214, 200, 170)
        elif y <= 4:
            colors[(x, y)] = (190, 172, 142)
        elif y <= 6:
            colors[(x, y)] = (160, 142, 116)
        else:
            colors[(x, y)] = (122, 106, 90)
        if not top and _h(code, x, y, 7) > 0.93:
            colors[(x, y)] = (92, 80, 70)  # трещинка
    return _outlined(colors, (34, 24, 20)), 2


def style_fire(mask, code):
    """Буквы-пламя: горячий низ, красные языки сверху."""
    colors = {}
    for x, y in mask:
        if y >= 7:
            c = (255, 234, 150)
        elif y >= 5:
            c = (255, 176, 64)
        elif y >= 3:
            c = (240, 102, 38)
        else:
            c = (196, 48, 28)
        colors[(x, y)] = c
    for x, y in mask:
        if (x, y - 1) not in mask and _h(code, x, y) < 0.45:
            colors.setdefault((x, y - 1), (226, 84, 32))
            if _h(code, x, y, 3) < 0.5:
                colors.setdefault((x, y - 2), (168, 36, 24))
    return _outlined(colors, (48, 10, 10)), 1


def style_ice(mask, code):
    """Снежно-белые буквы с сосульками."""
    colors = {}
    for x, y in mask:
        colors[(x, y)] = (255, 255, 255) if y <= 3 else (230, 236, 242) if y <= 6 else (198, 210, 222)
    for x, y in mask:
        # Только с концов вертикальных штрихов: иначе «с» превращается в «ς».
        stem_end = (x, y + 1) not in mask and (x, y - 1) in mask
        if stem_end and y >= 6 and _h(code, x, y) < 0.5:
            colors.setdefault((x, y + 1), (208, 226, 238))
            if _h(code, x, y, 5) < 0.45:
                colors.setdefault((x, y + 2), (156, 186, 210))
    return _outlined(colors, (42, 52, 70)), 1


def style_air(mask, code):
    """Прямые буквы с небесным градиентом. Ветер добавляет шейдер в меню."""
    colors = {}
    for x, y in mask:
        colors[(x, y)] = (255, 255, 255) if y <= 4 else (214, 240, 252) if y <= 6 else (160, 214, 240)
    return _outlined(colors, (26, 58, 92)), 1


def make_styled_font(name, style):
    glyphs = parse_glyphs()
    rendered = []
    for ch in sorted(glyphs, key=ord):
        top, rows = glyphs[ch]
        mask = {(x, y + top) for y, row in enumerate(rows) for x, c in enumerate(row) if c == "#"}
        colors, extra = style(mask, ord(ch))
        xs = [p[0] for p in colors]
        ys = [p[1] for p in colors]
        x0, y0 = min(xs), min(ys)
        # Прозрачный столбец по бокам: шейдер ветра сдвигает строки пикселей
        # и не должен обрезать их о край квадрата глифа.
        img = Image.new("RGBA", (max(xs) - x0 + 3, max(ys) - y0 + 1), (0, 0, 0, 0))
        ip = img.load()
        for (x, y), c in colors.items():
            ip[x - x0 + 1, y - y0] = c + (255,)
        rendered.append((ch, img, x0 - 1, y0 + STYLE_SHIFT, len(rows[0]) + 1 + extra))
    cols = 16
    cell_w = max(r[1].width for r in rendered) + 2
    cell_h = max(r[1].height for r in rendered) + 2
    atlas = Image.new("RGBA", (cols * cell_w, ((len(rendered) + cols - 1) // cols) * cell_h), (0, 0, 0, 0))
    lines = []
    for i, (ch, img, xo, yo, adv) in enumerate(rendered):
        ax, ay = (i % cols) * cell_w + 1, (i // cols) * cell_h + 1
        atlas.paste(img, (ax, ay))
        lines.append(f"char id={ord(ch)} x={ax} y={ay} width={img.width} height={img.height} "
                     f"xoffset={xo} yoffset={yo} xadvance={adv} page=0 chnl=15")
    lines.append(f"char id=32 x=0 y=0 width=0 height=0 xoffset=0 yoffset=0 "
                 f"xadvance={SPACE_ADVANCE + 1} page=0 chnl=15")
    atlas.save(FONT_DIR / f"nelvar_{name}.png")
    header = [
        f'info face="Nelvar {name}" size={CELL_H} bold=0 italic=0 charset="" unicode=1 '
        f'stretchH=100 smooth=0 aa=1 padding=0,0,0,0 spacing=1,1 outline=0',
        f"common lineHeight={CELL_H + 2 + STYLE_SHIFT} base={BASE + STYLE_SHIFT} "
        f"scaleW={atlas.width} scaleH={atlas.height} pages=1 packed=0 "
        f"alphaChnl=0 redChnl=0 greenChnl=0 blueChnl=0",
        f'page id=0 file="nelvar_{name}.png"',
        f"chars count={len(lines)}",
    ]
    (FONT_DIR / f"nelvar_{name}.fnt").write_text("\n".join(header + lines) + "\n", encoding="utf-8")


# --- Курсоры стихий -----------------------------------------------------------
# Узкий треугольный наконечник остриём вверх-влево с вогнутым основанием.
# Остриё — в точке (1, 1) картинки (после обводки), это и есть hotspot.
CURSOR_SCALE = 2
CURSOR_POLY = [(0.0, 0.0), (2.8, 13.3), (6.2, 9.8), (14.2, 10.0)]
CURSOR_STYLES = {
    # обводка, светлая грань, тень, градиент от острия к основанию
    "earth": ((34, 24, 20), (236, 222, 190), (120, 104, 86),
              [(214, 200, 170), (190, 172, 142), (160, 142, 116)]),
    "fire": ((48, 10, 10), (255, 244, 190), (170, 40, 24),
             [(255, 230, 140), (255, 168, 60), (236, 90, 34)]),
    "ice": ((42, 52, 70), (255, 255, 255), (170, 188, 206),
            [(255, 255, 255), (232, 238, 244), (204, 216, 228)]),
    "air": ((26, 58, 92), (255, 255, 255), (110, 176, 222),
            [(255, 255, 255), (206, 236, 250), (150, 208, 238)]),
    # Пустота: чёрный наконечник в белой обводке (своего шрифта у неё нет).
    "void": ((255, 255, 255), (44, 42, 52), (0, 0, 0),
             [(16, 15, 20), (10, 9, 13), (4, 4, 6)]),
}


def _inside(poly, px, py):
    inside = False
    for i in range(len(poly)):
        (x1, y1), (x2, y2) = poly[i], poly[i - 1]
        if (y1 > py) != (y2 > py) and px < (x2 - x1) * (py - y1) / (y2 - y1) + x1:
            inside = not inside
    return inside


def make_cursor(name):
    outline, light, shade, grad = CURSOR_STYLES[name]
    fill = {(x, y) for x in range(16) for y in range(18) if _inside(CURSOR_POLY, x + 0.5, y + 0.5)}
    fill.add((0, 0))  # остриё
    img = Image.new("RGBA", (18, 20), (0, 0, 0, 0))
    p = img.load()
    for x, y in {(x + dx, y + dy) for x, y in fill for dx, dy in EIGHT} - fill:
        if x >= -1 and y >= -1:
            p[x + 1, y + 1] = outline + (255,)
    for x, y in fill:
        t = min(0.999, (x + y) / 16.5)
        c = grad[int(t * len(grad))]
        if (x - 1, y) not in fill or (x, y - 1) not in fill:
            c = light  # грань к свету
        elif (x + 1, y) not in fill or (x, y + 1) not in fill:
            c = shade
        p[x + 1, y + 1] = c + (255,)
    if name == "earth":  # мох у основания
        for x, y in fill:
            if x + y >= 12 and (x * 7 + y * 3) % 5 < 2:
                p[x + 1, y + 1] = (104, 156, 70, 255)
    elif name == "fire":  # раскалённая сердцевина
        for x, y in fill:
            if 3 <= x + y <= 10 and abs(x - y * 0.95) < 1.0:
                p[x + 1, y + 1] = (255, 250, 220, 255)
    save_scaled(img, f"cursor_{name}.png", scale=CURSOR_SCALE)


def make_element_ui():
    for name, style in (("earth", style_earth), ("fire", style_fire), ("ice", style_ice), ("air", style_air)):
        make_styled_font(name, style)
        make_cursor(name)
    make_cursor("void")
    print("element fonts and cursors saved")


# --- Иконки способностей -------------------------------------------------------
# 24×24 арт-пикселя (в игре ×ICON_SCALE), палитра воздуха, тёмная обводка
# рисуется сама. Рисунки — по наброскам автора: снаряд-комета, расходящаяся
# волна, ветряной рывок-стрела, две волны, сжимаемые стрелками.
ICON_SIZE = 24
ICON_SCALE = 2
ICON_OUTLINE = (20, 40, 66)
ICON_WHITE = (255, 255, 255)
ICON_LIGHT = (206, 236, 250)
ICON_MID = (130, 194, 232)
ICON_DEEP = (70, 130, 186)


def _icon_save(pixels, name, dark=()):
    """pixels: {(x, y): rgb}; обводка в 8 соседей вокруг рисунка.
    dark: пиксели рисунка, которые закрашиваются обводкой (разделители)."""
    img = Image.new("RGBA", (ICON_SIZE, ICON_SIZE), (0, 0, 0, 0))
    p = img.load()
    for x, y in {(x + dx, y + dy) for x, y in pixels for dx, dy in EIGHT} - set(pixels):
        if 0 <= x < ICON_SIZE and 0 <= y < ICON_SIZE:
            p[x, y] = ICON_OUTLINE + (255,)
    for (x, y), c in pixels.items():
        if 0 <= x < ICON_SIZE and 0 <= y < ICON_SIZE:
            p[x, y] = c + (255,)
    for x, y in dark:
        if (x, y) in pixels:
            p[x, y] = ICON_OUTLINE + (255,)
    save_scaled(img, f"ability_{name}.png", ICON_SCALE)


def _bez(pts, t):
    while len(pts) > 1:
        pts = [(a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t) for a, b in zip(pts, pts[1:])]
    return pts[0]


def _stroke(px, pts, w0, w1, colors, steps=200):
    """Кривая Безье с толщиной от w0 к w1; colors: [(t_до, цвет), ...] вдоль кривой."""
    samples = [_bez(pts, i / steps) for i in range(steps + 1)]
    for y in range(ICON_SIZE):
        for x in range(ICON_SIZE):
            best = None
            for i, (sx, sy) in enumerate(samples):
                t = i / steps
                r = (w0 + (w1 - w0) * t) / 2
                d = math.hypot(x + 0.5 - sx, y + 0.5 - sy)
                if d <= r and (best is None or d - r < best[0]):
                    best = (d - r, t)
            if best:
                t = best[1]
                for lim, c in colors:
                    if t <= lim:
                        px[(x, y)] = c
                        break


def _thin(px, pts, colors, steps=400):
    """Линия в 1 пиксель вдоль кривой Безье, без Г-образных ступенек."""
    path = []
    for i in range(steps + 1):
        x, y = _bez(pts, i / steps)
        p = (int(math.floor(x)), int(math.floor(y)))
        if not path or path[-1] != p:
            path.append(p)
    clean = []
    for p in path:
        if len(clean) >= 2:
            a, b = clean[-2], clean[-1]
            if abs(a[0] - p[0]) == 1 and abs(a[1] - p[1]) == 1 and (b[0] == a[0] or b[1] == a[1]):
                clean.pop()
        clean.append(p)
    n = len(clean)
    for i, p in enumerate(clean):
        t = i / max(1, n - 1)
        for lim, c in colors:
            if t <= lim:
                px[p] = c
                break


def icon_primary():
    """ЛКМ: шар сжатого воздуха летит вверх-вправо, за ним хвост кометы."""
    px = {}
    cx, cy, r = 15.5, 7.5, 5.0
    # хвост: капля между двумя кривыми, у основания шириной с шар
    left = [(10.6, 6.6), (7.8, 11.0), (9.8, 16.5), (6.0, 23.5)]
    right = [(17.0, 12.6), (11.2, 15.0), (11.6, 19.0), (6.0, 23.5)]
    steps = 120
    for i in range(steps + 1):
        t = i / steps
        a, b = _bez(left, t), _bez(right, t)
        for j in range(41):
            s = j / 40
            x, y = a[0] + (b[0] - a[0]) * s, a[1] + (b[1] - a[1]) * s
            k = t + 0.35 * abs(s - 0.5)
            px[(int(x), int(y))] = ICON_LIGHT if k < 0.32 else ICON_MID if k < 0.7 else ICON_DEEP
    _thin(px, [(11, 12), (9, 15), (10, 18), (7, 22)], [(0.45, ICON_WHITE), (1, ICON_LIGHT)])
    # отдельные струйки по бокам
    _thin(px, [(5, 8), (1, 12), (6, 16), (2, 21)], [(0.5, ICON_LIGHT), (1, ICON_MID)])
    _thin(px, [(18, 15), (21, 17), (17, 21)], [(0.6, ICON_LIGHT), (1, ICON_MID)])
    # шар, отделённый от хвоста тёмным кольцом
    ring = []
    for y in range(ICON_SIZE):
        for x in range(ICON_SIZE):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            d = math.hypot(dx, dy)
            if d <= r:
                light = dx + dy
                if d > r - 1.1 and light > 1.5:
                    c = ICON_MID
                elif abs(d - 3.1) < 0.55 and dx > 0.3 and dy > 0.3:
                    c = ICON_WHITE  # внутренняя дуга-завиток
                else:
                    c = ICON_LIGHT
                px[(x, y)] = c
            elif d <= r + 1.0:
                ring.append((x, y))
    for p in ((13, 5), (13, 4), (14, 4)):
        px[p] = ICON_WHITE
    return px, ring


def _arc(px, ox, oy, radius, a0, a1, w0, wm, colors):
    """Дуга окружности вокруг (ox, oy) от угла a0 до a1 (градусы), толще в середине."""
    n = 8
    pts = []
    for i in range(n + 1):
        a = math.radians(a0 + (a1 - a0) * i / n)
        pts.append((ox + math.cos(a) * radius, oy + math.sin(a) * radius))
    for i in range(n):
        wa = w0 + (wm - w0) * math.sin(math.pi * i / n)
        wb = w0 + (wm - w0) * math.sin(math.pi * (i + 1) / n)
        _stroke(px, [pts[i], pts[i + 1]], wa, wb, colors, steps=30)


def icon_wave():
    """ПКМ: фронт волны расходится из угла, порывы толкают его наружу."""
    px = {}
    _arc(px, 2.0, 22.5, 20.0, -86, -4, 1.0, 3.4, [(1, ICON_WHITE)])
    _arc(px, 2.0, 22.5, 14.5, -82, -8, 1.0, 2.2, [(1, ICON_LIGHT)])
    # порывы, толкающие фронт (ровные штрихи под 45°)
    for (x0, y0, n, c) in ((2, 15, 4, ICON_MID), (4, 20, 5, ICON_LIGHT)):
        for i in range(n):
            px[(x0 + i, y0 - i)] = c
            px[(x0 + i + 1, y0 - i)] = c
    return px, ()


def icon_flight():
    """Shift: рывок — стрела из воздушных потоков с линиями скорости."""
    px = {}
    poly = [(2, 7), (14, 10), (15.5, 8), (23, 12), (15.5, 16), (14, 14), (2, 17), (7.5, 12)]

    def inside(x, y):
        c = False
        for (ax, ay), (bx, by) in zip(poly, poly[1:] + poly[:1]):
            if (ay > y) != (by > y) and x < ax + (y - ay) * (bx - ax) / (by - ay):
                c = not c
        return c

    for y in range(ICON_SIZE):
        for x in range(ICON_SIZE):
            if inside(x + 0.5, y + 0.5):
                fx = x + 0.5
                px[(x, y)] = ICON_WHITE if fx > 17 else ICON_LIGHT if fx > 10 else ICON_MID
    # поток вдоль стрелы
    _thin(px, [(6, 12), (21, 12)], [(0.35, ICON_DEEP), (0.6, ICON_LIGHT), (1, ICON_WHITE)])
    # линии скорости
    _thin(px, [(5, 3), (15, 4)], [(0.3, ICON_MID), (1, ICON_LIGHT)])
    _thin(px, [(2, 21), (13, 20)], [(0.3, ICON_MID), (1, ICON_LIGHT)])
    _thin(px, [(17, 3), (21, 7)], [(1, ICON_MID)])
    _thin(px, [(17, 21), (21, 17)], [(1, ICON_MID)])
    return px, ()


def icon_compression():
    """R: две волны с противоположных углов, стрелки толкают их навстречу."""
    px = {}
    for ox, oy, a0, a1, sx in ((23.0, 1.0, 94, 176, -1), (1.0, 23.0, -86, -4, 1)):
        # волна выгнута к центру
        _arc(px, ox, oy, 10.0, a0, a1, 1.0, 3.0, [(1, ICON_WHITE)])
        # стрелка из угла: остриё в вогнутости волны
        tx, ty = (18, 5) if sx < 0 else (5, 18)
        for i in range(5):
            px[(tx - sx * i, ty + sx * i)] = ICON_MID if i > 2 else ICON_LIGHT
        for i in range(1, 4):
            px[(tx, ty + sx * i)] = ICON_LIGHT
            px[(tx - sx * i, ty)] = ICON_LIGHT
    # сжатый воздух между волнами
    for p in ((11, 12), (12, 11)):
        px[p] = ICON_LIGHT
    return px, ()


def make_ability_icons():
    for name, draw in (("primary", icon_primary), ("wave", icon_wave),
                       ("flight", icon_flight), ("compression", icon_compression)):
        pixels, dark = draw()
        _icon_save(pixels, name, dark)
    print("ability icons saved")


if __name__ == "__main__":
    make_font()
    make_ui()
    make_element_ui()
    make_ability_icons()
