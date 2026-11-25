"""Procedural sounds for the Only One's rifts, collapse, shards and squeeze."""

import numpy as np

from boss_sfx_common import (
    RATE, attack_decay, bandpass, bell, crackle, crush, decay, fade, finish,
    fm, glide, loop, lowpass, norm, pink_noise, place, ramp, reverse, ring,
    seconds, shepard, sine, space, stutter, sub_thump, tremolo, whoosh_envelope,
)


def _air(t, rng, centre, q=1.1):
    return norm(bandpass(pink_noise(t.size, rng), centre, q))


def _shot(sound, tail=0.035):
    return finish(fade(sound, 0.002, tail), -3.0)


def _bed(sound, overlap):
    body = loop(sound, overlap)
    # Preserve the level of phase-aligned tones during the crossfade.
    angle = np.linspace(0.0, np.pi / 2.0, int(overlap * RATE))
    body[:angle.size] /= np.cos(angle) + np.sin(angle)
    # Let finish's DC filter reach its periodic state before taking the loop.
    return finish(np.tile(body, 2), -6.0)[body.size:]


def rift_crack(variant):
    rng = np.random.default_rng(21000 + variant)
    t = seconds(0.9)
    rise = ramp(t, 0.06, 0.8, 1.65)
    release = decay(t, 0.023, 0.8)
    env = np.where(t < 0.8, rise, release)
    if variant == 1:
        stone = _air(t, rng, 760.0) * attack_decay(t, 0.002, 0.027)
        grains = crackle(t, rng, 6 + 510 * rise, 1450.0)
        sound = 0.9 * stone + env * (1.6 * grains + 0.52 * _air(t, rng, 950 + 800 * rise))
    elif variant == 2:
        snap = bell(t, 419.0, 0.035)
        splinters = crackle(t, rng, 8 + 690 * rise, 2650.0)
        squeal = fm(t, 420 + 330 * rise, 1.37, 0.28 + 0.5 * rise)
        sound = 0.6 * snap + env * (1.3 * splinters + 0.28 * squeal * tremolo(t, 16 + 40 * rise, 0.84))
    else:
        chip = _air(t, rng, 1630.0) * attack_decay(t, 0.001, 0.019)
        grit = _air(t, rng, 700 + 1000 * rise)
        broken = crush(grit, bits=6, hold=5) * tremolo(t, 7 + 53 * rise, 0.93) ** 2
        grain = crackle(t, rng, 16 + 450 * rise, 1900.0)
        sound = chip + env * (0.9 * broken + 1.05 * grain + 0.16 * sine(103 + 70 * rise))
    return _shot(sound)


def rift_open(variant):
    rng = np.random.default_rng(21100 + variant)
    t = seconds(1.3)
    head = sub_thump(t, 116.0, 45.0, 0.15)
    if variant == 1:
        centre = glide(t, [(0, 1020), (0.085, 3100), (0.52, 1530), (0.9, 580), (1.3, 210)])
        tear = _air(t, rng, centre, 1.65) * tremolo(t, 48 - 26 * ramp(t, 0, 0.9), 0.54)
        sound = 0.46 * head + 1.2 * tear * whoosh_envelope(t, 0.085)
    elif variant == 2:
        freq = glide(t, [(0, 146), (0.1, 305), (0.6, 172), (1.3, 59)])
        tear = fm(t, freq, 2.73, 2.1 * decay(t, 0.54))
        grit = _air(t, rng, 6 * freq, 1.5)
        sound = 0.48 * head + (0.74 * tear * tremolo(t, 41, 0.4) + 0.66 * grit) * attack_decay(t, 0.085, 0.36)
    else:
        freq = glide(t, [(0, 290), (0.065, 530), (0.9, 132), (1.3, 90)])
        edge = crush(ring(_air(t, rng, 3.3 * freq), 213.0), bits=6, hold=5)
        current = sine(freq) * tremolo(t, 92 - 77 * ramp(t, 0, 0.9), 0.96)
        gate = attack_decay(t, 0.055, 0.34)
        sparks = crackle(t, rng, 170 * decay(t, 0.35), 2300)
        sound = 0.42 * head + gate * (1.2 * edge + 0.55 * current + 0.36 * sparks)
    return _shot(sound, 0.09)


