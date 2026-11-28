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


def reed_tone(t: np.ndarray, frequency: np.ndarray) -> np.ndarray:
    """Breathy pipe tone with a quiet woody second harmonic."""
    phase = 2.0 * np.pi * np.cumsum(frequency) / RATE
    return np.sin(phase) + 0.16 * np.sin(2.0 * phase)


def soft_edges(signal: np.ndarray, attack: float, release: float) -> np.ndarray:
    """Fade the finished sound to exact silence at both edges."""
    n = signal.size
    a, b = int(attack * RATE), int(release * RATE)
    signal[:a] *= np.sin(np.linspace(0.0, np.pi / 2, a)) ** 2
    signal[n-b:] *= np.cos(np.linspace(0.0, np.pi / 2, b)) ** 2
    return signal


def whistler_inhale(variant: int) -> np.ndarray:
    """A rising hiss and strained pipe whistle warn of the incoming breath."""
    rng = np.random.default_rng(15000 + variant)
    t = seconds(0.9)
    freq = glide(t, [(0, 700), (0.9, 1000)]) * (1 + 0.012 * (t / 0.9) * np.sin(2 * np.pi * 6 * t))
    air = bandpass(pink_noise(t.size, rng), glide(t, [(0, 1000), (0.9, 2800)]), 1.1)
    air /= np.max(np.abs(air))
    sound = (0.55 * air + 0.48 * reed_tone(t, freq)) * (0.12 + 0.88 * (t / 0.9) ** 1.4)
    return soft_edges(finish(sound, -4.0), 0.02, 0.04)


def whistler_blow(variant: int) -> np.ndarray:
    """A breathy falling pipe note with tiny bubbles forming in the puff."""
    rng = np.random.default_rng(16000 + variant)
    t = seconds(0.45)
    air = bandpass(pink_noise(t.size, rng), 1500, 0.8)
    air /= np.max(np.abs(air))
    freq = glide(t, [(0, 900 + 25 * (variant - 2)), (0.45, 600)])
    sound = (0.7 * air + 0.5 * reed_tone(t, freq)) * whoosh_envelope(t, 0.01)
    for start in (0.09, 0.15, 0.22):
        x = np.maximum(t - start - 0.005 * variant, 0)
        sound += 0.13 * np.sin(2 * np.pi * (1800 * x - 9000 * x * x)) * np.exp(-x / 0.012) * (t >= start + 0.005 * variant)
    return soft_edges(finish(sound, -4.0), 0.003, 0.025)


def whistler_toot(variant: int) -> np.ndarray:
    """One breathy reed note; three pitches make a little sequential trill."""
    rng = np.random.default_rng(17000 + variant)
    t = seconds(0.2)
    air = bandpass(pink_noise(t.size, rng), 1500, 1.0)
    air /= np.max(np.abs(air))
    freq = np.full_like(t, [760, 850, 960][variant - 1])
    sound = (0.3 * air + reed_tone(t, freq)) * whoosh_envelope(t, 0.025)
    return soft_edges(finish(sound, -5.0), 0.005, 0.02)


def whistler_hurt(variant: int) -> np.ndarray:
    """A small hollow reed knock and a fleeting upward squeak."""
    rng = np.random.default_rng(18000 + variant)
    t = seconds(0.14)
    knock = bandpass(pink_noise(t.size, rng), 450 + 45 * variant, 5.0)
    knock /= np.max(np.abs(knock))
    squeak = reed_tone(t, glide(t, [(0, 800), (0.1, 1200)]))
    sound = knock * np.exp(-t / 0.06) + 0.2 * squeak * np.exp(-t / 0.035)
    return soft_edges(finish(sound, -6.0), 0.006, 0.025)


def whistler_death(variant: int) -> np.ndarray:
    """The bag deflates with a wavering falling whistle and a dark last puff."""
    rng = np.random.default_rng(19000 + variant)
    t = seconds(0.8)
    air = bandpass(pink_noise(t.size, rng), glide(t, [(0, 2200), (0.8, 400)]), 0.8)
    air /= np.max(np.abs(air))
    freq = glide(t, [(0, 800), (0.8, 250)]) * (1 + 0.035 * wander(t, rng, 9))
    sound = (0.75 * air + 0.48 * reed_tone(t, freq)) * whoosh_envelope(t, 0.035)
    puff = svf(pink_noise(t.size, rng), 450, 0.7, "low")
    puff /= np.max(np.abs(puff))
    x = np.maximum(t - 0.62, 0)
    sound += 0.3 * puff * np.sin(np.pi * np.minimum(x / 0.18, 1)) ** 2
    return soft_edges(finish(sound, -4.0), 0.01, 0.03)


