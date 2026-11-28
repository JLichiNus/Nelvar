shader_type canvas_item;
render_mode unshaded;

// A trunk of the giant forest (or a piece of the fallen giant, or a giant mushroom's cap)
// that turns see-through while the player is behind it. The art codes which pixels may thin
// out in their alpha: 240 thins out, 255 stays (the trunk's foot, so its roots always show),
// less is a shadow left as it is. Thinning lowers those pixels' alpha smoothly, at `fade` = 1
// down to MIN_ALPHA. A trunk's top `top_fade` of the texture (a share of its height) fades
// out smoothly to nothing.

uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform float top_fade = 0.0;

const float MIN_ALPHA = 0.35;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	if (color.a > 0.9 && color.a < 0.99) {
		color.a = mix(1.0, MIN_ALPHA, smoothstep(0.0, 1.0, fade));
	}
	if (top_fade > 0.0) {
		color.a *= smoothstep(0.0, top_fade, UV.y);
	}
	COLOR = color;
}
