class_name NelvarLocations
extends RefCounted
## Where the game's catalog of maps is (NelvarLocationCatalog).
##
## Its own class rather than a static function on the catalog: written that way, the
## catalog's script (a Resource naming itself) was not freed at exit and every run that
## opened a location ended with "Pages in use exist at exit in PagedAllocator".

const CATALOG_PATH := "res://locations/catalog.tres"


## The catalog (loaded once, then cached by the resource loader).
static func catalog() -> NelvarLocationCatalog:
	return load(CATALOG_PATH) as NelvarLocationCatalog
