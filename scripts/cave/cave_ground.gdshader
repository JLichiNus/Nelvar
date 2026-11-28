shader_type canvas_item;
// Disabled blending: the viewport keeps the floor's own alpha, so the translucent tops of
// the walls, the lakes and the chasms let what lies under them (NelvarIceDepths, the
// abyss) show through.
render_mode unshaded, blend_disabled;

// The floor of the ice cave, Лёд 2. The walls are the cave's distance field
// (NelvarCaveData.sdf, sampled bilinearly per art pixel exactly as wall_depth() does, so
// the collision, the logic and this see one boundary): where the floor lies within FACE
// art pixels straight down, the wall shows its south face — layers of blue ice, darker
// to the foot, light running down it, icicles hanging from its lit edge, frost and
// shards at its foot; above it the top of the ice, translucent (the depths show through:
// creatures frozen into the walls), darker the deeper in, a lit rim along its edge. The
// floor: stone in frost, here and there a patch of ice, frost flowers in the cold halls,
// pebbles thicker by the walls; snow under the holes in the roof (with the marks and
// sparkles of ice_common); wet dark stone, puddles and travertine round the geysers;
// smooth ice in the icy passages; frozen lakes as on the valley, murky melting ice,
// black open water with slush and ripples round the bodies floating on it; crevasses and
// snow bridges as on the valley; chasms — the far wall of layered ice dropping into the
// dark, then nothing (the abyss below shows), a ledge of ice on the near edge — and the
// ice arches over them with their shadow on the depth.
//
// Runs through NelvarCloudSea with parallax 1 and no drift: one fragment per art pixel of
// the world grid. NelvarCaveField supplies what lies where; the light is the overlays'.

uniform vec2 base_pixel;             // world art pixel at the viewport's top-left corner
uniform vec2 sea_size;               // viewport size in art pixels
uniform float breath_time = 0.0;     // set by NelvarCloudSea; unused here
uniform float hole_amount = 0.0;     // set by NelvarCloudSea; unused here
uniform vec2 seed_offset;            // set by NelvarCloudSea; unused here

// The walls: signed distance (world units, positive in the ice) per sample.
uniform sampler2D sdf_tex : filter_nearest, repeat_disable;
uniform vec2 sdf_origin;             // world point of sample (0, 0)
uniform vec2 sdf_size;
uniform float sdf_cell = 8.0;
uniform sampler2D field_tex : filter_nearest, repeat_disable;
uniform sampler2D zone_tex : filter_nearest, repeat_disable;
uniform vec2 field_origin;           // world art pixel of the maps' first texel
uniform vec2 field_size;
// NelvarCaveField's light map: R sun, G glow, B warmth, A cold.
uniform sampler2D light_tex : filter_linear, repeat_disable;
uniform vec2 light_origin;
uniform vec2 light_size = vec2(0.0);
uniform float light_scale = 4.0;
// Bodies floating on open water: art pixel, radius (art px), phase.
uniform vec4 ripples[12];
uniform int ripple_count = 0;
// Melting ice giving under the player: art pixel and how far it has given (0..1).
uniform vec3 strain = vec3(0.0);

vec4 field_at(vec2 pixel) {
	vec2 f = pixel - field_origin;
	if (f.x < 0.0 || f.y < 0.0 || f.x >= field_size.x || f.y >= field_size.y) {
		return vec4(0.0);
	}
	return texelFetch(field_tex, ivec2(f), 0);
}

#include "res://scripts/ice/ice_common.gdshaderinc"

const float FACE = 12.0;

