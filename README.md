# Nelvar

**Nelvar** is a pixel-art 2D roguelike with a top-down perspective, where mutation serves as both the primary means of character progression and a constant source of danger.

Unlike traditional roguelikes, where characters gradually grow stronger, in Nelvar, every advantage comes at a cost.

## Concept

The world of Nelvar is inhabited by creatures for whom mutation is a natural part of existence.

Players take control of one of the **Wanderers** — paradoxical beings whose very existence defies the conventional laws of reality.

Every Wanderer is forced to constantly evolve, adapting to the surrounding world and the consequences of their own mutations.

**The game's core principle: to gain something, you must sacrifice something in return.**

## Development

Nelvar is currently in the early stages of active development.

The current priority is to create a playable prototype featuring a fully developed character and a functional procedural environment generation system.

Gameplay mechanics, content, and technical implementation will gradually expand as the project evolves.

**Nelvar is not a game about endlessly accumulating power, but about surviving through constant adaptation.**

## Map prototype

Open `project.godot` in **Godot 4.7.2** and press **F5**. No external dependencies
are required. Each launch generates a new random seed, displayed
in the upper-left corner and printed to Output.

- **WASD / arrow keys:** walk.
- **Ctrl:** toggle running.
- **Shift:** short flight (speed boost); airborne the player ignores contact damage.
- **LMB:** wind projectile. **RMB:** wind wave. **R:** compression on the enemy nearest to the cursor.
- **E:** open the choice of a ripe mutation (see Mutations below).
- **Mouse wheel:** zoom the camera attached to the player.
- **F4** (debug builds): fill the adaptation meter at once.
- **F3:** show occupied chunks, collision boundaries, trunk circles, rock footprints and island IDs.

The player (`player/player.tscn`) is drawn from two animated layers: legs play
the locomotion, the torso follows it or plays an attack on top. The node origin
is at the feet, under a circular collider of `NelvarPlayer.BODY_RADIUS`; aiming
and attacks start from the body center (`AimPivot`). Hopper enemies spawn on
walkable ground around the player, away from trunks. At zero HP the scene
restarts with a new seed.

### Mutations

Every mutation gives something and takes something (`mutations/`). The
player's body adapts to what it lives through: the **adaptation** meter
above the level line fills from lost health (most), kills and, slowly, time.
A full meter ripens a mutation, and each ripening belongs in advance to one of
the four linked versions of the Wanderer — the player's own (Air), Earth, Fire,
Ice — or to none (spontaneous). The next owners are shown as element sigils
next to the meter, so the player can plan around them.

- **The player's own** waits: the sigil pulses, the meter stops and **E**
  opens three cards (the game pauses; 1/2/3 or a click picks, Esc/E puts it
  off). Left waiting for 40 s, another version seizes it and picks from the
  same cards for itself.
- **Another version's** is picked by that version from three cards by what
  its element values (`NelvarMutation.VERSION_WEIGHTS`: Air — speed and
  flight, Earth — health and defence, Fire — damage, Ice — cooldowns and
  control). Each card says which version would like it.
- **Spontaneous** ones are random.

Received mutations line up along the top of the screen as small tiles (first
letter, frame in the colour of the version that picked it, a mark of its layer,
one pip per stage); hovering one shows its short summary. **Esc → Инвентарь**
lists them all with exact numbers, layer and who picked each stage.

The player's share of ripenings falls from 70% to 25% over the first 12
mutations. Taking a mutation again deepens it to stage II (both sides doubled).
Mutations come in three layers: **body** (stat trades), **ability** (how a skill
works: split shot, piercing wind, longer or broader wave, longer flight, ...)
and **rule** (hollow vortex — flight no longer protects; rooting — armour when
standing still; storm core; last breath). The catalog is
`mutations/mutation_catalog.gd`; stats live in `NelvarStats`, which the player
reads instead of its exports; the meter, the queue and the choice are
`NelvarMutationDirector` under the player; the HUD is `ui/mutations/`.

### Sound

Three audio buses (`default_bus_layout.tres`): **Master**, **Music** and **SFX**.
Every music player sends to Music and every sound to SFX; their volumes are
set in Settings → «Аудио» (main menu and pause menu alike) and saved in
`user://settings.cfg` (`GameSettings`). The settings panel is split into tabs:
«Экран», «Интерфейс», «Аудио».

