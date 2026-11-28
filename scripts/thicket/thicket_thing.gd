class_name NelvarThicketThing
extends NelvarEarthThing
## A thing of the giant forest on screen (NelvarEarthThing with this map's rules): low
## obstacles stand on layer 6 (the flight passes over them), flat things lie under everyone
## (leaves, feathers, bones, an acorn's cup), a creature in amber watches with the
## statues' eye, a giant mushroom's cap thins out while the player is under or behind it
## (giant_trunk.gdshader), and a drop of dew can burst.

const FADE_IN := NelvarGiantTrunk.FADE_IN
const FADE_OUT := NelvarGiantTrunk.FADE_OUT

## 0 solid .. 1 thinned out (mushrooms).
var fade := 0.0
var _fade_material: ShaderMaterial


func setup(spec: NelvarEarthData.Thing, artwork: NelvarEarthArt) -> void:
	super.setup(spec, artwork)
	if spec is NelvarThicketData.Item and (spec as NelvarThicketData.Item).low and spec.solid:
		collision_layer = NelvarProp.LOW_OBSTACLE_LAYER
	if is_flat():
		z_index = -1
	if artwork != null:
		set_art(artwork)
	if spec.kind == Kind.GIANT_MUSHROOM and spec.variant != 2:
		_fade_material = ShaderMaterial.new()
		_fade_material.shader = NelvarGiantTrunk.SHADER
		material = _fade_material


func set_art(artwork: NelvarEarthArt) -> void:
	super.set_art(artwork)
	if thing.kind == Kind.AMBER and artwork.eye.is_finite():
		set_process(true)


func is_flat() -> bool:
	return thing.kind in [Kind.LEAF, Kind.FEATHER, Kind.BONES, Kind.LILY] \
		or (thing.kind == Kind.ACORN and thing.variant == 3)


func occludes() -> bool:
	return not is_flat() and thing.kind not in [Kind.DEW, Kind.CLOVER, Kind.GIANT_MUSHROOM, Kind.ACORN]


## Mushrooms: true when the point is under the cap or behind it on screen.
func hides(point: Vector2) -> bool:
	if _fade_material == null:
		return false
	var offset := point - thing.position
	var cap := thing.size.x
	var height := thing.size.y
	if absf(offset.x) > cap + 10.0:
		return false
	# Under the cap (close round the stem), or north of the stem within the cap's height.
	if offset.length() < cap * 0.8:
		return true
	return offset.y < 0.0 and offset.y > -height - cap * 0.6 and offset.y - 70.0 < -height + cap * 0.25


func update_fade(behind: bool, delta: float) -> void:
	if _fade_material == null:
		return
	var target := 1.0 if behind else 0.0
	if is_equal_approx(fade, target):
		return
	fade = move_toward(fade, target, delta / (FADE_IN if behind else FADE_OUT))
	_fade_material.set_shader_parameter("fade", fade)
