class_name NelvarPropData
extends RefCounted
## Rocks and bushes: small Y-sorted props placed after the forest. Only rocks collide.

enum Kind { ROCK, BUSH }

## A rock's footprint on the ground is an ellipse this much flatter than it is wide.
const FOOTPRINT := 0.55

class PropSpec:
	var id: int
	var kind: Kind
	var island_id: int
	## Ground centre of the footprint: the Y-sort origin and the collider centre.
	var position: Vector2
	## Half-width of the footprint, world units.
	var radius: float
	## A small stone resting against this rock (id), or -1.
	var anchor_id := -1
	## Rocks: a moss cap. Bushes: blossoms.
	var accent: bool
	## Bushes: foliage ramp shared with trees (NelvarTreePainter.foliage).
	var palette: int
	var appearance_seed: int

	func is_solid() -> bool:
		return kind == Kind.ROCK

	func footprint() -> Vector2:
		return Vector2(radius, radius * FOOTPRINT)


var props: Array[PropSpec] = []


func count(kind: Kind) -> int:
	var total := 0
	for prop in props:
		if prop.kind == kind:
			total += 1
	return total


## True when a circle of `radius` at `point` keeps off every rock. The footprint is
## treated as a circle of its half-width, so the answer errs on the safe side.
func has_clearance(point: Vector2, radius: float) -> bool:
	for prop in props:
		if prop.is_solid() and point.distance_squared_to(prop.position) < pow(radius + prop.radius, 2.0):
			return false
	return true
