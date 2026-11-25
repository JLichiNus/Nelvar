"""The Only One's sounds, part A: dashes, gravity wells and the boss itself.
Three variants of every sound (see gen_boss_sfx.py); each variant is a
different idea, not the same sound at another pitch."""

import numpy as np

from boss_sfx_common import (
    RATE, seconds, svf, bandpass, pink_noise, lowpass, highpass, finish, wander,
    place, ramp, decay, attack_decay, fade, reverse, norm, sine, saw, square, fm,
    bell, shepard, tremolo, crackle, space, crush, stutter, ring, sub_thump, loop,
    noise, phase,
)


def rng_for(seed: int, variant: int) -> np.random.Generator:
    return np.random.default_rng(seed * 10 + variant)


def done(sound: np.ndarray, peak_db: float, cutoff: float = 6500.0, seam: float = 0.0) -> np.ndarray:
    """Darkens the top (the Void is never shrill: two gentle low-pass passes)
    and finishes the sound at `peak_db`. With `seam`, the sound becomes a loop
    after all filtering, so the filters cannot leave a click at the seam."""
    sound = highpass(lowpass(lowpass(sound, cutoff), cutoff * 1.3), 30.0)
    if seam > 0.0:
        sound = loop(sound, seam)
    return sound * 10 ** (peak_db / 20.0) / np.max(np.abs(sound))


# --- Dashes ------------------------------------------------------------------

def dash_aim(variant: int) -> np.ndarray:
    """The aim follows the player for ~0.75 s: rising, unsettled."""
    rng = rng_for(100, variant)
    t = seconds(0.8)
    rise = ramp(t, 0.0, 0.75, 1.6)
    if variant == 1:
        # A thin whine climbing through a narrowing band of noise.
        air = bandpass(pink_noise(t.size, rng), 500.0 * 4.0 ** rise, 6.0)
        tone = sine(320.0 * 2.0 ** (rise * 1.5)) * 0.35
        sound = (norm(air) + tone) * (0.2 + 0.8 * rise)
    elif variant == 2:
        # Two detuned saws drifting together: a beating that tightens.
        beat = 9.0 * (1.0 - rise) + 0.5
        sound = saw(180.0 * 1.6 ** rise) + saw(180.0 * 1.6 ** rise + beat)
        sound = lowpass(sound, 1800.0) * (0.15 + 0.85 * rise)
    else:
        # A swarm of tiny ticks speeding up, like something counting down.
        ticks = crackle(t, rng, 30.0 + 400.0 * rise, 2600.0)
        hum = sine(90.0 + 60.0 * rise) * 0.4
        sound = (norm(ticks) + hum) * (0.25 + 0.75 * rise)
    return done(fade(sound, 0.02, 0.03), -6.0)


def dash_lock(variant: int) -> np.ndarray:
    """The aim locks: THE cue to dodge. Short, sharp, unmistakable."""
    rng = rng_for(110, variant)
    t = seconds(0.45)
    click = highpass(noise(t.size, rng), 2500.0) * decay(t, 0.004)
    if variant == 1:
        # A latch clicking shut and a cold glass ping.
        sound = click + 0.6 * bell(t, 1320.0, 0.25)
    elif variant == 2:
        # A low metallic clank with a ringing FM tail.
        sound = click * 0.6 + fm(t, 220.0, 3.5, 4.0 * decay(t, 0.08)) * decay(t, 0.12) \
            + 0.4 * sub_thump(t, 120.0, 60.0, 0.08)
    else:
        # A reversed swell snapping into silence, then a pale double click.
        swell = reverse(bandpass(pink_noise(t.size, rng), 3000.0, 2.0) * decay(t, 0.05))
        sound = place(0.45, (0.0, swell[-int(0.2 * RATE):], 0.8), (0.2, click, 1.0), (0.26, click, 0.6)) \
            + 0.4 * bell(t, 1760.0, 0.15) * ramp(t, 0.2, 0.201)
    return done(fade(sound, 0.001, 0.05), -3.0, 9000.0)


