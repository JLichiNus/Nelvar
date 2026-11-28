// Shared by the floors of the fire maps (fire_ground.gdshader — the forge — and the
// volcano's crater_ground.gdshader, its islands and lava splashes): the palette of the
// "Огонь" menu, noise, ordered dithering, cracked cells, and the surfaces themselves —
// bare basalt and ash, black plates with glowing seams, lava, roads of cooled lava.
//
// Include it after declaring `uniform float time;` (everything molten moves with it).

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

// Slow breathing of everything molten, a little different from place to place.
float pulse(vec2 np) {
	return 0.5 + 0.5 * sin(time * 1.3 + value_noise(np * 0.02) * 9.0);
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