// The cave's own shades, dark to light.
const int STONE = 0;     // 5
const int FROST = 5;     // 3
const int WET = 8;       // 4
const int PUDDLE = 12;   // 3
const int TRAV = 15;     // 4
const int TOP = 19;      // 6
const int FACEC = 25;    // 6
const int RIM = 31;
const int MELT = 32;     // 4
const int DEEP = 36;     // 4
const int ARCH = 40;     // 4
const int DROP = 44;     // 6
const int ICY = 50;      // 4
const int CONTOUR = 54;
const vec3 CAVE[55] = vec3[55](
	vec3(46.0, 54.0, 70.0) / 255.0, vec3(62.0, 72.0, 90.0) / 255.0, vec3(80.0, 92.0, 112.0) / 255.0,
	vec3(102.0, 114.0, 134.0) / 255.0, vec3(128.0, 140.0, 158.0) / 255.0,
	vec3(158.0, 178.0, 198.0) / 255.0, vec3(194.0, 212.0, 228.0) / 255.0, vec3(228.0, 240.0, 248.0) / 255.0,
	vec3(46.0, 54.0, 70.0) / 255.0, vec3(60.0, 70.0, 88.0) / 255.0, vec3(78.0, 90.0, 110.0) / 255.0,
	vec3(110.0, 126.0, 146.0) / 255.0,
	vec3(22.0, 36.0, 48.0) / 255.0, vec3(36.0, 60.0, 74.0) / 255.0, vec3(78.0, 112.0, 126.0) / 255.0,
	vec3(138.0, 126.0, 108.0) / 255.0, vec3(176.0, 164.0, 140.0) / 255.0, vec3(210.0, 200.0, 178.0) / 255.0,
	vec3(236.0, 232.0, 218.0) / 255.0,
	vec3(24.0, 40.0, 72.0) / 255.0, vec3(36.0, 58.0, 98.0) / 255.0, vec3(54.0, 84.0, 128.0) / 255.0,
	vec3(78.0, 114.0, 158.0) / 255.0, vec3(110.0, 150.0, 186.0) / 255.0, vec3(146.0, 186.0, 208.0) / 255.0,
	vec3(40.0, 68.0, 112.0) / 255.0, vec3(56.0, 94.0, 144.0) / 255.0, vec3(78.0, 124.0, 174.0) / 255.0,
	vec3(106.0, 156.0, 200.0) / 255.0, vec3(140.0, 190.0, 222.0) / 255.0, vec3(180.0, 220.0, 238.0) / 255.0,
	vec3(222.0, 242.0, 250.0) / 255.0,
	vec3(92.0, 108.0, 118.0) / 255.0, vec3(116.0, 132.0, 140.0) / 255.0, vec3(140.0, 154.0, 160.0) / 255.0,
	vec3(168.0, 180.0, 186.0) / 255.0,
	vec3(14.0, 26.0, 40.0) / 255.0, vec3(22.0, 40.0, 56.0) / 255.0, vec3(34.0, 58.0, 76.0) / 255.0,
	vec3(70.0, 108.0, 126.0) / 255.0,
	vec3(118.0, 168.0, 204.0) / 255.0, vec3(154.0, 202.0, 228.0) / 255.0, vec3(196.0, 230.0, 244.0) / 255.0,
	vec3(236.0, 250.0, 255.0) / 255.0,
	vec3(10.0, 18.0, 38.0) / 255.0, vec3(18.0, 32.0, 60.0) / 255.0, vec3(30.0, 52.0, 88.0) / 255.0,
	vec3(48.0, 80.0, 122.0) / 255.0, vec3(78.0, 118.0, 160.0) / 255.0, vec3(124.0, 168.0, 200.0) / 255.0,
	vec3(126.0, 166.0, 196.0) / 255.0, vec3(152.0, 192.0, 216.0) / 255.0, vec3(182.0, 216.0, 232.0) / 255.0,
	vec3(214.0, 236.0, 246.0) / 255.0,
	vec3(20.0, 26.0, 40.0) / 255.0
);

vec3 cramp(int start, int count, float level, vec2 pixel) {
	float t = clamp(level, 0.0, 0.9999) * float(count - 1);
	int i = int(t);
	if ((t - float(i)) * 16.0 > bayer(pixel) + 0.5) {
		i += 1;
	}
	return CAVE[start + i];
}

