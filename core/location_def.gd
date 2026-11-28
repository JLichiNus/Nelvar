class_name NelvarLocationDef
extends Resource
## One map, as the game knows it without opening it: which reality it belongs to, its
## name, its scene, whether «Играть» may start there. Every map has one in locations/,
## listed in the catalog (NelvarLocationCatalog); the map's scene points back to it
## (NelvarLocation.definition). A reality may have any number of maps.

## Stable name: saved in the settings (GameSettings.dev_start), used by the transitions.
@export var id: StringName
## The reality the map belongs to: colours, cursor, pause menu, music.
@export var reality: NelvarMenuElement
## The info panel's title, before the seed: "ЛЁД 2 · ПЕЩЕРА".
@export var title := ""
@export_file("*.tscn") var scene := ""
## «Играть» picks among the maps with this on when no developer start is set.
@export var random_start := false

@export_group("Developer menu")
## The start option's line: "Запускать игру в Огне".
@export var dev_label := ""
## Its hint: what «Играть» opens then.
@export var dev_hint := ""
