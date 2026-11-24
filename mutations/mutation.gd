class_name NelvarMutation
extends Resource
## One mutation: always a gain and a cost at the same time (VISION §3).
##
## A mutation can be taken again up to max_stage times: every next stage
## deepens it, multiplying both its gains and its costs (stage II doubles
## them). Rule-changing mutations usually have a single stage.

## The four linked versions of a Wanderer (LORE §4). Who picked a mutation is
## one of them or SPONTANEOUS.
enum Version { AIR, EARTH, FIRE, ICE }
## How deep the mutation reaches: plain trade of stats, a change of how an
## ability works, or a change of the rules the player is used to.
enum Layer { STATS, ABILITY, RULE }

const SPONTANEOUS := -1
const VERSION_NAMES := ["Воздух", "Земля", "Огонь", "Лёд"]
## Accents of the elements from the main menu (ui/main_menu/elements/*.tres).
const VERSION_COLORS := [
	Color(0.64, 0.9, 1.0),
	Color(0.79, 0.88, 0.5),
	Color(1.0, 0.62, 0.3),
	Color(0.93, 0.95, 0.97),
]
const SPONTANEOUS_NAME := "Спонтанная"
const SPONTANEOUS_COLOR := Color(0.78, 0.66, 1.0)
const LAYER_NAMES := ["Тело", "Способность", "Правило"]
const STAGE_NAMES := ["I", "II", "III", "IV"]
## How much each version values every stat when it picks a mutation for all
## four of them (LORE §4.3). Air — the player's version (the wind elemental) —
## wants speed and flight, Earth wants to endure, Fire wants to hit hard, Ice
## wants control and short cooldowns. Unlisted stats count DEFAULT_WEIGHT.
const VERSION_WEIGHTS := [
	{  # Air
		&"move_speed": 1.4, &"acceleration": 1.0, &"flight_duration": 1.2,
		&"flight_cooldown": 1.2, &"flight_speed": 1.2, &"flight_unprotected": 0.6,
		&"primary_cooldown": 0.8, &"projectile_speed": 0.8, &"air_damage": 1.2,
		&"max_health": 0.4, &"damage_taken": 0.4, &"still_armor": 0.1,
		&"moving_vulnerability": 0.2,
	},
	{  # Earth
		&"max_health": 1.5, &"damage_taken": 1.5, &"still_armor": 1.4, &"regen": 1.2,
		&"invulnerability": 1.0, &"kill_heal": 0.8, &"move_speed": 0.1,
		&"acceleration": 0.1, &"flight_duration": 0.1, &"flight_cooldown": 0.1,
		&"flight_speed": 0.1, &"moving_vulnerability": 0.2, &"flight_unprotected": 0.1,
	},
	{  # Fire
		&"damage": 1.6, &"primary_damage": 1.3, &"wave_damage": 1.3,
		&"compression_damage": 1.3, &"primary_cooldown": 1.0, &"primary_projectiles": 1.2,
		&"low_health_damage": 1.4, &"kill_heal": 1.0, &"air_damage": 0.8,
		&"ground_damage": 0.8, &"max_health": 0.2, &"damage_taken": 0.2,
		&"invulnerability": 0.2,
	},
	{  # Ice
		&"wave_cooldown": 1.4, &"compression_cooldown": 1.4, &"flight_cooldown": 0.8,
		&"compression_range": 1.2, &"wave_size": 1.1, &"wave_range": 1.0,
		&"invulnerability": 1.0, &"projectile_pierce": 1.0, &"primary_spread": 0.8,
		&"damage": 0.4, &"low_health_damage": 0.2, &"low_health_speed": 0.2,
	},
]
const DEFAULT_WEIGHT := 0.35