vec4 zone_at(vec2 pixel) {
	vec2 f = pixel - field_origin;
	if (f.x < 0.0 || f.y < 0.0 || f.x >= field_size.x || f.y >= field_size.y) {
		return vec4(0.0);
	}
	return texelFetch(zone_tex, ivec2(f), 0);
}

float sdf_sample(ivec2 cell) {
	return texelFetch(sdf_tex, cell, 0).r;
}

// NelvarCaveData.wall_depth at the art pixel's centre: world units, positive in the ice.
float wall_at(vec2 pixel) {
	vec2 f = ((pixel + 0.5) * texel_size - sdf_origin) / sdf_cell;
	vec2 i = floor(f);
	if (i.x < 0.0 || i.y < 0.0 || i.x >= sdf_size.x - 1.0 || i.y >= sdf_size.y - 1.0) {
		return 1000.0;
	}
	vec2 t = f - i;
	ivec2 c = ivec2(i);
	float top = mix(sdf_sample(c), sdf_sample(c + ivec2(1, 0)), t.x);
	float bottom = mix(sdf_sample(c + ivec2(0, 1)), sdf_sample(c + ivec2(1, 1)), t.x);
	return mix(top, bottom, t.y);
}

vec4 light_at(vec2 pixel) {
	if (light_size.x <= 0.0) {
		return vec4(0.0);
	}
	vec2 uv = (pixel + 0.5 - light_origin) / (light_size * light_scale);
	return texture(light_tex, uv);
}

// Slabs (of ice, of the stone floor): a jittered grid of cells, flattened across. x: how near the border with
// the next slab (small on it), y: the slab's own hash.
vec2 slabs(vec2 p, float size) {
	vec2 cell = floor(p / size);
	float best = 1e9;
	float second = 1e9;
	float id = 0.0;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			vec2 center = (c + 0.2 + hash32(c).xy * 0.6) * size;
			float d = length((p - center) * vec2(1.0, 1.5));
			if (d < best) {
				second = best;
				best = d;
				id = hash12(c + 7.0);
			} else if (d < second) {
				second = d;
			}
		}
	}
	return vec2(second - best, id);
}

// The south face of a wall, `down` art pixels above the floor (of `height`).
vec3 face_look(vec2 pixel, float down, float height) {
	float u = (down - 1.0) / max(height - 1.0, 1.0);
	float strata = floor((pixel.y + value_noise(vec2(pixel.x * 0.06, 1.0)) * 4.0) / 3.0);
	float band = (hash12(vec2(strata, floor(pixel.x / 23.0))) - 0.5) * 0.14;
	float streak = (hash12(vec2(pixel.x, 9.1)) - 0.5) * 0.12 + (value_noise(vec2(pixel.x * 0.3, 2.0)) - 0.5) * 0.16;
	vec3 color = cramp(FACEC, 6, 0.18 + u * 0.66 + band + streak, pixel);
	// Icicles hanging from the lit edge, their tips catching the light.
	float from_top = height - down;
	if (hash12(vec2(pixel.x, 4.4)) < 0.34) {
		float reach = 1.0 + floor(hash12(vec2(pixel.x, 7.7)) * 5.0);
		if (from_top >= 1.0 && from_top <= reach) {
			color = from_top == reach ? CAVE[FACEC + 5] : CAVE[FACEC + 4];
		}
	}
	if (down >= height) {
		color = CAVE[RIM];
	} else if (down == 1.0) {
		color = hash12(pixel * 1.3) < 0.45 ? CAVE[FROST + 1] : CAVE[FACEC];
	}
	return color;
}

