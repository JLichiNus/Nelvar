shader_type canvas_item;
render_mode unshaded;

// The Void beneath and around everything: slow, warped dark matter in black, violet,
// deep blue and grey; cracks of cold light; stars that are not quite stars; broken
// halos hanging far away. When `dread` rises, something vast opens its eye.
//
// Driven by NelvarCloudSea (cloud_sea.gd) with this shader: one fragment per sky pixel
// in a small viewport, stretched over the screen.

uniform vec2 base_pixel;
uniform vec2 sea_size;
uniform float breath_time = 0.0;
uniform vec2 seed_offset;
uniform float dread = 0.0;

const vec3 VIOLET[5] = vec3[5](
	vec3(3.0, 2.0, 6.0) / 255.0, vec3(10.0, 7.0, 20.0) / 255.0, vec3(19.0, 12.0, 36.0) / 255.0,
	vec3(29.0, 18.0, 54.0) / 255.0, vec3(42.0, 26.0, 74.0) / 255.0
);
const vec3 BLUE[5] = vec3[5](
	vec3(3.0, 3.0, 8.0) / 255.0, vec3(7.0, 11.0, 22.0) / 255.0, vec3(12.0, 20.0, 38.0) / 255.0,
	vec3(20.0, 30.0, 54.0) / 255.0, vec3(30.0, 42.0, 70.0) / 255.0
);
const vec3 GREY[5] = vec3[5](
	vec3(4.0, 4.0, 5.0) / 255.0, vec3(11.0, 11.0, 15.0) / 255.0, vec3(19.0, 19.0, 25.0) / 255.0,
	vec3(28.0, 28.0, 36.0) / 255.0, vec3(38.0, 38.0, 47.0) / 255.0
);
const vec3 RIFT = vec3(98.0, 62.0, 168.0) / 255.0;
const vec3 EYE_GLOW = vec3(150.0, 90.0, 255.0) / 255.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

float fbm(vec2 p) {
	float sum = 0.0;
	float amp = 0.5;
	for (int i = 0; i < 4; i++) {
		sum += value_noise(p) * amp;
		p = p * 2.03 + vec2(17.1, 9.7);
		amp *= 0.5;
	}
	return sum;
}

float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

vec3 pick(int ramp, int i) {
	if (ramp == 0) {
		return GREY[i];
	} else if (ramp == 1) {
		return VIOLET[i];
	}
	return BLUE[i];
}

vec3 ramp_color(int ramp, float level, vec2 pixel) {
	float t = clamp(level, 0.0, 0.9999) * 4.0;
	int i = int(t);
	if ((t - float(i)) * 16.0 > bayer4(pixel) * 16.0 + 0.5) {
		i += 1;
	}
	return pick(ramp, i);
}

// A halo far away, broken in places; its gaps turn slowly.
float halo(vec2 p, float time) {
	vec2 cell = floor(p / 230.0);
	if (hash12(cell + 3.7) > 0.13) {
		return 0.0;
	}
	vec2 center = (cell + 0.25 + vec2(hash12(cell), hash12(cell + 1.3)) * 0.5) * 230.0;
	float radius = mix(26.0, 60.0, hash12(cell + 2.1));
	vec2 d = p - center;
	float r = length(d);
	if (abs(r - radius) > 0.6 && abs(r - radius * 0.8) > 0.5) {
		return 0.0;
	}
	float angle = atan(d.y, d.x) + time * 0.02 * (hash12(cell + 5.5) - 0.5);
	float gaps = sin(angle * (2.0 + floor(hash12(cell + 4.4) * 4.0)));
	return gaps > -0.2 ? 1.0 : 0.0;
}

