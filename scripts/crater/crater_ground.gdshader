shader_type canvas_item;
// Disabled blending: the viewport keeps the floor's own alpha, so where there is no
// mountain (past the foot of its side, under the clouds and through their gaps) the
// clouds far below (crater_below.gdshader, on the layer under this one) show through.
// Every pixel is either opaque or fully clear: nothing of the clouds below shows through
// the mountain.
render_mode unshaded, blend_disabled;

// The top of the volcano in the palette of the "Огонь" menu (fire_common): the rim of
// basalt and ash with its roads of cooled lava, sulfur round the vents and geysers, the
// geysers' mouths; the lava lake, swirled brighter and darker, bright along its shores,
// boiling in patches and churning white-hot in the vent (the floes of crust on it are
// sprites); the crater's inner wall under the north shore (a few art pixels of basalt
// strata lit red from below), the faces of the capes. Past the summit's edge the
// mountain's side falls away all round, its walls leaning far out like a huge cone's
// (the camera looks from the south): long under the south edge, broad at the east and
// west flanks, foreshortened beyond the north edge. Ribs and gullies of basalt and ash run down it, lit from
// the upper right, lava trickling down some gullies; it darkens into the haze and sinks
// into the clouds far below: the puffs in front of it hide its foot, through their gaps
// it goes on down into the dark.
//
// Runs through NelvarCloudSea with parallax 1: one fragment per art pixel of the world
// grid. The lake, the capes and the summit's edge are computed here exactly
// as NelvarCraterData does (lava_depth, rim_depth); NelvarCraterField supplies the rest.
// The lake is drawn without screen-fixed dithering and holds still: nothing on it
// shimmers.

uniform vec2 base_pixel;
uniform vec2 sea_size;
uniform float breath_time = 0.0;     // set by NelvarCloudSea; unused here
uniform float hole_amount = 0.0;     // set by NelvarCloudSea; unused here
uniform vec2 seed_offset;            // set by NelvarCloudSea; unused here

uniform float texel_size = 4.0;
uniform float time = 0.0;
uniform vec2 noise_offset;
uniform sampler2D field_tex : filter_nearest, repeat_disable;
uniform vec2 field_origin;
uniform vec2 field_size;
// The lake (a NelvarEarthData.Radial).
uniform vec2 lake_center;
uniform vec2 lake_axes = vec2(1640.0, 1540.0);
uniform float lake_amp[6];
uniform float lake_phase[6];
// The summit's edge: its radius in each of `edge_count` directions round lake_center.
uniform sampler2D edge_tex : filter_nearest, repeat_disable;
uniform int edge_count = 1;
// Capes: base and tip (world), then the half width at the base and at the tip, the
// wobble and its phase.
uniform vec4 cape_line[6];
uniform vec4 cape_form[6];
uniform int cape_count = 0;
uniform float cape_blend = 48.0;
// The vent: world centre and radius. Boiling patches: world centre and radius.
uniform vec3 vent = vec3(0.0, 0.0, 70.0);
uniform vec3 boils[6];
uniform int boil_count = 0;
// Geysers: world art pixel, mouth radius in art pixels, state (0..1 resting, 1..2
// warning, 2..3 erupting).
uniform vec4 geysers[10];
uniform int geyser_count = 0;
// The clouds far below (the "Below" NelvarCloudSea, crater_below): their pixel at a world
// art pixel's place on screen is that pixel + below_shift; how torn their cover is and
// their breath time.
uniform vec2 below_shift;
uniform float below_holes = 0.24;
uniform float below_breath = 0.0;
// The screen's centre (world art pixel) and the clouds' parallax: the mountain's side
// sinks from the summit (parallax 1) to the clouds' top (below_parallax) in perspective.
uniform vec2 view_center;
uniform float below_parallax = 0.6;

#include "res://scripts/fire/fire_common.gdshaderinc"
#include "res://scripts/crater/crater_clouds.gdshaderinc"

