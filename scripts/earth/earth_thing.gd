class_name NelvarEarthThing
extends StaticBody2D
## Anything standing in the earth valley, or a peak round it. The origin is the ground
## point: it drives Y-sorting against the player and centres the collider.
##
## Plants sway: their upper part leans one art pixel (two for tall grass and willows)
## while a gust passes — whole pixels, drawn as shifted bands of the texture.
## A petrified creature opens its eye while the player is near and watches them.

const Kind = NelvarEarthData.Kind
const STEP := NelvarEarthData.PIXEL
const DEBUG_COLOR := Color("ff6470")
## Statues: the eye opens within this distance and closes beyond the next.
const EYE_OPEN_DISTANCE := 260.0
const EYE_CLOSE_DISTANCE := 320.0
const EYE_OUTLINE := Color8(46, 50, 54)
const EYE_WHITE := Color8(232, 222, 168)
const EYE_PUPIL := Color8(36, 22, 26)

var thing: NelvarEarthData.Thing
var art: NelvarEarthArt
var show_collision := false
## Current lean of a plant's top, art pixels.
var lean := 0
## Statues: whose approach opens the eye.
var watcher: Node2D

## 0 closed, 1 a slit, 2 open.
var _eye := 0
var _look := 0
var _eye_timer := 0.0


func setup(spec: NelvarEarthData.Thing, artwork: NelvarEarthArt) -> void:
	thing = spec
	art = artwork
	name = "%s_%d" % [(Kind.keys()[spec.kind] as String).capitalize().replace(" ", ""), spec.id]
	position = spec.position
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	collision_layer = 0
	collision_mask = 0
	if spec.kind == Kind.LILY:
		# Flat on the water, under everything that stands.
		z_index = -1
	set_process(spec.kind == Kind.STATUE)
	if not spec.solid:
		return
	collision_layer = NelvarProp.WORLD_LAYER
	if spec.kind == Kind.ROCK:
		collision_layer = NelvarProp.rock_layer(spec.radius)
	collision_mask = 2
	var collider := CollisionShape2D.new()
	collider.name = "Collision"
	if spec.kind == Kind.TREE or spec.kind == Kind.STUMP:
		var circle := CircleShape2D.new()
		circle.radius = spec.radius
		collider.shape = circle
	else:
		var shape := ConvexPolygonShape2D.new()
		shape.points = NelvarProp.footprint_polygon(spec.footprint())
		collider.shape = shape
	add_child(collider)


## The art painted after the node went up (the collision stood from the start).
func set_art(artwork: NelvarEarthArt) -> void:
	art = artwork
	if is_inside_tree():
		_add_occluder()
	queue_redraw()


## Tiny things on the ground never hide the player.
func occludes() -> bool:
	return thing.kind not in [Kind.LILY, Kind.MUSHROOMS, Kind.FLOWERS]


func _enter_tree() -> void:
	_add_occluder()


func _add_occluder() -> void:
	if art != null and art.texture != null and occludes():
		NelvarOcclusionOutline.add_occluder(self, art.texture,
			Rect2(global_position + art.local_rect.position, art.local_rect.size))


func _exit_tree() -> void:
	NelvarOcclusionOutline.remove_occluder(self)


## Called with the wind's strength here (NelvarEarthMain.gust); redraws on a change.
func set_gust(value: float) -> void:
	var amount := art.sway
	var next := 0
	if value > 0.8:
		next = amount
	elif value > 0.45 or (amount > 1 and value > 0.3):
		next = 1
	elif value < -0.85:
		next = -1
	if next != lean:
		lean = next
		queue_redraw()


func _process(delta: float) -> void:
	if art == null or watcher == null or not is_instance_valid(watcher):
		return
	var distance := global_position.distance_to(watcher.global_position)
	var wanted := 2 if distance < EYE_OPEN_DISTANCE else (_eye if distance < EYE_CLOSE_DISTANCE else 0)
	var look := clampi(roundi((watcher.global_position.x - global_position.x - art.eye.x * STEP) / 90.0), -1, 1)
	_eye_timer -= delta
	if wanted != _eye and _eye_timer <= 0.0:
		# Through the slit, one step at a time.
		_eye += signi(wanted - _eye)
		_eye_timer = 0.12
		queue_redraw()
	if look != _look:
		_look = look
		if _eye > 0:
			queue_redraw()


func is_eye_open() -> bool:
	return _eye == 2


func _draw() -> void:
	if art == null or art.texture == null:
		return
	if lean == 0:
		draw_texture_rect(art.texture, art.local_rect, false)
	else:
		_draw_leaning()
	if _eye > 0:
		_draw_eye()
	if show_collision and thing.solid:
		if thing.kind == Kind.TREE or thing.kind == Kind.STUMP:
			draw_circle(Vector2.ZERO, thing.radius, DEBUG_COLOR, false, 2.0)
		else:
			var outline := NelvarProp.footprint_polygon(thing.footprint())
			outline.append(outline[0])
			draw_polyline(outline, DEBUG_COLOR, 2.0)


## The top of the art leans by `lean`, the middle by half of it, the rest stands still.
func _draw_leaning() -> void:
	var rect := art.local_rect
	var rows := roundi(rect.size.y / STEP)
	var above := -rect.position.y / STEP
	var cuts: Array[int] = [0, clampi(int(above * 0.38), 0, rows), clampi(int(above * 0.7), 0, rows), rows]
	var shifts: Array[int] = [lean, int(lean / 2.0), 0]
	for i in 3:
		if cuts[i + 1] <= cuts[i]:
			continue
		var source := Rect2(0, cuts[i], rect.size.x / STEP, cuts[i + 1] - cuts[i])
		var target := Rect2(rect.position + Vector2(shifts[i], cuts[i]) * STEP,
			Vector2(rect.size.x, (cuts[i + 1] - cuts[i]) * STEP))
		draw_texture_rect_region(art.texture, target, source)


## The open eye over the baked lid: a pale slit, then a full eye with a pupil that
## looks towards the player.
func _draw_eye() -> void:
	var center := art.eye
	var half := 2
	var cell := Vector2.ONE * STEP
	for dx in range(-half + 1, half):
		draw_rect(Rect2((center + Vector2(dx, 0)) * STEP, cell), EYE_WHITE)
	if _eye == 2:
		for dx in range(-half + 1, half):
			draw_rect(Rect2((center + Vector2(dx, -1)) * STEP, cell), EYE_OUTLINE)
		draw_rect(Rect2((center + Vector2(-half, 0)) * STEP, cell), EYE_OUTLINE)
		draw_rect(Rect2((center + Vector2(half, 0)) * STEP, cell), EYE_OUTLINE)
		draw_rect(Rect2((center + Vector2(_look, 0)) * STEP, cell), EYE_PUPIL)
	else:
		draw_rect(Rect2((center + Vector2(_look, 0)) * STEP, cell), EYE_PUPIL)
