class_name NelvarMutationDirector
extends Node
## Drives the player's mutations: the adaptation meter, whose turn the next
## mutation is, the player's own choice and its interception.
##
## Adaptation fills from what the body has to adapt to: lost health most of
## all, kills, and slowly with time. A full meter ripens a mutation. Every
## ripening belongs in advance to one of the four versions (or to none —
## a spontaneous one); the upcoming owners are known ahead (queue_length), so
## the player can plan around what the other versions will take.
##
## - The player's own: it waits (the meter stops) until the player opens the
##   choice of offer_count cards. Waited too long (pending_duration), another
##   version seizes it and picks from the same cards for itself.
## - Another version's: it picks the card that suits its element best.
## - Spontaneous: a random mutation.
##
## The player's share of ripenings goes from start_share to final_share as
## the mutations pile up (LORE, discussed part §1: 70% falling to 25%).
## Lives under the player (player.tscn) so every scene with a player has it.

signal adaptation_changed(value: float, threshold: float)
## The upcoming owners changed (upcoming_owners()).
signal queue_changed
## The player's ripe mutation appeared (true) or was resolved (false).
signal pending_changed(pending: bool)
## A mutation took effect. owner: NelvarMutation.Version or SPONTANEOUS.
## intercepted: the player's mutation was seized by another version.
signal mutation_applied(mutation: NelvarMutation, stage: int, owner: int, intercepted: bool)
## A mutation was taken away (console).
signal mutation_removed(mutation: NelvarMutation)

@export_category("Adaptation")
@export var first_threshold: float = 100.0
## Every ripening makes the next one need this many times more adaptation.
@export var threshold_growth: float = 1.18
@export var per_kill: float = 6.0
## Per point of health lost.
@export var per_health_lost: float = 1.5
@export var per_second: float = 0.3

@export_category("Versions")
@export var player_version: NelvarMutation.Version = NelvarMutation.Version.AIR
@export_range(0.0, 1.0) var start_share: float = 0.7
@export_range(0.0, 1.0) var final_share: float = 0.25
## After this many mutations the player's share reaches final_share.
@export var mutations_to_final_share: int = 12
## Share of ripenings that belong to no version at all.
@export_range(0.0, 1.0) var spontaneous_chance: float = 0.12
@export var queue_length: int = 3

@export_category("Choice")
@export var offer_count: int = 3
## Seconds the player's ripe mutation waits before another version seizes it.
@export var pending_duration: float = 40.0
## Developer key that fills the meter (debug builds only).
@export var debug_fill_key: Key = KEY_F4

var adaptation := 0.0
var threshold := 0.0
## Mutations received so far, of any owner.
var mutation_count := 0

var _player: NelvarPlayer
var _rng := RandomNumberGenerator.new()
var _pool: Array[NelvarMutation] = []
var _queue: Array[int] = []
## id -> stage reached.
var _stages := {}
## Ids in the order they were first received.
var _order: Array[StringName] = []
## id -> Array[int]: who picked each stage (Version or SPONTANEOUS).
var _owners := {}
var _pending := false
var _pending_left := 0.0
var _offers: Array[NelvarMutation] = []


func _ready() -> void:
	_player = get_parent() as NelvarPlayer
	if _player == null:
		push_warning("Директор мутаций должен быть дочерним узлом игрока.")
		set_process(false)
		return
	_rng.randomize()
	_pool = NelvarMutationCatalog.all()
	threshold = first_threshold
	_player.enemy_killed.connect(func() -> void: add_adaptation(per_kill))
	_player.damaged.connect(func(amount: float, _from: Vector2) -> void:
		add_adaptation(amount * per_health_lost))
	_refill_queue()


func _process(delta: float) -> void:
	if _pending:
		_pending_left -= delta
		if _pending_left <= 0.0:
			_intercept()
		return
	add_adaptation(per_second * delta)


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == debug_fill_key:
		add_adaptation(threshold)
		get_viewport().set_input_as_handled()


