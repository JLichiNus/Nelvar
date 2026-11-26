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

### Enemies

The spawner (`enemies/enemy_spawner.gd`) brings several kinds: each spawn picks
an `NelvarEnemyKind` (scene, weight, own cap) among those below their cap. On the
air map: hoppers (weight 3), Runners (weight 2, at most 4 alive) and Whistlers
(weight 1, at most 3 alive).

- **Прыгун** (`enemies/hopper/`) — a ball that hops about at random; hurts on touch.
- **Свистун** (`enemies/whistler/`) — a hollow sack of dry reed rooted in the
  ground, with a tube for a mouth that turns after the player. Within 640 of the
  player it draws breath for 0.9 s — swells, quivers, air streams into the tube and
  it whistles higher; the tube stops following 0.25 s before the blow — and blows
  slow pink soap bubbles: a fan of 3–5, or (30%) a trill of three aimed one by one.
  A bubble floats above its shadow, which is its collider; it hurts a walking player
  (10) and passes a flying one, bursts on trunks and rocks but drifts over shores
  and rails. The LMB shot bursts it; the RMB wave turns it back (`deflect`): it
  takes the colours of the wind, flies twice as fast toward an enemy near the
  wave's direction and hits it for 30. R compression breaks off a breath. 45 HP,
  light contact damage; a wave only rocks it.

- **Бегунок** (`enemies/runner/`) — a tiny fluffy bird on long legs. It chases
  the player at 250 (slower than a walk), curving round to come from the side, and
  Runners keep a little apart. When the player is 160–390 away and nothing stands
  between them it winds up for 0.6 s — crouches, scratches the ground, chirps, and a
  dashed orange arrow grows along the ground, following the player until it turns
  light and locks 0.18 s before the dash — then dashes 760 for 0.42 s, hurting 14
  instead of 8, with a wind trail behind. A miss ends in a skid and a moment out of
  breath. A dash into a trunk or rock bounces it off stunned for 1.4 s (stars over its
  head, harmless to touch); an RMB wave that catches it winding up or dashing knocks
  it over for 0.9 s; R compression cancels the dash. 35 HP; it dies in a puff of
  feathers.

Enemy sounds are positional (`AudioStreamPlayer2D`); those that must outlive
their source (a popped bubble, a dead Whistler) are played by
`NelvarOneShotSound`, which also skips the same sound repeated within 40 ms.

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
The Whistler draws breath with a rising whistle (`whistler_inhale_*`, 0.9 s, as
long as the breath), blows a fan with a falling "pfoo" (`whistler_blow_*`) or a
trill of three notes (`whistler_toot_1..3`, played in order), knocks hollow when
hit (`whistler_hurt_*`) and wheezes as it deflates (`whistler_death_*`). Its
bubbles pop (`bubble_pop_*`) and, turned back by the wave, bounce off with a
springy "bwip" (`bubble_deflect_*`).
The Runner patters with every footfall (`runner_step_*`, quiet), chirps through
its windup (`runner_chirp_*`, 0.6 s), takes off with a flutter and a rush of air
(`runner_dash_*`), scrapes into a skid (`runner_skid_*`), bonks into trunks and
tweets dizzily (`runner_bonk_*`), peeps when hit (`runner_hurt_*`) and dies with a
squawk and a puff of feathers (`runner_death_*`).

The final boss has its own sounds in `assets/audio/sfx/boss/`, synthesised by
`tools/gen_boss_sfx.py` (`boss_sfx_a.py`, `boss_sfx_b.py`, shared tools in
`boss_sfx_common.py`). Every sound has three candidate variants:
`--preview DIR` writes them all for listening, `--pick name=k ...` writes the
chosen ones into the game. They are played by `NelvarBossSound`
(`scripts/void/boss/boss_sound.gd`) as positional sounds where the attack
happens: the aim, lock and rush of a dash, a tear charging and erupting and then
crackling, a gravity well appearing, charging (timed to end on its burst), stopping
still and bursting (twins differ in pitch), a rift cracking and opening (the sound
rides the light along it) and then humming, the collapse's quickening ticks, strike
and reversal, the shard rings' charge, launch and turn, a shard hitting, and the
squeeze's groan, rising spiral, the beacon of the way out at the gap and the final
blast. Around the boss: its intro, a low presence that sinks with every phase, hits,
phase shifts and death. Hits, cracks and many rifts at once have a shortest gap and
a voice limit, so a burst of them is heard as one event. Loops
(`boss_presence`, `trail_crackle`, `rift_hum`, `squeeze_beacon`) are imported
with loop mode Forward.

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

