class_name NelvarProp
extends StaticBody2D
## A rock or a bush. The origin is the ground centre of its footprint: it drives Y-sorting
## against the player, and for rocks also the elliptic collider. Bushes do not collide.

const FOOTPRINT_POINTS := 16
## Physics layer 1 ("World"): blocks everyone.
const WORLD_LAYER := 1
## Physics layer 6 ("LowObstacles"): small rocks. They stop walkers, enemies and
## projectiles, but the flying player passes over them.
const LOW_OBSTACLE_LAYER := 32
## Rocks up to this radius are low enough to fly over, on both maps.
const LOW_ROCK_RADIUS := 28.0


## The layer a rock of this radius collides on.
static func rock_layer(radius: float) -> int:
	return LOW_OBSTACLE_LAYER if radius <= LOW_ROCK_RADIUS else WORLD_LAYER

var prop_data: NelvarPropData.PropSpec
var art: NelvarPropArt
var show_collision := false


func setup(data: NelvarPropData.PropSpec, artwork: NelvarPropArt) -> void:
	prop_data = data
	art = artwork
	name = "%s_%d" % ["Rock" if data.is_solid() else "Bush", data.id]
	position = data.position
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	collision_layer = 0
	collision_mask = 0
	if not data.is_solid():
		return
	collision_layer = rock_layer(data.radius)
	collision_mask = 2
	var shape := ConvexPolygonShape2D.new()
	shape.points = footprint_polygon(data.footprint())
	var collider := CollisionShape2D.new()
	collider.name = "RockCollision"
	collider.shape = shape
	add_child(collider)


static func footprint_polygon(axes: Vector2) -> PackedVector2Array:
	var points := PackedVector2Array()
	for i in FOOTPRINT_POINTS:
		points.append(Vector2.from_angle(TAU * float(i) / FOOTPRINT_POINTS) * axes)
	return points


func _enter_tree() -> void:
	# Like tree crowns: whoever stands behind gets an outline drawn over the prop.
	if art != null:
		NelvarOcclusionOutline.add_occluder(self, art.texture,
			Rect2(global_position + art.local_rect.position, art.local_rect.size))


func _exit_tree() -> void:
	NelvarOcclusionOutline.remove_occluder(self)


func _draw() -> void:
	if art == null:
		return
	draw_texture_rect(art.texture, art.local_rect, false)
	if show_collision and prop_data.is_solid():
		var outline := footprint_polygon(prop_data.footprint())
		outline.append(outline[0])
		draw_polyline(outline, Color("ff6470"), 2.0)
