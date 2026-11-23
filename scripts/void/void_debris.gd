class_name NelvarVoidDebris
extends Node2D
## One piece of the Void on screen: the underside hangs below every surface
## (z_index -1 inside the world node), the surface on top, an additive glow over it.
## NelvarVoidMain drives it with the shared Void clock, so what is drawn always
## matches what can be stood on.

const GLOW_MATERIAL_BLEND := CanvasItemMaterial.BLEND_MODE_ADD

var piece: NelvarVoidData.Debris
var art: NelvarDebrisPainter.Art
## Extra glow on top of the breathing (the arena flares up when the fight starts).
var glow_boost := 0.0

var _underside: Sprite2D
var _surface: Sprite2D
var _glow: Sprite2D
var _glow_phase := 0.0


func setup(data: NelvarVoidData.Debris, artwork: NelvarDebrisPainter.Art) -> void:
	piece = data
	art = artwork
	name = "Debris_%d" % data.id if data.id >= 0 else "Monolith"
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_underside = _sprite(art.underside, -1)
	_surface = _sprite(art.surface, 0)
	if art.glow != null:
		_glow = _sprite(art.glow, 1)
		var material := CanvasItemMaterial.new()
		material.blend_mode = GLOW_MATERIAL_BLEND
		_glow.material = material
	_glow_phase = float(data.appearance_seed % 1000) / 1000.0 * TAU
	sync(0.0)


func _sprite(texture: Texture2D, z: int) -> Sprite2D:
	var sprite := Sprite2D.new()
	sprite.texture = texture
	sprite.centered = false
	sprite.position = art.rect.position
	sprite.scale = Vector2.ONE * NelvarDebrisPainter.PIXEL
	sprite.z_index = z
	add_child(sprite)
	return sprite


func sync(time: float) -> void:
	position = (piece.position + piece.offset_at(time)).round()
	if _glow != null:
		var breath := 0.55 + 0.3 * sin(time * 0.9 + _glow_phase)
		_glow.modulate.a = clampf(breath + glow_boost, 0.0, 1.0)
	if piece.motion != NelvarVoidData.Motion.FLICKER:
		return
	# Solid -> flickering warning -> almost gone (a faint ghost stays) -> back.
	var cycle := piece.cycle_at(time)
	var solid_time := NelvarVoidData.FLICKER_SOLID_SHARE * piece.period
	var now := cycle * piece.period
	var alpha := 1.0
	if now >= solid_time:
		var gone := (now - solid_time) / (piece.period - solid_time)
		# Fades back in during the last moment before it is solid again.
		alpha = 0.07 if gone < 0.85 else lerpf(0.07, 0.8, (gone - 0.85) / 0.15)
	elif now > solid_time - NelvarVoidData.FLICKER_WARN_TIME:
		alpha = 1.0 if int(now * 14.0) % 2 == 0 else 0.35
	modulate.a = alpha
