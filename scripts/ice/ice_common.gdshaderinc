// Shared by the floors of the ice maps (ice_ground.gdshader — the valley — and the cave's
// cave_ground.gdshader): the palette of the "Лёд" menu, noise and ordered dithering, and
// the surfaces themselves — snow with sastrugi and sparkles, dry stems, the marks left
// in the snow, lake ice with white veins and drifting glints, thin ice, crevasses (the
// north wall of blue ice dropping into the dark, a snow cornice on the near edge), snow
// bridges, and during play the cracks spreading on thin ice and the holes freezing over.
//
// Include it after defining `vec4 field_at(vec2 pixel)`: the floor map of NelvarIceField's
// layout — R lake (128 + art pixels into the ice), B crevasse (128 + art pixels into the
// crack, bridges ignored), A 255 on a bridge's deck. It declares the uniforms below.

uniform float texel_size = 4.0;      // world units per art pixel
uniform float time = 0.0;            // seconds; shared with the swaying plants
uniform vec2 noise_offset;           // a different floor per world
uniform vec2 wind_dir = vec2(1.0, 0.08);
// Cracks spreading on thin ice: centre (art px), radius (art px), stage (0..1 growing,
// 1..2 held and fading).
uniform vec4 cracks[8];
uniform int crack_count = 0;
// Holes: centre (art px), radius (art px), how far frozen over again (0..1).
uniform vec4 holes[16];
uniform int hole_count = 0;
// NelvarSnowMarks: RG the snow clock when stamped (×2, 16 bits), B kind × 16 + depth,
// A 1 where marked.
uniform sampler2D marks_tex : filter_nearest, repeat_disable;
uniform vec2 marks_origin;
uniform vec2 marks_size = vec2(0.0);
uniform float snow_clock = 0.0;
uniform float mark_life = 90.0;
uniform float ice_alpha = 0.74;
uniform float clear_alpha = 0.5;
uniform float thin_alpha = 0.4;

const float TUFT_CELL = 7.0;

