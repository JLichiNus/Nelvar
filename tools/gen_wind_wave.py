"""Генератор пиксельного спрайтшита ПКМ-волны (attacks/wind_wave).

Волна — серп ветра «)» с потоковыми прожилками, внутренними порывами,
завитками на кончиках, линиями скорости и искрами. В конце жизни
рассыпается через упорядоченный дизеринг.

Почему именно так:
  * размер тексела постоянный и равен пикселю игрока (TEXEL world-единиц),
    поэтому расширение волны нарисовано кадрами, а не масштабом узла —
    пиксели не «раздуваются»;
  * повёрнутый пиксель-арт с nearest-фильтром рвётся, поэтому направления
    предрендерены: строки листа — углы 0..90° (шаг 90/(ROWS-1)),
    остальные квадранты получаются flip_h / flip_v в wind_wave.gd.

Лист: колонки — кадры (FRAMES), строки — углы (ROWS), кадр CELL x CELL,
центр дуги (origin узла) — в центре кадра.

Радиус кадра повторяет tween масштаба из wind_wave.gd
(TRANS_QUAD + EASE_OUT, start_size -> end_size). При изменении этих
экспортов в сцене — поправить константы ниже и перезапустить:
    python3 tools/gen_wind_wave.py [--preview out.png]
"""

import math
import random
import sys
from pathlib import Path

from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
OUT = ROOT / "attacks" / "wind_wave" / "wind_wave_sheet.png"
PREVIEW = Path(sys.argv[sys.argv.index("--preview") + 1]) if "--preview" in sys.argv[:-1] else None

# --- синхронно с wind_wave.gd / player.tscn
TEXEL = 1.5            # масштаб Body игрока: 1 пиксель спрайта = 1.5 единицы
ARC_RADIUS = 35.0      # радиус CollisionPolygon2D волны в базовом масштабе
START_SIZE = 70.0
END_SIZE = 180.0

FRAMES = 16
ROWS = 17              # 0°, 5.625°, ..., 90°
CELL = 136

# Бирюзовая палитра ветра (от первого рисунка игрока).
DEEP = (32, 86, 90)
TEAL_D = (40, 108, 112)
TEAL = (53, 133, 137)
TEAL_L = (64, 151, 151)
MINT = (127, 197, 176)
CYAN = (115, 220, 223)
CYAN_L = (184, 245, 239)
WHITE = (233, 245, 233)

# Матрица Байера 4x4 для рассыпания.
BAYER = [
    [0, 8, 2, 10],
    [12, 4, 14, 6],
    [3, 11, 1, 9],
    [15, 7, 13, 5],
]


def ease_out_quad(t: float) -> float:
    return 1.0 - (1.0 - t) * (1.0 - t)


def smooth(e0: float, e1: float, x: float) -> float:
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def fract(x: float) -> float:
    return x - math.floor(x)


def bayer(x: int, y: int) -> float:
    return (BAYER[y & 3][x & 3] + 0.5) / 16.0


def hash01(x: int, y: int) -> float:
    h = (x * 374761393 + y * 668265263) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    return (h & 0xFFFF) / 65535.0


def grain(x: int, y: int) -> float:
    """Порог рассыпания: блоки 2x2 по Байеру + шум, чтобы не было шахматки."""
    return 0.55 * bayer(x >> 1, y >> 1) + 0.45 * hash01(x, y)


class Canvas:
    """Слои рисуются по приоритету: больший prio перекрывает меньший."""

    def __init__(self):
        self.px = {}

    def put(self, x: int, y: int, color, alpha: int = 255, prio: int = 0):
        half = CELL // 2
        if not (-half <= x < half and -half <= y < half):
            return
        old = self.px.get((x, y))
        if old is None or prio >= old[2]:
            self.px[(x, y)] = (color, alpha, prio)

    def image(self) -> Image.Image:
        img = Image.new("RGBA", (CELL, CELL))
        half = CELL // 2
        for (x, y), (c, a, _) in self.px.items():
            img.putpixel((x + half, y + half), (*c, a))
        return img


# ------------------------------------------------------------------ кадр