## Restarts with a fixed seed (tests).
func set_seed(value: int) -> void:
	_rng.seed = value
	_queue.clear()
	_refill_queue()


## Grows the meter (scaled by the adaptation_gain stat). Nothing grows while
## the player's mutation waits.
func add_adaptation(amount: float) -> void:
	if _pending or _player == null or _player.is_dead() or amount <= 0.0:
		return
	adaptation += amount * _player.stats.value(&"adaptation_gain")
	while adaptation >= threshold and not _pending:
		adaptation -= threshold
		threshold *= threshold_growth
		_ripen()
	adaptation_changed.emit(adaptation, threshold)


## Owners of the next ripenings, [0] is the next one.
func upcoming_owners() -> Array[int]:
	return _queue.duplicate()


## The player's share of ripenings right now (0..1).
func player_share() -> float:
	var progress := clampf(float(mutation_count) / maxi(mutations_to_final_share, 1), 0.0, 1.0)
	return lerpf(start_share, final_share, progress)


func has_pending() -> bool:
	return _pending


func pending_time_left() -> float:
	return maxf(_pending_left, 0.0) if _pending else 0.0


## The cards of the waiting mutation; empty when nothing waits.
func pending_offers() -> Array[NelvarMutation]:
	return _offers.duplicate() if _pending else []


## Takes card `index` of pending_offers().
func choose(index: int) -> void:
	if not _pending or index < 0 or index >= _offers.size():
		return
	var mutation := _offers[index]
	_resolve_pending()
	_apply(mutation, player_version, false)


## Stage reached for `id`, 0 if not received.
func stage_of(id: StringName) -> int:
	return int(_stages.get(id, 0))


## Received mutations, in the order they first came: [{mutation, stage,
## owners}], owners[i] picked stage i + 1.
func owned() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for id in _order:
		result.append({"mutation": _find(id), "stage": _stages[id], "owners": _owners[id].duplicate()})
	return result


## The stage `mutation` would get if taken now.
func next_stage(mutation: NelvarMutation) -> int:
	return stage_of(mutation.id) + 1


## Every mutation that can come.
func catalog() -> Array[NelvarMutation]:
	return _pool.duplicate()


## The catalog's mutation `id`, null if there is none.
func find(id: StringName) -> NelvarMutation:
	return _find(id)


## Console: `id` takes `stage` at once, as if `owner` picked every stage it
## gains. A lower stage than the current one takes the rest back. False for
## an unknown id or a stage outside 1..max_stage.
func grant(id: StringName, stage: int, owner: int = player_version) -> bool:
	var mutation := _find(id)
	if mutation == null or stage < 1 or stage > mutation.max_stage or _player == null:
		return false
	if not _stages.has(id):
		_order.append(id)
		_owners[id] = [] as Array[int]
	var owners: Array[int] = _owners[id]
	mutation_count += stage - stage_of(id)
	while owners.size() < stage:
		owners.append(owner)
	owners.resize(stage)
	_stages[id] = stage
	_player.stats.set_source(StringName("mutation:%s" % id), mutation.modifiers_at(stage))
	mutation_applied.emit(mutation, stage, owners[stage - 1], false)
	return true


## Console: takes `id` away with all its stages. False if it is not received.
func remove(id: StringName) -> bool:
	if not _stages.has(id) or _player == null:
		return false
	mutation_count -= int(_stages[id])
	_stages.erase(id)
	_owners.erase(id)
	_order.erase(id)
	_player.stats.set_source(StringName("mutation:%s" % id), [])
	mutation_removed.emit(_find(id))
	return true