// Palettes, dark to light (tools/gen_menu_backgrounds.py, ice()).
const int SNOW = 0;      // 5
const int PATH = 5;      // 3
const int PATH_EDGE = 8;
const int DENT = 9;      // 2
const int ICE = 11;      // 4
const int ICE_CRACK = 15;
const int THIN = 16;     // 4
const int GRASS = 20;    // 4
const int WALL = 24;     // 6
const int ABYSS = 30;    // 3
const int WATER = 33;    // 4
const int GLINT = 37;
const int SLUSH = 38;    // 3
const int SCREE = 41;    // 3
const int FIR = 44;      // 3
const int FIR_CAP = 47;
const vec3 PAL[48] = vec3[48](
	vec3(176.0, 182.0, 194.0) / 255.0, vec3(198.0, 204.0, 214.0) / 255.0, vec3(218.0, 222.0, 230.0) / 255.0,
	vec3(236.0, 238.0, 242.0) / 255.0, vec3(250.0, 251.0, 252.0) / 255.0,
	vec3(184.0, 190.0, 200.0) / 255.0, vec3(200.0, 206.0, 214.0) / 255.0, vec3(214.0, 218.0, 226.0) / 255.0,
	vec3(232.0, 234.0, 238.0) / 255.0,
	vec3(164.0, 170.0, 182.0) / 255.0, vec3(176.0, 182.0, 194.0) / 255.0,
	vec3(170.0, 188.0, 194.0) / 255.0, vec3(196.0, 212.0, 216.0) / 255.0, vec3(218.0, 230.0, 232.0) / 255.0,
	vec3(238.0, 245.0, 246.0) / 255.0,
	vec3(150.0, 166.0, 174.0) / 255.0,
	vec3(98.0, 128.0, 146.0) / 255.0, vec3(124.0, 156.0, 172.0) / 255.0, vec3(156.0, 186.0, 198.0) / 255.0,
	vec3(194.0, 216.0, 224.0) / 255.0,
	vec3(120.0, 112.0, 100.0) / 255.0, vec3(150.0, 140.0, 122.0) / 255.0, vec3(176.0, 166.0, 144.0) / 255.0,
	vec3(204.0, 196.0, 176.0) / 255.0,
	vec3(226.0, 242.0, 248.0) / 255.0, vec3(186.0, 222.0, 236.0) / 255.0, vec3(132.0, 186.0, 214.0) / 255.0,
	vec3(84.0, 138.0, 182.0) / 255.0, vec3(46.0, 86.0, 138.0) / 255.0, vec3(24.0, 46.0, 86.0) / 255.0,
	vec3(14.0, 24.0, 48.0) / 255.0, vec3(8.0, 14.0, 30.0) / 255.0, vec3(4.0, 6.0, 16.0) / 255.0,
	vec3(16.0, 40.0, 54.0) / 255.0, vec3(24.0, 58.0, 74.0) / 255.0, vec3(38.0, 84.0, 100.0) / 255.0,
	vec3(70.0, 124.0, 138.0) / 255.0,
	vec3(176.0, 222.0, 230.0) / 255.0,
	vec3(112.0, 132.0, 144.0) / 255.0, vec3(146.0, 164.0, 176.0) / 255.0, vec3(184.0, 198.0, 206.0) / 255.0,
	vec3(110.0, 114.0, 122.0) / 255.0, vec3(140.0, 144.0, 150.0) / 255.0, vec3(172.0, 176.0, 182.0) / 255.0,
	vec3(58.0, 76.0, 74.0) / 255.0, vec3(78.0, 92.0, 96.0) / 255.0, vec3(96.0, 110.0, 112.0) / 255.0,
	vec3(244.0, 246.0, 248.0) / 255.0
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

float byte_of(float channel) {
	return floor(channel * 255.0 + 0.5);
}

// The wind over the valley (NelvarIceMain.gust): gusts run from the left.
float gust(vec2 world) {
	return 0.65 * sin(world.x * 0.0045 + world.y * 0.0012 - time * 1.7)
		+ 0.35 * sin(world.x * 0.011 - world.y * 0.006 - time * 2.6);
}

// Light level of the snow: broad patches, and sastrugi — low ridges the wind carved
// along itself, a lit crest and a shaded lee. `drift`: how deep the wind-blown snow.
float snow_level(vec2 np, float drift) {
	float level = 0.66 + (fbm(np * vec2(0.02, 0.03)) - 0.5) * 0.5 + (value_noise(np * 0.11) - 0.5) * 0.1
		+ drift * 0.1;
	vec2 across = vec2(-wind_dir.y, wind_dir.x);
	float ridges = sin(dot(np, across) * 0.75 + value_noise(np * 0.04) * 7.0);
	float patchy = smoothstep(0.45, 0.7, value_noise(np / 36.0 + 9.0)) + drift * 0.8;
	if (patchy > 0.3) {
		if (ridges > 0.9) {
			level += 0.14;
		} else if (ridges < -0.86) {
			level -= 0.1;
		}
	}
	return level;
}

// Sparkles of the snow: a few pixels flash white, here and there and now and then.
bool sparkle(vec2 pixel, vec2 np) {
	float h = hash12(np * 0.77 + 3.3);
	if (h < 0.004 && sin(time * 2.3 + hash12(np * 1.3) * 40.0) > 0.92) {
		return true;
	}
	return hash12(pixel + floor(time * 1.5) * 17.0) < 0.0008;
}

// One tuft of dry stems per cell (where there is one); the tips lean with the gust.
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
			int shade = k == height - 1 ? 3 : (k > height / 2 ? 2 : 1);
			if (k == 0) {
				shade = 0;
			}
			return vec4(PAL[GRASS + shade], 1.0);
		}
	}
	return vec4(0.0);
}

