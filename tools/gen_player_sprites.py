"""Генератор спрайтов игрока из базового рисунка 32x32.

Спрайт собирается из двух слоёв, чтобы атаки не останавливали ноги:
  * legs  — ноги: idle / walk / run / fly;
  * torso — корпус с шарфом: idle / walk / run / fly + анимации атак
            (attack_primary — ЛКМ, attack_wave — ПКМ,
             attack_compression — R).
Кадры локомоции у слоёв совпадают по числу и fps — игрок синхронизирует их.

Верх тела берётся из nelvar_wind_wanderer_32x32.png, ноги рисуются заново
(носками вперёд — персонаж смотрит вправо), руки и ветер — патчами ниже.

Запуск из корня проекта:
    python3 tools/gen_player_sprites.py [путь_к_базовому_png]
"""

import math
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
SRC = Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "nelvar_wind_wanderer_32x32.png"
OUT_DIR = ROOT / "player" / "sprites"
SIZE = 32

OUTLINE = (16, 43, 48, 255)
PANTS = (23, 55, 59, 255)
PANTS_FAR = (16, 38, 42, 255)
BOOT_DARK = (112, 82, 75, 255)
BOOT = (154, 112, 96, 255)
BOOT_LIGHT = (195, 174, 160, 255)
BOOT_FAR_DARK = (84, 62, 58, 255)
BOOT_FAR = (122, 89, 78, 255)
BOOT_FAR_LIGHT = (154, 112, 96, 255)
WIND = (115, 220, 223, 255)
WIND_LIGHT = (184, 245, 239, 255)
WIND_WHITE = (233, 245, 233, 255)

# Палитра для патчей. "." — не трогать пиксель, "_" — стереть.
PALETTE = {
    "A": OUTLINE,
    "B": (40, 108, 112, 255),   # рукав, тень
    "E": (53, 133, 137, 255),   # рукав
    "D": (64, 151, 151, 255),   # рукав, свет
    "N": (231, 198, 169, 255),  # кожа
    "M": (188, 157, 136, 255),  # кожа, тень
    "J": WIND,
    "L": WIND_LIGHT,
    "F": WIND_WHITE,
}

# Строки, где заканчивается туника (нижний контур) и стоят ступни.
BODY_BOTTOM = 28
GROUND = 31
# Центры бёдер: дальняя (задняя) и ближняя нога.
HIP_FAR = 15
HIP_NEAR = 21

FPS = {"idle": 5.0, "walk": 10.0, "run": 14.0, "fly": 12.0}


# --------------------------------------------------------------- утилиты


def blank() -> Image.Image:
    return Image.new("RGBA", (SIZE, SIZE))


def put(img: Image.Image, x: int, y: int, color) -> None:
    if 0 <= x < SIZE and 0 <= y < SIZE:
        img.putpixel((x, y), color)


def stamp(img: Image.Image, x0: int, y0: int, rows) -> None:
    """Рисует патч из строк палитры с левым верхним углом в (x0, y0)."""
    for dy, row in enumerate(rows):
        for dx, ch in enumerate(row):
            if ch == ".":
                continue
            if ch == "_":
                put(img, x0 + dx, y0 + dy, (0, 0, 0, 0))
            else:
                put(img, x0 + dx, y0 + dy, PALETTE[ch])


def shifted(img: Image.Image, dx: int, dy: int) -> Image.Image:
    if not (dx or dy):
        return img
    out = blank()
    for y in range(SIZE):
        for x in range(SIZE):
            p = img.getpixel((x, y))
            if p[3]:
                put(out, x + dx, y + dy, p)
    return out


# ------------------------------------------------------------ база и слои


