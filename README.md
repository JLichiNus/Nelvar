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
- **Mouse wheel:** zoom the camera attached to the player.
- **F3:** show occupied chunks, collision boundaries, trunk circles and island IDs.

The player currently uses a static 32×32 sprite for standing and walking.
Moving left mirrors the sprite; moving right restores its original orientation.
Stopping or moving vertically preserves the last horizontal orientation.

The earth map contains 2–3 large floating islands and 6–7 small ones, connected
by narrow wooden bridges. Shorelines and bridge sides block movement; falling
and height differences are not implemented yet.

Bridge decks, board seams, rails, end caps and posts are generated procedurally
and baked onto the same world pixel grid as the islands. Angled bridges are
rasterized before display, so the finished pixels remain aligned with the
terrain. The experimental bridge tile remains in `assets/textures/bridge/`
for later use and is not loaded by the renderer.

Island artwork is painted procedurally after map generation: grass and dirt
patches, stepped shorelines, layered cliffs, branching roots and individual
grass tufts. Artwork follows a shared world pixel grid and is baked once per
island; chunks display regions of those same textures to avoid seams. Painting
does not modify the generated surface, bridges or physics. Grass avoids bridge
landings. The same seed and style reproduce the same artwork.

Visual settings are exposed in `resources/earth_terrain_style.tres`:
`pixel_size` is measured in world units (4 by default), `cliff_depth` and
`root_length` in terrain pixels, and `grass_density` controls tuft placement.

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
```

Here `godot` means the path to your Godot 4.7.2 executable. The checks cover
island counts, connectivity, determinism, chunk geometry, spawn clearance,
bridge landings, actual character movement and collision boundaries.
Terrain checks cover repeatable island and bridge artwork across different
chunk subdivisions, surface coverage, grass settings, hanging roots and
unchanged map geometry.
Forest checks cover repeatable groves and tree art, trunk spacing, clear bridge
routes, circular colliders and actual movement into and around a tree.
