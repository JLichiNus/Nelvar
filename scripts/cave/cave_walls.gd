class_name NelvarCaveWalls
extends RefCounted
## The cave's walls as collision: the zero line of NelvarCaveData's distance field by
## marching squares (straight between the samples, where the field crosses zero), cut
## into chunks of CHUNK so the broad phase never tests the whole cave. The bodies are on
## World and on Walls (NelvarCaveData.WALL_SIGHT_LAYER), so a sight line sees them and
## not the things.

const CHUNK := 512.0
const CELL := NelvarCaveData.CELL


## Segments of the zero line (pairs of points), keyed by chunk.
static func segments(cave: NelvarCaveData) -> Dictionary:
	var chunks := {}
	var w := cave.sdf_size.x
	var h := cave.sdf_size.y
	var sdf := cave.sdf
	for y in h - 1:
		for x in w - 1:
			var i := y * w + x
			var s00 := sdf[i]
			var s10 := sdf[i + 1]
			var s01 := sdf[i + w]
			var s11 := sdf[i + w + 1]
			var inside00 := s00 > 0.0
			if inside00 == (s10 > 0.0) and inside00 == (s01 > 0.0) and inside00 == (s11 > 0.0):
				continue
			var corner := cave.sdf_origin + Vector2(x, y) * CELL
			# Crossings on the edges: top, right, bottom, left (-INF where none).
			var top := _cross(s00, s10, corner, corner + Vector2(CELL, 0.0))
			var right := _cross(s10, s11, corner + Vector2(CELL, 0.0), corner + Vector2(CELL, CELL))
			var bottom := _cross(s01, s11, corner + Vector2(0.0, CELL), corner + Vector2(CELL, CELL))
			var left := _cross(s00, s01, corner, corner + Vector2(0.0, CELL))
			var found: Array[Vector2] = []
			for point in [top, right, bottom, left]:
				if point.is_finite():
					found.append(point)
			var key := Vector2i((corner / CHUNK).floor())
			if not chunks.has(key):
				chunks[key] = PackedVector2Array()
			var list: PackedVector2Array = chunks[key]
			if found.size() == 2:
				list.append(found[0])
				list.append(found[1])
			elif found.size() == 4:
				# A saddle: the middle decides which corners stand apart.
				var middle := (s00 + s10 + s01 + s11) * 0.25
				if (middle > 0.0) == inside00:
					list.append_array([top, right, bottom, left])
				else:
					list.append_array([top, left, right, bottom])
			chunks[key] = list
	return chunks


static func _cross(a: float, b: float, from: Vector2, to: Vector2) -> Vector2:
	if (a > 0.0) == (b > 0.0):
		return Vector2.INF
	return from.lerp(to, a / (a - b))


## One static body per chunk of `chunks` (segments()) under `parent`.
static func build(chunks: Dictionary, parent: Node) -> Array[StaticBody2D]:
	var bodies: Array[StaticBody2D] = []
	for key: Vector2i in chunks:
		var list: PackedVector2Array = chunks[key]
		if list.is_empty():
			continue
		var body := StaticBody2D.new()
		body.name = "Walls_%d_%d" % [key.x, key.y]
		body.collision_layer = NelvarProp.WORLD_LAYER | NelvarCaveData.WALL_SIGHT_LAYER
		body.collision_mask = 0
		var shape := ConcavePolygonShape2D.new()
		shape.segments = list
		var collider := CollisionShape2D.new()
		collider.shape = shape
		body.add_child(collider)
		parent.add_child(body)
		bodies.append(body)
	return bodies