// How deep a mark in the snow still shows here (x: dug, y: piled), 0 once drifted over.
vec2 mark_at(vec2 pixel) {
	if (marks_size.x <= 0.0) {
		return vec2(0.0);
	}
	vec2 m = pixel - marks_origin;
	if (m.x < 0.0 || m.y < 0.0 || m.x >= marks_size.x || m.y >= marks_size.y) {
		return vec2(0.0);
	}
	vec4 mark = texelFetch(marks_tex, ivec2(m), 0);
	if (mark.a < 0.5) {
		return vec2(0.0);
	}
	float stamp = byte_of(mark.r) * 256.0 + byte_of(mark.g);
	float now = mod(floor(snow_clock * 2.0), 65536.0);
	float age = mod(now - stamp + 65536.0, 65536.0) * 0.5;
	float fade = 1.0 - age / mark_life;
	if (fade <= 0.0) {
		return vec2(0.0);
	}
	// Drifted over unevenly: the shallow parts go first.
	float info = byte_of(mark.b);
	float kind = floor(info / 16.0);
	float depth = mod(info, 16.0) / 15.0;
	if (fade < 0.5 && hash12(pixel * 0.91) > fade * 2.0) {
		return vec2(0.0);
	}
	if (kind == 1.0 || kind == 3.0) {
		return vec2(depth * fade, 0.0);
	}
	return vec2(0.0, depth * fade);
}

// Lines of a crack spreading from its centre: a few jagged rays and their branches.
bool on_crack(vec2 rel, float radius, float growth, vec2 seed) {
	float r = length(rel);
	if (r > radius * growth + 0.5) {
		return false;
	}
	if (r < 1.2) {
		return true;
	}
	float angle = atan(rel.y, rel.x);
	float a0 = hash12(seed) * 6.2831;
	for (int k = 0; k < 6; k++) {
		float ak = a0 + float(k) * 1.0472 + (hash12(seed + float(k) * 3.1) - 0.5) * 0.7;
		ak += sin(r * 0.55 + float(k) * 1.7) * 0.14;
		float da = abs(mod(angle - ak + 3.14159, 6.2831) - 3.14159);
		float reach = radius * (0.65 + hash12(seed + float(k) * 7.7) * 0.35);
		if (r < reach * growth && da * r < 0.6) {
			return true;
		}
		float fork = reach * 0.45;
		if (r > fork && r < reach * 0.85 * growth) {
			float side = hash12(seed + float(k)) < 0.5 ? -0.55 : 0.55;
			float db = abs(mod(angle - ak - side + 3.14159, 6.2831) - 3.14159);
			if (db * r < 0.55 && (r - fork) < reach * 0.4) {
				return true;
			}
		}
	}
	return false;
}

// Lake ice `lake` art pixels in from the shore: pale blue, veined white, glints drifting
// across; it lets the depths show (more through its clear windows and the thin ice,
// `thin` 0..1 how far inside a thin patch). The north bank shades it, a frosted rim
// runs along the shore.
void lake_ice(vec2 pixel, vec2 np, float lake, float thin, inout vec3 color, inout float alpha) {
	float above = byte_of(field_at(pixel + vec2(0.0, -1.0)).r) - 128.0;
	float above2 = byte_of(field_at(pixel + vec2(0.0, -2.0)).r) - 128.0;
	float t = 0.42 + (fbm(np * vec2(0.03, 0.05)) - 0.5) * 0.5
		+ (value_noise(vec2(np.x * 0.2, np.y * 0.6)) - 0.5) * 0.25;
	// Clear windows in the ice, where the depths show best.
	float clear = smoothstep(0.55, 0.75, value_noise(np / 22.0 + 51.0));
	alpha = mix(0.88, mix(ice_alpha, clear_alpha, clear), smoothstep(2.0, 14.0, lake));
	if (clear > 0.5) {
		t -= 0.08;
	}
	if (thin > 0.0) {
		color = ramp(THIN, 4, t - 0.08, pixel);
		alpha = mix(ice_alpha, thin_alpha, smoothstep(0.0, 0.5, thin));
		if (thin <= 0.09) {
			// The cloudy rim of a thin patch: a fair warning for a watchful eye.
			color = PAL[ICE + 2];
			alpha = 0.8;
		}
	} else {
		color = ramp(ICE, 4, t, pixel);
	}
	if (abs(fbm(np * 0.045 + 7.0) - 0.5) < 0.011) {
		color = PAL[ICE + 3];
		alpha = max(alpha, 0.9);
	} else if (abs(value_noise(np * 0.09 + 3.1) - 0.5) < 0.008) {
		color = PAL[ICE_CRACK];
		alpha = max(alpha, 0.88);
	} else if (hash12(np * 1.91) < 0.003) {
		// A frozen bubble.
		color = PAL[ICE + 3];
		alpha = 0.95;
	}
	if (lake > 2.0 && mod(pixel.y, 11.0) < 1.0) {
		float run = fract((pixel.x - time * 2.0 + hash12(vec2(pixel.y, 3.1)) * 61.0) / 47.0);
		if (run < 0.06) {
			color = PAL[GLINT];
			alpha = 0.95;
		}
	}
	if (above < 0.0 || above2 < 0.0) {
		// Under the north bank: its shadow on the ice.
		color = PAL[ICE] * 0.9;
		alpha = 0.95;
	}
	if (lake < 1.5) {
		// The frosted rim along the shore.
		color = PAL[SNOW + 3];
		alpha = 1.0;
	}
}

