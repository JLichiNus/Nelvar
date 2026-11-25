class_name CompressionVortex
extends Node2D
## Воздух R-сжатия: штрихи ветра в несколько пикселей, а не точки — одиночный
## пиксель теряется в траве. У каждой частицы хвост из её прошлых позиций:
## голова кремовая, хвост голубеет и тает.
##
## Два вида частиц:
##   * вихревые — кружат вокруг цели по спирали и втягиваются в неё
##     (координаты полярные относительно центра, центр едет за целью);
##   * прямые — линии скорости за серпами и брызги при ударе.
## Живёт рядом со сжатием, а не внутри него: после конца воздух дотаивает сам.
## Пиксели — на сетке мира размером TEXEL, как у игрока.

const TEXEL := 3.0
const RAMP: Array[Color] = [
	Color8(75, 106, 142), Color8(110, 156, 188), Color8(165, 207, 220),
	Color8(221, 238, 230), Color8(251, 248, 232),
]
## Сколько прошлых позиций (кадров) помнит хвост.
const TAIL := 9

## Центр вихря — позиция цели; сжатие ставит его каждый кадр.
var center := Vector2.ZERO
## Направление закрутки: ±1.
var swirl := 1.0

var _parts: Array[Dictionary] = []
var _stopped := false


func _ready() -> void:
	top_level = true
	global_position = Vector2.ZERO
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST


## Вихревая частица: рождается на кольце вокруг цели и уходит к ней
## по сужающейся спирали, ускоряясь.
func emit_swirl(min_radius: float, max_radius: float) -> void:
	if _stopped:
		return
	var angle := randf() * TAU
	var radius := randf_range(min_radius, max_radius)
	var life := randf_range(0.45, 0.75)
	_parts.append({
		"orbit": true,
		"angle": angle,
		"radius": radius,
		# угловая скорость, рад/с; радиус тает к ~10 за жизнь частицы
		"w": swirl * randf_range(6.0, 8.5),
		"vr": -(radius - 10.0) / life * randf_range(0.8, 1.0),
		"pos": center + Vector2.from_angle(angle) * radius,
		"vel": Vector2.ZERO,
		"age": 0.0,
		"life": life,
		"tail": [],
	})


## Прямая частица: летит из at со скоростью velocity, тормозя.
func emit_line(at: Vector2, velocity: Vector2, life: float = 0.35, drag: float = 3.0) -> void:
	if _stopped:
		return
	_parts.append({
		"orbit": false,
		"pos": at,
		"vel": velocity,
		"drag": drag,
		"age": 0.0,
		"life": life * randf_range(0.8, 1.2),
		"tail": [],
	})


## Сжатие закончилось: новых частиц нет, вихрь отпускает воздух — кружащие
## частицы срываются по касательной наружу. Узел уходит, когда всё дотает.
func release() -> void:
	_stopped = true
	for part in _parts:
		if part.orbit:
			var out := Vector2.from_angle(part.angle)
			var tangent := out.orthogonal() * -signf(part.w)
			part.orbit = false
			part.vel = tangent * absf(part.w) * part.radius * 0.6 + out * 90.0
			part.drag = 3.5
			part.life = minf(part.life, part.age + 0.3)


func _physics_process(delta: float) -> void:
	var alive: Array[Dictionary] = []
	for part in _parts:
		part.age += delta
		if part.age >= part.life:
			continue
		if part.orbit:
			part.angle += part.w * delta
			part.w *= 1.0 + 1.2 * delta          # к центру крутится быстрее
			part.radius = maxf(part.radius + part.vr * delta, 6.0)
			part.pos = center + Vector2.from_angle(part.angle) * part.radius
		else:
			part.pos += part.vel * delta
			part.vel *= exp(-delta * part.drag)
		var tail: Array = part.tail
		tail.push_front(part.pos)
		if tail.size() > TAIL:
			tail.pop_back()
		alive.append(part)
	_parts = alive
	if _stopped and _parts.is_empty():
		queue_free()
		return
	queue_redraw()


func _draw() -> void:
	var texel := Vector2(TEXEL, TEXEL)
	for part in _parts:
		var tail: Array = part.tail
		if tail.size() < 2:
			continue
		var t: float = part.age / part.life
		var alpha := smoothstep(0.0, 0.06, t) * (1.0 - smoothstep(0.7, 1.0, t))
		# пиксели вдоль хвоста: от головы к концу, без повторов
		var drawn := {}
		var total := 0.0
		for i in tail.size() - 1:
			total += (tail[i + 1] as Vector2).distance_to(tail[i])
		if total < 0.5:
			continue
		var walked := 0.0
		for i in tail.size() - 1:
			var a: Vector2 = tail[i]
			var b: Vector2 = tail[i + 1]
			var length := a.distance_to(b)
			var steps := maxi(ceili(length / TEXEL), 1)
			for k in steps:
				var at := a.lerp(b, float(k) / steps)
				var cell := (at / TEXEL).floor()
				if drawn.has(cell):
					continue
				drawn[cell] = true
				var s := (walked + length * k / steps) / total   # 0 — голова
				var tone := 4 if s < 0.25 else (3 if s < 0.6 else 2)
				var color := RAMP[tone]
				color.a = alpha * (1.0 - 0.4 * s)
				draw_rect(Rect2(cell * TEXEL, texel), color)
			walked += length
