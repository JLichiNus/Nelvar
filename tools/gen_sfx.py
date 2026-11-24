#!/usr/bin/env python3
"""Synthesises Nelvar's sound effects into assets/audio/sfx/.

Every sound is built from a few layers of filtered noise, so it can be tuned
by numbers and regenerated the same way every time (fixed seeds). A sound
with variants is written as <name>_<n>.wav, a single one as <name>.wav.

Run from the project root:  python3 tools/gen_sfx.py [name ...]
Needs numpy only.
"""

import sys
import wave
from pathlib import Path

import numpy as np

RATE = 48000
OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx"


# --- building blocks ---------------------------------------------------------

def seconds(duration: float) -> np.ndarray:
    return np.arange(int(duration * RATE)) / RATE


def svf(signal: np.ndarray, cutoff, q: float, mode: str) -> np.ndarray:
    """State-variable filter ("low", "band" or "high"); `cutoff` may be a
    number or a per-sample array, so the filter can move during the sound."""
    cutoff = np.broadcast_to(np.asarray(cutoff, dtype=float), signal.shape)
    coeff = 2.0 * np.sin(np.pi * np.minimum(cutoff, RATE / 6.0) / RATE)
    damping = 1.0 / q
    low = band = 0.0
    out = np.empty_like(signal)
    for i, x in enumerate(signal):
        f = coeff[i]
        high = x - low - damping * band
        band += f * high
        low += f * band
        out[i] = low if mode == "low" else band if mode == "band" else high
    return out


def bandpass(signal: np.ndarray, centre, q: float) -> np.ndarray:
    return svf(signal, centre, q, "band")


def pink_noise(size: int, rng: np.random.Generator) -> np.ndarray:
    """Noise with equal energy per octave: softer and "airier" than white."""
    spectrum = np.fft.rfft(rng.standard_normal(size))
    freqs = np.fft.rfftfreq(size, 1.0 / RATE)
    spectrum /= np.sqrt(np.maximum(freqs, 20.0))
    noise = np.fft.irfft(spectrum, size)
    return noise / np.max(np.abs(noise))


def lowpass(signal: np.ndarray, cutoff: float) -> np.ndarray:
    a = np.exp(-2.0 * np.pi * cutoff / RATE)
    out = np.empty_like(signal)
    y = 0.0
    for i, x in enumerate(signal):
        y = (1.0 - a) * x + a * y
        out[i] = y
    return out


def highpass(signal: np.ndarray, cutoff: float) -> np.ndarray:
    return signal - lowpass(signal, cutoff)


def finish(signal: np.ndarray, peak_db: float, drive: float = 0.0) -> np.ndarray:
    """Optional soft saturation (`drive` > 0 roughens the sound, keep it off
    for air), DC removal and normalisation to `peak_db`."""
    if drive > 0.0:
        signal = np.tanh(drive * signal / np.max(np.abs(signal)))
    signal = highpass(signal, 30.0)
    signal *= 10 ** (peak_db / 20.0) / np.max(np.abs(signal))
    return signal