// Inside a crevasse `crack_depth` art pixels from its edge. The north wall: a lit rim,
// then layers of blue ice dropping fast into the dark; along a crack running north–south
// its west wall catches the sun, its east one is in shade. The near (south) edge is a
// snow cornice with deep shade under it. A bridge deck above stands for the rim.
void crevasse_look(vec2 pixel, float crack_depth, inout vec3 color, inout float alpha) {
	float north = 99.0;
	for (int k = 1; k <= 12; k++) {
		vec4 f = field_at(pixel - vec2(0.0, float(k)));
		if (byte_of(f.b) < 128.0 || byte_of(f.a) == 255.0) {
			north = float(k);
			break;
		}
	}
	float south = 99.0;
	for (int k = 1; k <= 2; k++) {
		if (byte_of(field_at(pixel + vec2(0.0, float(k))).b) < 128.0) {
			south = float(k);
			break;
		}
	}
	float west = 99.0;
	float east = 99.0;
	for (int k = 1; k <= 3; k++) {
		if (west > 9.0 && byte_of(field_at(pixel - vec2(float(k), 0.0)).b) < 128.0) {
			west = float(k);
		}
		if (east > 9.0 && byte_of(field_at(pixel + vec2(float(k), 0.0)).b) < 128.0) {
			east = float(k);
		}
	}
	bool under_deck = north < 99.0 && byte_of(field_at(pixel - vec2(0.0, north)).a) == 255.0;
	float deep = clamp(0.25 + crack_depth * 0.04 + (north < 99.0 ? 0.0 : 0.3), 0.0, 1.0);
	color = ramp(ABYSS, 3, deep, pixel);
	if (west <= 2.0) {
		color = PAL[WALL + int(west)];
	} else if (east == 1.0) {
		color = PAL[WALL + 4];
	}
	if (north <= 6.0) {
		if (under_deck) {
			// The bridge's own face, then its shadow.
			color = north == 1.0 ? PAL[SNOW + 1] : (north == 2.0 ? PAL[SNOW] : PAL[WALL + 5]);
		} else if (north == 1.0) {
			color = PAL[SNOW + 3];
		} else {
			float band = mod(north + floor(value_noise(vec2(pixel.x * 0.18, 2.0)) * 3.0), 3.0);
			color = PAL[WALL + min(int(north) - 1 + (band < 1.0 ? -1 : 0), 5)];
			if (north <= 3.0 && hash12(vec2(pixel.x, 5.0)) < 0.28) {
				// Icicles hanging from the rim.
				color = PAL[WALL];
			}
		}
	} else if (hash12(pixel * 0.53 + floor(time * 0.7)) < 0.0015) {
		color = PAL[WALL + 3];
	}
	if (south == 1.0) {
		color = PAL[SNOW + 4];
	} else if (south == 2.0) {
		color = PAL[ABYSS];
	}
	alpha = 1.0;
}