// The top of the ice, `wall` world units in from its edge: translucent (the creatures
// frozen in it show through), darker inward, broken into slabs with pale cracks between,
// a frozen bubble here and there.
void top_look(vec2 pixel, vec2 np, float wall, inout vec3 color, inout float alpha) {
	float t = clamp(wall / 260.0, 0.0, 1.0);
	vec2 slab = value_noise(np * 0.004 + 8.0) > 0.5 ? slabs(np, 34.0) : slabs(np + 300.0, 24.0);
	float level = 0.96 - t * 0.62 + (slab.y - 0.5) * 0.2 + (fbm(np * 0.03) - 0.5) * 0.14;
	color = cramp(TOP, 6, level, pixel);
	alpha = mix(0.4, 0.7, smoothstep(0.0, 1.0, t));
	// Cracks between the slabs: plain by the edge, fewer and fewer further in.
	float keep = mix(0.75, 0.2, t) * smoothstep(0.25, 0.6, value_noise(np * 0.012 + 40.0));
	if (slab.x < 1.1 && hash12(floor(np / 7.0) + slab.y) < keep) {
		color = CAVE[TOP + 5];
		alpha = max(alpha, 0.66);
	} else if (hash12(np * 1.7) < 0.003) {
		color = CAVE[RIM];
		alpha = 0.9;
	}
}

// The stone floor: in frost (the colder the more), cracked, a patch of ice here and there,
// frost flowers in the cold, pebbles thicker by the walls; wet and dark in the warmth,
// with puddles and travertine by a geyser's mouth.
vec3 stone_look(vec2 pixel, vec2 np, float wall, float cold, float warmth, float sun) {
	vec2 slab = slabs(np, 34.0);
	float level = 0.48 + cold * 0.16 + (fbm(np * 0.022) - 0.5) * 0.36 + (slab.y - 0.5) * 0.14
		+ (value_noise(np * 0.21) - 0.5) * 0.1;
	vec3 color = cramp(STONE, 5, level, pixel);
	float dry = 1.0 - smoothstep(0.05, 0.35, warmth);
	// Cracks between the flags of the floor, here and there.
	if (slab.x < 1.0 && hash12(floor(np / 9.0) + slab.y * 13.0) < 0.45) {
		color = CAVE[STONE];
	}
	// Frost: a fur of rime in patches, dithered at its edge, white specks; more of it in
	// the cold.
	float frost = (0.25 + cold * 0.6) * dry;
	float fur = smoothstep(0.38, 0.8, fbm(np * 0.04 + 31.0) + cold * 0.2) * frost;
	if (fur * 48.0 - 14.0 > bayer(pixel) + 0.5) {
		color = cramp(FROST, 3, 0.15 + fur * 0.6 + (hash12(np) - 0.5) * 0.3, pixel);
	}
	if (hash12(np * 0.91) < frost * 0.05) {
		color = CAVE[FROST + 2];
	}
	// A patch of ice in the dark.
	float patch = value_noise(np / 19.0 + 77.0) * 0.7 + value_noise(np / 7.0) * 0.3;
	if (patch > 0.79 && dry > 0.9) {
		color = cramp(ICY, 4, 0.3 + (value_noise(vec2(np.x * 0.1, np.y * 0.4)) - 0.5) * 0.4, pixel);
		if (patch < 0.805) {
			color = CAVE[FROST + 1];
		} else if (hash12(np * 3.1) < 0.02) {
			color = CAVE[ICY + 3];
		}
	}
	// Frost flowers: little six-armed rosettes in the cold halls.
	vec2 cell = floor(np / 11.0);
	vec3 h = hash32(cell + 3.7);
	if (h.x < cold * 0.12 * dry) {
		vec2 c = cell * 11.0 + 2.0 + floor(h.yz * 7.0);
		vec2 d = np - c;
		if ((abs(d.x) <= 2.0 && d.y == 0.0) || (abs(d.y) <= 1.0 && d.x == 0.0) || (abs(d.x) == 1.0 && abs(d.y) == 1.0)) {
			color = (d.x == 0.0 && d.y == 0.0) ? vec3(1.0) : CAVE[FROST + 2];
		}
	}
	// Pebbles, thicker along the walls as if fallen from them.
	vec2 pcell = floor(np / 5.0);
	vec3 p = hash32(pcell + 9.1);
	if (p.x < 0.035 + 0.2 * (1.0 - smoothstep(0.0, 70.0, -wall))) {
		vec2 at = pcell * 5.0 + floor(p.yz * 4.0);
		vec2 d = np - at;
		if (d.x >= 0.0 && d.x <= 1.0 && d.y == 0.0) {
			color = d.x == 0.0 ? CAVE[STONE + 4] : CAVE[STONE + 1];
		} else if (d.y == 1.0 && d.x >= 0.0 && d.x <= 1.0) {
			color = CAVE[STONE];
		}
	}
	// The warmth: wet stone, puddles, the frost melting at its edge, travertine terraces
	// round the mouth, drips.
	if (warmth > 0.05) {
		float wet = smoothstep(0.04, 0.4, warmth) + (value_noise(np * 0.045 + 3.0) - 0.5) * 0.7
			+ (value_noise(np * 0.2) - 0.5) * 0.15;
		if (wet > 0.5 && value_noise(np * 0.09 + 21.0) > 0.22 + (1.0 - warmth) * 0.25) {
			color = cramp(WET, 4, level + 0.1 + (value_noise(np * 0.12) - 0.5) * 0.3, pixel);
			// The wet sheen: short bright glints.
			if (mod(pixel.y, 5.0) < 1.0 && hash12(floor(np / vec2(4.0, 1.0))) < 0.05) {
				color = CAVE[WET + 3];
			}
		} else if (wet > 0.38) {
			color = mix(color, CAVE[FROST + 1], 0.3);
		}
		float puddle = value_noise(np / 14.0 + 13.0);
		if (warmth > 0.25 && warmth < 0.7 && puddle > 0.64) {
			color = cramp(PUDDLE, 3, 0.4 + (puddle - 0.66) * 2.0, pixel);
			if (mod(pixel.y, 3.0) < 1.0 && fract((pixel.x + time * 1.5 + hash12(vec2(pixel.y, 2.0)) * 20.0) / 13.0) < 0.1) {
				color = CAVE[PUDDLE + 2];
			}
		}
		if (warmth > 0.86 + (value_noise(np * 0.2) - 0.5) * 0.05) {
			float rings = fract(warmth * 22.0 + value_noise(np * 0.15) * 0.6);
			color = cramp(TRAV, 4, 0.45 + rings * 0.5, pixel);
			if (rings < 0.12) {
				color = CAVE[TRAV];
			}
		}
	}
	if (hash12(floor(np / 3.0) + 41.0) < (sun * 0.02 + warmth * 0.03) && hash12(np * 2.1) < 0.5) {
		color = CAVE[WET];
	}
	return color;
}

