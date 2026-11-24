class_name NelvarStats
extends RefCounted
## Characteristics of a creature that mutations change.
##
## A stat is its base value (the player's exports) plus flat additions, times
## 1 + the sum of percent changes: (base + flat) * (1 + percent / 100). Each
## source (one mutation) keeps its own modifiers, so replacing a mutation's
## stage replaces its modifiers instead of stacking them again.
##
## A modifier is a Dictionary: {"stat": &"move_speed", "percent": 20.0} or
## {"stat": &"regen", "flat": 1.0}.

signal changed

## Every stat a mutation may touch.
## - label: the name shown in descriptions; empty = described by the
##   mutation's own text (conditional and on/off stats).
## - good: +1 when more is better for the player, -1 when less is.
## - base: value when the owner sets none (conditional stats start at 0).
## - flat_unit: suffix after a flat change in descriptions.
## - weigh: what a flat change counts as when a version weighs a mutation,
##   in percent per unit (for stats whose base is 0).
const INFO := {
	&"move_speed": {"label": "Скорость", "good": 1},
	&"acceleration": {"label": "Разгон", "good": 1},
	&"max_health": {"label": "Макс. здоровье", "good": 1},
	&"damage": {"label": "Урон", "good": 1, "base": 1.0},
	&"damage_taken": {"label": "Получаемый урон", "good": -1, "base": 1.0},
	&"invulnerability": {"label": "Неуязвимость после удара", "good": 1},
	&"regen": {"label": "Восстановление", "good": 1, "flat_unit": " ОЗ/с", "weigh": 25.0},
	&"kill_heal": {"label": "Лечение за убийство", "good": 1, "flat_unit": " ОЗ", "weigh": 8.0},
	&"adaptation_gain": {"label": "Скорость адаптации", "good": 1, "base": 1.0},

	&"primary_cooldown": {"label": "Пауза между снарядами", "good": -1},
	&"primary_spread": {"label": "Разброс снарядов", "good": -1},
	&"primary_damage": {"label": "Урон снарядов", "good": 1, "base": 1.0},
	&"primary_projectiles": {"label": "Снарядов за выстрел", "good": 1, "base": 1.0, "flat_unit": "", "weigh": 40.0},
	&"projectile_speed": {"label": "Скорость снарядов", "good": 1, "base": 1.0},
	&"projectile_pierce": {"label": "Снаряд пробивает врагов", "good": 1, "flat_unit": "", "weigh": 35.0},

	&"wave_cooldown": {"label": "Перезарядка волны", "good": -1},
	&"wave_damage": {"label": "Урон волны", "good": 1, "base": 1.0},
	&"wave_range": {"label": "Дальность волны", "good": 1, "base": 1.0},
	&"wave_size": {"label": "Размер волны", "good": 1, "base": 1.0},

	&"compression_cooldown": {"label": "Перезарядка сжатия", "good": -1},
	&"compression_damage": {"label": "Урон сжатия", "good": 1, "base": 1.0},
	&"compression_range": {"label": "Дальность сжатия", "good": 1, "base": 1.0},

	&"flight_duration": {"label": "Длительность полёта", "good": 1},
	&"flight_cooldown": {"label": "Перезарядка полёта", "good": -1},
	&"flight_speed": {"label": "Ускорение в полёте", "good": 1},

	# Conditional and on/off stats: the mutation's own text describes them.
	&"flight_unprotected": {"label": "", "good": -1, "weigh": 60.0},
	&"still_armor": {"label": "", "good": 1, "weigh": 0.6},
	&"moving_vulnerability": {"label": "", "good": -1, "weigh": 1.0},
	&"air_damage": {"label": "", "good": 1, "weigh": 0.6},
	&"ground_damage": {"label": "", "good": 1, "weigh": 1.0},
	&"low_health_damage": {"label": "", "good": 1, "weigh": 0.4},
	&"low_health_speed": {"label": "", "good": 1, "weigh": 0.4},
}
## No stat falls below this share of its base, however many penalties stack.
const MIN_FACTOR := 0.15

var _base := {}
## source id -> Array[Dictionary] of modifiers.
var _sources := {}
var _flat := {}
var _percent := {}


func set_base(stat: StringName, value: float) -> void:
	_base[stat] = value
	changed.emit()


func base(stat: StringName) -> float:
	if _base.has(stat):
		return _base[stat]
	return float(INFO.get(stat, {}).get("base", 0.0))


func value(stat: StringName) -> float:
	var raw := base(stat) + float(_flat.get(stat, 0.0))
	var factor := maxf(1.0 + float(_percent.get(stat, 0.0)) / 100.0, MIN_FACTOR)
	return raw * factor


## For on/off stats: any positive value turns it on.
func flag(stat: StringName) -> bool:
	return value(stat) > 0.5


## Replaces everything `source` changes. An empty list removes the source.
func set_source(source: StringName, modifiers: Array) -> void:
	if modifiers.is_empty():
		_sources.erase(source)
	else:
		_sources[source] = modifiers.duplicate(true)
	_recount()
	changed.emit()


func sources() -> Array:
	return _sources.keys()


func _recount() -> void:
	_flat.clear()
	_percent.clear()
	for modifiers in _sources.values():
		for modifier: Dictionary in modifiers:
			var stat: StringName = modifier["stat"]
			if not INFO.has(stat):
				push_warning("Неизвестная характеристика мутации: %s." % stat)
			_flat[stat] = float(_flat.get(stat, 0.0)) + float(modifier.get("flat", 0.0))
			_percent[stat] = float(_percent.get(stat, 0.0)) + float(modifier.get("percent", 0.0))


## How a modifier reads in a description: "Скорость +20%". Empty for stats
## without a label.
static func describe_modifier(modifier: Dictionary) -> String:
	var info: Dictionary = INFO.get(modifier["stat"], {})
	var label: String = info.get("label", "")
	if label.is_empty():
		return ""
	if modifier.has("percent"):
		return "%s %s%%" % [label, _signed(modifier["percent"])]
	return "%s %s%s" % [label, _signed(modifier.get("flat", 0.0)), info.get("flat_unit", "")]


## +1 when the modifier helps the player, -1 when it hurts, 0 when neutral.
static func goodness(modifier: Dictionary) -> int:
	var info: Dictionary = INFO.get(modifier["stat"], {})
	var amount := float(modifier.get("percent", modifier.get("flat", 0.0)))
	return int(signf(amount)) * int(info.get("good", 1))


## Size of the change in percent, for weighing: percents as they are, flat
## changes through the stat's `weigh` (or relative to its default base).
static func magnitude(modifier: Dictionary) -> float:
	if modifier.has("percent"):
		return absf(modifier["percent"])
	var info: Dictionary = INFO.get(modifier["stat"], {})
	var flat := absf(modifier.get("flat", 0.0))
	if info.has("weigh"):
		return flat * float(info["weigh"])
	var stat_base := float(info.get("base", 0.0))
	return flat / stat_base * 100.0 if stat_base != 0.0 else flat


static func _signed(amount: float) -> String:
	var text := ("%.1f" % absf(amount)).trim_suffix(".0")
	return ("+" if amount > 0.0 else "-") + text
