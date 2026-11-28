class_name NelvarIceDepths
extends CanvasLayer
## What lies under the lakes' ice: dark water with slow streaks of light and the
## creatures frozen into it. Drawn under the floor (whose ice is translucent): only
## the ice lets it show, the thin ice most.
##
## It lies deeper than the floor: it follows the camera by PARALLAX only, the creatures
## round their anchors (NelvarIceData.depth_anchors: each lake's centre, and in the cave
## also the spots in the walls), so standing over a creature puts it right under the
## player. The offset is snapped to whole art pixels, so the sprites stay on the world
## grid and never smear. A creature with an eye opens it, slowly, while the player
## stands over it (or, deep in a wall, walks by it), and follows them with it (as the
## petrified ones do); under melting ice they drift slowly round a loop.
##
## The cave gives it a mask (set_mask): under the walls' translucent tops it shows deep
## blue ice with bubbles and layers instead of water, under the chasms nothing (the
## abyss below shows). Without a mask it is all water, as on the valley.

const SHADER := preload("res://scripts/ice/ice_depths.gdshader")
const STEP := NelvarIceData.PIXEL
## 1 = moves with the floor, 0 = fixed on screen.
const PARALLAX := 0.85
## Pale and cold: light enough to read through the ice against the dark water.
const TINT := Color(1.8, 2.0, 2.25)


## A creature frozen under the ice.
class FrozenNode extends Node2D:
	const EYE_OUTLINE := Color8(30, 44, 66)
	const EYE_WHITE := Color8(196, 232, 242)
	const EYE_PUPIL := Color8(10, 18, 36)
	## The eye opens while the watcher is this close (beyond the body's radius), and
	## closes past the next.
	const OPEN_REACH := 50.0
	const CLOSE_REACH := 140.0
	## Seconds per step of the lid: slow.
	const LID_TIME := 0.32

	var creature: NelvarIceData.Frozen
	var art: NelvarIceArt
	var watcher: Node2D
	## 0 closed, 1 a slit, 2 open.
	var eye := 0
	var look := Vector2i.ZERO
	var _lid_timer := 0.0

	func setup(spec: NelvarIceData.Frozen, artwork: NelvarIceArt) -> void:
		creature = spec
		art = artwork
		name = "Frozen_%d" % spec.id
		position = spec.position
		texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		self_modulate = TINT

	func watch(delta: float) -> void:
		if not creature.eye or watcher == null or not is_instance_valid(watcher) or not art.eye.is_finite():
			return
		var eye_point := global_position + art.eye * STEP
		var distance := global_position.distance_to(watcher.global_position) - creature.radius - creature.reach
		var wanted := 2 if distance < OPEN_REACH else (eye if distance < CLOSE_REACH else 0)
		_lid_timer -= delta
		if wanted != eye and _lid_timer <= 0.0:
			eye += signi(wanted - eye)
			_lid_timer = LID_TIME
			queue_redraw()
		var offset := watcher.global_position - eye_point
		var next := Vector2i(clampi(roundi(offset.x / 60.0), -1, 1), clampi(roundi(offset.y / 60.0), -1, 0))
		if next != look:
			look = next
			if eye > 0:
				queue_redraw()

	func is_eye_open() -> bool:
		return eye == 2

	func _draw() -> void:
		if art == null or art.texture == null:
			return
		draw_texture_rect(art.texture, art.local_rect, false)
		if eye == 0 or not art.eye.is_finite():
			return
		var center := art.eye
		var cell := Vector2.ONE * STEP
		# A huge eye: a pale slit, then wide open with a dark pupil that follows.
		for dx in range(-2, 3):
			draw_rect(Rect2((center + Vector2(dx, 0)) * STEP, cell), EYE_WHITE)
		if eye == 2:
			for dx in range(-2, 3):
				draw_rect(Rect2((center + Vector2(dx, -1)) * STEP, cell), EYE_WHITE if absi(dx) < 2 else EYE_OUTLINE)
				draw_rect(Rect2((center + Vector2(dx, 1)) * STEP, cell), EYE_OUTLINE if absi(dx) == 2 else EYE_WHITE)
			draw_rect(Rect2((center + Vector2(-3, 0)) * STEP, cell), EYE_OUTLINE)
			draw_rect(Rect2((center + Vector2(3, 0)) * STEP, cell), EYE_OUTLINE)
			draw_rect(Rect2((center + Vector2(-1, -2)) * STEP, Vector2(3, 1) * STEP), EYE_OUTLINE)
			draw_rect(Rect2((center + Vector2(-1, 2)) * STEP, Vector2(3, 1) * STEP), EYE_OUTLINE)
			draw_rect(Rect2((center + Vector2(look.x, look.y)) * STEP, cell), EYE_PUPIL)
			draw_rect(Rect2((center + Vector2(look.x, look.y + 1)) * STEP, cell), EYE_PUPIL)
		else:
			draw_rect(Rect2((center + Vector2(look.x, 0)) * STEP, cell), EYE_PUPIL)


