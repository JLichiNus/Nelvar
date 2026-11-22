"""Генератор спрайтов игрока — элементаль ветра «Вихрь» (концепт A).

Торс с головой и гребнем-потоками, парящие кулаки, вместо ног — смерч.
Формы собираются из примитивов -> объём (ламберт по размытой маске) ->
5-тоновая палитра -> контур, как в концепте.

Спрайт из двух слоёв, чтобы атаки не останавливали смерч:
  * vortex — смерч и кольца ветра: idle / walk / run / fly и *_back
             (движение спиной вперёд: хвост смерча тянется в другую сторону);
  * torso  — торс, голова, гребень, кулаки: idle / walk / run / fly +
             атаки (attack_primary — ЛКМ, attack_wave — ПКМ,
             attack_compression — R).
Кадров локомоции у всех анимаций поровну — игрок синхронизирует слои.
Свет и контур каждого слоя считаются по объединению с неподвижной частью
другого слоя, поэтому на стыке торса и смерча нет шва.

Персонаж смотрит вправо, ось тела — центр кадра (CX): вокруг неё
отражается спрайт. Земля — строка GROUND.

Запуск из корня проекта:
    python3 tools/gen_player_sprites.py
"""

import math
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "player" / "sprites"
W, H = 48, 40
CX = 24
GROUND = 35
LOCO_FRAMES = 8

# Приглушённое небо, чтобы не спорить с оливковым миром.
RAMP = [(70, 104, 150), (112, 152, 196), (162, 198, 226), (214, 236, 246), (246, 252, 254)]
OUTLINE = (36, 50, 84)

FPS = {"idle": 8.0, "walk": 12.0, "run": 16.0, "fly": 16.0}
TAU = math.tau


# ------------------------------------------------------------ геометрия


def sample(pts, t):
    """Катмулл-Ром по точкам."""
    n = len(pts) - 1
    f = min(max(t, 0.0), 1.0) * n
    i = min(int(f), n - 1)
    u = f - i
    p0 = pts[max(i - 1, 0)]
    p1, p2 = pts[i], pts[i + 1]
    p3 = pts[min(i + 2, n)]

    def cr(a, b, c, d):
        return 0.5 * ((2 * b) + (-a + c) * u + (2 * a - 5 * b + 4 * c - d) * u * u
                      + (-a + 3 * b - 3 * c + d) * u ** 3)

    return cr(p0[0], p1[0], p2[0], p3[0]), cr(p0[1], p1[1], p2[1], p3[1])


def blur(a, r):
    k = np.exp(-np.arange(-2 * r, 2 * r + 1) ** 2 / (2 * r * r))
    k /= k.sum()
    p = np.pad(a, 2 * r, mode="constant")
    p = np.apply_along_axis(lambda v: np.convolve(v, k, "same"), 0, p)
    p = np.apply_along_axis(lambda v: np.convolve(v, k, "same"), 1, p)
    return p[2 * r:-2 * r, 2 * r:-2 * r]


_YS, _XS = np.mgrid[0:H, 0:W]
_XS = _XS + 0.5
_YS = _YS + 0.5