def bubble_pop(variant: int) -> np.ndarray:
    """A soft descending bubble plop followed by little droplets."""
    rng = np.random.default_rng(20000 + variant)
    t = seconds(0.12)
    freq = glide(t, [(0, 2500), (0.025, 1200), (0.12, 1100)])
    sound = reed_tone(t, freq) * np.exp(-t / 0.012)
    for start in (0.038, 0.058, 0.078):
        x = np.maximum(t - start - rng.uniform(0, 0.004), 0)
        sound += 0.17 * np.sin(2 * np.pi * (2000 + 300 * rng.random()) * x) * np.exp(-x / 0.004) * (x > 0)
    sound = soft_edges(finish(sound, -6.0), 0.002, 0.015)
    return sound * (10 ** (-6.0 / 20.0) / np.max(np.abs(sound)))


def bubble_deflect(variant: int) -> np.ndarray:
    """A buoyant upward rubbery chirp with a light breath of air."""
    rng = np.random.default_rng(21000 + variant)
    t = seconds(0.25)
    freq = glide(t, [(0, 500), (0.18, 1400 + 40 * variant), (0.25, 1300)])
    air = bandpass(pink_noise(t.size, rng), 1800, 1.0)
    air /= np.max(np.abs(air))
    sound = (reed_tone(t, freq) + 0.2 * air) * whoosh_envelope(t, 0.04)
    return soft_edges(finish(sound, -4.0), 0.005, 0.025)


def runner_step(variant: int) -> np.ndarray:
    """A tiny dry footfall on earth and grass."""
    rng = np.random.default_rng(22000 + variant)
    t = seconds(0.07)
    noise = bandpass(rng.standard_normal(t.size), 2600 + 200 * variant, 1.2)
    sound = noise * np.exp(-t / 0.012) + 0.07 * np.sin(2 * np.pi * 200 * t) * np.exp(-t / 0.014)
    sound = soft_edges(finish(sound, -6.0), 0.002, 0.01)
    return sound * (10 ** (-6.0 / 20.0) / np.max(np.abs(sound)))


def runner_chirp(variant: int) -> np.ndarray:
    """Two quick chirps lead into a rising, trilling warning."""
    t = seconds(0.6)
    sound = np.zeros_like(t)
    for start in (0.015, 0.095):
        x = t - start
        u = np.clip(x / 0.038, 0, 1)
        sound += 0.55 * np.sin(2 * np.pi * (2500 * x + 1500 * x * u / 2)) * np.sin(np.pi * u) ** 2 * ((x >= 0) & (x < 0.038))
    x = np.maximum(t - 0.18, 0)
    freq = 2700 + 1100 * x / 0.42 + 100 * np.sin(2 * np.pi * 25 * x) + 65 * (variant - 1)
    env = np.clip(x / 0.035, 0, 1) * (0.35 + 0.65 * x / 0.42)
    sound += np.sin(2 * np.pi * np.cumsum(freq) / RATE) * env * (t >= 0.18)
    return soft_edges(finish(sound, -4.0), 0.003, 0.03)


def runner_dash(variant: int) -> np.ndarray:
    """A short airy burst carries a fading flutter of wings."""
    rng = np.random.default_rng(23000 + variant)
    t = seconds(0.45)
    noise = rng.standard_normal(t.size)
    air = bandpass(noise, glide(t, [(0, 500), (0.04, 4200), (0.45, 1000)]), 0.8)
    flutter = bandpass(rng.standard_normal(t.size), 1100 + 100 * variant, 0.9)
    pulses = np.maximum(0, np.sin(2 * np.pi * 20 * t)) ** 2 * np.exp(-t / 0.16)
    sound = 0.6 * air * whoosh_envelope(t, 0.018) + flutter * pulses
    return soft_edges(finish(sound, -4.5), 0.003, 0.025)


def runner_skid(variant: int) -> np.ndarray:
    """Rough little claws scrape the ground as their pitch falls."""
    rng = np.random.default_rng(24000 + variant)
    t = seconds(0.35)
    noise = bandpass(rng.standard_normal(t.size), glide(t, [(0, 3000 + 100 * variant), (0.35, 1500)]), 1.4)
    rough = 0.55 + 0.45 * np.sin(2 * np.pi * (45 + 3 * variant) * t)
    sound = noise * rough * (1 - t / 0.35) ** 0.7
    return soft_edges(finish(sound, -5.0), 0.004, 0.025)


