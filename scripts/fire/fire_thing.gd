class_name NelvarFireThing
extends StaticBody2D
## Anything standing in the fire forge. The origin is the ground point: it drives
## Y-sorting against the player and centres the collider. Plants lean in the hot gusts
## in whole art pixels (as on the earth map).

const Kind = NelvarFireData.Kind
const STEP := NelvarFireData.PIXEL
const DEBUG_COLOR := Color("ff6470")

var thing: NelvarFireData.Thing
var art: NelvarFireArt
var show_collision := false
var lean := 0


## The art may come later (set_art): the collision stands from the start.
func setup(spec: NelvarFireData.Thing, artwork: NelvarFireArt = null) -> void:
	thing = spec
	art = artwork
	name = "%s_%d" % [(Kind.keys()[spec.kind] as String).capitalize().replace(" ", ""), spec.id]
	position = spec.position
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	collision_layer = 0
	collision_mask = 0
	if not spec.solid:
		return
	collision_layer = NelvarProp.WORLD_LAYER
	if spec.kind in [Kind.ROCK, Kind.CRYSTALS]:
		collision_layer = NelvarProp.rock_layer(spec.radius)
	collision_mask = 2
	var collider := CollisionShape2D.new()
	collider.name = "Collision"
	if spec.kind == Kind.TREE or spec.kind == Kind.SNAG:
		var circle := CircleShape2D.new()
		circle.radius = spec.radius
		collider.shape = circle
	else:
		var shape := ConvexPolygonShape2D.new()
		shape.points = NelvarProp.footprint_polygon(spec.footprint())
		collider.shape = shape
	add_child(collider)


func set_art(artwork: NelvarFireArt) -> void:
	art = artwork
	if is_inside_tree():
		_add_occluder()
	queue_redraw()


## Low things on the ground never hide the player.
func occludes() -> bool:
	return thing.kind not in [Kind.VENT, Kind.ASH_FLOWER, Kind.EMBER_GRASS]


## World points where sparks fly up from this thing.
func spark_points() -> PackedVector2Array:
	var points := PackedVector2Array()
	for point in art.sparks:
		points.append(position + point * STEP)
	return points


func _enter_tree() -> void:
	_add_occluder()


func _add_occluder() -> void:
	if art != null and art.texture != null and occludes():
		NelvarOcclusionOutline.add_occluder(self, art.texture,
			Rect2(global_position + art.local_rect.position, art.local_rect.size))


func _exit_tree() -> void:
	NelvarOcclusionOutline.remove_occluder(self)


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
	if show_collision and thing.solid:
		if thing.kind == Kind.TREE or thing.kind == Kind.SNAG:
			draw_circle(Vector2.ZERO, thing.radius, DEBUG_COLOR, false, 2.0)
		else:
			var outline := NelvarProp.footprint_polygon(thing.footprint())
			outline.append(outline[0])
			draw_polyline(outline, DEBUG_COLOR, 2.0)