Each phase has its own 3200 HP: the bar at the top shows only the current phase,
empties, and fills up again in the next phase's colour; diamonds under it count
the phases. The attacks follow three rules: the difficulty is in their geometry,
they get in the way of hitting the boss, and every one can be avoided at plain
walking or running speed.

- **I · Единственный** — a hunched figure with an empty face and a huge left arm.
  A dash that leads the player (the aim follows them, then locks just before it
  goes) and leaves a tear in space that bursts out to both sides a second later;
  a gravity well that pulls harder and grows its burst circle as it charges; a
  rift whose energy runs along it as a wave and stays open for 2 s.
- **II · Искажение** — the limbs come loose from the body. Two leading dashes, a
  well that creeps after the player and stops before it bursts, three parallel
  rifts that cut the floor into narrow corridors.
- **III · Отторжение** — it stretches, squashes and blinks part by part. Three
  dashes whose tears all stay open and divide the arena; twin wells circling one
  point, pulling in turn and bursting one after the other; a maze of crossing
  rifts that closes one corridor after another, always leaving a way out; the
  collapse: 42° sectors turning around the boss with 18° lanes between them, no
  safe spot at its feet, and a warned reversal.
- **IV · Поглощённый** — only a crawling silhouette hovering in the centre. Two
  rings of shards on spiral paths that curl back the other way, the second ring
  crossing the first; and the squeeze: an accelerating ring of the Void whose one
  gap sweeps around the boss.

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

### The volcano, Fire 2 (developer menu)

Settings → «Меню разработчика» → «Запускать игру в Огне 2» makes «Играть» open
`scenes/fire2.tscn`: the top of one huge volcano. A broad rim of basalt and ash runs
right round the crater; the crater is a lake of lava filled almost to the brim, crowded
with floes of magma crust; past the rim's outer edge there is
nothing but a drop into clouds of ash far below. The camera looks down from the south, so under the southern edge the
mountain's front slope runs down the screen until the clouds swallow it. The forge
(«Огонь») stays as it is; both maps live side by side.

`NelvarCraterGenerator` lays it out from the seed (parameters in
`resources/fire_crater_config.tres`):

- **The lake and the rim.** The lake is about 1960×1840; the rim round it is 400–500
  wide (never under 340) and bulges out further at 2–4 **terraces**, broad places to
  fight on. The spawn is on the southern one, looking north over the lava. A ring road of cooled
  lava runs all the way round the rim (solid things keep off it, so the way round is never
  blocked), with spurs to the capes and out onto the terraces.
- **Capes** (3–5): tongues of rock reaching 150–320 into the lake from the shore.
- **Floes of magma crust** (about 180–230, radius 44–230; `NelvarCraterData.floes`) are
  the only ground on the lake: dark plates with glowing seams covering much of it, of
  every size (more small than broad) and shape — round, oval, long slabs,
  three-cornered, lobed. They grow out from the shore, each a step of lava (16–26) from
  the one it grew from, until there is no room left; any floe that cannot be reached
  from the shore in steps of at most a run is dropped, so one can walk from the rim to
  the vent's moat. All of them sway together on one slow swell (6–10 out on each axis,
  one sway in 50–100 s, its wave 7000 long), so the steps between neighbours hold.
  Wherever the swell takes it, a floe stays in the lava, clear of the shore, the capes,
  the vent's moat, the boiling patches and the other floes. A floe holds whoever walks
  on it, unharmed, and carries them along. About a third of them (more of the small
  ones) **sink** by themselves every 30–55 s for 5–8 s: 3 s of warning (the seams
  flare, lava bubbles along the edge), 1.2 s going down from the edge in, then up again
  red-hot, cooling in 2 s. Where a floe is and whether it is under depends on the time
  only, so every layout is reproducible.
