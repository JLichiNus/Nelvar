class_name NelvarFireArt
extends NelvarEarthArt
## One baked sprite of the fire forge. Glowing pixels are keyed by alpha
## (fire_molten.gdshader animates them): FLOW streams downwards like lava down a slope,
## HOT churns and flickers, EMBER breathes slowly. Painted on a worker thread like the
## earth's art.

const FLOW_KEY := 250
const HOT_KEY := 251
const EMBER_KEY := 252

## Carries keyed pixels: drawn with fire_molten.gdshader.
var molten := false
## Where smoke rises from (the crater, a smouldering top, a vent's mouth), art pixels
## from the origin; INF for none.
var vent := Vector2.INF
## Where sparks fly up from (glowing cracks), art pixels from the origin.
var sparks := PackedVector2Array()


static func of(canvas: NelvarEarthCanvas) -> NelvarFireArt:
	var art := NelvarFireArt.new()
	art.local_rect = canvas.local_rect()
	art.image = canvas.image
	return art


## The same sprite as an earth art (a peak painted by NelvarMountainPainter).
static func adopt(earth: NelvarEarthArt) -> NelvarFireArt:
	var art := NelvarFireArt.new()
	art.local_rect = earth.local_rect
	art.image = earth.image
	art.sway = earth.sway
	art.relief = earth.relief
	art.waterfall = earth.waterfall
	return art


## The keyed colour: what the pixel shows without the shader, with its key as alpha.
static func keyed(color: Color, key: int) -> Color:
	return Color(color.r, color.g, color.b, key / 255.0)
