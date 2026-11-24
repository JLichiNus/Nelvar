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
- **Mouse wheel:** zoom the camera attached to the player.
- **F3:** show occupied chunks, collision boundaries, trunk circles, rock footprints and island IDs.

The player (`player/player.tscn`) is drawn from two animated layers: legs play
the locomotion, the torso follows it or plays an attack on top. The node origin
is at the feet, under a circular collider of `NelvarPlayer.BODY_RADIUS`; aiming
and attacks start from the body center (`AimPivot`). Hopper enemies spawn on
walkable ground around the player, away from trunks. At zero HP the scene
restarts with a new seed.

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

### The earth valley (developer menu)

Settings → «Меню разработчика» → «Запускать игру на Земле» makes «Играть» open
`scenes/earth.tscn`: a plain of grass and groves ringed by snowy mountains, in the
style of the «Земля» menu background. Only one of the two start options is on at a
time; the hint under them says what «Играть» opens.

`NelvarEarthGenerator` lays the valley out from the seed (parameters in
`resources/earth_valley_config.tres`): a bent oval about the size of the air map,
3–5 ponds, clearings joined by trails (a spanning tree plus a few loops, two of
them running off into the mountains), petrified creatures — the menu's boulder
with a closed eye, which opens and follows the player while they are near —
groves of oaks, birches, firs, blossoming cherries, apple trees and a rare golden
maple, willows over the ponds, stands of firs along the mountain foot, rocks and
scree, stumps and fallen logs, bushes with berries or blossom, tall grass, ferns,
flowers, mushrooms, reeds and lilies. Solid things always leave a passage wider
than the player; trails, clearings and the spawn stay free of them.

The mountain foot stops everyone. Ponds are on physics layer 5 («Water»): they
stop the player and enemies but not projectiles. Rows of peaks stand round the
valley and sort with the player like trees (lower on the south side, where they
stand between the camera and the plain). Peaks differ in look
(`NelvarEarthData.Peak`): summits with shoulders, broad massifs of several tops,
clusters of rocky needles, flat-topped peaks with a cap of layered rock, and
behind the nearest row rare giants with glaciers down their gullies; the rock
takes one of three tints (grey-blue, warm grey-brown, slate). Each peak is a
height field over a round base drawn in the map's oblique view, so its tops,
ridges, saddles and snowfields face the camera and its base is a curve sinking
into the ground; the slopes are lit by the same upper-right sun as everything
else (tops and eastern slopes bright, western ones in shade), snow lies on the
high gentle ground, grass and firs climb the low slopes, the gullies and the
saddles. Under the range lies its foot — darker ground, scree and stands of
firs — and the peaks cast slanted shadows down and to the left over the uplands
and the valley (`NelvarMountainField`, drawn by the floor shader). The valley's
grass runs on past the mountain foot without a seam. Some peaks of the nearest row carry a waterfall,
animated by `waterfall.gdshader` (the painter keys its water, foam and mist by
alpha). The outer row breaks up, and beyond it lie the uplands drawn by the floor
shader: the valley again, duller and with less detail — meadows on uneven grassy
terraces, groves and lone trees, now and then a lake — with rocky crags and
boulders standing on them.

Everything in the valley and the peaks round it is painted on several cores while
the scene loads (`NelvarEarthPainter`, `NelvarEarthCanvas`, `NelvarMountainPainter`),
so the map opens complete; past about half the cores script threads mostly wait
for each other, so the painting uses no more than that. The floor is a
shader (`scripts/earth/earth_ground.gdshader`, run through `NelvarCloudSea` with
parallax 1) fed by a ground map (`NelvarEarthField`): grass patches, tufts that
bend as gusts run across the meadow, flowers, trails with pebbles, ponds with a
shaded north bank and drifting glints, leaf litter under the crowns. Plants lean
with the same gusts in whole art pixels. Cloud shadows drift over everything
(`cloud_shadows.gdshader`, multiplied over the world), pollen floats in the air
and butterflies flutter between flowers and scatter from the player
(`NelvarButterflies`). F3 shows the colliders, the mountain foot and the shores.

### The fire forge (developer menu)

Settings → «Меню разработчика» → «Запускать игру в Огне» makes «Играть» open
`scenes/fire.tscn`: a basin of ash and basalt ringed by black ridges and volcanoes, in
the style of the «Огонь» menu background — a world that is still being forged rather
than one that burnt. Only one of the start options is on at a time.

