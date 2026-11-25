class_name NelvarEnemyKind
extends Resource
## One kind of enemy the spawner can bring: its scene, how often it is picked
## among the others and how many of it may be alive at once.

@export var scene: PackedScene
## Relative chance among the kinds that are not at their cap.
@export var weight: float = 1.0
## 0 — no cap of its own (the spawner's max_alive still applies).
@export var max_alive: int = 0
