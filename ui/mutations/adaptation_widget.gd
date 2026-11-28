extends Control
## Shows adaptation, the owner queue and the time to interception.

const ART_PIXEL := 3.0
## 3x the 11 px bitmap font, so a font pixel matches an art pixel.
const FONT_SIZE := 33
const EDGE := Color(0.05, 0.06, 0.08, 0.88)
const BACK := Color(0.05, 0.06, 0.08, 0.72)
const URGENT := Color(1.0, 0.49, 0.48)
const URGENT_TIME := 10.0

var _director: NelvarMutationDirector
var _owners: Array[int] = []
var _progress := 0.0
var _pulse := 0.0


func bind(director: NelvarMutationDirector) -> void:
	_director = director
	director.adaptation_changed.connect(_update_adaptation)
	director.queue_changed.connect(_update_queue)
	director.pending_changed.connect(_update_pending)
	_update_adaptation(director.adaptation, director.threshold)
	_update_queue()
	_update_pending(director.has_pending())


func _update_adaptation(value: float, threshold: float) -> void:
	_progress = clampf(value / threshold, 0.0, 1.0) if threshold > 0.0 else 0.0
	queue_redraw()


func _update_queue() -> void:
	_owners = _director.upcoming_owners()
	queue_redraw()


func _update_pending(pending: bool) -> void:
	_pulse = 0.0
	set_process(pending)
	queue_redraw()


func _process(delta: float) -> void:
	var period := 0.55 if _director.pending_time_left() <= URGENT_TIME else 1.35
	_pulse = fposmod(_pulse + delta * TAU / period, TAU)
	queue_redraw()


func _draw() -> void:
	if not is_instance_valid(_director):
		return

	var own := _director.player_version
	var pending := _director.has_pending()
	var time_left := _director.pending_time_left()
	var urgent := pending and time_left <= URGENT_TIME
	var accent := NelvarMutation.version_color(own)
	if urgent:
		accent = URGENT

	var meter := Rect2(0.0, 63.0, snappedf(size.x, ART_PIXEL), 15.0)
	_draw_bar(meter, _progress, NelvarMutation.version_color(own))

	var owners := _owners.duplicate()
	# The director has already popped the waiting turn from upcoming_owners().
	if pending:
		owners.push_front(own)

	var title := "E — мутация" if pending else "Адаптация"
	# Sigils stop one art pixel short of the title's dark outline.
	var sigil_limit := _text_x(title) - ART_PIXEL * 2.0
	var x := 18.0
	for i in mini(owners.size(), 5):
		# Outer edge of the sigil frame: half size, the extra pixel, the dark edge.
		var reach := ((3.0 if i == 0 else 2.0) + 3.0) * ART_PIXEL
		if i > 0 and x + reach > sigil_limit:
			break
		var color := NelvarMutation.version_color(owners[i])
		if pending and i == 0:
			color = accent.lerp(EDGE, (1.0 - cos(_pulse)) * 0.24)
		_draw_sigil(Vector2(x, 33.0), owners[i], color, i == 0)
		x += 33.0 if i == 0 else 30.0

	if pending:
		var ratio := time_left / maxf(_director.pending_duration, 0.001)
		_draw_bar(Rect2(0.0, 51.0, 36.0, 9.0), ratio, accent)
		_draw_text(title, 42.0, accent)
		if urgent:
			_draw_text("перехватят через %d с" % ceili(time_left), 9.0, URGENT)
	else:
		_draw_text(title, 42.0, Color.WHITE)


func _draw_bar(rect: Rect2, ratio: float, fill: Color) -> void:
	draw_rect(rect.grow(ART_PIXEL), EDGE)
	draw_rect(rect.grow(-ART_PIXEL / 2.0), Color.WHITE, false, ART_PIXEL)
	var inner := rect.grow(-ART_PIXEL)
	draw_rect(inner, BACK)
	var width := snappedf(inner.size.x * clampf(ratio, 0.0, 1.0), ART_PIXEL)
	if width > 0.0:
		draw_rect(Rect2(inner.position, Vector2(width, inner.size.y)), fill)


func _draw_sigil(center: Vector2, owner: int, color: Color, first: bool) -> void:
	var radius := 3 if first else 2
	var half_size := (radius + 1) * ART_PIXEL
	var frame := Rect2(center - Vector2.ONE * half_size, Vector2.ONE * (half_size * 2.0 + ART_PIXEL))
	draw_rect(frame.grow(ART_PIXEL), EDGE)
	if owner == _director.player_version:
		draw_rect(frame.grow(-ART_PIXEL / 2.0), Color.WHITE, false, ART_PIXEL)
	for y in range(-radius, radius + 1):
		var span := radius - absi(y)
		for x in range(-span, span + 1):
			if owner != NelvarMutation.SPONTANEOUS or absi(x) == span:
				var pos := center + Vector2(x, y) * ART_PIXEL
				draw_rect(Rect2(pos, Vector2.ONE * ART_PIXEL), color)


func _draw_text(value: String, baseline: float, color: Color) -> void:
	var font := get_theme_font("font", "Label")
	var origin := Vector2(_text_x(value), baseline)
	for offset in [Vector2.LEFT, Vector2.RIGHT, Vector2.UP, Vector2.DOWN]:
		draw_string(font, origin + offset * ART_PIXEL, value, HORIZONTAL_ALIGNMENT_LEFT,
			-1.0, FONT_SIZE, EDGE)
	draw_string(font, origin, value, HORIZONTAL_ALIGNMENT_LEFT, -1.0, FONT_SIZE, color)


## Left edge of a right-aligned line; a line wider than the widget starts at
## its left edge instead.
func _text_x(value: String) -> float:
	var font := get_theme_font("font", "Label")
	var width := font.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SIZE).x
	return maxf(snappedf(size.x - width, ART_PIXEL), 0.0)
