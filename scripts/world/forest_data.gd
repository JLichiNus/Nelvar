class_name NelvarForestData
extends RefCounted
## Forest placement is separate from terrain geometry and visual pixel size.

class Cluster:
	var id: int
	var island_id: int
	var center: Vector2
	var radius: float
	var stretch: float
	var rotation: float
	var palette: int
	var form: int
	var tree_ids: Array[int] = []


class TreeSpec:
	var id: int
	var island_id: int
	var cluster_id: int
	var position: Vector2
	var trunk_radius: float
	var canopy_radius: float
	var trunk_height: float
	var lean: float
	var palette: int
	var form: int
	var appearance_seed: int

	func canopy_axes() -> Vector2:
		if form == 1:
			return Vector2(0.78, 1.08) * canopy_radius
		if form == 2:
			return Vector2(1.16, 0.70) * canopy_radius
		return Vector2(1.0, 0.82) * canopy_radius


	func canopy_center() -> Vector2:
		return Vector2(lean, -trunk_height - canopy_axes().y)


var clusters: Array[Cluster] = []
var trees: Array[TreeSpec] = []


func has_clearance(point: Vector2, radius: float) -> bool:
	for tree in trees:
		if point.distance_squared_to(tree.position) < pow(radius + tree.trunk_radius, 2.0):
			return false
	return true