// Smooth ice of an icy passage: pale, streaked, glints sliding along it.
vec3 icy_look(vec2 pixel, vec2 np) {
	vec3 color = cramp(ICY, 4, 0.45 + (fbm(np * vec2(0.03, 0.06)) - 0.5) * 0.5
		+ (value_noise(vec2(np.x * 0.25, np.y * 0.5)) - 0.5) * 0.2, pixel);
	if (abs(fbm(np * 0.05 + 9.0) - 0.5) < 0.012) {
		color = CAVE[ICY + 3];
	}
	if (mod(pixel.y, 9.0) < 1.0 && fract((pixel.x - time * 2.0 + hash12(vec2(pixel.y, 3.1)) * 61.0) / 41.0) < 0.06) {
		color = vec3(1.0);
	}
	return color;
}

// Murky melting ice: grey, with dark blotches where the water shows; more translucent
// further from the shore. Under the player it gives: cracks run, the water seeps up.
void melt_look(vec2 pixel, vec2 np, float lake, inout vec3 color, inout float alpha) {
	color = cramp(MELT, 4, 0.45 + (fbm(np * 0.05) - 0.5) * 0.45 + (value_noise(np * 0.3) - 0.5) * 0.1, pixel);
	alpha = mix(0.92, 0.66, smoothstep(2.0, 12.0, lake));
	float blotch = value_noise(np * 0.07 + 11.0);
	if (blotch > 0.66) {
		color = mix(color, CAVE[DEEP + 2], 0.45 + (blotch - 0.66));
		alpha = max(alpha - 0.12, 0.5);
	}
	if (abs(value_noise(np * 0.11 + 2.0) - 0.5) < 0.01) {
		color = CAVE[MELT + 3];
		alpha = 0.9;
	}
	if (lake < 1.5) {
		color = CAVE[MELT];
		alpha = 1.0;
	}
	if (strain.z > 0.45) {
		vec2 rel = pixel + 0.5 - strain.xy;
		float growth = clamp((strain.z - 0.45) / 0.5, 0.0, 1.0);
		if (strain.z > 0.8 && length(rel) < 3.0 + (strain.z - 0.8) * 30.0) {
			color = mix(color, CAVE[DEEP + 1], 0.6);
			alpha = 0.95;
		}
		if (on_crack(rel, 10.0, growth, floor(strain.xy / 6.0))) {
			color = hash12(pixel + floor(time * 10.0)) < 0.3 ? CAVE[MELT + 1] : vec3(0.95);
			alpha = 0.97;
		}
	}
}

