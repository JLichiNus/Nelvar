class_name NelvarTerrainStyle
extends Resource
## Visual-only settings. One terrain texel covers pixel_size world units.

@export_range(2, 8, 1) var pixel_size: int = 4
@export_range(6, 24, 1) var cliff_depth: int = 12
@export_range(12, 64, 1) var root_length: int = 36
@export_range(0.0, 1.0, 0.01) var grass_density: float = 0.34
## Share of grass tufts with a small flower beside them.
@export_range(0.0, 1.0, 0.01) var flower_density: float = 0.22
