class_name WindProjectileTrail
extends Node2D
## Шлейф частиц воздуха: они срываются с задней кромки ЛКМ-шарика (или
## с задней кромки ПКМ-волны), разлетаются в стороны, развиваются в завитки и тают.
##
## Живёт рядом со снарядом, а не внутри него: шарик пропадает при попадании,
## а уже выпущенный воздух должен спокойно дотаять. Каждая частица рисуется
## пикселями размером TEXEL на сетке мира — как у игрока и самого шарика.
## Тона — рампа неба из tools/gen_attack_sprites.py, без контура (как штрихи
## ветра у спрайтов).

const TEXEL := 3.0
const RAMP: Array[Color] = [
	Color8(75, 106, 142), Color8(110, 156, 188), Color8(165, 207, 220),
	Color8(221, 238, 230), Color8(251, 248, 232),
]

## Расстояние между частицами вдоль пути, world-единиц.
@export var spacing: float = 9.0
## Частицы рождаются за шариком, на столько позади его центра.
@export var back_offset: float = 4.5
@export var lifetime := Vector2(0.26, 0.46)
## Скорость назад, против полёта, world-единиц в секунду.
@export var drift_back := Vector2(30.0, 90.0)
## Скорость в стороны: шлейф расходится клином.
@export var drift_side := Vector2(20.0, 60.0)
## Наибольший радиус завитка, в пикселях (TEXEL).
@export var curl_radius: float = 2.8

var _puffs: Array[Dictionary] = []
var _emitting := true
var _has_last := false
var _last_position := Vector2.ZERO
var _carry := 0.0
var _side := 1.0


func _ready() -> void:
	# Позиции частиц — мировые, узел стоит в начале координат.
	top_level = true
	global_position = Vector2.ZERO
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Шарик сообщает, где его центр и куда он летит, каждый физический кадр.
func follow(center: Vector2, direction: Vector2) -> void:
	if not _emitting:
		return
	var origin := center - direction * back_offset
	if not _has_last:
		_has_last = true
		_last_position = origin
		_spawn(origin, direction)
		return
	var path := origin - _last_position
	var length := path.length()
	var travelled := _carry
	while travelled + spacing <= length:
		travelled += spacing
		_spawn(_last_position + path * (travelled / length), direction)
	_carry = travelled - length
	_last_position = origin


## Шарик исчез: новых частиц нет, остальные дотаивают, потом узел уходит.
## burst > 0 — частицы, разлетающиеся во все стороны (удар о цель).
func release(at: Vector2, direction: Vector2, burst: int) -> void:
	_emitting = false
	for i in burst:
		var angle := TAU * (i + randf() * 0.6) / burst
		var out := Vector2.from_angle(angle)
		_puffs.append(_make_puff(at, out * randf_range(60.0, 120.0) - direction * 30.0, out))
	if _puffs.is_empty():
		queue_free()


## Одна частица вручную: так ПКМ-волна срывает воздух с разных точек дуги.
## heading — куда летел источник (штрих молодой частицы тянется вдоль него).
func emit_puff(at: Vector2, velocity: Vector2, heading: Vector2) -> void:
	if _emitting:
		_puffs.append(_make_puff(at, velocity, heading))


func _spawn(at: Vector2, direction: Vector2) -> void:
	# Стороны чередуются — клин симметричный; разброс делает его рваным.
	_side = -_side
	var normal := direction.orthogonal() * _side
	var velocity := (
		-direction * randf_range(drift_back.x, drift_back.y)
		+ normal * randf_range(drift_side.x, drift_side.y)
	)
	_puffs.append(_make_puff(at + normal * randf_range(0.0, 3.0), velocity, direction))


func _make_puff(at: Vector2, velocity: Vector2, heading: Vector2) -> Dictionary:
	return {
		"pos": at,
		"vel": velocity,
		"heading": heading,
		"age": 0.0,
		"life": randf_range(lifetime.x, lifetime.y),
		"spin": randf_range(0.0, TAU),
		# направление закрутки — по стороне, с которой частица сорвалась
		"turn": signf(velocity.cross(Vector2.RIGHT) + 0.001) * randf_range(5.0, 9.0),
	}


func _process(delta: float) -> void:
	var damping := exp(-delta * 4.0)
	var alive: Array[Dictionary] = []
	for puff in _puffs:
		puff.age += delta
		if puff.age >= puff.life:
			continue
		puff.pos += puff.vel * delta
		puff.vel *= damping
		puff.spin += puff.turn * delta
		alive.append(puff)
	_puffs = alive
	if _puffs.is_empty() and not _emitting:
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var texel := Vector2(TEXEL, TEXEL)
	for puff in _puffs:
		var t: float = puff.age / puff.life
		# Тон холодеет с возрастом: кремовый у шарика, голубой к хвосту.
		# Самый тёмный тон рампы не берём — на траве он читается грязью.
		var tone := 4 if t < 0.3 else (3 if t < 0.6 else (2 if t < 0.85 else 1))
		var color := RAMP[tone]
		color.a = 1.0 - smoothstep(0.6, 1.0, t)
		if t < 0.15:
			# Только что сорвалась с шарика: штрих вдоль полёта —
			# вблизи шарика шлейф плотная струя, а не россыпь.
			var heading: Vector2 = puff.heading
			for i in 2:
				var at: Vector2 = puff.pos - heading * TEXEL * i
				draw_rect(Rect2(_snap(at), texel), color)
			continue
		# Дальше завиток развивается: дуга из соседних пикселей, её радиус
		# растёт, а сама она вращается; под конец рвётся на редкие точки.
		var grow := 1.0 - (1.0 - t) * (1.0 - t)
		var radius := lerpf(0.8, curl_radius, grow)
		var count := 2 if t < 0.35 else 3
		var step := 1.15 / radius * (1.0 if t < 0.8 else 2.0)
		for i in count:
			var angle: float = puff.spin + step * (i - (count - 1) * 0.5)
			var at: Vector2 = puff.pos + Vector2.from_angle(angle) * radius * TEXEL
			draw_rect(Rect2(_snap(at), texel), color)


func _snap(at: Vector2) -> Vector2:
	return (at / TEXEL).floor() * TEXEL