def rift_hum(variant):
    rng = np.random.default_rng(21200 + variant)
    t = seconds(2.25)
    if variant == 1:
        hum = sine(55, t.size) + 0.28 * sine(110, t.size) + 0.13 * sine(275, t.size)
        sound = hum * (0.83 + 0.13 * sine(1.5, t.size)) + 0.19 * _air(t, rng, 350)
    elif variant == 2:
        beats = sine(62.5, t.size) + 0.55 * sine(64, t.size)
        breath = _air(t, rng, 290 + 82 * sine(1, t.size), 1.8)
        sound = 0.73 * beats + 0.42 * breath + 0.13 * sine(187.5, t.size)
    else:
        buzz = fm(t, 49, 3.0, 1.15 + 0.5 * sine(2.5, t.size))
        static = lowpass(crush(_air(t, rng, 615), bits=5, hold=7), 1700)
        sound = 0.77 * buzz + 0.32 * static * tremolo(t, 8.5, 0.65)
    return _bed(sound, 0.25)


def maze_step(variant):
    t = seconds(0.6)
    if variant == 1:
        partials = ((1.0, 1.0), (2.0, 0.32), (3.17, 0.2), (6.2, 0.11))
        sound = bell(t, 261.63, 0.16, partials)
    elif variant == 2:
        reed = fm(t, 293.66, 2.0, 1.35 * decay(t, 0.065) + 0.12)
        sound = reed * attack_decay(t, 0.017, 0.14)
        sound += 0.22 * place(0.6, (0.087, sound[:int(0.45 * RATE)], 1.0))
    else:
        pitch = glide(t, [(0, 192), (0.035, 220), (0.6, 220)])
        scoop = sine(pitch)
        harmonic = 0.26 * sine(440, t.size)
        sound = (scoop + harmonic) * attack_decay(t, 0.042, 0.115)
    return _shot(sound, 0.065)


def blink(variant):
    rng = np.random.default_rng(21300 + variant)
    grain_t = seconds(0.16)
    if variant == 1:
        bits = crush(fm(grain_t, 216 - 830 * grain_t, 2.4, 1.8), bits=5, hold=5)
        broken = stutter(bits, rng, slices=8, repeat_chance=0.82)
        out = broken * attack_decay(grain_t, 0.005, 0.072)
        arrival = sub_thump(seconds(0.14), 201, 54, 0.05)
        sound = place(0.5, (0.0, out, 0.73), (0.27, reverse(fade(out, 0.005, 0.02)), 0.55),
                      (0.36, arrival, 0.75))
    elif variant == 2:
        inhale = _air(grain_t, rng, glide(grain_t, [(0, 330), (0.16, 2440)]))
        inhale *= ramp(grain_t, 0.0, 0.16, 1.7) * tremolo(grain_t, 24 + 330 * grain_t, 0.93)
        crystal = bell(grain_t, 338, 0.041, ((1, 1), (2.8, 0.52), (5.8, 0.19)))
        sound = place(0.5, (0, fade(inhale, 0.002, 0.008), 1), (0.207, crystal, 0.27),
                      (0.267, crystal, 0.85), (0.321, crystal, 0.51))
    else:
        chirp = fm(grain_t, 740 * decay(grain_t, 0.023) + 88, 1.49, 0.7)
        chirp *= attack_decay(grain_t, 0.002, 0.026)
        sound = place(0.5, (0, chirp, 0.72), (0.039, chirp, 0.5), (0.077, chirp, 0.3),
                      (0.167, reverse(fade(chirp, 0.002, 0.006)), 0.84),
                      (0.338, chirp, 1), (0.384, chirp, 0.45))
        sound = lowpass(crush(sound, bits=6, hold=6), 3100)
    return _shot(sound)


def collapse_tick(variant):
    rng = np.random.default_rng(21400 + variant)
    t = seconds(0.15)
    if variant == 1:
        sound = sub_thump(t, 109, 51, 0.027)
        sound += 0.31 * _air(t, rng, 640) * attack_decay(t, 0.001, 0.008)
    elif variant == 2:
        sound = bell(t, 258, 0.029, ((1, 0.93), (2.41, 0.44), (5.37, 0.27)))
        sound += 0.19 * sub_thump(t, 128, 75, 0.021)
    else:
        pips = fm(t, 185 + 255 * decay(t, 0.009), 1.36, 1.5 * decay(t, 0.024))
        sound = lowpass(crush(pips * attack_decay(t, 0.0015, 0.013), bits=5, hold=6), 2900)
        sound += 0.25 * place(0.15, (0.045, sound[:2400], 1))
    return _shot(sound, 0.017)


