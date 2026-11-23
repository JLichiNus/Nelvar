shader_type canvas_item;
render_mode unshaded;

// The floor of the earth valley in the palette of the "Земля" menu: broad patches of
// green, tufts of grass bending as gusts run across the meadow, small flowers, worn
// trails with pebbles, ponds with a shaded north bank and drifting glints, darker
// forest floor strewn with leaves under the groves, and beyond the mountain foot
// scree, rock and snowfields.
//
// Runs through NelvarCloudSea with parallax 1 and no drift: one fragment per art
// pixel of the world grid. NelvarEarthField supplies what lies where (ponds, trails,
// crowns); the valley outline is the same function as NelvarEarthData.Radial.

uniform vec2 base_pixel;             // world art pixel at the viewport's top-left corner
uniform vec2 sea_size;               // viewport size in art pixels
uniform float breath_time = 0.0;     // set by NelvarCloudSea; unused here
uniform float hole_amount = 0.0;     // set by NelvarCloudSea; unused here
uniform vec2 seed_offset;            // set by NelvarCloudSea; unused here

uniform float texel_size = 4.0;      // world units per art pixel
uniform float wind_time = 0.0;       // seconds; shared with the swaying plants
uniform vec2 noise_offset;           // a different floor per world
uniform sampler2D field_tex : filter_nearest, repeat_disable;
uniform vec2 field_origin;           // world art pixel of the field's first texel
uniform vec2 field_size;
uniform vec2 valley_center;
uniform vec2 valley_axes = vec2(1750.0, 1500.0);
uniform float valley_amp[6];
uniform float valley_phase[6];

const float TUFT_CELL = 6.0;

// Palettes, dark to light (tools/gen_menu_backgrounds.py, earth()).
const int GRASS = 0;    // 5
const int TUFT = 5;     // 3
const int PATH = 8;     // 4
const int WATER = 12;   // 4
const int ROCK = 16;    // 5
const int SNOW = 21;    // 3
const int SCREE = 24;   // 3
const int FLOWER = 27;  // 4
const int LITTER = 31;  // 3
const int PATH_EDGE = 34;
const int STONE = 35;   // 2
const int GLINT = 37;
const int FOOT_LINE = 38;
const vec3 PAL[39] = vec3[39](
	vec3(52.0, 108.0, 60.0) / 255.0, vec3(68.0, 130.0, 66.0) / 255.0, vec3(88.0, 152.0, 72.0) / 255.0,
	vec3(112.0, 172.0, 80.0) / 255.0, vec3(146.0, 194.0, 96.0) / 255.0,
	vec3(48.0, 104.0, 56.0) / 255.0, vec3(78.0, 146.0, 66.0) / 255.0, vec3(130.0, 186.0, 90.0) / 255.0,
	vec3(120.0, 92.0, 66.0) / 255.0, vec3(150.0, 116.0, 82.0) / 255.0, vec3(178.0, 142.0, 100.0) / 255.0,
	vec3(198.0, 166.0, 120.0) / 255.0,
	vec3(52.0, 104.0, 140.0) / 255.0, vec3(70.0, 132.0, 166.0) / 255.0, vec3(104.0, 168.0, 196.0) / 255.0,
	vec3(160.0, 210.0, 226.0) / 255.0,
	vec3(66.0, 76.0, 94.0) / 255.0, vec3(88.0, 100.0, 116.0) / 255.0, vec3(114.0, 124.0, 138.0) / 255.0,
	vec3(144.0, 152.0, 160.0) / 255.0, vec3(176.0, 182.0, 186.0) / 255.0,
	vec3(176.0, 196.0, 214.0) / 255.0, vec3(214.0, 226.0, 236.0) / 255.0, vec3(244.0, 248.0, 250.0) / 255.0,
	vec3(84.0, 88.0, 92.0) / 255.0, vec3(112.0, 114.0, 112.0) / 255.0, vec3(142.0, 142.0, 132.0) / 255.0,
	vec3(238.0, 222.0, 96.0) / 255.0, vec3(244.0, 244.0, 238.0) / 255.0, vec3(222.0, 120.0, 160.0) / 255.0,
	vec3(150.0, 170.0, 236.0) / 255.0,
	vec3(72.0, 92.0, 46.0) / 255.0, vec3(112.0, 104.0, 52.0) / 255.0, vec3(150.0, 118.0, 60.0) / 255.0,
	vec3(96.0, 128.0, 64.0) / 255.0,
	vec3(110.0, 104.0, 96.0) / 255.0, vec3(168.0, 160.0, 146.0) / 255.0,
	vec3(200.0, 232.0, 240.0) / 255.0,
	vec3(26.0, 50.0, 40.0) / 255.0
);
// NelvarPixelArt.BAYER: the sprites dither with the same matrix.
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

