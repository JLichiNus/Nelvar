shader_type canvas_item;
// Disabled blending: the viewport keeps the floor's own alpha, so where there is no
// mountain (past the summit's edge, round the front slope) the clouds far below
// (crater_below.gdshader, on the layer under this one) show through.
render_mode unshaded, blend_disabled;

// The top of the volcano in the palette of the "Огонь" menu (fire_common): the rim of
// basalt and ash with its roads of cooled lava, sulfur round the vents and geysers, the
// geysers' mouths; the lava lake turning slowly with its rings of current, crusted over
// in the open, bright along its shores, boiling in patches and churning white-hot in
// the vent; the crater's inner wall under the north shore (a few art pixels of basalt
// strata lit red from below), the faces of the capes and the anchors; the anchors' hot
// joints. Under the summit's south edge hangs the front slope of the mountain: strata
// of basalt and ash, gullies and ribs running down and spreading like a cone, lava
// trickling down some gullies; it darkens and dissolves into the clouds.
//
// Runs through NelvarCloudSea with parallax 1: one fragment per art pixel of the world
// grid. The lake, the capes, the anchors and the summit's edge are computed here exactly
// as NelvarCraterData does (lava_depth, rim_depth); NelvarCraterField supplies the rest.

uniform vec2 base_pixel;
uniform vec2 sea_size;
uniform float breath_time = 0.0;     // set by NelvarCloudSea; unused here
uniform float hole_amount = 0.0;     // set by NelvarCloudSea; unused here
uniform vec2 seed_offset;            // set by NelvarCloudSea; unused here

uniform float texel_size = 4.0;
uniform float time = 0.0;
uniform vec2 noise_offset;
uniform sampler2D field_tex : filter_nearest, repeat_disable;
uniform vec2 field_origin;
uniform vec2 field_size;
// The lake (a NelvarEarthData.Radial).
uniform vec2 lake_center;
uniform vec2 lake_axes = vec2(1640.0, 1540.0);
uniform float lake_amp[6];
uniform float lake_phase[6];
// The summit's edge: its radius in each of `edge_count` directions round lake_center.
uniform sampler2D edge_tex : filter_nearest, repeat_disable;
uniform int edge_count = 1;
// Capes: base and tip (world), then the half width at the base and at the tip, the
// wobble and its phase.
uniform vec4 cape_line[6];
uniform vec4 cape_form[6];
uniform int cape_count = 0;
uniform float cape_blend = 48.0;
// Anchors: centre and axes, then six bends each.
uniform vec4 anchor_shape[4];
uniform float anchor_amp[24];
uniform float anchor_phase[24];
uniform int anchor_count = 0;
// The vent: world centre and radius. Boiling patches: world centre and radius.
uniform vec3 vent = vec3(0.0, 0.0, 70.0);
uniform vec3 boils[6];
uniform int boil_count = 0;
// The rings of current: inner and outer edge (distance from the vent), radians per second.
uniform vec3 rings[3];
uniform int ring_count = 0;
uniform float ring_gap = 18.0;
// Geysers: world art pixel, mouth radius in art pixels, state (0..1 resting, 1..2
// warning, 2..3 erupting).
uniform vec4 geysers[10];
uniform int geyser_count = 0;
// The front slope: per art pixel column from slope_origin, the row where the summit ends
// in the south (-1: none); the first and last such columns and their rows; the
// crater's centre column and half width, art pixels.
uniform sampler2D slope_tex : filter_nearest, repeat_disable;
uniform float slope_origin = 0.0;
uniform vec4 slope_ends = vec4(0.0);
uniform float summit_mid = 0.0;
uniform float summit_half = 420.0;

#include "res://scripts/fire/fire_common.gdshaderinc"

