shader_type canvas_item;
// Disabled blending: the viewport keeps the floor's own alpha, so the frozen lakes let
// the water and the creatures under them (NelvarIceDepths) show through.
render_mode unshaded, blend_disabled;

// The floor of the ice valley in the palette of the "Лёд" menu: snow in broad patches
// with sastrugi along the wind and sparkles, dry grass poking out, trodden trails with
// a chain of dents, frozen lakes of pale blue ice with white veins and drifting glints
// (translucent: what lies under them shows through, more so through thin ice),
// crevasses whose north wall of layered ice drops into a dark blue depth under a snow
// cornice on the south edge, snow bridges over them, and beyond the foot the snowy
// uplands. During play: cracks spreading under the player on thin ice, holes of open
// water freezing over again, and the marks left in the snow (NelvarSnowMarks), drifted
// over with time — faster in a blizzard.
//
// Runs through NelvarCloudSea with parallax 1 and no drift: one fragment per art pixel
// of the world grid. NelvarIceField supplies what lies where; the valley outline is the
// same function as NelvarEarthData.Radial.

uniform vec2 base_pixel;             // world art pixel at the viewport's top-left corner
uniform vec2 sea_size;               // viewport size in art pixels
uniform float breath_time = 0.0;     // set by NelvarCloudSea; unused here
uniform float hole_amount = 0.0;     // set by NelvarCloudSea; unused here
uniform vec2 seed_offset;            // set by NelvarCloudSea; unused here

uniform float texel_size = 4.0;      // world units per art pixel
uniform float time = 0.0;            // seconds; shared with the swaying plants
uniform vec2 noise_offset;           // a different floor per world
uniform vec2 wind_dir = vec2(1.0, 0.08);
uniform sampler2D field_tex : filter_nearest, repeat_disable;
uniform vec2 field_origin;           // world art pixel of the field's first texel
uniform vec2 field_size;
uniform vec2 valley_center;
uniform vec2 valley_axes = vec2(1750.0, 1500.0);
uniform float valley_amp[6];
uniform float valley_phase[6];
// NelvarMountainField: R the range's foot, G the peaks' shadows.
uniform sampler2D mountain_tex : filter_linear, repeat_disable;
uniform vec2 mountain_origin;
uniform vec2 mountain_size = vec2(0.0);
uniform float mountain_scale = 4.0;
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
const float WALL_HEIGHT = 11.0;

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
// The uplands fade towards the menu's pale haze.
const vec3 UPLAND_HAZE = vec3(226.0, 229.0, 234.0) / 255.0;
const float UPLAND_FADE = 0.4;
const float TREE_CELL = 6.0;
// The peaks' cast shadow on snow: cool blue.
const vec3 MOUNTAIN_SHADE = vec3(0.76, 0.8, 0.92);
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
		return vec4(0.0, 1.0, 0.0, 0.0);
	}
	return texelFetch(field_tex, ivec2(f), 0);
}