// Open water: black and cold, slow glints, slush and floes of ice by its edge, rings
// spreading round whatever floats on it.
void water_look(vec2 pixel, vec2 np, float water, inout vec3 color, inout float alpha) {
	float level = 0.32 + (value_noise(np * 0.05 + vec2(time * 0.04, 0.0)) - 0.5) * 0.35;
	color = cramp(DEEP, 4, level, pixel);
	if (mod(pixel.y, 4.0) < 1.0 && fract((pixel.x + time * 2.0 + hash12(vec2(pixel.y, 5.0)) * 30.0) / 19.0) < 0.07) {
		color = CAVE[DEEP + 3];
	}
	if (water < 4.0) {
		float floe = value_noise(np * 0.3 + vec2(sin(time * 0.3), 0.0) * 0.4);
		if (floe > 0.62 - (4.0 - water) * 0.05) {
			color = floe > 0.72 ? PAL[SLUSH + 2] : ramp(SLUSH, 3, hash12(np) * 0.9, pixel);
		}
	}
	for (int i = 0; i < 12; i++) {
		if (i >= ripple_count) {
			break;
		}
		vec4 ripple = ripples[i];
		float r = length(pixel + 0.5 - ripple.xy) - ripple.z;
		if (r < 0.0 || r > 14.0) {
			continue;
		}
		for (int k = 0; k < 2; k++) {
			float ring = mod(time * 3.0 + ripple.w * 7.0 + float(k) * 7.0, 14.0);
			if (abs(r - ring) < 0.55) {
				color = mix(color, CAVE[DEEP + 3], 1.0 - ring / 14.0);
			}
		}
	}
	alpha = 1.0;
}