def split_layers(base: Image.Image):
    """Делит базовый рисунок на тело и хвосты шарфа, выбрасывая старые ноги."""
    body, tails = blank(), blank()
    for y in range(SIZE):
        for x in range(SIZE):
            p = base.getpixel((x, y))
            if p[3] == 0:
                continue
            if y > BODY_BOTTOM:
                # Старые ботинки (смотрели назад) — выкидываем; полы плаща
                # справа/слева на этих строках оставляем телу.
                if 10 <= x <= 26:
                    continue
                body.putpixel((x, y), p)
            elif 14 <= y <= 24 and x <= 7 and not (y == 24 and x == 7):
                tails.putpixel((x, y), p)
            else:
                body.putpixel((x, y), p)
    # Нижний контур туники над старой ногой был цвета штанины.
    body.putpixel((16, BODY_BOTTOM), OUTLINE)
    return body, tails


def wave_tails(tails: Image.Image, phase: float, amp: float) -> Image.Image:
    """Колышет хвосты шарфа: сдвиг столбцов по вертикали растёт к кончику."""
    out = blank()
    attach_x = 8
    for x in range(attach_x):
        k = (attach_x - x) / attach_x  # 0 у тела, ~1 на кончике
        dy = round(amp * k * math.sin(phase - x * 0.7))
        for y in range(SIZE):
            p = tails.getpixel((x, y))
            if p[3]:
                put(out, x, y + dy, p)
    return out


def lean(body: Image.Image, dx: int, from_row: int = 15) -> Image.Image:
    """Наклон: всё выше from_row сдвигается по X на dx."""
    if not dx:
        return body
    out = blank()
    for y in range(SIZE):
        shift = dx if y < from_row else 0
        for x in range(SIZE):
            p = body.getpixel((x, y))
            if p[3]:
                put(out, x + shift, y, p)
    return out


def torso(body, tails, tail_phase: float, tail_amp: float, lean_dx: int = 0,
          dx: int = 0, dy: int = 0, patches=(), effects=None) -> Image.Image:
    """Корпус: хвосты + тело (+наклон) + патчи рук, общий сдвиг, эффекты.

    Патчи (руки) двигаются вместе с телом, эффекты ветра — в координатах
    кадра, чтобы не уезжать за край при сдвиге корпуса.
    """
    img = blank()
    img.alpha_composite(wave_tails(tails, tail_phase, tail_amp))
    img.alpha_composite(lean(body, lean_dx))
    for x0, y0, rows in patches:
        stamp(img, x0, y0, rows)
    img = shifted(img, dx, dy)
    if effects:
        effects(img)
    return img


# ------------------------------------------------------------------ ноги


def draw_leg(img: Image.Image, hip_x: int, foot_dx: int, lift: int, far: bool) -> None:
    """Штанина от туники до ботинка + ботинок носком вправо.

    hip_x  — центр бедра, foot_dx — вынос ступни вперёд(+)/назад(-),
    lift   — на сколько пикселей ступня оторвана от земли.
    """
    pants = PANTS_FAR if far else PANTS
    dark, mid, light = (
        (BOOT_FAR_DARK, BOOT_FAR, BOOT_FAR_LIGHT) if far else (BOOT_DARK, BOOT, BOOT_LIGHT)
    )
    sole = GROUND - lift
    fx = hip_x + foot_dx - 1  # левый край голенища
    boot_top = sole - 2
    # Штанина: от низа туники до голенища, ширина 2, со смещением к ступне.
    top = BODY_BOTTOM - 3
    for y in range(top, boot_top):
        t = (y - top) / max(boot_top - top, 1)
        cx = round(hip_x - 1 + (fx - (hip_x - 1)) * t)
        put(img, cx - 1, y, OUTLINE)
        put(img, cx, y, pants)
        put(img, cx + 1, y, pants)
        put(img, cx + 2, y, OUTLINE)
    # Ботинок: голенище 2px под штаниной, стопа 4px — носок торчит вправо.
    #   A d m A A
    #   A d m m l A
    #   A A A A A A
    for x in range(fx - 1, fx + 3):
        if 0 <= x < SIZE and 0 <= boot_top - 1 < SIZE and img.getpixel((x, boot_top - 1))[3] == 0:
            put(img, x, boot_top - 1, OUTLINE)
    put(img, fx - 1, boot_top, OUTLINE)
    put(img, fx, boot_top, dark)
    put(img, fx + 1, boot_top, mid)
    put(img, fx + 2, boot_top, OUTLINE)
    put(img, fx + 3, boot_top, OUTLINE)
    put(img, fx - 1, boot_top + 1, OUTLINE)
    put(img, fx, boot_top + 1, dark)
    put(img, fx + 1, boot_top + 1, mid)
    put(img, fx + 2, boot_top + 1, mid)
    put(img, fx + 3, boot_top + 1, light)
    put(img, fx + 4, boot_top + 1, OUTLINE)
    for x in range(fx - 1, fx + 5):
        put(img, x, sole, OUTLINE)