- **The vent** churns white-hot in the middle of the lake under a heavy plume, spitting
  fountains of lava; 3–5 **boiling patches** bubble brighter. The air shimmers only over
  these and over the smoke banks (`heat_haze.gdshader`'s `use_haze_mask`), not over the
  whole lake.
- **Geysers** (7–10, at least two on the capes as springboards out over the floes): every 10–16 s the mouth
  glows and trembles for 1.5 s, then a column of steam with a core of fire bursts for
  0.9 s. Whoever stands in the mouth takes 6 HP and is thrown (`NelvarPlayer.launch`) up
  and along their run-up ×1.25 for 1.1 s, steering at 35%; airborne, lava and hoppers do
  not touch them, and landing in the lava burns. Hoppers in the mouth take 20 and are
  thrown back.
- Stones, crystals, snags (a charred tree or two at most), vents over sulfur under smoke
  banks, ember grass by the lava, ash flowers and shrubs.

Nothing is a wall here: **the lava and the edge are falls**. A
step over either holds for 0.12 s (sparks hiss under the player over the lava), then the
player goes down — burnt in the lava (20 HP) or dropped into the clouds (15 HP) — and
comes back where they last stood safely: on the rim (clear of the lake, the edge, the
geysers and any splash) or on a floe that never sinks, well in from its edge (then
where that floe has drifted to). A floe carries whoever stands on it (hoppers too).
Sinking eats a floe from the edge in, the same way on screen and for the logic; whoever
is on it goes down with it. After the first fall the game says what to do («Эта плита
уходит под лаву…», «Лава не держит…»). Every 7–12 s **lava splashes**
over a shore or a broad floe's edge 250–800 from the player (`NelvarLavaSplashes`): it bulges
and bubbles for 1.3 s, then a tongue of lava sloshes over (10 HP and a shove away from
the lake); the fresh lava burns (4 HP every 0.5 s) and slows to 0.6 for 3 s, sets into a
safe crust for 8 s and fades. Hoppers burn in the lava (floes hold them),
die off the edge and on a sinking floe, and never land in a geyser or fresh lava.

The floor (`scripts/crater/crater_ground.gdshader`) computes the lake, the capes and
the summit's edge exactly as `NelvarCraterData` does (the edge from a table of
radii), and reads roads and sulfur from `NelvarCraterField`. It shares the forge's palette
and surfaces through `scripts/fire/fire_common.gdshaderinc`. The lava lies still in broad
flat swirls (no dithering, nothing to shimmer); everything that floats on it is a sprite
on whole art pixels; the crater's inner wall shows under the north shore, only a few art
pixels high; the front slope (its top row per column baked into a 1D texture) has ribs
and gullies spreading like a cone, short ledges, ash drifts and lava trickling down a few
gullies, and darkens into the clouds. Past the edge the floor is transparent and the
clouds of ash show through from the layer below (`crater_below.gdshader` on
`NelvarCloudSea`, parallax 0.6), with dark land and rivers of lava in their gaps. The
floes are sprites (`NelvarCraterIsland`, a baked mask and `crater_island.gdshader`)
on whole art pixels; geyser columns and the vent's fountains are `NelvarGeysers`; tongues of flame
lick up along the shores, over the boils and the splashes (`NelvarEmbers.flame`), ash falls
thicker than in the forge. F3 shows the edge, the shore and the capes, the floes as they are
now (the ones that sink in cyan), the geysers and the splashes.

### The ice cave, Ice 2 (developer menu)

Settings → «Меню разработчика» → «Запускать игру на Льду 2» (right under «на Льду») makes
«Играть» open `scenes/ice2.tscn`: a maze of halls and winding passages cut into a mass of
blue ice with dead creatures frozen into it. Mostly dusk; under holes in the roof the sun
shines in slanting shafts, snow falls and lies, pines grow; the biggest halls are cold,
with frost, mist, ice pillars and geysers. The ice valley (Ice 1) stays as it is; both
maps live side by side.

`NelvarCaveGenerator` lays it out from the seed (parameters in
`resources/ice_cave_config.tres`) in a cave of 5200×4200 with solid ice all round:

- **Halls:** 2–3 cold arenas (radius 450–650), 3–5 sunny halls (260–380), 5–8 dark ones
  (200–320) and 4–7 grottos (90–150), at least 220 of ice apart. The start is on the snow
  of a sunny hall with a way out to the north, so it is in view at once.
