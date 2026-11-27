shader_type canvas_item;
// The game behind the pause menu: drained of color, darkened and softly
// blurred, so it stays recognizable but does not compete with the menu.
// `amount` 0..1 follows the menu's open animation.

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float amount : hint_range(0.0, 1.0) = 1.0;
// At amount 1: how much color is left, how bright, blur radius in pixels.
uniform float saturation = 0.25;
uniform float brightness = 0.45;
uniform float blur_radius = 2.5;
uniform vec3 tint : source_color = vec3(0.55, 0.62, 0.8);

void fragment() {
	vec2 reach = SCREEN_PIXEL_SIZE * blur_radius * amount;
	// 9 taps in a ring around the pixel plus the pixel itself.
	vec3 color = textureLod(screen_texture, SCREEN_UV, 0.0).rgb * 2.0;
	for (int i = 0; i < 8; i++) {
		float angle = float(i) * 0.785398;
		color += textureLod(screen_texture, SCREEN_UV + vec2(cos(angle), sin(angle)) * reach, 0.0).rgb;
	}
	color /= 10.0;
	float luma = dot(color, vec3(0.299, 0.587, 0.114));
	vec3 drained = mix(vec3(luma) * tint * 1.6, color, saturation);
	vec3 result = mix(color, drained * brightness, amount);
	COLOR = vec4(result, 1.0);
}
