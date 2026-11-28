class_name NelvarIceArt
extends NelvarEarthArt
## One baked sprite of the ice valley around its ground origin (painted on a worker
## thread like the earth's art). Ice glints: a few pixels twinkle now and then.

## Where the ice glints (blocks, icicles, frozen crowns), art pixels from the origin.
var sparkles := PackedVector2Array()


static func of(canvas: NelvarEarthCanvas) -> NelvarIceArt:
	var art := NelvarIceArt.new()
	art.local_rect = canvas.local_rect()
	art.image = canvas.image
	return art


## The same sprite as an earth art (a peak painted by NelvarMountainPainter).
static func adopt(earth: NelvarEarthArt) -> NelvarIceArt:
	var art := NelvarIceArt.new()
	art.local_rect = earth.local_rect
	art.image = earth.image
	art.sway = earth.sway
	art.eye = earth.eye
	art.relief = earth.relief
	return art
