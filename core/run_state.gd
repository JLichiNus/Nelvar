class_name NelvarRunState
extends RefCounted
## What one run keeps between locations (NelvarRun): the player's progress, their
## mutations and the Void's checkpoint. Plain data: the nodes that use it
## (NelvarPlayer, NelvarMutationDirector, NelvarVoidMain) hold the rules.

var player := NelvarPlayerProgress.new()
var mutations := NelvarMutationState.new()
## A Void whose boss fight was lost comes back with this seed, the player at the
## arena's door: the climb is not repeated. -1: no checkpoint.
var void_checkpoint := -1