// Same rule as NelvarPixelArt.ramp: dither between neighbouring shades.
vec3 ramp(int start, int count, float level, vec2 pixel) {
	float t = clamp(level, 0.0, 0.9999) * float(count - 1);
	int i = int(t);
	if ((t - float(i)) * 16.0 > bayer(pixel) + 0.5) {
		i += 1;
	}
	return PAL[start + i];
}

// NelvarEarthData.Radial.signed_distance for the valley: positive inside, world units.
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
		return vec4(0.0, 1.0, 0.0, 1.0);
	}
	return texelFetch(field_tex, ivec2(f), 0);
}

float pond_depth(vec4 field) {
	return floor(field.r * 255.0 + 0.5) - 128.0;
}

// The wind over the valley (NelvarEarthMain.gust): gusts run from the left.
float gust(vec2 world) {
	return 0.65 * sin(world.x * 0.0045 + world.y * 0.0012 - wind_time * 1.5)
		+ 0.35 * sin(world.x * 0.011 - world.y * 0.006 - wind_time * 2.4);
}

// Beyond the mountain foot: scree, then rock in strata, snowfields further out.
vec3 massif(vec2 pixel, vec2 np, float beyond) {
	float n = fbm(np * 0.03);
	float strata = value_noise(vec2(np.x * 0.02, np.y * 0.22));
	float level = 0.45 + (n - 0.5) * 0.7 + (strata - 0.5) * 0.3 + (hash12(np) - 0.5) * 0.1;
	vec3 color = ramp(ROCK, 5, level, pixel);
	float snow = fbm(np * 0.016 + 5.3) + beyond / 140.0;
	if (snow > 0.92) {
		color = ramp(SNOW, 3, level + 0.25, pixel);
	}
	if (beyond < 7.0) {
		float h = hash12(np * 1.7);
		color = h < 0.55 ? ramp(SCREE, 3, hash12(np * 3.1), pixel) : ramp(GRASS, 5, 0.12, pixel);
	}
	if (beyond < 1.0) {
		color = PAL[FOOT_LINE];
	}
	return color;
}