def runner_bonk(variant: int) -> np.ndarray:
    """A hollow wooden bump gives way to three dizzy descending tweets."""
    rng = np.random.default_rng(25000 + variant)
    t = seconds(1.0)
    sound = np.sin(2 * np.pi * (165 + 20 * variant) * t) * np.exp(-t / 0.055)
    sound += 0.4 * bandpass(rng.standard_normal(t.size), 850, 3.0) * np.exp(-t / 0.025)
    for start in (0.22, 0.45, 0.68):
        x = t - start
        u = np.clip(x / 0.15, 0, 1)
        freq = 2800 - 900 * u + 70 * np.sin(2 * np.pi * 9 * x) + 70 * variant
        sound += 0.22 * np.sin(2 * np.pi * np.cumsum(freq) / RATE) * np.sin(np.pi * u) ** 2 * ((x >= 0) & (x < 0.15))
    return soft_edges(finish(sound, -4.5), 0.003, 0.025)


def runner_hurt(variant: int) -> np.ndarray:
    """A brief, quiet upward and downward bird squeak."""
    rng = np.random.default_rng(26000 + variant)
    t = seconds(0.12)
    freq = glide(t, [(0, 2100 + 80 * variant), (0.045, 3200), (0.12, 2300)])
    sound = (np.sin(2 * np.pi * np.cumsum(freq) / RATE) + 0.07 * rng.standard_normal(t.size)) * whoosh_envelope(t, 0.012)
    return soft_edges(finish(sound, -6.0), 0.003, 0.02)


def runner_death(variant: int) -> np.ndarray:
    """A falling comic squeal dissolves into a soft feather puff."""
    rng = np.random.default_rng(27000 + variant)
    t = seconds(0.6)
    freq = glide(t, [(0, 3800 + 100 * variant), (0.12, 1800), (0.6, 1800)])
    squeal = np.sin(2 * np.pi * np.cumsum(freq) / RATE) * np.sin(np.pi * np.clip(t / 0.12, 0, 1)) ** 2
    x = np.maximum(t - 0.08, 0)
    puff = bandpass(pink_noise(t.size, rng), glide(t, [(0, 2600), (0.6, 700)]), 0.8)
    sound = squeal + 0.7 * puff * np.clip(x / 0.04, 0, 1) * np.exp(-x / 0.18) * (t >= 0.08)
    return soft_edges(finish(sound, -4.5), 0.003, 0.04)


# --- the giant forest (Земля 2) -----------------------------------------------

def flytrap_click(variant: int) -> np.ndarray:
    """A flytrap's warning: its hairs bristle, a dry rattle of quick clicks that
    speeds up over the 0.45 s before it snaps."""
    rng = np.random.default_rng(30000 + variant)
    t = seconds(0.45)
    sound = np.zeros(t.size)
    at = 0.0
    gap = 0.07
    while at < 0.43:
        x = np.maximum(t - at, 0)
        tick = bandpass(rng.standard_normal(t.size), 3200 + 400 * rng.random(), 2.5)
        sound += tick * np.exp(-x / 0.004) * (t >= at) * (0.5 + at)
        at += gap
        gap = max(0.025, gap * 0.82)
    return soft_edges(finish(sound, -8.0), 0.002, 0.02)


def flytrap_snap(variant: int) -> np.ndarray:
    """The flytrap snaps shut: a wet, leathery clap with a short thump."""
    rng = np.random.default_rng(31000 + variant)
    t = seconds(0.22)
    clap = bandpass(rng.standard_normal(t.size), glide(t, [(0, 1800 + 200 * variant), (0.22, 600)]), 1.2)
    thump = np.sin(2 * np.pi * np.cumsum(glide(t, [(0, 180), (0.22, 70)])) / RATE)
    sound = clap * np.exp(-t / 0.03) + 0.8 * thump * np.exp(-t / 0.05)
    return soft_edges(finish(sound, -3.0, drive=1.5), 0.001, 0.03)


def acorn_rustle(variant: int) -> np.ndarray:
    """Up in the crown something knocks through the leaves: a rustle swelling over
    the 1.1 s before an acorn lands."""
    rng = np.random.default_rng(32000 + variant)
    t = seconds(1.1)
    leaves = highpass(bandpass(pink_noise(t.size, rng), 4200, 0.7), 1500)
    leaves /= np.max(np.abs(leaves))
    flutter = 0.5 + 0.5 * np.abs(wander(t, rng, 14.0))
    sound = leaves * flutter * (t / 1.1) ** 1.6
    return soft_edges(finish(sound, -12.0), 0.05, 0.03)


