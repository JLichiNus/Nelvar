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
// same function as NelvarEarthData.Radial. The snow, the ice, the crevasses, the holes,
// the cracks and the marks are ice_common.gdshaderinc's (the cave draws them too).

uniform vec2 base_pixel;             // world art pixel at the viewport's top-left corner
uniform vec2 sea_size;               // viewport size in art pixels
uniform float breath_time = 0.0;     // set by NelvarCloudSea; unused here
uniform float hole_amount = 0.0;     // set by NelvarCloudSea; unused here
uniform vec2 seed_offset;            // set by NelvarCloudSea; unused here

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

vec4 field_at(vec2 pixel) {
	vec2 f = pixel - field_origin;
	if (f.x < 0.0 || f.y < 0.0 || f.x >= field_size.x || f.y >= field_size.y) {
		return vec4(0.0, 1.0, 0.0, 0.0);
	}
	return texelFetch(field_tex, ivec2(f), 0);
}

#include "res://scripts/ice/ice_common.gdshaderinc"

const float WALL_HEIGHT = 11.0;

// The uplands fade towards the menu's pale haze.
const vec3 UPLAND_HAZE = vec3(226.0, 229.0, 234.0) / 255.0;
const float UPLAND_FADE = 0.4;
const float TREE_CELL = 6.0;
// The peaks' cast shadow on snow: cool blue.
const vec3 MOUNTAIN_SHADE = vec3(0.76, 0.8, 0.92);

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
			lake_ice(pixel, np, lake, thin, color, alpha);
		} else if (lake > -2.0) {
			color = mix(color, PAL[ICE + 3], 0.4);
		}
		if (in_crevasse) {
			crevasse_look(pixel, crack_depth, color, alpha);
		} else if (bridge) {
			bridge_look(pixel, np, crack_depth, color, alpha);
		}
		holes_look(pixel, np, color, alpha);
		cracks_look(pixel, color, alpha);
	}
	// The peaks' shadows, their soft edge dithered.
	if (mountains.y * 16.0 > bayer(pixel) + 0.5) {
		color *= MOUNTAIN_SHADE;
	}
	COLOR = vec4(color, alpha);
}