var frozen_nodes: Array[FrozenNode] = []

var _water: ColorRect
var _material: ShaderMaterial
## One holder per anchor (a lake, a spot in a wall): its creatures move round it.
var _holders: Array[Node2D] = []
var _anchors := PackedVector2Array()
var _drifting: Array[FrozenNode] = []
var _time := 0.0


func _ready() -> void:
	layer = -2
	follow_viewport_enabled = true
	# Late priority: read the camera only after it has moved this frame.
	process_priority = 100
	_material = ShaderMaterial.new()
	_material.shader = SHADER
	_water = ColorRect.new()
	_water.name = "Water"
	_water.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_water.material = _material
	add_child(_water)


## `arts[i]` is the painted art of `data.frozen[i]`; `watcher` opens their eyes.
func setup(data: NelvarIceData, arts: Array, watcher: Node2D) -> void:
	var anchors := data.depth_anchors()
	for i in anchors.size():
		var holder := Node2D.new()
		holder.name = "Lake_%d" % i if i < data.lakes.size() else "Wall_%d" % (i - data.lakes.size())
		add_child(holder)
		_holders.append(holder)
		_anchors.append(anchors[i])
	for i in data.frozen.size():
		var creature := data.frozen[i]
		var art: NelvarIceArt = arts[i]
		if art == null:
			continue
		art.bake()
		var node := FrozenNode.new()
		node.setup(creature, art)
		node.watcher = watcher
		_holders[creature.lake].add_child(node)
		frozen_nodes.append(node)
		if creature.drift.x > 0.0:
			_drifting.append(node)
	_update_view()


## Shows ice under the walls and nothing under the chasms: the cave's distance field
## (one texel per `sdf_cell` world units from `sdf_origin`) and its zone map (R chasm,
## G arch; one texel per art pixel from `zone_origin`).
func set_mask(sdf: Texture2D, sdf_origin: Vector2, sdf_size: Vector2, sdf_cell: float, zone: Texture2D,
		zone_origin: Vector2, zone_size: Vector2) -> void:
	_material.set_shader_parameter("use_mask", true)
	_material.set_shader_parameter("sdf_tex", sdf)
	_material.set_shader_parameter("sdf_origin", sdf_origin)
	_material.set_shader_parameter("sdf_size", sdf_size)
	_material.set_shader_parameter("sdf_cell", sdf_cell)
	_material.set_shader_parameter("zone_tex", zone)
	_material.set_shader_parameter("zone_origin", zone_origin)
	_material.set_shader_parameter("zone_size", zone_size)


func material() -> ShaderMaterial:
	return _material


func _process(delta: float) -> void:
	_time += delta
	for node in _drifting:
		# Whole art pixels from where it was painted, so it stays on the world grid.
		node.position = node.creature.position + snap(node.creature.position_at(_time) - node.creature.position)
	_update_view()
	for node in frozen_nodes:
		node.watch(delta)


## Whole art pixels of `offset`.
static func snap(offset: Vector2) -> Vector2:
	return (offset / STEP).round() * STEP


func _update_view() -> void:
	var viewport := get_viewport()
	if viewport == null:
		return
	var to_world := viewport.get_canvas_transform().affine_inverse()
	var top_left := to_world * Vector2.ZERO
	var extent := to_world.basis_xform(viewport.get_visible_rect().size)
	var center := top_left + extent * 0.5
	var view := Rect2(top_left, extent).grow(STEP * 2.0)
	_water.position = view.position
	_water.size = view.size
	_material.set_shader_parameter("rect_origin", view.position)
	_material.set_shader_parameter("rect_size", view.size)
	_material.set_shader_parameter("shift", snap(center * (1.0 - PARALLAX)))
	_material.set_shader_parameter("texel_size", float(STEP))
	_material.set_shader_parameter("time", _time)
	for i in _holders.size():
		_holders[i].position = snap((center - _anchors[i]) * (1.0 - PARALLAX))
