shader_type canvas_item;
render_mode unshaded;

// Rare clouds drifting over the plateau and the far peaks: the valley lies high, and
// they pass by close. Puffy shapes in the menu's cloud colours, lit from the upper
// right, a shaded lower-left rim, and a shadow on the ground below them. Over the
// valley they thin out and vanish, so they never hide the play.
//
// Runs through NelvarCloudSea with parallax 1 and the wind's drift, over the world
// with normal blending. `drift_pixels` (NelvarEarthMain) turns cloud pixels back
// into world pixels for the valley test.

uniform vec2 base_pixel;
uniform vec2 sea_size;
uniform float breath_time = 0.0;
uniform float hole_amount = 0.0;
uniform vec2 seed_offset;

uniform float texel_size = 4.0;
uniform vec2 drift_pixels;
uniform vec2 valley_center;
uniform vec2 valley_axes = vec2(1750.0, 1500.0);
uniform float valley_amp[6];
uniform float valley_phase[6];
// Share of grid cells over the plateau with a cloud.
uniform float cover = 0.2;
// Art pixels outside the mountain foot where the clouds begin, and where they are full.
uniform vec2 fade = vec2(160.0, 420.0);
// Shadow on the ground: down and to the left, like every shadow in the valley.
uniform vec2 shadow_offset = vec2(-12.0, 30.0);

// Menu cumulus, dark to light (tools/gen_menu_backgrounds.py, earth()).
const vec3 CLOUD[4] = vec3[4](vec3(178.0, 196.0, 222.0) / 255.0, vec3(214.0, 226.0, 238.0) / 255.0,
	vec3(242.0, 246.0, 248.0) / 255.0, vec3(1.0));
const vec4 SHADOW = vec4(38.0 / 255.0, 56.0 / 255.0, 86.0 / 255.0, 0.22);
// Grid cell holding at most one cloud, art pixels.
const float CELL = 190.0;
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

// earth_ground.gdshader, valley_depth: positive inside, world units.
float valley_depth(vec2 world) {
	vec2 offset = world - valley_center;
	float angle = atan(offset.y, offset.x);
	float c = cos(angle);
	float s = sin(angle);
	float radius = valley_axes.x * valley_axes.y
		/ sqrt(valley_axes.y * valley_axes.y * c * c + valley_axes.x * valley_axes.x * s * s);
	float bend = 1.0;
	for (int i = 0; i < 6; i++) {
		bend += valley_amp[i] * cos(float(i + 2) * angle + valley_phase[i]);
	}
	return radius * bend - length(offset);
}

// How deep into a cloud a cloud pixel lies: above zero inside. A cloud is a few
// round lumps on a flat base (the menu's cumulus), one maybe per grid cell, more
// often far from the valley; near it they shrink and vanish.
float cloud(vec2 pixel) {
	vec2 q = pixel + seed_offset;
	vec2 cell = floor(q / CELL);
	float best = -1.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			if (hash12(c * 1.7 + 3.1) > cover) {
				continue;
			}
			vec2 center = (c + 0.25 + vec2(hash12(c + 7.0), hash12(c + 13.0)) * 0.5) * CELL;
			vec2 world = (center - seed_offset + drift_pixels) * texel_size;
			float open = smoothstep(fade.x, fade.y, -valley_depth(world) / texel_size);
			float size = (1.0 + hash12(c + 21.0) * 0.8) * open;
			if (size < 0.2) {
				continue;
			}
			int lumps = 3 + int(hash12(c + 29.0) * 3.0);
			for (int k = 0; k < 6; k++) {
				if (k >= lumps) {
					break;
				}
				float f = float(k) / float(lumps - 1) - 0.5;
				vec2 at = center + vec2(f * 46.0 + (hash12(c + float(k) * 5.0) - 0.5) * 10.0,
					abs(f) * 10.0 - (0.5 - abs(f)) * 14.0) * size;
				float r = (11.0 + (0.5 - abs(f)) * 16.0 + hash12(c + float(k) * 11.0) * 5.0) * size;
				vec2 d = (q - at) / vec2(r * 1.15, r);
				// The flat base: lumps are cut off below the cloud's floor.
				if (q.y > center.y + 8.0 * size) {
					continue;
				}
				best = max(best, 1.0 - length(d));
			}
		}
	}
	float wobble = (value_noise(q * 0.18 + breath_time * 0.05) - 0.5) * 0.12;
	return best + wobble;
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size);
	float bayer = BAYER[int(mod(pixel.y, 4.0)) * 4 + int(mod(pixel.x, 4.0))];
	float inside = cloud(pixel);
	if (inside > 0.0) {
		// Lit where the cloud goes on towards the upper right; a dark rim at the lower left.
		float lit = cloud(pixel + vec2(3.0, -3.0));
		float level = 0.5 + clamp(inside * 1.5, 0.0, 0.3) + (lit > 0.0 ? 0.2 : -0.15);
		if (cloud(pixel + vec2(-2.0, 2.0)) <= 0.0) {
			level = 0.1;
		}
		float t = clamp(level, 0.0, 0.9999) * 3.0;
		int i = int(t);
		if ((t - float(i)) * 16.0 > bayer + 0.5) {
			i += 1;
		}
		COLOR = vec4(CLOUD[i], 1.0);
	} else if (cloud(pixel - shadow_offset) > 0.0) {
		COLOR = SHADOW;
	} else {
		COLOR = vec4(0.0);
	}
}
