shader_type canvas_item;
render_mode unshaded;

// Sea of clouds far below the islands: the air reality of the main menu seen from
// above. Puffs sit in staggered rows and each lower puff overlaps the one above it;
// every puff is lit like a sphere from the upper right and Bayer-dithered on the
// sea's own pixel grid. Sparse spots leave small gaps where the sky shows through.
//
// The shader runs in a small viewport with one fragment per cloud pixel; cloud_sea.gd
// picks the window of the sea under the camera (parallax and wind drift included) and
// stretches the result over the screen with a sub-pixel offset, so it slides smoothly.

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

// Palettes of the air menu background, dark to light.
const vec3 CLOUD[5] = vec3[5](
	vec3(172.0, 186.0, 222.0) / 255.0,
	vec3(204.0, 214.0, 238.0) / 255.0,
	vec3(230.0, 236.0, 248.0) / 255.0,
	vec3(246.0, 249.0, 254.0) / 255.0,
	vec3(1.0)
);
const vec3 SKY[4] = vec3[4](
	vec3(52.0, 112.0, 196.0) / 255.0,
	vec3(70.0, 140.0, 220.0) / 255.0,
	vec3(96.0, 164.0, 232.0) / 255.0,
	vec3(128.0, 190.0, 240.0) / 255.0
);

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

vec3 ramp_sky(float level, vec2 pixel) {
	float t = clamp(level, 0.0, 0.9999) * 3.0;
	int i = int(t);
	if ((t - float(i)) * 16.0 > bayer4(pixel) * 16.0 + 0.5) {
		i += 1;
	}
	return SKY[i];
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
		color = ramp_cloud(0.3 + 0.55 * lit + grain * 0.1 + tone, pixel);
	} else if (density(p) > hole_amount + 0.03) {
		// A crevice between puffs: cloud in deep shade, not yet the sky.
		color = ramp_cloud(0.1 + tone * 0.5, pixel);
	} else {
		// A gap: the sky far below, darker just under the cloud edge above it.
		float level = 0.85;
		if (puff_at(p + vec2(0.0, -2.0)).z > 0.5) {
			level = 0.08;
		} else if (puff_at(p + vec2(0.0, -5.0)).z > 0.5) {
			level = 0.38;
		} else if (puff_at(p + vec2(0.0, -9.0)).z > 0.5) {
			level = 0.62;
		}
		color = ramp_sky(level, pixel);
	}
	COLOR = vec4(color, 1.0);
}
