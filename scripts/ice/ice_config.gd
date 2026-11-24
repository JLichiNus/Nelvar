class_name NelvarIceConfig
extends Resource
## Generation parameters of the ice valley (developer setting "Запускать игру на Льду").
## Distances are world units; the valley is centred on the origin.

@export_group("Valley")
## Half-size of the valley floor: about the earth valley's.
@export var valley_radius: Vector2 = Vector2(1750.0, 1500.0)
## Relative depth of the slow bends of the mountain foot.
@export_range(0.0, 0.2, 0.01) var valley_wobble: float = 0.09
@export_range(64, 512) var boundary_vertices: int = 256
## Open snow around the spawn.
@export var spawn_clearance: float = 180.0

@export_group("Lakes")
@export var lake_count: Vector2i = Vector2i(2, 4)
## Horizontal radius of a frozen lake: bigger than the earth's ponds.
@export var lake_radius: Vector2 = Vector2(220.0, 420.0)
## Smallest snow between two lakes.
@export var lake_gap: float = 260.0
## Smallest snow between a lake and the mountain foot.
@export var lake_margin: float = 260.0
@export_range(24, 128) var lake_vertices: int = 72
## Patches of thin ice in each lake.
@export var thin_patches: Vector2i = Vector2i(1, 3)
@export var thin_radius: Vector2 = Vector2(48.0, 100.0)
## Creatures frozen into each lake; a share of them follow the player with an eye.
@export var frozen_per_lake: Vector2i = Vector2i(1, 3)
@export_range(0.0, 1.0, 0.05) var watching_share: float = 0.5

@export_group("Crevasses")
@export var crevasse_count: Vector2i = Vector2i(2, 4)
## Half width of a crevasse, changing along it.
@export var crevasse_half_width: Vector2 = Vector2(14.0, 40.0)
## Smallest snow between a crevasse and the ice: sliding off the ice into it is unfair.
@export var ice_gap: float = 250.0
## Longest stretch of a crevasse without a snow bridge (inside the valley).
@export var bridge_spacing: float = 520.0
## Half the length of a snow bridge, along the crevasse.
@export var bridge_half_length: float = 46.0

@export_group("Paths")
## Clearings the trails connect, besides the spawn and the lakes.
@export var clearing_count: Vector2i = Vector2i(4, 6)
@export var clearing_radius: Vector2 = Vector2(90.0, 150.0)
@export var path_half_width: Vector2 = Vector2(13.0, 20.0)
## Loops added to the tree of trails.
@export_range(0, 6) var extra_paths: int = 2
## Trails that run off into the mountains.
@export_range(0, 4) var mountain_trails: int = 2

@export_group("Trees")
@export var pine_groves: Vector2i = Vector2i(7, 9)
@export var grove_radius: Vector2 = Vector2(160.0, 280.0)
@export var grove_trees: Vector2i = Vector2i(4, 9)
@export var lone_pines: Vector2i = Vector2i(8, 12)
## Dead standing trees (сухостой), alone or at the edge of the groves.
@export var dead_trees: Vector2i = Vector2i(8, 12)
## Smallest distance between two trunks.
@export var tree_spacing: float = 92.0
## Free ground kept between any two solid things (more than the player is wide).
@export var passage_width: float = 46.0
## Free ground beside a trail, in addition to its half width.
@export var path_clearance: float = 26.0
## Free ground kept between solid things and a crevasse.
@export var crevasse_clearance: float = 40.0

@export_group("Stone and snow")
@export var rocks: Vector2i = Vector2i(13, 19)
## Boulders gathered at the mountain foot.
@export var scree_rocks: Vector2i = Vector2i(20, 28)
## Petrified creatures with an eye, as on the menu background.
@export var statues: Vector2i = Vector2i(2, 4)
## Snowdrifts: low, solid mounds.
@export var drifts: Vector2i = Vector2i(12, 18)
## Blocks and ridges of ice on the snow by the lakes and at the foot.
@export var ice_blocks: Vector2i = Vector2i(6, 10)
## Blocks standing out on the ice of each lake (cover out on the slippery ground).
@export var lake_blocks: Vector2i = Vector2i(1, 3)
## Fields of wind-blown snow (shown by the floor only).
@export var snow_banks: Vector2i = Vector2i(5, 8)

@export_group("Plants")
@export var dry_grass: Vector2i = Vector2i(44, 64)
@export var shrubs: Vector2i = Vector2i(14, 22)

@export_group("Mountains")
## Rows of peaks around the valley, from the foot outwards.
@export_range(1, 4) var peak_rows: int = 3
@export var plateau_crags: Vector2i = Vector2i(18, 24)
@export var plateau_boulders: Vector2i = Vector2i(35, 50)


func validation_error() -> String:
	if valley_radius.x < 800.0 or valley_radius.y < 800.0:
		return "The valley is too small."
	if lake_count.x < 1 or lake_count.y < lake_count.x:
		return "Invalid lake count."
	if lake_radius.x <= 120.0 or lake_radius.y < lake_radius.x:
		return "Invalid lake radius."
	if thin_radius.x < NelvarPlayer.BODY_RADIUS * 2.0 or thin_radius.y < thin_radius.x:
		return "Invalid thin ice radius."
	if crevasse_count.x < 0 or crevasse_count.y < crevasse_count.x:
		return "Invalid crevasse count."
	if crevasse_half_width.x < 8.0 or crevasse_half_width.y < crevasse_half_width.x:
		return "Invalid crevasse width."
	if bridge_half_length < NelvarPlayer.BODY_RADIUS * 2.0:
		return "Snow bridges are narrower than the player."
	if path_half_width.x < 8.0 or path_half_width.y < path_half_width.x:
		return "Invalid path width."
	if passage_width < NelvarPlayer.BODY_RADIUS * 2.0 + 4.0:
		return "Passages are narrower than the player."
	if tree_spacing <= 0.0 or boundary_vertices < 64:
		return "Invalid spacing or boundary resolution."
	return ""
