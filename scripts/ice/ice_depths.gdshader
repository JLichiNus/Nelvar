shader_type canvas_item;
render_mode unshaded;

// The dark water under the lakes' ice (NelvarIceDepths): deep blue-green, slow pale
// streaks of light drifting through it, now and then a rising bubble. It lies deeper
// than the floor: `shift` (whole art pixels) moves it with the camera's parallax, so
// its pixels stay on the world grid. With the cave's mask (use_mask) it is deep blue ice
// under the walls — layers, cracks, strings of frozen bubbles, darker the deeper in —
// and nothing under the chasms; the mask is read at the floor's own pixel.

uniform vec2 rect_origin;            // world point of the rect's top-left corner
uniform vec2 rect_size;              // the rect's world size
uniform vec2 shift;                  // parallax offset, world units, snapped to art pixels
uniform float texel_size = 4.0;
uniform float time = 0.0;
uniform bool use_mask = false;
uniform sampler2D sdf_tex : filter_nearest, repeat_disable;
uniform vec2 sdf_origin;
uniform vec2 sdf_size;
uniform float sdf_cell = 8.0;
uniform sampler2D zone_tex : filter_nearest, repeat_disable;
uniform vec2 zone_origin;
uniform vec2 zone_size;

const vec3 WATER[4] = vec3[4](vec3(10.0, 24.0, 38.0) / 255.0, vec3(16.0, 36.0, 54.0) / 255.0,
	vec3(24.0, 52.0, 72.0) / 255.0, vec3(42.0, 76.0, 96.0) / 255.0);
const vec3 SHINE = vec3(86.0, 130.0, 150.0) / 255.0;
// Deep ice in the cave's walls, dark to light.
const vec3 ICE_BODY[5] = vec3[5](vec3(12.0, 22.0, 46.0) / 255.0, vec3(20.0, 36.0, 70.0) / 255.0,
	vec3(32.0, 56.0, 98.0) / 255.0, vec3(50.0, 84.0, 130.0) / 255.0, vec3(84.0, 124.0, 166.0) / 255.0);
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

float bayer(vec2 pixel) {
	vec2 m = mod(pixel, 4.0);
	return BAYER[int(m.y) * 4 + int(m.x)];
}

// The cave's wall depth at a floor pixel (as NelvarCaveData.wall_depth).
float wall_at(vec2 floor_pixel) {
	vec2 f = ((floor_pixel + 0.5) * texel_size - sdf_origin) / sdf_cell;
	vec2 i = floor(f);
	if (i.x < 0.0 || i.y < 0.0 || i.x >= sdf_size.x - 1.0 || i.y >= sdf_size.y - 1.0) {
		return 1000.0;
	}
	vec2 t = f - i;
	ivec2 c = ivec2(i);
	float top = mix(texelFetch(sdf_tex, c, 0).r, texelFetch(sdf_tex, c + ivec2(1, 0), 0).r, t.x);
	float bottom = mix(texelFetch(sdf_tex, c + ivec2(0, 1), 0).r, texelFetch(sdf_tex, c + ivec2(1, 1), 0).r, t.x);
	return mix(top, bottom, t.y);
}

void fragment() {
	vec2 world = rect_origin + UV * rect_size;
	vec2 pixel = floor((world - shift) / texel_size);
	vec4 masked = vec4(-1.0);
	if (use_mask) {
		vec2 floor_pixel = floor(world / texel_size);
		vec2 z = floor_pixel - zone_origin;
		float wall = wall_at(floor_pixel);
		if (wall <= 0.0 && z.x >= 0.0 && z.y >= 0.0 && z.x < zone_size.x && z.y < zone_size.y) {
			vec4 zone = texelFetch(zone_tex, ivec2(z), 0);
			if (zone.r * 255.0 > 127.5 && zone.g < 0.5) {
				masked = vec4(0.0);
			}
		}
		if (masked.a < 0.0 && wall > 0.0) {
			float deep = clamp(wall / 300.0, 0.0, 1.0);
			float n = value_noise(pixel * 0.02 + vec2(time * 0.006, 0.0)) * 0.6 + value_noise(pixel * 0.07) * 0.4;
			float level = 0.78 - deep * 0.5 + (n - 0.5) * 0.3 + sin(pixel.y * 0.33 + n * 5.0) * 0.05;
			float t = clamp(level, 0.0, 0.9999) * 4.0;
			int i = int(t);
			if ((t - float(i)) * 16.0 > bayer(pixel) + 0.5) {
				i += 1;
			}
			vec3 ice = ICE_BODY[i];
			// Strings of bubbles frozen on their way up.
			vec2 cell = floor(pixel / vec2(5.0, 23.0));
			float h = hash12(cell + 0.3);
			if (h < 0.08 && pixel.x == cell.x * 5.0 + 2.0 && mod(pixel.y + floor(h * 40.0), 3.0) < 1.0) {
				ice = ICE_BODY[4];
			}
			masked = vec4(ice, 1.0);
		}
	}
	float n = value_noise(pixel * 0.018 + vec2(time * 0.04, time * 0.015)) * 0.65
		+ value_noise(pixel * 0.05 - vec2(time * 0.07, 0.0)) * 0.35;
	float level = 0.3 + (n - 0.5) * 0.7;
	float t = clamp(level, 0.0, 0.9999) * 3.0;
	int i = int(t);
	if ((t - float(i)) * 16.0 > bayer(pixel) + 0.5) {
		i += 1;
	}
	vec3 color = WATER[i];
	// Slow streaks of light from above, bending as they drift.
	float streak = sin(dot(pixel, vec2(0.11, 0.045)) + n * 5.0 + time * 0.35);
	if (streak > 0.985 && value_noise(pixel * 0.03 + 4.0) > 0.45) {
		color = mix(color, SHINE, 0.6);
	}
	// A bubble rising now and then.
	vec2 cell = floor(pixel / 9.0);
	float h = hash12(cell + 0.7);
	if (h < 0.025) {
		vec2 at = cell * 9.0 + vec2(floor(hash12(cell + 2.1) * 8.0), 8.0 - mod(time * 3.0 + h * 400.0, 9.0));
		if (pixel == floor(at)) {
			color = SHINE;
		}
	}
	COLOR = masked.a >= 0.0 ? masked : vec4(color, 1.0);
}
