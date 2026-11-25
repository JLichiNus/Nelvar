shader_type canvas_item;
render_mode unshaded;

// Clouds of ash far below the volcano's top (NelvarCloudSea, the "Below" layer under the
// transparent floor): the air map's sea of clouds (cloud_sea.gdshader, left as it is)
// in the smoky palette of the "Огонь" menu, lit from the upper right and warmed from
// below. Where the cover tears open the land shows far down: dark basalt with rivers of
// lava glowing through the haze.
//
// It lies deep below the summit: it follows the camera only by its parallax and drifts
// slowly with the wind, so the top of the mountain plainly stands far above it.

uniform vec2 base_pixel;             // sea pixel at the viewport's top-left corner
uniform vec2 sea_size;               // viewport size in sea pixels
uniform float breath_time = 0.0;     // seconds; puffs slowly swell and settle
uniform float hole_amount = 0.14;    // 0 = solid cover; higher tears more and wider gaps
uniform vec2 seed_offset;            // integer pixel offset: a different sea per world

// Two layers of puffs, each on its own grid in cloud pixels: a field of small and
// middling puffs and, over it, sparse big billows. Rows are staggered by half a cell
// and centres jitter by JITTER of a cell. Whole areas of the sea hold more big
// billows or more small fluff. A puff reaches at most (1.5 - JITTER) cells of its own
// grid from its cell centre (wobble and breathing included), so a 3x3 neighbourhood
// of each grid finds every puff that can cover a pixel.
const vec2 CELL = vec2(26.0, 13.0);
const vec2 BIG_CELL = vec2(68.0, 34.0);
const float JITTER = 0.15;
const float REGION_SCALE = 140.0;    // size of the areas of big or small puffs, cloud pixels
const float FLAT = 0.6;              // puffs are cut flat below this unit height
const float HOLE_SCALE = 64.0;       // size of the sparse regions, cloud pixels
const vec3 SUN = vec3(0.4194, -0.5792, 0.6990);

// Ash clouds, dark to light: smoky browns, dim with the distance below.
const vec3 CLOUD[5] = vec3[5](
	vec3(46.0, 36.0, 42.0) / 255.0,
	vec3(62.0, 49.0, 54.0) / 255.0,
	vec3(80.0, 64.0, 66.0) / 255.0,
	vec3(100.0, 82.0, 80.0) / 255.0,
	vec3(122.0, 104.0, 98.0) / 255.0
);
// The land far below: basalt in haze, dark to light.
const vec3 LAND[4] = vec3[4](
	vec3(20.0, 14.0, 18.0) / 255.0,
	vec3(28.0, 20.0, 24.0) / 255.0,
	vec3(38.0, 26.0, 30.0) / 255.0,
	vec3(50.0, 34.0, 36.0) / 255.0
);
// Its rivers of lava, through the haze.
const vec3 RIVER[3] = vec3[3](
	vec3(118.0, 34.0, 22.0) / 255.0,
	vec3(176.0, 62.0, 28.0) / 255.0,
	vec3(214.0, 104.0, 44.0) / 255.0
);
// The glow of the lava below on the clouds' undersides.
const vec3 UNDERGLOW = vec3(104.0, 46.0, 38.0) / 255.0;

// Sine-free hashes stay stable for large cell coordinates.
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

// Ordered 4x4 Bayer threshold in [0, 1).
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

// Same rule as NelvarPixelArt.ramp: dither between neighbouring shades.
vec3 ramp_cloud(float level, vec2 pixel) {
	float t = clamp(level, 0.0, 0.9999) * 4.0;
	int i = int(t);
	if ((t - float(i)) * 16.0 > bayer4(pixel) * 16.0 + 0.5) {
		i += 1;
	}
	return CLOUD[i];
}

vec3 ramp_land(float level, vec2 pixel) {
	float t = clamp(level, 0.0, 0.9999) * 3.0;
	int i = int(t);
	if ((t - float(i)) * 16.0 > bayer4(pixel) * 16.0 + 0.5) {
		i += 1;
	}
	return LAND[i];
}

// A river of lava in the land below: above zero in it.
float river(vec2 p) {
	float n = value_noise(p / 90.0 + 7.0) * 0.7 + value_noise(p / 30.0 + 3.0) * 0.3;
	return 0.018 - abs(n - 0.5);
}

// The land far below where the clouds part.
vec3 land(vec2 p, vec2 pixel) {
	float r = river(p);
	if (r > 0.0) {
		float streak = fract((p.x + p.y * 0.3) / 9.0 - breath_time * 0.25 + value_noise(p / 6.0) * 0.6);
		return r > 0.01 ? (streak < 0.3 ? RIVER[2] : RIVER[1]) : RIVER[0];
	}
	float level = 0.35 + (value_noise(p / 24.0) - 0.5) * 0.5 + (value_noise(p / 5.0) - 0.5) * 0.2;
	vec3 color = ramp_land(level, pixel);
	if (r > -0.025) {
		// The banks glow.
		color = mix(color, RIVER[0], (1.0 - (-r / 0.025)) * 0.35);
	}
	return color;
}

