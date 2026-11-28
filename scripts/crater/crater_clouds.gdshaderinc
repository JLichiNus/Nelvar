// The puffs of the clouds of ash far below the volcano's top. crater_below.gdshader
// draws them; crater_ground.gdshader finds the same puffs to hide the mountain's foot
// behind them. Needs hash12, hash32 and value_noise (fire_common's, or crater_below's
// copies of them).
//
// One field of small and middling puffs on a grid in cloud pixels, all of a size: the
// clouds lie far below, and a bigger puff would look nearer. Rows are staggered by half
// a cell and centres jitter by JITTER of a cell. A puff reaches at most (1.5 - JITTER)
// cells from its cell centre (wobble and breathing included), so a 3x3 neighbourhood
// finds every puff that can cover a pixel.
const vec2 CELL = vec2(26.0, 13.0);
const float JITTER = 0.15;
const float FLAT = 0.6;              // puffs are cut flat below this unit height
const float HOLE_SCALE = 64.0;       // size of the sparse regions, cloud pixels

// Low where the sea is torn open; puffs only grow where it is above `holes`.
float density(vec2 p) {
	return value_noise(p / HOLE_SCALE);
}

// Tests one puff against pixel centre p. A puff sits on its flat
// base, and the puff whose base lies lower is in front: it keeps the best one in
// `best` (xy = position on the puff in unit coordinates, z = 1 when covered, w = the
// puff's half height in cloud pixels) and the middle of its base in `best_foot`.
void try_puff(vec2 p, vec2 cell, float shift, float holes, float breath,
		inout vec4 best, inout float best_base, inout vec2 best_foot) {
	vec3 h = hash32(cell);
	vec2 center = (cell + vec2(0.5 + shift, 0.5) + (h.xy - 0.5) * 2.0 * JITTER) * CELL;
	float thick = density(center);
	if (thick < holes) {
		return;
	}
	float size = mix(0.55, 1.0, h.z);
	// Puffs shrink towards a gap, so its rim stays fluffy.
	size *= mix(0.8, 1.0, smoothstep(holes, holes + 0.16, thick));
	size *= 1.0 + 0.035 * sin(breath * 0.4 + h.x * 6.2832);
	vec2 axes = vec2(1.0, 0.55) * size * CELL.x;
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
		best = vec4(l / edge, 1.0, axes.y);
		best_base = base;
		best_foot = vec2(center.x, base);
	}
}

// The front-most puff covering pixel centre p (as try_puff's `best`) and the middle of
// its base (`foot`, cloud pixels). `holes`: how torn the cover is (0 = solid); `breath`:
// seconds, the puffs swell slowly.
vec4 puff_with_foot(vec2 p, float holes, float breath, out vec2 foot) {
	vec4 best = vec4(0.0);
	float best_base = -1.0e20;
	foot = vec2(0.0);
	float row = floor(p.y / CELL.y);
	for (int j = -1; j <= 1; j++) {
		float r = row + float(j);
		float shift = 0.5 * mod(r, 2.0);
		float column = floor(p.x / CELL.x - shift);
		for (int i = -1; i <= 1; i++) {
			try_puff(p, vec2(column + float(i), r), shift, holes, breath, best, best_base, foot);
		}
	}
	return best;
}

// The front-most puff covering pixel centre p, as puff_with_foot.
vec4 puff_at(vec2 p, float holes, float breath) {
	vec2 foot;
	return puff_with_foot(p, holes, breath, foot);
}