@export var id: StringName
@export var title: String
@export var layer: Layer = Layer.STATS
@export_range(1, 4) var max_stage: int = 2
## Modifiers at stage I (see NelvarStats). Stage N multiplies every value by N,
## except modifiers marked "fixed": true (on/off stats).
@export var modifiers: Array[Dictionary] = []
## Extra lines for what the stats cannot say themselves, at stage I. "{x}" in
## a line becomes "x" times the stage, so "{30}%" reads "30%" at I, "60%" at II.
@export var gain_lines: PackedStringArray = []
@export var cost_lines: PackedStringArray = []
## Relative chance to be offered or to appear spontaneously.
@export var weight: float = 1.0
## One short sentence: the gain and the cost in plain words, for the hover
## hint over the received mutations ("Ты быстрее, но хрупче.").
@export_multiline var summary: String = ""


static func create(mutation_id: StringName, mutation_title: String, mutation_layer: Layer,
		stage_one: Array[Dictionary], gains: PackedStringArray = [],
		costs: PackedStringArray = [], stages: int = 2) -> NelvarMutation:
	var mutation := NelvarMutation.new()
	mutation.id = mutation_id
	mutation.title = mutation_title
	mutation.layer = mutation_layer
	mutation.modifiers = stage_one
	mutation.gain_lines = gains
	mutation.cost_lines = costs
	mutation.max_stage = stages
	mutation.weight = [1.0, 0.7, 0.45][mutation_layer]
	return mutation


## Sets the summary; returns self so the catalog can chain it.
func described(text: String) -> NelvarMutation:
	summary = text
	return self


func modifiers_at(stage: int) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for modifier in modifiers:
		var scaled := modifier.duplicate()
		if not modifier.get("fixed", false):
			for key in ["percent", "flat"]:
				if scaled.has(key):
					scaled[key] = float(scaled[key]) * stage
		result.append(scaled)
	return result


## {"gains": PackedStringArray, "costs": PackedStringArray} — short lines for
## the card: what the player gets (green) and what they pay (red).
func describe(stage: int) -> Dictionary:
	var gains := PackedStringArray()
	var costs := PackedStringArray()
	for modifier in modifiers_at(stage):
		var line := NelvarStats.describe_modifier(modifier)
		if line.is_empty():
			continue
		if NelvarStats.goodness(modifier) >= 0:
			gains.append(line)
		else:
			costs.append(line)
	for line in gain_lines:
		gains.append(_format_line(line, stage))
	for line in cost_lines:
		costs.append(_format_line(line, stage))
	return {"gains": gains, "costs": costs}


## How much `version` wants this mutation at `stage`: its gains weighed by
## what the version values minus its costs weighed the same way.
func score_for(version: int, stage: int) -> float:
	var weights: Dictionary = VERSION_WEIGHTS[version]
	var total := 0.0
	for modifier in modifiers_at(stage):
		var stat_weight := float(weights.get(modifier["stat"], DEFAULT_WEIGHT))
		total += NelvarStats.goodness(modifier) * NelvarStats.magnitude(modifier) * stat_weight
	return total


## The version that would want this mutation most (shown on its card).
func favored_version(stage: int = 1) -> int:
	var best := 0
	var best_score := -INF
	for version in Version.size():
		var score := score_for(version, stage)
		if score > best_score:
			best_score = score
			best = version
	return best


static func version_name(owner: int) -> String:
	return SPONTANEOUS_NAME if owner == SPONTANEOUS else VERSION_NAMES[owner]


static func version_color(owner: int) -> Color:
	return SPONTANEOUS_COLOR if owner == SPONTANEOUS else VERSION_COLORS[owner]


static func stage_name(stage: int) -> String:
	return STAGE_NAMES[clampi(stage - 1, 0, STAGE_NAMES.size() - 1)]


func _format_line(line: String, stage: int) -> String:
	var result := line
	var regex := RegEx.create_from_string("\\{([0-9.]+)\\}")
	for found in regex.search_all(line):
		var amount := float(found.get_string(1)) * stage
		result = result.replace(found.get_string(), ("%.1f" % amount).trim_suffix(".0"))
	return result