def collapse_strike(variant):
    rng = np.random.default_rng(21500 + variant)
    t = seconds(1.2)
    debris = crackle(t, rng, 230 * decay(t, 0.26), 1710) * decay(t, 0.27)
    if variant == 1:
        tear = _air(t, rng, glide(t, [(0, 2350), (0.13, 1140), (0.57, 380), (1.2, 190)]))
        sound = sub_thump(t, 113, 37, 0.23) + 1.12 * tear * attack_decay(t, 0.008, 0.21) + 0.6 * debris
    elif variant == 2:
        freq = 71 + 105 * decay(t, 0.112)
        metal = fm(t, freq, 3.17, 2.5 * decay(t, 0.27) + 0.35)
        clang = metal * attack_decay(t, 0.008, 0.20) * tremolo(t, 36, 0.53)
        scrape = _air(t, rng, 1180, 1.35) * attack_decay(t, 0.012, 0.22)
        sound = 0.94 * sub_thump(t, 88, 34, 0.24) + 0.78 * clang + 0.58 * scrape + 0.57 * debris
    else:
        brief = seconds(0.29)
        rip = _air(brief, rng, 1760 * decay(brief, 0.09) + 430)
        rip = lowpass(crush(rip, bits=5, hold=5), 3600) * tremolo(brief, 40, 0.74)
        rip *= attack_decay(brief, 0.005, 0.071)
        room = space(fade(rip), 0.9, mix=0.45, dark=1300, seed=21503)
        sound = sub_thump(t, 122, 40, 0.19) + place(1.2, (0, room, 1.28)) + 0.43 * debris
    return _shot(sound, 0.085)


def collapse_reverse(variant):
    rng = np.random.default_rng(21600 + variant)
    rise = seconds(0.65)
    after = seconds(0.35)
    if variant == 1:
        intake = reverse(bell(rise, 310, 0.22, ((1, 1), (2.8, 0.48), (5.6, 0.26))))
        sweep = sine(145 + 290 * decay(after, 0.076))
        release = (0.48 * sweep + 0.43 * _air(after, rng, 470 + 1220 * decay(after, 0.11)))
    elif variant == 2:
        intake = _air(rise, rng, 270 + 2250 * ramp(rise, 0, 0.65, 1.3), 2.1)
        intake = 0.92 * intake + 0.62 * sine(106 + 174 * ramp(rise, 0, 0.65, 1.6))
        pitch = glide(after, [(0, 357), (0.085, 196), (0.35, 159)])
        release = 0.68 * fm(after, pitch, 1.51, 1.05) + 0.26 * _air(after, rng, 810)
    else:
        tone = reverse(fm(rise, 102 + 124 * decay(rise, 0.14), 3.43, 2.04))
        intake = lowpass(crush(tone * tremolo(rise, 7 + 47 * ramp(rise, 0, 0.65), 0.87),
                               bits=5, hold=6), 2500)
        sweep = _air(after, rng, 500 + 1350 * decay(after, 0.054))
        release = 0.51 * sweep + 0.53 * sine(190 - 64 * decay(after, 0.076))
    inhale = fade(intake * ramp(rise, 0, 0.65, 1.2), 0.002, 0.006)
    return _shot(np.concatenate((inhale, release * attack_decay(after, 0.007, 0.086))))


