class_name NelvarWorldData
extends RefCounted
## Authoritative geometry shared by generation, rendering and physics.

## Shores and bridge sides sit on their own physics layer: they stop enemies but
## not the player, who can walk off them and fall into the clouds (main.gd).
const EDGE_LAYER := 128
const EDGE_LAYER_NUMBER := 8

class Island:
	var id: int
	var large: bool
	var center: Vector2
	var radius: float
	var polygon: PackedVector2Array
	var bounds: Rect2


class Bridge:
	var island_a: int
	var island_b: int
	var start: Vector2
	var finish: Vector2
	var width: float
	var polygon: PackedVector2Array
	var bounds: Rect2


class Border:
	var start: Vector2
	var finish: Vector2
	var shore: bool


class Chunk:
	var rect: Rect2
	var depth: int
	var children: Array[Chunk] = []
	var island_ids: Array[int] = []
	var bridge_ids: Array[int] = []
	var ground_polygons: Array[PackedVector2Array] = []
	var ground_ids: Array[int] = []
	var bridge_polygons: Array[PackedVector2Array] = []
	var borders: Array[Border] = []

	func find_leaf(point: Vector2) -> Chunk:
		if not rect.has_point(point):
			return null
		if children.is_empty():
			return self
		for child in children:
			if child.rect.has_point(point):
				return child.find_leaf(point)
		return null


var world_seed: int
var islands: Array[Island] = []
var bridges: Array[Bridge] = []
var borders: Array[Border] = []
var root: Chunk
var leaves: Array[Chunk] = []
var bounds: Rect2
var spawn_position: Vector2


func is_walkable(point: Vector2) -> bool:
	if root == null:
		return false
	var chunk := root.find_leaf(point)
	if chunk == null:
		return false
	for id in chunk.island_ids:
		if Geometry2D.is_point_in_polygon(point, islands[id].polygon):
			return true
	for id in chunk.bridge_ids:
		if Geometry2D.is_point_in_polygon(point, bridges[id].polygon):
			return true
	return false


## Like has_clearance, but checks only the borders of the leaves around the point:
## cheap enough for every physics frame. `radius` must stay below the smallest chunk
## size, so the leaves holding the corners of the surrounding square hold every border
## that can come that close.
func is_firm(point: Vector2, radius: float) -> bool:
	if not is_walkable(point):
		return false
	var seen: Array[Chunk] = []
	for corner: Vector2 in [Vector2(-1, -1), Vector2(1, -1), Vector2(-1, 1), Vector2(1, 1)]:
		var leaf := root.find_leaf(point + corner * radius)
		if leaf == null or seen.has(leaf):
			continue
		seen.append(leaf)
		for border in leaf.borders:
			var closest := Geometry2D.get_closest_point_to_segment(point, border.start, border.finish)
			if point.distance_squared_to(closest) < radius * radius:
				return false
	return true


func has_clearance(point: Vector2, radius: float) -> bool:
	if not is_walkable(point):
		return false
	for border in borders:
		var closest := Geometry2D.get_closest_point_to_segment(
			point, border.start, border.finish
		)
		if point.distance_squared_to(closest) < radius * radius:
			return false
	return true
