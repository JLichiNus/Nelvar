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

const int BASALT = 0;   // 5
const int ASH = 5;      // 4
const int CINDER = 9;   // 3
const int FLOW = 12;    // 4
const int LAVA = 16;    // 6
const int CRUST = 22;   // 3
const int SULFUR = 25;  // 4
const int PLATE = 29;   // 3
const int PEBBLE = 32;  // 2
const int GLOSS = 34;
const int FLOW_EDGE = 35;
const int SCREE = 36;   // 3
const vec3 PAL[39] = vec3[39](
	vec3(40.0, 28.0, 32.0) / 255.0, vec3(54.0, 38.0, 40.0) / 255.0, vec3(70.0, 50.0, 50.0) / 255.0,
	vec3(88.0, 64.0, 60.0) / 255.0, vec3(110.0, 82.0, 74.0) / 255.0,
	vec3(78.0, 72.0, 74.0) / 255.0, vec3(98.0, 90.0, 90.0) / 255.0, vec3(122.0, 114.0, 110.0) / 255.0,
	vec3(150.0, 142.0, 134.0) / 255.0,
	vec3(76.0, 36.0, 32.0) / 255.0, vec3(100.0, 48.0, 38.0) / 255.0, vec3(126.0, 64.0, 46.0) / 255.0,
	vec3(30.0, 22.0, 26.0) / 255.0, vec3(42.0, 32.0, 36.0) / 255.0, vec3(58.0, 44.0, 48.0) / 255.0,
	vec3(82.0, 64.0, 66.0) / 255.0,
	vec3(118.0, 26.0, 20.0) / 255.0, vec3(170.0, 44.0, 24.0) / 255.0, vec3(214.0, 80.0, 32.0) / 255.0,
	vec3(246.0, 132.0, 52.0) / 255.0, vec3(255.0, 196.0, 96.0) / 255.0, vec3(255.0, 238.0, 164.0) / 255.0,
	vec3(42.0, 22.0, 24.0) / 255.0, vec3(66.0, 30.0, 28.0) / 255.0, vec3(96.0, 40.0, 32.0) / 255.0,
	vec3(150.0, 124.0, 34.0) / 255.0, vec3(204.0, 176.0, 54.0) / 255.0, vec3(236.0, 214.0, 92.0) / 255.0,
	vec3(250.0, 240.0, 160.0) / 255.0,
	vec3(46.0, 38.0, 42.0) / 255.0, vec3(66.0, 54.0, 58.0) / 255.0, vec3(92.0, 76.0, 76.0) / 255.0,
	vec3(62.0, 46.0, 46.0) / 255.0, vec3(132.0, 120.0, 114.0) / 255.0,
	vec3(150.0, 136.0, 140.0) / 255.0,
	vec3(20.0, 14.0, 18.0) / 255.0,
	vec3(64.0, 38.0, 36.0) / 255.0, vec3(84.0, 52.0, 46.0) / 255.0, vec3(106.0, 70.0, 58.0) / 255.0
);
// Beyond the foot the land fades towards this dark smoky red.
const vec3 HAZE = vec3(74.0, 44.0, 44.0) / 255.0;
// The ridges' cast shadow.
const vec3 MOUNTAIN_SHADE = vec3(0.62, 0.56, 0.62);
// Ground warmed by lava or magma nearby.
const vec3 SCORCH = vec3(120.0, 44.0, 28.0) / 255.0;
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

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

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash12(i);
	float b = hash12(i + vec2(1.0, 0.0));
	float c = hash12(i + vec2(0.0, 1.0));
	float d = hash12(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

float fbm(vec2 p) {
	return (value_noise(p) * 0.5 + value_noise(p * 2.0 + 17.0) * 0.25
		+ value_noise(p * 4.0 + 41.0) * 0.125) / 0.875;
}

float bayer(vec2 pixel) {
	vec2 m = mod(pixel, 4.0);
	return BAYER[int(m.y) * 4 + int(m.x)];
}

vec3 ramp(int start, int count, float level, vec2 pixel) {
	float t = clamp(level, 0.0, 0.9999) * float(count - 1);
	int i = int(t);
	if ((t - float(i)) * 16.0 > bayer(pixel) + 0.5) {
		i += 1;
	}
	return PAL[start + i];
}

// Cells of a cracked surface: distance to the nearest cell's point (x), how far from
// the crack between two cells (y), and the nearest cell's own random value (z).
vec3 cells(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	float d1 = 8.0;
	float d2 = 8.0;
	float id = 0.0;
	for (int y = -1; y <= 1; y++) {
		for (int x = -1; x <= 1; x++) {
			vec2 o = vec2(float(x), float(y));
			vec3 h = hash32(i + o);
			vec2 r = o + h.xy * 0.8 + 0.1 - f;
			float d = dot(r, r);
			if (d < d1) {
				d2 = d1;
				d1 = d;
				id = h.z;
			} else if (d < d2) {
				d2 = d;
			}
		}
	}
	return vec3(sqrt(d1), sqrt(d2) - sqrt(d1), id);
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

// Slow breathing of everything molten, a little different from place to place.
float pulse(vec2 np) {
	return 0.5 + 0.5 * sin(time * 1.3 + value_noise(np * 0.02) * 9.0);
}

float rocky_at(vec2 np, float foot) {
	if (foot <= 0.0) {
		return 0.0;
	}
	return foot + (value_noise(np / 7.0 + 23.0) - 0.5) * 0.3 + (fbm(np * 0.05) - 0.5) * 0.2;
}

// The bare ground of the basin: basalt with cooling joints, ash fields with ripples,
// red cinder, pebbles and flecks.
vec3 bare_ground(vec2 pixel, vec2 np, float magma) {
	float h = hash12(np * 1.37 + 7.1);
	float level = 0.5 + (fbm(np * vec2(0.02, 0.03)) - 0.5) * 0.6 + (value_noise(np * 0.13) - 0.5) * 0.15;
	vec3 color = ramp(BASALT, 5, level, pixel);
	float ash = fbm(np * vec2(0.010, 0.016) + 31.0) + (value_noise(np * 0.2) - 0.5) * 0.06;
	float cinder = value_noise(np / 90.0 + 51.0);
	vec3 joint = cells(np / 9.0);
	bool on_ash = (ash - 0.56) * 160.0 > bayer(pixel) + 0.5;
	if (on_ash) {
		// Ash drifts in ripples across the wind.
		float ripple = fract(np.y * 0.2 + np.x * 0.04 + value_noise(np * vec2(0.03, 0.015)) * 4.0);
		float a = 0.45 + (value_noise(np * 0.07) - 0.5) * 0.3;
		if (ripple < 0.12) {
			a += 0.3;
		} else if (ripple < 0.2) {
			a -= 0.25;
		}
		color = ramp(ASH, 4, a, pixel);
		if (h < 0.008) {
			color = PAL[PEBBLE];
		}
	} else {
		if ((cinder - 0.74) * 160.0 > bayer(pixel) + 0.5) {
			color = ramp(CINDER, 3, level + (cinder - 0.74) * 1.5, pixel);
		}
		// Cooling joints show where the basalt lies bare, not everywhere.
		float bare = value_noise(np / 46.0 + 77.0);
		if (joint.y < 0.045 + magma * 0.06 && (bare > 0.42 || magma > 0.0)) {
			color = magma > 0.0 ? PAL[BASALT] : mix(color, PAL[BASALT], 0.6);
			if (magma > 0.0) {
				// Magma underneath: the joints glow, brighter where the field is deepest.
				float glow = magma * (0.6 + 0.4 * pulse(np + joint.z * 50.0));
				if (glow * 16.0 > bayer(pixel) + 0.5 + (1.0 - joint.y / 0.11) * 2.0) {
					color = ramp(LAVA, 6, 0.15 + glow * 0.55 - joint.y * 2.0, pixel);
				}
			}
		} else if (magma > 0.0) {
			// The plates between hot joints: darker, with a warm edge.
			color = mix(color, PAL[BASALT], magma * 0.5);
			if (joint.y < 0.12 && magma > 0.3) {
				color = mix(color, SCORCH, 0.4);
			}
		}
		if (h < 0.006) {
			color = PAL[PEBBLE + int(hash12(np * 0.7) * 1.99)];
		} else if (h > 0.9975) {
			color = PAL[ASH + 3];
		}
	}
	return color;
}

// Black plates with glowing seams (islands, crossings).
vec3 plates(vec2 pixel, vec2 np, float lava) {
	vec3 c = cells(np / 6.0);
	float lit = 0.45 + (c.z - 0.5) * 0.5 + (value_noise(np * 0.3) - 0.5) * 0.2;
	vec3 color = ramp(PLATE, 3, lit, pixel);
	if (c.y < 0.07) {
		float glow = 0.5 + 0.5 * sin(time * 1.7 + c.z * 20.0);
		color = glow > 0.55 ? PAL[LAVA + 3] : PAL[LAVA + 2];
	} else if (c.y < 0.12) {
		color = PAL[LAVA];
	}
	if (lava > -1.5) {
		color = PAL[LAVA + 4];
	}
	return color;
}

// Lava: crust drifting with the flow (or churning slowly in a lake), bright seams
// between the floes, a hot rim at the shore, bubbles bursting now and then.
vec3 lava_color(vec2 pixel, vec2 np, float depth, float way) {
	vec2 q = np;
	if (way < 254.5) {
		float angle = way / 254.0 * 6.2831853;
		q -= vec2(cos(angle), sin(angle)) * time * 4.0;
	} else {
		q += vec2(sin(time * 0.13 + np.y * 0.02), cos(time * 0.11 + np.x * 0.02)) * 3.0
			+ vec2(time * 0.5, time * 0.2);
	}
	vec3 floe = cells(q / 7.0);
	float heat = clamp(depth / 14.0, 0.0, 1.0);
	float t = 0.28 + heat * 0.24 + (value_noise(q * 0.12) - 0.5) * 0.36;
	vec3 color = ramp(LAVA, 6, t, pixel);
	if (floe.z < 0.48 && floe.y > 0.1) {
		// A floe of crust, red at its edge.
		color = floe.y < 0.17 ? PAL[LAVA + 1] : ramp(CRUST, 3, 0.3 + floe.z, pixel);
	} else if (floe.y < 0.05) {
		color = PAL[LAVA + 4];
	}
	if (hash12(floor(np / 3.0) + floor(time * 1.4) * 7.0) < 0.003) {
		color = PAL[LAVA + 5];
	}
	if (depth < 1.0) {
		color = PAL[LAVA + 3];
	}
	return color;
}

// Roads of cooled lava: black and glossy, wrinkled into ropes, glowing in a crack here
// and there.
vec3 flow_color(vec2 pixel, vec2 np, float road) {
	vec3 color = ramp(FLOW, 4, 0.35 + (value_noise(np * 0.3) - 0.5) * 0.3, pixel);
	float rope = fract(value_noise(np * vec2(0.08, 0.11) + 3.0) * 6.0);
	if (rope < 0.12) {
		color = PAL[FLOW + 3];
	} else if (rope < 0.19) {
		color = PAL[FLOW];
	}
	float h = hash12(np * 2.17);
	if (h < 0.006) {
		color = PAL[GLOSS];
	}
	if (road < 0.6 && abs(value_noise(np * 0.05 + 9.0) - 0.5) < 0.008) {
		color = pulse(np) > 0.5 ? PAL[LAVA + 2] : PAL[LAVA + 1];
	}
	if (road > 0.84) {
		color = PAL[FLOW_EDGE];
	}
	return color;
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