// A snow bridge: drifted snow over the crack, sagging and bluer in the middle, a bright
// lip where it meets the open crack.
void bridge_look(vec2 pixel, vec2 np, float crack_depth, inout vec3 color, inout float alpha) {
	float sag = clamp(crack_depth / 8.0, 0.0, 1.0);
	color = ramp(SNOW, 5, snow_level(np, 0.0) - 0.06 - sag * 0.16, pixel);
	if (crack_depth >= 0.0) {
		color = mix(color, PAL[WALL + 1], 0.18 + sag * 0.12);
	}
	vec4 above = field_at(pixel - vec2(0.0, 1.0));
	if (byte_of(above.b) >= 128.0 && byte_of(above.a) != 255.0) {
		color = PAL[SNOW + 4];
	}
	alpha = 1.0;
}

// Holes: open water, then slush, then dark new ice; jagged broken edges.
void holes_look(vec2 pixel, vec2 np, inout vec3 color, inout float alpha) {
	for (int i = 0; i < 16; i++) {
		if (i >= hole_count) {
			break;
		}
		vec4 hole = holes[i];
		vec2 rel = pixel + 0.5 - hole.xy;
		float r = length(rel);
		if (r > hole.z * 1.3 + 2.0) {
			continue;
		}
		float angle = atan(rel.y, rel.x);
		float edge = hole.z * (1.0 + (value_noise(vec2(angle * 2.5, float(i) * 7.3)) - 0.5) * 0.3);
		if (r > edge + 1.5) {
			continue;
		}
		float f = hole.w;
		if (r > edge - 1.0) {
			// Shards of broken ice round the rim (fewer as it freezes over).
			if (hash12(pixel * 1.7) < 0.7 - f * 0.4) {
				color = hash12(pixel * 2.3) < 0.5 ? PAL[ICE + 3] : vec3(1.0);
				alpha = 1.0;
			}
			continue;
		}
		float ripple = sin(r * 1.3 - time * 3.0) * 0.5 + 0.5;
		vec3 water = ramp(WATER, 4, 0.25 + ripple * 0.35 + (value_noise(np * 0.3 + time) - 0.5) * 0.2, pixel);
		if (mod(pixel.y, 3.0) < 1.0 && fract((pixel.x + time * 3.0 + hash12(vec2(pixel.y, 1.0)) * 20.0) / 9.0) < 0.12) {
			water = PAL[GLINT];
		}
		if (f < 0.6) {
			color = water;
			alpha = 1.0;
		} else if (f < 0.8) {
			float cover = (f - 0.6) / 0.2;
			color = value_noise(np * 0.35 + float(i)) < cover ? ramp(SLUSH, 3, hash12(np) * 0.9, pixel) : water;
			alpha = 1.0;
		} else {
			color = ramp(THIN, 4, 0.2 + (value_noise(np * 0.4) - 0.5) * 0.3, pixel);
			alpha = thin_alpha;
		}
	}
}

// Cracks: white while they spread, grey-blue once they hold.
void cracks_look(vec2 pixel, inout vec3 color, inout float alpha) {
	for (int i = 0; i < 8; i++) {
		if (i >= crack_count) {
			break;
		}
		vec4 crack = cracks[i];
		vec2 rel = pixel + 0.5 - crack.xy;
		if (dot(rel, rel) > crack.z * crack.z * 1.2 + 4.0) {
			continue;
		}
		float growth = clamp(crack.w, 0.0, 1.0);
		if (on_crack(rel, crack.z, growth, crack.xy)) {
			if (crack.w <= 1.0) {
				color = hash12(pixel + floor(time * 12.0)) < 0.2 ? PAL[ICE + 2] : vec3(1.0);
			} else {
				// A crack that held stays in sight as a warning, fading slowly.
				color = mix(PAL[ICE + 3], PAL[ICE_CRACK], clamp(crack.w - 1.0, 0.0, 1.0));
			}
			alpha = 0.97;
		} else if (on_crack(rel + vec2(0.0, -1.0), crack.z, growth, crack.xy)) {
			// The crack's shaded lower lip.
			color = PAL[THIN];
			alpha = max(alpha, 0.85);
		}
	}
}
