class_name NelvarSnowMarks
extends Node
## Marks left in the snow, drifted over with time. The player is a whirlwind without
## feet: it leaves a swept furrow, the snow pushed aside and swirled; a hopper leaves a
## round dent where it lands, snow thrown round it.
##
## The marks live in a texture the size of the floor's map, one pixel per art pixel,
## drawn by a viewport that is never cleared and only renders when there are new marks.
## Each pixel keeps the snow clock when it was stamped (R and G, 16 bits, the clock ×2)
## and its kind and depth (B); the floor shader works out the age from the clock and
## fades the mark. The clock runs faster in a blizzard, so a blizzard drifts the marks
## over faster without anything being redrawn.

const STEP := NelvarIceData.PIXEL
## World units of the player's way between two stamps.
const PLAYER_SPACING := 6.0
## Kinds (B = kind × 16 + depth 0..15): dug furrow, snow piled beside it, a hopper's
## dent, snow thrown out of it.
const FURROW := 1
const BANK := 2
const DENT := 3
const SPRAY := 4
## Snow-clock seconds a dug pixel keeps the piled snow of later stamps off it.
const KEEP_DUG := 20.0

## Stamps made so far, and the last ones (world points), for the tests.
var stamps := 0
var recent := PackedVector2Array()

var _data: NelvarIceData
var _origin := Vector2i.ZERO
var _size := Vector2i.ZERO
var _viewport: SubViewport
var _canvas: Node2D
## Pixels to draw this frame: [pixel, colour].
var _pending: Array = []
## Per pixel: the kind last stamped and the snow clock then (to keep furrows clean).
var _kinds := PackedByteArray()
var _times := PackedFloat32Array()
var _clock := 0.0
var _last_player := Vector2.INF
var _travel := 0.0
var _swirl := 0.0


## `origin` and `size`: the floor map's, art pixels (NelvarIceField).
func setup(data: NelvarIceData, origin: Vector2i, size: Vector2i) -> void:
	_data = data
	_origin = origin
	_size = size
	_kinds.resize(size.x * size.y)
	_times.resize(size.x * size.y)
	_viewport = SubViewport.new()
	_viewport.name = "MarkPixels"
	_viewport.disable_3d = true
	_viewport.transparent_bg = true
	_viewport.size = size
	_viewport.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	add_child(_viewport)
	_canvas = Node2D.new()
	_canvas.name = "Stamps"
	_canvas.draw.connect(_draw_pending)
	_viewport.add_child(_canvas)


func texture() -> Texture2D:
	return _viewport.get_texture() if _viewport != null else null


## The snow clock (NelvarIceMain advances it).
func set_clock(clock: float) -> void:
	_clock = clock


## The player's way over the snow: a stamp every PLAYER_SPACING. `lifted`: in the air
## or falling, no marks.
func track_player(point: Vector2, lifted: bool) -> void:
	if lifted or not _last_player.is_finite():
		_last_player = point if not lifted else Vector2.INF
		_travel = 0.0
		return
	var step := point - _last_player
	var distance := step.length()
	if distance > 200.0:
		# Thrown back after a fall: start afresh.
		_last_player = point
		return
	_travel += distance
	while _travel >= PLAYER_SPACING:
		_travel -= PLAYER_SPACING
		var at := point - step.normalized() * _travel
		_swirl += 0.9
		stamp_furrow(at, _swirl)
	_last_player = point


## The whirlwind's furrow: swept out in the middle, the snow piled on two swirling arms.
func stamp_furrow(point: Vector2, swirl: float) -> void:
	if not _on_snow(point):
		return
	var center := Vector2i((point / STEP).floor())
	for dy in range(-3, 4):
		for dx in range(-3, 4):
			var r := Vector2(dx, dy).length()
			if r <= 1.0:
				_put(center + Vector2i(dx, dy), FURROW, 10 if r < 0.5 else 7)
			elif r >= 1.9 and r <= 3.0 and sin(atan2(float(dy), float(dx)) * 2.0 + swirl) > 0.3:
				_put(center + Vector2i(dx, dy), BANK, 10)
	_count(point)


## A hopper's landing: a round dent, a ring of snow and a little thrown about.
func stamp_dent(point: Vector2) -> void:
	if not _on_snow(point):
		return
	var center := Vector2i((point / STEP).floor())
	var salt := int(point.x * 13.0 + point.y * 7.0)
	for dy in range(-6, 7):
		for dx in range(-6, 7):
			var r := Vector2(dx, dy * 1.4).length()
			if r <= 2.4:
				_put(center + Vector2i(dx, dy), DENT, 13 if r < 1.5 else 9)
			elif r <= 3.6:
				_put(center + Vector2i(dx, dy), BANK, 8)
			elif r <= 6.0 and NelvarPixelArt.hash01(center.x + dx, center.y + dy, salt) < 0.12:
				_put(center + Vector2i(dx, dy), SPRAY, 7)
	_count(point)


## Marks younger than `age` snow-clock seconds within `radius` of the point (tests).
func fresh_near(point: Vector2, radius: float, age: float = 30.0) -> int:
	var found := 0
	var center := Vector2i((point / STEP).floor()) - _origin
	var reach := ceili(radius / STEP)
	for dy in range(-reach, reach + 1):
		for dx in range(-reach, reach + 1):
			var p := center + Vector2i(dx, dy)
			if p.x < 0 or p.y < 0 or p.x >= _size.x or p.y >= _size.y:
				continue
			var index := p.y * _size.x + p.x
			if _kinds[index] != 0 and _clock - _times[index] < age:
				found += 1
	return found


func _on_snow(point: Vector2) -> bool:
	return _data != null and _data.lake_depth(point) < -4.0 and _data.crevasse_sample(point).x < -6.0 \
		and _data.valley.signed_distance(point) > 0.0


func _count(point: Vector2) -> void:
	stamps += 1
	recent.append(point)
	if recent.size() > 64:
		recent.remove_at(0)


func _put(pixel: Vector2i, kind: int, depth: int) -> void:
	var p := pixel - _origin
	if p.x < 0 or p.y < 0 or p.x >= _size.x or p.y >= _size.y:
		return
	var index := p.y * _size.x + p.x
	# Piled snow never fills a freshly swept or dented pixel.
	if (kind == BANK or kind == SPRAY) and (_kinds[index] == FURROW or _kinds[index] == DENT) \
			and _clock - _times[index] < KEEP_DUG:
		return
	_kinds[index] = kind
	_times[index] = _clock
	var stamp := int(floor(_clock * 2.0)) % 65536
	_pending.append([p, Color8(stamp >> 8, stamp & 255, kind * 16 + depth, 255)])


func _process(_delta: float) -> void:
	if _pending.is_empty() or _viewport == null:
		return
	_canvas.queue_redraw()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE


func _draw_pending() -> void:
	for entry: Array in _pending:
		var p: Vector2i = entry[0]
		_canvas.draw_rect(Rect2(Vector2(p), Vector2.ONE), entry[1])
	_pending.clear()
