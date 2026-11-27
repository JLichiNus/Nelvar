# Nelvar

**A pixel-art top-down action roguelike where every mutation is a trade-off.**

You play a **Wanderer** — a paradoxical being whose versions died in all four
elemental realities and went on existing anyway. Reality can't tolerate you: the
longer you stay and the more you do, the sooner it throws you out into the
next one, until there is nowhere left but the Void.

To survive, you mutate. But every mutation that gives you something takes
something away — and you share your body with three other versions of
yourself, who pick mutations for their own element, not yours.

> **Nelvar is not a game about endlessly accumulating power, but about
> surviving through constant adaptation.**

## Features

- **Mutations with a cost.** Twenty-one mutations across three layers — body,
  abilities and rules — each with a gain and a drawback. Some reshape how you
  play: flight that no longer protects you, armour that only works while you
  stand still, power that awakens near death.
- **Four versions, one body.** Your Air version picks its own mutations, while
  your Earth, Fire and Ice versions pick theirs. You see whose turn is next and
  plan around it, but over the run you control less and less.
- **Fast, readable combat.** Wind shots, a wave that turns enemy projectiles
  back, a compression that crushes one target and a flight that carries you over
  danger. Every enemy attack is shown before it lands.
- **Procedural worlds.** Floating islands joined by wooden bridges over a sea
  of clouds, with groves and rocks — layout and pixel art alike generated from
  a seed.
- **The Void and the Only One.** A final route across drifting debris of all
  four realities, and a four-phase boss whose attacks are about geometry rather
  than damage.

## Status

The first playable stage is close: the Air location, its enemies, the
mutation system, the Void and the final boss are in. The Earth, Fire and Ice
locations are in progress, followed by the full run from the first location to
the boss. Development continues after that.

## Controls

| Key | Action |
|---|---|
| WASD / arrows | Move |
| Ctrl | Toggle running |
| Shift | Flight |
| LMB | Wind shot (hold to keep firing) |
| RMB | Wind wave |
| R | Compression on the enemy nearest to the cursor |
| E | Choose a ripe mutation |
| Mouse wheel | Zoom |
| Esc | Pause and mutation inventory |

## Running

Open `project.godot` in **Godot 4.7.2** and press **F5**. No other
dependencies are needed.

## Documentation

The design documents are in Russian.

- [`docs/VISION.md`](docs/VISION.md) — what the game should be and why.
- [`docs/LORE.md`](docs/LORE.md) — the world of Nelvar.
- [`docs/GDD.md`](docs/GDD.md) — rules, mechanics and numbers.
- [`docs/DEVELOPMENT.md`](docs/DEVELOPMENT.md) — project structure,
  generators, sound pipeline, tests (in English).

## Licence

[MIT](LICENCE)
