class_name NelvarMenuElement
extends Resource
## One of the four realities shown behind the main menu.
## The background art can be replaced freely; keep breath_points in sync with it.

@export var id: StringName
## Human-readable name of the reality (not shown in the menu at the moment).
@export var title: String
@export var background: Texture2D
## Effect mask, same size as background: R = glints, G = glow, B = sway.
## Optional — without it the landscape is shown static.
@export var fx_mask: Texture2D
## Color added by the mask's glow channel (lava, embers).
@export var glow_color: Color = Color(1.0, 0.55, 0.2)
## Logo glow, highlighted button and wave edge color.
@export var accent: Color = Color.WHITE
## Stylized pixel font of this reality's menu button (colors are baked in).
@export var font: Font
## Optional material for the button text only (air: wind_text.gdshader).
@export var text_material: Material
## Living spots of the landscape: x, y in texture UV, z = radius in UV.y units.
## Tuned for tools/gen_menu_backgrounds.py: statue, right tree, pond, far tree.
@export var breath_points: PackedVector3Array

@export_group("Particles")
@export var particle_color: Color = Color.WHITE
## Particle texture size in background texels; particles are aligned along Y to velocity.
@export var particle_size: Vector2i = Vector2i(1, 1)
@export var particle_direction: Vector2 = Vector2.DOWN
@export_range(0.0, 180.0) var particle_spread: float = 20.0
@export var particle_velocity: Vector2 = Vector2(10.0, 30.0)
@export var particle_gravity: Vector2 = Vector2.ZERO
