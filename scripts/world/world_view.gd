class_name NelvarWorldView
extends Node2D

const BridgeDetails = preload("res://scripts/world/bridge_details.gd")

@export var terrain_style: NelvarTerrainStyle = preload("res://resources/earth_terrain_style.tres")

var world: NelvarWorldData
var terrain_art: Array[NelvarIslandArt] = []
var bridge_art: Array[NelvarBridgeArt] = []
var details: Node2D
var clouds: Array[NelvarCloudPainter.Cloud] = []
var _sky: Rect2


func build(data: NelvarWorldData) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	world = data
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	terrain_art = NelvarTerrainPainter.new().paint(data, terrain_style)
	bridge_art = NelvarBridgePainter.new().paint(data, terrain_style)
	_sky = data.bounds.grow(1400.0)
	clouds = NelvarCloudPainter.new().paint(data, terrain_style, _sky, 70)
	for leaf in data.leaves:
		var chunk := NelvarWorldChunk.new()
		chunk.setup(data, leaf, terrain_art)
		add_child(chunk)
	details = BridgeDetails.new()
	details.world = data
	details.bridge_art = bridge_art
	add_child(details)
	queue_redraw()


func _process(delta: float) -> void:
	if world == null:
		return
	# Clouds drift with the wind and wrap around the sky rectangle.
	for cloud in clouds:
		cloud.position.x += cloud.speed * delta
		if cloud.position.x > _sky.end.x:
			cloud.position.x -= _sky.size.x + cloud.size.x
	queue_redraw()


func toggle_chunks() -> bool:
	if details == null:
		return false
	details.show_chunks = not details.show_chunks
	details.queue_redraw()
	return details.show_chunks


func _draw() -> void:
	if world == null:
		return
	var step := float(maxi(1, terrain_style.pixel_size))
	for cloud in clouds:
		# Snap to the terrain pixel grid so drifting clouds stay crisp.
		var at := (cloud.position / step).round() * step
		draw_texture_rect(cloud.texture, Rect2(at, cloud.size), false,
			Color(1, 1, 1, cloud.opacity))
	for art in terrain_art:
		draw_texture_rect(art.surface_texture,
			Rect2(art.world_rect.position + Vector2(16, 100), art.world_rect.size),
			false, Color(0.16, 0.23, 0.27, 0.2))
	for art in terrain_art:
		draw_texture_rect(art.underside_texture, art.world_rect, false)
