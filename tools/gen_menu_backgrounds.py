"""Генератор фонов-заглушек для главного меню.

Рисует одно и то же место в четырёх реальностях:
  * earth — цветущая поляна;
  * ice   — снег и лёд, прохладно-белая гамма;
  * fire  — вулканическая пустошь с лавой;
  * air   — то же место на облаках: островки парят над облачным морем.
Статуя-валун, деревья, пруд и тропа стоят на одних и тех же позициях.

Для каждой реальности сохраняются два файла (480x270):
  bg_<стихия>.png     — сама картинка;
  bg_<стихия>_fx.png  — маска эффектов для шейдера меню:
                         R — блики (вода, лёд, блестящий снег),
                         G — пульсирующее свечение (лава, угли),
                         B — покачивание (листва, трава, облака).
Настоящий арт можно положить по тем же путям; маску тогда тоже стоит
нарисовать (или залить чёрным — эффекты просто отключатся).
Точки «дыхания» в ui/main_menu/elements/*.tres рассчитаны на позиции
объектов ниже (статуя, большое дерево справа, пруд, дальнее дерево).

Левая треть кадра закрыта кнопками меню, поэтому главное — справа.

Запуск из корня проекта:
    python3 tools/gen_menu_backgrounds.py
"""

import math
import random
from pathlib import Path

from PIL import Image, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
OUT_DIR = ROOT / "assets" / "textures" / "menu"
W, H = 480, 270

BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]

NOFX = (0, 0, 0)
SHIMMER = (255, 0, 0)

# --- Общая компоновка: одно место во всех реальностях -----------------------
SUN = (404, 46)
STATUE = (332, 202)
POND = (222, 236, 30, 9)
TREES = [  # x, основание y, масштаб
    (30, 214, 1.1),
    (86, 204, 1.25),
    (254, 190, 0.7),
    (426, 208, 1.35),
    (470, 230, 0.95),
]
BUSHES = [(196, 202, 1.0), (288, 214, 0.9), (392, 236, 1.1), (140, 228, 1.0)]
PEBBLES = [(262, 252), (372, 258), (176, 260), (452, 252), (300, 236)]
AVOID = [  # эллипсы, где не растёт мелочь
    (POND[0], POND[1], POND[2] + 6, POND[3] + 5),
    (STATUE[0], STATUE[1] - 14, 40, 22),
]

# Свет падает справа сверху (от солнца).
_L = (0.42, -0.58, 0.70)
_LN = math.sqrt(sum(v * v for v in _L))
LIGHT = tuple(v / _LN for v in _L)


# --- Утилиты ----------------------------------------------------------------
def clamp(v, lo=0.0, hi=1.0):
    return lo if v < lo else hi if v > hi else v