`NelvarFireGenerator` lays it out from the seed (parameters in
`resources/fire_forge_config.tres`): 1–2 great volcanoes in the north of the ring,
2–4 lava lakes (the bigger ones hold islands of black plates), a lava stream from under
each volcano into a lake (sometimes one from lake to lake), roads of cooled lava — black,
glossy and wrinkled — joining the clearings, magma fissures (about half of them erupt),
magma fields where the basalt's joints glow, fumarole fields with yellow sulfur and banks
of smoke over them, stands of burnt trees (charred with embers at the tips, smouldering
trunks split open and glowing, grey ashen ones) and small groves of emberleaves — the
red-crowned tree that lives in the heat — broken snags and logs, basalt boulders (bare,
capped with ash or glowing through their cracks), blue-green crystals and a few plants:
ember grass, ash flowers, scorched shrubs.

Lava is on physics layer 7 («Lava»): it stops the walking player but not the flying one
(Shift) and not projectiles. Whoever comes down in it burns: the player sinks in a flash
of sparks and comes back on the ground they last stood on safely, 20 HP worse for it.
Standing right at the lava's edge scorches a little. Every stretch of a stream inside the
basin has a crossing — a raft of set crust — within `crossing_spacing`, so all open ground
can be reached on foot; the islands only by flight. Hoppers do not jump into the lava
(`is_safe_landing`), but a wind wave can blow them in, and then they burn. An active
fissure glows brighter for a moment, then erupts: the burst hurts whoever stands on the
crack (flight passes over it) and throws hoppers back.

The ridges are `NelvarMountainPainter`'s height fields painted by `NelvarVolcanoPainter`:
basalt with a fiery rim on the skyline, columnar walls, dull ash where snow would lie,
cinder slopes with dead snags. The giant's look is a volcano with a crater; the molten
ones hold lava, and a great volcano's runs down its front to where its stream begins.
Some massifs pour lavafalls; cinder cones stand on the plateau beyond. Glowing pixels of
every sprite are keyed by alpha and animated by `fire_molten.gdshader` (flowing lava,
churning hot spots, breathing embers).

The floor (`scripts/fire/fire_ground.gdshader`, fed by `NelvarFireField`) draws the
cooling joints, ash ripples, cinder, roads, sulfur, plates, fissures and the lava — floes
of crust drifting with each stream's flow or churning slowly in a lake, a hot rim at the
shore — and beyond the ridges the land runs on with rivers of lava. Over the world:
the light of the lava and the magma, breathing slowly and added in dithered steps
(`fire_glow.gdshader`), eruptions and craters flashing; shadows of smoke drifting by; heat
haze shimmering over the lava and the fissures (`NelvarHeatHaze`). Ash drifts and sparks
rise from the lava, glowing cracks and craters (`NelvarEmbers`); wisps rise from the vents
and smouldering trunks and plumes from the craters (`NelvarSmoke`). The player's wind
blows ash, sparks and smoke away and thins the smoke banks, which grow back. Ember moths
flutter over the heat and scatter, salamanders bask on the shores and dive into the lava
when the player comes close (`NelvarFireCritters`). F3 shows the walls and the fissures.

### The ice valley (developer menu)

Settings → «Меню разработчика» → «Запускать игру на Льду» makes «Играть» open
`scenes/ice.tscn`: a snowy valley ringed by snowy mountains, in the style of the «Лёд»
menu background — snow with sastrugi and sparkles, dry stems poking out of it, pines
under snow, dead trees, rocks with snow caps, drifts, blocks of ice, petrified creatures
with an eye, frozen lakes.

`NelvarIceGenerator` lays it out from the seed (parameters in
`resources/ice_valley_config.tres`): 2–4 frozen lakes with 1–3 patches of thin ice each
and 1–3 creatures frozen into each, 2–4 crevasses from the mountain foot (some branching
off another) whose width wanders along them, snow bridges over them, trodden trails
between the clearings, groves of pines, dead trees, rocks and scree, drifts in the lee of
rocks and trees, blocks and pressure ridges of ice (a few out on the lakes, the only cover
there), dry grass and bare shrubs, fields of wind-blown snow, and the rows of peaks.
Every stretch of a crevasse inside the valley has a bridge within `bridge_spacing`,
trails cross crevasses only on bridges, and no crevasse comes within `ice_gap` (250) of the
ice, so nobody slides off the ice into one. The spawn is on the snow.

There are no walls but the mountain foot:

- **The ice is slippery.** The map sets the player's `traction` every frame (snow 1, ice
  0.15): on the ice they speed up slowly and coast a few body lengths after the keys are
  let go. Hoppers take the grip too (`grip_at`): the wind wave blows them far over the ice,
  and they slip a little where they land.
- **Under the ice** (`NelvarIceDepths`, below the floor, which is translucent on the ice
  through `NelvarCloudSea.transparent`) lies dark water with creatures frozen into it. It
  follows the camera by 0.85, snapped to whole art pixels; the thin ice shows it best.
  Some creatures slowly open an eye while the player stands over them and follow them.