Music during a run is the `GameMusic` autoload (`scripts/game_music.gd`): a
track fades in, plays to its end, fades out, then 30 s of silence and the next
track is picked at random from `PLAYLIST` (`assets/audio/music/game/`). It
keeps playing through the pause menu and through a restart after death, and
fades out when the main menu opens.

Sound effects are synthesised by `tools/gen_sfx.py` (numpy only) into
`assets/audio/sfx/`; run `python3 tools/gen_sfx.py` from the project root to
rebuild them. The LMB shot has no sound of its own: each shot feeds a small,
looped wind (`wind.wav`, `ShotWind` under the player) that holds while the
next shot is due and dies down without shots. A tap is a short breath of wind,
held LMB one even wind of the same volume — five separate sounds a second
would wear the ear out. The wind eases in and drifts away rather than
switching on and off; volume, fade and easing are exports on the player
(`shot_wind_*`). The RMB wave is one gust that rushes ahead with it and sinks as
it spreads (`wind_wave_1..3.wav` via `wind_wave.tres`, `WaveSound`). The R
compression rushes air in and strikes softly on impact
(`compression_start_*`), then holds a looped tight wind whose pitch rises over
the squeeze (`compression_hold.wav`); when the compression ends, early or not,
both fade out instead of cutting off. Flight (Shift) takes off with a soft upward gust
(`flight_lift_*`), keeps a looped rush of air while airborne that is louder the
faster the player flies (`flight_air.wav`, `FlightAir`) and settles with a
soft low puff on landing (`flight_land_*`).

`test_world.tscn` is a flat arena for tuning combat without the generator (F6).

### The Void (developer menu)

Settings → «Меню разработчика» → «Запускать игру в Пустоте» makes «Играть» open
`scenes/void.tscn` instead of the earth map. The player wakes on debris of all four
realities — torn earth, rocks, fallen trunks, ice, cooling basalt, cloud-stone,
paved ruins and violet shards — hanging over the dark Void, and makes their way to
the monolith: a black-grey angular island that is the same in every run.

Debris has no walls. Off its edge the player keeps going for a moment
(`NelvarVoidData.COYOTE_TIME`), so narrow gaps are walked over, wider ones need a
run-up (Ctrl) and the widest need the flight (Shift); otherwise they fall, lose a
little HP, come back where they last stood firmly and are told what that crossing
takes. Some pieces drift between their neighbours and carry the player, some fade
out of existence for a while. Faint threads of light across the gaps mark the
route; their look tells a step, a run-up and a flight apart.

Gaps are measured the way a player crosses them: straight from the middle of one
piece towards the middle of the next, and lines a little to either side must stay
within reach too (`NelvarVoidData.crossing_gap`, `slack_gap`). The test plays whole
Voids with the real player, from the spawn to the arena, without a single fall.
The layout comes from `NelvarVoidGenerator` (seeded like the earth map), the art
from `NelvarDebrisPainter`, the sky from `scripts/void/void_sky.gdshader`.

Stepping into the arena on the monolith starts the boss fight (`NelvarVoidArena`):
the edge is sealed, the Void opens its eyes and the Only One (Единственный,
`scripts/void/boss/`) forms out of the sigil. It is one body that the fight bends
out of shape, its contours always lagging a moment behind it:

- **I · Единственный** — a hunched figure with an empty face and a huge left arm.
  Dash (leaves a short trail of the Void), pull around itself that bursts after
  2 s, a rift dragged along the floor towards the player.
- **II · Искажение** (70% HP) — the limbs come loose from the body. Double dash
  aimed anew, a pull next to the player, three rifts in a fan.
- **III · Отторжение** (42%) — it stretches, squashes and blinks part by part.
  Three dashes (the last trail lingers), two pulls tearing both ways, rifts crossing
  the arena one after another, and the collapse: rotating sectors from the centre.
- **IV · Поглощённый** (14%) — only a crawling silhouette hovering in the centre.
  Rings of shards that fly out and come back, and a closing ring of the Void with a
  single gap.

Every hazard shows itself before it hurts (a dash even draws its path); flight
(Shift) passes through all of them. The fight is lit by the boss and its attacks
(violet 2D lights on the dark arena), throws pixel sparks, and shakes the picture
itself (`NelvarVoidScreen`: shockwaves, tearing, colour fringes, slow motion at
phase changes and at its death); a title card announces it and each phase. Losing the fight brings the same Void back with the player at the arena's
door. Defeating the Only One lifts the seal. The monolith is painted on a worker
thread, so the Void loads as fast as before.

