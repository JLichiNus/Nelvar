class_name NelvarVoidThreads
extends Node2D
## Faint threads of light across the gaps of the route, as if someone had walked
## here before: a trail of pixel motes from the edge of one piece to the next, with
## a pulse running along it towards the monolith. Their look tells what a crossing
## takes: violet dots for a step, longer blue dashes for a run-up, sparse pale
## motes for a flight. A drifting piece gets a thread at both ends of its way.

const SPACING: Array[float] = [10.0, 14.0, 26.0]
const DASH: Array[int] = [1, 2, 1]
const COLORS: Array[Color] = [Color(0.8, 0.58, 1.0), Color(0.55, 0.8, 1.0), Color(1.0, 0.96, 1.0)]
## The thread reaches this far onto each piece.
const OVERLAP := 10.0

class Trail:
	var from: Vector2
	var to: Vector2
	var gap: NelvarVoidData.Gap

var _threads: Array[Trail] = []
var _time := 0.0


func setup(data: NelvarVoidData) -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	z_index = 2
	var glow := CanvasItemMaterial.new()
	glow.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = glow
	for i in data.route.size():
		var here := data.debris[data.route[i]]
		var far := here.period * 0.5 if here.motion == NelvarVoidData.Motion.FERRY else 0.0
		var from := here.position + here.offset_at(far)
		var there := data.monolith
		if i + 1 < data.route.size():
			there = data.debris[data.route[i + 1]]
		var points := NelvarVoidData.crossing_points(from, here.world_polygon(far), there.position,
			there.world_polygon(0.0))
		var thread := Trail.new()
		var direction := points[0].direction_to(points[1])
		thread.from = points[0] - direction * OVERLAP
		thread.to = points[1] + direction * OVERLAP
		thread.gap = here.gap
		_threads.append(thread)


func _process(delta: float) -> void:
	_time += delta
	queue_redraw()


func _draw() -> void:
	for thread in _threads:
		var length := thread.from.distance_to(thread.to)
		var direction := thread.from.direction_to(thread.to)
		var spacing: float = SPACING[thread.gap]
		var color: Color = COLORS[thread.gap]
		var count := int(length / spacing)
		for i in count + 1:
			var along := float(i) * spacing
			# A pulse travels along the thread, towards the monolith.
			var pulse := pow(0.5 + 0.5 * sin(_time * 2.6 - along * 0.06), 6.0)
			var core := 0.45 + 0.55 * pulse
			var point := (thread.from + direction * along).snapped(Vector2(4.0, 4.0))
			for dash in DASH[thread.gap]:
				var spot: Vector2 = (point + direction * 4.0 * dash).snapped(Vector2(4.0, 4.0))
				# A soft square halo, then the bright mote itself.
				color.a = core * 0.16
				draw_rect(Rect2(spot - Vector2(6.0, 6.0), Vector2(12.0, 12.0)), color)
				color.a = core
				draw_rect(Rect2(spot - Vector2(2.0, 2.0), Vector2(4.0, 4.0)), color)
