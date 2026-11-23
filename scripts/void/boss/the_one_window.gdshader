shader_type canvas_item;
render_mode unshaded;

// The hole through the Only One's chest is a window into the Void: deep dark,
// a slow violet pulse turning around its middle, a few stars that come and go.
// Drawn over the hole's mask (white where the hole is), one texel per pixel.

uniform float time = 0.0;
uniform float intensity = 1.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	if (texture(TEXTURE, UV).a < 0.5) {
		discard;
	}
	vec2 texel = floor(UV / TEXTURE_PIXEL_SIZE);
	float swirl = 0.5 + 0.5 * sin(time * 2.2 - length(texel - vec2(8.5, 11.5)) * 1.7
		+ atan(texel.y - 11.5, texel.x - 8.5) * 2.0);
	vec3 color = mix(vec3(0.01, 0.0, 0.04), vec3(0.32, 0.12, 0.62), swirl * 0.55 * intensity);
	float star = hash12(texel + floor(time * 1.3) * 17.0);
	if (star > 0.82) {
		color = mix(color, vec3(0.9, 0.86, 1.0), 0.85);
	}
	COLOR = vec4(color, 1.0);
}
