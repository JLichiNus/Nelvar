class_name NelvarCaveFloaters
extends Node2D
## The bodies floating on the cave's open water, under everyone who walks (it lies in
## the World layer): each drifts slowly round its loop, turning to face the way it goes,
## and bobs a pixel up and down; the floor draws the rings spreading round them
## (ripples()). Where a body is depends on the time only.

const STEP := NelvarIceData.PIXEL

var floaters: Array[NelvarCaveData.Floater] = []
var _arts: Array[NelvarIceArt] = []
var _time := 0.0


## `arts[i]` is the painted art of `cave.floaters[i]`.
func setup(cave: NelvarCaveData, arts: Array) -> void:
	floaters = cave.floaters
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for art: NelvarIceArt in arts:
		art.bake()
		_arts.append(art)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


## Where floater `i` is now (snapped to the art pixels, bobbing).
func position_of(i: int) -> Vector2:
	var floater := floaters[i]
	var at := (floater.position_at(_time) / STEP).round() * STEP
	return at + Vector2(0.0, roundf(sin(_time * 1.3 + floater.drift.z * 3.0)) * STEP)


## Rings round each body for the floor: art pixel, radius (art px), phase.
func ripples() -> Array[Vector4]:
	var result: Array[Vector4] = []
	for i in floaters.size():
		var at := position_of(i) / STEP
		result.append(Vector4(at.x, at.y, floaters[i].radius / STEP * 0.8, floaters[i].drift.z))
	return result


func _draw() -> void:
	for i in floaters.size():
		var floater := floaters[i]
		var art := _arts[i]
		var at := position_of(i)
		# Facing the way it drifts: the body was painted facing its own way.
		var going := cos(floater.drift.z + TAU * _time / maxf(floater.drift.y, 1.0) + PI * 0.5)
		var flip := (going > 0.0) == floater.facing_left
		var rect := art.local_rect
		if flip:
			draw_set_transform(at, 0.0, Vector2(-1.0, 1.0))
		else:
			draw_set_transform(at)
		draw_texture_rect(art.texture, rect, false)
	draw_set_transform(Vector2.ZERO)
