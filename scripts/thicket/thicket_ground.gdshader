shader_type canvas_item;
render_mode unshaded;

// The floor of the giant forest (Земля 2) under the player the size of a beetle: forest
// litter in broad patches with pine needles as long as a stick (thick under a pine),
// grains of soil the size of pebbles, cushions of moss and
// white threads of mycelium on the damp ground, now and then the glistening trail of a
// snail; brighter mossy ground on the clearings; the ant trails worn bare; churned soil
// and rootlets along the roots, their shade, the giants' long shadows down and to the left;
// ponds with a steep clay north bank and a mossy south one; amber pools of resin with
// bubbles; dark loose earth crumbling at its edge, cracks under a player who stands on it,
// pits gone through; the tunnel's floor of rotten wood; beyond the floor's edge the ring's
// tangled roots running into the dark, and on the south side a low bank of roots and ferns.
//
// Runs through NelvarCloudSea with parallax 1: one fragment per art pixel of the world grid.
// NelvarThicketField supplies the floor map (ponds, trails, roots) and the coarse light map
// (sun, damp, loose earth, resin); the floor's outline is NelvarEarthData.Radial again.

uniform vec2 base_pixel;
uniform vec2 sea_size;
uniform float breath_time = 0.0;
uniform float hole_amount = 0.0;
uniform vec2 seed_offset;

uniform float texel_size = 4.0;
uniform float time = 0.0;
uniform vec2 noise_offset;
uniform sampler2D field_tex : filter_nearest, repeat_disable;
uniform vec2 field_origin;
uniform vec2 field_size;
uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 light_origin;            // art pixel of the light map's first texel's corner
uniform vec2 light_size = vec2(0.0);
uniform float light_scale = 4.0;
uniform vec2 valley_center;
uniform vec2 valley_axes = vec2(2300.0, 1900.0);
uniform float valley_amp[6];
uniform float valley_phase[6];
// The giants: centre (world), radius, kind (0 oak, 1 pine, 2 birch, 3 dead); their seen height.
uniform vec4 giants[24];
uniform float giant_height[24];
uniform int giant_count = 0;
// The fallen giant: start, axis, length, outer half thickness, tunnel half width (0: none).
uniform vec2 fallen_start;
uniform vec2 fallen_axis = vec2(1.0, 0.0);
uniform vec3 fallen_size = vec3(0.0);
// The damp hollow the root plate was torn from: centre, radius (world).
uniform vec3 plate_pit = vec3(0.0, 0.0, 0.0);
// Pits gone through the loose earth: centre, radius (world), age (s).
uniform vec4 pits[24];
uniform int pit_count = 0;
// Cracks spreading under the player on loose earth: centre (world), stage 0..1, reach.
uniform vec4 crack = vec4(0.0);

const vec3 LITTER[5] = vec3[5](vec3(46.0, 38.0, 28.0) / 255.0, vec3(64.0, 52.0, 36.0) / 255.0,
	vec3(84.0, 68.0, 44.0) / 255.0, vec3(106.0, 88.0, 56.0) / 255.0, vec3(130.0, 110.0, 70.0) / 255.0);
const vec3 MOSS[4] = vec3[4](vec3(44.0, 70.0, 36.0) / 255.0, vec3(62.0, 94.0, 44.0) / 255.0,
	vec3(86.0, 120.0, 54.0) / 255.0, vec3(114.0, 148.0, 66.0) / 255.0);
const vec3 SUNNY[5] = vec3[5](vec3(62.0, 98.0, 46.0) / 255.0, vec3(82.0, 124.0, 54.0) / 255.0,
	vec3(108.0, 150.0, 64.0) / 255.0, vec3(138.0, 176.0, 78.0) / 255.0, vec3(172.0, 200.0, 100.0) / 255.0);
const vec3 TRAIL[4] = vec3[4](vec3(98.0, 78.0, 54.0) / 255.0, vec3(124.0, 100.0, 70.0) / 255.0,
	vec3(150.0, 124.0, 88.0) / 255.0, vec3(176.0, 150.0, 108.0) / 255.0);