def legs_frame(far_dx, far_lift, near_dx, near_lift, effects=None) -> Image.Image:
    img = blank()
    draw_leg(img, HIP_FAR, far_dx, far_lift, True)
    draw_leg(img, HIP_NEAR, near_dx, near_lift, False)
    if effects:
        effects(img)
    return img


# (вынос дальней, подъём дальней, вынос ближней, подъём ближней, сдвиг корпуса)
WALK_CYCLE = [
    (-2, 0, 2, 0, 0),
    (-1, 1, 1, 0, -1),
    (1, 1, 0, 0, -1),
    (2, 0, -2, 0, 0),
    (1, 0, -1, 1, -1),
    (0, 0, 1, 1, -1),
]
RUN_CYCLE = [
    (-3, 1, 3, 0, 0),
    (-1, 2, 1, 0, -1),
    (2, 2, -1, 1, -2),
    (3, 0, -3, 1, 0),
    (1, 0, -1, 2, -1),
    (-1, 1, 2, 2, -2),
]
FLY_FRAMES = 4
IDLE_DY = [0, 0, 1, 1]


def fly_swirl(frame: int):
    """Вихрь под поджатыми ногами: две дуги, бегущие по кругу."""
    def draw(img):
        cx, cy, rx, ry = 18.5, 30.0, 6.5, 1.4
        for k in range(10):
            a = frame * math.pi / 2 + k * 0.38
            if k >= 5:
                a += math.pi
            color = WIND_LIGHT if k % 5 < 2 else WIND
            if k % 5 == 4:
                continue
            put(img, round(cx + rx * math.cos(a)), round(cy + ry * math.sin(a)), color)
    return draw


def legs_animations():
    idle = [legs_frame(0, 0, 0, 0) for _ in IDLE_DY]
    walk = [legs_frame(f, fl, n, nl) for f, fl, n, nl, _ in WALK_CYCLE]
    run = [legs_frame(f, fl, n, nl) for f, fl, n, nl, _ in RUN_CYCLE]
    # В полёте ноги поджаты и чуть отведены назад, ступни покачиваются.
    fly = []
    for i in range(FLY_FRAMES):
        bob = 1 if i in (1, 2) else 0
        fly.append(legs_frame(-2, 2 + bob, -1, 1 + bob, fly_swirl(i)))
    return {"idle": idle, "walk": walk, "run": run, "fly": fly}


# ---------------------------------------------------------------- корпус


def torso_locomotion(body, tails):
    idle = [torso(body, tails, i * math.pi / 2, 1.0, dy=dy) for i, dy in enumerate(IDLE_DY)]
    walk = [
        torso(body, tails, i * math.pi / 3, 1.2, dy=c[4]) for i, c in enumerate(WALK_CYCLE)
    ]
    run = [
        torso(body, tails, i * math.pi / 3 * 2, 1.6, lean_dx=1, dy=c[4])
        for i, c in enumerate(RUN_CYCLE)
    ]
    fly = [
        torso(body, tails, i * math.pi / 2 * 1.5, 2.0, lean_dx=1, dy=-1 if i in (1, 2) else 0)
        for i in range(FLY_FRAMES)
    ]
    return {"idle": idle, "walk": walk, "run": run, "fly": fly}


