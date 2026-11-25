class_name NelvarCraterConfig
extends Resource
## Generation parameters of the volcano (developer setting "Запускать игру в Огне 2").
## Distances are world units; the crater is centred on the origin.

@export_group("Lake")
## Half-size of the lava lake that fills the crater almost to its brim.
@export var lake_radius: Vector2 = Vector2(1960.0, 1840.0)
## Relative depth of the slow bends of its shore.
@export_range(0.0, 0.1, 0.005) var lake_wobble: float = 0.035
@export_range(64, 512) var shore_vertices: int = 256

@export_group("Rim")
## Width of the ring of rock between the lake and the summit's edge: room to run and
## fight all the way round, still a ring round a far larger lake.
@export var rim_width: Vector2 = Vector2(400.0, 500.0)
## Nowhere narrower than this.
@export var rim_min: float = 340.0
## Broad places where the edge bulges outwards: room to fight. The spawn is on the
## southern one.
@export var terraces: Vector2i = Vector2i(2, 4)
## How far a terrace pushes the edge out, and its angular half-width (radians).
@export var terrace_bulge: Vector2 = Vector2(200.0, 280.0)
@export var terrace_spread: Vector2 = Vector2(0.16, 0.24)
## Open ground round the spawn.
@export var spawn_clearance: float = 150.0

@export_group("Capes and the vent")
## Tongues of rock reaching into the lake.
@export var capes: Vector2i = Vector2i(3, 5)
@export var cape_half_width: Vector2 = Vector2(70.0, 100.0)
## How far a cape reaches from the shore.
@export var cape_length: Vector2 = Vector2(150.0, 320.0)
## The vent in the middle of the lake.
@export var vent_radius: Vector2 = Vector2(64.0, 84.0)
## Patches where the lava boils brighter.
@export var boils: Vector2i = Vector2i(3, 5)

@export_group("Magma crust")
## Floes of crust grown out from the shore across the lake, each a step from the one it
## grew from: one can walk to the middle on them. They hold whoever walks on them (no
## harm) and carry them along. They grow until there is no room left; this is only a
## bound.
@export var floe_limit: int = 400
## Radius before the bends; more small ones than broad.
@export var floe_radius: Vector2 = Vector2(44.0, 230.0)
## Lava between a floe and the one it grew from (or the shore): a step.
@export var floe_gap: Vector2 = Vector2(16.0, 26.0)
## The swell they all sway on: reach on each axis (small: a floe at the shore stays
## within a run of it) and seconds of one sway.
@export var floe_drift: Vector2 = Vector2(6.0, 10.0)
@export var floe_period: Vector2 = Vector2(50.0, 100.0)
## Length of the swell's wave: far longer than a floe, so neighbours sway together.
@export var floe_swell: float = 7000.0
## Open lava kept round the vent.
@export var vent_moat: float = 140.0
## Share of the floes that sink by themselves now and then (more of the small ones): seconds
## between, and how long they stay under. They warn first: their seams flare.
@export_range(0.0, 0.8, 0.05) var sinking_share: float = 0.3
@export var sink_period: Vector2 = Vector2(30.0, 55.0)
@export var sink_time: Vector2 = Vector2(5.0, 8.0)

@export_group("Geysers")
@export var geysers: Vector2i = Vector2i(7, 10)
## Of them at the capes, as springboards out over the floes.
@export var cape_geysers: int = 2
@export var geyser_radius: Vector2 = Vector2(16.0, 22.0)
@export var geyser_period: Vector2 = Vector2(10.0, 16.0)
@export var geyser_spacing: float = 250.0

@export_group("Things")
## Roads of cooled lava: the ring along the rim and spurs to the capes and terraces.
@export var flow_half_width: Vector2 = Vector2(14.0, 20.0)
## Fumarole fields with smoke banks over them, and vents in each.
@export var vent_fields: Vector2i = Vector2i(2, 3)
@export var vents_per_field: Vector2i = Vector2i(2, 3)
@export var rocks: Vector2i = Vector2i(30, 42)
@export var crystal_clusters: Vector2i = Vector2i(9, 13)
@export var snags: Vector2i = Vector2i(6, 10)
## A burnt tree or two: almost nothing grows up here.
@export var trees: Vector2i = Vector2i(0, 2)
@export var ember_grass: Vector2i = Vector2i(32, 46)
@export var ash_flowers: Vector2i = Vector2i(16, 24)
@export var shrubs: Vector2i = Vector2i(10, 15)
## Free ground kept between any two solid things, and between them and any edge.
@export var passage_width: float = 46.0
## Free ground beside a road, in addition to its half width.
@export var path_clearance: float = 20.0


func validation_error() -> String:
	if lake_radius.x < 1200.0 or lake_radius.y < 1200.0:
		return "The lake is too small."
	if rim_width.x < rim_min or rim_width.y < rim_width.x or rim_min < 160.0:
		return "Invalid rim width."
	if floe_radius.x < NelvarPlayer.BODY_RADIUS * 3.0 or floe_period.x < 20.0 or floe_swell < 3000.0:
		return "Invalid floes."
	if floe_gap.x < 12.0 or floe_gap.y > 30.0 or floe_gap.y < floe_gap.x:
		return "Floes must stay a step apart."
	if capes.x < 1 or capes.y < capes.x:
		return "Invalid cape count."
	if cape_length.x < 60.0 or cape_length.y < cape_length.x:
		return "Invalid cape length."
	if sink_period.x < sink_time.y + 10.0:
		return "Sinking floes must stay up longer than under."
	if passage_width < NelvarPlayer.BODY_RADIUS * 2.0 + 4.0:
		return "Passages are narrower than the player."
	return ""
