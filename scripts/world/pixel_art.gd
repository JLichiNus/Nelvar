class_name NelvarPixelArt
extends RefCounted
## Shared helpers for baked pixel art: palette ramps with 4x4 ordered dithering and
## lattice value noise. Both are keyed to global world-grid cells, so neighbouring
## sprites dither and grain consistently.

const BAYER: Array[int] = [0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5]
## Sun from the upper right, as in the air reality of the main menu.
const LIGHT := Vector3(0.4194, -0.5792, 0.6990)
## Soft ground shadow under trees, rocks and bushes; translucent pixels never
## count as occluders for the player's outline.
const SHADOW := Color(0.16, 0.26, 0.3, 0.22)


## Palette lookup (dark to light) with ordered dithering between neighbouring shades.
static func ramp(colors: Array[Color], level: float, cell: Vector2i) -> Color:
	var t := clampf(level, 0.0, 0.9999) * (colors.size() - 1)
	var index := int(t)
	if (t - index) * 16.0 > bayer(cell) + 0.5:
		return colors[index + 1]
	return colors[index]


static func bayer(cell: Vector2i) -> int:
	return BAYER[(cell.y & 3) * 4 + (cell.x & 3)]


static func value_noise(x: float, y: float, salt: int) -> float:
	var ix := floori(x)
	var iy := floori(y)
	var fx := x - ix
	var fy := y - iy
	var sx := fx * fx * (3.0 - 2.0 * fx)
	var sy := fy * fy * (3.0 - 2.0 * fy)
	var a := hash01(ix, iy, salt)
	var b := hash01(ix + 1, iy, salt)
	var c := hash01(ix, iy + 1, salt)
	var d := hash01(ix + 1, iy + 1, salt)
	return a + (b - a) * sx + (c - a) * sy + (a - b - c + d) * sx * sy


static func hash01(x: int, y: int, salt: int) -> float:
	var value := (x * 374761393 + y * 668265263 + salt * 2246822519) & 0xffffffff
	value = ((value ^ (value >> 13)) * 1274126177) & 0xffffffff
	return float((value ^ (value >> 16)) & 0xffff) / 65535.0


## Dithered soft-edged ellipse used for ground shadows (outer 45% fades out).
static func shadow_at(point: Vector2, center: Vector2, reach: Vector2, cell: Vector2i) -> Color:
	var d := ((point - center) / reach).length_squared()
	if d > 1.0:
		return Color.TRANSPARENT
	if d > 0.55 and (1.0 - (d - 0.55) / 0.45) * 16.0 <= bayer(cell) + 0.5:
		return Color.TRANSPARENT
	return SHADOW
