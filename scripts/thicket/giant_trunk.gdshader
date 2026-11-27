shader_type canvas_item;
render_mode unshaded;

// A trunk of the giant forest (or a piece of the fallen giant, or a giant mushroom's cap)
// that thins out while the player is behind it. The art codes which pixels may thin out in
// their alpha: 240 thins out, 255 stays (the trunk's foot, so its roots always show), less
// is a shadow left as it is. Thinning keeps a dithered share of the pixels, at `fade` = 1
// only 30%, on the world's art pixel grid (the same 4×4 matrix as the art).

uniform float fade : hint_range(0.0, 1.0) = 0.0;
uniform float texel_size = 4.0;

varying vec2 world;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

void vertex() {
	world = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	if (color.a > 0.9 && color.a < 0.99) {
		color.a = 1.0;
		if (fade > 0.0) {
			vec2 pixel = floor(world / texel_size);
			vec2 m = mod(pixel, 4.0);
			float threshold = (BAYER[int(m.y) * 4 + int(m.x)] + 0.5) / 16.0;
			if (threshold > 1.0 - 0.7 * fade) {
				color.a = 0.0;
			}
		}
	}
	COLOR = color;
}
