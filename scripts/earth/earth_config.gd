class_name NelvarEarthConfig
extends Resource
## Generation parameters of the earth valley (developer setting "Запускать игру на
## Земле"). Distances are world units; the valley is centred on the origin.

@export_group("Valley")
## Half-size of the valley floor: about the area the air islands cover.
@export var valley_radius: Vector2 = Vector2(1750.0, 1500.0)
## Relative depth of the slow bends of the mountain foot.
@export_range(0.0, 0.2, 0.01) var valley_wobble: float = 0.09
@export_range(64, 512) var boundary_vertices: int = 256
## Open ground around the spawn.
@export var spawn_clearance: float = 170.0

@export_group("Ponds")
@export var pond_count: Vector2i = Vector2i(3, 5)
## Horizontal radius; ponds are a little flatter than wide, like the menu pond.
@export var pond_radius: Vector2 = Vector2(110.0, 240.0)
## Smallest ground between two ponds.
@export var pond_gap: float = 300.0
## Smallest ground between a pond and the mountain foot.
@export var pond_margin: float = 320.0
@export_range(24, 128) var pond_vertices: int = 64

@export_group("Paths")
## Clearings the trails connect, besides the spawn and the ponds.
@export var clearing_count: Vector2i = Vector2i(4, 6)
@export var clearing_radius: Vector2 = Vector2(90.0, 150.0)
@export var path_half_width: Vector2 = Vector2(13.0, 20.0)
## Loops added to the tree of trails.
@export_range(0, 6) var extra_paths: int = 2
## Trails that run off into the mountains.
@export_range(0, 4) var mountain_trails: int = 2

@export_group("Trees")
@export var grove_count: Vector2i = Vector2i(10, 13)
@export var grove_radius: Vector2 = Vector2(170.0, 300.0)
@export var grove_trees: Vector2i = Vector2i(6, 13)
@export var lone_trees: Vector2i = Vector2i(16, 24)
## Pines in small stands along the mountain foot.
@export var foothill_pines: Vector2i = Vector2i(22, 32)
@export var willows_per_pond: Vector2i = Vector2i(1, 2)
## Smallest distance between two trunks.
@export var tree_spacing: float = 92.0
## Free ground kept between any two solid things (more than the player is wide).
@export var passage_width: float = 46.0
## Free ground beside a trail, in addition to its half width.
@export var path_clearance: float = 26.0

@export_group("Rocks")
@export var rocks: Vector2i = Vector2i(24, 34)
## Boulders gathered at the mountain foot.
@export var scree_rocks: Vector2i = Vector2i(40, 56)
## Petrified creatures: huge boulders with a closed eye.
@export var statues: Vector2i = Vector2i(2, 4)
@export var stumps_and_logs: Vector2i = Vector2i(7, 11)

@export_group("Plants")
@export var bushes: Vector2i = Vector2i(44, 60)
@export var tall_grass: Vector2i = Vector2i(110, 150)
@export var ferns: Vector2i = Vector2i(40, 60)
@export var flower_clumps: Vector2i = Vector2i(60, 84)
@export var mushrooms: Vector2i = Vector2i(16, 26)
@export var reeds_per_pond: Vector2i = Vector2i(4, 8)
@export var lilies_per_pond: Vector2i = Vector2i(3, 7)

@export_group("Mountains")
## Rows of peaks around the valley, from the foot outwards.
@export_range(1, 4) var peak_rows: int = 3
## Rocky outcrops on the high plateau beyond the range.
@export var plateau_crags: Vector2i = Vector2i(28, 38)
## Boulders on the plateau, besides those beside the crags.
@export var plateau_boulders: Vector2i = Vector2i(70, 95)


func validation_error() -> String:
	if valley_radius.x < 800.0 or valley_radius.y < 800.0:
		return "The valley is too small."
	if pond_count.x < 0 or pond_count.y < pond_count.x:
		return "Invalid pond count."
	if pond_radius.x <= 40.0 or pond_radius.y < pond_radius.x:
		return "Invalid pond radius."
	if path_half_width.x < 8.0 or path_half_width.y < path_half_width.x:
		return "Invalid path width."
	if passage_width < NelvarPlayer.BODY_RADIUS * 2.0 + 4.0:
		return "Passages are narrower than the player."
	if tree_spacing <= 0.0 or boundary_vertices < 64:
		return "Invalid spacing or boundary resolution."
	return ""
