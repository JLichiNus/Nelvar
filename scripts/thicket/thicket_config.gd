class_name NelvarThicketConfig
extends Resource
## Generation parameters of the giant forest, Земля 2 (developer setting "Запускать игру
## на Земле"). Distances are world units; the forest floor is centred on the origin.
## The player is a beetle here: a trunk is wider than the screen, a grass blade taller
## than the player, an acorn a boulder.

@export_group("Floor")
## Half-size of the forest floor inside the ring of giants.
@export var floor_radius: Vector2 = Vector2(2300.0, 1900.0)
@export_range(0.0, 0.2, 0.01) var floor_wobble: float = 0.07
@export_range(64, 512) var boundary_vertices: int = 256

@export_group("Giants")
## Giants standing inside, besides the one north of the start.
@export var giants: Vector2i = Vector2i(4, 6)
@export var giant_radius: Vector2 = Vector2(220.0, 420.0)
## Smallest ground between the bark of two giants.
@export var giant_gap: float = 700.0
## Giants standing shoulder to shoulder round the floor (none on the south side).
@export var ring_giants: Vector2i = Vector2i(10, 14)
## Seen height of a trunk, in its diameters, and its cap.
@export var trunk_height: Vector2 = Vector2(1.3, 1.8)
@export var trunk_height_cap: float = 1100.0
## The nearest giant north of the start: its centre this far north of the start.
@export var start_giant_distance: Vector2 = Vector2(520.0, 620.0)

@export_group("Roots")
@export var roots_per_giant: Vector2i = Vector2i(0, 0)
@export var root_length: Vector2 = Vector2(300.0, 900.0)
## Width of a root where it leaves the trunk, and at its tip.
@export var root_width: Vector2 = Vector2(30.0, 140.0)
## Share of a root's length that stands higher than the player (a wall).
@export var high_share: Vector2 = Vector2(0.4, 0.6)
## Chance of a root to branch once, and to lift into an arch.
@export_range(0.0, 1.0, 0.05) var branch_chance: float = 0.4
@export_range(0.0, 1.0, 0.05) var arch_chance: float = 0.55

@export_group("Clearings and trails")
## Clearings besides the one with the start.
@export var clearings: Vector2i = Vector2i(5, 7)
@export var clearing_radius: Vector2 = Vector2(220.0, 420.0)
@export var start_clearing_radius: Vector2 = Vector2(210.0, 250.0)
@export var trail_half_width: Vector2 = Vector2(20.0, 34.0)
## Loops added to the tree of ant trails.
@export var extra_trails: Vector2i = Vector2i(2, 3)
## Free ground kept between any two solid things (more than a hopper is wide).
@export var passage_width: float = 46.0
## Free ground beside a trail, in addition to its half width.
@export var trail_clearance: float = 26.0

@export_group("Ponds")
@export var ponds: Vector2i = Vector2i(1, 2)
@export var pond_radius: Vector2 = Vector2(260.0, 460.0)
@export var lilies_per_pond: Vector2i = Vector2i(4, 7)
@export var lily_radius: Vector2 = Vector2(70.0, 140.0)
@export var rafts_per_pond: Vector2i = Vector2i(3, 6)
@export var raft_length: Vector2 = Vector2(110.0, 240.0)
## Seconds for a raft to go once round its pond.
@export var raft_period: Vector2 = Vector2(60.0, 120.0)

@export_group("Fallen giant")
@export var fallen_length: Vector2 = Vector2(1600.0, 2200.0)
@export var fallen_thickness: Vector2 = Vector2(260.0, 380.0)
@export var tunnel_width: Vector2 = Vector2(120.0, 200.0)
@export var root_plate_width: Vector2 = Vector2(500.0, 700.0)
@export var breaches: Vector2i = Vector2i(1, 3)

@export_group("Hazards")
@export var flytrap_groups: Vector2i = Vector2i(0, 0)
@export var flytraps_per_group: Vector2i = Vector2i(2, 6)
@export var flytrap_radius: Vector2 = Vector2(55.0, 85.0)
@export var puffball_groups: Vector2i = Vector2i(5, 8)
@export var puffballs_per_group: Vector2i = Vector2i(2, 5)
@export var puffball_radius: Vector2 = Vector2(24.0, 60.0)
@export var loose_patches: Vector2i = Vector2i(0, 0)
@export var loose_radius: Vector2 = Vector2(80.0, 200.0)
@export var resin_lobes: Vector2i = Vector2i(0, 0)
@export var resin_radius: Vector2 = Vector2(60.0, 160.0)
@export var ambers: Vector2i = Vector2i(3, 6)
## Hazards keep this far from the start.
@export var start_clearance: float = 300.0

@export_group("Things")
@export var acorns: Vector2i = Vector2i(20, 35)
@export var mushroom_groups: Vector2i = Vector2i(6, 12)
@export var grass_clumps: Vector2i = Vector2i(60, 90)
@export var clovers: Vector2i = Vector2i(15, 25)
@export var flowers: Vector2i = Vector2i(6, 10)
@export var leaves: Vector2i = Vector2i(40, 60)
@export var twigs: Vector2i = Vector2i(3, 6)
@export var shells: Vector2i = Vector2i(2, 4)
@export var feathers: Vector2i = Vector2i(1, 3)
@export var dew_drops: Vector2i = Vector2i(30, 50)
@export var statues: Vector2i = Vector2i(2, 3)
@export var bones: Vector2i = Vector2i(6, 10)
@export var rocks: Vector2i = Vector2i(2, 5)
@export var reeds_per_pond: Vector2i = Vector2i(5, 8)


func validation_error() -> String:
	if floor_radius.x < 1400.0 or floor_radius.y < 1200.0:
		return "The forest floor is too small."
	if giant_radius.x < 120.0 or giant_radius.y < giant_radius.x:
		return "Invalid giant radius."
	if root_length.x < 100.0 or root_length.y < root_length.x:
		return "Invalid root length."
	if trail_half_width.x < 12.0 or trail_half_width.y < trail_half_width.x:
		return "Invalid trail width."
	if passage_width < NelvarPlayer.BODY_RADIUS * 2.0 + 4.0:
		return "Passages are narrower than the player."
	if pond_radius.x < 160.0 or pond_radius.y < pond_radius.x:
		return "Invalid pond radius."
	if boundary_vertices < 64:
		return "Invalid boundary resolution."
	return ""