- **Passages:** a spanning tree of the Delaunay triangulation of the halls plus 35–50% of
  its other edges (loops: many ways to a place); edges grazing a third hall are left out;
  every hall has two ways out, every grotto hangs on one (dead ends). A passage winds, its
  half width wanders between 50 and 95, now and then it narrows to a slit (36, a hopper
  gets through); niches and pockets beside it hold the things, the way stays free. 2–4
  passages are smooth slippery ice. The big halls get 2–6 ice pillars (cover).
- **The walls are one distance field** (`NelvarCaveData.sdf`, a sample every 8 units,
  exact near the outline, a distance transform further in). Walls thinner than a south
  face needs are cut into the floor first, crumbs of ice and cut-off pockets of floor go.
  The collision is its zero line by marching squares (`NelvarCaveWalls`, chunks of 512, on
  World and on layer 9 «Walls»), the logic reads it bilinearly (`wall_depth`), and so does
  the floor shader per art pixel: one boundary for all three. The flight does not pass
  over the walls.
- **Zones:** sunny spots (160–320) with snow round them and in tongues into the passages,
  cold halls with soft edges (120), geysers' warmth (170–240), the icy passages, the grottos.
- **Lakes:** 2–4 frozen (thin patches as on the valley, creatures frozen in, some watch),
  1–2 melting (300–400 across) and 1–3 of open water (a band of melting ice round it,
  bodies floating on it). Melting ice and open water are never on the only way anywhere:
  after each of them, each chasm and each crevasse the floor is searched from the start.
- **Chasms** (2–3): one splits a hall (one end runs into the ice, the other tapers out on
  the floor), the others cross passages. Ice arches (50–80 wide, at most 300 long) carry
  every needed way over them; narrow places (`leaps`) are crossed at a run (up to 34) or
  in flight (up to 100). 2–4 short crevasses with snow bridges, as on the valley.
- **Creatures:** 14–24 frozen in the walls 40–220 from the floor, seen from the passages
  through the ice (~30% open an eye as the player walks by), one or two giants running
  through the ice from one passage to another, 6–10 caught in ice flows at the foot of
  the south faces (some heads watch), the winged and the crawler besides the valley's
  beast, fish and serpent.
- **Things:** crystals (shards, druses, hexagonal columns, slabs, fans; clear blue, deep
  blue, now and then violet; about 30% glow), boulders with snow caps on the snow and frost
  caps in the dark, smooth stones of ice, stalagmites round the geysers and under the sun,
  bones, pines and drifts on the snow, blocks of ice on the frozen lakes, statues in the
  grottos. Solid things keep off the passages' ways, the halls' middles and the start.

Playing it (`NelvarCaveMain`; the falls, the thin ice and the holes are the valley's own,
now `NelvarIceHazards`):

- The dark is an overlay multiplied over everything (`cave_shade.gdshader`): a cold blue
  dusk, the sun leaves things as they are, the player carries a soft light of 190. The
  light is added on top (`cave_shine.gdshader`): shafts from the holes in the roof to the
  upper left with motes in them, the glow of the crystals and of the ice by the sun, the
  geysers' warmth and eruptions, the mist of the cold halls. Both read a coarse light map
  (`NelvarCaveField`: sun, glow, warmth, cold); there is no mini-map — the sun, the steam
  and the glowing crystals are the landmarks.
- **Melting ice** gives even under a walker: the strain grows to 1 in 1 s on the move,
  2.5 times faster standing, and eases twice as fast off it; at 0.5 cracks run under the
  player, at 0.8 the water seeps up, at 1 a hole opens and they fall into the water. A walk
  does not get across, a run does, the flight passes over. **Open water**, **chasms** and
  **crevasses** are falls (0.09 s on the edge, then back on safe ground with 12 HP less).
- **Geysers** (1–3 per cold hall) go round every 14–22 s: 1.5 s of bubbling, 1.2 s of
  eruption (a column of water and steam, a flash of warm light), the warmth wider for 4 s.
  The blast throws hoppers back from the mouth; the player is never hurt or thrown. Steam
  (`NelvarSmoke` in white) hangs over them and is blown away by the wind.
- **Snow** takes the marks of the valley (`NelvarSnowMarks`, now asking `is_snow()`); snow
  falls through each hole in the roof while it is near the screen.
