class_name NelvarIceThing
extends StaticBody2D
## Anything standing in the ice valley. The origin is the ground point: it drives
## Y-sorting against the player and centres the collider. Plants lean in the wind in
## whole art pixels (as on the earth map); ice glints now and then; a petrified creature
## opens its eye while the player is near and watches them (as on the earth map).

const Kind = NelvarIceData.Kind
const STEP := NelvarIceData.PIXEL
const DEBUG_COLOR := Color("ff6470")
const EYE_OPEN_DISTANCE := NelvarEarthThing.EYE_OPEN_DISTANCE
const EYE_CLOSE_DISTANCE := NelvarEarthThing.EYE_CLOSE_DISTANCE
const EYE_OUTLINE := Color8(58, 62, 70)
const EYE_WHITE := Color8(214, 236, 244)
const EYE_PUPIL := Color8(22, 34, 58)
const SPARKLE := Color(1.0, 1.0, 1.0, 0.95)

var thing: NelvarIceData.Thing
var art: NelvarIceArt
var show_collision := false
var lean := 0
## Statues: whose approach opens the eye.
var watcher: Node2D

## 0 closed, 1 a slit, 2 open.
var _eye := 0
var _look := 0
var _eye_timer := 0.0
## The sparkle shown now (index into art.sparkles, -1 none) and when it changes.
var _sparkle := -1
var _sparkle_timer := 0.0


## The art may come later (set_art): the collision stands from the start.
func setup(spec: NelvarIceData.Thing, artwork: NelvarIceArt = null) -> void:
	thing = spec
	name = "%s_%d" % [(Kind.keys()[spec.kind] as String).capitalize().replace(" ", ""), spec.id]
	position = spec.position
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	collision_layer = 0
	collision_mask = 0
	_sparkle_timer = fmod(float(spec.appearance_seed & 0xffff) / 997.0, 3.0)
	set_process(false)
	if artwork != null:
		set_art(artwork)
	if not spec.solid:
		return
	collision_layer = NelvarProp.WORLD_LAYER
	if spec.kind in [Kind.ROCK, Kind.ICE_BLOCK, Kind.DRIFT, Kind.ICE_STONE, Kind.CRYSTAL, Kind.STALAGMITE]:
		collision_layer = NelvarProp.rock_layer(spec.radius)
	collision_mask = 2
	var collider := CollisionShape2D.new()
	collider.name = "Collision"
	if spec.is_tree():
		var circle := CircleShape2D.new()
		circle.radius = spec.radius
		collider.shape = circle
	else:
		var shape := ConvexPolygonShape2D.new()
		shape.points = NelvarProp.footprint_polygon(spec.footprint())
		collider.shape = shape
	add_child(collider)


func set_art(artwork: NelvarIceArt) -> void:
	art = artwork
	set_process(thing.kind == Kind.STATUE or art.eye.is_finite() or not art.sparkles.is_empty())
	if is_inside_tree():
		_add_occluder()
	queue_redraw()


## Low things on the ground never hide the player.
func occludes() -> bool:
	return thing.kind not in [Kind.DRY_GRASS, Kind.DRIFT, Kind.BONES]


func _enter_tree() -> void:
	_add_occluder()


func _add_occluder() -> void:
	if art != null and art.texture != null and occludes():
		NelvarOcclusionOutline.add_occluder(self, art.texture,
			Rect2(global_position + art.local_rect.position, art.local_rect.size))


func _exit_tree() -> void:
	NelvarOcclusionOutline.remove_occluder(self)


## Called with the wind's strength here (NelvarIceMain.gust); redraws on a change.
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
	# Processing comes on by itself when the node is ready, art or not.
	if art == null:
		return
	if not art.sparkles.is_empty():
		_sparkle_timer -= delta
		if _sparkle_timer <= 0.0:
			# A short glint, then a while of nothing.
			if _sparkle >= 0:
				_sparkle = -1
				_sparkle_timer = randf_range(1.5, 4.5)
			else:
				_sparkle = randi_range(0, art.sparkles.size() - 1)
				_sparkle_timer = 0.18
			queue_redraw()
	if watcher == null or not is_instance_valid(watcher) or not art.eye.is_finite():
		return
	var distance := global_position.distance_to(watcher.global_position)
	var wanted := 2 if distance < EYE_OPEN_DISTANCE else (_eye if distance < EYE_CLOSE_DISTANCE else 0)
	var look := clampi(roundi((watcher.global_position.x - global_position.x - art.eye.x * STEP) / 90.0), -1, 1)
	_eye_timer -= delta
	if wanted != _eye and _eye_timer <= 0.0:
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
	if _sparkle >= 0 and _sparkle < art.sparkles.size():
		var at := art.sparkles[_sparkle] * STEP
		var cell := Vector2.ONE * STEP
		draw_rect(Rect2(at, cell), SPARKLE)
		for offset: Vector2 in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
			draw_rect(Rect2(at + offset * STEP, cell), Color(1, 1, 1, 0.45))
	if _eye > 0:
		_draw_eye()
	if show_collision and thing.solid:
		if thing.is_tree():
			draw_circle(Vector2.ZERO, thing.radius, DEBUG_COLOR, false, 2.0)
		else:
			var outline := NelvarProp.footprint_polygon(thing.footprint())
			outline.append(outline[0])
			draw_polyline(outline, DEBUG_COLOR, 2.0)


## The open eye over the baked lid: a pale slit, then a full eye looking at the player.
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
