class_name NelvarCraterConfig
extends Resource
## Generation parameters of the volcano (developer setting "Запускать игру в Огне 2").
## Distances are world units; the crater is centred on the origin.

@export_group("Lake")
## Half-size of the lava lake that fills the crater almost to its brim.
@export var lake_radius: Vector2 = Vector2(1640.0, 1540.0)
## Relative depth of the slow bends of its shore.
@export_range(0.0, 0.1, 0.005) var lake_wobble: float = 0.035
@export_range(64, 512) var shore_vertices: int = 256

@export_group("Rim")
## Width of the ring of rock between the lake and the summit's edge. Kept narrow: a thin
## ring round a huge lake reads as a crater, a broad one as a plain with a pond.
@export var rim_width: Vector2 = Vector2(210.0, 280.0)
## Nowhere narrower than this.
@export var rim_min: float = 170.0
## Broad places where the edge bulges outwards: room to fight. The spawn is on the
## southern one.
@export var terraces: Vector2i = Vector2i(2, 4)
## How far a terrace pushes the edge out, and its angular half-width (radians).
@export var terrace_bulge: Vector2 = Vector2(150.0, 210.0)
@export var terrace_spread: Vector2 = Vector2(0.16, 0.24)
## Open ground round the spawn.
@export var spawn_clearance: float = 150.0

@export_group("Capes and the vent")
## Tongues of rock reaching into the lake: the islands come alongside their tips.
@export var capes: Vector2i = Vector2i(3, 5)
@export var cape_half_width: Vector2 = Vector2(56.0, 84.0)
## Shortest cape (the islands' rings are set inside the lake so that this fits), and
## the longest wanted (where the shore allows).
@export var cape_min_length: float = 150.0
@export var cape_max_length: float = 280.0
## The vent in the middle of the lake, and how far from its centre islands keep.
@export var vent_radius: Vector2 = Vector2(64.0, 84.0)
@export var vent_clearance: float = 250.0
## Patches where the lava boils brighter.
@export var boils: Vector2i = Vector2i(3, 5)

@export_group("Islands")
## Islands that stand round the vent and never sink.
@export var anchors: Vector2i = Vector2i(2, 3)
@export var anchor_radius: Vector2 = Vector2(150.0, 200.0)
## Plates: inner ring (big ones) and outer ring (smaller ones); rafts between them.
@export var inner_plates: Vector2i = Vector2i(3, 4)
@export var inner_plate_radius: Vector2 = Vector2(104.0, 128.0)
@export var outer_plates: Vector2i = Vector2i(3, 5)
@export var outer_plate_radius: Vector2 = Vector2(72.0, 92.0)
@export var rafts: Vector2i = Vector2i(6, 10)
@export var raft_radius: Vector2 = Vector2(44.0, 56.0)
## Islands of a ring differ in size by no more than this (each spans its ring: it comes
## close to the rings on both sides).
@export var ring_slack: float = 8.0
## Gap between neighbouring rings (and between the outer ring and the capes' tips).
@export var ring_gap: float = 18.0
## Seconds per turn of a ring.
@export var ring_period: Vector2 = Vector2(90.0, 160.0)
## Lava kept between neighbours in one ring (they never meet).
@export var ring_spacing: Vector2 = Vector2(50.0, 240.0)
## Plates sink by themselves now and then: seconds between, and how long they stay under.
@export var sink_period: Vector2 = Vector2(45.0, 80.0)
@export var sink_time: Vector2 = Vector2(7.0, 10.0)

@export_group("Geysers")
@export var geysers: Vector2i = Vector2i(6, 9)
## Of them at the capes, as springboards onto the islands.
@export var cape_geysers: int = 2
@export var geyser_radius: Vector2 = Vector2(16.0, 22.0)
@export var geyser_period: Vector2 = Vector2(10.0, 16.0)
@export var geyser_spacing: float = 250.0

@export_group("Things")
## Roads of cooled lava: the ring along the rim and spurs to the capes and terraces.
@export var flow_half_width: Vector2 = Vector2(14.0, 20.0)
## Fumarole fields with smoke banks over them, and vents in each.
@export var vent_fields: Vector2i = Vector2i(1, 2)
@export var vents_per_field: Vector2i = Vector2i(2, 3)
@export var rocks: Vector2i = Vector2i(18, 26)
## Boulders on the anchors.
@export var anchor_rocks: Vector2i = Vector2i(1, 3)
@export var crystal_clusters: Vector2i = Vector2i(6, 9)
@export var snags: Vector2i = Vector2i(4, 7)
## A burnt tree or two: almost nothing grows up here.
@export var trees: Vector2i = Vector2i(0, 2)
@export var ember_grass: Vector2i = Vector2i(22, 32)
@export var ash_flowers: Vector2i = Vector2i(10, 16)
@export var shrubs: Vector2i = Vector2i(6, 10)
## Free ground kept between any two solid things, and between them and any edge.
@export var passage_width: float = 46.0
## Free ground beside a road, in addition to its half width.
@export var path_clearance: float = 20.0


func validation_error() -> String:
	if lake_radius.x < 1200.0 or lake_radius.y < 1200.0:
		return "The lake is too small."
	if rim_width.x < rim_min or rim_width.y < rim_width.x or rim_min < 160.0:
		return "Invalid rim width."
	if capes.x < 1 or capes.y < capes.x:
		return "Invalid cape count."
	if anchors.x < 1 or anchors.y < anchors.x:
		return "Invalid anchor count."
	if ring_gap < 10.0 or ring_gap > 30.0:
		return "The ring gap must stay between touching and a short run."
	if ring_slack < 0.0 or ring_slack > 14.0:
		return "Invalid ring slack."
	if raft_radius.x < NelvarPlayer.BODY_RADIUS * 2.0:
		return "Rafts are smaller than the player."
	if passage_width < NelvarPlayer.BODY_RADIUS * 2.0 + 4.0:
		return "Passages are narrower than the player."
	return ""
