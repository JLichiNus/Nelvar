shader_type canvas_item;
// Brightness over everything drawn before it (DisplayOverlay): a gamma curve,
// so black and white stay and the mid tones move. gamma > 1 is brighter.

uniform sampler2D screen_texture : hint_screen_texture, filter_nearest;
uniform float gamma = 1.0;

void fragment() {
	vec3 color = textureLod(screen_texture, SCREEN_UV, 0.0).rgb;
	COLOR = vec4(pow(max(color, vec3(0.0)), vec3(1.0 / gamma)), 1.0);
}