// Art pixels of slope seen before the clouds swallow it, and how its sides spread
// (pixels down per pixel out).
const float SLOPE_DEPTH = 240.0;
const float CONE = 2.4;
// What the slope fades into: the ash clouds' shadowed tone.
const vec3 DEPTHS = vec3(58.0, 46.0, 50.0) / 255.0;
const vec3 PIT = vec3(20.0, 14.0, 18.0) / 255.0;

float smooth_max(float a, float b, float k) {
	float h = max(k - abs(a - b), 0.0) / k;
	return max(a, b) + h * h * k * 0.25;
}

// NelvarEarthData.Radial.signed_distance of the lake.
float lake_sd(vec2 world) {
	vec2 offset = world - lake_center;
	float angle = atan(offset.y, offset.x);
	float c = cos(angle);
	float s = sin(angle);
	float radius = lake_axes.x * lake_axes.y
		/ sqrt(lake_axes.y * lake_axes.y * c * c + lake_axes.x * lake_axes.x * s * s);
	float bend = 1.0;
	for (int i = 0; i < 6; i++) {
		bend += lake_amp[i] * cos(float(i + 2) * angle + lake_phase[i]);
	}
	return radius * bend - length(offset);
}

float anchor_sd(int a, vec2 world) {
	vec2 offset = world - anchor_shape[a].xy;
	vec2 axes = anchor_shape[a].zw;
	float angle = atan(offset.y, offset.x);
	float c = cos(angle);
	float s = sin(angle);
	float radius = axes.x * axes.y / sqrt(axes.y * axes.y * c * c + axes.x * axes.x * s * s);
	float bend = 1.0;
	for (int i = 0; i < 6; i++) {
		bend += anchor_amp[a * 6 + i] * cos(float(i + 2) * angle + anchor_phase[a * 6 + i]);
	}
	return radius * bend - length(offset);
}

// NelvarCraterData.Cape.signed_distance.
float cape_sd(int c, vec2 world) {
	vec2 base = cape_line[c].xy;
	vec2 axis = cape_line[c].zw - base;
	float t = clamp(dot(world - base, axis) / max(dot(axis, axis), 0.0001), 0.0, 1.0);
	float width = mix(cape_form[c].x, cape_form[c].y, t) * (1.0 + cape_form[c].z * sin(t * 9.0 + cape_form[c].w));
	return width - length(world - (base + axis * t));
}

// NelvarCraterData.lava_depth: positive in the lake's lava, world units.
float lava_depth(vec2 world) {
	float ground = -lake_sd(world);
	if (ground > 600.0) {
		return -ground;
	}
	for (int c = 0; c < 6; c++) {
		if (c >= cape_count) {
			break;
		}
		ground = smooth_max(ground, cape_sd(c, world), cape_blend);
	}
	for (int a = 0; a < 4; a++) {
		if (a >= anchor_count) {
			break;
		}
		ground = max(ground, anchor_sd(a, world));
	}
	return -ground;
}

// NelvarCraterData.rim_depth: positive on the summit, world units.
float summit_sd(vec2 world) {
	vec2 offset = world - lake_center;
	float t = mod(atan(offset.y, offset.x), 6.2831853) / 6.2831853 * float(edge_count);
	int i = int(t);
	float f = t - float(i);
	i = i % edge_count;
	float a = texelFetch(edge_tex, ivec2(i, 0), 0).r;
	float b = texelFetch(edge_tex, ivec2((i + 1) % edge_count, 0), 0).r;
	return mix(a, b, f) - length(offset);
}

vec4 field_at(vec2 pixel) {
	vec2 f = pixel - field_origin;
	if (f.x < 0.0 || f.y < 0.0 || f.x >= field_size.x || f.y >= field_size.y) {
		return vec4(0.0, 1.0, 1.0, 0.0);
	}
	return texelFetch(field_tex, ivec2(f), 0);
}

