shader_type canvas_item;
render_mode unshaded;

// The light of the giant forest, added over everything after the crowns' shade
// (NelvarCloudSea as an overlay with additive blending, parallax 1): slanting rays from the
// openings in the crowns towards the upper right (the sun is there), breathing slowly, motes
// of pollen drifting in them; sparks on the resin in the sun; the faint glow of tinder
// fungi and of the glowing mushrooms in the dark (strongest in the fallen giant's tunnel).
// All in a few dithered steps, one per art pixel.

uniform vec2 base_pixel;
uniform vec2 sea_size;
uniform float breath_time = 0.0;
uniform float hole_amount = 0.0;
uniform vec2 seed_offset;

uniform float texel_size = 4.0;
uniform float time = 0.0;
uniform vec2 noise_offset;
uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 light_origin;
uniform vec2 light_size = vec2(0.0);
uniform float light_scale = 4.0;
// Towards the sun: the rays run this way from the open spots.
uniform vec2 sun_dir = vec2(0.52, -0.85);
// Glowing things near the player: art pixel, radius (art px), strength; and their colour.
uniform vec4 glows[16];
uniform vec3 glow_tint[16];
uniform int glow_count = 0;

const vec3 SUN = vec3(0.3, 0.27, 0.16);
const vec3 MOTE = vec3(0.4, 0.36, 0.2);
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);
const float STEPS = 5.0;

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

vec4 light_at(vec2 pixel) {
	if (light_size.x <= 0.0) {
		return vec4(0.0);
	}
	vec2 uv = (pixel + 0.5 - light_origin) / (light_size * light_scale);
	return texture(light_tex, uv);
}

float steps(float value, float dither) {
	return floor(clamp(value, 0.0, 1.5) * STEPS + dither) / STEPS;
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size);
	vec2 np = pixel + noise_offset;
	vec4 light = light_at(pixel);
	float dither = (BAYER[int(mod(pixel.y, 4.0)) * 4 + int(mod(pixel.x, 4.0))] + 0.5) / 16.0;
	vec3 color = vec3(0.0);
	// Rays: an open spot further back along the ray lights this pixel.
	vec2 dir = normalize(sun_dir);
	float shaft = 0.0;
	for (int k = 1; k <= 10; k++) {
		float t = float(k * k) * 1.8 + 4.0;
		float s = light_at(pixel - dir * t).r;
		shaft = max(shaft, s * (1.0 - t / 190.0));
	}
	shaft = max(shaft, light.r * 0.55);
	if (shaft > 0.0) {
		vec2 across = vec2(-dir.y, dir.x);
		float band = dot(np, across);
		float breathe = 0.5 + 0.5 * sin(band * 0.11 + value_noise(vec2(band * 0.02, time * 0.1)) * 7.0 + time * 0.3);
		float rays = smoothstep(0.42, 0.85, breathe) * shaft;
		color += SUN * steps(rays * 0.9, dither);
		// Pollen drifting in the light.
		vec2 cell = floor((np + vec2(time * 2.2, -time * 1.4)) / 7.0);
		if (rays > 0.12 && hash12(cell) < 0.035 && hash12(cell + floor(time * 0.6)) < 0.65) {
			color += MOTE * rays;
		}
	}
	// Sparks on the resin in the sun.
	if (light.a > 0.52 && hash12(np * 0.71 + floor(time * 2.0) * 13.0) < 0.004 + light.r * 0.01) {
		color += vec3(0.6, 0.5, 0.3);
	}
	// The glow of fungi and mushrooms.
	for (int i = 0; i < 16; i++) {
		if (i >= glow_count) {
			break;
		}
		float r = length(pixel - glows[i].xy) / max(glows[i].z, 1.0);
		if (r < 1.0) {
			float pulse = 0.85 + 0.15 * sin(time * 1.7 + float(i) * 1.3);
			color += glow_tint[i] * steps((1.0 - r) * (1.0 - r) * glows[i].w * pulse, dither);
		}
	}
	COLOR = vec4(color, 1.0);
}
