class_name NelvarWorldView
extends Node2D
## Island surfaces (one node per occupied chunk), island undersides and bridges.
## The sky below is NelvarCloudSea on its own canvas layer.

const BridgeDetails = preload("res://scripts/world/bridge_details.gd")

@export var terrain_style: NelvarTerrainStyle = preload("res://resources/earth_terrain_style.tres")

var world: NelvarWorldData
var terrain_art: Array[NelvarIslandArt] = []
var bridge_art: Array[NelvarBridgeArt] = []
var details: Node2D


func build(data: NelvarWorldData) -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	world = data
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	terrain_art = NelvarTerrainPainter.new().paint(data, terrain_style)
	bridge_art = NelvarBridgePainter.new().paint(data, terrain_style)
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
	for art in terrain_art:
		draw_texture_rect(art.underside_texture, art.world_rect, false)
