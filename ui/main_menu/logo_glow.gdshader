shader_type canvas_item;
render_mode blend_add;
// Glowing cracks and ornament of the logo; tinted by the node's modulate
// (the current reality's accent) and slowly pulsing along the word.

uniform float pulse = 0.3;

void fragment() {
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	COLOR.rgb *= 1.0 - pulse + pulse * sin(TIME * 2.0 - px.x * 0.12);
}