def render(theta: float, frame: int) -> Image.Image:
    t = (frame + 0.5) / FRAMES                  # середина кадра по времени
    scale = 1.0 + (END_SIZE / START_SIZE - 1.0) * ease_out_quad(t)
    R = ARC_RADIUS * scale / TEXEL              # внешний край, тексели
    birth = smooth(0.0, 0.18, t)                # серп «наливается»
    decay = smooth(0.55, 1.0, t)                # рассыпание
    flow = frame * 0.9                          # фаза потока вдоль дуги

    A = math.radians(74.0)                      # полуугол серпа
    W = (3.4 + 0.15 * R) * (0.65 + 0.35 * birth) * (1.0 - 0.35 * decay)

    ct, st = math.cos(theta), math.sin(theta)
    cv = Canvas()
    half = CELL // 2

    def local(x, y):
        """Мировые тексели (y вниз) -> локальные (ось +x = направление)."""
        cx, cy = x + 0.5, y + 0.5
        return cx * ct + cy * st, -cx * st + cy * ct

    def world(lx, ly):
        return (math.floor(lx * ct - ly * st), math.floor(lx * st + ly * ct))

    def dissolve(x, y, weight, streak=None):
        """True — пиксель съеден рассыпанием; weight 0..1: чем больше, тем дольше живёт.
        streak — координата вдоль потока: серп рвётся на штрихи, а не тает ровно."""
        if decay <= 0.0:
            return False
        level = decay * 1.25 - weight * 0.45
        if streak is not None and fract(streak) < level * 0.9:
            return True
        return grain(x, y) < level * 0.85

    # --- основной серп + внутренние порывы (растровый проход)
    gusts = [
        # (доля радиуса, толщина, полуугол, длина штриха, скважность, prio)
        (0.80, 0.42, 0.78, 9.0, 0.62, 2),
        (0.64, 0.30, 0.58, 7.0, 0.55, 1),
    ]
    for y in range(-half, half):
        for x in range(-half, half):
            lx, ly = local(x, y)
            r = math.hypot(lx, ly)
            a = math.atan2(ly, lx)
            aa = abs(a)

            # основной серп: внешний край круговой, толщина сужается к кончикам
            if aa < A:
                u = aa / A
                w = W * (1.0 - u * u) ** 0.65
                d = (R - r) / w if w > 0.6 else 9.0
                if 0.0 <= d <= 1.0:
                    arc_pos = aa * R                     # длина дуги от центра
                    # прожилки потока бегут от центра серпа к кончикам
                    vein = fract(arc_pos / 11.0 - flow * 0.5 + d * 0.9)
                    weight = (1.0 - u) * 0.7 + (1.0 - d) * 0.5
                    # у каждой «дорожки» по толщине своя фаза — разрывы тянутся вдоль потока
                    lane = int(d * 4.0)
                    streak = arc_pos / 13.0 - flow * 0.35 + hash01(lane, 7)
                    if dissolve(x, y, weight, streak):
                        continue
                    if d < 0.16 and u < 0.62:
                        col, al = WHITE, 255
                    elif d < 0.38:
                        col, al = CYAN_L, 255
                    elif d < 0.66:
                        col, al = (MINT if 0.42 < vein < 0.62 else CYAN), 240
                    elif d < 0.86:
                        col, al = (TEAL_L if vein < 0.5 else TEAL), 200
                    else:
                        col, al = TEAL_D, 150
                    # кончики прозрачнее и холоднее
                    if u > 0.82 and col in (WHITE, CYAN_L):
                        col = CYAN
                    cv.put(x, y, col, al, prio=5)
                    continue

            # внутренние порывы — пунктирные дуги, бегущие к краям
            for k, (fr, th, ga, dash, duty, prio) in enumerate(gusts):
                gA = A * ga
                if aa >= gA:
                    continue
                gr = R * fr
                gw = max(1.2, W * th * (1.0 - (aa / gA) ** 2) ** 0.5)
                d = (gr - r) / gw
                if not 0.0 <= d <= 1.0:
                    continue
                s = aa * gr / dash - flow * (0.7 + 0.25 * k) + k * 0.37
                cut = duty * (1.0 - 0.5 * decay)
                pos = fract(s) / cut              # 0 — голова штриха (у края), 1 — хвост
                if pos > 1.0:
                    continue
                # штрих сужается к хвосту — читается как порыв, а не кирпичик
                if d > 1.0 - 0.6 * pos and gw > 1.5:
                    continue
                if dissolve(x, y, 0.35 - 0.1 * k):
                    continue
                col = CYAN_L if d < 0.4 and k == 0 and pos < 0.5 else CYAN if d < 0.6 else TEAL_L
                cv.put(x, y, col, 230 if k == 0 else 190, prio=prio)
                break

    # --- завитки на кончиках: продолжают кончик серпа и сворачиваются внутрь
    curl_r = max(2.8, 0.12 * R) * (0.75 + 0.25 * birth)
    turns = (0.95 + 0.45 * birth) * (1.0 - 0.4 * decay)
    tip_a = A * 0.985
    for side in (1, -1):
        # центр — на нормали внутрь от кончика, так спираль стартует из кончика
        ccx = (R - curl_r) * math.cos(tip_a)
        ccy = side * (R - curl_r) * math.sin(tip_a)
        steps = int(80 + curl_r * 24)
        for i in range(steps):
            p = i / steps
            ang = side * (tip_a + p * turns * math.tau)
            rho = curl_r * (1.0 - 0.78 * p)
            lx = ccx + rho * math.cos(ang)
            ly = ccy + rho * math.sin(ang)
            x, y = world(lx, ly)
            if dissolve(x, y, 0.55 - 0.4 * p, p * 5.0 - flow * 0.3):
                continue
            col = CYAN_L if p < 0.3 else CYAN if p < 0.7 else MINT
            cv.put(x, y, col, 240, prio=4)
            # первая треть — двойная толщина (наружу), продолжение тела серпа
            if p < 0.3 and curl_r > 3.5:
                ox, oy = world(lx + 0.9 * math.cos(ang), ly + 0.9 * math.sin(ang))
                cv.put(ox, oy, TEAL_L, 210, prio=3)

    # --- линии скорости позади серпа (параллельны направлению)
    rnd = random.Random(7)
    lanes = [rnd.uniform(-0.62, 0.62) for _ in range(6)]
    for k, lane in enumerate(lanes):
        ly = lane * R
        length = (4.0 + 0.09 * R) * (1.0 - 0.4 * abs(lane)) * (1.0 - 0.5 * decay)
        # штрих смещается назад со временем и «отклеивается» от серпа
        inner_edge = math.sqrt(max((R * 0.55) ** 2 - ly * ly, 0.0))
        head = inner_edge - (fract(frame * 0.11 + k * 0.29) * R * 0.45)
        if head - length < -R * 0.05:
            continue
        n = int(length * 2) + 1
        for i in range(n):
            lx = head - length * i / max(n - 1, 1)
            x, y = world(lx, ly)
            fade = i / max(n - 1, 1)
            if dissolve(x, y, 0.4 - 0.3 * fade):
                continue
            col = CYAN_L if fade < 0.25 else CYAN if fade < 0.7 else TEAL_L
            cv.put(x, y, col, int(230 - 110 * fade), prio=1)

    # --- искры, сорванные с переднего края
    for k in range(9):
        seed = random.Random(100 + k)
        a0 = seed.uniform(-A * 0.95, A * 0.95)
        life = fract(seed.random() + frame / 7.0)
        if life > 0.8:
            continue
        rad = R * (1.02 + 0.10 * life) + seed.uniform(-1.0, 2.0)
        a1 = a0 * (1.0 + 0.10 * life)
        x, y = world(rad * math.cos(a1), rad * math.sin(a1))
        col = WHITE if life < 0.3 else CYAN_L if life < 0.6 else CYAN
        if not dissolve(x, y, 0.2):
            cv.put(x, y, col, 255, prio=6)
            if life < 0.3 and k % 3 == 0:  # крупная искра-крестик
                for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                    cv.put(x + dx, y + dy, CYAN, 200, prio=3)

    return cv.image()


