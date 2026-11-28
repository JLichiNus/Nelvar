class_name NelvarLocationCatalog
extends Resource
## Every map of the game (locations/catalog.tres, NelvarLocations.catalog()), in the order
## the developer menu lists them. Adding a map: its NelvarLocationDef in locations/, a line
## here, `definition` on the scene's root — nothing else needs to know about it.

@export var locations: Array[NelvarLocationDef] = []


## The map `id`; null if there is none.
func find(id: StringName) -> NelvarLocationDef:
	for location in locations:
		if location.id == id:
			return location
	return null


## The maps «Играть» picks among at random.
func random_starts() -> Array[NelvarLocationDef]:
	var result: Array[NelvarLocationDef] = []
	result.assign(locations.filter(func(location: NelvarLocationDef) -> bool: return location.random_start))
	return result


## Where «Играть» opens: the developer start `dev_start` if it names a map, else one of
## random_starts().
func start_location(dev_start: StringName = &"") -> NelvarLocationDef:
	var chosen := find(dev_start) if not dev_start.is_empty() else null
	if chosen != null:
		return chosen
	return random_starts().pick_random()
