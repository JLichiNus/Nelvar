# Nelvar — Development notes

How the project is built: where things live, how the generators and the sound
pipeline work, and how to run the checks. Game rules and numbers are in
`GDD.md`; this document only points to them.

## Running

Open `project.godot` in **Godot 4.7.2** and press **F5**. No external
dependencies are required.

Each launch generates a new random seed, printed to Output and shown on the
info panel (F12, or Settings → «Интерфейс»). To reproduce a map from its seed,
pass a command-line argument after `--`:

```sh
godot --path . -- --seed=20261120
```

Here `godot` means the path to your Godot 4.7.2 executable.

`scenes/main.tscn` is the air location (resources and some classes still carry
`earth_*` names). Settings → «Меню разработчика» → «Запускать игру в Пустоте»
makes «Играть» open `scenes/void.tscn` instead. `test_world.tscn` is a flat
arena for tuning combat without the generator (F6).

Debug keys: **F3** shows occupied chunks, collision boundaries, trunk circles,
rock footprints and island IDs; **F4** (debug builds only) fills the
adaptation meter at once.

### Console

In debug builds **/** opens the developer console during a run (the slash
key itself, whatever the layout). It works like a game chat with commands:
the game stands still while it is open, the list above the line shows what
may be typed next (a mutation is also found by its Russian title), the rest
of the chosen word is greyed out in the line. **Tab** takes it, **↑↓** walk
the list or, on a bare "/", the history; **Enter** runs the command and
closes the console, **Esc** just closes it. Answers stay over the game for a
few seconds; the mouse wheel scrolls them back while the console is open.

`/help` lists the commands, `/help <command>` shows every form of one:

- `/mutation give <id> [stage] [owner]`, `upgrade <id|all>`,
  `remove <id|all>`, `list`, `catalog`, `ripen [owner]`, `adapt <amount>`;
- `/hp add|remove|set <amount>`, `/hp full`, `/hp max <amount>` (base
  maximum); `remove` and `set` pass armor and invulnerability;
- `/god [on|off]`, `/cooldowns reset|off|on`, `/level set|add <n>`;
- `/spawn <enemy> [count]` (at the cursor), `/kill [enemy|boss]` (without an
  argument every enemy but the boss), `/spawner on|off`;
- `/tp` (to the cursor) or `/tp <x> <y>`, `/timescale <scale>` (kept until
  `/restart` or a new `/timescale`), `/stats [all]`, `/restart`, `/clear`.

Code: `ui/console/` — `dev_console.gd` (the `DevConsole` autoload: the look
and the keys), `command_tree.gd` (parsing and hints), `console_node.gd` (a
word or an argument of a command), `console_commands.gd` (the commands).
A command is a tree of `NelvarConsoleNode`; a node with a handler may end
the command, so a handler on a node with children makes the rest optional.
The mutation director and the player have small console-only methods
(`grant`, `remove`, `ripen_now`; `set_health`, `set_level`,
`reset_cooldowns`, `teleport`, `god_mode`, `no_cooldowns`). Tests:
`tests/test_console.gd`.

## Player

`player/player.tscn` is drawn from two animated layers: legs play the
locomotion, the torso follows it or plays an attack on top. The node origin is
at the feet, under a circular collider of `NelvarPlayer.BODY_RADIUS`; aiming
and attacks start from the body center (`AimPivot`).

The player reads its characteristics from `NelvarStats`
(`mutations/stats.gd`) instead of its own exports, so that mutations can change
them. The exports are only the base values.

## Enemies

The spawner (`enemies/enemy_spawner.gd`) brings several kinds: each spawn picks
an `NelvarEnemyKind` (scene, weight, own cap) among those below their cap, on
walkable ground around the player, away from trunks and rocks. Weights, caps
and behaviour are in `GDD.md` §4.

- **Прыгун** (`enemies/hopper/`) — a ball that hops about at random.
- **Свистун** (`enemies/whistler/`) — a hollow sack of dry reed rooted in the
  ground, with a tube for a mouth that turns after the player. While drawing
  breath it swells, quivers, air streams into the tube and it whistles higher.
  Its pink soap bubbles float above their shadow, which is their collider;
  turned back by the wave, a bubble takes the colours of the wind (`deflect`).
- **Бегунок** (`enemies/runner/`) — a tiny fluffy bird on long legs. Winding
  up, it crouches, scratches the ground and chirps while a dashed orange arrow
  grows along the ground and turns light when it locks. A dash leaves a wind
  trail; a stunned Runner has stars over its head; it dies in a puff of
  feathers.

Enemy sounds are positional (`AudioStreamPlayer2D`). Sounds that must outlive
their source (a popped bubble, a dead Whistler) are played by
`NelvarOneShotSound`, which also skips the same sound repeated within 40 ms.

## Mutations

Rules are in `GDD.md` §3. In code:

- `mutations/mutation_catalog.gd` — every mutation;
- `mutations/mutation.gd` — `NelvarMutation`, layers, stages, version weights
  (`VERSION_WEIGHTS`);
- `mutations/stats.gd` — `NelvarStats`, the stats mutations may touch;
- `mutations/mutation_director.gd` — `NelvarMutationDirector` under the player:
  the adaptation meter, the owner queue, the choice and its interception;
- `ui/mutations/` — the HUD, the cards and the inventory.

## Sound

Three audio buses (`default_bus_layout.tres`): **Master**, **Music** and
**SFX**. Every music player sends to Music and every sound to SFX; their
volumes are set in Settings → «Аудио» (main menu and pause menu alike) and
saved in `user://settings.cfg` (`GameSettings`). The settings panel is split
into tabs: «Экран», «Интерфейс», «Аудио».

### Music

Music during a run is the `GameMusic` autoload (`scripts/game_music.gd`): a
track fades in, plays to its end, fades out, then 30 s of silence and the next
track is picked at random from `PLAYLIST` (`assets/audio/music/game/`). It
keeps playing through the pause menu and through a restart after death, and
fades out when the main menu opens.

### Effects

Sound effects are synthesised by `tools/gen_sfx.py` (numpy only) into
`assets/audio/sfx/`; run `python3 tools/gen_sfx.py` from the project root to
rebuild them.

Player abilities:

- **LMB shot** has no sound of its own: each shot feeds a small looped wind
  (`wind.wav`, `ShotWind` under the player) that holds while the next shot is
  due and dies down without shots. A tap is a short breath of wind, held LMB
  one even wind of the same volume — five separate sounds a second would wear
  the ear out. The wind eases in and drifts away rather than switching on and
  off; volume, fade and easing are exports on the player (`shot_wind_*`).
- **RMB wave** is one gust that rushes ahead with it and sinks as it spreads
  (`wind_wave_1..3.wav` via `wind_wave.tres`, `WaveSound`).
- **R compression** rushes air in and strikes softly on impact
  (`compression_start_*`), then holds a looped tight wind whose pitch rises over
  the squeeze (`compression_hold.wav`); when the compression ends, early or
  not, both fade out instead of cutting off.
- **Flight (Shift)** takes off with a soft upward gust (`flight_lift_*`), keeps
  a looped rush of air while airborne that is louder the faster the player
  flies (`flight_air.wav`, `FlightAir`) and settles with a soft low puff on
  landing (`flight_land_*`).

Enemies:

- **Whistler** draws breath with a rising whistle (`whistler_inhale_*`, 0.9 s,
  as long as the breath), blows a fan with a falling "pfoo"
  (`whistler_blow_*`) or a trill of three notes (`whistler_toot_1..3`, played
  in order), knocks hollow when hit (`whistler_hurt_*`) and wheezes as it
  deflates (`whistler_death_*`). Its bubbles pop (`bubble_pop_*`) and, turned
  back by the wave, bounce off with a springy "bwip" (`bubble_deflect_*`).
- **Runner** patters with every footfall (`runner_step_*`, quiet), chirps
  through its windup (`runner_chirp_*`, 0.6 s), takes off with a flutter and a
  rush of air (`runner_dash_*`), scrapes into a skid (`runner_skid_*`), bonks
  into trunks and tweets dizzily (`runner_bonk_*`), peeps when hit
  (`runner_hurt_*`) and dies with a squawk and a puff of feathers
  (`runner_death_*`).

### Boss sounds

The final boss has its own sounds in `assets/audio/sfx/boss/`, synthesised by
`tools/gen_boss_sfx.py` (`boss_sfx_a.py`, `boss_sfx_b.py`, shared tools in
`boss_sfx_common.py`). Every sound has three candidate variants:
`--preview DIR` writes them all for listening, `--pick name=k ...` writes the
chosen ones into the game.

They are played by `NelvarBossSound` (`scripts/void/boss/boss_sound.gd`) as
positional sounds where the attack happens: the aim, lock and rush of a dash, a
tear charging and erupting and then crackling, a gravity well appearing,
charging (timed to end on its burst), stopping still and bursting (twins differ
in pitch), a rift cracking and opening (the sound rides the light along it) and
then humming, the collapse's quickening ticks, strike and reversal, the shard
rings' charge, launch and turn, a shard hitting, and the squeeze's groan,
rising spiral, the beacon of the way out at the gap and the final blast. Around
the boss: its intro, a low presence that sinks with every phase, hits, phase
shifts and death.

Hits, cracks and many rifts at once have a shortest gap and a voice limit, so a
burst of them is heard as one event. Loops (`boss_presence`, `trail_crackle`,
`rift_hum`, `squeeze_beacon`) are imported with loop mode Forward.

## Air location

Generation parameters are in `resources/earth_map_config.tres`. The generator
plans 2–3 large floating islands and 6–7 small ones and a connected graph of
narrow wooden bridges, shapes the shores, and subdivides the surface into a
quadtree. Interior leaves can remain large; shore and bridge regions subdivide
down to 256 world pixels by default. Each occupied leaf owns its clipped
geometry and boundary collisions. Shared island geometry keeps neighboring
chunks consistent, including bridge landings. Shorelines and bridge sides block
movement; falling and height differences are not implemented.

### Sky and wind

The islands float above a sea of clouds (`scripts/world/cloud_sea.gd` and its
shader): puffy pixel clouds in overlapping rows, lit from the upper right and
dithered like the menu art, with small gaps where the sky shows through. The
sea lies deeper than the islands, so it follows the camera with parallax, and
drifts smoothly with the wind. It is computed once per cloud pixel in a small
viewport and stretched over the screen with a sub-pixel offset. Thin wind
streaks, as in the menu, fly over the world (`scripts/fx/wind_particles.gd`).

### Terrain and bridges

Island artwork is painted procedurally after map generation: pale grass and
earth patches, stepped shorelines, layered cliffs, branching roots, individual
grass tufts and small flowers beside some of them. Artwork follows a shared
world pixel grid and is baked once per island; chunks display regions of those
same textures to avoid seams. Painting does not modify the generated surface,
bridges or physics. Grass avoids bridge landings. The same seed and style
reproduce the same artwork.

Bridge decks, board seams, rails, end caps and posts are generated
procedurally and baked onto the same world pixel grid as the islands. Angled
bridges are rasterized before display, so the finished pixels remain aligned
with the terrain. The experimental bridge tile remains in
`assets/textures/bridge/` for later use and is not loaded by the renderer.

Visual settings are in `resources/earth_terrain_style.tres`: `pixel_size` is
measured in world units (4 by default), `cliff_depth` and `root_length` in
terrain pixels, `grass_density` controls tuft placement and `flower_density`
the share of tufts with a flower.

### Trees

Trees are generated in groves, leaving open ground between groups. Their
placement uses a separate seeded generator with minimum trunk spacing, clear
island hubs, reserved bridge routes and a clear spawn area. Each tree gets a
different canopy silhouette, palette, bark and size, baked to the terrain's
world pixel grid. Forest density, group sizes and clearances are in
`resources/earth_forest_config.tres`.

Every trunk has a circular `StaticBody2D` collider. Trees and the player share
the `Actors` Y-sort layer, sorted at their ground origins: the player is drawn
behind trees when above their bases and in front when below. Canopies stay
opaque. Collision only affects trunks, so the player can walk under foliage.

### Rocks and bushes

Rocks and bushes are scattered after the forest (`NelvarPropGenerator`). Rocks
keep the same hubs, bridge routes, spawn area and passages open as trunks, have
an elliptic footprint collider and stop the player, enemies and projectiles.
Bushes gather at the foot of trees and in the open and can be walked through.
Neither is placed where a tree crown would hide it. Both Y-sort with the player
and outline it when it stands behind them. Counts and sizes are in
`resources/earth_prop_config.tres`; clearances come from the forest config.

## The Void

Rules of the route and the boss are in `GDD.md` §5.

The player wakes on debris of all four realities — torn earth, rocks, fallen
trunks, ice, cooling basalt, cloud-stone, paved ruins and violet shards —
hanging over the dark Void, and makes their way to the monolith: a black-grey
angular island that is the same in every run. The monolith is painted on a
worker thread, so the Void loads quickly.

Gaps are measured the way a player crosses them: straight from the middle of
one piece towards the middle of the next, and lines a little to either side
must stay within reach too (`NelvarVoidData.crossing_gap`, `slack_gap`). The
coyote time off an edge is `NelvarVoidData.COYOTE_TIME`. The test plays whole
Voids with the real player, from the spawn to the arena, without a single fall.

The layout comes from `NelvarVoidGenerator` (seeded like the air map), the art
from `NelvarDebrisPainter`, the sky from `scripts/void/void_sky.gdshader`.

### The Only One

Stepping into the arena on the monolith starts the fight (`NelvarVoidArena`):
the edge is sealed, the Void opens its eyes and the Only One (Единственный,
`scripts/void/boss/`) forms out of the sigil. It is one body that the fight
bends out of shape, its contours always lagging a moment behind it:

- **I · Единственный** — a hunched figure with an empty face and a huge left arm.
- **II · Искажение** — the limbs come loose from the body.
- **III · Отторжение** — it stretches, squashes and blinks part by part.
- **IV · Поглощённый** — only a crawling silhouette hovering in the centre.

The fight is lit by the boss and its attacks (violet 2D lights on the dark
arena), throws pixel sparks, and shakes the picture itself (`NelvarVoidScreen`:
shockwaves, tearing, colour fringes, slow motion at phase changes and at its
death); a title card announces it and each phase.

## Tests

Run the checks without opening a window:

```sh
godot --headless --path . --script tests/test_world.gd -- --seeds=100
godot --headless --path . --script tests/test_terrain.gd
godot --headless --path . --script tests/test_forest.gd -- --seed=20261120
godot --headless --path . --script tests/test_props.gd
godot --headless --path . --script tests/test_void.gd -- --seeds=50 --walks=6
godot --headless --path . --script tests/test_mutations.gd
godot --headless --path . --script tests/test_whistler.gd
godot --headless --path . --script tests/test_runner.gd
```

- **World** — island counts, connectivity, determinism, chunk geometry, spawn
  clearance, bridge landings, actual character movement and collision
  boundaries.
- **Terrain** — repeatable island and bridge artwork across different chunk
  subdivisions, surface coverage, grass and flower settings, hanging roots and
  unchanged map geometry.
- **Forest** — repeatable groves and tree art, trunk spacing, clear bridge
  routes, circular colliders and actual movement into and around a tree.
- **Props** — rock and bush placement rules, repeatable prop art, rock
  colliders that stop the player and bushes the player walks through.
- **Void** — walking cannot clear a leap but running can, flight covers every
  flight gap; a bot plays whole Voids from the spawn to the arena with the real
  player; the arena seals; every boss hazard hurts a player inside it and spares
  one outside; the Only One goes through its phases at their thresholds.
- **Mutations** — every mutation gains and costs at every stage; the meter
  ripens them; the player's own wait and get seized; other versions pick by
  their element; stats really change the player and the HUD; the choice opens
  on E, pauses and picks with 1/2/3.
- **Whistler** — breath, fans and trills; bubbles against walking and flying
  players, the shot, the wave and compression; the spawner's per-kind caps.
- **Runner** — chase, windup and dash, dash damage, skid and recovery, stuns
  from trunks and waves, compression cancelling the dash, getting round walls,
  death.