def main() -> None:
    sheet = Image.new("RGBA", (CELL * FRAMES, CELL * ROWS))
    for row in range(ROWS):
        theta = math.radians(90.0 * row / (ROWS - 1))
        for f in range(FRAMES):
            sheet.paste(render(theta, f), (f * CELL, row * CELL))
    OUT.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(OUT)
    print(f"{OUT.relative_to(ROOT)}: {sheet.size[0]}x{sheet.size[1]}")

    if PREVIEW is not None:
        # строки 0° и 45°, каждая 4-й кадр, увеличено x3 на тёмном фоне
        picks = [0, ROWS // 2, ROWS - 1]
        cols = list(range(0, FRAMES, 2))
        pv = Image.new("RGBA", (CELL * len(cols), CELL * len(picks)), (24, 30, 38, 255))
        for i, row in enumerate(picks):
            for j, f in enumerate(cols):
                cell = sheet.crop((f * CELL, row * CELL, (f + 1) * CELL, (row + 1) * CELL))
                pv.alpha_composite(cell, (j * CELL, i * CELL))
        pv = pv.resize((pv.width * 2, pv.height * 2), Image.NEAREST)
        pv.save(PREVIEW)
        print(f"preview: {PREVIEW}")


if __name__ == "__main__":
    main()
