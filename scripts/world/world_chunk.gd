class_name NelvarWorldChunk
extends Node2D
## One occupied leaf owns its clipped surface and physical boundary segments.

var chunk: NelvarWorldData.Chunk
var world: NelvarWorldData
var terrain_art: Array[NelvarIslandArt] = []


func setup(data: NelvarWorldData, leaf: NelvarWorldData.Chunk,
		art: Array[NelvarIslandArt]) -> void:
	world = data
	chunk = leaf
	terrain_art = art
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	position = leaf.rect.position
	name = "Chunk_%d_%d_D%d" % [int(position.x), int(position.y), leaf.depth]
	if not leaf.borders.is_empty():
		var body := StaticBody2D.new()
		# Edges stop enemies only: the player may step off into the sky.
		body.collision_layer = NelvarWorldData.EDGE_LAYER
		body.collision_mask = 2
		add_child(body)
		for border in leaf.borders:
			var segment := SegmentShape2D.new()
			segment.a = border.start - position
			segment.b = border.finish - position
			var collider := CollisionShape2D.new()
			collider.shape = segment
			body.add_child(collider)
	queue_redraw()


func _draw() -> void:
	if chunk == null:
		return
	for id in chunk.island_ids:
		var art := terrain_art[id]
		var visible := chunk.rect.intersection(art.world_rect)
		if not visible.has_area():
			continue
		var source := Rect2((visible.position - art.world_rect.position) / art.pixel_size,
			visible.size / art.pixel_size)
		draw_texture_rect_region(art.surface_texture,
			Rect2(visible.position - position, visible.size), source)