def dash_rush(variant: int) -> np.ndarray:
    """The dash itself: space torn as it rushes through."""
    rng = rng_for(120, variant)
    t = seconds(0.7)
    env = attack_decay(t, 0.03, 0.18)
    if variant == 1:
        # Ripping cloth: noise chopped by fast random gating, falling in pitch.
        rip = bandpass(noise(t.size, rng), 2400.0 * 0.4 ** ramp(t, 0.0, 0.6), 1.5)
        gate = (rng.random(t.size // 240 + 1) > 0.35).repeat(240)[: t.size]
        sound = norm(rip) * (0.5 + 0.5 * lowpass(gate.astype(float), 300.0)) * env \
            + 0.6 * sub_thump(t, 90.0, 40.0, 0.2)
    elif variant == 2:
        # A heavy whoosh passing by (Doppler-like fall) with a dark body.
        whoosh = svf(pink_noise(t.size, rng), 3000.0 * 0.25 ** ramp(t, 0.05, 0.5), 2.5, "band")
        body = saw(110.0 * 0.6 ** ramp(t, 0.0, 0.5)) * 0.3
        sound = (norm(whoosh) + lowpass(body, 600.0)) * env
    else:
        # Crushed and stuttering: the dash tears the picture as it goes.
        tear = norm(bandpass(noise(t.size, rng), 1500.0, 1.0)) * env
        sound = stutter(crush(tear, 5, 6), rng, 12, 0.5) + 0.5 * sub_thump(t, 70.0, 35.0, 0.25)
    return done(fade(sound, 0.002, 0.05), -3.0)


def trail_charge(variant: int) -> np.ndarray:
    """The tear charges for 1 s before it bursts to both sides."""
    rng = rng_for(130, variant)
    t = seconds(1.0)
    rise = ramp(t, 0.0, 1.0, 2.0)
    if variant == 1:
        # Hiss rising and brightening like a fuse.
        sound = norm(bandpass(noise(t.size, rng), 800.0 * 6.0 ** rise, 1.2)) * (0.1 + 0.9 * rise)
    elif variant == 2:
        # Electric buzz: a square wave pulsing faster and faster.
        sound = lowpass(square(70.0 + 50.0 * rise), 2000.0) * tremolo(t, 4.0 + 26.0 * rise, 0.8) \
            * (0.2 + 0.8 * rise)
    else:
        # Inhaled crackle: crackling pulled towards the moment (reversed decay).
        crack = norm(crackle(t, rng, 60.0 + 600.0 * rise, 3000.0))
        sound = crack * (0.15 + 0.85 * rise) + 0.3 * sine(60.0 * 2.0 ** rise) * rise
    return done(fade(sound, 0.02, 0.005), -6.0)


def trail_burst(variant: int) -> np.ndarray:
    """The tear bursts: waves thrown out to both sides."""
    rng = rng_for(140, variant)
    t = seconds(0.9)
    if variant == 1:
        # A double ragged pop: two tearing cracks 60 ms apart.
        pop = norm(bandpass(noise(t.size, rng), 1800.0, 0.8)) * attack_decay(t, 0.002, 0.07)
        sound = place(0.9, (0.0, pop, 1.0), (0.06, pop, 0.8)) + 0.7 * sub_thump(t, 100.0, 40.0, 0.18)
    elif variant == 2:
        # A whip-crack outward: a quick upward sweep and a fizzing tail.
        sweep = norm(svf(noise(t.size, rng), 500.0 * 8.0 ** ramp(t, 0.0, 0.12), 3.0, "band"))
        fizz = crackle(t, rng, 900.0 * decay(t, 0.2), 4000.0)
        sound = sweep * attack_decay(t, 0.005, 0.1) + 0.6 * norm(fizz) * decay(t, 0.3)
    else:
        # A deep "whump" with a glassy shimmer spreading out.
        whump = sub_thump(t, 140.0, 45.0, 0.3)
        shimmer = sum(bell(t, f, 0.3) for f in (880.0, 1175.0, 1568.0)) * 0.25
        sound = whump + shimmer + 0.3 * norm(lowpass(noise(t.size, rng), 900.0)) * decay(t, 0.1)
    return done(fade(space(sound, 0.6, 0.2), 0.001, 0.08), -3.0)


def trail_crackle(variant: int) -> np.ndarray:
    """Open tears (phase III) crackling quietly in the background. Loop."""
    rng = rng_for(150, variant)
    t = seconds(2.6)
    if variant == 1:
        sound = norm(crackle(t, rng, 70.0, 2800.0)) + 0.25 * sine(55.0, t.size)
    elif variant == 2:
        buzz = lowpass(saw(np.full(t.size, 50.0)), 400.0) * (0.6 + 0.4 * wander(t, rng, 2.0))
        sound = norm(buzz) * 0.6 + 0.5 * norm(crackle(t, rng, 25.0, 5000.0))
    else:
        sound = norm(bandpass(pink_noise(t.size, rng), 300.0 * 1.5 ** wander(t, rng, 1.0), 4.0)) \
            + 0.4 * norm(crackle(t, rng, 40.0, 1800.0))
    return done(sound, -9.0, seam=0.4)


# --- Gravity wells -----------------------------------------------------------

def pull_spawn(variant: int) -> np.ndarray:
    """A well opens: the Void breathes in."""
    rng = rng_for(200, variant)
    t = seconds(0.7)
    if variant == 1:
        # A reversed breath of air.
        breath = norm(bandpass(pink_noise(t.size, rng), 900.0, 1.0)) * attack_decay(t, 0.01, 0.2)
        sound = reverse(breath)
    elif variant == 2:
        # A reversed bell swallowed into a thump.
        sound = reverse(bell(t, 440.0, 0.25) + 0.5 * bell(t, 660.0, 0.2)) \
            + place(0.7, (0.62, sub_thump(seconds(0.08), 90.0, 50.0, 0.04), 0.6))
    else:
        # Downward FM swoop: something heavy settling into place.
        sound = fm(t, 300.0 * 0.3 ** ramp(t, 0.0, 0.5), 1.5, 3.0 * decay(t, 0.2)) * attack_decay(t, 0.02, 0.25)
    return done(fade(space(sound, 0.8, 0.25), 0.005, 0.1), -4.0)


def pull_charge(variant: int) -> np.ndarray:
    """A well charging for ~2.4 s: the pull grows, its pulse quickens."""
    rng = rng_for(210, variant)
    t = seconds(2.4)
    k = ramp(t, 0.0, 2.4)
    if variant == 1:
        # Low hum whose wobble speeds up and pitch climbs.
        hum = sine(55.0 * 2.0 ** k) + 0.5 * sine(110.0 * 2.0 ** k)
        swirl = norm(bandpass(pink_noise(t.size, rng), 400.0 * 3.0 ** k, 3.0)) * 0.4
        sound = (hum + swirl) * tremolo(t, 2.0 + 12.0 * k, 0.7) * (0.3 + 0.7 * k)
    elif variant == 2:
        # A vortex of air spinning faster: band sweeping round and round.
        spin = np.sin(phase(1.5 + 9.0 * k * k))
        air = norm(bandpass(pink_noise(t.size, rng), 700.0 * 1.8 ** spin * (1.0 + k), 4.0))
        sound = air * (0.3 + 0.7 * k) + 0.4 * sine(45.0 + 30.0 * k) * k
    else:
        # A rising Shepard swirl: endless climbing, never resolved.
        sound = shepard(t, 60.0, 0.3 + 1.2 * k, 6) * (0.3 + 0.7 * k) \
            + 0.3 * sine(40.0, t.size) * tremolo(t, 3.0 + 10.0 * k, 0.9)
    return done(fade(sound, 0.1, 0.03), -5.0)


def pull_lock(variant: int) -> np.ndarray:
    """The well stops still before bursting: the hum cuts, a high note hangs."""
    rng = rng_for(220, variant)
    t = seconds(0.75)
    if variant == 1:
        # Sudden silence pierced by a thin, trembling tone.
        sound = sine(1975.0 * (1.0 + 0.004 * np.sin(phase(np.full(t.size, 7.0))))) * attack_decay(t, 0.01, 0.4)
    elif variant == 2:
        # A tape-stop: everything slows down and dies into silence.
        stop = saw(140.0 * 0.05 ** ramp(t, 0.0, 0.35)) * (1.0 - ramp(t, 0.0, 0.35))
        sound = lowpass(stop, 1500.0)
    else:
        # A tightening wire: high FM squeal rising slightly, choked off.
        sound = fm(t, 900.0 * 1.2 ** ramp(t, 0.0, 0.7), 2.01, 1.2) * ramp(t, 0.0, 0.05) * (1.0 - ramp(t, 0.6, 0.75)) * 0.3 \
            + 0.3 * norm(highpass(noise(t.size, rng), 6000.0)) * decay(t, 0.02)
    return done(fade(sound, 0.002, 0.03), -6.0)


def pull_burst(variant: int) -> np.ndarray:
    """The well bursts."""
    rng = rng_for(230, variant)
    t = seconds(1.6)
    if variant == 1:
        # Implosion: a short suck-in, then a deep boom.
        suck = reverse(norm(bandpass(noise(int(0.25 * RATE), rng), 1200.0, 1.0)) * decay(seconds(0.25), 0.05))
        boom = sub_thump(t, 110.0, 32.0, 0.5) + 0.5 * norm(lowpass(noise(t.size, rng), 500.0)) * decay(t, 0.25)
        sound = place(1.6, (0.0, suck, 0.6), (0.25, boom, 1.0))
    elif variant == 2:
        # A shattering of glassy space: bright crash over a low hit.
        crash = norm(highpass(noise(t.size, rng), 2000.0)) * attack_decay(t, 0.002, 0.25)
        bells = sum(bell(t, f, 0.5) for f in (523.0, 740.0, 1047.0, 1480.0)) * 0.2
        sound = crash * 0.6 + bells + sub_thump(t, 90.0, 40.0, 0.35)
    else:
        # A crushed digital detonation: the picture breaking.
        hit = norm(bandpass(noise(t.size, rng), 700.0, 0.7)) * attack_decay(t, 0.003, 0.3)
        sound = crush(hit, 4, 10) * 0.7 + sub_thump(t, 80.0, 30.0, 0.5)
    return done(fade(space(sound, 1.4, 0.3), 0.001, 0.2), -2.0)


# --- The boss ----------------------------------------------------------------

def boss_presence(variant: int) -> np.ndarray:
    """A quiet drone around the boss, fading with distance. Loop."""
    rng = rng_for(300, variant)
    t = seconds(4.4)
    if variant == 1:
        # Deep choir-like hum: stacked sines breathing slowly.
        sound = sum(sine(f * (1.0 + 0.003 * wander(t, rng, 0.3))) * g
                    for f, g in ((41.2, 1.0), (61.8, 0.6), (82.4, 0.4), (123.5, 0.2)))
        sound *= 0.8 + 0.2 * wander(t, rng, 0.4)
    elif variant == 2:
        # Wind through a hollow: dark resonant noise moving slowly.
        sound = norm(bandpass(pink_noise(t.size, rng), 180.0 * 1.4 ** wander(t, rng, 0.25), 5.0)) \
            + 0.3 * sine(36.0, t.size)
    else:
        # Electric whisper: a soft detuned buzz with faint glitches.
        buzz = lowpass(saw(np.full(t.size, 55.0)) + saw(np.full(t.size, 55.4)), 500.0)
        sound = norm(buzz) * (0.7 + 0.3 * wander(t, rng, 0.5)) + 0.15 * norm(crackle(t, rng, 6.0, 3000.0))
    return done(sound, -10.0, seam=0.6)


def boss_hit(variant: int) -> np.ndarray:
    """The player's attack lands on the boss (plays often: short, rate-limited)."""
    rng = rng_for(310, variant)
    t = seconds(0.25)
    if variant == 1:
        # Glass crunching: a dense burst of clicks.
        sound = norm(crackle(t, rng, 3000.0 * decay(t, 0.03), 3500.0)) + 0.3 * sub_thump(t, 160.0, 80.0, 0.04)
    elif variant == 2:
        # A dull thud into something hollow, with a tiny ring.
        sound = sub_thump(t, 200.0, 90.0, 0.05) + 0.3 * bell(t, 940.0, 0.06) \
            + 0.4 * norm(lowpass(noise(t.size, rng), 1500.0)) * decay(t, 0.015)
    else:
        # A digital zap: crushed noise flick.
        sound = crush(norm(bandpass(noise(t.size, rng), 2200.0, 1.0)) * decay(t, 0.04), 4, 8)
    return done(fade(sound, 0.001, 0.03), -6.0)


def boss_intro(variant: int) -> np.ndarray:
    """The pillar of light forms the boss (2.6 s), ending in a burst."""
    rng = rng_for(320, variant)
    t = seconds(3.6)
    k = ramp(t, 0.0, 2.6, 2.0)
    before = t < 2.6
    if variant == 1:
        # A choir of sines swelling up an octave, cut by a boom.
        swell = sum(sine(f * 2.0 ** k) for f in (110.0, 165.0, 220.0, 330.0)) * k * before
    elif variant == 2:
        # A Shepard rise with streaming air, cut by a boom.
        swell = (shepard(t, 80.0, 0.6 + 1.5 * k) + 0.4 * norm(bandpass(pink_noise(t.size, rng), 600.0 * 4.0 ** k, 2.0))) * k * before
    else:
        # Reversed thunder: a whole explosion played backwards into the moment.
        boom = norm(lowpass(noise(int(2.6 * RATE), rng), 800.0)) * decay(seconds(2.6), 0.5)
        swell = place(3.6, (0.0, reverse(boom), 1.0)) * before
    hit = place(3.6, (2.6, sub_thump(seconds(1.0), 120.0, 35.0, 0.45), 1.0),
                (2.6, norm(highpass(noise(int(0.5 * RATE), rng), 1500.0)) * decay(seconds(0.5), 0.08), 0.5))
    return done(fade(space(swell * 0.6 + hit, 1.6, 0.3), 0.05, 0.3), -2.0)


def phase_shift(variant: int) -> np.ndarray:
    """A phase breaks: slow motion, the floor cracks, beams of light."""
    rng = rng_for(330, variant)
    t = seconds(2.6)
    crack = norm(crackle(t, rng, 2500.0 * decay(t, 0.4), 2500.0))
    thump = sub_thump(t, 130.0, 30.0, 0.7)
    if variant == 1:
        # A slowed-down shatter (tape slowing) under a pale choir chord.
        chord = sum(sine(f) * decay(t, 1.0) for f in (196.0, 247.0, 294.0, 392.0)) * 0.3
        slowed = norm(bandpass(noise(t.size, rng), 1200.0 * 0.3 ** ramp(t, 0.0, 0.6), 1.0)) * decay(t, 0.4)
        sound = thump + 0.6 * crack + 0.5 * slowed + chord
    elif variant == 2:
        # A colossal glass break with a reversed swell leading into it.
        pre = reverse(norm(bandpass(pink_noise(int(0.6 * RATE), rng), 2000.0, 1.5)) * decay(seconds(0.6), 0.15))
        glass = sum(bell(t, f, 0.9) for f in (311.0, 466.0, 698.0, 932.0, 1397.0)) * 0.25
        sound = place(3.2, (0.0, pre, 0.6), (0.6, thump + glass + 0.7 * crack, 1.0))
    else:
        # A ring-modulated, crushed roar: something inhuman tearing itself apart.
        roar = norm(bandpass(noise(t.size, rng), 400.0, 0.8)) * attack_decay(t, 0.05, 0.6)
        sound = thump + 0.6 * crush(ring(roar, 73.0), 5, 4) + 0.4 * crack
    return done(fade(space(sound, 2.2, 0.35), 0.002, 0.4), -1.5)


def death(variant: int) -> np.ndarray:
    """The Only One dies: everything is sucked in, flashes quicken, it bursts
    into light; a long tail, silence, a faint ring."""
    rng = rng_for(340, variant)
    total = 6.0
    t = seconds(total)
    pull = norm(bandpass(pink_noise(int(1.4 * RATE), rng), 600.0 * 3.0 ** ramp(seconds(1.4), 0.0, 1.4), 1.2)) \
        * ramp(seconds(1.4), 0.0, 1.4, 2.0)
    pops = [0.0, 0.32, 0.6, 0.84, 1.04, 1.2, 1.32]
    flash = sub_thump(seconds(0.3), 160.0, 70.0, 0.06)
    boom_t = seconds(total - 1.4)
    if variant == 1:
        # Deep and solemn: thumps quicken, a vast boom, a choir fading.
        boom = sub_thump(boom_t, 120.0, 28.0, 1.2) + 0.4 * norm(lowpass(noise(boom_t.size, rng), 400.0)) * decay(boom_t, 0.6)
        choir = sum(sine(f) for f in (130.8, 196.0, 261.6, 329.6)) * 0.12 * attack_decay(boom_t, 0.3, 1.4)
        end = boom + choir
    elif variant == 2:
        # Shattering light: bells and glass rain after the burst.
        boom = sub_thump(boom_t, 100.0, 30.0, 0.8)
        glass = sum(bell(boom_t, f, 1.6) for f in (523.0, 659.0, 784.0, 1046.0, 1318.0)) * 0.22
        rain = norm(crackle(boom_t, rng, 800.0 * decay(boom_t, 1.0), 4000.0)) * 0.4
        end = boom + glass + rain
    else:
        # Digital collapse: crushed roar, stutter, then a lone clean tone.
        roar = norm(bandpass(noise(boom_t.size, rng), 300.0, 0.7)) * attack_decay(boom_t, 0.01, 0.8)
        end = sub_thump(boom_t, 110.0, 30.0, 0.9) + 0.6 * stutter(crush(roar, 4, 6), rng, 16, 0.5) \
            + 0.25 * sine(880.0, boom_t.size) * ramp(boom_t, 1.8, 2.2) * decay(boom_t, 1.0, 2.2)
    layers = [(0.0, pull, 0.5)] + [(p, flash, 0.4 + 0.08 * i) for i, p in enumerate(pops)] + [(1.4, end, 1.0)]
    ring_tone = bell(seconds(3.0), 1760.0, 1.2) * 0.12
    sound = place(total, *layers) + place(total, (4.4, ring_tone, 1.0))
    return done(fade(space(sound, 2.5, 0.35)[: int(total * RATE)], 0.02, 0.6), -1.0)


def _entry(group: str, title: str, build, variants: list[str], is_loop: bool = False) -> dict:
    return {"group": group, "title": title, "build": build, "variants": variants, "loop": is_loop}


SOUNDS = {
    "dash_aim": _entry("Рывки", "Прицел ведёт игрока", dash_aim,
                       ["Тонкий вой, сужающийся шум", "Два сходящихся тона, биения стягиваются", "Ускоряющееся тиканье, отсчёт"]),
    "dash_lock": _entry("Рывки", "Фиксация прицела — «уклоняйся!»", dash_lock,
                        ["Щелчок защёлки и стеклянный звон", "Низкий металлический лязг", "Обратный всплеск и двойной щелчок"]),
    "dash_rush": _entry("Рывки", "Сам рывок", dash_rush,
                        ["Рвущаяся ткань", "Тяжёлый пролетающий свист", "Глитч: рваный, заикающийся"]),
    "trail_charge": _entry("Рывки", "Зарядка разрыва (1 с)", trail_charge,
                           ["Шипение, как бикфордов шнур", "Электрический зуд, ускоряется", "Нарастающее потрескивание"]),
    "trail_burst": _entry("Рывки", "Разрыв выбрасывает волну", trail_burst,
                          ["Двойной рваный хлопок", "Хлёсткий удар и шипящий хвост", "Глухой удар со стеклянным мерцанием"]),
    "trail_crackle": _entry("Рывки", "Открытые разрывы (фон III фазы)", trail_crackle,
                            ["Сухое потрескивание с гулом", "Тихое жужжание и искры", "Тёмный шум с треском"], True),
    "pull_spawn": _entry("Притяжение", "Появление вихря", pull_spawn,
                         ["Вдох задом наперёд", "Обратный колокол, проглоченный ударом", "Тяжёлый нисходящий свуп"]),
    "pull_charge": _entry("Притяжение", "Зарядка вихря (2,4 с)", pull_charge,
                          ["Гул, пульс ускоряется и растёт", "Воздушная воронка раскручивается", "Бесконечный подъём (Шепард)"]),
    "pull_lock": _entry("Притяжение", "Остановка перед взрывом", pull_lock,
                        ["Тишина и тонкий дрожащий тон", "Остановка плёнки, затухание в тишину", "Натянутая струна, обрыв"]),
    "pull_burst": _entry("Притяжение", "Взрыв вихря", pull_burst,
                         ["Имплозия: втягивание и глубокий бум", "Разбитое стекло пространства", "Цифровой взрыв, ломается картинка"]),
    "boss_presence": _entry("Сам босс", "Присутствие (фон рядом с боссом)", boss_presence,
                            ["Глубокий хоровой гул", "Ветер в пустоте", "Электрический шёпот"], True),
    "boss_hit": _entry("Сам босс", "Удар по боссу", boss_hit,
                       ["Хруст стекла", "Глухой удар в пустоту", "Цифровой «зап»"]),
    "boss_intro": _entry("Сам босс", "Появление из столба света", boss_intro,
                         ["Хор поднимается на октаву, удар", "Подъём Шепарда с потоком воздуха", "Взрыв задом наперёд"]),
    "phase_shift": _entry("Сам босс", "Смена фазы", phase_shift,
                          ["Замедленный разлом и бледный аккорд", "Огромное стекло, обратный всплеск", "Нечеловеческий рёв, рвётся"]),
    "death": _entry("Сам босс", "Смерть", death,
                    ["Торжественно: удары, бум, хор", "Ливень света и стекла", "Цифровой распад, одинокий тон"]),
}