def mix(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def mul(c, k):
    return tuple(int(clamp(c[i] * k, 0, 255)) for i in range(3))


def dither(t, x, y):
    return t * 16 > BAYER[y & 3][x & 3] + 0.5


def ramp(cols, t, x, y):
    """Цвет из палитры (тёмный → светлый) с упорядоченным дизерингом."""
    t = clamp(t, 0.0, 0.9999) * (len(cols) - 1)
    i = int(t)
    if i >= len(cols) - 1:
        return cols[-1]
    return cols[i + 1] if dither(t - i, x, y) else cols[i]


def _hash(ix, iy, seed):
    n = (ix * 374761393 + iy * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    n = ((n ^ (n >> 13)) * 1274126177) & 0xFFFFFFFF
    return ((n ^ (n >> 16)) & 0xFFFF) / 65535.0


def vnoise(x, y, seed=0):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    sx, sy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
    a, b = _hash(ix, iy, seed), _hash(ix + 1, iy, seed)
    c, d = _hash(ix, iy + 1, seed), _hash(ix + 1, iy + 1, seed)
    return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy


def fbm(x, y, seed=0, octaves=4):
    v, amp, f, total = 0.0, 0.5, 1.0, 0.0
    for o in range(octaves):
        v += amp * vnoise(x * f, y * f, seed + o * 17)
        total += amp
        amp *= 0.5
        f *= 2.0
    return v / total


def ridged(x, seed):
    return 1.0 - abs(2.0 * fbm(x, 0.5, seed, 3) - 1.0)


def far_ridge(x):
    return 146 - 44 * ridged(x / 95.0, 3) ** 1.6 - 12 * ridged(x / 31.0, 8)


def mid_ridge(x):
    return 174 - 14 * fbm(x / 70.0, 4.2, 5) - 3 * vnoise(x / 9.0, 1.0, 6)


def ground_top(x):
    return 188 - 6 * fbm(x / 55.0, 9.1, 9)


def avoided(x, y, pad=0):
    for cx, cy, rx, ry in AVOID:
        if ((x - cx) / (rx + pad)) ** 2 + ((y - cy) / (ry + pad)) ** 2 < 1:
            return True
    return False


def path_center(y):
    """Тропа от нижнего края к подножию статуи."""
    t = clamp((y - 206) / (H - 206))
    return 322 - t * 44 + 7 * math.sin(t * 5.0), 1.5 + t * 9.0


class Canvas:
    def __init__(self):
        self.img = Image.new("RGB", (W, H))
        self.px = self.img.load()
        self.fx = Image.new("RGB", (W, H))
        self.fpx = self.fx.load()

    def put(self, x, y, c, fx=NOFX):
        x, y = int(x), int(y)
        if 0 <= x < W and 0 <= y < H:
            self.px[x, y] = c
            self.fpx[x, y] = fx

    def get(self, x, y):
        x, y = int(x), int(y)
        if 0 <= x < W and 0 <= y < H:
            return self.px[x, y]
        return (0, 0, 0)

    def tint(self, x, y, k, color=None, amount=0.0):
        x, y = int(x), int(y)
        if 0 <= x < W and 0 <= y < H:
            c = mul(self.px[x, y], k)
            if color is not None:
                c = mix(c, color, amount)
            self.px[x, y] = c

    def save(self, name):
        self.img.save(OUT_DIR / f"bg_{name}.png")
        # Покачивание расширяем на пару пикселей, чтобы край листвы
        # двигался целиком, а не «съедался».
        r, g, b = self.fx.split()
        b = b.filter(ImageFilter.MaxFilter(5))
        Image.merge("RGB", (r, g, b)).save(OUT_DIR / f"bg_{name}_fx.png")


# --- Примитивы --------------------------------------------------------------
def blob(cv, cx, cy, rx, ry, cols, seed=0, wobble=0.12, outline=None, fx=NOFX,
         flat=None, tex=0.10, bias=0.0, outline_t=0.6):
    """Объёмная «капля» с освещением сферы и неровным краем."""
    pts = {}
    pad = 1 + wobble
    for y in range(int(cy - ry * pad) - 1, int(cy + ry * pad) + 2):
        for x in range(int(cx - rx * pad) - 1, int(cx + rx * pad) + 2):
            dx, dy = (x + 0.5 - cx) / rx, (y + 0.5 - cy) / ry
            if flat is not None and dy > flat:
                continue
            d = math.hypot(dx, dy)
            edge = 1.0
            if d > 0:
                edge += wobble * (vnoise(dx / d * 1.7 + seed * 3.7, dy / d * 1.7 + seed * 1.3, 7) * 2 - 1)
            if d <= edge:
                pts[(x, y)] = (dx / edge, dy / edge)
    for (x, y), (dx, dy) in pts.items():
        nz = math.sqrt(max(0.0, 1.0 - min(1.0, dx * dx + dy * dy)))
        lit = dx * LIGHT[0] + dy * LIGHT[1] + nz * LIGHT[2]
        t = 0.5 + 0.5 * lit - 0.15 + bias + (vnoise(x * 0.45, y * 0.45, seed + 5) - 0.5) * tex * 2
        c = ramp(cols, t, x, y)
        if outline is not None and t < outline_t:
            if any((x + ox, y + oy) not in pts for ox, oy in ((1, 0), (-1, 0), (0, 1), (0, -1))):
                c = outline
        cv.put(x, y, c, fx(x, y) if callable(fx) else fx)
    return pts


def shadow(cv, cx, cy, rx, ry, k=0.72, color=None, amount=0.0):
    for y in range(int(cy - ry), int(cy + ry) + 2):
        for x in range(int(cx - rx), int(cx + rx) + 2):
            d = ((x + 0.5 - cx) / rx) ** 2 + ((y + 0.5 - cy) / ry) ** 2
            if d <= 1 and (d < 0.55 or dither(1 - (d - 0.55) / 0.45, x, y)):
                cv.tint(x, y, k, color, amount)


def sky(cv, cols, y_end=H):
    for y in range(y_end):
        t = y / (y_end - 1)
        for x in range(W):
            cv.put(x, y, ramp(cols, t, x, y))


def sun(cv, core, halo, r=13, halo_r=34, rays=False):
    cx, cy = SUN
    for y in range(cy - halo_r - 2, cy + halo_r + 3):
        for x in range(cx - halo_r - 2, cx + halo_r + 3):
            d = math.hypot(x + 0.5 - cx, y + 0.5 - cy)
            if d <= r:
                cv.put(x, y, core if d < r - 2 or (x + y) % 2 else halo)
            elif d <= halo_r:
                t = 1 - (d - r) / (halo_r - r)
                if rays:
                    a = math.atan2(y - cy, x - cx)
                    t *= 0.65 + 0.35 * math.cos(a * 8)
                if dither(t * t * 0.9, x, y):
                    cv.put(x, y, mix(cv.get(x, y), halo, 0.45))


def cumulus(cv, cx, cy, w, h, cols, seed, outline=None, fx=NOFX, flat=0.5, bias=0.0, tex=0.04, lump=9):
    rng = random.Random(seed)
    n = max(3, int(w / lump))
    lumps = []
    for i in range(n):
        t = i / (n - 1)
        bump = math.sin(t * math.pi) ** 0.8
        ry = h * (0.35 + 0.65 * bump) * rng.uniform(0.8, 1.1)
        lumps.append((cx - w / 2 + t * w + rng.uniform(-2, 2), cy - ry * flat, ry * 1.25, ry))
    for k, (lx, ly, rx, ry) in enumerate(sorted(lumps, key=lambda l: l[3])):
        blob(cv, lx, ly, rx, ry, cols, seed=seed * 13 + k, wobble=0.07, outline=outline,
             fx=fx, flat=flat, tex=tex, bias=bias)


def mountains(cv, cols, seed, snow_cols=None, snow_line=None, haze=None, haze_amt=0.0,
              ridge=far_ridge, y_end=H, rim=None, slope_k=0.0):
    for x in range(W):
        top = int(ridge(x))
        slope = (ridge(x + 3) - ridge(x - 3)) / 6.0
        for y in range(top, y_end):
            depth = y - top
            n = fbm(x * 0.07, y * 0.16, seed, 3)
            streak = fbm(x * 0.05, y * 0.3, seed + 3, 2)
            t = 0.55 + clamp(slope * slope_k, -0.3, 0.3) + (n - 0.5) * 0.5 + (streak - 0.5) * 0.15
            t -= depth * 0.004
            c = ramp(cols, t, x, y)
            if snow_cols and snow_line is not None:
                line = snow_line + (vnoise(x * 0.3, 2.0, seed) - 0.5) * 10 + slope * 6
                if y < line:
                    c = ramp(snow_cols, t + 0.15, x, y)
            if rim and depth == 0:
                c = rim
            if haze and haze_amt > 0:
                c = mix(c, haze, clamp(depth / 70.0) * haze_amt)
            cv.put(x, y, c)


def make_peaks(seed, volcano=None):
    rng = random.Random(seed)
    peaks = []
    x = -50
    while x < W + 60:
        peaks.append((x, rng.uniform(96, 134), rng.uniform(0.75, 1.15), rng.uniform(0.75, 1.15)))
        x += rng.uniform(40, 70)
    if volcano is not None:
        peaks.append(volcano)
    return peaks


def peak_height(peaks, x):
    """Верхняя граница хребта и пик, которому принадлежит этот столбец."""
    best, owner = 1e9, None
    for p in peaks:
        px, py, sl, sr = p
        h = py + (px - x) * sl if x < px else py + (x - px) * sr
        if h < best:
            best, owner = h, p
    return best, owner


def peak_range(cv, peaks, cols, seed, snow_cols=None, snow_h=14, haze=None, haze_amt=0.0,
               y_end=H, crater=None):
    """Горы из отдельных пиков: освещённая правая грань, тёмная левая, лощины, снег."""
    for x in range(W):
        top, (px, py, sl, sr) = peak_height(peaks, x)
        if crater and abs(x - crater[0]) < crater[1]:
            top = max(top, py + 3)
        for y in range(int(top), y_end):
            below = y - py
            # Линия хребта от вершины вниз чуть виляет.
            ridge_x = px + (vnoise(y * 0.12, px, seed) - 0.5) * below * 0.5
            lit = x > ridge_x
            # Лощины: радиальные полосы, расходящиеся от вершины.
            gully = vnoise((x - px) / (below + 6.0) * 7.0, px * 0.1, seed + 1)
            t = (0.68 if lit else 0.28) + (gully - 0.5) * 0.35
            t += (vnoise(x * 0.2, y * 0.2, seed + 2) - 0.5) * 0.15 - (y - top) * 0.003
            c = ramp(cols, t, x, y)
            if snow_cols:
                line = py + snow_h * (0.5 + 1.0 * gully) + (vnoise(x * 0.4, 1.0, seed) - 0.5) * 4
                if y < line:
                    c = ramp(snow_cols, t + 0.1, x, y)
            if haze and haze_amt > 0:
                c = mix(c, haze, clamp((y - top) / 60.0) * haze_amt)
            cv.put(x, y, c)


def treeline(cv, ridge, cols, seed, kind="round", caps=None):
    rng = random.Random(seed)
    x = -6
    while x < W + 6:
        base = ridge(x) + 4
        h = rng.randint(7, 13)
        if kind == "pine":
            for k in range(h):
                half = int(k * 0.38) + 1
                for dx in range(-half, half + 1):
                    t = 0.35 + (0.25 if dx > 0 else -0.1)
                    c = ramp(cols, t, x + dx, int(base - h + k))
                    if caps and (k < 2 or (k % 4 == 0 and abs(dx) > half - 2)):
                        c = caps
                    cv.put(x + dx, base - h + k, c)
        elif kind == "dead":
            for k in range(h):
                cv.put(x, base - k, cols[0])
            for b in range(2):
                by = base - rng.randint(h // 3, h - 2)
                d = rng.choice((-1, 1))
                for k in range(3):
                    cv.put(x + d * (k + 1), by - k, cols[0])
        else:
            blob(cv, x, base - h * 0.6, h * 0.55, h * 0.6, cols, seed=int(x) + seed,
                 wobble=0.15, tex=0.15, bias=-0.05)
        x += rng.randint(3, 7)


def ground(cv, cols, seed, patch=0.6, base=0.72, fx=NOFX, top_fn=ground_top):
    for x in range(W):
        top = int(top_fn(x))
        for y in range(top, H):
            depth = (y - top) / (H - top)
            n = fbm(x * 0.035, y * 0.08, seed, 4)
            t = base - depth * 0.42 + (n - 0.5) * patch
            if y == top:
                t += 0.3
            cv.put(x, y, ramp(cols, t, x, y), fx(x, y) if callable(fx) else fx)


def tufts(cv, rng, count, cols, y_min=192, y_max=H, sway=True, avoid=True):
    for _ in range(count):
        x, y = rng.randint(0, W - 1), rng.randint(y_min, y_max)
        if avoid and avoided(x, y, 3):
            continue
        depth = (y - y_min) / max(1, y_max - y_min)
        size = 1 + int(depth * 4)
        fxv = (0, 0, int(80 + 140 * depth)) if sway else NOFX
        for b in (-1, 0, 1):
            hgt = size + rng.randint(0, 1) + (1 if b == 0 else 0)
            for k in range(hgt):
                lean = (b * k) // 3
                c = cols[2] if k == hgt - 1 else cols[1] if k > hgt // 2 else cols[0]
                cv.put(x + b + lean, y - k, c, fxv)


def sprinkle(cv, rng, count, colors, y_min=194, y_max=H - 2, fx=NOFX, size=1):
    for _ in range(count):
        x, y = rng.randint(0, W - 1), rng.randint(y_min, y_max)
        if avoided(x, y, 2):
            continue
        c = rng.choice(colors)
        cv.put(x, y, c, fx)
        if size > 1 and y > 225:
            cv.put(x + 1, y, c, fx)
            cv.put(x, y - 1, mix(c, (255, 255, 255), 0.35), fx)


def path(cv, cols, seed, edge=None, fx=NOFX, stones=None):
    rng = random.Random(seed)
    for y in range(206, H):
        cx, w = path_center(y)
        wob = (vnoise(y * 0.2, 4.0, seed) - 0.5) * 2.5
        for x in range(int(cx - w + wob), int(cx + w + wob) + 1):
            u = abs(x - cx - wob) / max(1.0, w)
            t = 0.6 - u * 0.35 + (vnoise(x * 0.4, y * 0.4, seed) - 0.5) * 0.5
            c = ramp(cols, t, x, y)
            if edge is not None and u > 0.82:
                c = edge
            cv.put(x, y, c, fx)
        if stones and rng.random() < 0.25:
            sx = cx + rng.uniform(-w * 0.7, w * 0.7)
            cv.put(sx, y, stones[0])
            cv.put(sx + 1, y, stones[1])


def pebble(cv, x, y, cols, outline, seed, s=1.0, fx=NOFX):
    shadow(cv, x + 1, y + 1, 4 * s, 1.6 * s, 0.75)
    return blob(cv, x, y - 1.5 * s, 3.5 * s, 2.4 * s, cols, seed=seed, outline=outline,
                flat=0.6, tex=0.1, fx=fx)


def trunk(cv, x0, y0, height, width, cols, outline, seed, fx=NOFX, flare=True):
    for y in range(int(y0 - height), int(y0) + 1):
        f = 1 if flare and y > y0 - 3 else 0
        f += 1 if flare and y == y0 else 0
        left, right = int(x0 - width - f), int(x0 + width + f)
        for x in range(left, right + 1):
            u = (x - left) / max(1, right - left)
            t = 0.15 + u * 0.75 + (vnoise(x * 0.6, y * 0.22, seed) - 0.5) * 0.35
            c = outline if x == left else ramp(cols, t, x, y)
            cv.put(x, y, c, fx)


def sway_fx(y_bottom, height, strength=210):
    def f(x, y):
        k = clamp((y_bottom - y) / max(1.0, height) * 0.8 + 0.3)
        return (0, 0, int(k * strength))
    return f


def canopy(cv, x0, top, s, cols, outline, seed, lumps, sway_bottom, tex=0.22):
    fxf = sway_fx(sway_bottom, 30 * s)
    for k, (dx, dy, rx, ry) in enumerate(sorted(lumps, key=lambda l: -l[1])):
        blob(cv, x0 + dx * s, top + dy * s, rx * s, ry * s, cols, seed=seed + k * 7,
             wobble=0.16, outline=outline, fx=fxf, tex=tex)


ROUND_LUMPS = [(0, -9, 13, 10), (-10, -2, 9, 7), (10, -3, 10, 7), (-5, -16, 8, 6),
               (7, -15, 8, 6), (0, 2, 11, 6), (-13, 3, 6, 5), (13, 3, 6, 5)]
WIND_LUMPS = [(4, -9, 14, 8), (-6, -3, 9, 6), (14, -4, 10, 6), (0, -15, 9, 5),
              (12, -13, 8, 5), (20, -8, 6, 4), (2, 1, 10, 5)]


def statue(cv, cols, outline, seed):
    """Окаменевшее существо, похожее на валун: тело, плечо, голова, закрытый глаз."""
    sx, sy = STATUE
    pts = {}
    pts.update(blob(cv, sx - 16, sy - 20, 13, 11, cols, seed=seed, outline=outline, tex=0.14, bias=-0.06))
    pts.update(blob(cv, sx, sy - 15, 29, 18, cols, seed=seed + 1, outline=outline, tex=0.14, flat=0.85))
    pts.update(blob(cv, sx + 18, sy - 34, 12, 10, cols, seed=seed + 2, outline=outline, tex=0.12))
    # Закрытое веко.
    ex, ey = sx + 20, sy - 34
    for i, dx in enumerate(range(-4, 5)):
        cv.put(ex + dx, ey + (1 if abs(dx) == 4 else 0), outline)
    for dx in (-3, 0, 3):
        cv.put(ex + dx, ey + 1, mix(outline, cols[1], 0.5))
    # Трещины и складки.
    rng = random.Random(seed)
    for _ in range(3):
        x, y = sx + rng.randint(-24, -2), sy - rng.randint(4, 16)
        for k in range(rng.randint(3, 6)):
            if (x, y) in pts:
                cv.put(x, y, outline)
            x += rng.choice((-1, 0, 1))
            y += 1
    return pts


def icicles(cv, pts, rng, ice, fx=SHIMMER, chance=0.35):
    bottoms = {}
    for (x, y) in pts:
        if (x, y + 1) not in pts:
            bottoms[x] = max(bottoms.get(x, -1), y)
    for x, y in bottoms.items():
        if rng.random() < chance:
            n = rng.randint(2, 6)
            for k in range(n):
                cv.put(x, y + 1 + k, ice[2] if k == 0 else ice[1] if k < n - 1 else ice[0], fx)


def cap(cv, pts, cols, seed, depth=0.45, fx=NOFX):
    """Шапка (снег/мох) на верхней части объекта."""
    for (x, y), _ in list(pts.items()):
        if (x, y - 1) in pts:
            above = 0
            yy = y - 1
            while (x, yy) in pts:
                above += 1
                yy -= 1
            limit = 2 + int(vnoise(x * 0.35, 0.0, seed) * 4 * depth * 2)
            if above > limit:
                continue
        t = 0.7 - (0.25 if (x - 1, y) not in pts else 0) + (vnoise(x * 0.5, y * 0.5, seed) - 0.5) * 0.4
        cv.put(x, y, ramp(cols, t, x, y), fx)


def islet(cv, cx, top, w, s, grass, earth, outline, seed, roots, fx_grass=NOFX):
    """Парящий островок: травяная шапка и каменное «корневище» снизу."""
    rng = random.Random(seed)
    depth = int(w * 0.9)
    for y in range(int(top), int(top + depth)):
        k = (y - top) / depth
        half = w * (1 - k ** 0.75) + (vnoise(y * 0.3, seed, 3) - 0.5) * 3
        for x in range(int(cx - half), int(cx + half) + 1):
            u = (x - (cx - half)) / max(1.0, 2 * half)
            t = 0.2 + u * 0.55 - k * 0.25 + (vnoise(x * 0.5, y * 0.25, seed) - 0.5) * 0.35
            c = ramp(earth, t, x, y)
            if x <= int(cx - half) or (y + 1) >= top + depth:
                c = outline
            cv.put(x, y, c)
    for i in range(int(w * 0.6)):
        rx = cx + rng.uniform(-w * 0.7, w * 0.7)
        ry = top + depth * (1 - abs(rx - cx) / w) * 0.85
        for k in range(rng.randint(3, 9)):
            cv.put(rx + (1 if k > 4 and i % 2 else 0), ry + k, roots, (0, 0, 120))
    for y in range(int(top - 3), int(top + 3)):
        for x in range(int(cx - w - 1), int(cx + w + 2)):
            d = ((x - cx) / (w + 1)) ** 2 + ((y - top) / 3.2) ** 2
            if d <= 1:
                t = 0.75 - (y - top + 3) / 8 + (vnoise(x * 0.6, y * 0.6, seed + 1) - 0.5) * 0.4
                cv.put(x, y, ramp(grass, t, x, y), fx_grass)


def cloud_sea(cv, cols, seed, y_start=170, outline=None):
    """Облачное море вместо земли: ряды пухлых облаков, растущих к зрителю."""
    rng = random.Random(seed)
    y = y_start
    row = 0
    while y < H + 30:
        k = (y - y_start) / (H - y_start)
        r = 7 + k * 26
        x = -r + rng.uniform(0, r)
        while x < W + r:
            rr = r * rng.uniform(0.75, 1.2)
            blob(cv, x, y, rr * 1.3, rr * 0.75, cols, seed=seed + row * 31 + int(x),
                 wobble=0.1, flat=0.55, tex=0.05, outline=outline, outline_t=0.3,
                 fx=(0, 0, int(40 + 60 * k)))
            x += rr * rng.uniform(1.3, 1.9)
        y += 5 + k * 13
        row += 1


# --- Реальности -------------------------------------------------------------
def earth():
    cv = Canvas()
    rng = random.Random(1)
    sky(cv, [(70, 128, 196), (96, 156, 214), (134, 188, 228), (180, 216, 234), (220, 236, 232)], 190)
    sun(cv, (255, 250, 222), (255, 240, 186))
    cloud = [(178, 196, 222), (214, 226, 238), (242, 246, 248), (255, 255, 255)]
    for i, (x, y, w, h) in enumerate([(120, 44, 62, 16), (250, 30, 44, 11), (318, 74, 70, 15),
                                      (452, 92, 40, 10), (40, 98, 36, 9)]):
        cumulus(cv, x, y, w, h, cloud, seed=40 + i)
    peak_range(cv, make_peaks(11), [(76, 104, 138), (98, 128, 158), (124, 154, 178), (150, 178, 196)], 11,
               snow_cols=[(176, 196, 214), (214, 226, 236), (244, 248, 250)], snow_h=16,
               haze=(178, 210, 222), haze_amt=0.6)
    mountains(cv, [(56, 104, 82), (70, 124, 88), (88, 144, 94), (112, 162, 100)], 12,
              ridge=mid_ridge, haze=(150, 196, 190), haze_amt=0.25, rim=(140, 186, 110))
    treeline(cv, mid_ridge, [(40, 86, 68), (52, 104, 74), (70, 122, 80)], 13)
    grass = [(52, 108, 60), (68, 130, 66), (88, 152, 72), (112, 172, 80), (146, 194, 96)]
    ground(cv, grass, 14)
    path(cv, [(120, 92, 66), (150, 116, 82), (178, 142, 100), (198, 166, 120)], 15,
         edge=(96, 128, 64), stones=[(110, 104, 96), (168, 160, 146)])
    # Пруд.
    px, py, prx, pry = POND
    shadow(cv, px, py, prx + 4, pry + 3, 0.7)
    water = [(52, 104, 140), (70, 132, 166), (104, 168, 196), (160, 210, 226)]
    for y in range(py - pry, py + pry + 1):
        for x in range(px - prx, px + prx + 1):
            d = ((x - px) / prx) ** 2 + ((y - py) / pry) ** 2
            if d <= 1:
                t = 0.2 + (y - (py - pry)) / (2 * pry) * 0.6 + (vnoise(x * 0.3, y, 21) - 0.5) * 0.3
                c = ramp(water, t, x, y)
                if d > 0.82 and y < py:
                    c = water[0]
                cv.put(x, y, c, SHIMMER)
    for lx, ly in ((px - 14, py + 2), (px + 9, py - 3), (px + 16, py + 4)):
        blob(cv, lx, ly, 3.2, 1.6, [(58, 120, 62), (86, 150, 70), (120, 176, 86)], seed=lx)
        cv.put(lx + 1, ly - 1, (236, 196, 220))
    for k in range(3):
        y = py - 2 + k * 3
        for x in range(px - 8 + k * 5, px - 2 + k * 5):
            cv.put(x, y, (200, 232, 240), SHIMMER)

    trunk_c = [(74, 50, 40), (98, 68, 50), (124, 88, 62), (150, 110, 78)]
    leaves = [(34, 84, 56), (46, 108, 62), (64, 134, 68), (92, 160, 76), (136, 188, 92)]
    outline = (26, 50, 40)
    for i, (tx, ty, s) in enumerate(TREES):
        if ty < STATUE[1]:
            draw_round_tree(cv, tx, ty, s, trunk_c, leaves, outline, 100 + i)
    for i, (bx, by, s) in enumerate(BUSHES):
        draw_bush(cv, bx, by, s, leaves, outline, 200 + i, berries=(214, 72, 84))
    shadow(cv, STATUE[0] + 6, STATUE[1] + 1, 36, 7, 0.68)
    pts = statue(cv, [(84, 88, 92), (112, 114, 112), (142, 142, 132), (170, 168, 150), (196, 192, 170)],
                 (46, 50, 54), 300)
    moss = [(58, 112, 64), (82, 140, 70), (116, 168, 84)]
    cap(cv, pts, moss, 301, depth=0.5)
    sprinkle(cv, random.Random(5), 6, [(240, 214, 96), (244, 244, 236)], y_min=170, y_max=200)
    for i, (x, y) in enumerate(PEBBLES):
        pebble(cv, x, y, [(96, 100, 98), (128, 130, 124), (164, 164, 152)], (60, 64, 64), 400 + i)
    for i, (tx, ty, s) in enumerate(TREES):
        if ty >= STATUE[1]:
            draw_round_tree(cv, tx, ty, s, trunk_c, leaves, outline, 100 + i)
    tufts(cv, rng, 260, [(48, 104, 56), (78, 146, 66), (130, 186, 90)])
    sprinkle(cv, rng, 120, [(238, 222, 96), (244, 244, 238), (222, 120, 160), (150, 170, 236)], size=2)
    foreground_grass(cv, rng, [(30, 70, 46), (44, 92, 52), (62, 116, 58)])
    return cv


def draw_round_tree(cv, x0, y0, s, trunk_c, leaves, outline, seed):
    th = 24 * s
    shadow(cv, x0 + 5 * s, y0 + 1, 15 * s, 3.5 * s, 0.68)
    trunk(cv, x0, y0, th, max(1.5, 2.6 * s), trunk_c, outline, seed)
    canopy(cv, x0, y0 - th, s, leaves, outline, seed, ROUND_LUMPS, y0 - th + 6 * s)


def draw_bush(cv, x0, y0, s, leaves, outline, seed, berries=None, fx=True):
    shadow(cv, x0 + 2, y0 + 1, 11 * s, 2.5 * s, 0.7)
    fxf = (0, 0, 110) if fx else NOFX
    for k, (dx, dy, rx, ry) in enumerate([(-5, -4, 6, 5), (5, -4, 6, 5), (0, -7, 7, 6)]):
        blob(cv, x0 + dx * s, y0 + dy * s, rx * s, ry * s, leaves, seed=seed + k, wobble=0.15,
             outline=outline, flat=0.7, tex=0.2, fx=fxf)
    if berries:
        rng = random.Random(seed)
        for _ in range(5):
            cv.put(x0 + rng.randint(-8, 8) * s, y0 - rng.randint(3, 10) * s, berries, fxf)


def foreground_grass(cv, rng, cols, sway=True):
    """Высокие тёмные травинки у нижнего края — глубина кадра."""
    for _ in range(170):
        x = rng.randint(-4, W + 4)
        if 120 < x < 400 and rng.random() < 0.75:
            continue
        hgt = rng.randint(8, 22)
        lean = rng.uniform(-0.5, 0.5)
        for k in range(hgt):
            y = H - 1 - k
            c = cols[0] if k < hgt * 0.5 else cols[1] if k < hgt - 2 else cols[2]
            fxv = (0, 0, int(80 + 170 * k / hgt)) if sway else NOFX
            cv.put(x + lean * k * k / hgt, y, c, fxv)


def ice():
    cv = Canvas()
    rng = random.Random(1)
    # Прохладно-белое пасмурное небо: почти без синевы.
    sky(cv, [(188, 194, 204), (204, 210, 218), (220, 224, 230), (232, 235, 238), (242, 243, 244)], 190)
    sun(cv, (250, 250, 246), (246, 246, 242), r=12, halo_r=40)
    cloud = [(206, 210, 218), (222, 226, 232), (236, 238, 241), (246, 247, 248)]
    for i, (x, y, w, h) in enumerate([(120, 44, 70, 12), (250, 30, 52, 9), (318, 74, 80, 12),
                                      (452, 92, 44, 8), (40, 98, 40, 7)]):
        cumulus(cv, x, y, w, h, cloud, seed=40 + i)
    peak_range(cv, make_peaks(11), [(122, 126, 136), (150, 154, 164), (178, 182, 190), (206, 209, 214)], 11,
               snow_cols=[(190, 195, 204), (216, 220, 227), (236, 238, 242), (250, 250, 251)], snow_h=34,
               haze=(226, 229, 234), haze_amt=0.55)
    snow = [(176, 182, 194), (198, 204, 214), (218, 222, 230), (236, 238, 242), (250, 251, 252)]
    mountains(cv, [(190, 196, 206), (208, 212, 220), (226, 229, 234), (242, 244, 246)], 12,
              ridge=mid_ridge, haze=(230, 232, 236), haze_amt=0.25, rim=(252, 252, 252))
    treeline(cv, mid_ridge, [(78, 92, 96), (96, 110, 112), (120, 132, 134)], 13, kind="pine",
             caps=(244, 246, 248))
    ground(cv, snow, 14, patch=0.75, base=0.86)
    # Искорки на снегу.
    for _ in range(260):
        x, y = rng.randint(0, W - 1), rng.randint(192, H - 1)
        if not avoided(x, y):
            cv.put(x, y, (255, 255, 255), SHIMMER)
    # Сугробы.
    for i, (x, y, w) in enumerate([(170, 214, 26), (400, 256, 40), (60, 262, 46), (276, 250, 22)]):
        blob(cv, x, y, w, w * 0.22, snow, seed=500 + i, wobble=0.1, flat=0.4, tex=0.06, bias=0.1)
    # Тропа: утоптанный снег со следами.
    path(cv, [(184, 190, 200), (200, 206, 214), (214, 218, 226)], 15, edge=(232, 234, 238))
    for y in range(212, H, 7):
        cx, w = path_center(y)
        for side in (-1, 1):
            fx_, fy = int(cx + side * w * 0.3), y + (2 if side > 0 else 0)
            cv.put(fx_, fy, (164, 170, 182))
            cv.put(fx_, fy + 1, (176, 182, 194))
    # Замёрзший пруд.
    px, py, prx, pry = POND
    shadow(cv, px, py + 1, prx + 4, pry + 3, 0.88)
    icec = [(170, 188, 194), (196, 212, 216), (218, 230, 232), (238, 245, 246)]
    for y in range(py - pry, py + pry + 1):
        for x in range(px - prx, px + prx + 1):
            d = ((x - px) / prx) ** 2 + ((y - py) / pry) ** 2
            if d <= 1:
                t = 0.35 + (x - px) / prx * 0.25 - (y - py) / pry * 0.1 + (vnoise(x * 0.2, y * 0.6, 21) - 0.5) * 0.4
                cv.put(x, y, ramp(icec, t, x, y), SHIMMER)
    crack_rng = random.Random(22)
    for _ in range(4):
        x, y = px + crack_rng.randint(-20, 20), py + crack_rng.randint(-5, 5)
        for k in range(crack_rng.randint(5, 12)):
            if ((x - px) / prx) ** 2 + ((y - py) / pry) ** 2 < 0.9:
                cv.put(x, y, (150, 166, 174), SHIMMER)
            x += crack_rng.choice((-1, 1))
            y += crack_rng.choice((-1, 0, 0, 1))
    trunk_c = [(56, 50, 52), (74, 66, 66), (94, 84, 82)]
    needles = [(44, 60, 60), (58, 76, 74), (76, 94, 90), (98, 114, 108)]
    snowcap = [(196, 202, 212), (222, 226, 232), (240, 242, 245), (252, 252, 253)]
    outline = (34, 42, 46)
    for i, (tx, ty, s) in enumerate(TREES):
        if ty < STATUE[1]:
            draw_pine(cv, tx, ty, s, trunk_c, needles, snowcap, outline, 100 + i)
    for i, (bx, by, s) in enumerate(BUSHES):
        draw_snow_mound(cv, bx, by, s, snow, 200 + i)
    shadow(cv, STATUE[0] + 6, STATUE[1] + 1, 36, 7, 0.86, (170, 176, 190), 0.2)
    pts = statue(cv, [(92, 96, 104), (118, 122, 130), (146, 150, 156), (172, 176, 182), (196, 200, 204)],
                 (58, 62, 70), 300)
    cap(cv, pts, snowcap, 301, depth=0.75)
    icicles(cv, pts, random.Random(9), [(196, 214, 220), (224, 236, 240), (246, 250, 252)])
    for i, (x, y) in enumerate(PEBBLES):
        p = pebble(cv, x, y, [(110, 114, 122), (140, 144, 150), (172, 176, 182)], (70, 74, 82), 400 + i)
        cap(cv, p, snowcap, 410 + i, depth=0.4)
    for i, (tx, ty, s) in enumerate(TREES):
        if ty >= STATUE[1]:
            draw_pine(cv, tx, ty, s, trunk_c, needles, snowcap, outline, 100 + i)
    # Сухие стебли, торчащие из снега.
    tufts(cv, rng, 90, [(150, 140, 122), (176, 166, 144), (204, 196, 176)])
    foreground_grass(cv, rng, [(120, 112, 100), (150, 140, 122), (182, 174, 156)])
    for i, (x, y, w) in enumerate([(30, 272, 70), (470, 274, 60)]):
        blob(cv, x, y, w, 16, snow, seed=520 + i, wobble=0.12, tex=0.05, bias=0.05)
    return cv


def draw_pine(cv, x0, y0, s, trunk_c, needles, snowcap, outline, seed):
    rng = random.Random(seed)
    th = 7 * s
    total = 46 * s
    shadow(cv, x0 + 6 * s, y0 + 1, 14 * s, 3.5 * s, 0.86, (170, 176, 190), 0.2)
    trunk(cv, x0, y0, th, max(1.5, 2.2 * s), trunk_c, outline, seed)
    tiers = 4
    for i in range(tiers):
        tier_top = y0 - th - total + i * total * 0.22
        tier_h = total * (0.32 + i * 0.03)
        width = (7 + i * 4.5) * s
        for k in range(int(tier_h)):
            y = int(tier_top + k)
            frac = k / tier_h
            half = width * frac ** 0.85 + (vnoise(k * 0.7, i, seed) - 0.5) * 2
            snow_rows = max(2, tier_h * 0.3)
            for x in range(int(x0 - half), int(x0 + half) + 1):
                u = (x - x0) / max(1.0, half)
                t = 0.45 + u * 0.35 - frac * 0.25 + (vnoise(x * 0.6, y * 0.6, seed + i) - 0.5) * 0.4
                c = ramp(needles, t, x, y)
                drift = (vnoise(x * 0.5, i, seed + 9) - 0.5) * 2.5
                if k < snow_rows * (1 - abs(u) * 0.5) + drift or (frac > 0.8 and abs(u) > 0.8):
                    c = ramp(snowcap, t + 0.25, x, y)
                if abs(x - (x0 - half)) < 1:
                    c = outline if k > snow_rows else snowcap[0]
                fxv = (0, 0, int(60 + 60 * (1 - i / tiers)))
                cv.put(x, y, c, fxv)
        # Свисающие капли снега на краях яруса.
        for side in (-1, 1):
            ex = int(x0 + side * width)
            ey = int(tier_top + tier_h - 1)
            for k in range(rng.randint(1, 3)):
                cv.put(ex, ey + k, snowcap[2])


def draw_snow_mound(cv, x0, y0, s, snow, seed):
    shadow(cv, x0 + 2, y0 + 1, 12 * s, 2.5 * s, 0.86, (170, 176, 190), 0.2)
    blob(cv, x0, y0 - 4 * s, 10 * s, 6 * s, snow, seed=seed, wobble=0.15, flat=0.65, tex=0.06, bias=0.12)
    rng = random.Random(seed)
    for _ in range(3):
        x = x0 + rng.randint(-6, 6)
        for k in range(rng.randint(3, 6)):
            cv.put(x + (k // 3), y0 - 8 * s - k, (92, 80, 74))


def fire():
    cv = Canvas()
    rng = random.Random(1)
    sky(cv, [(30, 12, 22), (58, 18, 28), (104, 30, 32), (160, 52, 36), (214, 94, 46), (242, 148, 70)], 190)
    sun(cv, (255, 196, 120), (250, 120, 70), r=11, halo_r=30)
    smoke = [(44, 22, 28), (62, 32, 36), (84, 44, 44), (108, 58, 52)]
    for i, (x, y, w, h) in enumerate([(120, 44, 80, 18), (250, 24, 60, 12), (330, 70, 90, 16),
                                      (452, 92, 50, 10), (40, 98, 44, 9), (300, 112, 40, 9)]):
        cumulus(cv, x, y, w, h, smoke, seed=40 + i)
    # Вулкан среди дальних гор.
    peaks = make_peaks(11, volcano=(300, 74, 0.95, 0.95))
    peak_range(cv, peaks, [(38, 18, 24), (54, 26, 30), (74, 36, 36), (98, 46, 40)], 11,
               haze=(150, 56, 40), haze_amt=0.55, crater=(300, 6))
    for x in range(W):  # огненный контур хребта
        top, _ = peak_height(peaks, x)
        cv.put(x, top, (190, 86, 52))
    # Лавовый поток по склону вулкана и свечение кратера.
    for k in range(7):
        r = 5 + k * 2.2
        blob(cv, 300 - k * 5 + math.sin(k) * 3, 70 - k * 9, r * 1.2, r, smoke, seed=80 + k,
             wobble=0.12, tex=0.08, bias=-0.05 - k * 0.02)
    for y in range(78, 172):
        cx = 300 + math.sin(y * 0.18) * 3 + (y - 80) * 0.15
        w = 1 + (y - 80) * 0.02
        for x in range(int(cx - w), int(cx + w) + 1):
            cv.put(x, y, (255, 160, 64) if x == int(cx) else (226, 92, 40), (0, 255, 0))
    for y in range(70, 84):
        for x in range(286, 315):
            d = ((x - 300) / 14) ** 2 + ((y - 84) / 12) ** 2
            if d < 1 and dither(1 - d, x, y) and cv.get(x, y)[0] < 120:
                cv.put(x, y, mix(cv.get(x, y), (240, 110, 50), 0.4))
    basalt = [(30, 20, 24), (42, 28, 30), (58, 38, 38), (76, 50, 46), (98, 64, 54)]
    mountains(cv, basalt[:4], 12, ridge=mid_ridge, haze=(120, 50, 40), haze_amt=0.3, rim=(220, 110, 60))
    treeline(cv, mid_ridge, [(26, 16, 20)], 13, kind="dead")
    ground(cv, basalt, 14, patch=0.7, base=0.62)
    # Светящиеся трещины в земле.
    for y in range(190, H):
        for x in range(W):
            if avoided(x, y, -2):
                continue
            if fbm(x * 0.02, y * 0.04, 34, 2) < 0.47:
                continue
            n = fbm(x * 0.03, y * 0.07, 33, 3)
            width = 0.003 + (y - 190) / (H - 190) * 0.009
            if abs(n - 0.5) < width and y > ground_top(x) + 2:
                hot = abs(n - 0.5) < width * 0.4
                cv.put(x, y, (255, 196, 96) if hot else (226, 92, 40), (0, 255 if hot else 180, 0))
    # Тропа: остывшая корка лавы.
    path(cv, [(22, 16, 20), (36, 24, 28), (52, 34, 36)], 15, edge=(150, 60, 36))
    # Лавовое озерцо вместо пруда.
    px, py, prx, pry = POND
    lava = [(150, 40, 26), (212, 76, 34), (246, 130, 52), (255, 196, 96), (255, 236, 160)]
    for y in range(py - pry - 2, py + pry + 3):
        for x in range(px - prx - 3, px + prx + 4):
            d = ((x - px) / (prx + 3)) ** 2 + ((y - py) / (pry + 2)) ** 2
            if d <= 1:
                cv.put(x, y, ramp(basalt, 0.3 + (vnoise(x * 0.5, y * 0.5, 2) - 0.5) * 0.5, x, y))
    for y in range(py - pry, py + pry + 1):
        for x in range(px - prx, px + prx + 1):
            d = ((x - px) / prx) ** 2 + ((y - py) / pry) ** 2
            if d <= 1:
                n = fbm(x * 0.12, y * 0.3, 44, 3)
                t = 0.9 - d * 0.6 + (n - 0.5) * 0.8
                c = ramp(lava, t, x, y)
                if n > 0.62:
                    c = basalt[1]  # плавающая корка
                cv.put(x, y, c, (180, 255, 0))
    trunk_c = [(18, 12, 14), (30, 20, 22), (44, 30, 30)]
    outline = (12, 8, 10)
    for i, (tx, ty, s) in enumerate(TREES):
        if ty < STATUE[1]:
            draw_burnt_tree(cv, tx, ty, s, trunk_c, outline, 100 + i)
    for i, (bx, by, s) in enumerate(BUSHES):
        p = pebble(cv, bx, by, s=1.6 * s, cols=basalt[1:4], outline=outline, seed=200 + i)
        ember_cracks(cv, p, 210 + i, density=0.5)
    shadow(cv, STATUE[0] + 6, STATUE[1] + 1, 36, 7, 0.6)
    pts = statue(cv, [(26, 20, 26), (40, 30, 36), (58, 42, 46), (80, 56, 56), (104, 70, 62)],
                 (12, 8, 12), 300)
    ember_cracks(cv, pts, 301, density=0.55)
    # Огненный контровой свет по верхнему краю статуи.
    for (x, y) in pts:
        if (x, y - 1) not in pts and (x, y - 2) not in pts:
            cv.put(x, y, (236, 122, 62))
    for i, (x, y) in enumerate(PEBBLES):
        pebble(cv, x, y, basalt[1:4], outline, 400 + i)
    for i, (tx, ty, s) in enumerate(TREES):
        if ty >= STATUE[1]:
            draw_burnt_tree(cv, tx, ty, s, trunk_c, outline, 100 + i)
    sprinkle(cv, rng, 160, [(70, 60, 60), (90, 76, 72)], y_min=192)  # пепел
    sprinkle(cv, rng, 50, [(255, 150, 60), (255, 200, 110)], y_min=192, fx=(0, 255, 0))  # угли
    for i, (x, y, w) in enumerate([(30, 276, 66), (470, 278, 58), (130, 282, 40)]):
        p = blob(cv, x, y, w, 24, basalt[:3], seed=530 + i, wobble=0.15, tex=0.1,
                 outline=(10, 6, 8), bias=-0.1)
        for (bx, by) in p:
            if (bx, by - 1) not in p:
                cv.put(bx, by, (180, 76, 44))
    return cv


def ember_cracks(cv, pts, seed, density=1.0):
    for (x, y) in pts:
        n = fbm(x * 0.12, y * 0.12, seed, 3)
        if abs(n - 0.5) < 0.022 * density:
            hot = abs(n - 0.5) < 0.009 * density
            cv.put(x, y, (255, 200, 100) if hot else (230, 96, 42), (0, 255 if hot else 200, 0))


def draw_burnt_tree(cv, x0, y0, s, trunk_c, outline, seed):
    rng = random.Random(seed)
    th = 30 * s
    shadow(cv, x0 + 4 * s, y0 + 1, 10 * s, 3 * s, 0.6)
    trunk(cv, x0, y0, th, max(1.2, 2.0 * s), trunk_c, outline, seed)

    def branch(x, y, angle, length, depth):
        for k in range(int(length)):
            px = x + math.cos(angle) * k
            py = y + math.sin(angle) * k
            cv.put(px, py, trunk_c[0] if depth > 0 else trunk_c[1])
            if depth > 0:
                cv.put(px + 1, py, trunk_c[1])
        ex, ey = x + math.cos(angle) * length, y + math.sin(angle) * length
        if depth > 0:
            for d in (-0.5, 0.45):
                branch(ex, ey, angle + d + rng.uniform(-0.2, 0.2), length * 0.62, depth - 1)
        else:
            cv.put(ex, ey, (255, 160, 70), (0, 255, 0))
            if rng.random() < 0.5:
                cv.put(ex, ey - 1, (255, 210, 120), (0, 255, 0))

    top = y0 - th
    branch(x0, top + 2, -math.pi / 2 - 0.15, 10 * s, 2)
    branch(x0, top + 8 * s, -math.pi / 2 - 0.9, 9 * s, 1)
    branch(x0, top + 6 * s, -math.pi / 2 + 0.85, 10 * s, 1)
    # Тлеющие трещины в коре.
    for k in range(3):
        y = int(y0 - rng.uniform(4, th - 4))
        cv.put(x0, y, (230, 96, 42), (0, 220, 0))
        cv.put(x0, y + 1, (255, 170, 80), (0, 255, 0))


def air():
    cv = Canvas()
    rng = random.Random(1)
    # Мы над облаками: небо продолжается до самого низа кадра.
    sky(cv, [(46, 118, 206), (72, 146, 224), (110, 176, 236), (160, 208, 244), (206, 232, 250),
             (226, 242, 252)], H)
    sun(cv, (255, 254, 236), (255, 248, 210), r=14, halo_r=46, rays=True)
    cloud = [(172, 186, 222), (204, 214, 238), (230, 236, 248), (246, 249, 254), (255, 255, 255)]
    # Высокие кучевые башни на месте гор. Основания уходят ниже начала облачного
    # моря, чтобы башни «вырастали» из него, а не висели с обрезанным низом.
    for i, (x, y, w, h) in enumerate([(70, 178, 130, 60), (196, 180, 100, 46), (300, 178, 140, 70),
                                      (440, 180, 120, 58)]):
        cumulus(cv, x, y, w, h, cloud, seed=60 + i, flat=0.5, bias=-0.12, tex=0.08, lump=6)
    for i, (x, y, w, h) in enumerate([(130, 40, 54, 10), (260, 26, 40, 8), (40, 74, 30, 7)]):
        cumulus(cv, x, y, w, h, cloud, seed=40 + i)
    # Далёкие парящие островки в дымке.
    far_c = [(120, 160, 196), (140, 180, 210), (160, 196, 222)]
    for i, (x, y, w) in enumerate([(170, 112, 10), (390, 100, 14), (250, 128, 7), (60, 118, 6)]):
        islet(cv, x, y, w, 1, far_c, far_c, far_c[0], 70 + i, far_c[0])
    # Облачное море вместо земли.
    cloud_sea(cv, cloud, 80, y_start=160)
    # Пруд — разрыв в облаках, сквозь который видно небо внизу.
    px, py, prx, pry = POND
    below = [(70, 140, 220), (96, 164, 232), (128, 190, 240)]
    for y in range(py - pry - 1, py + pry + 2):
        for x in range(px - prx - 2, px + prx + 3):
            d = ((x - px) / (prx + 2)) ** 2 + ((y - py) / (pry + 1)) ** 2
            if d <= 1:
                cv.put(x, y, ramp(below, 0.1 + (y - py + pry) / (2 * pry) * 0.8, x, y))
    for k in range(9):
        a = k / 9 * math.tau
        blob(cv, px + math.cos(a) * prx, py + math.sin(a) * pry * 0.9 + 2, 7, 4, cloud,
             seed=90 + k, wobble=0.1, flat=0.6, tex=0.04, fx=(0, 0, 70))
    for k in range(3):  # птицы далеко внизу
        bx, by = px - 10 + k * 8, py - 1 + (k % 2) * 3
        cv.put(bx, by, (40, 80, 140))
        cv.put(bx - 1, by - 1, (40, 80, 140))
        cv.put(bx + 1, by - 1, (40, 80, 140))
    grass = [(70, 140, 106), (96, 170, 120), (130, 198, 140), (178, 226, 170)]
    earth_c = [(88, 74, 82), (112, 96, 100), (140, 122, 118), (170, 150, 138)]
    leaves = [(62, 140, 116), (86, 170, 132), (120, 200, 152), (168, 228, 186), (214, 246, 220)]
    trunk_c = [(96, 76, 74), (122, 98, 90), (150, 124, 108)]
    outline = (52, 60, 82)
    roots = (100, 86, 94)
    # Тропа из парящих камней к статуе.
    for i, y in enumerate(range(212, H, 13)):
        cx, w = path_center(y)
        islet(cv, cx, y, 3 + i * 1.2, 1, grass, earth_c, outline, 600 + i, roots)
    for i, (tx, ty, s) in enumerate(TREES):
        if ty < STATUE[1]:
            draw_air_tree(cv, tx, ty, s, trunk_c, leaves, grass, earth_c, outline, roots, 100 + i)
    for i, (bx, by, s) in enumerate(BUSHES):
        islet(cv, bx, by - 2, 6 * s, 1, grass, earth_c, outline, 200 + i, roots, (0, 0, 60))
        draw_bush(cv, bx, by - 2, 0.6 * s, leaves, outline, 210 + i)
    islet(cv, STATUE[0] + 2, STATUE[1] - 2, 40, 1, grass, earth_c, outline, 300, roots)
    pts = statue(cv, [(120, 126, 150), (148, 154, 174), (176, 182, 198), (204, 210, 222), (230, 234, 242)],
                 (70, 76, 104), 300)
    cap(cv, pts, [(96, 170, 120), (130, 198, 140), (178, 226, 170)], 301, depth=0.35)
    # Ленты ветра вокруг статуи и в небе.
    for k, (wx, wy, length, amp) in enumerate([(250, 160, 70, 4), (360, 128, 90, 5), (140, 70, 80, 3),
                                                (300, 46, 60, 3), (420, 186, 50, 3)]):
        for i in range(length):
            x = wx + i
            y = wy + math.sin(i * 0.09 + k) * amp
            if i % 17 < 13:
                cv.put(x, y, (250, 252, 255) if i % 3 else (222, 238, 252), (200, 0, 0))
    for i, (tx, ty, s) in enumerate(TREES):
        if ty >= STATUE[1]:
            draw_air_tree(cv, tx, ty, s, trunk_c, leaves, grass, earth_c, outline, roots, 100 + i)
    # Большие облака на переднем плане по углам.
    for i, (x, y, w, h) in enumerate([(40, 276, 110, 34), (460, 280, 100, 30)]):
        cumulus(cv, x, y, w, h, cloud, seed=700 + i, flat=0.6, fx=(0, 0, 90))
    return cv


def draw_air_tree(cv, x0, y0, s, trunk_c, leaves, grass, earth_c, outline, roots, seed):
    islet(cv, x0, y0, 12 * s, 1, grass, earth_c, outline, seed + 50, roots, (0, 0, 60))
    th = 20 * s
    # Ствол чуть наклонён ветром.
    for y in range(int(y0 - th), int(y0) + 1):
        lean = int((y0 - y) / th * 3 * s)
        for x in range(int(x0 - 2 * s) + lean, int(x0 + 2 * s) + lean + 1):
            u = (x - (x0 - 2 * s + lean)) / (4 * s)
            cv.put(x, y, outline if u < 0.15 else ramp(trunk_c, 0.2 + u * 0.7, x, y))
    canopy(cv, x0 + 3 * s, y0 - th, s, leaves, outline, seed, WIND_LUMPS, y0 - th + 6 * s, tex=0.18)


def main():
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    for name, painter in (("earth", earth), ("ice", ice), ("fire", fire), ("air", air)):
        painter().save(name)
        print(f"saved assets/textures/menu/bg_{name}.png (+ _fx)")


if __name__ == "__main__":
    main()