// Row (art pixels) where the mountain's front begins under column x: the summit's south
// edge, and past its sides the cone's flanks running down and out.
float slope_top(float x) {
	if (x < slope_ends.x) {
		return slope_ends.z + (slope_ends.x - x) * CONE;
	}
	if (x > slope_ends.y) {
		return slope_ends.w + (x - slope_ends.y) * CONE;
	}
	float top = texelFetch(slope_tex, ivec2(int(x - slope_origin), 0), 0).r;
	return top < 0.0 ? 1.0e6 : top;
}

// The mountain's front below the summit: x is the art pixel column, depth how far below
// the edge. Transparent above it and once it has dissolved into the clouds.
vec4 front_slope(vec2 pixel, vec2 np) {
	float depth = pixel.y + 0.5 - slope_top(pixel.x);
	if (depth <= 0.0) {
		return vec4(0.0);
	}
	float fade = 1.0 - smoothstep(SLOPE_DEPTH * 0.45, SLOPE_DEPTH, depth + (value_noise(np * 0.08) - 0.5) * 34.0);
	if (fade * 16.0 <= bayer(pixel) + 0.5) {
		return vec4(0.0);
	}
	float half_width = summit_half + depth / CONE;
	float across = (pixel.x + 0.5 - summit_mid) / half_width;
	// Ribs and gullies run down the slope, uneven, spreading as the cone widens. Each rib
	// is lit on its right side and shaded on its left (the light is from the upper right).
	float warp = (value_noise(vec2(across * 6.0, depth * 0.025) + 5.0) - 0.5) * 1.8
		+ (value_noise(vec2(across * 23.0, depth * 0.06) + 9.0) - 0.5) * 0.5;
	float lane = across * 26.0 + warp;
	float gully = floor(lane);
	float side = fract(lane);
	float lit = 0.5 + across * 0.16 - across * across * 0.22
		+ (side - 0.5) * 0.34
		- smoothstep(0.0, SLOPE_DEPTH, depth) * 0.42
		+ (value_noise(np * 0.13) - 0.5) * 0.14;
	vec3 color = ramp(BASALT, 5, lit, pixel);
	// Ash lies in drifts, thickest near the top.
	float ash = value_noise(vec2(pixel.x * 0.035, depth * 0.05) + 17.0) - smoothstep(0.0, SLOPE_DEPTH * 0.7, depth) * 0.3;
	if ((ash - 0.6) * 90.0 > bayer(pixel) + 0.5) {
		color = ramp(ASH, 4, lit - 0.12, pixel);
	} else if (value_noise(vec2(pixel.x * 0.05, depth * 0.04) + 61.0) > 0.78) {
		color = ramp(CINDER, 3, lit - 0.05, pixel);
	}
	// The gully floor: a dark line between ribs, lost here and there under ash.
	if (side < 0.06 && value_noise(vec2(gully * 3.7, depth * 0.05)) > 0.3) {
		color = PAL[BASALT];
	}
	// Ledges of harder rock across the slope: a lit top over a shadow, short and few.
	float ledge = depth + (value_noise(vec2(pixel.x * 0.06, 2.0)) - 0.5) * 12.0;
	float step_row = fract(ledge / 23.0) * 23.0;
	if (value_noise(vec2(pixel.x * 0.045, floor(ledge / 23.0) * 3.1)) > 0.64) {
		if (step_row < 1.0) {
			color = PAL[BASALT + 3];
		} else if (step_row < 2.0) {
			color = PAL[BASALT];
		}
	}
	// Lava trickling down a few gullies, from under the edge.
	if (hash12(vec2(gully, 11.3)) < 0.12) {
		float start = 2.0 + hash12(vec2(gully, 2.1)) * 24.0;
		float run = 30.0 + hash12(vec2(gully, 7.9)) * 80.0;
		float width = 0.045 * (1.0 - smoothstep(start + run * 0.5, start + run, depth)) + 0.02;
		if (depth > start && depth < start + run) {
			float off = abs(side - 0.08);
			if (off < width) {
				float streak = fract((depth - time * 5.0) / 7.0 + hash12(vec2(gully, 4.7)));
				color = streak < 0.16 ? PAL[LAVA + 3] : (streak < 0.55 ? PAL[LAVA + 2] : PAL[LAVA + 1]);
			} else if (off < width + 0.05) {
				color = mix(color, SCORCH, 0.55);
			}
		}
	}
	color = mix(color, DEPTHS, smoothstep(SLOPE_DEPTH * 0.15, SLOPE_DEPTH, depth) * 0.6);
	// The lip where the flat top breaks into the slope.
	float lip = pixel.x < slope_ends.x || pixel.x > slope_ends.y ? CONE : 1.0;
	if (depth < lip) {
		color = PAL[BASALT + 3];
	} else if (depth < lip + 1.0) {
		color = PAL[BASALT];
	}
	return vec4(color, 1.0);
}

