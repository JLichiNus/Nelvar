"""Building blocks for the Only One's sounds (tools/gen_boss_sfx.py).

Reuses the noise and filter tools of gen_sfx.py and adds what the boss needs
on top: tones (oscillators, bells, FM, Shepard glides), placement of layers in
time, a cheap convolution "space" for the Void's long tails, bit-crushing and
stutter for its glitches. Everything is numpy, seeded and deterministic.
"""

import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from gen_sfx import (  # noqa: E402,F401  (re-exported for the sound modules)
    RATE, seconds, svf, bandpass, pink_noise, lowpass, highpass, finish, wander,
    seamless, glide, whoosh_envelope,
)


# --- time and envelopes ------------------------------------------------------

def silence(duration: float) -> np.ndarray:
    return np.zeros(int(duration * RATE))


def place(total: float, *layers: tuple[float, np.ndarray, float]) -> np.ndarray:
    """Mixes (start seconds, signal, gain) layers into one sound `total` long."""
    out = silence(total)
    for start, signal, gain in layers:
        a = int(start * RATE)
        b = min(out.size, a + signal.size)
        if b > a:
            out[a:b] += gain * signal[: b - a]
    return out


def ramp(t: np.ndarray, start: float, end: float, power: float = 1.0) -> np.ndarray:
    """0 before `start`, 1 after `end`, a curve of `power` between."""
    return np.clip((t - start) / max(end - start, 1e-6), 0.0, 1.0) ** power


def decay(t: np.ndarray, tau: float, start: float = 0.0) -> np.ndarray:
    """Exponential fall from 1 at `start` (0 before it)."""
    return np.where(t >= start, np.exp(-(t - start) / tau), 0.0)


def attack_decay(t: np.ndarray, attack: float, tau: float) -> np.ndarray:
    """A quick rise over `attack` seconds, then an exponential fall."""
    return np.minimum(t / max(attack, 1e-6), 1.0) * np.exp(-np.maximum(t - attack, 0.0) / tau)


def fade(signal: np.ndarray, fade_in: float = 0.005, fade_out: float = 0.02) -> np.ndarray:
    """Short fades at both ends, so a sound never clicks."""
    out = signal.copy()
    a = max(1, int(fade_in * RATE))
    b = max(1, int(fade_out * RATE))
    out[:a] *= np.linspace(0.0, 1.0, a)
    out[-b:] *= np.linspace(1.0, 0.0, b)
    return out


def reverse(signal: np.ndarray) -> np.ndarray:
    return signal[::-1].copy()


def norm(signal: np.ndarray) -> np.ndarray:
    peak = np.max(np.abs(signal))
    return signal / peak if peak > 0 else signal


# --- tones -------------------------------------------------------------------

def phase(freq) -> np.ndarray:
    """Running phase (radians) of a frequency that may change every sample."""
    return 2.0 * np.pi * np.cumsum(np.asarray(freq, dtype=float)) / RATE


def sine(freq, size: int | None = None) -> np.ndarray:
    freq = np.broadcast_to(np.asarray(freq, dtype=float), (size,) if size else np.shape(freq))
    return np.sin(phase(freq))


def saw(freq, size: int | None = None) -> np.ndarray:
    freq = np.broadcast_to(np.asarray(freq, dtype=float), (size,) if size else np.shape(freq))
    p = phase(freq) / (2.0 * np.pi)
    return 2.0 * (p - np.floor(p + 0.5))


def square(freq, size: int | None = None, duty: float = 0.5) -> np.ndarray:
    freq = np.broadcast_to(np.asarray(freq, dtype=float), (size,) if size else np.shape(freq))
    p = (phase(freq) / (2.0 * np.pi)) % 1.0
    return np.where(p < duty, 1.0, -1.0)


def fm(t: np.ndarray, carrier, ratio: float, index) -> np.ndarray:
    """FM tone: a carrier wobbled by a modulator at `ratio` times its frequency.
    A high `index` gives metallic, glassy or growling colours."""
    carrier = np.broadcast_to(np.asarray(carrier, dtype=float), t.shape)
    index = np.broadcast_to(np.asarray(index, dtype=float), t.shape)
    return np.sin(phase(carrier) + index * np.sin(phase(carrier * ratio)))


def bell(t: np.ndarray, freq: float, tau: float = 0.8,
         partials=((1.0, 1.0), (2.76, 0.5), (5.4, 0.25), (8.93, 0.12))) -> np.ndarray:
    """A struck glass / metal tone: inharmonic partials, the high ones dying first."""
    out = np.zeros_like(t)
    for ratio, gain in partials:
        out += gain * np.sin(2.0 * np.pi * freq * ratio * t) * np.exp(-t * ratio ** 0.5 / tau)
    return out * np.minimum(t / 0.002, 1.0)


