shader_type canvas_item;
render_mode unshaded;

// The floor of the fire forge in the palette of the "Огонь" menu: dark basalt cracked
// into cooling joints, fields of grey ash rippled by the wind, red cinder, pebbles and
// flecks; roads of cooled lava, black and glossy with ropy wrinkles; fissures where
// magma glows (the active ones flare before they erupt); magma fields whose joints
// glow; yellow sulfur round the vents; lava — lakes churning slowly under drifting
// crust, streams running along their course — with a hot rim at the shore and a dark
// bank on the north side; islands and crossings of black plates with glowing seams.
// Beyond the ridges' foot the land runs on, darker and hazier: terraces of basalt and
// ash with rivers of lava winding through them.
//
// Runs through NelvarCloudSea with parallax 1 and no drift: one fragment per art pixel
// of the world grid. NelvarFireField supplies what lies where; the basin's outline is
// the same function as NelvarEarthData.Radial.

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
uniform vec2 basin_center;
uniform vec2 basin_axes = vec2(1750.0, 1500.0);
uniform float basin_amp[6];
uniform float basin_phase[6];
uniform sampler2D mountain_tex : filter_linear, repeat_disable;
uniform vec2 mountain_origin;
uniform vec2 mountain_size = vec2(0.0);
uniform float mountain_scale = 4.0;
// Eruptions (NelvarFireMain): world art pixel (xy), radius in art pixels (z) and heat
// (w: up to 1 while it warns, up to 2 as it bursts).
uniform vec4 flares[8];
uniform int flare_count = 0;

// Beyond the foot the land fades towards this dark smoky red.
const vec3 HAZE = vec3(74.0, 44.0, 44.0) / 255.0;
// The ridges' cast shadow.
const vec3 MOUNTAIN_SHADE = vec3(0.62, 0.56, 0.62);

#include "res://scripts/fire/fire_common.gdshaderinc"

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

vec4 field_at(vec2 pixel) {
	vec2 f = pixel - field_origin;
	if (f.x < 0.0 || f.y < 0.0 || f.x >= field_size.x || f.y >= field_size.y) {
		return vec4(0.0, 1.0, 1.0, 0.0);
	}
	return texelFetch(field_tex, ivec2(f), 0);
}

vec2 mountains_at(vec2 pixel) {
	if (mountain_size.x <= 0.0) {
		return vec2(0.0);
	}
	vec2 uv = (pixel + 0.5 - mountain_origin) / (mountain_size * mountain_scale);
	if (uv.x <= 0.0 || uv.y <= 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return vec2(0.0);
	}
	return texture(mountain_tex, uv).rg;
}

float lava_of(vec4 field) {
	return floor(field.r * 255.0 + 0.5) - 128.0;
}

// The strongest eruption over this pixel: 0 none, up to 2 at a burst's heart.
float flare_at(vec2 pixel) {
	float best = 0.0;
	for (int i = 0; i < 8; i++) {
		if (i >= flare_count) {
			break;
		}
		float d = length(pixel - flares[i].xy) / max(flares[i].z, 1.0);
		if (d < 1.0) {
			best = max(best, flares[i].w * (1.0 - d * d));
		}
	}
	return best;
}

float rocky_at(vec2 np, float foot) {
	if (foot <= 0.0) {
		return 0.0;
	}
	return foot + (value_noise(np / 7.0 + 23.0) - 0.5) * 0.3 + (fbm(np * 0.05) - 0.5) * 0.2;
}

// A river of lava out in the land beyond the ridges: above zero in the lava.
float river(vec2 np) {
	float n = value_noise(np / 150.0 + 7.0) * 0.7 + value_noise(np / 50.0 + 3.0) * 0.3;
	return 0.012 - abs(n - 0.5);
}

// Terraces of the land beyond: broad steps with wandering edges.
float terrace(vec2 np) {
	float n = value_noise(np * 0.0032) * 0.7 + value_noise(np * 0.009 + 31.0) * 0.3
		+ (value_noise(np * 0.07 + 5.0) - 0.5) * 0.03;
	return floor(n * 6.0);
}

