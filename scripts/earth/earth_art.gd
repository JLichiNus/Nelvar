class_name NelvarEarthArt
extends RefCounted
## One baked sprite of the earth valley around its ground origin. The image is
## painted on a worker thread; bake() makes the texture on the main thread.

var local_rect: Rect2
var image: Image
var texture: ImageTexture
## Plants sway in the wind: how far their top leans, in art pixels (0 = still).
var sway := 0
## Statues: the top-left corner of the eye's middle pixel, art pixels from the origin.
var eye := Vector2.INF


static func from_canvas(canvas: NelvarEarthCanvas) -> NelvarEarthArt:
	var art := NelvarEarthArt.new()
	art.local_rect = canvas.local_rect()
	art.image = canvas.image
	return art


func bake() -> void:
	if texture == null and image != null:
		texture = ImageTexture.create_from_image(image)