class Layer:
    """Маска тела слоя + штрихи ветра поверх/вокруг."""

    def __init__(self):
        self.mask = np.zeros((H, W), bool)
        self.back = np.zeros((H, W), bool)   # дальний план (на тон темнее)
        self.over = {}                       # (x, y) -> тон поверх тела
        self.wisps = {}                      # (x, y) -> тон, без контура

    def _add(self, m, back):
        self.mask |= m
        if back:
            self.back |= m

    def circle(self, cx, cy, r, back=False):
        r = max(r, 0.5)
        self._add((_XS - cx) ** 2 + (_YS - cy) ** 2 <= r * r, back)

    def ellipse(self, cx, cy, rx, ry, back=False):
        self._add(((_XS - cx) / rx) ** 2 + ((_YS - cy) / ry) ** 2 <= 1, back)

    def stroke(self, pts, r0, r1, back=False, steps=60):
        """Капсульный мазок по кривой с радиусом r0 -> r1."""
        for i in range(steps + 1):
            t = i / steps
            x, y = sample(pts, t)
            self.circle(x, y, r0 + (r1 - r0) * t, back)

    def _pixel(self, x, y):
        xi, yi = int(math.floor(x)), int(math.floor(y))
        if 0 <= xi < W and 0 <= yi < H:
            return xi, yi
        return None

    def wisp(self, pts, tone=3, steps=40, gap=0, fade=True):
        """Штрих ветра вне тела (на теле не рисуется)."""
        for i in range(steps + 1):
            t = i / steps
            if gap and int(t * 10) % gap == gap - 1:
                continue
            p = self._pixel(*sample(pts, t))
            if p:
                self.wisps[p] = tone if (t < 0.7 or not fade) else tone - 1

    def dot(self, x, y, tone=3):
        p = self._pixel(x, y)
        if p:
            self.wisps[p] = tone

    def streak(self, pts, tone=3, steps=40):
        """Светлая полоса поверх тела (только внутри маски)."""
        for i in range(steps + 1):
            p = self._pixel(*sample(pts, i / steps))
            if p and self.mask[p[1], p[0]]:
                self.over[p] = tone if i / steps < 0.75 else tone - 1

    def over_px(self, x, y, tone):
        p = self._pixel(x, y)
        if p and self.mask[p[1], p[0]]:
            self.over[p] = tone


