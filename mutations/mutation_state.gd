class_name NelvarMutationState
extends RefCounted
## The mutations' part of the run (NelvarRunState): the meter, the owners' queue, what
## was received and by whom, the waiting choice. NelvarMutationDirector holds the rules
## and changes this in place, so it carries from one location to the next.

## False until a director first takes it (it then rolls the queue).
var started := false
var adaptation := 0.0
var threshold := 0.0
## Mutations received so far, of any owner.
var mutation_count := 0
## Owners of the next ripenings (Version or SPONTANEOUS), [0] is the next one.
var queue: Array[int] = []
## id -> stage reached.
var stages := {}
## Ids in the order they were first received.
var order: Array[StringName] = []
## id -> Array[int]: who picked each stage (Version or SPONTANEOUS).
var owners := {}
## The player's ripe mutation waits for their choice among `offers` (ids).
var pending := false
var pending_left := 0.0
var offers: Array[StringName] = []
## Every roll of the run: the queue, the cards, the versions' picks.
var rng := RandomNumberGenerator.new()