# Рука вытянута вперёд поверх шарфа: рукав x23-27, кисть x28-29.
ARM_OUT = (23, 19, [
    "AAAAAAA.",
    "EDDDDNNA",
    "BBBBBMMA",
    "AAAAAAA.",
])
# Рука наполовину убрана.
ARM_HALF = (24, 19, [
    "AAAA.",
    "EDNNA",
    "BBMMA",
    "AAAA.",
])
# Рука вскинута вверх перед капюшоном, ладонь раскрыта.
ARM_UP = (25, 9, [
    ".A.A.",
    "ANANA",
    "ANNNA",
    "AMNMA",
    "AEDA.",
    "AEDA.",
    "ABEA.",
    "ABEA.",
    "ABEA.",
    "ABEA.",
])
# То же, но кисть сжата в кулак.
FIST_UP = (25, 9, [
    ".....",
    ".AAA.",
    "AMNMA",
    "AMMMA",
    "AEDA.",
    "AEDA.",
    "ABEA.",
    "ABEA.",
    "ABEA.",
    "ABEA.",
])
HAND_UP = (27.0, 11.0)


def puff(points):
    """Эффект из списка (x, y, цвет-буква)."""
    def draw(img):
        for x, y, ch in points:
            put(img, x, y, PALETTE[ch])
    return draw


def crescent(cx: float, cy: float, r: float, half: int, sparse: bool = False):
    """Дуга волны «)» перед персонажем, как у атаки ПКМ."""
    def draw(img):
        for dy in range(-half, half + 1):
            if sparse and dy % 2:
                continue
            w = math.sqrt(max(r * r - dy * dy, 0.0))
            x = round(cx + w)
            y = round(cy + dy)
            edge = abs(dy) >= half - 1
            if sparse:
                put(img, x, y, PALETTE["J"])
                continue
            if not edge:
                put(img, x - 1, y, PALETTE["J"])
            put(img, x, y, PALETTE["F" if abs(dy) <= 1 else "J" if edge else "L"])
    return draw


def swirl(cx: float, cy: float, r: float, phase: float, count: int = 4):
    """Сходящийся вихрь вокруг кисти (R-сжатие)."""
    def draw(img):
        for k in range(count):
            a = phase + k * math.tau / count
            put(img, round(cx + r * math.cos(a)), round(cy + r * math.sin(a)),
                PALETTE["L" if k % 2 else "J"])
            # хвостик частицы по направлению вращения
            a2 = a - 0.5
            put(img, round(cx + (r + 0.8) * math.cos(a2)),
                round(cy + (r + 0.8) * math.sin(a2)), PALETTE["J"])
    return draw


def torso_attacks(body, tails):
    def t(i, arm, **kw):
        return torso(body, tails, i * math.pi / 2, 1.0, patches=[arm], **kw)

    # ЛКМ: короткий толчок рукой с выбросом ветра, 3 кадра = кулдаун 0.2 с.
    primary = [
        t(0, ARM_OUT, effects=puff([
            (30, 20, "F"), (30, 21, "F"), (31, 20, "L"), (31, 21, "L"),
            (30, 19, "L"), (30, 22, "L"), (31, 18, "J"), (31, 23, "J"),
        ])),
        t(1, ARM_OUT, effects=puff([(31, 20, "L"), (31, 21, "J"), (31, 18, "J")])),
        t(2, ARM_HALF),
    ]

    # ПКМ: замах назад (ветер собирается у кисти) -> выброс дуги -> возврат.
    wave = [
        t(0, ARM_HALF, dx=-1, lean_dx=-1, effects=puff([
            (30, 17, "J"), (30, 23, "J"), (31, 20, "J"),
        ])),
        t(1, ARM_HALF, dx=-1, lean_dx=-1, effects=swirl(27.5, 20.5, 2.5, 1.0)),
        t(2, ARM_OUT, effects=puff([
            (28, 15, "J"), (29, 16, "L"), (30, 17, "L"), (31, 18, "F"), (31, 19, "L"),
        ])),
        t(3, ARM_HALF, dx=1, lean_dx=1, effects=crescent(24.5, 20.5, 6.5, 6)),
        t(0, ARM_HALF, dx=1, lean_dx=1, effects=crescent(25.0, 20.5, 6.5, 6, sparse=True)),
        t(1, ARM_HALF),
    ]

    # R: ладонь вскинута, вихрь сходится к ней и сжимается в кулаке.
    compression = [
        t(0, ARM_HALF, effects=swirl(29.0, 20.5, 2.0, 0.0, 3)),
        t(1, ARM_UP, effects=swirl(*HAND_UP, 4.5, 0.6)),
        t(2, ARM_UP, effects=swirl(*HAND_UP, 3.5, 1.7)),
        t(3, ARM_UP, effects=swirl(*HAND_UP, 2.5, 2.8)),
        # хлопок: кулак сжат, вспышка, корпус напрягается вниз
        t(0, FIST_UP, dy=1, effects=puff([
            (26, 9, "F"), (28, 9, "F"), (27, 8, "L"), (24, 10, "L"), (30, 10, "L"),
            (24, 13, "J"), (30, 13, "J"), (27, 6, "J"),
        ])),
        t(1, FIST_UP, dy=1, effects=puff([(23, 8, "J"), (31, 8, "J"), (31, 14, "J")])),
        t(2, ARM_HALF),
    ]
    return {
        "attack_primary": (primary, 15.0, False),
        "attack_wave": (wave, 18.0, False),
        "attack_compression": (compression, 14.0, False),
    }