// The mountain's side. The camera looks down from the south: a point of the side d art
// pixels below the summit lies d further down the screen, and the side flares out
// flare() pixels for each pixel down, its walls leaning far out. And it is seen in
// perspective round the screen's centre: d below the summit everything is drawn at
// parallax 1 / (1 + d / depth_scale()), down to the clouds' parallax at their top. Deep
// down it lags behind the summit as the camera moves and draws in towards the middle of
// the view. On the north side the walls lean out less than one pixel per pixel down:
// steeper than the line of sight, they never show past the north edge. Round the flanks
// they lean out far more, so the far flanks still spread out downwards in spite of the
// perspective drawing them in: a broad cone, not a column. The south face, seen head on,
// leans out less again: a long wall going far down into the haze.
const float FLARE_NORTH = 0.85;
const float FLARE_FLANK = 2.2;
const float FLARE_SOUTH = 1.0;
// side_point: samples down the line of sight (squared spacing: about a pixel apart at
// the summit's edge, wider deep down) and halvings of the first crossing.
const int SIDE_SAMPLES = 18;
const int SIDE_HALVINGS = 9;
// The side's relief (art pixels either way): its ribs and its broad spurs.
const float RIB_RELIEF = 5.0;
const float SPUR_RELIEF = 36.0;
// The up part of the side's normal for its light (its run out is 1).
const float SLOPE_UP = 0.6;
// How far down (art pixels) the top of the clouds far below lies; it wanders by
// CLOUD_WANDER either way round the mountain. Through the clouds' gaps the side goes on
// DEEP_RUN further, into the dark.
const float CLOUD_DROP = 240.0;
const float CLOUD_WANDER = 0.12;
const float DEEP_RUN = 160.0;
// Each puff is in front of the side or behind it as a whole, by where the middle of its
// base stands: past the mountain's foot (where the side seen there is already under the
// clouds' top) all of it hides the side, its round top too, so the foot sinks into the
// clouds along the puffs' outlines. A puff whose base lies behind the side by `sink`
// still shows where its bulge towards the camera (PUFF_BULGE of its half height in its
// middle, none at its rim) is more than that: one drifting under the edge shrinks away
// behind the side instead of popping.
const float PUFF_BULGE = 0.8;
// How far up the screen a puff reaches at most above its base: the biggest puff's
// (1 + FLAT) half heights, with the wobble of its rim and its breathing.
const float PUFF_HEIGHT = 28.0;
// Ribs round the whole mountain (the seam of their noise is in the north, blended over).
const float RIBS = 104.0;
// Light from the upper right (the menu art's sun), as in crater_below.
const vec3 SUN = vec3(0.4194, -0.5792, 0.6990);
// What the side fades into: the ash clouds' shadowed tone, and the dark far below.
const vec3 DEPTHS = vec3(58.0, 46.0, 50.0) / 255.0;
const vec3 ABYSS = vec3(26.0, 18.0, 22.0) / 255.0;
const vec3 PIT = vec3(20.0, 14.0, 18.0) / 255.0;

// How far the side leans out (art pixels out per pixel down) in a direction from the
// crater's centre (screen y down: sin > 0 is the south).
float flare(float angle) {
	float s = sin(angle);
	return mix(mix(FLARE_NORTH, FLARE_FLANK, smoothstep(-0.45, 0.1, s)), FLARE_SOUTH, smoothstep(0.5, 0.95, s));
}

float smooth_max(float a, float b, float k) {
	float h = max(k - abs(a - b), 0.0) / k;
	return max(a, b) + h * h * k * 0.25;
}

// NelvarEarthData.Radial.signed_distance of the lake.
float lake_sd(vec2 world) {
	vec2 offset = world - lake_center;
	float angle = atan(offset.y, offset.x);
	float c = cos(angle);
	float s = sin(angle);
	float radius = lake_axes.x * lake_axes.y
		/ sqrt(lake_axes.y * lake_axes.y * c * c + lake_axes.x * lake_axes.x * s * s);
	float bend = 1.0;
	for (int i = 0; i < 6; i++) {
		bend += lake_amp[i] * cos(float(i + 2) * angle + lake_phase[i]);
	}
	return radius * bend - length(offset);
}

// NelvarCraterData.Cape.signed_distance.
float cape_sd(int c, vec2 world) {
	vec2 base = cape_line[c].xy;
	vec2 axis = cape_line[c].zw - base;
	float t = clamp(dot(world - base, axis) / max(dot(axis, axis), 0.0001), 0.0, 1.0);
	float width = mix(cape_form[c].x, cape_form[c].y, t) * (1.0 + cape_form[c].z * sin(t * 9.0 + cape_form[c].w));
	return width - length(world - (base + axis * t));
}

