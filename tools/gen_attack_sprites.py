"""Генератор пиксельных спрайтов атак игрока (ЛКМ, ПКМ, R).

Стиль — как у самого игрока (tools/gen_player_sprites.py): та же
5-тоновая палитра неба, тёмный контур по 4 соседям, простые
крупные формы без мелких деталей.

  * ЛКМ — attacks/wind_projectile: шарик сжатого воздуха, 4 кадра
    (внутри проворачивается завиток); шлейф частиц — не спрайт, его
    рисует attacks/wind_projectile/wind_projectile_trail.gd;
  * ПКМ — attacks/wind_wave: порыв ветра — толстый серп «)» с бегущими
    волокнами, завитками на кончиках и пунктирными «эхо»-дугами позади;
    растёт по кадрам и в конце рвётся на клочья;
  * R   — attacks/wind_compression: крупный серп того же вида, цикл
    кадров: блики сбегаются к оси, кончики загибаются вперёд и обхватывают
    цель (две волны — это два спрайта).

Почему так:
  * размер тексела постоянный и равен пикселю игрока (TEXEL world-единиц),
    поэтому рост ПКМ-волны нарисован кадрами, а не масштабом узла;
  * формы заданы в дизайн-единицах (DESIGN_TEXEL world-единиц), как у
    игрока, и снимаются с суперсэмплингом K x K на пиксель: пиксель тела —
    если блок покрыт наполовину, тон — средний по блоку;
  * повёрнутый пиксель-арт с nearest-фильтром рвётся, поэтому направления
    предрендерены: строки листа — углы 0..90° (шаг 90/(ROWS-1)),
    остальные квадранты — flip_h / flip_v в скриптах атак. Свет у форм
    симметричен относительно оси полёта, поэтому отражение его не ломает.

Центр кадра — origin спрайта: у капли — её центр, у серпов — центр дуги.

Радиус ПКМ-кадров повторяет tween масштаба из wind_wave.gd
(TRANS_QUAD + EASE_OUT, start_size -> end_size). При изменении этих
экспортов — поправить константы ниже и перезапустить из корня проекта:
    python3 tools/gen_attack_sprites.py [--preview out.png]
"""

import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
PREVIEW = Path(sys.argv[sys.argv.index("--preview") + 1]) if "--preview" in sys.argv[:-1] else None

# --- синхронно с player.tscn / gen_player_sprites.py
TEXEL = 3.0            # масштаб Body игрока: 1 пиксель спрайта = 3 единицы
DESIGN_TEXEL = 1.5     # world-единиц на дизайн-единицу (размеры форм ниже)
K = round(TEXEL / DESIGN_TEXEL)
assert K * DESIGN_TEXEL == TEXEL
# Небо со сдвигом оттенка, как рампы мира (деревья, слайм): тени уходят
# в холодный сланцево-синий, блики — в тёплый кремовый. Контур — тёмный
# тон той же рампы, а не чистый синий, чтобы не выбиваться из оливкового мира.
RAMP = [(75, 106, 142), (110, 156, 188), (165, 207, 220), (221, 238, 230), (251, 248, 232)]
OUTLINE = (40, 54, 82)

ROWS = 17              # 0°, 5.625°, ..., 90°

# --- ПКМ, синхронно с wind_wave.gd / wind_wave.tscn
WAVE_ARC_RADIUS = 35.0  # радиус CollisionPolygon2D волны в базовом масштабе
WAVE_START_SIZE = 70.0
WAVE_END_SIZE = 180.0
WAVE_FRAMES = 16
WAVE_CELL = 136        # дизайн-единицы; в листе — WAVE_CELL / K пикселей

# --- R, синхронно с wind_compression.gd (ARC_RADIUS)
COMPRESSION_RADIUS = 46  # дизайн-единицы: 46 * 1.5 = 69 world-единиц
COMPRESSION_CELL = 124
COMPRESSION_FRAMES = 8

# --- ЛКМ
PROJECTILE_FRAMES = 4
PROJECTILE_CELL = 24
PROJECTILE_RADIUS = 4.2  # дизайн-единицы: 4 пикселя тела, как голова старой капли