# ----------------------------------------------------------------- вывод


def save_strip(frames, name: str) -> None:
    strip = Image.new("RGBA", (SIZE * len(frames), SIZE))
    for i, f in enumerate(frames):
        strip.paste(f, (i * SIZE, 0))
    strip.save(OUT_DIR / f"{name}.png")


def write_sprite_frames(path: Path, anims) -> None:
    """SpriteFrames-ресурс: каждая полоса режется на AtlasTexture по 32x32.

    anims — список (имя_анимации, имя_файла, число_кадров, fps, loop).
    """
    ext, subs, entries = [], [], []
    for idx, (anim, file, count, fps, loop) in enumerate(anims, start=1):
        tex_id = f"{idx}_{anim}"
        ext.append(
            f'[ext_resource type="Texture2D" path="res://player/sprites/{file}.png" id="{tex_id}"]'
        )
        frames = []
        for i in range(count):
            sub_id = f"AtlasTexture_{anim}{i}"
            subs.append(
                f'[sub_resource type="AtlasTexture" id="{sub_id}"]\n'
                f'atlas = ExtResource("{tex_id}")\n'
                f"region = Rect2({i * SIZE}, 0, {SIZE}, {SIZE})"
            )
            frames.append(f'{{"duration": 1.0, "texture": SubResource("{sub_id}")}}')
        entries.append(
            f'{{"frames": [{", ".join(frames)}], "loop": {"true" if loop else "false"}, '
            f'"name": &"{anim}", "speed": {fps:.1f}}}'
        )
    text = (
        '[gd_resource type="SpriteFrames" format=3]\n\n'
        + "\n".join(ext)
        + "\n\n"
        + "\n\n".join(subs)
        + "\n\n[resource]\nanimations = ["
        + ", ".join(entries)
        + "]\n"
    )
    path.write_text(text)


def main() -> None:
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    body, tails = split_layers(Image.open(SRC).convert("RGBA"))

    legs_anims = []
    for name, frames in legs_animations().items():
        save_strip(frames, f"legs_{name}")
        legs_anims.append((name, f"legs_{name}", len(frames), FPS[name], True))
    write_sprite_frames(OUT_DIR / "player_legs_frames.tres", legs_anims)

    torso_anims = []
    for name, frames in torso_locomotion(body, tails).items():
        save_strip(frames, f"torso_{name}")
        torso_anims.append((name, f"torso_{name}", len(frames), FPS[name], True))
    for name, (frames, fps, loop) in torso_attacks(body, tails).items():
        save_strip(frames, f"torso_{name}")
        torso_anims.append((name, f"torso_{name}", len(frames), fps, loop))
    write_sprite_frames(OUT_DIR / "player_torso_frames.tres", torso_anims)


if __name__ == "__main__":
    main()
