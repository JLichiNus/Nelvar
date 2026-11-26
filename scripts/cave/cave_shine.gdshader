shader_type canvas_item;
render_mode unshaded;

// The light of the ice cave, added over everything after the dark (NelvarCloudSea as an
// overlay with additive blending, parallax 1): slanting shafts of sunlight from each hole
// in the roof towards the upper left, breathing slowly, motes and snow glinting in them;
// sparks on the sunlit snow; the pale blue haloes of the glowing crystals and the
// turquoise glow of the ice by the sun; the warm rosy light of the geysers and the
// flashes of their eruptions; and the frosty mist creeping over the cold halls. All in a
// few dithered steps, one per art pixel.

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
// Towards the sun: the shafts run this way from the sunny spots.
uniform vec2 sun_dir = vec2(-0.52, -0.85);
uniform vec4 flares[8];
uniform int flare_count = 0;
uniform vec4 heat[8];
uniform int heat_count = 0;

const vec3 SUN = vec3(0.34, 0.31, 0.22);
const vec3 GLOW = vec3(0.08, 0.26, 0.32);
const vec3 WARM = vec3(0.24, 0.12, 0.14);
const vec3 FLASH = vec3(0.5, 0.36, 0.26);
const vec3 MIST = vec3(0.16, 0.2, 0.26);
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
	// Shafts of sunlight: a sunny spot further back along the shaft lights this pixel.
	vec2 dir = normalize(sun_dir);
	float shaft = 0.0;
	for (int k = 1; k <= 9; k++) {
		float t = float(k * k) * 1.6 + 4.0;
		float s = light_at(pixel - dir * t).r;
		shaft = max(shaft, s * (1.0 - t / 140.0));
	}
	shaft *= 1.0 - smoothstep(0.05, 0.6, light.r);
	if (shaft > 0.0) {
		vec2 across = vec2(-dir.y, dir.x);
		float band = dot(np, across);
		float breathe = 0.5 + 0.5 * sin(band * 0.13 + value_noise(vec2(band * 0.025, time * 0.12)) * 7.0 + time * 0.35);
		float rays = smoothstep(0.45, 0.85, breathe) * shaft;
		color += SUN * steps(rays * 0.95, dither);
		// Motes drifting in the light.
		vec2 cell = floor((np + vec2(time * 3.0, time * 1.5)) / 6.0);
		if (rays > 0.15 && hash12(cell) < 0.03 && hash12(cell + floor(time * 0.7)) < 0.6) {
			color += vec3(0.35, 0.33, 0.28) * rays;
		}
	}
	// Sparks on the sunlit snow.
	if (light.r > 0.5 && hash12(np * 0.71 + floor(time * 2.0) * 13.0) < 0.0016) {
		color += vec3(0.7);
	}
	// The cold glow of the crystals and of the ice by the sun.
	float glow = light.g * (0.82 + 0.18 * sin(time * 1.3 + value_noise(np * 0.02) * 6.0));
	color += GLOW * steps(glow, dither);
	// The geysers' warmth and their eruptions.
	float warm = light.b;
	for (int i = 0; i < 8; i++) {
		if (i >= heat_count) {
			break;
		}
		float r = length(pixel - heat[i].xy) / max(heat[i].z * heat[i].w, 1.0);
		warm = max(warm, 1.0 - smoothstep(0.0, 1.0, r));
	}
	float breath = 0.85 + 0.15 * sin(time * 0.9 + value_noise(np * 0.015) * 7.0);
	color += WARM * steps(warm * warm * breath * 0.55, dither);
	float flash = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= flare_count) {
			break;
		}
		float r = length(pixel - flares[i].xy) / max(flares[i].z, 1.0);
		if (r < 1.0) {
			flash = max(flash, flares[i].w * (1.0 - r) * (1.0 - r));
		}
	}
	color += FLASH * steps(flash, dither);
	// Frosty mist creeping over the cold halls.
	if (light.a > 0.05) {
		vec2 drift = vec2(time * 1.8, time * 0.6);
		float n = value_noise((np + drift) * 0.012) * 0.65 + value_noise((np - drift * 1.4) * 0.03) * 0.35;
		float mist = light.a * smoothstep(0.35, 0.85, n);
		color += MIST * floor(clamp(mist * 0.45, 0.0, 1.0) * 8.0 + dither) / 8.0;
	}
	COLOR = vec4(color, 1.0);
}