// Over a chasm: the far (north) wall — a lit lip, then layers of blue ice dropping into the
// dark, icicles under the lip — then nothing; the near edge a ledge of ice. Under an arch
// its front face, then its shadow on the depth.
void chasm_look(vec2 pixel, vec2 np, inout vec3 color, inout float alpha) {
	float north = 99.0;
	bool under_arch = false;
	bool under_wall = false;
	for (int k = 1; k <= 34; k++) {
		vec2 at = pixel - vec2(0.0, float(k));
		vec4 z = zone_at(at);
		if (byte_of(z.g) == 255.0) {
			north = float(k);
			under_arch = true;
			break;
		}
		if (byte_of(z.r) < 128.0) {
			north = float(k);
			break;
		}
		if (wall_at(at) > 0.0) {
			north = float(k);
			under_wall = true;
			break;
		}
	}
	float drop = 14.0 + floor(value_noise(vec2(pixel.x * 0.09, 5.0)) * 8.0);
	color = vec3(0.0);
	alpha = 0.0;
	if (under_arch) {
		if (north <= 3.0) {
			color = cramp(ARCH, 4, 0.5 - north * 0.15, pixel);
			alpha = 1.0;
		} else if (north <= 14.0) {
			color = vec3(0.02, 0.04, 0.1);
			alpha = 0.62 * (1.0 - (north - 3.0) / 11.0);
		}
	} else if (north == 1.0 && !under_wall) {
		color = CAVE[RIM];
		alpha = 1.0;
	} else if (north <= drop) {
		float v = (north - 1.0) / drop;
		float band = mod(north + floor(value_noise(vec2(pixel.x * 0.15, 2.0)) * 3.0), 3.0);
		float level = 0.95 - v * 1.05 + (band < 1.0 ? -0.12 : 0.0) + (hash12(vec2(pixel.x, 3.3)) - 0.5) * 0.12;
		color = cramp(DROP, 6, level, pixel);
		if (north <= 5.0 && hash12(vec2(pixel.x, 5.5)) < 0.3) {
			color = CAVE[DROP + 5];
		}
		alpha = 1.0;
		if (v > 0.45 && (v - 0.45) / 0.55 * 16.0 > bayer(pixel) + 0.5) {
			alpha = 0.0;
		}
	}
	// The near edge: a ledge of ice, deep shade under it.
	float south = 99.0;
	for (int k = 1; k <= 2; k++) {
		vec4 z = zone_at(pixel + vec2(0.0, float(k)));
		if (byte_of(z.r) < 128.0 || byte_of(z.g) == 255.0) {
			south = float(k);
			break;
		}
	}
	if (south == 1.0) {
		color = CAVE[FROST + 1];
		alpha = 1.0;
	} else if (south == 2.0) {
		color = CAVE[DROP];
		alpha = 1.0;
	}
	// The side walls: the west one catches the light, the east one is dark.
	if (alpha > 0.0 || north > drop) {
		for (int k = 1; k <= 2; k++) {
			if (byte_of(zone_at(pixel - vec2(float(k), 0.0)).r) < 128.0) {
				color = CAVE[DROP + 4 - k];
				alpha = 1.0;
				break;
			}
			if (byte_of(zone_at(pixel + vec2(float(k), 0.0)).r) < 128.0 && k == 1) {
				color = CAVE[DROP + 1];
				alpha = 1.0;
				break;
			}
		}
	}
}

