"""Генератор пиксельных спрайтов атак игрока (ЛКМ, ПКМ, R).

Стиль — как у самого игрока (tools/gen_player_sprites.py): та же
5-тоновая палитра неба, тёмный контур по 4 соседям, простые
крупные формы без мелких деталей.

  * ЛКМ — attacks/wind_projectile: сгусток ветра-«капля» с коротким
    хвостом, 2 кадра (хвост мерцает);
  * ПКМ — attacks/wind_wave: серп ветра «)», растёт по кадрам
    и в конце распадается на куски;
  * R   — attacks/wind_compression: крупный серп того же вида,
    одна дуга на кадр (две волны — это два спрайта).

Почему так:
  * размер тексела постоянный и равен пикселю игрока (TEXEL world-единиц),
    поэтому рост ПКМ-волны нарисован кадрами, а не масштабом узла;
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
TEXEL = 1.5            # масштаб Body игрока: 1 пиксель спрайта = 1.5 единицы
RAMP = [(70, 104, 150), (112, 152, 196), (162, 198, 226), (214, 236, 246), (246, 252, 254)]
OUTLINE = (36, 50, 84)

ROWS = 17              # 0°, 5.625°, ..., 90°

# --- ПКМ, синхронно с wind_wave.gd / wind_wave.tscn
WAVE_ARC_RADIUS = 35.0  # радиус CollisionPolygon2D волны в базовом масштабе
WAVE_START_SIZE = 70.0
WAVE_END_SIZE = 180.0
WAVE_FRAMES = 16
WAVE_CELL = 136

# --- R, синхронно с wind_compression.gd (ARC_RADIUS)
COMPRESSION_RADIUS = 46  # тексели: 46 * 1.5 = 69 world-единиц
COMPRESSION_CELL = 100

# --- ЛКМ
PROJECTILE_FRAMES = 2
PROJECTILE_CELL = 24


def ease_out_quad(t: float) -> float:
    return 1.0 - (1.0 - t) * (1.0 - t)


def smooth(e0: float, e1: float, x: float) -> float:
    t = min(max((x - e0) / (e1 - e0), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def local_grid(cell: int, theta: float):
    """Локальные координаты центров пикселей: ось +x — направление атаки."""
    half = cell // 2
    ys, xs = np.mgrid[-half:half, -half:half].astype(float)
    xs += 0.5
    ys += 0.5
    ct, st = math.cos(theta), math.sin(theta)
    return xs * ct + ys * st, -xs * st + ys * ct


def compose(body: np.ndarray, tone: np.ndarray, wisp: np.ndarray, wisp_tone: np.ndarray) -> Image.Image:
    """Тело с тонами + контур по 4 соседям + штрихи ветра без контура."""
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


def crescent(cell, theta, R, W, A, gap=0.0, wisp=True):
    """Серп «)» с центром дуги в центре кадра.

    R — внешний радиус, W — толщина в середине, A — полуугол.
    gap > 0 рвёт серп на три куска (распад волны).
    """
    lx, ly = local_grid(cell, theta)
    r = np.hypot(lx, ly)
    aa = np.abs(np.arctan2(ly, lx))
    u = np.clip(aa / A, 0.0, 1.0)

    # толщина сужается к кончикам
    w = W * (1.0 - u * u) ** 0.6
    d = (R - r) / np.maximum(w, 1e-3)    # 0 — передний край, 1 — задний
    body = (aa < A) & (w > 0.8) & (d >= 0.0) & (d <= 1.0)
    if gap > 0.0:
        body &= np.abs(u - 0.42) > gap

    # передний край светлый, задний темнее, кончики холоднее
    tone = np.where(d < 0.34, 3, np.where(d < 0.7, 2, 1))
    tone = np.where((d < 0.34) & (u < 0.45), 4, tone)
    tone = np.where(u > 0.8, tone - 1, tone)

    # одна внутренняя дуга-порыв, как штрихи ветра у игрока
    ww = np.zeros_like(body)
    if wisp:
        gr = R - W - 3.0
        ww = (aa < A * 0.55) & (np.abs(r - gr) < 0.6)
        if gap > 0.0:
            ww &= np.abs(u - 0.25) > gap
    wtone = np.full(body.shape, 2)
    return compose(body, tone, ww, wtone)


def wave_frame(theta: float, frame: int) -> Image.Image:
    t = (frame + 0.5) / WAVE_FRAMES              # середина кадра по времени
    scale = 1.0 + (WAVE_END_SIZE / WAVE_START_SIZE - 1.0) * ease_out_quad(t)
    R = WAVE_ARC_RADIUS * scale / TEXEL           # внешний край, тексели
    birth = smooth(0.0, 0.2, t)                   # серп «наливается»
    decay = smooth(0.55, 1.0, t)                  # распад на куски
    W = (3.0 + 0.09 * R) * (0.7 + 0.3 * birth) * (1.0 - 0.45 * decay)
    A = math.radians(72.0) * (1.0 - 0.2 * decay)
    return crescent(WAVE_CELL, theta, R, W, A, gap=0.16 * decay, wisp=decay < 0.6)


def compression_frame(theta: float) -> Image.Image:
    return crescent(COMPRESSION_CELL, theta, COMPRESSION_RADIUS, 8.0, math.radians(70.0))


# ------------------------------------------------------------------ капля


def projectile_frame(theta: float, frame: int) -> Image.Image:
    lx, ly = local_grid(PROJECTILE_CELL, theta)
    # «капля»: круглая голова впереди, хвост сужается назад
    head_x, head_r = 2.5, 3.2
    tail_x, tail_r = -5.0, 1.0
    k = np.clip((lx - tail_x) / (head_x - tail_x), 0.0, 1.0)
    rad = tail_r + (head_r - tail_r) * k
    body = ((lx - head_x) ** 2 + ly ** 2 <= head_r ** 2) | (
        (lx >= tail_x) & (lx <= head_x) & (np.abs(ly) <= rad)
    )
    edge = np.abs(ly) / np.maximum(rad, 1e-3)
    tone = np.where(lx > 0.0, 3, np.where(lx > -3.0, 2, 1))
    tone = np.where((lx > -1.0) & (edge < 0.45), 4, tone)

    # хвост ветра мерцает: прямой штрих / два боковых
    # Границы полуоткрытые: при 0° центры пикселей лежат на ±0.5, ±1.5…
    if frame == 0:
        wisp = (np.abs(ly) <= 0.5) & (lx > -9.5) & (lx < -6.0)
    else:
        wisp = (np.abs(ly) >= 2.0) & (np.abs(ly) < 3.0) & (lx > -8.5) & (lx < -5.5)
    wtone = np.where(lx > -7.5, 2, 1)
    return compose(body, tone, wisp, wtone)


# ------------------------------------------------------------------ вывод


def build_sheet(cell, frames, render):
    sheet = Image.new("RGBA", (cell * frames, cell * ROWS))
    for row in range(ROWS):
        theta = math.radians(90.0 * row / (ROWS - 1))
        for f in range(frames):
            sheet.paste(render(theta, f), (f * cell, row * cell))
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
        cols = sheet.width // cell
        for row in picks:
            blocks.append([sheet.crop((f * cell, row * cell, (f + 1) * cell, (row + 1) * cell))
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
    projectile = build_sheet(PROJECTILE_CELL, PROJECTILE_FRAMES, projectile_frame)
    wave = build_sheet(WAVE_CELL, WAVE_FRAMES, wave_frame)
    compression = build_sheet(COMPRESSION_CELL, 1, lambda th, _f: compression_frame(th))
    save(projectile, "attacks/wind_projectile/wind_projectile_sheet.png")
    save(wave, "attacks/wind_wave/wind_wave_sheet.png")
    save(compression, "attacks/wind_compression/wind_compression_sheet.png")
    if PREVIEW is not None:
        preview([(projectile, PROJECTILE_CELL), (wave, WAVE_CELL),
                 (compression, COMPRESSION_CELL)], PREVIEW)


if __name__ == "__main__":
    main()