def ease_out_quad(t: float) -> float:
    return 1.0 - (1.0 - t) * (1.0 - t)


def smooth(e0: float, e1: float, x: float) -> float:
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def local_grid(cell: int, theta: float):
    """Локальные координаты центров дизайн-пикселей: ось +x — направление атаки."""
    half = cell // 2
    ys, xs = np.mgrid[-half:half, -half:half].astype(float)
    xs += 0.5
    ys += 0.5
    ct, st = math.cos(theta), math.sin(theta)
    return xs * ct + ys * st, -xs * st + ys * ct


def down(a: np.ndarray) -> np.ndarray:
    """Среднее по блокам K x K: дизайн-сетка -> пиксель листа."""
    h, w = a.shape
    return a.reshape(h // K, K, w // K, K).mean(axis=(1, 3))


def compose(body: np.ndarray, tone: np.ndarray, wisp: np.ndarray, wisp_tone: np.ndarray) -> Image.Image:
    """Тело с тонами + контур по 4 соседям + штрихи ветра без контура.

    Вход — на дизайн-сетке, выход — в пикселях листа (в K раз меньше).
    """
    cover = down(body.astype(float))
    tone = np.rint(down(np.where(body, tone, 0)) / np.maximum(cover, 1e-6)).astype(int)
    body = cover >= 0.5
    wisp_tone = np.rint(down(np.where(wisp, wisp_tone, 0)) / np.maximum(down(wisp.astype(float)), 1e-6)).astype(int)
    wisp = down(wisp.astype(float)) >= 0.25
    h, w = body.shape
    img = np.zeros((h, w, 4), np.uint8)
    ramp = np.array(RAMP, np.uint8)

    near = np.zeros_like(body)
    near[1:, :] |= body[:-1, :]
    near[:-1, :] |= body[1:, :]
    near[:, 1:] |= body[:, :-1]
    near[:, :-1] |= body[:, 1:]
    outline = near & ~body

    wisp = wisp & ~body & ~outline
    img[wisp, :3] = ramp[wisp_tone[wisp]]
    img[wisp, 3] = 255
    img[outline, :3] = OUTLINE
    img[outline, 3] = 255
    img[body, :3] = ramp[np.clip(tone[body], 0, 4)]
    img[body, 3] = 255
    return Image.fromarray(img, "RGBA")


# ------------------------------------------------------------------ серп


def stroke(lx, ly, pts, half_width):
    """Маска пикселей ближе half_width к ломаной из точек pts (N x 2)."""
    mask = np.zeros(lx.shape, bool)
    for px, py in pts:
        mask |= (lx - px) ** 2 + (ly - py) ** 2 <= half_width * half_width
    return mask


def tip_curl(R, A, rc, turns, forward=False):
    """Завиток на кончике серпа (верхнем, ly > 0): продолжает дугу прочь от
    оси и закручивается внутрь, к центру дуги, а при forward — наружу,
    вперёд по ходу серпа. turns — сколько оборотов уже свито."""
    tip = np.array([R * math.cos(A), R * math.sin(A)])
    n = tip / np.linalg.norm(tip)              # наружу от центра дуги
    m = -n if forward else n                   # от центра завитка к кончику
    c = tip - m * rc
    phi = np.linspace(0.0, turns * 2.0 * math.pi, max(int(turns * 60), 2))
    rho = rc * (1.0 - 0.6 * phi / (2.0 * math.pi * 0.85))
    rho = np.maximum(rho, 0.6)
    # поворот m на ±phi: первое движение — по касательной, прочь от оси
    sign = -1.0 if forward else 1.0
    cos, sin = np.cos(phi), np.sin(phi) * sign
    dx = m[0] * cos - m[1] * sin
    dy = m[0] * sin + m[1] * cos
    return np.stack([c[0] + rho * dx, c[1] + rho * dy], axis=1), phi


def wave_frame(theta: float, frame: int) -> Image.Image:
    """Порыв ветра: толстый серп с волокнами, завитки на кончиках,
    пунктирные «эхо»-дуги позади; под конец рвётся на клочья.

    Всё симметрично оси полёта (|ly|), чтобы flip_h / flip_v не ломали вид.
    """
    t = (frame + 0.5) / WAVE_FRAMES              # середина кадра по времени
    scale = 1.0 + (WAVE_END_SIZE / WAVE_START_SIZE - 1.0) * ease_out_quad(t)
    R = WAVE_ARC_RADIUS * scale / DESIGN_TEXEL    # внешний край, дизайн-единицы
    birth = smooth(0.0, 0.25, t)                  # серп «наливается»
    decay = smooth(0.55, 1.0, t)                  # распад на клочья
    W = (4.0 + 0.14 * R) * (0.6 + 0.4 * birth) * (1.0 - 0.5 * decay)
    A = math.radians(70.0) * (0.85 + 0.15 * birth)

    lx, ly = local_grid(WAVE_CELL, theta)
    ay = np.abs(ly)
    r = np.hypot(lx, ly)
    ang = np.arctan2(ay, lx)
    u = np.clip(ang / A, 0.0, 1.0)
    arc_s = ang * R                               # длина дуги от оси

    # --- тело: передний край выпуклый, толщина сужается к кончикам
    w = W * (1.0 - u ** 2.2) ** 0.55
    d = (R - r) / np.maximum(w, 1e-3)             # 0 — передний край, 1 — задний
    body = (ang < A) & (w > 0.9) & (d >= 0.0) & (d <= 1.0)
    # распад: тело тает от кончиков к середине и рвётся в двух местах,
    # а отслоившийся передний край уходит штрихами (ниже, «клочья»)
    erode = 1.0 - 0.45 * decay
    if decay > 0.0:
        body &= u < erode
        for at, size in ((0.3, 0.05), (0.62, 0.07)):
            body &= np.abs(u - at) > size * smooth(0.0, 0.5, decay) + 0.06 * decay * decay

    tone = np.where(d < 0.28, 4, np.where(d < 0.55, 3, np.where(d < 0.8, 2, 1)))
    tone = np.where((u > 0.75) & (tone > 1), tone - 1, tone)
    # волокна: пунктир тёмнее тела бежит от середины к кончикам
    flow = np.modf((arc_s - frame * 2.6) / 11.0 + 10.0)[0]
    fiber = (np.abs(d - 0.5) < 0.12) & (flow < 0.55) & (u < 0.85)
    tone = np.where(fiber & (W > 6.0), np.minimum(tone, 2), tone)
    glint = (d < 0.18) & (np.modf((arc_s - frame * 2.6) / 15.0 + 10.0)[0] < 0.3) & (u < 0.6)
    tone = np.where(glint, 4, tone)

    # --- штрихи без контура
    wisp = np.zeros(lx.shape, bool)
    wtone = np.full(lx.shape, 3)

    # «эхо»-дуги позади тела: пунктир, бегущий к кончикам
    echo_fade = 1.0 - decay
    for k, (gap, span, tn) in enumerate(((3.5, 0.75, 3), (8.0, 0.5, 2))):
        if echo_fade < 0.3 + 0.3 * k:
            continue
        er = R - W - gap - 1.5 * k
        dash = np.modf((arc_s - frame * (3.5 + k)) / (8.0 + 3.0 * k) + 10.0)[0] < 0.6
        line = (np.abs(r - er) < 0.55) & (ang < A * span * (0.6 + 0.4 * birth)) & dash
        wisp |= line
        wtone = np.where(line, tn, wtone)

    # завитки на кончиках: сворачиваются по ходу волны, при распаде
    # рвутся и уносятся назад
    rc = 2.0 + 0.11 * R
    turns = 0.25 + 0.75 * smooth(0.05, 0.6, t)
    pts, phi = tip_curl(R - W * 0.15, A, rc, turns)
    if decay > 0.0:
        keep = np.modf(phi / 1.3)[0] > decay * 0.8
        pts = pts[keep] - np.array([decay * 6.0, 0.0])
    if len(pts):
        curl = stroke(lx, ay, pts, 0.6)
        wisp |= curl
        wtone = np.where(curl, np.where(r > R - rc, 4, 3), wtone)

    # клочья распада: где тело растаяло, передний край ещё летит
    # рваными штрихами и отстаёт назад
    if decay > 0.05:
        lag = decay * 5.0
        peel = (ang < A) & (u >= erode - 0.05) & (u < erode + 0.35 * (1.0 - decay) + 0.1)
        dash = np.modf((arc_s - frame * 2.6) / 7.0 + 10.0)[0] < 0.55 - 0.25 * decay
        seg = peel & dash & (np.abs(r - (R - 1.5 - lag * (0.5 + u))) < 0.6)
        wisp |= seg
        wtone = np.where(seg, np.where(u < erode + 0.15, 3, 2), wtone)

    return compose(body, tone, wisp, wtone)


def compression_frame(theta: float, frame: int) -> Image.Image:
    """Серп сжатия: тот же порыв, что у ПКМ, но давит на цель. Блики бегут
    от кончиков к оси (воздух сходится в точку), кончики загибаются вперёд
    завитками-«пальцами» и обхватывают цель. Кадры — цикл.
    """
    phase = frame / COMPRESSION_FRAMES          # 0..1 по циклу
    R = float(COMPRESSION_RADIUS)
    W = 9.5
    A = math.radians(64.0)

    lx, ly = local_grid(COMPRESSION_CELL, theta)
    ay = np.abs(ly)
    r = np.hypot(lx, ly)
    ang = np.arctan2(ay, lx)
    u = np.clip(ang / A, 0.0, 1.0)
    arc_s = ang * R

    w = W * (1.0 - u ** 2.4) ** 0.5
    d = (R - r) / np.maximum(w, 1e-3)
    body = (ang < A) & (w > 0.9) & (d >= 0.0) & (d <= 1.0)
    tone = np.where(d < 0.28, 4, np.where(d < 0.55, 3, np.where(d < 0.8, 2, 1)))
    tone = np.where((u > 0.75) & (tone > 1), tone - 1, tone)
    # поток к оси: длина дуги + сдвиг по фазе (цикл ровно на период)
    flow = lambda period: np.modf(arc_s / period + phase * 2.0 + 10.0)[0]
    fiber = (np.abs(d - 0.5) < 0.12) & (flow(11.0) < 0.5) & (u < 0.85)
    tone = np.where(fiber, np.minimum(tone, 2), tone)
    glint = (d < 0.2) & (flow(16.0) < 0.3) & (u < 0.75)
    tone = np.where(glint, 4, tone)

    wisp = np.zeros(lx.shape, bool)
    wtone = np.full(lx.shape, 3)
    # «эхо»-дуги позади: воздух, который серп гонит перед собой
    for k, (gap, span, tn) in enumerate(((3.5, 0.75, 3), (8.0, 0.5, 2))):
        er = R - W - gap - 1.5 * k
        dash = np.modf(arc_s / (8.0 + 3.0 * k) + phase * (2.0 + k) + 10.0)[0] < 0.6
        line = (np.abs(r - er) < 0.55) & (ang < A * span) & dash
        wisp |= line
        wtone = np.where(line, tn, wtone)

    # завитки-«пальцы» обхватывают цель; чуть дышат по циклу
    rc = 8.0 + 0.8 * math.sin(phase * 2.0 * math.pi)
    pts, _phi = tip_curl(R - W * 0.15, A, rc, 0.9, forward=True)
    curl = stroke(lx, ay, pts, 0.6)
    wisp |= curl
    wtone = np.where(curl, np.where(lx > R * math.cos(A) + rc * 0.6, 4, 3), wtone)

    return compose(body, tone, wisp, wtone)


# ------------------------------------------------------------------ капля


def projectile_frame(theta: float, frame: int) -> Image.Image:
    """Шарик сжатого воздуха; шлейф частиц рисует wind_projectile_trail.gd.

    Свет — спереди по ходу полёта (симметрично оси, flip его не ломает),
    задняя кромка холодная. Внутри по кадрам проворачивается завиток ветра.
    """
    lx, ly = local_grid(PROJECTILE_CELL, theta)
    r = np.hypot(lx, ly)
    ball_r = PROJECTILE_RADIUS
    k = ball_r / 6.3  # внутренние размеры подобраны для радиуса 6.3
    body = r <= ball_r
    # тон по положению вдоль оси: передняя полусфера светлее
    tone = np.where(lx > 1.0 * k, 4, np.where(lx > -2.0 * k, 3, np.where(lx > -4.2 * k, 2, 1)))
    tone = np.where((r > ball_r - 1.8 * k) & (lx < 0.5 * k), np.minimum(tone, 2), tone)

    # завиток: дуга тона 2 внутри шарика, поворачивается на 90° за кадр
    a = np.arctan2(ly, lx) - frame * math.pi * 0.5
    a = (a + math.pi) % (2.0 * math.pi) - math.pi
    curl = (np.abs(r - 3.0 * k) < 1.1 * k) & (a > -0.2) & (a < 2.0)
    tone = np.where(body & curl, np.minimum(tone, 2), tone)
    tone = np.where(body & (r < 1.0 * k), 4, tone)

    wisp = np.zeros_like(body)
    return compose(body, tone, wisp, np.full(body.shape, 2))


# ------------------------------------------------------------------ вывод


def build_sheet(cell, frames, render):
    """cell — в дизайн-единицах; ячейка листа — cell / K пикселей."""
    px = cell // K
    sheet = Image.new("RGBA", (px * frames, px * ROWS))
    for row in range(ROWS):
        theta = math.radians(90.0 * row / (ROWS - 1))
        for f in range(frames):
            sheet.paste(render(theta, f), (f * px, row * px))
    return sheet


def save(sheet: Image.Image, rel: str) -> None:
    out = ROOT / rel
    out.parent.mkdir(parents=True, exist_ok=True)
    sheet.save(out)
    print(f"{rel}: {sheet.size[0]}x{sheet.size[1]}")


def preview(sheets, path: Path) -> None:
    """Строки 0°/45°/90° каждого листа на фоне травы, увеличено x3."""
    picks = [0, ROWS // 2, ROWS - 1]
    blocks = []
    for sheet, cell in sheets:
        cell_px = cell // K
        cols = sheet.width // cell_px
        for row in picks:
            blocks.append([sheet.crop((f * cell_px, row * cell_px, (f + 1) * cell_px, (row + 1) * cell_px))
                           for f in range(0, cols, max(1, cols // 6))])
    width = max(sum(c.width for c in b) for b in blocks)
    height = sum(b[0].height for b in blocks)
    pv = Image.new("RGBA", (width, height), (62, 90, 60, 255))
    y = 0
    for b in blocks:
        x = 0
        for c in b:
            pv.alpha_composite(c, (x, y))
            x += c.width
        y += b[0].height
    pv.resize((pv.width * 3, pv.height * 3), Image.NEAREST).save(path)
    print(f"preview: {path}")


def main() -> None:
    assert all(c % (2 * K) == 0 for c in (PROJECTILE_CELL, WAVE_CELL, COMPRESSION_CELL))
    projectile = build_sheet(PROJECTILE_CELL, PROJECTILE_FRAMES, projectile_frame)
    wave = build_sheet(WAVE_CELL, WAVE_FRAMES, wave_frame)
    compression = build_sheet(COMPRESSION_CELL, COMPRESSION_FRAMES, compression_frame)
    save(projectile, "attacks/wind_projectile/wind_projectile_sheet.png")
    save(wave, "attacks/wind_wave/wind_wave_sheet.png")
    save(compression, "attacks/wind_compression/wind_compression_sheet.png")
    if PREVIEW is not None:
        preview([(projectile, PROJECTILE_CELL), (wave, WAVE_CELL),
                 (compression, COMPRESSION_CELL)], PREVIEW)


if __name__ == "__main__":
    main()