vec3 outlands(vec2 pixel, vec2 np, float beyond, float foot) {
	float h = hash12(np);
	float rocky = rocky_at(np, foot);
	float t = terrace(np);
	float face = 0.0;
	float height = 0.0;
	bool shaded = false;
	for (int d = 1; d <= 8; d++) {
		float above = terrace(np - vec2(0.0, float(d)));
		if (above > t) {
			height = min(above - t, 2.0) * 3.0 + 1.0;
			if (float(d) <= height) {
				face = float(d);
			} else if (float(d) <= height + 1.0) {
				shaded = true;
			}
			break;
		}
		if (above < t) {
			break;
		}
	}
	// The basin's ground runs on past the foot, turning into the land beyond.
	vec3 color = bare_ground(pixel, np, 0.0);
	float level = 0.45 + (fbm(np * vec2(0.018, 0.028)) - 0.5) * 0.5 + (t - 2.5) * 0.05;
	vec3 far = ramp(BASALT, 5, level - clamp(rocky, 0.0, 1.0) * 0.2, pixel);
	if (value_noise(np / 60.0 + 101.0) > 0.7) {
		far = mix(far, ramp(ASH, 4, level - 0.15, pixel), 0.6);
	}
	if (smoothstep(0.0, 14.0, beyond) * 16.0 > bayer(pixel) + 0.5) {
		color = far;
	}
	bool scree = (rocky - 0.55 - (1.0 - smoothstep(6.0, 30.0, beyond)) * 0.6) * 64.0 > bayer(pixel) + 0.5;
	float lava = beyond > 30.0 ? river(np) : -1.0;
	if (face > 0.0) {
		color = face == 1.0 ? PAL[BASALT + 4] : ramp(BASALT, 5, 0.3 - face / height * 0.3, pixel);
	} else if (lava > 0.0) {
		color = lava > 0.007 ? lava_color(pixel, np, 8.0, 255.0) : PAL[LAVA + 1];
	} else {
		if (lava > -0.01) {
			color = mix(color, SCORCH, 0.45);
		}
		if (scree) {
			color = h < 0.5 ? ramp(SCREE, 3, hash12(np * 3.1), pixel) : PAL[CINDER];
		} else if (h > 0.996) {
			color = PAL[PEBBLE + 1];
		}
		if (shaded) {
			color *= 0.8;
		}
	}
	return mix(color, HAZE, 0.35 * smoothstep(0.0, 40.0, beyond) + smoothstep(40.0, 900.0, beyond) * 0.15);
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size);
	vec2 world = (pixel + 0.5) * texel_size;
	vec2 np = pixel + noise_offset;
	float inside = basin_depth(world) / texel_size;
	vec2 mountains = mountains_at(pixel);
	vec3 color;
	if (inside < 0.0) {
		color = outlands(pixel, np, -inside, mountains.x);
	} else {
		vec4 field = field_at(pixel);
		float lava = lava_of(field);
		float g = floor(field.g * 255.0 + 0.5);
		float crack = floor(field.b * 255.0 + 0.5) / 16.0;
		float a = floor(field.a * 255.0 + 0.5);
		float magma = a > 100.5 && a < 254.5 ? (a - 100.0) / 100.0 : 0.0;
		if (magma > 0.0) {
			// The field's edge wanders.
			magma = clamp(magma * 1.6 - 0.3 + (value_noise(np / 14.0 + 3.0) - 0.5) * 0.6, 0.0, 1.0);
		}
		color = bare_ground(pixel, np, magma);
		float rocky = clamp(rocky_at(np, mountains.x), 0.0, 1.0) * (1.0 - smoothstep(0.0, 16.0, inside));
		if (rocky * 64.0 > bayer(pixel) + 40.0) {
			color = hash12(np) < 0.5 ? ramp(SCREE, 3, hash12(np * 3.1), pixel) : PAL[CINDER];
		}
		if (a > 0.5 && a < 100.5) {
			// Sulfur crusts round the vents, in blotches, with bright crystals.
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
		if (lava < 0.0 && road < 1.0) {
			color = flow_color(pixel, np, road);
		}
		float flare = flare_at(pixel);
		if (crack < 5.0 && lava < -2.0) {
			float p = pulse(np);
			if (crack < 0.55) {
				color = flare > 0.6 ? PAL[LAVA + 5] : (p > 0.5 || flare > 0.2 ? PAL[LAVA + 4] : PAL[LAVA + 3]);
			} else if (crack < 1.3 + flare * 0.9) {
				color = flare > 1.0 ? PAL[LAVA + 4] : (p > 0.3 ? PAL[LAVA + 2] : PAL[LAVA + 1]);
			} else if (crack < 2.2 + flare * 0.6) {
				color = PAL[BASALT];
			} else {
				float warm = (5.0 - crack) / 5.0 * (0.25 + 0.15 * p + flare * 0.25);
				if (warm * 16.0 > bayer(pixel) + 0.5) {
					color = mix(color, SCORCH, 0.45);
				}
			}
		}
		if (a > 254.5) {
			// Plates stand a little proud of the lava: their south side shows as a dark
			// face lit red from below.
			float below = lava_of(field_at(pixel + vec2(0.0, 1.0)));
			float below2 = lava_of(field_at(pixel + vec2(0.0, 2.0)));
			if (below >= 0.0 && lava < -0.5) {
				color = PAL[LAVA];
			} else if (below2 >= 0.0 && lava < -0.5) {
				color = PAL[CRUST];
			} else {
				color = plates(pixel, np, lava);
			}
		} else if (lava >= 0.0) {
			// The north shore's bank: its dark face, then a hot rim, then the lava.
			float above = lava_of(field_at(pixel + vec2(0.0, -1.0)));
			float above2 = lava_of(field_at(pixel + vec2(0.0, -2.0)));
			if (above < 0.0) {
				color = PAL[CRUST];
			} else if (above2 < 0.0) {
				color = PAL[LAVA];
			} else {
				color = lava_color(pixel, np, lava, g);
			}
		} else if (lava > -2.0) {
			color = PAL[CRUST];
		} else if (lava > -6.0) {
			// Ground scorched by the lava beside it.
			float warm = (6.0 + lava) / 6.0;
			if (warm * 16.0 > bayer(pixel) + 0.5) {
				color = mix(color, SCORCH, 0.5);
			}
		}
	}
	if (mountains.y * 16.0 > bayer(pixel) + 0.5) {
		color *= MOUNTAIN_SHADE;
	}
	COLOR = vec4(color, 1.0);
}