// 0..1: how hard the lava boils here.
float boiling(vec2 world, vec2 np) {
	float best = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= boil_count) {
			break;
		}
		float d = length(world - boils[i].xy) / boils[i].z + (value_noise(np * 0.12) - 0.5) * 0.3;
		best = max(best, 1.0 - smoothstep(0.45, 1.0, d));
	}
	return best;
}

// The lake: crust drifting with its ring of current (or churning slowly where no ring
// runs), bright seams between the floes, a hot band along the shores, bubbles; brighter
// and barer in the boiling patches and round the vent.
vec3 crater_lava(vec2 pixel, vec2 np, float depth, vec2 world) {
	vec2 offset = world - vent.xy;
	float r = length(offset);
	float wander = r + (value_noise(np * 0.04) - 0.5) * 36.0;
	float spin = 0.0;
	for (int k = 0; k < 3; k++) {
		if (k >= ring_count) {
			break;
		}
		if (wander > rings[k].x - ring_gap * 0.5 && wander < rings[k].y + ring_gap * 0.5) {
			spin = rings[k].z;
		}
	}
	float a = -mod(spin * time, 6.2831853);
	vec2 turned = vec2(cos(a) * offset.x - sin(a) * offset.y, sin(a) * offset.x + cos(a) * offset.y);
	vec2 q = (turned + vent.xy) / texel_size + noise_offset;
	if (spin == 0.0) {
		q += vec2(sin(time * 0.13 + q.y * 0.02), cos(time * 0.11 + q.x * 0.02)) * 3.0
			+ vec2(time * 0.4, time * 0.15);
	}
	float mouth = (r - vent.z) / texel_size + (value_noise(np * 0.12) - 0.5) * 5.0;
	if (mouth < 0.0) {
		// The vent: white-hot lava welling up and churning.
		float churn = hash12(pixel + floor(time * 4.0 + hash12(pixel) * 3.0) * 5.3);
		return churn < 0.25 ? PAL[LAVA + 5] : (churn < 0.7 ? PAL[LAVA + 4] : PAL[LAVA + 3]);
	}
	if (mouth < 2.5 && value_noise(np * 0.2 + 9.0) > 0.38) {
		// Its rim of spatter, broken, cracked and glowing.
		vec3 c = cells(np / 3.0);
		return c.y < 0.1 ? PAL[LAVA + 2] : ramp(CRUST, 3, 0.2 + c.z * 0.6, pixel);
	}
	float shore = 1.0 - smoothstep(0.0, 5.0, depth);
	float near_vent = 1.0 - smoothstep(0.0, 56.0, mouth);
	float boil = boiling(world, np);
	// Rafts of dark crust cover the lake; pools of open lava wander between them, and it
	// lies open along the shores, over the boils and round the vent.
	float pool = value_noise(q / 40.0 + 11.0) * 0.75 + value_noise(q / 14.0) * 0.25;
	float open = max(max(max(shore, near_vent), boil), smoothstep(0.64, 0.76, pool));
	vec3 floe = cells(q / 12.0);
	vec3 color;
	if (open > 0.5 + (floe.z - 0.5) * 0.7) {
		color = ramp(LAVA, 6, 0.28 + open * 0.3 + (value_noise(q * 0.15) - 0.5) * 0.3, pixel);
		if (floe.y < 0.03) {
			color = PAL[LAVA + 4];
		}
		float bubbles = 0.004 + boil * 0.06 + near_vent * 0.05;
		if (hash12(floor(q / 3.0) + floor(time * (1.4 + boil * 2.0)) * 7.0) < bubbles) {
			color = PAL[LAVA + 5];
		}
	} else if (floe.y < 0.03) {
		// The seams between rafts glow, brighter where the lava is open nearby.
		color = open > 0.25 ? PAL[LAVA + 3] : PAL[LAVA + 2];
	} else if (floe.y < 0.06) {
		color = PAL[LAVA];
	} else {
		color = ramp(CRUST, 3, 0.18 + floe.z * 0.45 + (value_noise(q * 0.25) - 0.5) * 0.2, pixel);
		if (abs(value_noise(q * 0.08 + floe.z * 40.0) - 0.5) < 0.008) {
			color = PAL[LAVA];
		}
	}
	if (depth < 1.0) {
		color = PAL[LAVA + 3];
	}
	return color;
}