- **Enemies:** the spawner only puts a hopper where the way on foot from the player is
  short (`path_distance`, a grid of 32 searched again when the player moves on), not in
  the next passage behind a wall; hoppers never jump into a drop or onto thin or melting
  ice, and die when blown into one; the wind wave and the compression stop at the walls
  (`NelvarPlayer.sight_mask`, 0 on every other map).

The floor (`scripts/cave/cave_ground.gdshader`) draws the walls' south faces (layers of
blue ice, light running down, icicles, frost and shards at their foot), the translucent
tops of the ice (slabs with cracks; `NelvarIceDepths` shows deep ice with bubbles and the
frozen creatures under them), stone in frost with frost flowers and pebbles, wet stone,
puddles and travertine by the geysers, snow, smooth ice, the three kinds of lake, and the
chasms — the far wall of ice dropping into the dark, the abyss under them
(`cave_abyss.gdshader`: ledges, mist, settling snow dust, very rarely something enormous),
the arches with their shadow on it. Snow, lake ice, crevasses, bridges, holes, cracks and
marks come from `scripts/ice/ice_common.gdshaderinc`, shared with the valley. F3 shows the
walls' collision, the halls by kind and the passages (icy ones in aquamarine), the chasms
with their arches, the crevasses with their bridges, the lakes by kind with their thin
ice, the geysers' warmth and blast, the edges of the cold, the sunny spots, the holes and
the spawner's path grid round the player.

The earth map contains 2–3 large floating islands and 6–7 small ones, connected
by narrow wooden bridges. Shorelines and bridge sides are on their own physics
layer 8 («Edges», `NelvarWorldData.EDGE_LAYER`): they stop enemies, but not the
player or projectiles. Off the ground the player keeps going for a moment
(`COYOTE_TIME` in `scripts/main.gd`), longer is a fall: they sink into the clouds,
lose 10 HP and come back where they last stood firmly (`SAFE_CLEARANCE` from any
edge, so the middle of a bridge counts). The flight (Shift) carries them over the
sky, even from island to island, but landing in it is a fall too. Height
differences are not implemented yet.

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
godot --headless --path . --script tests/test_crater.gd -- --seeds=30
godot --headless --path . --script tests/test_cave.gd -- --seeds=6
godot --headless --path . --script tests/test_mutations.gd
godot --headless --path . --script tests/test_whistler.gd
godot --headless --path . --script tests/test_runner.gd
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
Volcano checks cover the layout (the rim never narrower than its minimum, capes as long
as asked, geysers and things on rock, passages, the ring road on rock all the way round,
the front slope's table on the summit's edge), that floes never run aground or touch
each other, drift slowly, make a way on foot from the shore to every floe and to the
vent's moat, and about the asked share of them sink, determinism, the light and haze
maps, the floes' masks, the five start options, and in the real scene: a floe holds the
player unharmed and carries them exactly as far as it drifts, a fall from it comes back
onto it, a step into the lava and off the edge are falls that throw the player back hurt
while a moment over the lava is not, a sinking floe takes the player down and says why,
a geyser hurts and throws (and a throw into the lava burns), a splash hurts and shoves,
its fresh lava burns and slows and its crust does not, and hoppers die in the lava, off
the edge and on a sinking floe.
Cave checks cover the layout (halls of every kind, two ways out of every hall and one out
of every grotto, at least three loops, the start on the snow of a sunny hall, geysers in
the cold halls, snow only round the sun and the pines and drifts on it, things clear of the
ice and the drops, creatures where they can be seen, bodies on open water), that every hall
can be walked to without melting ice or water and through ways wider than a hopper, the
wall over every south face, that the collision, the queries and the shader's field see one
boundary, the floor and light maps against the queries, repeatable art for every kind,
creature and crystal, the six start options, and in the real scene: the walls hold even in
flight, melting ice gives under a walker and not under a runner and at once under a
stander, open water and a chasm drop the player and bring them back hurt, a run crosses a
narrow place of a chasm, thin ice breaks, an icy passage slides, snow takes marks and stone
does not, hoppers blown into a drop die, the wave stops at a wall, an eruption throws a
hopper and leaves the player be, and the spawner keeps to short ways on foot.
