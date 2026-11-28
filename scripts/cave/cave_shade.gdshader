shader_type canvas_item;
render_mode unshaded;

// The dark of the ice cave, multiplied over everything (NelvarCloudSea as an overlay with
// multiply blending, parallax 1). In the dark a cold blue dusk (`dark`): everything still
// reads. Under the holes in the roof the sun leaves things as they are; round the player
// their own soft light (never quite as bright as the sun); the crystals, the ice by the
// sun and the geysers' warmth lift the dusk a little; an eruption flashes. The light
// falls in a few dithered steps, one per art pixel.

uniform vec2 base_pixel;
uniform vec2 sea_size;
uniform float breath_time = 0.0;
uniform float hole_amount = 0.0;
uniform vec2 seed_offset;

uniform float texel_size = 4.0;
uniform float time = 0.0;
// NelvarCaveField's light map: R sun, G glow, B warmth, A cold.
uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 light_origin;
uniform vec2 light_size = vec2(0.0);
uniform float light_scale = 4.0;
uniform vec3 dark = vec3(0.46, 0.52, 0.66);
// The player's own light: art pixel, radius (art px), strength.
uniform vec4 player = vec4(0.0, 0.0, 47.0, 0.85);
// Eruptions: art pixel, radius (art px), strength.
uniform vec4 flares[8];
uniform int flare_count = 0;
// The geysers' warmth now (an eruption widens it): art pixel, radius (art px), scale.
uniform vec4 heat[8];
uniform int heat_count = 0;

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);
const float STEPS = 7.0;

vec4 light_at(vec2 pixel) {
	if (light_size.x <= 0.0) {
		return vec4(0.0);
	}
	vec2 uv = (pixel + 0.5 - light_origin) / (light_size * light_scale);
	return texture(light_tex, uv);
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size);
	vec4 light = light_at(pixel);
	float lit = light.r;
	float d = length(pixel + 0.5 - player.xy) / max(player.z, 1.0);
	lit = max(lit, player.w * (1.0 - smoothstep(0.3, 1.0, d)));
	lit = max(lit, light.g * 0.42);
	float warm = light.b;
	for (int i = 0; i < 8; i++) {
		if (i >= heat_count) {
			break;
		}
		float r = length(pixel - heat[i].xy) / max(heat[i].z * heat[i].w, 1.0);
		warm = max(warm, 1.0 - smoothstep(0.0, 1.0, r));
	}
	lit = max(lit, warm * 0.5);
	for (int i = 0; i < 8; i++) {
		if (i >= flare_count) {
			break;
		}
		float r = length(pixel - flares[i].xy) / max(flares[i].z, 1.0);
		if (r < 1.0) {
			lit = max(lit, flares[i].w * (1.0 - r));
		}
	}
	float dither = (BAYER[int(mod(pixel.y, 4.0)) * 4 + int(mod(pixel.x, 4.0))] + 0.5) / 16.0;
	lit = clamp(floor(clamp(lit, 0.0, 1.0) * STEPS + dither) / STEPS, 0.0, 1.0);
	COLOR = vec4(mix(dark, vec3(1.0), lit), 1.0);
}