// The crater's inner wall under the north shore: `k` rows below the rim's lip, of `h`.
// Strata of basalt, the lowest row lit red by the lava.
vec3 crater_wall(vec2 pixel, vec2 np, float k, float h) {
	if (k >= h) {
		return PAL[LAVA];
	}
	if (k <= 1.0) {
		return PAL[BASALT + 3];
	}
	float band = hash12(vec2(floor((pixel.y + floor(value_noise(vec2(pixel.x * 0.1, 2.0)) * 3.0)) / 1.0), 7.3));
	vec3 color = band < 0.35 ? PAL[BASALT + 2] : (band < 0.8 ? PAL[BASALT + 1] : PAL[CRUST + 1]);
	if (k >= h - 1.0) {
		color = mix(color, PAL[LAVA], 0.45);
	}
	return color;
}

vec3 geyser_mouth(vec3 color, vec2 pixel, vec2 np) {
	for (int i = 0; i < 10; i++) {
		if (i >= geyser_count) {
			break;
		}
		vec4 g = geysers[i];
		vec2 o = (pixel + 0.5 - g.xy) * vec2(1.0, 1.35);
		float d = length(o) / g.z;
		if (d > 1.9) {
			continue;
		}
		float warn = clamp(g.w - 1.0, 0.0, 1.0);
		float burst = clamp(g.w - 2.0, 0.0, 1.0);
		bool erupting = g.w >= 2.0;
		if (d < 0.55) {
			color = PIT;
			float heat = erupting ? 1.0 - burst * 0.5 : warn * (0.6 + 0.4 * abs(sin(time * 14.0)));
			if (d < 0.2 + heat * 0.32) {
				float churn = hash12(pixel + floor(time * 6.0) * 3.1);
				color = heat > 0.7 ? (churn < 0.4 ? PAL[LAVA + 4] : PAL[LAVA + 3])
					: (heat > 0.25 ? PAL[LAVA + 2] : (churn < 0.5 ? PAL[CRUST + 1] : PIT));
			}
		} else if (d < 0.9) {
			// Geyserite: pale mineral crust round the mouth.
			float n = value_noise(np * 0.5);
			color = n < 0.45 ? PAL[ASH + 3] : (n < 0.75 ? PAL[SULFUR + 3] : PAL[ASH + 2]);
			if (erupting && hash12(pixel + floor(time * 10.0)) < 0.2) {
				color = PAL[LAVA + 3];
			}
		} else if (d < 1.3) {
			if (value_noise(np * 0.4 + 3.0) > 0.45) {
				color = mix(color, PAL[ASH + 2], 0.6);
			}
			if (erupting) {
				color *= 0.82;
			}
		}
		// The warning: a ring of tremor running out over the ground.
		float ring = 1.0 + warn * 0.8;
		if (warn > 0.0 && !erupting && abs(d - ring) < 0.09 && hash12(pixel + floor(time * 12.0)) < 0.7) {
			color = mix(color, PAL[ASH + 3], 0.7);
		}
	}
	return color;
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size);
	vec2 world = (pixel + 0.5) * texel_size;
	vec2 np = pixel + noise_offset;
	float edge = summit_sd(world) / texel_size;
	if (edge < 0.0) {
		COLOR = front_slope(pixel, np);
	} else {
		float lava = lava_depth(world) / texel_size;
		vec3 color;
		if (lava >= 0.0) {
			// Is there rock just above? Then this is its face, lit by the lava below it.
			float above = 0.0;
			bool rim_above = false;
			for (int k = 1; k <= 5; k++) {
				vec2 up = world - vec2(0.0, float(k) * texel_size);
				if (lava_depth(up) < 0.0) {
					above = float(k);
					rim_above = lake_sd(up) < 0.0;
					break;
				}
			}
			float wall = 3.0 + floor(value_noise(vec2(pixel.x / 11.0, 4.2)) * 2.99);
			if (above > 0.0 && rim_above && above <= wall) {
				color = crater_wall(pixel, np, above, wall);
			} else if (above > 0.0 && !rim_above && above <= 2.0) {
				color = above < 1.5 ? PAL[CRUST] : PAL[LAVA];
			} else if (rim_above && above > 0.0 && above <= wall + 1.0) {
				color = PAL[LAVA + 3];
			} else {
				color = crater_lava(pixel, np, lava, world);
			}
		} else {
			vec4 field = field_at(pixel);
			float g = floor(field.g * 255.0 + 0.5);
			float a = floor(field.a * 255.0 + 0.5);
			float magma = 0.0;
			if (lake_sd(world) > 0.0) {
				// On an anchor its joints glow near the lava.
				for (int i = 0; i < 4; i++) {
					if (i >= anchor_count) {
						break;
					}
					float inside = anchor_sd(i, world) / texel_size;
					if (inside > 0.0) {
						magma = clamp(1.0 - inside / 18.0, 0.0, 1.0) * 0.85 + 0.12;
					}
				}
			}
			color = bare_ground(pixel, np, magma);
			if (edge < 3.0 && (3.0 - edge) / 3.0 * 64.0 > bayer(pixel) + 44.0) {
				// Loose scree near the edge.
				color = hash12(np) < 0.5 ? ramp(SCREE, 3, hash12(np * 3.1), pixel) : PAL[CINDER];
			}
			if (a > 0.5 && a < 100.5) {
				float s = a / 100.0;
				float n = value_noise(np / 5.0 + 7.0) * 0.7 + value_noise(np / 2.0) * 0.3;
				if (n < s * 1.2 - 0.1) {
					color = ramp(SULFUR, 4, 0.25 + s * 0.45 + (hash12(np * 1.9) - 0.5) * 0.3, pixel);
					if (hash12(np * 3.3) < 0.03) {
						color = PAL[SULFUR + 3];
					}
				} else if (n < s * 1.2) {
					color = PAL[SULFUR];
				}
			}
			float road = g / 64.0;
			if (road < 1.0) {
				color = flow_color(pixel, np, road);
			}
			color = geyser_mouth(color, pixel, np);
			if (lava > -1.0) {
				color = PAL[CRUST];
			} else if (lava > -6.0) {
				float warm = (6.0 + lava) / 6.0;
				if (warm * 16.0 > bayer(pixel) + 0.5) {
					color = mix(color, SCORCH, 0.5);
				}
			}
			if (edge < 1.0) {
				// The summit's outline against the depths: the south lip is lit, the rest
				// is a dark line.
				vec2 out_dir = normalize(world - lake_center);
				color = out_dir.y > 0.35 ? PAL[BASALT + 3] : PAL[BASALT];
			}
		}
		COLOR = vec4(color, 1.0);
	}
}