// NelvarCraterData.lava_depth: positive in the lake's lava, world units.
float lava_depth(vec2 world) {
	float ground = -lake_sd(world);
	if (ground > 600.0) {
		return -ground;
	}
	for (int c = 0; c < 6; c++) {
		if (c >= cape_count) {
			break;
		}
		ground = smooth_max(ground, cape_sd(c, world), cape_blend);
	}
	return -ground;
}

// The summit's radius in a direction from lake_center (NelvarCraterData.Profile).
float summit_radius(float angle) {
	float t = mod(angle, TAU) / TAU * float(edge_count);
	int i = int(t);
	float f = t - float(i);
	i = i % edge_count;
	float a = texelFetch(edge_tex, ivec2(i, 0), 0).r;
	float b = texelFetch(edge_tex, ivec2((i + 1) % edge_count, 0), 0).r;
	return mix(a, b, f);
}

// NelvarCraterData.rim_depth: positive on the summit, world units.
float summit_sd(vec2 world) {
	vec2 offset = world - lake_center;
	return summit_radius(atan(offset.y, offset.x)) - length(offset);
}

vec4 field_at(vec2 pixel) {
	vec2 f = pixel - field_origin;
	if (f.x < 0.0 || f.y < 0.0 || f.x >= field_size.x || f.y >= field_size.y) {
		return vec4(0.0, 1.0, 1.0, 0.0);
	}
	return texelFetch(field_tex, ivec2(f), 0);
}

// The depth (art pixels) at which the side is drawn at half the summit's parallax: the
// clouds' top (CLOUD_DROP) is at below_parallax.
float depth_scale() {
	return CLOUD_DROP * below_parallax / max(1.0 - below_parallax, 0.01);
}

// The lane round the mountain for an angle: 0..RIBS, growing eastwards along the south
// side (westwards along the north); the seam is in the north.
float lane_of(float angle) {
	return (1.0 - mod(angle + TAU * 0.25, TAU) / TAU) * RIBS;
}

// value_noise over (lane, y), closed round the mountain: it runs into itself at the seam.
float lane_noise(float lane, float y, float scale, float seed) {
	float a = value_noise(vec2(lane * scale, y) + seed);
	float b = value_noise(vec2((lane - RIBS) * scale, y) + seed);
	return mix(a, b, smoothstep(RIBS - 8.0, RIBS, lane));
}

// The ribs down the side at a lane and `depth` screen pixels down: uneven, spreading as
// the mountain widens. Gullies at whole numbers.
float rib_line(float lane, float depth) {
	return lane + (lane_noise(lane, depth * 0.012, 0.23, 5.0) - 0.5) * 1.1
		+ (lane_noise(lane, depth * 0.05, 0.88, 9.0) - 0.5) * 0.3;
}

// How far (art pixels) the side's relief stands out of the smooth cone `drop` below the
// summit: the ribs and broad spurs, growing out from under the edge. Against the clouds
// the flanks show a ragged skyline of ridges, not a smooth curve.
float side_relief(float angle, float drop) {
	float lane = lane_of(angle);
	float depth = drop * length(vec2(cos(angle), sin(angle)) * flare(angle) + vec2(0.0, 1.0));
	float rib = sin(PI * fract(rib_line(lane, depth))) - 0.5;
	float spur = lane_noise(lane, drop * 0.008, 0.35, 41.0) - 0.5;
	return rib * RIB_RELIEF * smoothstep(0.0, 30.0, drop) + spur * SPUR_RELIEF * smoothstep(0.0, 90.0, drop);
}

// The point of the mountain's side seen at a world art pixel of the floor's grid (past
// the summit's edge): how far below the summit it lies (x, art pixels; -1 where the line
// of sight misses the mountain down to `reach`: past the north edge, past the flanks)
// and its direction from the crater's centre (y). Seen d below the summit, the pixel is
// over the world point pixel + d * ((pixel - view_center) / depth_scale() - (0, 1))
// (undoing the perspective and the drop): a straight line out from the crater. The side
// there is the summit's outline grown by flare() * d, and the point is outside it by -g;
// the first d where g turns positive is the side nearest the camera. Lines of sight that
// graze the flanks close in very slowly, so no stepping by g: g is sampled down to
// `reach`, denser near the summit, and the first crossing is halved down to a fraction
// of a pixel.
float side_gap(vec2 q, vec2 line, float d, out float angle) {
	vec2 o = q - line * d;
	angle = atan(o.y, o.x);
	return summit_radius(angle) / texel_size + flare(angle) * d + side_relief(angle, d) - length(o);
}