// Eyes open all over the Void as `open` rises, each in its own cell, blinking on its
// own; their pupils turn to the middle of the screen, where the player stands.
vec3 eyes(vec2 p, vec2 watched, float open, vec2 pixel, vec3 color) {
	vec2 cell = floor(p / 64.0);
	float chance = hash12(cell + 8.3);
	if (chance > 0.3 * open) {
		return color;
	}
	vec2 center = (cell + 0.3 + vec2(hash12(cell + 1.1), hash12(cell + 2.2)) * 0.4) * 64.0;
	float width = mix(7.0, 15.0, hash12(cell + 3.3));
	vec2 q = p - center;
	float x = q.x / width;
	if (abs(x) >= 1.0) {
		return color;
	}
	float closing = smoothstep(0.45, 0.5, abs(fract(breath_time / mix(7.0, 13.0, hash12(cell + 4.4))
		+ hash12(cell + 5.5)) - 0.5));
	float lid = width * 0.42 * (1.0 - closing) * min(1.0, open * 1.5) * (1.0 - x * x);
	if (abs(q.y) < lid) {
		vec2 look = normalize(watched - center + vec2(0.001)) * width * 0.3;
		float iris = length(q - look);
		if (iris < width * 0.18) {
			return vec3(0.0);
		} else if (iris < width * 0.32) {
			return mix(EYE_GLOW, color, 0.25);
		}
		return mix(color, vec3(0.55, 0.5, 0.62), 0.55);
	} else if (abs(abs(q.y) - lid) < 0.6 && lid > 0.5) {
		return mix(color, EYE_GLOW, 0.5);
	}
	return color;
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size) + seed_offset;
	vec2 p = pixel + 0.5;
	float t = breath_time;
	// Warped dark matter, drifting very slowly.
	vec2 warp = vec2(fbm(p / 150.0 + vec2(t * 0.012, 0.0)), fbm(p / 150.0 + vec2(5.2, -t * 0.009)));
	float n = fbm(p / 95.0 + warp * 1.6);
	float region = fbm(p / 260.0 + warp * 0.5 + 11.0);
	int ramp = region < 0.4 ? 0 : (region < 0.58 ? 1 : 2);
	// Mostly near-black; the clouds of matter catch a little light.
	float level = pow(n, 2.2) * 1.6 - 0.05 + dread * 0.08;
	vec3 color = ramp_color(ramp, level, pixel);
	if (ramp == 1 && dread > 0.0) {
		color = mix(color, VIOLET[3], dread * 0.15 * n);
	}
	// Cracks of cold light where the matter folds.
	float fold = fbm(p / 60.0 - warp * 2.0 + 3.0);
	if (abs(fold - 0.5) < 0.0045 && value_noise(p / 120.0 + 7.0) > 0.55) {
		color = mix(color, RIFT, 0.5 + 0.3 * sin(t * 0.7 + p.x * 0.05));
	}
	// Halos far away.
	if (halo(p, t) > 0.5) {
		color = mix(color, ramp == 2 ? BLUE[4] : VIOLET[4], 0.7);
	}
	// Stars, slowly breathing; a rare red one blinks like it is watching.
	float star = hash12(pixel * 1.37 + 0.5);
	if (star > 0.9975) {
		float phase = hash12(pixel + 9.1) * 6.2832;
		float twinkle = 0.5 + 0.5 * sin(t * (0.6 + hash12(pixel + 3.3) * 1.4) + phase);
		vec3 tint = hash12(pixel + 1.7) > 0.5 ? vec3(0.72, 0.62, 0.95) : vec3(0.6, 0.72, 0.92);
		if (star > 0.99985) {
			tint = vec3(0.9, 0.25, 0.28);
			twinkle = step(0.93, fract(t * 0.09 + phase));
			twinkle = 1.0 - twinkle;
		}
		color = mix(color, tint, 0.25 + 0.55 * twinkle);
	}
	if (dread > 0.01) {
		vec2 watched = base_pixel + sea_size * 0.5 + seed_offset;
		color = eyes(p, watched, dread, pixel, color);
	}
	COLOR = vec4(color, 1.0);
}