The earth map contains 2–3 large floating islands and 6–7 small ones, connected
by narrow wooden bridges. Shorelines and bridge sides block movement; falling
and height differences are not implemented yet.

The world wears the style of the air reality from the main menu. The islands
float above a sea of clouds (`scripts/world/cloud_sea.gd` and its shader): puffy
pixel clouds in overlapping rows, lit from the upper right and dithered like the
menu art, with small gaps where the sky shows through. The sea lies deeper than
the islands, so it follows the camera with parallax, and drifts smoothly with the
wind. It is computed once per cloud pixel in a small viewport and stretched over
the screen with a sub-pixel offset. Thin wind streaks, as in the menu, fly over
the world (`scripts/fx/wind_particles.gd`).

Bridge decks, board seams, rails, end caps and posts are generated procedurally
and baked onto the same world pixel grid as the islands. Angled bridges are
rasterized before display, so the finished pixels remain aligned with the
terrain. The experimental bridge tile remains in `assets/textures/bridge/`
for later use and is not loaded by the renderer.

Island artwork is painted procedurally after map generation: pale grass and
earth patches, stepped shorelines, layered cliffs, branching roots, individual
grass tufts and small flowers beside some of them. Artwork follows a shared world pixel grid and is baked once per
island; chunks display regions of those same textures to avoid seams. Painting
does not modify the generated surface, bridges or physics. Grass avoids bridge
landings. The same seed and style reproduce the same artwork.

Visual settings are exposed in `resources/earth_terrain_style.tres`:
`pixel_size` is measured in world units (4 by default), `cliff_depth` and
`root_length` in terrain pixels, `grass_density` controls tuft placement and
`flower_density` the share of tufts with a flower.

Trees are generated in groves, leaving open ground between groups. Their
placement uses a separate seeded generator with minimum trunk spacing, clear
island hubs, reserved bridge routes and a clear spawn area. Each tree gets a
different canopy silhouette, palette, bark and size, baked to the terrain's
world pixel grid. Forest density, group sizes and clearances are exposed in
`resources/earth_forest_config.tres`.

Every trunk has a circular `StaticBody2D` collider. Trees and the player share
the `Actors` Y-sort layer, sorted at their ground origins: the player is drawn
behind trees when above their bases and in front when below. Canopies stay
opaque. Collision only affects trunks, so the player can walk under foliage.

Rocks and bushes are scattered after the forest (`NelvarPropGenerator`). Rocks
keep the same hubs, bridge routes, spawn area and passages open as trunks, have
an elliptic footprint collider and stop the player, enemies and projectiles.
Bushes gather at the foot of trees and in the open and can be walked through.
Neither is placed where a tree crown would hide it. Both Y-sort with the player
and outline it when it stands behind them. Counts and sizes are exposed in
`resources/earth_prop_config.tres`; clearances come from the forest config.

Generation parameters are exposed in `resources/earth_map_config.tres`.
The generator plans the islands and connected bridge graph, shapes the shores,
and subdivides the surface into a quadtree. Interior leaves can remain large;
shore and bridge regions subdivide down to 256 world pixels by default. Each
occupied leaf owns its clipped geometry and boundary collisions. Shared island
geometry keeps neighboring chunks consistent, including bridge landings.

To reproduce a map from its seed, pass a command-line argument after `--`:

```sh
godot --path . -- --seed=20261120
```

Run the generation and physics checks without opening a window:

```sh
godot --headless --path . --script tests/test_world.gd -- --seeds=100
godot --headless --path . --script tests/test_terrain.gd
godot --headless --path . --script tests/test_forest.gd -- --seed=20261120
godot --headless --path . --script tests/test_props.gd
godot --headless --path . --script tests/test_void.gd -- --seeds=50 --walks=6
godot --headless --path . --script tests/test_mutations.gd
```

Here `godot` means the path to your Godot 4.7.2 executable. The checks cover
island counts, connectivity, determinism, chunk geometry, spawn clearance,
bridge landings, actual character movement and collision boundaries.
Terrain checks cover repeatable island and bridge artwork across different
chunk subdivisions, surface coverage, grass and flower settings, hanging roots
and unchanged map geometry.
Forest checks cover repeatable groves and tree art, trunk spacing, clear bridge
routes, circular colliders and actual movement into and around a tree.
Prop checks cover rock and bush placement rules, repeatable prop art, rock
colliders that stop the player and bushes the player walks through.