vec2 side_point(vec2 pixel, float reach) {
	vec2 q = pixel - lake_center / texel_size;
	vec2 line = vec2(0.0, 1.0) - (pixel - view_center) / depth_scale();
	float angle;
	float lo = 0.0;
	float hi = -1.0;
	for (int i = 1; i <= SIDE_SAMPLES; i++) {
		float t = float(i) / float(SIDE_SAMPLES);
		float d = reach * t * t;
		if (side_gap(q, line, d, angle) >= 0.0) {
			hi = d;
			break;
		}
		lo = d;
	}
	if (hi < 0.0) {
		return vec2(-1.0, angle);
	}
	for (int i = 0; i < SIDE_HALVINGS; i++) {
		float mid = (lo + hi) * 0.5;
		if (side_gap(q, line, mid, angle) >= 0.0) {
			hi = mid;
		} else {
			lo = mid;
		}
	}
	side_gap(q, line, hi, angle);
	return vec2(hi, angle);
}


// How far below the summit (art pixels) the top of the clouds lies round the mountain.
float cloud_top(float lane) {
	return CLOUD_DROP * (1.0 + (lane_noise(lane, 3.0, 0.14, 31.0) - 0.5) * 2.0 * CLOUD_WANDER);
}

// Whether the clouds far below hide the side at this pixel, `drop` below the summit
// where their top lies `top` below it: a puff in front of the side (PUFF_BULGE), the
// cover between the puffs where the side goes on under it, and through a gap the side
// past DEEP_RUN, lost in the dark.
bool behind_clouds(vec2 pixel, float drop, float top) {
	vec2 p = floor(pixel + 0.5 + below_shift) + 0.5;
	vec2 foot;
	vec4 puff = puff_with_foot(p, below_holes, below_breath, foot);
	if (puff.z > 0.5) {
		// The side seen at the puff's base: a miss is past the flank or deep under the
		// clouds' top, both in front of the mountain.
		vec2 at = side_point(foot - below_shift, CLOUD_DROP * (1.0 + CLOUD_WANDER));
		if (at.x < 0.0) {
			return true;
		}
		float sink = cloud_top(lane_of(at.y)) - at.x;
		float bulge = sqrt(max(0.0, 1.0 - dot(puff.xy, puff.xy))) * puff.w * PUFF_BULGE;
		return sink < bulge || drop > top + DEEP_RUN;
	}
	if (density(p) > below_holes + 0.03) {
		return drop > top;
	}
	return drop > top + DEEP_RUN;
}