float byte_of(float channel) {
	return floor(channel * 255.0 + 0.5);
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

// The range's foot (NelvarMountainField R), its edge broken up by noise.
float rocky_at(vec2 np, float foot) {
	if (foot <= 0.0) {
		return 0.0;
	}
	return foot + (value_noise(np / 7.0 + 23.0) - 0.5) * 0.3 + (fbm(np * 0.05) - 0.5) * 0.2;
}

// Height step of the uplands: broad uneven terraces of snow.
float terrace(vec2 np) {
	float n = value_noise(np * 0.0032) * 0.7 + value_noise(np * 0.009 + 31.0) * 0.3
		+ (value_noise(np * 0.07 + 5.0) - 0.5) * 0.03;
	return floor(n * 6.0);
}

// Frozen lakes of the uplands: above zero on the ice.
float upland_lake(vec2 np) {
	return value_noise(np / 100.0 + 41.0) * 0.8 + value_noise(np / 34.0 + 9.0) * 0.2 - 0.8;
}

// A snowy fir of the uplands seen from afar: a dark cone with a white cap and a shadow
// down and to the left. Alpha 1 on the fir, 0.5 in its shadow, 0 elsewhere.
vec4 upland_fir(vec2 pixel, vec2 np, float grove) {
	vec2 cell = floor(np / TREE_CELL);
	vec4 found = vec4(0.0);
	float front = -1e9;
	for (int j = -1; j <= 1; j++) {
		for (int i = -1; i <= 1; i++) {
			vec2 c = cell + vec2(float(i), float(j));
			vec3 h = hash32(c * 1.3 + 17.0);
			if (h.x > grove * 0.5 + 0.004) {
				continue;
			}
			vec2 center = c * TREE_CELL + 1.0 + h.yz * (TREE_CELL - 2.0);
			if (upland_lake(center) > -0.04) {
				continue;
			}
			float r = 2.0 + hash12(c + 5.0) * 1.6;
			vec2 d = np - center;
			float apex = -r * 1.9;
			float base = r * 0.6;
			if (d.y >= apex && d.y <= base) {
				float half_width = r * 0.85 * (d.y - apex) / (base - apex);
				if (abs(d.x) <= half_width + 0.2) {
					vec3 color = d.x > 0.0 ? PAL[FIR + 2] : PAL[FIR + 1];
					if (d.x < -half_width + 0.9) {
						color = PAL[FIR];
					}
					if (d.y < apex + r * 0.8 || hash12(np) < 0.25) {
						color = PAL[FIR_CAP];
					}
					if (center.y > front) {
						front = center.y;
						found = vec4(color, 1.0);
					}
					continue;
				}
			}
			vec2 s = (d - vec2(-r * 0.7, r * 0.9)) / vec2(r * 1.2, r * 0.6);
			if (found.a < 1.0 && dot(s, s) <= 1.0) {
				found = vec4(0.0, 0.0, 0.0, 0.5);
			}
		}
	}
	return found;
}

// Beyond the mountain foot: snowy uplands — terraces whose south edges drop in short
// banks, stands of snowy firs, scree by the peaks, now and then a frozen lake; paler
// with distance.
vec3 uplands(vec2 pixel, vec2 np, float beyond, float foot) {
	float h = hash12(np);
	float rocky = rocky_at(np, foot);
	float ice = upland_lake(np) - max(rocky, 0.0) * 0.6;
	float t = terrace(np);
	float face = 0.0;
	float height = 0.0;
	bool shaded = false;
	if (ice < -0.06) {
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
	}
	float grove = smoothstep(0.52, 0.7, value_noise(np / 60.0 + 101.0));
	grove = max(grove, smoothstep(0.22, 0.45, rocky));
	float level = snow_level(np, 0.0) + (t - 2.5) * 0.03 - clamp(rocky, 0.0, 1.0) * 0.18;
	vec3 color = ramp(SNOW, 5, level, pixel);
	bool scree = (rocky - 0.58 - (1.0 - smoothstep(6.0, 30.0, beyond)) * 0.6) * 64.0 > bayer(pixel) + 0.5;
	if (face > 0.0) {
		// A snowy bank, its lip catching the light, a stone showing here and there.
		color = face == 1.0 ? PAL[SNOW + 4] : ramp(SNOW, 5, 0.45 - face / height * 0.35, pixel);
		if (face > 1.0 && h < 0.06) {
			color = PAL[SCREE + 1];
		}
	} else if (ice > 0.0) {
		float above = upland_lake(np - vec2(0.0, 1.0));
		color = ramp(ICE, 4, 0.45 + (value_noise(vec2(np.x * 0.2, np.y * 0.6)) - 0.5) * 0.5, pixel);
		if (above <= 0.0) {
			color = PAL[ICE];
		} else if (abs(fbm(np * 0.05 + 7.0) - 0.5) < 0.012) {
			color = PAL[ICE + 3];
		}
	} else {
		if (h > 0.997 - max(rocky, 0.0) * 0.02) {
			color = PAL[SCREE + int(hash12(np * 0.7) * 2.99)];
		}
		if (scree) {
			color = h < 0.45 ? ramp(SCREE, 3, hash12(np * 3.1) * 0.9, pixel) : ramp(SNOW, 5, 0.3, pixel);
		}
		vec4 fir = scree ? vec4(0.0) : upland_fir(pixel, np, grove);
		if (fir.a >= 1.0) {
			color = fir.rgb;
		} else if (fir.a > 0.0) {
			color *= vec3(0.84, 0.87, 0.95);
		}
		if (shaded) {
			color *= vec3(0.86, 0.89, 0.96);
		}
	}
	return mix(color, UPLAND_HAZE, UPLAND_FADE * smoothstep(0.0, 40.0, beyond)
		+ smoothstep(40.0, 900.0, beyond) * 0.12);
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

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size);
	vec2 world = (pixel + 0.5) * texel_size;
	vec2 np = pixel + noise_offset;
	float inside = valley_depth(world) / texel_size;
	vec2 mountains = mountains_at(pixel);
	vec3 color;
	float alpha = 1.0;
	if (inside < 0.0) {
		color = uplands(pixel, np, -inside, mountains.x);
	} else {
		vec4 field = field_at(pixel);
		float lake = byte_of(field.r) - 128.0;
		float trail = byte_of(field.g) / 64.0;
		float crack_depth = byte_of(field.b) - 128.0;
		float extra = byte_of(field.a);
		bool bridge = extra == 255.0;
		float thin = (extra >= 1.0 && extra <= 100.0) ? extra / 100.0 : 0.0;
		float drift = (extra >= 101.0 && extra <= 200.0) ? (extra - 100.0) / 100.0 : 0.0;
		bool in_crevasse = crack_depth >= 0.0 && byte_of(field.b) > 0.0 && !bridge;
		// The snow, with what the wind and the walkers did to it.
		float level = snow_level(np, drift) - clamp(rocky_at(np, mountains.x), 0.0, 1.0) * 0.18
			* (1.0 - smoothstep(0.0, 16.0, inside));
		bool on_snow = lake < -0.5 && byte_of(field.b) < 126.0 && !bridge;
		vec2 mark = (on_snow && trail > 1.05) ? mark_at(pixel) : vec2(0.0);
		level += mark.y * 0.14 - mark.x * 0.26;
		color = ramp(SNOW, 5, level, pixel);
		if (mark.x > 0.45) {
			color = mix(color, PAL[DENT], 0.25);
		}
		if (trail > 1.3 && mark.x <= 0.0 && sparkle(pixel, np)) {
			color = vec3(1.0);
		}
		// Dry stems in patches, thinning towards the foot and the ice.
		if (trail > 1.4 && lake < -3.0 && mark.x <= 0.0 && byte_of(field.b) < 120.0) {
			float patches = smoothstep(0.45, 0.75, value_noise(np / 26.0 + 71.0));
			vec4 blade = tuft(pixel, (0.008 + patches * 0.09) * (1.0 - drift) * smoothstep(0.0, 10.0, inside));
			if (blade.a > 0.0) {
				color = blade.rgb;
			}
		}
		if (trail < 1.0) {
			// Trodden snow, a chain of dents down the middle, the snow piled at its edges.
			float t = 0.62 - trail * 0.3 + (value_noise(np * 0.4) - 0.5) * 0.4;
			color = ramp(PATH, 3, t, pixel);
			if (trail > 0.84) {
				color = PAL[PATH_EDGE];
			}
			vec2 cell = floor(pixel / vec2(3.0, 4.0));
			if (trail < 0.6 && hash12(cell + 0.37) < 0.18) {
				vec2 q = pixel - cell * vec2(3.0, 4.0);
				if (q.x == 1.0 && q.y == 1.0) {
					color = PAL[DENT];
				} else if (q.x == 1.0 && q.y == 2.0) {
					color = PAL[DENT + 1];
				}
			}
		}
		if (lake >= 0.0) {
			// Ice: pale blue, veined white, glints drifting across; it lets the depths show.
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
		} else if (lake > -2.0) {
			color = mix(color, PAL[ICE + 3], 0.4);
		}
		if (in_crevasse) {
			// The north wall: a lit rim, then layers of blue ice dropping fast into the
			// dark; along a crack running north–south its west wall catches the sun, its
			// east one is in shade. The near (south) edge is a snow cornice with deep
			// shade under it. A bridge deck above stands for the rim.
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
		} else if (bridge) {
			// A snow bridge: drifted snow over the crack, sagging and bluer in the middle,
			// a bright lip where it meets the open crack.
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
		// Cracks: white while they spread, grey-blue once they hold.
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
	// The peaks' shadows, their soft edge dithered.
	if (mountains.y * 16.0 > bayer(pixel) + 0.5) {
		color *= MOUNTAIN_SHADE;
	}
	COLOR = vec4(color, alpha);
}