// One tuft of three blades per cell (where there is one): the top pixel of the taller
// blades leans with the passing gust. Returns the blade colour, or alpha 0.
vec4 tuft(vec2 pixel, float density) {
	vec2 cell = floor(pixel / TUFT_CELL);
	vec3 h = hash32(cell + noise_offset * 0.37);
	if (h.x >= density) {
		return vec4(0.0);
	}
	vec2 base = vec2(cell.x * TUFT_CELL + 1.0 + floor(h.y * 4.0), cell.y * TUFT_CELL + 4.0 + floor(h.z * 2.0));
	vec2 q = pixel - base;
	if (q.y > 0.0 || q.y < -4.0) {
		return vec4(0.0);
	}
	int k = int(-q.y);
	float g = gust((base + 0.5) * texel_size);
	int sway = g > 0.45 ? 1 : (g < -0.85 ? -1 : 0);
	for (int b = -1; b <= 1; b++) {
		int height = 2 + int(fract(h.z * float(7 + b * 3)) * 2.0) + (b == 0 ? 1 : 0);
		if (k >= height) {
			continue;
		}
		int x = b + (b * k) / 3 + ((k == height - 1 && height >= 3) ? sway : 0);
		if (int(q.x) == x) {
			int shade = k == height - 1 ? 2 : (k > height / 2 ? 1 : 0);
			return vec4(PAL[TUFT + shade], 1.0);
		}
	}
	return vec4(0.0);
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size);
	vec2 world = (pixel + 0.5) * texel_size;
	vec2 np = pixel + noise_offset;
	float inside = valley_depth(world) / texel_size;
	vec3 color;
	if (inside < 0.0) {
		color = massif(pixel, np, -inside);
	} else {
		vec4 field = field_at(pixel);
		float pond = pond_depth(field);
		float trail = floor(field.g * 255.0 + 0.5) / 64.0;
		float shade = field.b;
		float meadow = smoothstep(0.56, 0.74, value_noise(np / 70.0 + 13.7)) * (1.0 - shade);
		float level = 0.58 + (fbm(np * vec2(0.022, 0.034)) - 0.5) * 0.7
			+ (value_noise(np * 0.11) - 0.5) * 0.16 + meadow * 0.08 - shade * 0.42
			- (1.0 - smoothstep(0.0, 26.0, inside)) * 0.3;
		if (trail < 1.35) {
			level -= 0.1;
		}
		color = ramp(GRASS, 5, level, pixel);
		// Leaves under the crowns; flowers, thickest in the meadows.
		float h = hash12(np * 1.37 + 7.1);
		if (shade > 0.2 && h < shade * 0.1) {
			color = PAL[LITTER + int(hash12(np * 0.71) * 2.99)];
		} else {
			float bloom = (0.0012 + meadow * 0.014) * (1.0 - shade);
			if (h < bloom) {
				color = PAL[FLOWER + int(hash12(np * 0.53 + 3.0) * 3.99)];
			} else if (hash12((np + vec2(0.0, 1.0)) * 1.37 + 7.1) < bloom) {
				// The lit top of a flower one pixel below.
				color = mix(PAL[FLOWER + int(hash12((np + vec2(0.0, 1.0)) * 0.53 + 3.0) * 3.99)], vec3(1.0), 0.35);
			}
		}
		if (trail > 1.4 && pond < -3.0 && inside > 4.0) {
			// Tufts gather in patches; between them the grass is short.
			float patches = smoothstep(0.3, 0.7, value_noise(np / 23.0 + 71.0));
			vec4 blade = tuft(pixel, (0.06 + patches * 0.36 + meadow * 0.3) * (1.0 - shade * 0.7));
			if (blade.a > 0.0) {
				color = blade.rgb;
			}
		}
		// Pebbles at the mountain foot.
		if (inside < 5.0 && hash12(np * 2.3) < (1.0 - inside / 5.0) * 0.5) {
			color = ramp(SCREE, 3, hash12(np * 3.1), pixel);
		}
		if (trail < 1.0) {
			float t = 0.6 - trail * 0.35 + (value_noise(np * 0.4) - 0.5) * 0.5;
			color = ramp(PATH, 4, t, pixel);
			if (trail > 0.82) {
				color = PAL[PATH_EDGE];
			}
			float stone = hash12(np * 2.17);
			if (stone < 0.025) {
				color = PAL[STONE];
			} else if (stone < 0.04) {
				color = PAL[STONE + 1];
			}
		}
		if (pond >= 0.0) {
			float above = pond_depth(field_at(pixel + vec2(0.0, -1.0)));
			float above2 = pond_depth(field_at(pixel + vec2(0.0, -2.0)));
			float depth = min(pond, 14.0) / 14.0;
			float t = 0.66 - depth * 0.4 + (value_noise(vec2(np.x * 0.3, np.y)) - 0.5) * 0.3;
			color = ramp(WATER, 4, t, pixel);
			if (above < 0.0) {
				color = PAL[WATER];
			} else if (above2 < 0.0) {
				color = ramp(WATER, 4, t - 0.3, pixel);
			} else if (pond > 2.0 && mod(pixel.y, 4.0) < 1.0) {
				// Short glints drifting across the surface.
				float run = fract((pixel.x - wind_time * 2.5 + hash12(vec2(pixel.y, 3.1)) * 61.0) / 29.0);
				if (run < 0.16) {
					color = PAL[GLINT];
				}
			}
			if (hash12(pixel + floor(wind_time * 1.5) * 13.0) < 0.0015 && pond > 2.0) {
				color = vec3(1.0);
			}
		} else if (pond > -2.0) {
			// The damp, shaded bank.
			color *= 0.7;
		} else if (pond > -4.0 && bayer(pixel) < 8.0) {
			color *= 0.84;
		}
	}
	COLOR = vec4(color, 1.0);
}