// Low where the sea is torn open; puffs only grow where it is above hole_amount.
float density(vec2 p) {
	return value_noise(p / HOLE_SCALE);
}

// Share of big billows around p: 0 = only small fluff.
float region(vec2 p) {
	return smoothstep(0.2, 0.8, value_noise(p / REGION_SCALE + 17.0));
}

// Tests one puff of the given grid against pixel centre p. A puff sits on its flat
// base, and the puff whose base lies lower is in front: it keeps the best one in
// `best` (xy = position on the puff in unit coordinates, z = 1 when covered).
void try_puff(vec2 p, vec2 cell, vec2 grid, float shift, bool big, inout vec3 best,
		inout float best_base) {
	vec3 h = hash32(cell + (big ? vec2(913.0, 377.0) : vec2(0.0)));
	vec2 center = (cell + vec2(0.5 + shift, 0.5) + (h.xy - 0.5) * 2.0 * JITTER) * grid;
	float thick = density(center);
	float share = region(center);
	float size;
	if (big) {
		// Big billows stand away from the gaps and only in part of the cells.
		if (thick < hole_amount + 0.06 || hash12(cell + 71.0) > mix(0.12, 0.8, share)) {
			return;
		}
		size = mix(0.55, 1.0, h.z);
	} else {
		if (thick < hole_amount) {
			return;
		}
		size = mix(0.55, 1.0, h.z) * mix(0.82, 1.0, share);
	}
	// Puffs shrink towards a gap, so its rim stays fluffy.
	size *= mix(0.8, 1.0, smoothstep(hole_amount, hole_amount + 0.16, thick));
	size *= 1.0 + 0.035 * sin(breath_time * 0.4 + h.x * 6.2832);
	vec2 axes = vec2(1.0, 0.55) * size * grid.x;
	float base = center.y + FLAT * axes.y;
	if (base <= best_base) {
		return;
	}
	vec2 l = (p - center) / axes;
	if (l.y > FLAT) {
		return;
	}
	float angle = atan(l.y, l.x);
	float edge = 1.0 + 0.07 * sin(angle * 5.0 + h.y * 6.2832) + 0.04 * sin(angle * 11.0 + h.z * 6.2832);
	if (length(l) < edge) {
		best = vec3(l / edge, 1.0);
		best_base = base;
	}
}

// The front-most puff of both layers covering pixel centre p.
vec3 puff_at(vec2 p) {
	vec3 best = vec3(0.0);
	float best_base = -1.0e20;
	for (int layer = 0; layer < 2; layer++) {
		bool big = layer == 1;
		vec2 grid = big ? BIG_CELL : CELL;
		float row = floor(p.y / grid.y);
		for (int j = -1; j <= 1; j++) {
			float r = row + float(j);
			float shift = 0.5 * mod(r, 2.0);
			float column = floor(p.x / grid.x - shift);
			for (int i = -1; i <= 1; i++) {
				try_puff(p, vec2(column + float(i), r), grid, shift, big, best, best_base);
			}
		}
	}
	return best;
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size) + seed_offset;
	vec2 p = pixel + 0.5;
	// Broad, soft variation of tone: the sea is not evenly lit everywhere.
	float tone = (value_noise(p / 150.0 + 41.0) - 0.5) * 0.2;
	vec3 puff = puff_at(p);
	vec3 color;
	if (puff.z > 0.5) {
		float nz = sqrt(max(0.0, 1.0 - dot(puff.xy, puff.xy)));
		float lit = dot(vec3(puff.xy, nz), SUN);
		float grain = value_noise(pixel * 0.45) - 0.5;
		color = ramp_cloud(0.22 + 0.5 * lit + grain * 0.08 + tone, pixel);
		// The undersides catch the red of the lava below.
		if (puff.y > 0.35 && (puff.y - 0.35) * 40.0 > bayer4(pixel) * 16.0 + 0.5) {
			color = mix(color, UNDERGLOW, 0.4);
		}
	} else if (density(p) > hole_amount + 0.03) {
		// A crevice between puffs: cloud in deep shade.
		color = ramp_cloud(0.05 + tone * 0.5, pixel);
	} else {
		// A gap: the land far below, in the shadow of the cloud edge above it.
		color = land(p, pixel);
		if (puff_at(p + vec2(0.0, -3.0)).z > 0.5) {
			color *= 0.55;
		} else if (puff_at(p + vec2(0.0, -7.0)).z > 0.5) {
			color *= 0.78;
		}
	}
	COLOR = vec4(color, 1.0);
}
