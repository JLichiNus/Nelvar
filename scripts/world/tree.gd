class_name NelvarTree
extends StaticBody2D
## The node origin is the trunk base: the same point drives collision and Y-sort.

var tree_data: NelvarForestData.TreeSpec
var art: NelvarTreeArt
var show_collision := false


func setup(data: NelvarForestData.TreeSpec, artwork: NelvarTreeArt) -> void:
	tree_data = data
	art = artwork
	name = "Tree_%d" % data.id
	position = data.position
	collision_layer = 1
	collision_mask = 2
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	var circle := CircleShape2D.new()
	circle.radius = data.trunk_radius
	var collider := CollisionShape2D.new()
	collider.name = "TrunkCollision"
	collider.shape = circle
	add_child(collider)


func _enter_tree() -> void:
	# Крона закрывает тех, кто стоит позади, — им рисуется контур поверх неё.
	if art != null:
		NelvarOcclusionOutline.add_occluder(self, art.texture,
			Rect2(global_position + art.local_rect.position, art.local_rect.size))


func _exit_tree() -> void:
	NelvarOcclusionOutline.remove_occluder(self)


func _draw() -> void:
	if art == null:
		return
	draw_texture_rect(art.texture, art.local_rect, false)
	if show_collision:
		draw_circle(Vector2.ZERO, tree_data.trunk_radius, Color("ff6470"), false, 2.0)
