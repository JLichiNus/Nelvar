shader_type canvas_item;
render_mode unshaded;

// Shadows of the menu's clouds drifting over the earth valley: big soft shapes, cool
// shade inside, a dithered rim. Drawn over the world with multiply blending (white
// changes nothing), through NelvarCloudSea with parallax 1 and the wind's drift.

uniform vec2 base_pixel;
uniform vec2 sea_size;
uniform float breath_time = 0.0;
uniform float hole_amount = 0.0;
uniform vec2 seed_offset;
uniform vec3 shade = vec3(0.74, 0.8, 0.9);
// Share of the sky covered by clouds.
uniform float cover = 0.36;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size) + seed_offset;
	// Wide, flat-bottomed clouds: stretched sideways, slowly changing shape.
	vec2 p = pixel * vec2(0.006, 0.0095);
	float n = value_noise(p) * 0.6 + value_noise(p * 2.3 + 7.0 + breath_time * 0.01) * 0.28
		+ value_noise(p * 5.1 + 19.0) * 0.12;
	float edge = 1.0 - cover;
	float inside = smoothstep(edge - 0.012, edge + 0.012, n);
	vec2 m = mod(pixel, 4.0);
	float threshold = (BAYER[int(m.y) * 4 + int(m.x)] + 0.5) / 16.0;
	COLOR = vec4(inside > threshold ? shade : vec3(1.0), 1.0);
}