// The mountain's side past the summit's edge where it faces the camera; fully clear where
// it is not seen: behind the top, past the flanks, behind the clouds and far down
// through their gaps.
vec4 mountain_side(vec2 pixel, vec2 np) {
	vec2 at = side_point(pixel + 0.5, CLOUD_DROP * (1.0 + CLOUD_WANDER) + DEEP_RUN);
	float drop = at.x;
	if (drop < 0.0) {
		return vec4(0.0);
	}
	float angle = at.y;
	vec2 out_dir = vec2(cos(angle), sin(angle));
	float lane = lane_of(angle);
	float top = cloud_top(lane);
	// A puff reaches at most PUFF_HEIGHT pixels above its base, near the clouds' top the
	// side climbs at most about 1.6 pixels for each pixel up the screen, and a puff in
	// front has its base at most its bulge (about 12) above the clouds' top, which wanders
	// a little round the mountain: no need to look nearer the summit.
	if (drop > top - PUFF_HEIGHT * 1.6 - 30.0 && behind_clouds(pixel, drop, top)) {
		return vec4(0.0);
	}
	// Screen pixels down the side, along a rib.
	float depth = drop * length(out_dir * flare(angle) + vec2(0.0, 1.0));
	// Ribs and gullies run down, uneven, spreading as the mountain widens.
	float ribs = rib_line(lane, depth);
	float gully = floor(ribs);
	float side = fract(ribs);
	// Lit from the upper right: the east flank bright, the south face and the west in
	// shade. Each rib is lit on the side that faces the light.
	float sun = dot(normalize(vec3(out_dir, SLOPE_UP)), SUN);
	float facing = clamp(dot(vec2(out_dir.y, -out_dir.x), normalize(SUN.xy)) / 0.586, -1.2, 1.2);
	float lit = 0.44 + sun * 0.34
		+ (side - 0.5) * 0.5 * facing
		- smoothstep(0.0, top, drop) * 0.36
		+ (lane_noise(lane, depth * 0.13, 4.0, 23.0) - 0.5) * 0.1;
	vec3 color = ramp(BASALT, 5, lit, pixel);
	// Ash lies in drifts streaked down the side, thickest near the top.
	float ash = lane_noise(lane, depth * 0.016, 1.26, 17.0) - smoothstep(0.0, top * 0.8, drop) * 0.3;
	if ((ash - 0.6) * 90.0 > bayer(pixel) + 0.5) {
		color = ramp(ASH, 4, lit - 0.12, pixel);
	} else if (lane_noise(lane, depth * 0.014, 1.8, 61.0) > 0.78) {
		color = ramp(CINDER, 3, lit - 0.05, pixel);
	}
	// The gully floor: a dark line between ribs, lost here and there under ash.
	if (side < 0.06 && value_noise(vec2(gully * 3.7, depth * 0.05)) > 0.3) {
		color = PAL[BASALT];
	}
	// Ledges of harder rock across the side: a lit top over a shadow, short and few.
	float ledge = depth + (lane_noise(lane, 2.0, 2.2, 0.0) - 0.5) * 12.0;
	float step_row = fract(ledge / 23.0) * 23.0;
	if (lane_noise(lane, floor(ledge / 23.0) * 3.1, 1.6, 0.0) > 0.64) {
		if (step_row < 1.0) {
			color = PAL[BASALT + 3];
		} else if (step_row < 2.0) {
			color = PAL[BASALT];
		}
	}
	// Lava trickling down a few gullies, from under the edge.
	if (hash12(vec2(gully, 11.3)) < 0.12) {
		float start = 2.0 + hash12(vec2(gully, 2.1)) * 24.0;
		float length_run = 60.0 + hash12(vec2(gully, 7.9)) * 170.0;
		float width = 0.045 * (1.0 - smoothstep(start + length_run * 0.5, start + length_run, depth)) + 0.02;
		if (depth > start && depth < start + length_run) {
			float off = abs(side - 0.08);
			if (off < width) {
				float streak = fract((depth - time * 5.0) / 7.0 + hash12(vec2(gully, 4.7)));
				color = streak < 0.16 ? PAL[LAVA + 3] : (streak < 0.55 ? PAL[LAVA + 2] : PAL[LAVA + 1]);
			} else if (off < width + 0.05) {
				color = mix(color, SCORCH, 0.55);
			}
		}
	}
	// Into the haze towards the clouds, in dithered steps (nothing is see-through), and
	// on down into the dark through their gaps.
	float haze = smoothstep(top * 0.15, top, drop);
	if (haze * 16.0 > bayer(pixel) + 0.5) {
		color = mix(color, DEPTHS, 0.3 + haze * 0.35);
	} else {
		color = mix(color, DEPTHS, haze * 0.4);
	}
	float deep = clamp((drop - top) / DEEP_RUN, 0.0, 1.0);
	if (deep > 0.0) {
		color = mix(color, ABYSS, deep * deep * (3.0 - 2.0 * deep) * 0.6 + (deep * 16.0 > bayer(pixel) + 0.5 ? 0.4 * deep : 0.0));
	}
	// The lip where the flat top breaks into the side: lit where it faces the camera, the
	// side just under it in its shadow.
	if (depth < 1.0) {
		color = out_dir.y > 0.2 ? PAL[BASALT + 3] : PAL[BASALT + 1];
	} else if (depth < 2.0 && out_dir.y > 0.2) {
		color = PAL[BASALT];
	} else if (depth < 10.0 && (10.0 - depth) * 2.4 > bayer(pixel) + 0.5) {
		color *= 0.74;
	}
	return vec4(color, 1.0);
}

