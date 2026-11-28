class_name NelvarPlayerProgress
extends RefCounted
## The player's part of the run (NelvarRunState): what NelvarPlayer reads and changes in
## place, so it carries from one location to the next.

var level := 1
## Kills since the last level-up.
var level_kills := 0
## Current health; below 0 until the first player of the run sets it (they start full).
var health := -1.0