// An arch's deck: smooth ice, its north edge lit, its sides outlined.
void arch_look(vec2 pixel, vec2 np, inout vec3 color, inout float alpha) {
	float up = byte_of(zone_at(pixel - vec2(0.0, 1.0)).g) == 255.0 ? 0.0 : 1.0;
	bool side = byte_of(zone_at(pixel - vec2(1.0, 0.0)).g) != 255.0 || byte_of(zone_at(pixel + vec2(1.0, 0.0)).g) != 255.0;
	color = cramp(ARCH, 4, 0.55 + (fbm(np * 0.08) - 0.5) * 0.4 - (hash12(vec2(pixel.x, 2.0)) - 0.5) * 0.1, pixel);
	if (up > 0.0) {
		color = CAVE[ARCH + 3];
	} else if (side) {
		color = CAVE[ARCH];
	}
	alpha = 1.0;
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size);
	vec2 np = pixel + noise_offset;
	float wall = wall_at(pixel);
	vec3 color = vec3(0.0);
	float alpha = 1.0;
	if (wall > 0.0) {
		float height = FACE + floor((value_noise(vec2(pixel.x * 0.11, 3.7)) - 0.5) * 4.0 + 0.5);
		float down = 0.0;
		for (int k = 1; k <= 16; k++) {
			if (float(k) > height) {
				break;
			}
			if (wall_at(pixel + vec2(0.0, float(k))) <= 0.0) {
				down = float(k);
				break;
			}
		}
		if (down > 0.0) {
			color = face_look(pixel, down, height);
		} else {
			top_look(pixel, np, wall, color, alpha);
			// The lit rim along the edge of the ice.
			if (wall_at(pixel - vec2(0.0, 1.0)) <= 0.0 || wall_at(pixel - vec2(1.0, 0.0)) <= 0.0
					|| wall_at(pixel + vec2(1.0, 0.0)) <= 0.0) {
				color = CAVE[RIM];
				alpha = 1.0;
			}
		}
	} else {
		vec4 field = field_at(pixel);
		vec4 zone = zone_at(pixel);
		vec4 light = light_at(pixel);
		float lake = byte_of(field.r) - 128.0;
		int kinds = int(byte_of(field.g));
		int pool = kinds % 4;
		bool icy = (kinds / 4) % 2 == 1;
		float snow = float(kinds / 8) / 31.0;
		float crack_depth = byte_of(field.b) - 128.0;
		float extra = byte_of(field.a);
		bool bridge = extra == 255.0;
		float thin = (extra >= 1.0 && extra <= 100.0) ? extra / 100.0 : 0.0;
		bool in_crevasse = crack_depth >= 0.0 && byte_of(field.b) > 0.0 && !bridge;
		float chasm = byte_of(zone.r) - 128.0;
		bool arch = byte_of(zone.g) == 255.0;
		bool in_chasm = chasm >= 0.0 && byte_of(zone.r) > 0.0 && !arch;
		float water = byte_of(zone.b) - 128.0;
		color = stone_look(pixel, np, wall, light.a, light.b, light.r);
		if (icy) {
			color = icy_look(pixel, np);
		}
		// Snow, with the marks left in it; dust where it runs thin.
		bool on_snow = snow > 0.0 && (snow > 0.12 || hash12(np * 1.3) < snow / 0.12);
		if (on_snow && lake < -0.5 && byte_of(field.b) < 126.0) {
			vec2 mark = mark_at(pixel);
			float level = snow_level(np, clamp(snow * 2.0, 0.0, 1.0)) + mark.y * 0.14 - mark.x * 0.26;
			color = ramp(SNOW, 5, level, pixel);
			if (mark.x > 0.45) {
				color = mix(color, PAL[DENT], 0.25);
			}
			if (mark.x <= 0.0 && light.r > 0.3 && sparkle(pixel, np)) {
				color = vec3(1.0);
			}
		}
		// By the walls: a dark contour, then shade (the height reads); frost and shards of
		// icicles at the foot of the faces.
		float above = wall_at(pixel - vec2(0.0, 1.0));
		float above2 = wall_at(pixel - vec2(0.0, 2.0));
		if (above > 0.0) {
			color = hash12(pixel * 2.7) < 0.55 ? CAVE[FROST + 2] : CAVE[FACEC + 3];
		} else if (above2 > 0.0 && hash12(pixel * 1.9) < 0.4) {
			color = CAVE[FROST + 1];
		} else if (wall > -texel_size * 1.05) {
			color = CAVE[CONTOUR];
		} else if (wall > -texel_size * 3.0) {
			color *= 0.74;
		} else if (wall > -texel_size * 7.0) {
			color *= 0.9;
		}
		if (lake >= 0.0) {
			if (pool == 0) {
				lake_ice(pixel, np, lake, thin, color, alpha);
			} else if (pool == 1) {
				melt_look(pixel, np, lake, color, alpha);
			} else if (water >= 0.0 && byte_of(zone.b) > 0.0) {
				water_look(pixel, np, water, color, alpha);
			} else {
				melt_look(pixel, np, lake, color, alpha);
			}
		} else if (lake > -2.0 && byte_of(field.r) > 0.0) {
			color = mix(color, CAVE[FROST + 2], 0.4);
		}
		if (in_crevasse) {
			crevasse_look(pixel, crack_depth, color, alpha);
		} else if (bridge) {
			bridge_look(pixel, np, crack_depth, color, alpha);
		}
		if (in_chasm) {
			chasm_look(pixel, np, color, alpha);
		} else if (arch && chasm > -3.0) {
			arch_look(pixel, np, color, alpha);
		}
		holes_look(pixel, np, color, alpha);
		cracks_look(pixel, color, alpha);
	}
	COLOR = vec4(color, alpha);
}
