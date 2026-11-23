shader_type canvas_item;

// The edges of the view sink into the Void: a dark violet vignette in dithered
// steps, on a coarse grid so it matches the pixel art.

uniform vec4 tint : source_color = vec4(0.02, 0.0, 0.05, 1.0);
uniform float inner = 0.55;
uniform float outer = 1.25;
uniform float pixel = 6.0;

float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

void fragment() {
	vec2 q = UV - 0.5;
	q.x *= SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float amount = smoothstep(inner, outer, length(q) * 2.0) * 0.92;
	float stepped = floor(amount * 5.0 + bayer4(floor(FRAGCOORD.xy / pixel))) / 5.0;
	COLOR = vec4(tint.rgb, clamp(stepped, 0.0, 1.0));
}