const vec3 WATER[4] = vec3[4](vec3(20.0, 42.0, 36.0) / 255.0, vec3(28.0, 58.0, 46.0) / 255.0,
	vec3(40.0, 78.0, 58.0) / 255.0, vec3(58.0, 102.0, 74.0) / 255.0);
const vec3 CLAY[3] = vec3[3](vec3(92.0, 66.0, 44.0) / 255.0, vec3(124.0, 92.0, 62.0) / 255.0, vec3(156.0, 122.0, 84.0) / 255.0);
const vec3 RESIN[4] = vec3[4](vec3(122.0, 62.0, 10.0) / 255.0, vec3(178.0, 102.0, 20.0) / 255.0,
	vec3(222.0, 152.0, 42.0) / 255.0, vec3(250.0, 208.0, 112.0) / 255.0);
const vec3 LOOSE[3] = vec3[3](vec3(34.0, 24.0, 18.0) / 255.0, vec3(52.0, 38.0, 28.0) / 255.0, vec3(74.0, 56.0, 40.0) / 255.0);
const vec3 NEEDLE[3] = vec3[3](vec3(112.0, 56.0, 30.0) / 255.0, vec3(150.0, 82.0, 42.0) / 255.0, vec3(182.0, 112.0, 58.0) / 255.0);
const vec3 GRAIN[3] = vec3[3](vec3(70.0, 62.0, 52.0) / 255.0, vec3(112.0, 100.0, 86.0) / 255.0, vec3(150.0, 138.0, 118.0) / 255.0);
const vec3 BARK[4] = vec3[4](vec3(40.0, 32.0, 28.0) / 255.0, vec3(62.0, 48.0, 40.0) / 255.0,
	vec3(86.0, 68.0, 52.0) / 255.0, vec3(112.0, 90.0, 68.0) / 255.0);
const vec3 FERN[3] = vec3[3](vec3(32.0, 76.0, 44.0) / 255.0, vec3(48.0, 104.0, 54.0) / 255.0, vec3(80.0, 138.0, 66.0) / 255.0);
const vec3 ROT[3] = vec3[3](vec3(38.0, 26.0, 20.0) / 255.0, vec3(56.0, 40.0, 30.0) / 255.0, vec3(76.0, 56.0, 40.0) / 255.0);
const vec3 HAZE = vec3(18.0, 22.0, 16.0) / 255.0;
const vec3 MYCELIUM = vec3(222.0, 218.0, 200.0) / 255.0;
const vec3 SLIME = vec3(196.0, 214.0, 222.0) / 255.0;
const vec3 GLINT = vec3(196.0, 226.0, 206.0) / 255.0;
const vec3 OUTLINE = vec3(22.0, 18.0, 16.0) / 255.0;
const vec2 SHADOW_DIR = vec2(-0.55, 0.83);
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
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	return (value_noise(p) * 0.5 + value_noise(p * 2.0 + 17.0) * 0.25 + value_noise(p * 4.0 + 41.0) * 0.125) / 0.875;
}

float bayer(vec2 pixel) {
	vec2 m = mod(pixel, 4.0);
	return BAYER[int(m.y) * 4 + int(m.x)];
}

vec3 ramp5(vec3 colors[5], float level, vec2 pixel) {
	float t = clamp(level, 0.0, 0.9999) * 4.0;
	int i = int(t);
	if ((t - float(i)) * 16.0 > bayer(pixel) + 0.5) {
		i += 1;
	}
	return colors[min(i, 4)];
}

vec3 ramp4(vec3 colors[4], float level, vec2 pixel) {
	float t = clamp(level, 0.0, 0.9999) * 3.0;
	int i = int(t);
	if ((t - float(i)) * 16.0 > bayer(pixel) + 0.5) {
		i += 1;
	}
	return colors[min(i, 3)];
}

vec3 ramp3(vec3 colors[3], float level, vec2 pixel) {
	float t = clamp(level, 0.0, 0.9999) * 2.0;
	int i = int(t);
	if ((t - float(i)) * 16.0 > bayer(pixel) + 0.5) {
		i += 1;
	}
	return colors[min(i, 2)];
}

