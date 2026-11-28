extends HBoxContainer
## Received mutations along the top of the screen, in the order they came.
## Hovering a tile shows its short summary at once, right under it; the full
## description is in the pause menu's inventory.
##
## The hint is drawn here, inside the HUD, rather than as Godot's tooltip: a
## tooltip waits before it appears and lives in its own popup window, where
## the pixel font is filtered smoothly and looks blurry.

const GAP := 9
## Space between a tile and its hint, and the hint's distance from screen edges.
const HINT_OFFSET := 9.0
## A tile that just got its mutation (or a new stage) pops and glows this long.
const HIGHLIGHT_TIME := 0.9

var _director: NelvarMutationDirector
var _hint: PanelContainer
var _hovered: NelvarMutationIcon


func bind(director: NelvarMutationDirector) -> void:
	_director = director
	add_theme_constant_override("separation", GAP)
	alignment = BoxContainer.ALIGNMENT_CENTER
	_hint = PanelContainer.new()
	# Out of the row's layout, but still inheriting its theme. A top-level item
	# does not inherit the row's texture filter, so the nearest filter that
	# keeps the pixel font sharp is set on it directly.
	_hint.top_level = true
	_hint.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hint.visible = false
	_hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_theme_stylebox_override("panel", get_theme_stylebox("panel", "TooltipPanel"))
	add_child(_hint)
	director.mutation_applied.connect(func(mutation: NelvarMutation, _s, _o, _i) -> void:
		_rebuild()
		_highlight(mutation.id))
	_rebuild()


func hint_visible() -> bool:
	return _hint != null and _hint.visible


func _rebuild() -> void:
	_hide_hint(_hovered)
	for child in get_children():
		if child == _hint:
			continue
		remove_child(child)
		child.queue_free()
	for entry in _director.owned():
		var icon := NelvarMutationIcon.new()
		icon.setup(entry["mutation"], entry["stage"], entry["owners"])
		icon.mouse_entered.connect(_show_hint.bind(icon))
		icon.mouse_exited.connect(_hide_hint.bind(icon))
		add_child(icon)
	# The hint stays drawn above the tiles.
	move_child(_hint, -1)


func _highlight(id: StringName) -> void:
	for child in get_children():
		var icon := child as NelvarMutationIcon
		if icon == null or icon.mutation == null or icon.mutation.id != id:
			continue
		# Its place in the row is set on the next sort, so the pivot follows it.
		icon.pivot_offset = icon.custom_minimum_size / 2.0
		icon.scale = Vector2.ONE * 1.6
		icon.modulate = Color(2.2, 2.2, 2.2)
		var tween := icon.create_tween().set_parallel()
		tween.tween_property(icon, "scale", Vector2.ONE, HIGHLIGHT_TIME * 0.5) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		tween.tween_property(icon, "modulate", Color.WHITE, HIGHLIGHT_TIME) \
			.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)


func _show_hint(icon: NelvarMutationIcon) -> void:
	for child in _hint.get_children():
		_hint.remove_child(child)
		child.queue_free()
	var content := icon.build_hint()
	if content == null:
		return
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint.add_child(content)
	_hint.reset_size()
	_hovered = icon
	# Under the tile, centred on it, kept inside the screen.
	var tile := icon.get_global_rect()
	var hint_size := _hint.get_combined_minimum_size()
	var screen := get_viewport_rect().size
	var x := clampf(tile.get_center().x - hint_size.x / 2.0, HINT_OFFSET,
		maxf(screen.x - hint_size.x - HINT_OFFSET, HINT_OFFSET))
	_hint.position = Vector2(x, tile.end.y + HINT_OFFSET).round()
	_hint.show()


func _hide_hint(icon: NelvarMutationIcon) -> void:
	if _hint == null or icon != _hovered:
		return
	_hovered = null
	_hint.hide()