def shard_charge(variant):
    rng = np.random.default_rng(21700 + variant)
    t = seconds(0.85)
    rise = ramp(t, 0, 0.85)
    if variant == 1:
        # Faster, brighter strikes accumulate into a ringing chord.
        note = seconds(0.36)
        notes = (330, 392, 494, 587, 659, 784, 880)
        starts = (0.02, 0.205, 0.36, 0.49, 0.597, 0.688, 0.752)
        partials = ((1, 1), (2.76, 0.29), (4.9, 0.09))
        layers = [(start, bell(note, freq, 0.17, partials), 0.45 + 0.12 * i)
                  for i, (start, freq) in enumerate(zip(starts, notes))]
        sound = place(0.85, *layers) * (0.25 + 0.75 * rise ** 1.1)
    elif variant == 2:
        # Two drawn out resonances beat faster as the crystal strains.
        pitch = 387 + 213 * rise ** 1.55
        glass = fm(t, pitch, 2.21, 0.24 + 0.36 * rise)
        halo = sine(pitch * 1.501 + 14 * rise) + 0.24 * sine(3.413 * pitch)
        sound = (0.81 * glass + 0.4 * halo) * rise ** 1.7
        sound *= tremolo(t, 4 + 24 * rise ** 2, 0.4)
    else:
        # Reversed struck modes with a faint ring-modulated spray.
        partials = ((1, 1), (2.31, 0.39), (4.15, 0.13))
        suction = reverse(bell(t, 479, 0.3, partials)) + 0.46 * reverse(bell(t, 639, 0.38, partials))
        dust = ring(_air(t, rng, 1160 + 900 * rise), 368)
        sound = suction * (0.23 + 0.77 * rise) + 0.48 * dust * rise ** 2.6
    return _shot(sound, 0.009)