def write(name: str, signal: np.ndarray) -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    data = np.round(np.clip(signal, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(str(OUT / f"{name}.wav"), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(data.tobytes())


# --- sounds ------------------------------------------------------------------

def wander(t: np.ndarray, rng: np.random.Generator, rate: float) -> np.ndarray:
    """Smooth random curve in -1..1 that drifts about `rate` times a second."""
    curve = lowpass(lowpass(lowpass(rng.standard_normal(t.size), rate), rate), rate)
    curve -= curve.mean()
    return curve / np.max(np.abs(curve))


def seamless(signal: np.ndarray, overlap: float) -> np.ndarray:
    """Turns a sound into a loop without a seam: its last `overlap` seconds
    are cross-faded (equal power) into its beginning and then cut off."""
    fade = int(overlap * RATE)
    body = signal[:-fade].copy()
    ramp = np.linspace(0.0, 0.5 * np.pi, fade)
    body[:fade] = signal[:fade] * np.sin(ramp) + signal[-fade:] * np.cos(ramp)
    return body


def wind(_variant: int) -> np.ndarray:
    """LMB: plain wind, looped (6 s).

    Shots have no sound of their own: every shot feeds this wind and it dies
    down without them (player.gd), so a tap is a small puff and held LMB is
    one steady wind instead of a rattle of separate sounds.

    Two layers of pink noise: a soft low-passed bed and a gently resonant
    band that drifts slowly up and down — the faint "howl" that makes noise
    read as wind. Brightness and loudness drift only a little and slowly, so
    the wind stays smooth; nothing in it ever strikes.
    """
    rng = np.random.default_rng(8000)
    t = seconds(6.8)
    bed = svf(pink_noise(t.size, rng), 1300.0 * 1.2 ** wander(t, rng, 0.2), 0.6, "low")
    bed /= np.max(np.abs(bed))
    howl = bandpass(pink_noise(t.size, rng), 650.0 * 1.35 ** wander(t, rng, 0.15), 1.6)
    howl /= np.max(np.abs(howl))
    air = highpass(bed + 0.35 * howl, 120.0)
    air *= 1.0 + 0.1 * wander(t, rng, 0.3)
    return finish(seamless(air, 0.8), -3.0)


def glide(t: np.ndarray, points: list[tuple[float, float]]) -> np.ndarray:
    """A value moving exponentially through (time, value) points."""
    times = np.array([p[0] for p in points])
    logs = np.log([p[1] for p in points])
    return np.exp(np.interp(t, times, logs))


def whoosh_envelope(t: np.ndarray, peak: float) -> np.ndarray:
    """Smooth everywhere: swells in (sin²) to its top at `peak` seconds, then
    sinks along a soft cosine curve to exact silence at the end."""
    env = np.empty_like(t)
    rise = t < peak
    env[rise] = np.sin(0.5 * np.pi * t[rise] / peak) ** 2
    fall = (t[~rise] - peak) / (t[-1] - peak)
    env[~rise] = (0.5 + 0.5 * np.cos(np.pi * fall)) ** 1.6
    return env


def wind_wave(variant: int) -> np.ndarray:
    """RMB: the wave — one big gust, "vuu-uh", that rushes ahead with it.

    The same wind as the LMB (pink noise bed plus a soft howl band) but
    pushed: it swells in over ~90 ms as the wave is thrown, its brightness
    flares while the wave flies (0.55 s) and sinks as the wave spreads and
    fades, with a soft low rush under it for weight. No strike, no tone.
    The wave comes every few seconds, so three variants with a small pitch
    spread are enough.
    """
    rng = np.random.default_rng(9000 + variant)
    jitter = lambda spread: 1.0 + rng.uniform(-spread, spread)
    t = seconds(0.95)
    flare = 2400.0 * jitter(0.1)
    cutoff = glide(t, [(0.0, 500.0), (0.12 * jitter(0.15), flare), (0.55, 1100.0), (0.95, 450.0)])
    bed = svf(pink_noise(t.size, rng), cutoff, 0.7, "low")
    bed /= np.max(np.abs(bed))
    howl = bandpass(pink_noise(t.size, rng), cutoff * 0.45, 1.6)
    howl /= np.max(np.abs(howl))
    rush = svf(pink_noise(t.size, rng), 260.0, 0.7, "low")
    rush /= np.max(np.abs(rush))
    air = highpass(bed + 0.35 * howl + 0.3 * rush, 70.0)
    air *= whoosh_envelope(t, 0.09 * jitter(0.15)) * (1.0 + 0.08 * wander(t, rng, 4.0))
    return finish(air, -3.0)


# The compression (R): waves converge on the target for this long, then strike.
COMPRESSION_APPROACH = 0.3
# The hold loop throbs this many times a second, in step with the visual
# pulse of the squeezing waves (wind_compression.gd: pulse_frequency).
COMPRESSION_PULSE = 4.0


def compression_start(variant: int) -> np.ndarray:
    """R, part one: the air rushes in from both sides and strikes.

    A whoosh played "backwards": it swells and brightens faster and faster
    while the waves converge (COMPRESSION_APPROACH), and at the moment they
    meet it turns into a soft, dense "whumpf" — air packed tight, low and
    round, with no click (it still swells in over ~12 ms).
    """
    rng = np.random.default_rng(10000 + variant)
    jitter = lambda spread: 1.0 + rng.uniform(-spread, spread)
    t = seconds(0.6)
    hit = COMPRESSION_APPROACH
    approach = np.clip(t / hit, 0.0, 1.0)
    cutoff = np.where(t < hit, 450.0 * (2300.0 * jitter(0.1) / 450.0) ** (approach ** 2), 2300.0)
    rush = svf(pink_noise(t.size, rng), cutoff, 0.9, "low")
    rush /= np.max(np.abs(rush))
    # Swells in like the squared approach, gone shortly after the strike.
    rush_env = np.where(t < hit, approach ** 2.2, np.exp(-(t - hit) / 0.035))
    thud_cutoff = glide(t, [(0.0, 900.0), (hit, 900.0), (0.6, 160.0)])
    thud = svf(pink_noise(t.size, rng), thud_cutoff, 0.8, "low")
    thud /= np.max(np.abs(thud))
    after = np.maximum(t - hit, 0.0)
    thud_env = np.where(t < hit, 0.0, np.sin(0.5 * np.pi * np.minimum(after / 0.012, 1.0)) ** 2
                        * np.exp(-after / 0.11))
    sound = 0.75 * rush * rush_env + thud * thud_env
    end = t > t[-1] - 0.05
    sound[end] *= 0.5 + 0.5 * np.cos(np.pi * (t[end] - (t[-1] - 0.05)) / 0.05)
    return finish(highpass(sound, 60.0), -3.0)


def compression_hold(_variant: int) -> np.ndarray:
    """R, part two: the target held and squeezed — a tight, swirling wind
    under pressure, looped (2 s). It throbs softly with the waves'
    pulse; the game raises its pitch over the squeeze, so the pressure
    builds, and fades it out when the squeeze ends.
    """
    rng = np.random.default_rng(11000)
    loop = 2.0
    overlap = 0.5
    t = seconds(loop + overlap)
    swirl = bandpass(pink_noise(t.size, rng), 900.0 * 1.25 ** wander(t, rng, 1.5), 2.4)
    swirl /= np.max(np.abs(swirl))
    press = svf(pink_noise(t.size, rng), 230.0, 0.8, "low")
    press /= np.max(np.abs(press))
    # Whole pulses fit the loop, so the throb runs on across the seam.
    throb = 1.0 + 0.15 * np.sin(2.0 * np.pi * COMPRESSION_PULSE * t)
    sound = highpass((swirl + 0.5 * press) * throb, 70.0)
    return finish(seamless(sound, overlap), -3.0)


def flight_lift(variant: int) -> np.ndarray:
    """Shift, take-off: a soft upward gust, "fyu-uu" — air pushed down as the
    body rises. Swells in over ~70 ms while it brightens (rising), then
    sinks into the flight stream that follows."""
    rng = np.random.default_rng(12000 + variant)
    jitter = lambda spread: 1.0 + rng.uniform(-spread, spread)
    t = seconds(0.5)
    cutoff = glide(t, [(0.0, 600.0), (0.12, 2600.0 * jitter(0.1)), (0.5, 1400.0)])
    air = svf(pink_noise(t.size, rng), cutoff, 0.9, "low")
    air /= np.max(np.abs(air))
    lift = bandpass(pink_noise(t.size, rng), cutoff * 0.5, 2.0)
    lift /= np.max(np.abs(lift))
    sound = highpass(air + 0.3 * lift, 150.0) * whoosh_envelope(t, 0.07 * jitter(0.15))
    return finish(sound, -3.0)


def flight_air(_variant: int) -> np.ndarray:
    """Shift, in flight: air rushing past the body, looped (4 s). Brighter
    and more open than the LMB wind (no howl, a lighter low end), so the two
    can play together without blending into one. The game makes it louder
    and a touch higher the faster the player flies."""
    rng = np.random.default_rng(13000)
    t = seconds(4.6)
    rush = svf(pink_noise(t.size, rng), 2300.0 * 1.2 ** wander(t, rng, 0.4), 0.7, "low")
    rush /= np.max(np.abs(rush))
    flutter = bandpass(pink_noise(t.size, rng), 1600.0 * 1.3 ** wander(t, rng, 0.6), 1.2)
    flutter /= np.max(np.abs(flutter))
    sound = highpass(rush + 0.3 * flutter, 300.0) * (1.0 + 0.08 * wander(t, rng, 0.8))
    return finish(seamless(sound, 0.6), -3.0)


def flight_land(variant: int) -> np.ndarray:
    """Shift, landing: the rush sinks and darkens as the body settles, ending
    in a soft low "pf" of air pressed against the ground — no thump: it
    swells in over ~15 ms and stays low and round."""
    rng = np.random.default_rng(14000 + variant)
    jitter = lambda spread: 1.0 + rng.uniform(-spread, spread)
    t = seconds(0.45)
    cutoff = glide(t, [(0.0, 1800.0 * jitter(0.1)), (0.12, 700.0), (0.45, 250.0)])
    settle = svf(pink_noise(t.size, rng), cutoff, 0.8, "low")
    settle /= np.max(np.abs(settle))
    puff = svf(pink_noise(t.size, rng), 300.0, 0.7, "low")
    puff /= np.max(np.abs(puff))
    landed = np.maximum(t - 0.1, 0.0)
    puff_env = np.sin(0.5 * np.pi * np.minimum(landed / 0.015, 1.0)) ** 2 * np.exp(-landed / 0.07)
    puff_env[t < 0.1] = 0.0
    sound = settle * whoosh_envelope(t, 0.03) + 0.5 * puff * puff_env
    end = t > t[-1] - 0.04
    sound[end] *= 0.5 + 0.5 * np.cos(np.pi * (t[end] - (t[-1] - 0.04)) / 0.04)
    return finish(highpass(sound, 60.0), -3.0)


# name -> (builder, variants); 0 variants = a single file <name>.wav.
SOUNDS = {
    "wind": (wind, 0),
    "wind_wave": (wind_wave, 3),
    "compression_start": (compression_start, 2),
    "compression_hold": (compression_hold, 0),
    "flight_lift": (flight_lift, 2),
    "flight_air": (flight_air, 0),
    "flight_land": (flight_land, 2),
}


def main(names: list[str]) -> None:
    for name in names or SOUNDS:
        build, variants = SOUNDS[name]
        if variants == 0:
            write(name, build(0))
        for variant in range(1, variants + 1):
            write(f"{name}_{variant}", build(variant))
        print(f"{name}: {max(variants, 1)} file(s) -> {OUT}")


if __name__ == "__main__":
    main(sys.argv[1:])
