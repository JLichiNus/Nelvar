class_name NelvarCaveConfig
extends Resource
## Generation parameters of the ice cave, Лёд 2 (developer setting "Запускать игру на
## Льду"). Distances are world units; the cave is centred on the origin.

@export_group("Cave")
## The whole cave: solid ice all round it.
@export var size: Vector2 = Vector2(5200.0, 4200.0)
## Solid ice kept along the edge of the map.
@export var margin: float = 200.0
## Smallest ice between the edges of two halls.
@export var hall_gap: float = 220.0

@export_group("Halls")
## The cold halls: the biggest, the main arenas.
@export var cold_halls: Vector2i = Vector2i(2, 3)
@export var cold_radius: Vector2 = Vector2(450.0, 650.0)
## Halls under a hole in the roof: sun, snow, pines.
@export var sunny_halls: Vector2i = Vector2i(3, 5)
@export var sunny_radius: Vector2 = Vector2(260.0, 380.0)
@export var plain_halls: Vector2i = Vector2i(5, 8)
@export var plain_radius: Vector2 = Vector2(200.0, 320.0)
## Grottos at the ends of dead ends.
@export var grottos: Vector2i = Vector2i(4, 7)
@export var grotto_radius: Vector2 = Vector2(90.0, 150.0)
## Relative depth of the slow bends of a hall's outline.
@export_range(0.0, 0.25, 0.01) var hall_wobble: float = 0.12
## Ice pillars in the big halls (cover from hoppers).
@export var columns: Vector2i = Vector2i(2, 6)
@export var column_radius: Vector2 = Vector2(50.0, 110.0)

@export_group("Passages")
## Share of the triangulation's other edges added to the spanning tree (loops).
@export var extra_passages: Vector2 = Vector2(0.35, 0.5)
@export var passage_half_width: Vector2 = Vector2(50.0, 95.0)
## Now and then a passage narrows to a slit a hopper still gets through.
@export var slit_half_width: float = 36.0
@export_range(0.0, 1.0, 0.05) var slit_chance: float = 0.3
## Niches and pockets beside a passage (things stand in them).
@export var niches: Vector2i = Vector2i(0, 3)
## Passages of smooth slippery ice.
@export var icy_passages: Vector2i = Vector2i(2, 4)

@export_group("Sun and snow")
@export var skylight_radius: Vector2 = Vector2(160.0, 320.0)
## Snow lies this much further round a sunny spot...
@export var snow_reach: Vector2 = Vector2(60.0, 120.0)
## ...and runs this far into the passages out of a sunny hall.
@export var snow_tongue: Vector2 = Vector2(80.0, 200.0)
@export var pines_per_hall: Vector2i = Vector2i(2, 5)

@export_group("Lakes")
@export var frozen_lakes: Vector2i = Vector2i(2, 4)
@export var frozen_radius: Vector2 = Vector2(160.0, 380.0)
@export var melt_lakes: Vector2i = Vector2i(1, 2)
## Too wide to walk across (300 a second, the ice gives in 1), not to run (450).
@export var melt_radius: Vector2 = Vector2(180.0, 205.0)
@export var open_lakes: Vector2i = Vector2i(1, 3)
@export var open_radius: Vector2 = Vector2(90.0, 220.0)
## The band of melting ice round open water.
@export var open_rim: Vector2 = Vector2(16.0, 30.0)
@export var thin_patches: Vector2i = Vector2i(1, 3)
@export var thin_radius: Vector2 = Vector2(48.0, 100.0)
@export var frozen_per_lake: Vector2i = Vector2i(1, 3)
@export_range(0.0, 1.0, 0.05) var watching_share: float = 0.5

@export_group("Geysers")
@export var geysers_per_hall: Vector2i = Vector2i(1, 3)
@export var geyser_warmth: Vector2 = Vector2(170.0, 240.0)
@export var geyser_spacing: float = 260.0
## One cycle (calm, bubbling, eruption), seconds.
@export var geyser_period: Vector2 = Vector2(14.0, 22.0)

@export_group("Chasms")
@export var chasms: Vector2i = Vector2i(2, 3)
@export var arch_half_width: Vector2 = Vector2(25.0, 40.0)
@export var crevasses: Vector2i = Vector2i(2, 4)
@export var crevasse_half_width: Vector2 = Vector2(14.0, 36.0)
@export var bridge_half_length: float = 46.0

@export_group("Creatures")
## Creatures frozen into the walls, seen through the translucent ice.
@export var wall_creatures: Vector2i = Vector2i(14, 24)
@export_range(0.0, 1.0, 0.05) var wall_watching_share: float = 0.3
## Giants running through the ice between two passages.
@export var giants: Vector2i = Vector2i(1, 2)
## Creatures caught in ice flows at the foot of the walls.
@export var embedded: Vector2i = Vector2i(6, 10)
## Bodies floating on each open water.
@export var floaters: Vector2i = Vector2i(1, 3)

@export_group("Things")
## Free ground kept between any two solid things (more than the player is wide).
@export var passage_width: float = 46.0
@export var small_crystals: Vector2i = Vector2i(60, 90)
@export var medium_crystals: Vector2i = Vector2i(25, 40)
@export var large_crystals: Vector2i = Vector2i(8, 14)
@export_range(0.0, 1.0, 0.05) var glowing_share: float = 0.3
@export var boulders: Vector2i = Vector2i(15, 25)
@export var stones: Vector2i = Vector2i(30, 45)
@export var ice_stones: Vector2i = Vector2i(10, 16)
@export var stalagmites: Vector2i = Vector2i(10, 20)
@export var bones: Vector2i = Vector2i(6, 10)
@export var statues: Vector2i = Vector2i(1, 2)


func validation_error() -> String:
	if size.x < 2400.0 or size.y < 2000.0:
		return "The cave is too small."
	if cold_halls.x < 1 or cold_halls.y < cold_halls.x or sunny_halls.x < 1 or sunny_halls.y < sunny_halls.x:
		return "Invalid hall count."
	if plain_halls.y < plain_halls.x or grottos.y < grottos.x:
		return "Invalid hall count."
	if cold_radius.x < 200.0 or sunny_radius.x < 150.0 or plain_radius.x < 120.0 or grotto_radius.x < 60.0:
		return "Halls are too small."
	if passage_half_width.x < 40.0 or passage_half_width.y < passage_half_width.x:
		return "Invalid passage width."
	if slit_half_width < 26.0:
		return "Slits are narrower than a hopper."
	if passage_width < NelvarPlayer.BODY_RADIUS * 2.0 + 4.0:
		return "Passages are narrower than the player."
	if arch_half_width.x < NelvarPlayer.BODY_RADIUS + 8.0 or arch_half_width.y < arch_half_width.x:
		return "Arches are narrower than the player."
	if bridge_half_length < NelvarPlayer.BODY_RADIUS * 2.0:
		return "Snow bridges are narrower than the player."
	return ""
