#!/usr/bin/env python3
"""Synthesises the Only One's sounds (the Void's final boss).

Every sound has three candidate variants. They are built by the modules
boss_sfx_a.py (dashes, gravity wells, the boss itself) and boss_sfx_b.py
(rifts, collapse, shards, squeeze); shared tools are in boss_sfx_common.py.

  python3 tools/gen_boss_sfx.py --preview DIR [name ...]
      writes every variant as DIR/<name>_v<k>.wav plus DIR/manifest.json
  python3 tools/gen_boss_sfx.py --pick name=k [name=k ...]
      writes the chosen variants into assets/audio/sfx/boss/<name>.wav

Each module exposes SOUNDS: name -> {"group", "title", "build", "variants",
"loop"}: `build(variant)` returns the samples for variant 1..3, `variants`
describes each in a few words (Russian, for the listening page), `loop` marks
sounds that repeat seamlessly. Needs numpy only.
"""

import json
import sys
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

from boss_sfx_common import RATE  # noqa: E402

OUT = Path(__file__).resolve().parent.parent / "assets" / "audio" / "sfx" / "boss"


def sounds() -> dict:
    found = {}
    for module in ("boss_sfx_a", "boss_sfx_b"):
        try:
            found.update(getattr(__import__(module), "SOUNDS", {}))
        except ModuleNotFoundError as error:
            if error.name != module:
                raise
    return found


def write(path: Path, signal: np.ndarray) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    data = np.round(np.clip(signal, -1.0, 1.0) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as out:
        out.setnchannels(1)
        out.setsampwidth(2)
        out.setframerate(RATE)
        out.writeframes(data.tobytes())


def preview(folder: Path, names: list[str]) -> None:
    table = sounds()
    manifest = []
    for name, spec in table.items():
        if names and name not in names:
            continue
        for variant in (1, 2, 3):
            signal = spec["build"](variant)
            write(folder / f"{name}_v{variant}.wav", signal)
        manifest.append({"name": name, "group": spec["group"], "title": spec["title"],
                         "variants": spec["variants"], "loop": spec.get("loop", False)})
        print(f"{name}: 3 variants -> {folder}")
    if not names:
        (folder / "manifest.json").write_text(json.dumps(manifest, ensure_ascii=False, indent=1))


def pick(choices: list[str]) -> None:
    table = sounds()
    for choice in choices:
        name, variant = choice.split("=")
        write(OUT / f"{name}.wav", table[name]["build"](int(variant)))
        print(f"{name}: variant {variant} -> {OUT}")


if __name__ == "__main__":
    args = sys.argv[1:]
    if args[:1] == ["--preview"]:
        preview(Path(args[1]), args[2:])
    elif args[:1] == ["--pick"]:
        pick(args[1:])
    else:
        print(__doc__)