## Console: the next mutation ripens now, as if the meter filled. `owner`
## (a Version or SPONTANEOUS) takes the turn of the queued one; any other
## value keeps the queue. False while the player's mutation already waits.
func ripen_now(owner: int = -2) -> bool:
	if _pending or _player == null or _player.is_dead():
		return false
	if owner == NelvarMutation.SPONTANEOUS or (owner >= 0 and owner < NelvarMutation.Version.size()):
		_queue[0] = owner
	adaptation = 0.0
	threshold *= threshold_growth
	_ripen()
	adaptation_changed.emit(adaptation, threshold)
	return true


func _ripen() -> void:
	var owner: int = _queue.pop_front()
	_refill_queue()
	queue_changed.emit()
	if owner == player_version:
		_offers = _draw_offers(offer_count)
		if _offers.is_empty():
			return
		_pending = true
		_pending_left = pending_duration
		pending_changed.emit(true)
	elif owner == NelvarMutation.SPONTANEOUS:
		var drawn := _draw_offers(1)
		if not drawn.is_empty():
			_apply(drawn[0], owner, false)
	else:
		var choice := _pick_for(owner, _draw_offers(offer_count))
		if choice != null:
			_apply(choice, owner, false)


# Waited too long: one of the other versions seizes the player's cards.
func _intercept() -> void:
	var others: Array[int] = []
	for version in NelvarMutation.Version.size():
		if version != player_version:
			others.append(version)
	var owner := others[_rng.randi_range(0, others.size() - 1)]
	var choice := _pick_for(owner, _offers)
	_resolve_pending()
	if choice != null:
		_apply(choice, owner, true)


func _resolve_pending() -> void:
	_pending = false
	_pending_left = 0.0
	_offers.clear()
	pending_changed.emit(false)


func _pick_for(version: int, offers: Array[NelvarMutation]) -> NelvarMutation:
	var best: NelvarMutation = null
	var best_score := -INF
	for mutation in offers:
		# A little noise so a version is predictable, not mechanical.
		var score := mutation.score_for(version, next_stage(mutation)) + _rng.randf_range(0.0, 8.0)
		if score > best_score:
			best_score = score
			best = mutation
	return best


func _apply(mutation: NelvarMutation, owner: int, intercepted: bool) -> void:
	var stage := next_stage(mutation)
	if not _stages.has(mutation.id):
		_order.append(mutation.id)
		_owners[mutation.id] = [] as Array[int]
	_stages[mutation.id] = stage
	_owners[mutation.id].append(owner)
	mutation_count += 1
	_player.stats.set_source(StringName("mutation:%s" % mutation.id), mutation.modifiers_at(stage))
	# The share changed: owners already queued keep their place, new ones
	# follow the new share.
	mutation_applied.emit(mutation, stage, owner, intercepted)


# Distinct mutations that can still grow, weighted by their chance.
func _draw_offers(count: int) -> Array[NelvarMutation]:
	var candidates: Array[NelvarMutation] = []
	for mutation in _pool:
		if stage_of(mutation.id) < mutation.max_stage:
			candidates.append(mutation)
	var result: Array[NelvarMutation] = []
	while result.size() < count and not candidates.is_empty():
		var total := 0.0
		for mutation in candidates:
			total += mutation.weight
		var roll := _rng.randf() * total
		var picked := candidates.size() - 1
		for i in candidates.size():
			roll -= candidates[i].weight
			if roll <= 0.0:
				picked = i
				break
		result.append(candidates[picked])
		candidates.remove_at(picked)
	return result


func _refill_queue() -> void:
	while _queue.size() < queue_length:
		_queue.append(_roll_owner())


func _roll_owner() -> int:
	if _rng.randf() < spontaneous_chance:
		return NelvarMutation.SPONTANEOUS
	if _rng.randf() < player_share():
		return player_version
	var others: Array[int] = []
	for version in NelvarMutation.Version.size():
		if version != player_version:
			others.append(version)
	return others[_rng.randi_range(0, others.size() - 1)]


func _find(id: StringName) -> NelvarMutation:
	for mutation in _pool:
		if mutation.id == id:
			return mutation
	return null
