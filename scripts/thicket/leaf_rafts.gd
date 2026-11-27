class_name NelvarLeafRafts
extends Node2D
## The leaves drifting round the ponds as rafts (NelvarThicketData.Raft: where a raft is
## depends on the shared clock only). They hold the player and the hoppers and carry them
## (NelvarThicketMain moves whoever stands on one by its shift). A small leaf scoops water
## over its edge under a standing player: after SINK_DELAY seconds of their weight it goes
## under in SINK_TIME, stays under UNDER_TIME and comes up again.
##
## Each raft is drawn flat on the water, on whole art pixels, with a faint ripple round it.

const STEP := NelvarEarthData.PIXEL
const SINK_DELAY := 1.2
const SINK_TIME := 0.5
const UNDER_TIME := 6.0
const RISE_TIME := 1.5
const RIPPLE := Color(0.78, 0.9, 0.86, 0.35)


class Leaf extends Node2D:
	var raft: NelvarThicketData.Raft
	var art: NelvarEarthArt
	## Seconds of the player's weight (small ones), seconds under.
	var weight := 0.0
	var under := 0.0
	var show_collision := false

	func _draw() -> void:
		if art == null or art.texture == null:
			return
		var sink := raft.sink
		if sink < 1.0:
			draw_texture_rect(art.texture, art.local_rect, false, Color(1, 1, 1, 1.0 - sink * 0.75).lerp(Color(0.5, 0.7, 0.7, 1.0 - sink * 0.75), sink))
		# A faint ripple ring round the leaf.
		var axes := Vector2(raft.length, raft.width) * 0.5 + Vector2.ONE * 8.0
		var points := PackedVector2Array()
		for i in 25:
			var angle := TAU * i / 24.0
			var local := Vector2(cos(angle) * axes.x, sin(angle) * axes.y).rotated(raft.angle)
			points.append((local / STEP).round() * STEP)
		for i in range(0, 24, 2):
			draw_line(points[i], points[i + 1], RIPPLE, STEP * 0.5)
		if show_collision:
			var outline := PackedVector2Array()
			for i in 33:
				var angle := TAU * i / 32.0
				outline.append(Vector2(cos(angle) * raft.length * 0.5, sin(angle) * raft.width * 0.5).rotated(raft.angle))
			draw_polyline(outline, Color.GREEN_YELLOW if not raft.small() else Color.YELLOW, 2.0)


var data: NelvarThicketData
var leaves: Array[Leaf] = []
## Small rafts that went under so far.
var sunk := 0


func setup(thicket: NelvarThicketData, arts: Array) -> void:
	data = thicket
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	for i in data.rafts.size():
		var leaf := Leaf.new()
		leaf.name = "Raft_%d" % data.rafts[i].id
		leaf.raft = data.rafts[i]
		leaf.art = arts[i]
		leaf.art.bake()
		leaf.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		add_child(leaf)
		leaves.append(leaf)
	sync(0.0)


## Places every raft at `clock` on whole art pixels.
func sync(clock: float) -> void:
	for leaf in leaves:
		leaf.position = (leaf.raft.position_at(clock) / STEP).round() * STEP


## Small rafts sink under a standing player (`carried`: the raft under them, or null).
func step(delta: float, carried: NelvarThicketData.Raft) -> void:
	for leaf in leaves:
		var raft := leaf.raft
		if leaf.under > 0.0:
			leaf.under -= delta
			if leaf.under <= 0.0:
				leaf.under = 0.0
			continue
		if raft.sink > 0.0 and leaf.weight < SINK_DELAY:
			raft.sink = maxf(0.0, raft.sink - delta / RISE_TIME)
			leaf.queue_redraw()
			continue
		if raft.small() and carried == raft:
			leaf.weight += delta
		else:
			leaf.weight = maxf(0.0, leaf.weight - delta * 2.0)
		if leaf.weight >= SINK_DELAY:
			raft.sink = minf(1.0, raft.sink + delta / SINK_TIME)
			leaf.queue_redraw()
			if raft.sink >= 1.0:
				leaf.under = UNDER_TIME
				leaf.weight = 0.0
				sunk += 1


func set_debug(shown: bool) -> void:
	for leaf in leaves:
		leaf.show_collision = shown
		leaf.queue_redraw()
