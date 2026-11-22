extends Node2D
## Displays baked procedural bridges and optional world debug overlays.

var world: NelvarWorldData
var bridge_art: Array[NelvarBridgeArt] = []
var show_chunks := false


func _ready() -> void:
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


func _draw() -> void:
	if world == null:
		return
	for art in bridge_art:
		draw_texture_rect(art.texture, art.world_rect, false)
	if show_chunks:
		for chunk in world.leaves:
			draw_rect(chunk.rect, Color(0.4, 0.92, 1.0, 0.65), false, 2.0)
		for border in world.borders:
			draw_line(border.start, border.finish, Color(1.0, 0.35, 0.4, 0.9), 2.0)
		for island in world.islands:
			var label := "%s%d" % ["L" if island.large else "S", island.id]
			draw_string(ThemeDB.fallback_font, island.center + Vector2(24, -24),
				label, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 28, Color.WHITE)
