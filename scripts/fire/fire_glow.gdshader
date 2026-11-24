shader_type canvas_item;
render_mode unshaded;

// The light of the fire forge, added over the world (NelvarCloudSea as an overlay with
// additive blending, parallax 1): the lava lights the ground, the trees, the stones and
// whoever walks by it, the magma glows round the fissures and under the magma fields,
// eruptions flash, the craters of the volcanoes shine over their rims and the rivers
// of the land beyond light their banks. All of it breathes slowly. The light falls in
// a few dithered steps, one per art pixel, like the rest of the art.

uniform vec2 base_pixel;
uniform vec2 sea_size;
uniform float breath_time = 0.0;
uniform float hole_amount = 0.0;
uniform vec2 seed_offset;

uniform float texel_size = 4.0;
uniform float time = 0.0;
uniform vec2 noise_offset;
// NelvarFireField's light map: R the lava's light, G the magma's.
uniform sampler2D glow_tex : filter_linear, repeat_disable;
uniform vec2 glow_origin;
uniform vec2 glow_size = vec2(0.0);
uniform float glow_scale = 8.0;
uniform vec2 basin_center;
uniform vec2 basin_axes = vec2(1750.0, 1500.0);
uniform float basin_amp[6];
uniform float basin_phase[6];
// Eruptions and craters: world art pixel, radius in art pixels, heat.
uniform vec4 flares[16];
uniform int flare_count = 0;
// How strong the light is at its brightest.
uniform float strength = 0.62;

const vec3 LAVA_LIGHT = vec3(0.62, 0.24, 0.07);
const vec3 MAGMA_LIGHT = vec3(0.55, 0.2, 0.06);
const vec3 FLARE_LIGHT = vec3(0.75, 0.42, 0.14);
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);
// Steps the light falls in.
const float STEPS = 6.0;

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

float basin_depth(vec2 world) {
	vec2 offset = world - basin_center;
	float angle = atan(offset.y, offset.x);
	float c = cos(angle);
	float s = sin(angle);
	float radius = basin_axes.x * basin_axes.y
		/ sqrt(basin_axes.y * basin_axes.y * c * c + basin_axes.x * basin_axes.x * s * s);
	float bend = 1.0;
	for (int i = 0; i < 6; i++) {
		bend += basin_amp[i] * cos(float(i + 2) * angle + basin_phase[i]);
	}
	return radius * bend - length(offset);
}

// fire_ground.gdshader's river: above zero in the lava.
float river(vec2 np) {
	float n = value_noise(np / 150.0 + 7.0) * 0.7 + value_noise(np / 50.0 + 3.0) * 0.3;
	return 0.012 - abs(n - 0.5);
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size);
	vec2 np = pixel + noise_offset;
	vec2 light = vec2(0.0);
	if (glow_size.x > 0.0) {
		vec2 uv = (pixel + 0.5 - glow_origin) / (glow_size * glow_scale);
		if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
			light = texture(glow_tex, uv).rg;
		}
	}
	float breath = 0.82 + 0.18 * sin(time * 0.9 + value_noise(np * 0.01) * 7.0);
	float lava = light.r * breath;
	float magma = light.g * (0.7 + 0.3 * sin(time * 1.3 + value_noise(np * 0.02) * 9.0));
	float beyond = -basin_depth((pixel + 0.5) * texel_size) / texel_size;
	if (beyond > 30.0) {
		float r = river(np);
		lava = max(lava, clamp(1.0 + r / 0.05, 0.0, 1.0) * 0.7 * breath);
	}
	float flare = 0.0;
	for (int i = 0; i < 16; i++) {
		if (i >= flare_count) {
			break;
		}
		float d = length(pixel - flares[i].xy) / max(flares[i].z, 1.0);
		if (d < 1.0) {
			flare = max(flare, flares[i].w * (1.0 - d) * (1.0 - d));
		}
	}
	float dither = (BAYER[int(mod(pixel.y, 4.0)) * 4 + int(mod(pixel.x, 4.0))] + 0.5) / 16.0;
	vec3 color = LAVA_LIGHT * floor(lava * STEPS + dither) / STEPS
		+ MAGMA_LIGHT * floor(magma * STEPS + dither) / STEPS * 0.7
		+ FLARE_LIGHT * floor(min(flare, 1.6) * STEPS + dither) / STEPS;
	COLOR = vec4(color * strength, 1.0);
}
