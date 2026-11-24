class_name NelvarFireConfig
extends Resource
## Generation parameters of the fire forge (developer setting "Запускать игру в Огне").
## Distances are world units; the basin is centred on the origin.

@export_group("Basin")
## Half-size of the basin floor: about the earth valley's.
@export var basin_radius: Vector2 = Vector2(1750.0, 1500.0)
## Relative depth of the slow bends of the ridges' foot.
@export_range(0.0, 0.2, 0.01) var basin_wobble: float = 0.09
@export_range(64, 512) var boundary_vertices: int = 256
## Open ground around the spawn.
@export var spawn_clearance: float = 180.0

@export_group("Lava")
@export var lake_count: Vector2i = Vector2i(2, 4)
## Horizontal radius of a lava lake.
@export var lake_radius: Vector2 = Vector2(150.0, 290.0)
## Smallest ground between two lakes.
@export var lake_gap: float = 340.0
## Smallest ground between a lake and the ridges' foot.
@export var lake_margin: float = 300.0
@export_range(24, 128) var lake_vertices: int = 72
## Islands of plates in a lake big enough for them.
@export var islands_per_lake: Vector2i = Vector2i(0, 2)
@export var island_radius: Vector2 = Vector2(44.0, 72.0)
## Great volcanoes in the nearest row of ridges; a lava stream runs from under each.
@export var volcanoes: Vector2i = Vector2i(1, 2)
## Chance of a stream from one lake into another.
@export_range(0.0, 1.0, 0.05) var lake_stream_chance: float = 0.5
@export var stream_half_width: Vector2 = Vector2(22.0, 32.0)
## Longest stretch of a stream without a crossing (inside the basin).
@export var crossing_spacing: float = 560.0
## Half the length of a crossing, along the stream.
@export var crossing_half_length: float = 50.0

@export_group("Roads")
## Clearings the roads of cooled lava connect, besides the spawn and the lakes.
@export var clearing_count: Vector2i = Vector2i(4, 6)
@export var clearing_radius: Vector2 = Vector2(90.0, 150.0)
@export var flow_half_width: Vector2 = Vector2(14.0, 22.0)
## Loops added to the tree of roads.
@export_range(0, 6) var extra_flows: int = 1
## Roads that run off into the ridges.
@export_range(0, 4) var ridge_flows: int = 2

@export_group("Magma")
@export var fissures: Vector2i = Vector2i(7, 11)
## Share of the fissures that erupt.
@export_range(0.0, 1.0, 0.05) var active_share: float = 0.5
## Patches where magma glows through the joints of the basalt.
@export var magma_fields: Vector2i = Vector2i(2, 4)
## Fumarole fields with smoke banks over them, and vents in each.
@export var vent_fields: Vector2i = Vector2i(2, 3)
@export var vents_per_field: Vector2i = Vector2i(2, 4)

@export_group("Trees")
@export var tree_stands: Vector2i = Vector2i(6, 8)
@export var stand_radius: Vector2 = Vector2(150.0, 260.0)
@export var stand_trees: Vector2i = Vector2i(3, 7)
@export var lone_trees: Vector2i = Vector2i(8, 12)
## Small groups of emberleaves, the trees that live in the heat.
@export var emberleaf_groves: Vector2i = Vector2i(1, 2)
## Smallest distance between two trunks.
@export var tree_spacing: float = 96.0
## Free ground kept between any two solid things (more than the player is wide).
@export var passage_width: float = 46.0
## Free ground beside a road, in addition to its half width.
@export var path_clearance: float = 26.0
## Free ground kept between solid things and the lava.
@export var lava_clearance: float = 44.0

@export_group("Stone")
@export var rocks: Vector2i = Vector2i(16, 24)
## Boulders gathered at the ridges' foot.
@export var scree_rocks: Vector2i = Vector2i(20, 28)
## Boulders on the lava shores.
@export var shore_rocks: Vector2i = Vector2i(6, 10)
@export var crystal_clusters: Vector2i = Vector2i(6, 10)
@export var snags_and_logs: Vector2i = Vector2i(6, 10)

@export_group("Plants")
@export var ember_grass: Vector2i = Vector2i(30, 44)
@export var ash_flowers: Vector2i = Vector2i(16, 24)
@export var shrubs: Vector2i = Vector2i(14, 22)

@export_group("Ridges")
## Rows of ridges around the basin, from the foot outwards.
@export_range(1, 4) var peak_rows: int = 3
@export var plateau_crags: Vector2i = Vector2i(16, 22)
@export var plateau_boulders: Vector2i = Vector2i(30, 44)
## Small volcanoes on the plateau beyond the ridges.
@export var cinder_cones: Vector2i = Vector2i(6, 10)


func validation_error() -> String:
	if basin_radius.x < 800.0 or basin_radius.y < 800.0:
		return "The basin is too small."
	if lake_count.x < 1 or lake_count.y < lake_count.x:
		return "Invalid lake count."
	if lake_radius.x <= 60.0 or lake_radius.y < lake_radius.x:
		return "Invalid lake radius."
	if stream_half_width.x < 12.0 or stream_half_width.y < stream_half_width.x:
		return "Invalid stream width."
	if crossing_half_length < NelvarPlayer.BODY_RADIUS * 2.0:
		return "Crossings are narrower than the player."
	if flow_half_width.x < 8.0 or flow_half_width.y < flow_half_width.x:
		return "Invalid road width."
	if passage_width < NelvarPlayer.BODY_RADIUS * 2.0 + 4.0:
		return "Passages are narrower than the player."
	if tree_spacing <= 0.0 or boundary_vertices < 64:
		return "Invalid spacing or boundary resolution."
	return ""
