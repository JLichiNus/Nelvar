class_name NelvarWorldView
extends Node2D

const BridgeDetails = preload("res://scripts/world/bridge_details.gd")

@export var terrain_style: NelvarTerrainStyle = preload("res://resources/earth_terrain_style.tres")

var world: NelvarWorldData
var terrain_art: Array[NelvarIslandArt] = []
var bridge_art: Array[NelvarBridgeArt] = []
var details: Node2D
var _clouds: Array[Vector3] = []


func build(data: NelvarWorldData) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	world = data
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	terrain_art = NelvarTerrainPainter.new().paint(data, terrain_style)
	bridge_art = NelvarBridgePainter.new().paint(data, terrain_style)
	_clouds.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = ("%d:sky" % data.world_seed).hash()
	var sky_bounds := data.bounds.grow(1400.0)
	for i in 90:
		_clouds.append(Vector3(
			rng.randf_range(sky_bounds.position.x, sky_bounds.end.x),
			rng.randf_range(sky_bounds.position.y, sky_bounds.end.y),
			rng.randf_range(90.0, 220.0)))
	for leaf in data.leaves:
		var chunk := NelvarWorldChunk.new()
		chunk.setup(data, leaf, terrain_art)
		add_child(chunk)
	details = BridgeDetails.new()
	details.world = data
	details.bridge_art = bridge_art
	add_child(details)
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
	for cloud in _clouds:
		draw_set_transform(Vector2(cloud.x, cloud.y), 0.0, Vector2(1.7, 0.6))
		var color := Color(0.86, 0.92, 0.96, 0.12)
		draw_circle(Vector2.ZERO, cloud.z, color)
		draw_circle(Vector2(cloud.z * 0.7, -cloud.z * 0.15), cloud.z * 0.7, color)
	draw_set_transform(Vector2.ZERO)
	for art in terrain_art:
		draw_texture_rect(art.surface_texture,
			Rect2(art.world_rect.position + Vector2(16, 100), art.world_rect.size),
			false, Color(0.16, 0.23, 0.27, 0.2))
	for art in terrain_art:
		draw_texture_rect(art.underside_texture, art.world_rect, false)