def shepard(t: np.ndarray, base: float, speed, layers: int = 6, rising: bool = True) -> np.ndarray:
    """A Shepard–Risset glide: octave-spaced tones forever rising (or falling),
    each fading in at the bottom and out at the top. `speed` = octaves/second
    (may change over time: an accelerating spiral)."""
    speed = np.broadcast_to(np.asarray(speed, dtype=float), t.shape)
    travelled = np.cumsum(speed) / RATE * (1.0 if rising else -1.0)
    out = np.zeros_like(t)
    for k in range(layers):
        position = (k + travelled) % layers
        freq = base * 2.0 ** position
        weight = np.sin(np.pi * position / layers) ** 2
        out += weight * np.sin(phase(freq))
    return out / layers


def tremolo(t: np.ndarray, rate, depth: float) -> np.ndarray:
    """1 - depth .. 1, pulsing at `rate` (Hz, may change over time)."""
    rate = np.broadcast_to(np.asarray(rate, dtype=float), t.shape)
    return 1.0 - depth * (0.5 + 0.5 * np.sin(phase(rate)))


# --- colour, space and damage ------------------------------------------------

def noise(size: int, rng: np.random.Generator) -> np.ndarray:
    return rng.uniform(-1.0, 1.0, size)


def crackle(t: np.ndarray, rng: np.random.Generator, density, bright: float = 3500.0) -> np.ndarray:
    """Dry crackling: sparse random clicks (`density` per second, may change
    over time), each a tiny filtered burst."""
    density = np.broadcast_to(np.asarray(density, dtype=float), t.shape)
    clicks = (rng.random(t.size) < density / RATE).astype(float) * rng.uniform(0.3, 1.0, t.size)
    clicks *= np.where(rng.random(t.size) < 0.5, 1.0, -1.0)
    kernel = np.exp(-np.arange(int(0.004 * RATE)) / (0.0008 * RATE))
    body = np.convolve(clicks, kernel)[: t.size]
    return bandpass(body, bright, 0.9)


def convolve(signal: np.ndarray, impulse: np.ndarray) -> np.ndarray:
    size = signal.size + impulse.size - 1
    n = 1 << (size - 1).bit_length()
    out = np.fft.irfft(np.fft.rfft(signal, n) * np.fft.rfft(impulse, n), n)[:size]
    return out


def space(signal: np.ndarray, length: float = 1.8, mix: float = 0.35, dark: float = 2500.0,
          seed: int = 77) -> np.ndarray:
    """A cheap hall of the Void: convolution with decaying, darkened noise.
    Returns the dry sound with its tail (longer than the input by `length`)."""
    rng = np.random.default_rng(seed)
    tail_t = seconds(length)
    impulse = rng.standard_normal(tail_t.size) * np.exp(-tail_t / (length / 5.0))
    impulse = lowpass(impulse, dark)
    impulse[: int(0.012 * RATE)] *= np.linspace(0.0, 1.0, int(0.012 * RATE))
    wet = convolve(signal, impulse)
    wet = norm(wet) * np.max(np.abs(signal))
    dry = np.concatenate([signal, np.zeros(wet.size - signal.size)])
    return (1.0 - mix) * dry + mix * wet


def crush(signal: np.ndarray, bits: int = 6, hold: int = 4) -> np.ndarray:
    """Digital damage: fewer bits and a lower sample rate (sample-and-hold)."""
    held = np.repeat(signal[::hold], hold)[: signal.size]
    levels = 2 ** (bits - 1)
    return np.round(held * levels) / levels


def stutter(signal: np.ndarray, rng: np.random.Generator, slices: int = 8,
            repeat_chance: float = 0.4) -> np.ndarray:
    """Glitch: chops the sound into slices and repeats some of them."""
    size = signal.size // slices
    out = []
    for i in range(slices):
        piece = fade(signal[i * size:(i + 1) * size], 0.001, 0.002)
        out.append(piece)
        if rng.random() < repeat_chance:
            out.append(piece)
    return np.concatenate(out)[: signal.size]


def ring(signal: np.ndarray, freq: float) -> np.ndarray:
    """Ring modulation: metallic, inhuman."""
    return signal * np.sin(2.0 * np.pi * freq * np.arange(signal.size) / RATE)


def sub_thump(t: np.ndarray, start: float = 80.0, end: float = 35.0, tau: float = 0.25) -> np.ndarray:
    """A deep falling sine hit, felt more than heard."""
    freq = end + (start - end) * np.exp(-t / 0.06)
    return np.sin(phase(freq)) * attack_decay(t, 0.004, tau)


def loop(signal: np.ndarray, overlap: float = 0.3) -> np.ndarray:
    """A seamless loop (see gen_sfx.seamless)."""
    return seamless(signal, overlap)
