class_name NelvarOcclusionOutline
extends CanvasGroup
## Контур персонажа там, где его закрывает препятствие (например, крона дерева).
##
## Узел кладётся внутрь персонажа. Поверх всех слоёв он рисует копию спрайтов
## из sources, а шейдер оставляет от неё только контур с лёгкой заливкой — и лишь
## на пикселях препятствий, которые стоят перед персонажем по Y-сортировке
## (их основание ниже, чем у родителя). Препятствия сообщают о себе через
## add_occluder()/remove_occluder(). Поддерживаются Sprite2D без region/hframes
## и AnimatedSprite2D.

const MAX_OCCLUDERS := 6
const GRID_CELL := 256.0
const OUTLINE_SHADER := preload("res://scripts/fx/occlusion_outline.gdshader")


class Occluder:
	var node: Node2D
	var texture: Texture2D
	## Прямоугольник текстуры в мировых координатах.
	var rect: Rect2


# Препятствия неподвижны, поэтому раскладываются по клеткам мира один раз.
static var _grid := {}
static var _occluders := {}

@export var sources: Array[Node2D] = []
@export var outline_color := Color(1.0, 1.0, 1.0, 0.9)
@export var fill_color := Color(1.0, 1.0, 1.0, 0.12)
## Толщина контура в мировых пикселях.
@export var outline_width: float = 3.0

var _silhouette: Node2D
var _shader_material: ShaderMaterial
var _texture_params: Array[StringName] = []
var _rect_params: Array[StringName] = []


static func add_occluder(node: Node2D, texture: Texture2D, rect: Rect2) -> void:
	remove_occluder(node)
	var occluder := Occluder.new()
	occluder.node = node
	occluder.texture = texture
	occluder.rect = rect
	_occluders[node] = occluder
	for cell in _cells(rect):
		if not _grid.has(cell):
			_grid[cell] = []
		_grid[cell].append(occluder)


static func remove_occluder(node: Node2D) -> void:
	var occluder: Occluder = _occluders.get(node)
	if occluder == null:
		return
	_occluders.erase(node)
	for cell in _cells(occluder.rect):
		var list: Array = _grid.get(cell, [])
		list.erase(occluder)
		if list.is_empty():
			_grid.erase(cell)


static func _cells(rect: Rect2) -> Array[Vector2i]:
	var from := Vector2i((rect.position / GRID_CELL).floor())
	var to := Vector2i((rect.end / GRID_CELL).floor())
	var cells: Array[Vector2i] = []
	for y in range(from.y, to.y + 1):
		for x in range(from.x, to.x + 1):
			cells.append(Vector2i(x, y))
	return cells


func _ready() -> void:
	# Над деревьями и остальными актёрами, но в том же мировом пространстве.
	z_as_relative = false
	z_index = RenderingServer.CANVAS_ITEM_Z_MAX
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	fit_margin = outline_width * 2.0 + 2.0
	clear_margin = fit_margin
	_shader_material = ShaderMaterial.new()
	_shader_material.shader = OUTLINE_SHADER
	_shader_material.set_shader_parameter("outline_color", outline_color)
	_shader_material.set_shader_parameter("fill_color", fill_color)
	_shader_material.set_shader_parameter("outline_width", outline_width)
	material = _shader_material
	for i in MAX_OCCLUDERS:
		_texture_params.append(StringName("occluder_texture_%d" % i))
		_rect_params.append(StringName("occluder_rect_%d" % i))
	_silhouette = Node2D.new()
	_silhouette.name = "Silhouette"
	_silhouette.draw.connect(_draw_silhouette)
	add_child(_silhouette)
	visible = false


func _process(_delta: float) -> void:
	var occluders := _find_occluders()
	# Пустая группа всё равно стоила бы отдельного буфера — прячем её целиком.
	visible = not occluders.is_empty()
	if not visible:
		return
	_shader_material.set_shader_parameter("occluder_count", occluders.size())
	for i in occluders.size():
		var occluder := occluders[i]
		_shader_material.set_shader_parameter(_texture_params[i], occluder.texture)
		_shader_material.set_shader_parameter(_rect_params[i], Vector4(
			occluder.rect.position.x, occluder.rect.position.y,
			occluder.rect.size.x, occluder.rect.size.y))
	_silhouette.queue_redraw()


func _find_occluders() -> Array[Occluder]:
	var found: Array[Occluder] = []
	var bounds := _sources_rect()
	var owner_node := get_parent() as Node2D
	if not bounds.has_area() or owner_node == null:
		return found
	var depth := owner_node.global_position.y
	var seen := {}
	for cell in _cells(bounds):
		for occluder: Occluder in _grid.get(cell, []):
			if seen.has(occluder):
				continue
			seen[occluder] = true
			if occluder.node.global_position.y > depth and occluder.rect.intersects(bounds):
				found.append(occluder)
	if found.size() > MAX_OCCLUDERS:
		# Важнее всего те, что закрывают большую часть персонажа.
		found.sort_custom(func(a: Occluder, b: Occluder) -> bool:
			return _area(a.rect.intersection(bounds)) > _area(b.rect.intersection(bounds)))
		found.resize(MAX_OCCLUDERS)
	return found


func _sources_rect() -> Rect2:
	var bounds := Rect2()
	var first := true
	for source in sources:
		if not is_instance_valid(source) or not source.is_visible_in_tree():
			continue
		var texture := _source_texture(source)
		if texture == null:
			continue
		var rect := source.get_global_transform() * _source_rect(source, texture, false)
		bounds = rect if first else bounds.merge(rect)
		first = false
	return bounds


func _draw_silhouette() -> void:
	var to_local := _silhouette.get_global_transform().affine_inverse()
	for source in sources:
		if not is_instance_valid(source) or not source.is_visible_in_tree():
			continue
		var texture := _source_texture(source)
		if texture == null:
			continue
		_silhouette.draw_set_transform_matrix(to_local * source.get_global_transform())
		_silhouette.draw_texture_rect(texture, _source_rect(source, texture, true), false)
	_silhouette.draw_set_transform_matrix(Transform2D.IDENTITY)


static func _source_texture(source: Node2D) -> Texture2D:
	if source is AnimatedSprite2D:
		var sprite := source as AnimatedSprite2D
		if sprite.sprite_frames == null or not sprite.sprite_frames.has_animation(sprite.animation):
			return null
		return sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	if source is Sprite2D:
		return (source as Sprite2D).texture
	return null


# Как у Sprite2D: отрицательный размер прямоугольника отражает текстуру на месте.
static func _source_rect(source: Node2D, texture: Texture2D, with_flip: bool) -> Rect2:
	var size := texture.get_size()
	var offset: Vector2 = source.get("offset")
	if source.get("centered"):
		offset -= size / 2.0
	if with_flip and source.get("flip_h"):
		size.x = -size.x
	if with_flip and source.get("flip_v"):
		size.y = -size.y
	return Rect2(offset, size)


static func _area(rect: Rect2) -> float:
	return rect.size.x * rect.size.y