def shard_launch(variant):
    rng = np.random.default_rng(21800 + variant)
    note = seconds(0.25)
    layers = []
    for i in range(18):
        if variant == 1:
            # A rising minor-arpeggio fan.
            steps = (0, 3, 7, 10, 12, 15, 19, 22, 24)
            freq = 347 * 2 ** (steps[i // 2] / 12) * (1.006 if i % 2 else 1)
            start = 0.40 * (i / 17) ** 0.82
            glass = bell(note, freq, 0.087, ((1, 1), (2.51, 0.32), (3.83, 0.1)))
        elif variant == 2:
            # Three rakes of descending, bending needles.
            sweep, step = divmod(i, 6)
            start = 0.136 * sweep + 0.016 * step
            freq = (1190 - 106 * step) * (1 - 0.14 * sweep)
            glass = fm(note, freq * (0.73 + 0.27 * decay(note, 0.036)), 1.62, 0.72 * decay(note, 0.06))
            glass *= attack_decay(note, 0.0025, 0.061)
        else:
            # Granular fragments tumble outward in an expanding rhythm.
            start = 0.012 + 0.445 * (i / 17) ** 1.55 + rng.uniform(-0.003, 0.003)
            freq = rng.uniform(460, 1120)
            glass = bell(note, freq, 0.046, ((1, 0.85), (1.38, 0.43), (2.91, 0.22)))
            glass = crush(glass, bits=7, hold=4) * tremolo(note, 58, 0.55)
        layers.append((start, glass, rng.uniform(0.76, 1.0)))
    fan = place(0.7, *layers)
    if variant == 3:
        fan = lowpass(fan, 4100)
    return _shot(fan, 0.068)


def shard_turn(variant):
    rng = np.random.default_rng(21900 + variant)
    pause = seconds(0.65)
    curl = seconds(0.35)
    rise = ramp(pause, 0, 0.65, 1.45)
    if variant == 1:
        glass = sine(627, pause.size) + 0.38 * sine(638, pause.size) + 0.19 * sine(1390, pause.size)
        whistle = sine(glide(curl, [(0, 1080), (0.13, 960), (0.35, 470)]))
        whistle = reverse(whistle * decay(curl, 0.115))
    elif variant == 2:
        glass = fm(pause, 390 + 68 * rise, 2.48, 0.9 + 0.39 * rise)
        sweep = _air(curl, rng, glide(curl, [(0, 1750), (0.35, 560)]), 2.15)
        whistle = reverse((0.45 * sweep + 0.78 * sine(1090 - 1350 * curl)) * decay(curl, 0.108))
    else:
        glass = 0.68 * sine(524, pause.size) + 0.33 * ring(sine(1149, pause.size), 213)
        glass = lowpass(crush(glass, bits=6, hold=6), 2950)
        chirp = fm(curl, 1230 - 1660 * curl, 1.28, 0.48)
        whistle = reverse(lowpass(crush(chirp, bits=6, hold=5), 3200) * decay(curl, 0.096))
    hover = glass * tremolo(pause, 7 + 24 * rise, 0.46) * (0.11 + 0.45 * rise)
    whistle *= ramp(curl, 0, 0.014)
    return _shot(np.concatenate((fade(hover, 0.03, 0.018), 0.94 * whistle)), 0.013)


def shard_hit(variant):
    rng = np.random.default_rng(22000 + variant)
    t = seconds(0.3)
    if variant == 1:
        shard = _air(t, rng, 2340) * attack_decay(t, 0.0015, 0.022)
        sound = 0.88 * shard + 0.59 * bell(t, 798, 0.057)
    elif variant == 2:
        partials = ((1, 1), (1.84, 0.57), (3.61, 0.32), (5.02, 0.07))
        sound = bell(t, 562, 0.092, partials)
        sound += 0.42 * place(0.3, (0.018, bell(t, 911, 0.045, partials), 1))
    else:
        fragment = seconds(0.095)
        layers = []
        for start in (0, 0.012, 0.031, 0.057):
            pitch = rng.uniform(530, 1210) * (0.74 + 0.26 * decay(fragment, 0.017))
            glint = fm(fragment, pitch, 2.27, 0.84)
            layers.append((start, glint * attack_decay(fragment, 0.0015, 0.017), 1 - 9 * start))
        sound = place(0.3, *layers)
        sound += 0.52 * _air(t, rng, 1590) * attack_decay(t, 0.001, 0.012)
    return _shot(sound)


def squeeze_start(variant):
    rng = np.random.default_rng(22100 + variant)
    t = seconds(1.5)
    if variant == 1:
        bend = glide(t, [(0, 137), (0.31, 78), (0.63, 117), (1.5, 62)])
        groan = fm(t, bend, 2.35, 1.76) * tremolo(t, 12 + 7 * t, 0.44)
        timber = crackle(t, rng, 78 * decay(t, 0.56), 855)
        sound = sub_thump(t, 82, 34, 0.33) + 0.5 * groan * attack_decay(t, 0.14, 0.4) + 0.53 * timber
    elif variant == 2:
        yaw = glide(t, [(0, 580), (0.17, 310), (0.57, 630), (1.5, 185)])
        moan = _air(t, rng, yaw, 2.85) + 0.5 * _air(t, rng, yaw * 2.05, 2.4)
        tremor = sine(66 + 14 * decay(t, 0.19)) * tremolo(t, 4.5, 0.69)
        sound = sub_thump(t, 106, 40, 0.26) + (0.92 * moan + 0.27 * tremor) * whoosh_envelope(t, 0.39)
    else:
        bend = glide(t, [(0, 90), (0.28, 148), (0.81, 65), (1.5, 56)])
        strain = ring(fm(t, bend, 1.76, 1.6 * decay(t, 0.65)), 31)
        strain *= attack_decay(t, 0.08, 0.37) * tremolo(t, 5.5 + 14 * t, 0.8)
        debris = _air(t, rng, 250 + 1080 * decay(t, 0.27))
        sound = sub_thump(t, 139, 37, 0.29) + 0.47 * strain + 0.74 * debris * attack_decay(t, 0.008, 0.16)
    return _shot(sound, 0.1)


def squeeze_rise(variant):
    rng = np.random.default_rng(22200 + variant)
    t = seconds(6.8)
    progress = ramp(t, 0, 6.8)
    speed = 0.12 + 1.75 * progress ** 2.25
    swell = (0.085 + 0.915 * progress ** 1.55) * ramp(t, 0, 0.22)
    if variant == 1:
        # Smooth octave spiral with a granular, sub-bass undercurrent.
        spiral = shepard(t, 38, speed)
        undertow = sine(40 + 18 * progress) * tremolo(t, 1.4 + 12 * progress ** 2, 0.53)
        grit = _air(t, rng, 220 + 630 * progress ** 1.7, 1.35)
        sound = 2.3 * spiral + 0.32 * undertow + (0.22 + 0.24 * progress) * grit
    elif variant == 2:
        # Offset spirals beat against one another like bent metal.
        lower = shepard(t, 48, speed * 0.87)
        upper = shepard(t, 72.4, speed * 0.87, layers=5)
        spiral = np.tanh(3.8 * (lower + 0.71 * upper))
        growl = fm(t, 42 + 22 * progress ** 1.3, 2.43, 0.62 + 1.96 * progress)
        growl *= tremolo(t, 2 + 19 * progress ** 2, 0.54)
        sound = 0.9 * spiral + 0.35 * growl + 0.36 * _air(t, rng, 770, 1.8)
    else:
        # A gated, grainy spiral with successive surges getting closer together.
        spiral = shepard(t, 56, speed * 1.06, layers=5)
        gate = tremolo(t, 2.1 + 23 * progress ** 2.3, 0.77)
        throat = sine(45 + 8 * progress) + 0.29 * sine(92 + 24 * progress)
        granules = _air(t, rng, 390 + 530 * progress ** 2, 1.1)
        grit = lowpass(crush(2.25 * spiral + 0.66 * granules, bits=5, hold=6), 2500)
        sound = grit * gate ** 2 + 0.30 * throat * gate + 0.22 * granules
    return _shot(sound * swell, 0.012)


def squeeze_beacon(variant):
    t = seconds(1.4)
    cycle = 1 / 1.2
    pulse = (0.5 + 0.5 * np.cos(2 * np.pi * cycle * (t - 0.54))) ** 3
    if variant == 1:
        glass = sine(440, t.size) + 0.16 * sine(880, t.size) + 0.075 * sine(1320, t.size)
        sound = glass * (0.17 + 0.72 * pulse)
    elif variant == 2:
        phase = 2 * np.pi * cycle * (t - 0.16)
        # Two soft chime notes inside the cycle, followed by a quiet rest.
        first = np.maximum(np.cos(phase), 0) ** 9
        second = np.maximum(np.cos(phase - 1.28), 0) ** 10
        sound = 0.76 * fm(t, 360, 2.0, 0.18) * first
        sound += 0.63 * fm(t, 540, 2.0, 0.12) * second
    else:
        breath = fm(t, 400 + 3.8 * sine(cycle, t.size), 1.0, 0.27 + 0.17 * pulse)
        sheen = sine(600, t.size) * (0.25 + 0.75 * pulse)
        sound = (0.83 * breath + 0.2 * sheen) * (0.27 + 0.61 * pulse)
    return _bed(sound, 0.2)


def squeeze_final(variant):
    rng = np.random.default_rng(22300 + variant)
    pull = seconds(0.5)
    hit = seconds(1.8)
    pressure = ramp(pull, 0, 0.5)
    if variant == 1:
        intake = _air(pull, rng, 340 + 2200 * pressure ** 1.8, 1.55)
        intake += 0.48 * sine(73 + 96 * pressure ** 1.7)
        wave = _air(hit, rng, 180 + 2340 * decay(hit, 0.25), 1.2)
        wave *= attack_decay(hit, 0.009, 0.24)
        smoke = _air(hit, rng, 230 + 155 * decay(hit, 0.62), 1.7)
        burst = 1.35 * sub_thump(hit, 122, 32, 0.4) + 1.32 * wave + 0.54 * smoke * attack_decay(hit, 0.09, 0.59)
    elif variant == 2:
        intake = reverse(bell(pull, 246, 0.18, ((1, 1), (2.8, 0.57), (5.9, 0.22))))
        scrape = _air(hit, rng, 410 + 880 * decay(hit, 0.22)) * attack_decay(hit, 0.004, 0.16)
        fracture = fm(hit, 53 + 125 * decay(hit, 0.095), 2.39, 2.5 * decay(hit, 0.34))
        fracture *= attack_decay(hit, 0.005, 0.31)
        core = fracture[:int(0.56 * RATE)] + scrape[:int(0.56 * RATE)]
        hall = space(fade(core, 0.002, 0.1), 1.23, mix=0.45, dark=1350, seed=22302)
        burst = sub_thump(hit, 90, 34, 0.37) + place(1.8, (0, hall, 1.5)) + 0.38 * scrape
    else:
        intake = lowpass(crush(_air(pull, rng, 570 + 1660 * pressure), bits=5, hold=8), 3200)
        intake *= tremolo(pull, 7 + 62 * pressure ** 2, 0.78)
        intake += 0.32 * fm(pull, 82 + 153 * pressure ** 2, 1.55, 0.69)
        tear = _air(hit, rng, 350 + 1350 * decay(hit, 0.11))
        rupture = lowpass(crush(tear, bits=5, hold=6), 3200)
        rupture *= attack_decay(hit, 0.004, 0.29) * tremolo(hit, 14 + 54 * decay(hit, 0.41), 0.72)
        abyss = ring(_air(hit, rng, 290 + 270 * decay(hit, 0.47), 1.25), 73)
        burst = 1.19 * sub_thump(hit, 156, 37, 0.34) + 1.55 * rupture + 0.69 * abyss * attack_decay(hit, 0.078, 0.54)
    inhale = fade(0.68 * intake * pressure ** 1.3, 0.005, 0.012)
    return _shot(place(2.5, (0, inhale, 1), (0.7, burst, 1)), 0.12)


def _sound(group, title, build, variants, looping=False):
    return {"group": group, "title": title, "build": build, "variants": variants, "loop": looping}


SOUNDS = {
    "rift_crack": _sound("Трещины", "Появление трещины", rift_crack,
                         ["Каменный скол и песок", "Стеклянный щелчок и скрежет", "Дроблёная цифровая трещина"]),
    "rift_open": _sound("Трещины", "Раскрытие трещины", rift_open,
                        ["Шипящий фронт разлома", "Металлический рёв", "Бегущий дробный разряд"]),
    "rift_hum": _sound("Трещины", "Гул открытой трещины", rift_hum,
                       ["Низкий электрический гул", "Биения с призрачным дыханием", "Модулированное жужжание со статикой"], True),
    "maze_step": _sound("Трещины", "Шаг лабиринта", maze_step,
                        ["Удар по стеклянной пластинке", "Тростниковый тон с эхом", "Подъезд к мягкой ноте"]),
    "blink": _sound("Коллапс", "Телепорт босса", blink,
                    ["Битый сигнал и басовый удар", "Рваный вдох и стеклянное эхо", "Эхо коротких цифровых свистов"]),
    "collapse_tick": _sound("Коллапс", "Тик перед волной", collapse_tick,
                            ["Приглушённый удар сердца", "Щелчок тёмного металла", "Двойной цифровой тик"]),
    "collapse_strike": _sound("Коллапс", "Удар секторов", collapse_strike,
                              ["Басовый удар с каменным осыпанием", "Рваный металлический лязг", "Цифровой разрыв с гулким хвостом"]),
    "collapse_reverse": _sound("Коллапс", "Смена направления", collapse_reverse,
                               ["Обратный звон и нисходящий свист", "Всасывающий порыв и перелом тона", "Дробное втягивание со скачком тона"]),
    "shard_charge": _sound("Осколки", "Зарядка осколков", shard_charge,
                           ["Учащающиеся хрустальные удары", "Растущий звон с биениями", "Обратный звон со стеклянной пылью"]),
    "shard_launch": _sound("Осколки", "Запуск кольца", shard_launch,
                           ["Восходящее минорное арпеджио", "Три нисходящих веера", "Неровный каскад дроблёного стекла"]),
    "shard_turn": _sound("Осколки", "Разворот осколков", shard_turn,
                         ["Биения стекла и чистый свист", "Металлическое дрожание и шумный свист", "Цифровое мерцание и обратный писк"]),
    "shard_hit": _sound("Осколки", "Попадание осколка", shard_hit,
                        ["Сухой хруст и короткий звон", "Двойной стеклянный отскок", "Всплеск свистящих щепок"]),
    "squeeze_start": _sound("Сжатие", "Начало сжатия", squeeze_start,
                            ["Низкий трескучий скрип", "Басовый удар и полое завывание", "Дробный гул под давлением"]),
    "squeeze_rise": _sound("Сжатие", "Сжатие кольца", squeeze_rise,
                           ["Плавная спираль над пульсирующим басом", "Две спирали со скрежещущими биениями", "Прерывистая спираль с цифровым зерном"]),
    "squeeze_beacon": _sound("Сжатие", "Маяк прохода", squeeze_beacon,
                             ["Мягкий стеклянный пульс", "Двухнотный звон", "Воздушный дрожащий тон"], True),
    "squeeze_final": _sound("Сжатие", "Финальный взрыв", squeeze_final,
                            ["Всасывающий ветер и басовая волна", "Обратный колокол и гулкий обвал", "Дробный вдох и цифровой разлом"]),
}
