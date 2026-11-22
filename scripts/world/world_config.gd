class_name NelvarWorldConfig
extends Resource
## Distances are world pixels. Island radii include room for open combat areas.

@export_group("Islands")
@export_range(1, 8) var large_count_min: int = 2
@export_range(1, 8) var large_count_max: int = 3
@export_range(0, 24) var small_count_min: int = 6
@export_range(0, 24) var small_count_max: int = 7
@export var large_radius: Vector2 = Vector2(490.0, 650.0)
@export var small_radius: Vector2 = Vector2(190.0, 290.0)
@export var island_gap: Vector2 = Vector2(180.0, 370.0)

@export_group("Bridges")
@export var character_width: float = 28.0
@export_range(2.0, 3.0) var bridge_width_in_characters: float = 2.5
@export_range(0, 8) var extra_connections: int = 2

@export_group("Chunks")
@export var world_size: float = 8192.0
@export_range(1, 7) var chunk_depth: int = 5
@export_range(24, 128) var shore_vertices: int = 64


func bridge_width() -> float:
	return character_width * bridge_width_in_characters


func smallest_chunk_size() -> float:
	return world_size / pow(2.0, chunk_depth)


func validation_error() -> String:
	if large_count_min < 1 or large_count_max < large_count_min:
		return "Invalid large island count."
	if small_count_min < 0 or small_count_max < small_count_min:
		return "Invalid small island count."
	if large_radius.x <= 0.0 or large_radius.y < large_radius.x:
		return "Invalid large island radius."
	if small_radius.x <= 0.0 or small_radius.y < small_radius.x:
		return "Invalid small island radius."
	if island_gap.x <= 0.0 or island_gap.y < island_gap.x:
		return "Invalid gap between islands."
	if world_size <= 0.0 or chunk_depth < 1 or chunk_depth > 7:
		return "Invalid chunk dimensions."
	if bridge_width() <= 24.0 or shore_vertices < 24:
		return "Bridge width or shore resolution is too small."
	return ""
