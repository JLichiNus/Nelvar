shader_type canvas_item;
render_mode unshaded;

// Clouds of ash far below the volcano's top (NelvarCloudSea, the "Below" layer under the
// transparent floor): the air map's sea of clouds (cloud_sea.gdshader, left as it is)
// in the smoky palette of the "Огонь" menu, lit from the upper right and warmed from
// below. Where the cover tears open the land shows far down: dark basalt with rivers of
// lava glowing through the haze.
//
// It lies deep below the summit: it follows the camera only by its parallax and drifts
// slowly with the wind, so the top of the mountain plainly stands far above it. The
// puffs are crater_clouds.gdshaderinc's; the floor finds them too, to sink the
// mountain's foot into them.

uniform vec2 base_pixel;             // sea pixel at the viewport's top-left corner
uniform vec2 sea_size;               // viewport size in sea pixels
uniform float breath_time = 0.0;     // seconds; puffs slowly swell and settle
uniform float hole_amount = 0.14;    // 0 = solid cover; higher tears more and wider gaps
uniform vec2 seed_offset;            // integer pixel offset: a different sea per world

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

#include "res://scripts/crater/crater_clouds.gdshaderinc"

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size) + seed_offset;
	vec2 p = pixel + 0.5;
	// Broad, soft variation of tone: the sea is not evenly lit everywhere.
	float tone = (value_noise(p / 150.0 + 41.0) - 0.5) * 0.2;
	vec4 puff = puff_at(p, hole_amount, breath_time);
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
		if (puff_at(p + vec2(0.0, -3.0), hole_amount, breath_time).z > 0.5) {
			color *= 0.55;
		} else if (puff_at(p + vec2(0.0, -7.0), hole_amount, breath_time).z > 0.5) {
			color *= 0.78;
		}
	}
	COLOR = vec4(color, 1.0);
}
