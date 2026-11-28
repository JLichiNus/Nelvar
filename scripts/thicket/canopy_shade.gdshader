shader_type canvas_item;
render_mode unshaded;

// The shade of the crowns high above the giant forest, multiplied over everything
// (NelvarCloudSea as an overlay with multiply blending, parallax 1): a green-brown dusk under
// the crowns, full light on the clearings with a soft edge; under the crowns small bright
// flecks of sun tremble and drift as the branches sway in the gusts far above (the same
// wind as the grass's). The light falls in a few dithered steps, one per art pixel.

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
uniform vec3 dusk = vec3(0.58, 0.66, 0.56);
// The tunnel is darker still: start, axis, (length, half width).
uniform vec2 tunnel_start;
uniform vec2 tunnel_axis = vec2(1.0, 0.0);
uniform vec2 tunnel_size = vec2(0.0);

const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);
const float STEPS = 8.0;
const float CELL = 15.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 hash32(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973));
	p3 += dot(p3, p3.yxz + 33.33);
	return fract((p3.xxy + p3.yzz) * p3.zyx);
}

vec4 light_at(vec2 pixel) {
	if (light_size.x <= 0.0) {
		return vec4(0.0);
	}
	vec2 uv = (pixel + 0.5 - light_origin) / (light_size * light_scale);
	return texture(light_tex, uv);
}

// The wind far above (NelvarThicketMain.gust).
float gust(vec2 world) {
	return 0.65 * sin(world.x * 0.0045 + world.y * 0.0012 - time * 1.5)
		+ 0.35 * sin(world.x * 0.011 - world.y * 0.006 - time * 2.4);
}

// Flecks of sun on the floor under the crowns: 0..1.
float flecks(vec2 np, vec2 pixel) {
	vec2 cell = floor(np / CELL);
	float best = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			vec3 h = hash32(c + 11.0);
			if (h.x > 0.16) {
				continue;
			}
			float sway = gust((c * CELL) * texel_size) * 1.6;
			vec2 center = c * CELL + 2.0 + h.yz * (CELL - 4.0)
				+ vec2(sin(time * 0.6 + h.y * 6.28) * 1.4 + sway, cos(time * 0.45 + h.z * 6.28) * 1.1);
			float radius = 2.5 + hash12(c + 2.0) * 4.5;
			radius *= 0.8 + 0.2 * sin(time * 0.9 + h.x * 30.0);
			// Crisp spots, a ring of half light round each.
			float d = length(np - center) / radius;
			best = max(best, d < 0.75 ? 1.0 : (d < 1.0 ? 0.5 : 0.0));
		}
	}
	return best;
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size);
	vec2 np = pixel + noise_offset;
	vec4 light = light_at(pixel);
	float lit = light.r;
	lit = max(lit, flecks(np, pixel) * 0.8 * (1.0 - lit));
	vec3 dark = dusk;
	if (tunnel_size.x > 0.0) {
		vec2 world = (pixel + 0.5) * texel_size;
		vec2 local = world - tunnel_start;
		float along = dot(local, tunnel_axis);
		float across = abs(dot(local, vec2(-tunnel_axis.y, tunnel_axis.x)));
		if (along > 0.0 && along < tunnel_size.x && across < tunnel_size.y) {
			dark *= 0.72;
			lit *= 0.3;
		}
	}
	float dither = (BAYER[int(mod(pixel.y, 4.0)) * 4 + int(mod(pixel.x, 4.0))] + 0.5) / 16.0;
	lit = clamp(floor(clamp(lit, 0.0, 1.0) * STEPS + dither) / STEPS, 0.0, 1.0);
	COLOR = vec4(mix(dark, vec3(1.0), lit), 1.0);
}