float valley_depth(vec2 world) {
	vec2 offset = world - valley_center;
	float angle = atan(offset.y, offset.x);
	float c = cos(angle);
	float s = sin(angle);
	float radius = valley_axes.x * valley_axes.y
		/ sqrt(valley_axes.y * valley_axes.y * c * c + valley_axes.x * valley_axes.x * s * s);
	float bend = 1.0;
	for (int i = 0; i < 6; i++) {
		bend += valley_amp[i] * cos(float(i + 2) * angle + valley_phase[i]);
	}
	return radius * bend - length(offset);
}

vec4 field_at(vec2 pixel) {
	vec2 f = pixel - field_origin;
	if (f.x < 0.0 || f.y < 0.0 || f.x >= field_size.x || f.y >= field_size.y) {
		return vec4(0.0, 1.0, 0.0, 0.0);
	}
	return texelFetch(field_tex, ivec2(f), 0);
}

vec4 light_at(vec2 pixel) {
	if (light_size.x <= 0.0) {
		return vec4(0.0, 0.0, 0.0, 0.0);
	}
	vec2 uv = (pixel + 0.5 - light_origin) / (light_size * light_scale);
	return texture(light_tex, uv);
}

float pond_depth(vec4 field) {
	return floor(field.r * 255.0 + 0.5) - 128.0;
}

// A pine needle lying in a cell of `cell` pixels: a short line, alpha 0 where there is none.
vec4 needle(vec2 pixel, vec2 np, float cell, float density) {
	vec2 c = floor(np / cell);
	vec3 h = hash32(c + 7.3);
	if (h.x > density) {
		return vec4(0.0);
	}
	vec2 center = c * cell + 1.5 + h.yz * (cell - 3.0);
	vec2 d = np - center;
	float angle = hash12(c + 3.1) * 6.2832;
	vec2 dir = vec2(cos(angle), sin(angle));
	float along = dot(d, dir);
	float across = abs(dot(d, vec2(-dir.y, dir.x)));
	if (abs(along) < 3.5 + h.y * 2.0 && across < 0.6) {
		return vec4(ramp3(NEEDLE, 0.3 + along * 0.08 + h.z * 0.4, pixel), 1.0);
	}
	return vec4(0.0);
}

// Beyond the floor's edge: the ring's tangled roots running into the dark; on the south
// side a low bank of roots overgrown with ferns, then the forest's haze.
vec3 beyond(vec2 pixel, vec2 np, float out_px, vec2 world) {
	vec2 offset = world - valley_center;
	vec2 dir = normalize(offset);
	float along = atan(offset.y, offset.x) * 520.0;
	float south = smoothstep(0.5, 0.75, dir.y);
	// Roots run outwards, wavering; dark gaps between them.
	float strand = value_noise(vec2(along * 0.09 + value_noise(np * 0.03) * 4.0, out_px * 0.05));
	float level = 0.2 + strand * 0.6 - out_px * 0.006;
	vec3 roots = ramp4(BARK, level, pixel);
	if (strand < 0.35) {
		roots = mix(HAZE, BARK[0], 0.5);
	} else if (strand > 0.62 && value_noise(np * 0.11) > 0.55) {
		roots = ramp4(MOSS, level, pixel);
	}
	if (out_px < 1.5) {
		roots = BARK[3];
	}
	// The south bank: lit along its top, ferns over it.
	vec3 bank = roots;
	float bank_width = 26.0;
	if (out_px < bank_width) {
		vec2 cell = floor(np / 7.0);
		vec3 h = hash32(cell);
		vec2 d = np - (cell * 7.0 + 3.5);
		bank = ramp4(BARK, 0.55 - out_px / bank_width * 0.4 + (strand - 0.5) * 0.4, pixel);
		if (h.x < 0.6 && abs(d.x * 0.5 + d.y) < 0.8 + h.y) {
			bank = ramp3(FERN, 0.3 + h.z * 0.6 - out_px / bank_width * 0.3, pixel);
		}
		if (out_px < 2.0) {
			bank = MOSS[3];
		}
	}
	vec3 color = mix(roots, bank, south);
	float far = smoothstep(18.0, 90.0, out_px + (value_noise(np * 0.05) - 0.5) * 20.0);
	if (far * 16.0 > bayer(pixel) + 0.5) {
		color = mix(HAZE, color, 0.35 * (1.0 - far));
	}
	return color;
}

