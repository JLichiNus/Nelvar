class_name NelvarPropConfig
extends Resource
## Rocks (solid) and bushes (walk-through) scattered over the islands after the forest.
## Hubs, bridge routes, the spawn area and passage widths come from NelvarForestConfig,
## so trees, rocks and bushes keep the same routes open.

@export_group("Rocks")
@export var large_island_rocks: Vector2i = Vector2i(4, 6)
@export var small_island_rocks: Vector2i = Vector2i(1, 3)
## Footprint half-width of an ordinary rock, world units.
@export var rock_radius: Vector2 = Vector2(16.0, 26.0)
## Chance that a rock is a big boulder instead.
@export_range(0.0, 1.0, 0.01) var boulder_chance: float = 0.25
@export var boulder_radius: Vector2 = Vector2(32.0, 44.0)
## Chance of a small stone lying right against a rock.
@export_range(0.0, 1.0, 0.01) var companion_chance: float = 0.4
## Chance of a moss cap on a rock.
@export_range(0.0, 1.0, 0.01) var moss_chance: float = 0.45

@export_group("Bushes")
@export var large_island_bushes: Vector2i = Vector2i(3, 6)
@export var small_island_bushes: Vector2i = Vector2i(1, 3)
## Half-width of a bush, world units.
@export var bush_radius: Vector2 = Vector2(26.0, 38.0)
## Share of bushes growing at the foot of a tree rather than in the open.
@export_range(0.0, 1.0, 0.01) var grove_bush_share: float = 0.6
## Chance of pale blossoms on a bush.
@export_range(0.0, 1.0, 0.01) var blossom_chance: float = 0.35