// 0..1: how hard the lava boils here.
float boiling(vec2 world, vec2 np) {
	float best = 0.0;
	for (int i = 0; i < 6; i++) {
		if (i >= boil_count) {
			break;
		}
		float d = length(world - boils[i].xy) / boils[i].z + (value_noise(np * 0.12) - 0.5) * 0.3;
		best = max(best, 1.0 - smoothstep(0.45, 1.0, d));
	}
	return best;
}

// The lake: lava swirled brighter and darker in broad flat bands, hottest over the boils
// and round the vent, bubbles bursting; the white-hot vent churning in the middle.
vec3 crater_lava(vec2 pixel, vec2 np, float depth, vec2 world) {
	float r = length(world - vent.xy);
	float mouth = (r - vent.z) / texel_size + (value_noise(np * 0.12) - 0.5) * 5.0;
	if (mouth < 0.0) {
		// The vent: white-hot lava welling up and churning.
		float churn = hash12(pixel + floor(time * 3.0 + hash12(pixel) * 3.0) * 5.3);
		return churn < 0.25 ? PAL[LAVA + 5] : (churn < 0.7 ? PAL[LAVA + 4] : PAL[LAVA + 3]);
	}
	if (mouth < 2.5 && value_noise(np * 0.2 + 9.0) > 0.38) {
		// Its rim of spatter, broken, cracked and glowing.
		vec3 c = cells(np / 3.0);
		return c.y < 0.1 ? PAL[LAVA + 2] : ramp(CRUST, 3, 0.2 + c.z * 0.6, pixel);
	}
	float near_vent = 1.0 - smoothstep(0.0, 56.0, mouth);
	float boil = boiling(world, np);
	float swirl = value_noise(np / 22.0) * 0.7 + value_noise(np / 9.0 + 3.0) * 0.3;
	float heat = swirl * 0.8 + boil * 0.35 + near_vent * 0.45;
	vec3 color = heat < 0.4 ? PAL[LAVA + 2] : (heat < 0.64 ? PAL[LAVA + 3] : (heat < 0.84 ? PAL[LAVA + 4] : PAL[LAVA + 5]));
	float bubbles = 0.002 + boil * 0.05 + near_vent * 0.04;
	if (hash12(floor(np / 3.0) + floor(time * (1.2 + boil * 2.0)) * 7.0) < bubbles) {
		color = PAL[LAVA + 5];
	}
	if (depth < 1.0) {
		color = PAL[LAVA + 3];
	}
	return color;
}

// The crater's inner wall under the north shore: `k` rows below the rim's lip, of `h`.
// Strata of basalt, the lowest row lit red by the lava.
vec3 crater_wall(vec2 pixel, vec2 np, float k, float h) {
	if (k >= h) {
		return PAL[LAVA];
	}
	if (k <= 1.0) {
		return PAL[BASALT + 3];
	}
	float band = hash12(vec2(floor((pixel.y + floor(value_noise(vec2(pixel.x * 0.1, 2.0)) * 3.0)) / 1.0), 7.3));
	vec3 color = band < 0.35 ? PAL[BASALT + 2] : (band < 0.8 ? PAL[BASALT + 1] : PAL[CRUST + 1]);
	if (k >= h - 1.0) {
		color = mix(color, PAL[LAVA], 0.45);
	}
	return color;
}