// The giants' long shadows (down and to the left), soft-edged, 0..1.
float giant_shadow(vec2 world) {
	float shade = 0.0;
	for (int i = 0; i < 24; i++) {
		if (i >= giant_count) {
			break;
		}
		vec2 local = world - giants[i].xy;
		float r = giants[i].z;
		float along = dot(local, SHADOW_DIR);
		if (along < 0.0) {
			continue;
		}
		float length_ = giant_height[i] * 0.9;
		float across = abs(dot(local, vec2(-SHADOW_DIR.y, SHADOW_DIR.x)));
		float width = r * (1.0 - along / length_ * 0.25);
		if (along < length_ && across < width + 30.0) {
			float edge = 1.0 - smoothstep(width - 30.0, width + 30.0, across);
			shade = max(shade, edge * (1.0 - smoothstep(length_ * 0.7, length_, along)));
		}
	}
	return shade;
}

// The kind of giant whose crown is over the point (its litter lies here): -1 none.
int crown_kind(vec2 world) {
	int kind = -1;
	float best = 1e9;
	for (int i = 0; i < 24; i++) {
		if (i >= giant_count) {
			break;
		}
		float d = length(world - giants[i].xy) - giants[i].z;
		if (d < 900.0 && d < best) {
			best = d;
			kind = int(giants[i].w + 0.5);
		}
	}
	return kind;
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size);
	vec2 world = (pixel + 0.5) * texel_size;
	vec2 np = pixel + noise_offset;
	float inside = valley_depth(world) / texel_size;
	if (inside < 0.0) {
		COLOR = vec4(beyond(pixel, np, -inside, world), 1.0);
	} else {
		vec4 field = field_at(pixel);
		vec4 light = light_at(pixel);
		float sun = light.r;
		float damp = light.g;
		float loose = (floor(light.b * 255.0 + 0.5) - 128.0) * 2.0;
		float resin = (floor(light.a * 255.0 + 0.5) - 128.0) * 2.0;
		if (light.b == 0.0) {
			loose = -999.0;
		}
		if (light.a == 0.0) {
			resin = -999.0;
		}
		float pond = pond_depth(field);
		float trail = floor(field.g * 255.0 + 0.5) / 64.0;
		float shade = field.b;
		float churned = field.a;
		int kind = crown_kind(world);

		float level = 0.42 + (fbm(np * vec2(0.03, 0.042)) - 0.5) * 0.55 + (value_noise(np * 0.13) - 0.5) * 0.16;
		vec3 color = ramp5(LITTER, level, pixel);
		// Moss on the damp ground, in cushions.
		float moss = damp + (fbm(np * 0.045 + 31.0) - 0.5) * 0.7;
		if (moss > 0.55) {
			float cushion = value_noise(np * 0.22);
			color = ramp4(MOSS, 0.3 + cushion * 0.6 + (moss - 0.55) * 0.5, pixel);
		}
		// The clearings: brighter mossy ground with short grass.
		float open = sun + (value_noise(np * 0.06 + 9.0) - 0.5) * 0.35;
		if (open > 0.45) {
			color = ramp5(SUNNY, 0.35 + (fbm(np * 0.05 + 3.0) - 0.5) * 0.6 + (open - 0.45) * 0.4, pixel);
			if (hash12(np * 1.31) < 0.025) {
				color = SUNNY[4];
			}
		} else {
			// Pine needles in the litter: thick under a pine, a few anywhere.
			vec4 bit = kind == 1 ? needle(pixel, np, 9.0, 0.18 * (1.0 - sun)) : vec4(0.0);
			if (bit.a == 0.0) {
				bit = needle(pixel, np + vec2(4.5, 2.5), 13.0, 0.05);
			}
			if (bit.a > 0.0 && moss < 0.7) {
				color = bit.rgb;
			}
		}
		// Grains of soil like pebbles, seeds, mycelium on the damp, a snail's trail.
		float h = hash12(np * 0.93 + 4.7);
		if (h < 0.006) {
			color = ramp3(GRAIN, hash12(np * 2.1), pixel);
		} else if (h > 0.9975 && sun < 0.5) {
			color = vec3(0.86, 0.8, 0.62);
		}
		if (damp > 0.45 && abs(value_noise(np * 0.07 + 51.0) - 0.5) < 0.012 && value_noise(np * 0.02) > 0.45) {
			color = MYCELIUM;
		}
		float trailmark = abs(value_noise(np * 0.0085 + 77.0) - 0.5);
		if (trailmark < 0.0035 && value_noise(np * 0.004 + 5.0) > 0.62) {
			color = mix(color, SLIME, 0.55);
			if (hash12(pixel + floor(time * 2.0) * 7.0) < 0.06) {
				color = vec3(1.0);
			}
		}
		// Churned soil and rootlets along the roots.
		if (churned > 0.0) {
			float c = churned * (0.6 + value_noise(np * 0.25) * 0.6);
			if (c * 16.0 > bayer(pixel) + 4.0) {
				color = ramp3(LOOSE, 0.4 + value_noise(np * 0.3) * 0.6, pixel);
			}
			vec2 cell = floor(np / 5.0);
			vec3 r = hash32(cell + 19.0);
			if (churned > 0.4 && r.x < 0.35) {
				vec2 d = np - (cell * 5.0 + 2.5);
				if (abs(d.x - d.y * (r.y - 0.5) * 2.0) < 0.5 && abs(d.y) < 2.0) {
					color = OUTLINE;
				}
			}
		}
		// The ant trails: bare packed earth, a few grains, a darker edge.
		if (trail < 1.0) {
			float t = 0.55 - trail * 0.3 + (value_noise(np * 0.35) - 0.5) * 0.4;
			color = ramp4(TRAIL, t, pixel);
			if (trail > 0.84) {
				color = ramp5(LITTER, 0.25, pixel);
			} else if (hash12(np * 2.17) < 0.012) {
				color = GRAIN[1];
			}
		}
		// The tunnel's floor of rotten wood (seen when the trunk over it thins out).
		if (fallen_size.x > 0.0) {
			vec2 local = world - fallen_start;
			float along = dot(local, fallen_axis);
			float across = abs(dot(local, vec2(-fallen_axis.y, fallen_axis.x)));
			if (along > 0.0 && along < fallen_size.x && across < fallen_size.y) {
				color = ramp3(ROT, 0.3 + value_noise(np * 0.2) * 0.5 - across / fallen_size.y * 0.3, pixel);
				if (across > fallen_size.z) {
					color = ramp3(ROT, 0.1, pixel);
				} else if (hash12(np * 1.7) < 0.02) {
					color = vec3(0.62, 0.5, 0.36);
				}
			}
		}
		// The damp hollow the root plate was torn from.
		if (plate_pit.z > 0.0) {
			float d = length((world - plate_pit.xy) / vec2(1.0, 0.8)) / plate_pit.z;
			if (d < 1.0) {
				color = mix(color, ramp3(LOOSE, 0.5 - d * 0.3, pixel), 0.7);
				if (d < 0.55 && value_noise(np * 0.12) > 0.55) {
					color = ramp4(WATER, 0.4, pixel);
				}
			}
		}
		// Resin: glossy amber, bubbles, a bright rim.
		if (resin > 0.0) {
			float glossy = 0.45 + (value_noise(np * 0.06 + time * 0.02) - 0.5) * 0.4 + min(resin, 40.0) / 120.0;
			color = ramp4(RESIN, glossy, pixel);
			vec2 cell = floor(np / 6.0);
			vec3 b = hash32(cell + 41.0);
			vec2 d = np - (cell * 6.0 + 1.5 + b.yz * 3.0);
			if (b.x < 0.25 && dot(d, d) < 1.6) {
				color = d.x + d.y < -0.5 ? RESIN[3] : RESIN[0];
			}
			if (resin < 5.0) {
				color = RESIN[3];
			} else if (resin < 9.0) {
				color = RESIN[0];
			}
		}
		// Loose earth: dark lumpy soil, fine cracks, rootlets; it crumbles at its edge.
		if (loose > -8.0) {
			float lump = value_noise(np * 0.35) * 0.6 + value_noise(np * 0.11) * 0.4;
			vec3 soil = ramp3(LOOSE, lump, pixel);
			if (abs(value_noise(np * 0.09 + 13.0) - 0.5) < 0.02) {
				soil = OUTLINE;
			}
			vec2 cell = floor(np / 7.0);
			vec3 r = hash32(cell + 27.0);
			vec2 d = np - (cell * 7.0 + 3.5);
			if (r.x < 0.25 && abs(d.x + d.y * (r.y - 0.5)) < 0.5 && d.y > -2.0 && d.y < 1.0) {
				soil = vec3(0.47, 0.35, 0.24);
			}
			if (loose > 0.0) {
				color = soil;
			} else if ((loose + 8.0) / 8.0 * 16.0 > bayer(pixel) + 0.5) {
				color = soil;
			}
		}
		// The giants' long shadows (they show most where the sun comes through), the roots'.
		float cast = giant_shadow(world);
		if (cast * 16.0 > bayer(pixel) + 0.5) {
			color *= mix(0.82, 0.62, sun);
		}
		if (shade > 0.0) {
			color *= 1.0 - shade * 0.42;
		}
		// Ponds: dark green water; a steep clay bank on the north, a mossy one on the south.
		if (pond >= 0.0) {
			float above1 = pond_depth(field_at(pixel + vec2(0.0, -1.0)));
			float above3 = pond_depth(field_at(pixel + vec2(0.0, -3.0)));
			float above5 = pond_depth(field_at(pixel + vec2(0.0, -5.0)));
			float depth = min(pond, 16.0) / 16.0;
			color = ramp4(WATER, 0.62 - depth * 0.45 + (value_noise(vec2(np.x * 0.25, np.y)) - 0.5) * 0.3, pixel);
			if (above5 < 0.0) {
				// The north bank's clay face.
				float face = above1 < 0.0 ? 0.0 : (above3 < 0.0 ? 0.5 : 1.0);
				color = ramp3(CLAY, 0.8 - face * 0.6, pixel);
				if (above1 >= 0.0 && above3 >= 0.0 && pond > 4.0) {
					color = ramp4(WATER, 0.1, pixel);
				}
			} else if (pond > 2.0 && mod(pixel.y, 4.0) < 1.0) {
				float run = fract((pixel.x - time * 1.6 + hash12(vec2(pixel.y, 3.1)) * 61.0) / 37.0);
				if (run < 0.12) {
					color = GLINT;
				}
			}
		} else if (pond > -3.0) {
			color = ramp4(MOSS, 0.4, pixel);
		}
		// Cracks spreading under the player on loose earth.
		if (crack.w > 0.0) {
			vec2 local = (world - crack.xy) / texel_size;
			float d = length(local) / (crack.w / texel_size);
			if (d < crack.z * 1.1) {
				float a = atan(local.y, local.x);
				float rays = abs(sin(a * 5.0 + value_noise(local * 0.3) * 3.0));
				if (rays < 0.12 + crack.z * 0.1 || (d < crack.z * 0.35 && hash12(np + floor(time * 8.0)) < crack.z * 0.5)) {
					color = OUTLINE;
				}
			}
		}
		// Pits gone through: the crumbling rim, the north wall with roots in it, then dark.
		for (int i = 0; i < 24; i++) {
			if (i >= pit_count) {
				break;
			}
			vec2 local = (world - pits[i].xy) / texel_size;
			float r = pits[i].z / texel_size;
			float wobble = 1.0 + 0.08 * sin(atan(local.y, local.x) * 5.0 + pits[i].x);
			float d = length(local) / (r * wobble);
			if (d < 1.12) {
				if (d >= 1.0) {
					color = ramp3(LOOSE, 0.85, pixel);
				} else {
					// How far below the north rim this pixel is.
					float rim = -sqrt(max(0.0, r * r * wobble * wobble - local.x * local.x));
					float below = local.y - rim;
					color = below < 4.0 ? ramp3(LOOSE, 0.6 - below * 0.15, pixel) : vec3(0.03, 0.025, 0.02);
					if (below < 4.0 && hash12(floor(np) + 3.0) < 0.15) {
						color = BARK[1];
					}
				}
			}
		}
		COLOR = vec4(color, 1.0);
	}
}
