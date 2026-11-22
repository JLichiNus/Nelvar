class_name NelvarForestConfig
extends Resource

@export_group("Groups")
@export var large_island_groups: Vector2i = Vector2i(2, 3)
@export var small_island_groups: Vector2i = Vector2i(1, 1)
@export var large_group_trees: Vector2i = Vector2i(6, 10)
@export var small_group_trees: Vector2i = Vector2i(3, 6)
@export var group_radius: Vector2 = Vector2(155.0, 235.0)

@export_group("Clearances")
@export var tree_spacing: float = 96.0
@export var passage_width: float = 48.0
@export var shore_margin: float = 32.0
@export var path_half_width: float = 40.0
@export var hub_radius: float = 68.0
@export var spawn_radius: float = 130.0

@export_group("Trees")
@export var trunk_radius: Vector2 = Vector2(17.0, 23.0)
@export var canopy_radius: Vector2 = Vector2(64.0, 94.0)
@export var trunk_height: Vector2 = Vector2(52.0, 78.0)