vec3 geyser_mouth(vec3 color, vec2 pixel, vec2 np) {
	for (int i = 0; i < 10; i++) {
		if (i >= geyser_count) {
			break;
		}
		vec4 g = geysers[i];
		vec2 o = (pixel + 0.5 - g.xy) * vec2(1.0, 1.35);
		float d = length(o) / g.z;
		if (d > 1.9) {
			continue;
		}
		float warn = clamp(g.w - 1.0, 0.0, 1.0);
		float burst = clamp(g.w - 2.0, 0.0, 1.0);
		bool erupting = g.w >= 2.0;
		if (d < 0.55) {
			color = PIT;
			float heat = erupting ? 1.0 - burst * 0.5 : warn * (0.6 + 0.4 * abs(sin(time * 14.0)));
			if (d < 0.2 + heat * 0.32) {
				float churn = hash12(pixel + floor(time * 6.0) * 3.1);
				color = heat > 0.7 ? (churn < 0.4 ? PAL[LAVA + 4] : PAL[LAVA + 3])
					: (heat > 0.25 ? PAL[LAVA + 2] : (churn < 0.5 ? PAL[CRUST + 1] : PIT));
			}
		} else if (d < 0.9) {
			// Geyserite: pale mineral crust round the mouth.
			float n = value_noise(np * 0.5);
			color = n < 0.45 ? PAL[ASH + 3] : (n < 0.75 ? PAL[SULFUR + 3] : PAL[ASH + 2]);
			if (erupting && hash12(pixel + floor(time * 10.0)) < 0.2) {
				color = PAL[LAVA + 3];
			}
		} else if (d < 1.3) {
			if (value_noise(np * 0.4 + 3.0) > 0.45) {
				color = mix(color, PAL[ASH + 2], 0.6);
			}
			if (erupting) {
				color *= 0.82;
			}
		}
		// The warning: a ring of tremor running out over the ground.
		float ring = 1.0 + warn * 0.8;
		if (warn > 0.0 && !erupting && abs(d - ring) < 0.09 && hash12(pixel + floor(time * 12.0)) < 0.7) {
			color = mix(color, PAL[ASH + 3], 0.7);
		}
	}
	return color;
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size);
	vec2 world = (pixel + 0.5) * texel_size;
	vec2 np = pixel + noise_offset;
	float edge = summit_sd(world) / texel_size;
	if (edge < 0.0) {
		COLOR = mountain_side(pixel, np);
	} else {
		float lava = lava_depth(world) / texel_size;
		vec3 color;
		if (lava >= 0.0) {
			// Is there rock just above? Then this is its face, lit by the lava below it.
			float above = 0.0;
			bool rim_above = false;
			for (int k = 1; k <= 5; k++) {
				vec2 up = world - vec2(0.0, float(k) * texel_size);
				if (lava_depth(up) < 0.0) {
					above = float(k);
					rim_above = lake_sd(up) < 0.0;
					break;
				}
			}
			float wall = 3.0 + floor(value_noise(vec2(pixel.x / 11.0, 4.2)) * 2.99);
			if (above > 0.0 && rim_above && above <= wall) {
				color = crater_wall(pixel, np, above, wall);
			} else if (above > 0.0 && !rim_above && above <= 2.0) {
				color = above < 1.5 ? PAL[CRUST] : PAL[LAVA];
			} else if (rim_above && above > 0.0 && above <= wall + 1.0) {
				color = PAL[LAVA + 3];
			} else {
				color = crater_lava(pixel, np, lava, world);
			}
		} else {
			vec4 field = field_at(pixel);
			float g = floor(field.g * 255.0 + 0.5);
			float a = floor(field.a * 255.0 + 0.5);
			color = bare_ground(pixel, np, 0.0);
			if (edge < 3.0 && (3.0 - edge) / 3.0 * 64.0 > bayer(pixel) + 44.0) {
				// Loose scree near the edge.
				color = hash12(np) < 0.5 ? ramp(SCREE, 3, hash12(np * 3.1), pixel) : PAL[CINDER];
			}
			if (a > 0.5 && a < 100.5) {
				float s = a / 100.0;
				float n = value_noise(np / 5.0 + 7.0) * 0.7 + value_noise(np / 2.0) * 0.3;
				if (n < s * 1.2 - 0.1) {
					color = ramp(SULFUR, 4, 0.25 + s * 0.45 + (hash12(np * 1.9) - 0.5) * 0.3, pixel);
					if (hash12(np * 3.3) < 0.03) {
						color = PAL[SULFUR + 3];
					}
				} else if (n < s * 1.2) {
					color = PAL[SULFUR];
				}
			}
			float road = g / 64.0;
			if (road < 1.0) {
				color = flow_color(pixel, np, road);
			}
			color = geyser_mouth(color, pixel, np);
			if (lava > -1.0) {
				color = PAL[CRUST];
			} else if (lava > -6.0) {
				float warm = (6.0 + lava) / 6.0;
				if (warm * 16.0 > bayer(pixel) + 0.5) {
					color = mix(color, SCORCH, 0.5);
				}
			}
			if (edge < 1.0) {
				// The summit's outline against the depths: the south lip is lit, the rest
				// is a dark line.
				vec2 out_dir = normalize(world - lake_center);
				color = out_dir.y > 0.35 ? PAL[BASALT + 3] : PAL[BASALT];
			}
		}
		COLOR = vec4(color, 1.0);
	}
}