def acorn_thud(variant: int) -> np.ndarray:
    """An acorn the size of a boulder hits the ground: a dull wooden knock."""
    rng = np.random.default_rng(33000 + variant)
    t = seconds(0.35)
    body = np.sin(2 * np.pi * np.cumsum(glide(t, [(0, 140 + 10 * variant), (0.35, 55)])) / RATE)
    knock = bandpass(rng.standard_normal(t.size), 900, 2.0)
    dirt = bandpass(pink_noise(t.size, rng), 2400, 0.8)
    sound = body * np.exp(-t / 0.09) + 0.5 * knock * np.exp(-t / 0.02) + 0.25 * dirt * np.exp(-t / 0.12)
    return soft_edges(finish(sound, -3.0, drive=1.2), 0.001, 0.05)


def branch_crack(_variant: int) -> np.ndarray:
    """A branch breaks off far above: wood creaks for over a second, then cracks."""
    rng = np.random.default_rng(34000)
    t = seconds(1.6)
    creak_freq = 90 + 40 * wander(t, rng, 3.0)
    creak = np.sign(np.sin(2 * np.pi * np.cumsum(creak_freq) / RATE)) * bandpass(rng.standard_normal(t.size), 700, 1.5)
    creak *= np.clip(t / 1.3, 0, 1) * (t < 1.35)
    x = np.maximum(t - 1.35, 0)
    crack = bandpass(rng.standard_normal(t.size), 2200, 0.9) * np.exp(-x / 0.06) * (t >= 1.35)
    sound = 0.35 * creak + crack
    return soft_edges(finish(sound, -4.0), 0.02, 0.05)


def puffball_pop(variant: int) -> np.ndarray:
    """A puffball bursts: a soft papery pop and the hiss of its spores."""
    rng = np.random.default_rng(35000 + variant)
    t = seconds(0.6)
    pop = bandpass(rng.standard_normal(t.size), 600 + 100 * variant, 1.5) * np.exp(-t / 0.015)
    hiss = bandpass(pink_noise(t.size, rng), glide(t, [(0, 3000), (0.6, 1400)]), 0.8)
    hiss /= np.max(np.abs(hiss))
    sound = pop + 0.45 * hiss * np.clip(t / 0.03, 0, 1) * np.exp(-t / 0.2)
    return soft_edges(finish(sound, -5.0), 0.002, 0.08)


def earth_crumble(variant: int) -> np.ndarray:
    """Loose earth starts to give: soil trickling, a few small clods."""
    rng = np.random.default_rng(36000 + variant)
    t = seconds(0.5)
    trickle = bandpass(rng.standard_normal(t.size), 1800, 1.0) * (0.4 + 0.6 * np.abs(wander(t, rng, 30.0)))
    sound = trickle * np.clip(t / 0.1, 0, 1)
    for start in rng.uniform(0.05, 0.45, 5):
        x = np.maximum(t - start, 0)
        sound += 0.8 * bandpass(rng.standard_normal(t.size), 500, 2.0) * np.exp(-x / 0.01) * (t >= start)
    return soft_edges(finish(sound, -9.0), 0.01, 0.06)


# name -> (builder, variants); 0 variants = a single file <name>.wav.
SOUNDS = {
    "runner_step": (runner_step, 4),
    "runner_chirp": (runner_chirp, 2),
    "runner_dash": (runner_dash, 2),
    "runner_skid": (runner_skid, 2),
    "runner_bonk": (runner_bonk, 2),
    "runner_hurt": (runner_hurt, 3),
    "runner_death": (runner_death, 2),

    "whistler_inhale": (whistler_inhale, 2),
    "whistler_blow": (whistler_blow, 3),
    "whistler_toot": (whistler_toot, 3),
    "whistler_hurt": (whistler_hurt, 3),
    "whistler_death": (whistler_death, 2),
    "bubble_pop": (bubble_pop, 3),
    "bubble_deflect": (bubble_deflect, 2),

    "wind": (wind, 0),
    "wind_wave": (wind_wave, 3),
    "compression_start": (compression_start, 2),
    "compression_hold": (compression_hold, 0),
    "flight_lift": (flight_lift, 2),
    "flight_air": (flight_air, 0),
    "flight_land": (flight_land, 2),

    "flytrap_click": (flytrap_click, 2),
    "flytrap_snap": (flytrap_snap, 2),
    "acorn_rustle": (acorn_rustle, 2),
    "acorn_thud": (acorn_thud, 2),
    "branch_crack": (branch_crack, 0),
    "puffball_pop": (puffball_pop, 2),
    "earth_crumble": (earth_crumble, 2),
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