- **Crevasses** are falls. A step over one holds for a moment (0.09 s): walking is too
  slow for any crack, a run (Ctrl) crosses up to about 40 wide, the flight (Shift) crosses
  anything, the bridges are always there. A fall throws the player back on the snow they
  last stood on safely, 12 HP worse; the first one says how a crevasse is crossed.
- **Thin ice** holds a running player, not a standing one: standing still on it for 0.35 s
  cracks it, and unless the player gets 40 away within 0.8 s it breaks into a hole and
  they fall into the water (back on safe snow, 12 HP). A crack that held stays for 10 s and
  breaks under the next step. A hole is open water, then slush, then thin ice again over
  25 s. The flight leaves the ice alone.
- **Blizzards** cross the valley (radius 500–800, 40–60 s, lulls of 40–70 s, planned from
  the seed). Inside one the player moves at 0.7 and attacks at 0.65 of their pace
  (`move_scale`, `attack_rate`: cooldowns, animations, projectile speed, the wave), hoppers
  jump a little shorter (`jump_scale_at`), and a veil with dashes of snow covers the screen
  (`NelvarBlizzard`). About 4 s before one arrives, snow streams along that edge of the
  screen and «Надвигается метель» appears.
- **Marks in the snow** (`NelvarSnowMarks`): the player leaves a swept furrow, a hopper a
  dent where it lands. They live in a texture that is only drawn when there are new
  marks; each pixel keeps the snow clock at its stamp, and the clock runs six times faster
  in a blizzard, so blizzards drift the marks over faster. Marks show on snow only.
- Hoppers do not jump into crevasses, holes or onto thin ice (`is_safe_landing`); blown
  into a crevasse they fall, into a hole they drown.

The floor (`scripts/ice/ice_ground.gdshader`, fed by `NelvarIceField`) draws the snow,
trails, ice with white veins and drifting glints, thin ice, crevasses (the north wall of
blue ice dropping into the dark, a snow cornice on the near edge), bridges, holes, cracks
and marks, and beyond the foot the snowy uplands. The peaks are `NelvarMountainPainter`'s
height fields painted by `NelvarFrostPainter`: grey-blue rock, deep snow, glaciers, frosted
pines on a snowy foot. Snow falls over everything. F3 shows the mountain foot, the lakes
and their thin ice, the crevasses with their bridges and the holes.

The earth map contains 2–3 large floating islands and 6–7 small ones, connected
by narrow wooden bridges. Shorelines and bridge sides block movement; falling
and height differences are not implemented yet.

The world wears the style of the air reality from the main menu. The islands
float above a sea of clouds (`scripts/world/cloud_sea.gd` and its shader): puffy
pixel clouds in overlapping rows, lit from the upper right and dithered like the
menu art, with small gaps where the sky shows through. Puffs come in two layers —
a field of small and middling ones and sparse big billows over it — and whole
areas of the sea hold more big billows or more small fluff. The sea lies deeper than
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

Trees are generated in few small groves, leaving open ground between groups:
the air map is windswept and sparse, and many small islands stay bare. Each tree
is young, grown or old, so sizes in a grove clearly differ, and the number of
crown tiers follows the crown size. Their
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
godot --headless --path . --script tests/test_earth.gd -- --seeds=30
godot --headless --path . --script tests/test_fire.gd -- --seeds=30
godot --headless --path . --script tests/test_ice.gd -- --seeds=30
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
Earth checks cover the valley layout (ponds, dry trails, passages between solid
things, tree species, a closed ring of peaks), that nearly all open ground is
reachable from the spawn, repeatable art on the world grid, the ground map, the
start setting, and in the real scene: the mountain foot and ponds stop the player,
projectiles fly over water, trunks block and tall grass does not, statues open
their eye, plants sway, every peak is painted and enemies appear on open ground.
Fire checks cover the forge's layout (lava, crossings, roads, islands, fissures,
passages, a closed ring of ridges), that open ground is reachable across the crossings,
repeatable art on the world grid (volcanoes with lava running down them), the ground and
light maps, the start setting, and in the real scene: lava stops the walking player, the
flight carries them over a lake, coming down in it burns and throws them back, crossings
let them over a stream, a hopper blown into the lava burns, a fissure erupts and hurts,
a salamander dives and the wind thins a smoke bank.
Ice checks cover the valley's layout (lakes, thin ice inside them, crevasses far from the
ice and bridged, trails off the ice and the cracks, passages, frozen creatures under the
ice, a closed ring of peaks), that open ground is reachable over the bridges, repeatable
art on the world grid, the floor map, the start setting, and in the real scene: the
player coasts much further on the ice, a wide crevasse drops a walker and throws them
back hurt, the flight crosses it and a run crosses a narrow one, thin ice breaks under a
standing player and not under a running one, a hole freezes over, hoppers blown into a
crevasse or a hole die, a blizzard slows the player and lets go, walking leaves marks in
the snow and a frozen creature opens its eye.