def render(layer: Layer, static: np.ndarray, light=(-0.55, -0.75, 0.55)) -> Image.Image:
    """Рисует слой; static — маска неподвижной части соседнего слоя.

    Объём и контур считаются по объединению, а выводятся только пиксели
    своего слоя — так соседние слои стыкуются без контура на шве.
    """
    own = layer.mask
    union = own | static
    hgt = blur(blur(union.astype(float), 3), 2)
    gy, gx = np.gradient(hgt)
    nx, ny, nz = -gx * 3, -gy * 3, np.full_like(gx, 0.7)
    n = np.sqrt(nx * nx + ny * ny + nz * nz)
    lv = np.array(light) / np.linalg.norm(light)
    val = (nx * lv[0] + ny * lv[1] + nz * lv[2]) / n

    def inside(x, y):
        return 0 <= x < W and 0 <= y < H and union[y, x]

    img = Image.new("RGBA", (W, H))
    px = img.load()
    for y in range(H):
        for x in range(W):
            if not own[y, x]:
                continue
            v = val[y, x]
            tone = 1 if v < 0.55 else 2 if v < 0.85 else 3
            if not inside(x, y + 1) or not inside(x + 1, y + 1):
                tone = max(0, tone - 1)
            if not inside(x, y - 1) or not inside(x - 1, y - 1):
                tone = min(4, tone + 1)
            if layer.back[y, x]:
                tone = max(0, tone - 1)
            px[x, y] = RAMP[tone] + (255,)
    for (x, y), tone in layer.wisps.items():
        if not union[y, x]:
            px[x, y] = RAMP[tone] + (255,)
    for (x, y), tone in layer.over.items():
        px[x, y] = RAMP[tone] + (255,)
    for y in range(H):
        for x in range(W):
            if union[y, x]:
                continue
            if any(0 <= x + dx < W and 0 <= y + dy < H and own[y + dy, x + dx]
                   for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                px[x, y] = OUTLINE + (255,)
    return img


# ------------------------------------------------------------- смерч

NECK = (CX, 21.0)
# Ось смерча в покое относительно шеи: хвост завивается назад (влево).
TAIL = [(0.0, 0.0), (-0.4, 4.0), (-2.0, 8.0), (-4.5, 11.2), (-7.5, 12.6)]
TAIL_R0, TAIL_R1 = 4.2, 0.7


def tornado_axis(sweep, length, sway, phase, side):
    """Точки оси смерча. side=-1 — хвост назад, +1 — вперёд (ход спиной)."""
    pts = []
    for i, (x, y) in enumerate(TAIL):
        k = i / (len(TAIL) - 1)
        wob = sway * k * math.sin(TAU * phase + i * 1.1)
        pts.append((NECK[0] - side * x * sweep + wob,
                    NECK[1] + y * length - abs(x) * (sweep - 1) * 0.18 * k))
    return pts


def neck_mask() -> np.ndarray:
    """Верх смерча — общий для всех кадров, прячется под торсом."""
    lay = Layer()
    lay.circle(NECK[0], NECK[1], TAIL_R0)
    lay.circle(NECK[0] - 0.1, NECK[1] + 1.5, TAIL_R0 - 0.3)
    return lay.mask


def spiral(lay, axis, r0, r1, turns, phase, strands=1):
    """Полосы, огибающие смерч: видна только передняя половина витка."""
    steps = 90
    for s in range(strands):
        off = s / strands
        for i in range(steps + 1):
            t = 0.12 + 0.83 * i / steps
            x, y = sample(axis, t)
            x2, y2 = sample(axis, min(t + 0.02, 1.0))
            tx, ty = x2 - x, y2 - y
            ln = math.hypot(tx, ty) or 1.0
            nx, ny = -ty / ln, tx / ln
            th = TAU * (turns * t - phase - off)
            if math.cos(th) <= 0.35:
                continue
            r = (r0 + (r1 - r0) * t) * 0.8
            lay.over_px(x + nx * r * math.sin(th), y + ny * r * math.sin(th),
                        4 if t < 0.3 else 3)


def ring(lay, cx, cy, rx, ry, phase, span=1.25, segs=2, front_tone=4, back_tone=2):
    """Вращающиеся дуги кольца ветра вокруг смерча."""
    for s in range(segs):
        a0 = TAU * (phase + s / segs)
        for i in range(24):
            a = a0 + span * i / 23
            x, y = cx + rx * math.cos(a), cy + ry * math.sin(a)
            front = math.sin(a) > 0
            tone = front_tone if front else back_tone
            if i > 17:
                tone -= 1
            if front:
                lay.over_px(x, y, tone)
            lay.dot(x, y, tone)


def speed_lines(lay, phase, rows, x_from, length, tone=3):
    """Горизонтальные штрихи позади тела, бегущие назад."""
    for j, (y, shift) in enumerate(rows):
        x = x_from - ((phase + shift) % 1.0) * 10
        lay.wisp([(x, y), (x - length, y)], tone, steps=16)


VORTEX = {
    #        sweep length sway turns  thick
    "idle": (1.0, 1.0, 0.9, 2.0, 1.0),
    "walk": (1.45, 0.96, 0.7, 2.2, 1.0),
    "run": (1.95, 0.88, 0.6, 2.4, 0.95),
    "fly": (2.35, 0.62, 0.5, 2.0, 0.8),
}


def vortex_frame(kind, i, back=False):
    sweep, length, sway, turns, thick = VORTEX[kind]
    side = 1 if back else -1
    p = i / LOCO_FRAMES
    lay = Layer()
    axis = tornado_axis(sweep, length, sway, p, side)
    r0, r1 = TAIL_R0 * thick, TAIL_R1
    lay.circle(NECK[0], NECK[1], TAIL_R0)
    lay.stroke(axis, r0, r1)
    # Полосы закручиваются быстрее на бегу.
    spin = {"idle": 2, "walk": 2, "run": 3, "fly": 3}[kind]
    spiral(lay, axis, r0, r1, turns, p * spin)
    tip = axis[-1]
    trail = side  # куда тянется хвост: -1 влево, +1 вправо

    if kind == "idle":
        ring(lay, CX + 0.5, 28.5, 11.5, 3.6, p)
        ring(lay, tip[0] + 0.5, GROUND, 5.0, 1.1, p * 2, span=1.6, front_tone=3, back_tone=2)
    elif kind == "walk":
        ring(lay, CX + 1.5 * trail, 28.0, 11.0, 3.4, p * 1.5)
        ring(lay, tip[0], GROUND, 5.0, 1.1, p * 2, span=1.6, front_tone=3, back_tone=2)
    elif kind == "run":
        ring(lay, CX + 2.5 * trail, 27.5, 10.5, 3.0, p * 2, span=1.0)
        # пыль от кончика смерча
        for k in range(3):
            q = (p * 2 + k / 3) % 1.0
            lay.dot(tip[0] + trail * (2 + q * 9), GROUND - q * 2.5, 3 if q < 0.5 else 2)
    else:  # fly — высоко над землёй, только встречный ветер
        ring(lay, CX + 2.0 * trail, 25.0, 9.0, 2.6, p * 2, span=1.0)
        for k in range(2):
            q = (p * 2 + k / 2) % 1.0
            x = tip[0] + trail * (1 + q * 8)
            lay.wisp([(x, tip[1] - 1 + k * 2), (x + trail * 3, tip[1] - 1 + k * 2)], 3, steps=8)

    return lay


# --------------------------------------------------------------- торс

TORSO_C = (CX, 17.6)
HEAD_C = (CX + 2.6, 11.4)
NEAR_FIST = (CX + 10.6, 18.8)
FAR_FIST = (CX - 10.6, 19.6)


def torso_core_mask() -> np.ndarray:
    """Торс и голова в покое — для расчёта света смерча."""
    lay = Layer()
    lay.ellipse(*TORSO_C, 5.8, 4.6)
    lay.ellipse(*HEAD_C, 3.8, 3.6)
    return lay.mask


def torso_frame(near, far, *, body_dx=0, head_dx=0, head_dy=0, crest_len=1.0,
                crest_lift=0.0, flutter=0.0, flutter_amp=0.5, near_r=2.3, far_r=2.0,
                links=True, back_wisp=True, effects=None):
    lay = Layer()
    tx, ty = TORSO_C[0] + body_dx, TORSO_C[1]
    hx, hy = HEAD_C[0] + head_dx, HEAD_C[1] + head_dy

    # дальний кулак — позади всего, на тон темнее
    lay.circle(far[0], far[1], far_r, back=True)
    lay.ellipse(tx, ty, 5.8, 4.6)
    lay.ellipse(hx, hy, 3.8, 3.6)

    # Гребень-потоки: корень на затылке, хвосты треплет ветер.
    def crest(base, r0, r1):
        root = base[0]
        pts = [root]
        for i, (x, y) in enumerate(base[1:], start=1):
            k = i / (len(base) - 1)
            fy = flutter_amp * k * math.sin(TAU * flutter + i * 1.3)
            pts.append((root[0] + (x - root[0]) * crest_len,
                        y - crest_lift * k + fy))
        lay.stroke([(x + head_dx, y + head_dy) for x, y in pts], r0, r1)

    crest([(CX + 2.5, 8.2), (CX - 1.5, 6.6), (CX - 5.5, 7.0), (CX - 8.5, 9.2)], 2.3, 0.5)
    crest([(CX, 10.2), (CX - 3.5, 10.6), (CX - 6.2, 12.6)], 1.5, 0.4)

    lay.circle(near[0], near[1], near_r)

    # блик-поток по груди
    lay.streak([(tx - 4, 16.0), (tx - 0.5, 17.2), (tx + 3.5, 16.2)], 4)

    if links:
        # связь плечо-кулак — ветер, без контура
        sx, sy = tx + 6.0, 16.2
        if near[0] - near_r - sx > 1.5:
            mx = (sx + near[0] - near_r) / 2
            lay.wisp([(sx, sy), (mx, (sy + near[1]) / 2 - 0.6), (near[0] - near_r - 0.6, near[1] - 2.0)], 3, steps=20)
        fx, fy = tx - 6.2, 16.4
        if fx - (far[0] + far_r) > 1.5:
            lay.wisp([(fx, fy), ((fx + far[0]) / 2, fy + 0.2), (far[0] + far_r + 0.4, far[1] - 2.0)], 2, steps=20)
    if back_wisp:
        lay.wisp([(CX - 10.5 + head_dx, 13.5), (CX - 13 + head_dx, 14.0)], 3, steps=10)
    if effects:
        effects(lay)
    return lay


def fist_offsets(p, amp, phase_shift=0.0):
    return round(amp * math.sin(TAU * p + phase_shift))


def torso_locomotion():
    anims = {}
    frames = []
    for i in range(LOCO_FRAMES):
        p = i / LOCO_FRAMES
        frames.append(torso_frame(
            (NEAR_FIST[0], NEAR_FIST[1] + fist_offsets(p, 1.0)),
            (FAR_FIST[0], FAR_FIST[1] + fist_offsets(p, 1.0, 2.2)),
            flutter=p, flutter_amp=0.6))
    anims["idle"] = frames

    frames = []
    for i in range(LOCO_FRAMES):
        p = i / LOCO_FRAMES
        swing = fist_offsets(p, 1.5)
        frames.append(torso_frame(
            (NEAR_FIST[0] - 0.5 + swing, NEAR_FIST[1] + fist_offsets(p * 2, 0.6)),
            (FAR_FIST[0] - swing, FAR_FIST[1] + fist_offsets(p * 2, 0.6, 1.5)),
            head_dx=1, crest_len=1.15, crest_lift=0.3, flutter=p * 2, flutter_amp=0.6))
    anims["walk"] = frames

    frames = []
    for i in range(LOCO_FRAMES):
        p = i / LOCO_FRAMES

        def lines(lay, p=p):
            speed_lines(lay, p * 2, [(5.5, 0.0), (15.0, 0.45)], CX - 10, 3)

        swing = fist_offsets(p, 1.0)
        frames.append(torso_frame(
            (NEAR_FIST[0] - 0.5 + swing, NEAR_FIST[1] + 2),
            (FAR_FIST[0] - 1 - swing, FAR_FIST[1] - 0.5),
            body_dx=1, head_dx=2, crest_len=1.35, crest_lift=0.8,
            flutter=p * 2, flutter_amp=0.7, back_wisp=False, effects=lines))
    anims["run"] = frames

    frames = []
    for i in range(LOCO_FRAMES):
        p = i / LOCO_FRAMES

        def lines(lay, p=p):
            speed_lines(lay, p * 2, [(4.5, 0.0), (13.5, 0.3), (22.0, 0.65)], CX - 10, 4)

        frames.append(torso_frame(
            (NEAR_FIST[0] - 1, NEAR_FIST[1] + 2.5 + fist_offsets(p, 0.6)),
            (FAR_FIST[0] - 2, FAR_FIST[1] - 1 + fist_offsets(p, 0.6, 2)),
            body_dx=1, head_dx=2, crest_len=1.45, crest_lift=1.2,
            flutter=p * 2, flutter_amp=0.5, back_wisp=False, effects=lines))
    anims["fly"] = frames
    return anims


# --------------------------------------------------------------- атаки


def crescent(lay, cx, cy, r, half_angle, tone, sparse=False):
    """Дуга ветра, выпуклая вперёд (вправо)."""
    for i in range(40):
        a = -half_angle + 2 * half_angle * i / 39
        if sparse and i % 4 == 3:
            continue
        t = abs(a) / half_angle
        lay.dot(cx + r * math.cos(a), cy + r * math.sin(a), tone if t < 0.6 else tone - 1)


def puff(lay, pts, tone=3):
    for x, y in pts:
        lay.dot(x, y, tone)


def torso_attacks():
    nf, ff = NEAR_FIST, FAR_FIST
    attacks = {}

    # ЛКМ — короткий тычок ближним кулаком, ветер срывается с костяшек.
    attacks["attack_primary"] = ([
        torso_frame((nf[0] - 2.5, nf[1] - 0.8), (ff[0] - 1, ff[1]), flutter=0.0,
                    effects=lambda l: puff(l, [(nf[0] - 6, nf[1] - 3), (nf[0] - 7, nf[1] - 3)], 2)),
        torso_frame((nf[0] + 5, nf[1] - 1), (ff[0] - 1.5, ff[1] + 0.5), body_dx=1, head_dx=1,
                    crest_len=1.15, flutter=0.3,
                    effects=lambda l: (crescent(l, nf[0] + 5.5, nf[1] - 1, 3.6, 1.0, 4),
                                       puff(l, [(nf[0] + 10.5, nf[1] - 1)], 4))),
        torso_frame((nf[0] + 2, nf[1] - 0.5), (ff[0] - 1, ff[1]), head_dx=1, flutter=0.6,
                    effects=lambda l: puff(l, [(nf[0] + 7, nf[1] - 3), (nf[0] + 9, nf[1]),
                                               (nf[0] + 7, nf[1] + 2)], 3)),
    ], 15.0, False)

    # ПКМ — широкий мах ближним кулаком сверху вниз-вперёд, выпуская волну.
    def trail(points, tone=3):
        return lambda l: l.wisp(points, tone, steps=30)

    attacks["attack_wave"] = ([
        torso_frame((nf[0] - 1.8, 8.6), (ff[0] - 1.5, ff[1] - 1), body_dx=0, head_dx=-1,
                    flutter=0.0, links=False,
                    effects=lambda l: puff(l, [(nf[0] - 4, 5), (nf[0] - 2, 4)], 3)),
        torso_frame((nf[0] + 3, 11.0), (ff[0] - 2, ff[1] - 0.5), flutter=0.2, links=False,
                    effects=trail([(nf[0] - 3, 5.5), (nf[0] + 0.5, 6.0), (nf[0] + 3.5, 7.8)], 4)),
        torso_frame((nf[0] + 5.5, 17.0), (ff[0] - 2.5, ff[1]), body_dx=1, head_dx=1,
                    crest_len=1.3, crest_lift=0.6, flutter=0.4,
                    effects=lambda l: (crescent(l, nf[0] + 2, 17, 7.5, 1.05, 4),
                                       l.wisp([(nf[0] + 2, 7.5), (nf[0] + 6, 10.5), (nf[0] + 7.6, 14)], 3, steps=20))),
        torso_frame((nf[0] + 5, 18.5), (ff[0] - 2, ff[1]), body_dx=1, head_dx=1,
                    crest_len=1.25, crest_lift=0.5, flutter=0.6,
                    effects=lambda l: crescent(l, nf[0] + 3, 17.5, 9.5, 1.0, 3, sparse=True)),
        torso_frame((nf[0] + 2.5, 18.8), (ff[0] - 1, ff[1]), head_dx=1, flutter=0.8,
                    effects=lambda l: puff(l, [(nf[0] + 12, 12), (nf[0] + 13, 18), (nf[0] + 12, 24)], 2)),
        torso_frame((nf[0] + 1, 18.8), ff, flutter=1.0),
    ], 18.0, False)

    # R — кулаки взмывают над головой, собирают вихрь и сжимают его вперёд.
    def swirl_above(lay, cx, cy, rx, ry, phase, tone=3):
        ring(lay, cx, cy, rx, ry, phase, span=1.6, front_tone=tone, back_tone=tone - 1)

    attacks["attack_compression"] = ([
        torso_frame((nf[0] - 1, 14.5), (ff[0] + 0.5, 15.0), flutter=0.0, links=False),
        torso_frame((nf[0] - 1.2, 8.0), (ff[0] - 0.9, 11.5), flutter=0.15,
                    crest_lift=-0.4, links=False, back_wisp=False,
                    effects=lambda l: swirl_above(l, CX + 1, 6.5, 9.0, 2.0, 0.1)),
        torso_frame((nf[0] - 2.1, 4.5), (ff[0] + 1.6, 4.5), flutter=0.3, links=False,
                    back_wisp=False, effects=lambda l: swirl_above(l, CX + 0.5, 3.0, 6.5, 1.4, 0.45, 4)),
        torso_frame((nf[0] + 2.4, 10.0), (nf[0] - 0.6, 6.4), body_dx=1, head_dx=1, flutter=0.5,
                    crest_len=1.2, links=False, back_wisp=False,
                    effects=lambda l: l.wisp([(CX - 1, 2.0), (CX + 5, 1.5), (nf[0] + 3, 4.5)], 3, steps=24)),
        torso_frame((nf[0] + 4.8, 16.0), (nf[0] + 2.4, 13.5), near_r=2.1, far_r=1.9, body_dx=1,
                    head_dx=1, crest_len=1.3, crest_lift=0.6, flutter=0.7,
                    effects=lambda l: (crescent(l, nf[0] + 8.5, 15.0, 2.6, 2.4, 4),
                                       puff(l, [(nf[0] + 12.5, 11), (nf[0] + 12.5, 19)], 3))),
        torso_frame((nf[0] + 4.5, 16.2), (nf[0] + 2.2, 13.8), near_r=2.1, far_r=1.9, body_dx=1,
                    head_dx=1, crest_len=1.2, crest_lift=0.4, flutter=0.85,
                    effects=lambda l: puff(l, [(nf[0] + 9, 15), (nf[0] + 10, 13), (nf[0] + 10, 17),
                                               (nf[0] + 11.5, 15)], 4)),
        torso_frame((nf[0] + 1.5, 18.5), ff, head_dx=0, flutter=1.0),
    ], 14.0, False)
    return attacks


# --------------------------------------------------------------- вывод


def save_strip(frames, name: str) -> None:
    strip = Image.new("RGBA", (W * len(frames), H))
    for i, f in enumerate(frames):
        strip.paste(f, (i * W, 0))
    strip.save(OUT_DIR / f"{name}.png")


def write_sprite_frames(path: Path, anims) -> None:
    """SpriteFrames-ресурс: каждая полоса режется на AtlasTexture W x H.

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
                f"region = Rect2({i * W}, 0, {W}, {H})"
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
    torso_static = torso_core_mask()
    neck_static = neck_mask()

    vortex_anims = []
    for kind in ("idle", "walk", "run", "fly"):
        for back in (False, True):
            if kind == "idle" and back:
                continue
            name = f"{kind}_back" if back else kind
            frames = [render(vortex_frame(kind, i, back), torso_static)
                      for i in range(LOCO_FRAMES)]
            save_strip(frames, f"vortex_{name}")
            vortex_anims.append((name, f"vortex_{name}", len(frames), FPS[kind], True))
    write_sprite_frames(OUT_DIR / "player_vortex_frames.tres", vortex_anims)

    torso_anims = []
    for name, layers in torso_locomotion().items():
        frames = [render(lay, neck_static) for lay in layers]
        save_strip(frames, f"torso_{name}")
        torso_anims.append((name, f"torso_{name}", len(frames), FPS[name], True))
    for name, (layers, fps, loop) in torso_attacks().items():
        frames = [render(lay, neck_static) for lay in layers]
        save_strip(frames, f"torso_{name}")
        torso_anims.append((name, f"torso_{name}", len(frames), fps, loop))
    write_sprite_frames(OUT_DIR / "player_torso_frames.tres", torso_anims)


if __name__ == "__main__":
    main()
