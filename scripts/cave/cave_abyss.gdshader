shader_type canvas_item;
render_mode unshaded;

// The depth under the cave's chasms (NelvarCloudSea, the "Abyss" layer under the depths
// and the floor, which are clear over the chasms): dark blue going down forever, ledges
// of ice jutting out with lit lips, slow bands of mist, snow dust settling, now and then a
// glint far down — and very rarely, very far down, the shape of something enormous.
//
// It lies far below the floor: it follows the camera only by its parallax, so the chasm
// plainly opens onto a great depth.

uniform vec2 base_pixel;             // abyss pixel at the viewport's top-left corner
uniform vec2 sea_size;
uniform float breath_time = 0.0;     // seconds
uniform float hole_amount = 0.0;     // unused
uniform vec2 seed_offset;            // a different depth per world

const vec3 DEPTH[5] = vec3[5](vec3(8.0, 16.0, 40.0) / 255.0, vec3(14.0, 30.0, 64.0) / 255.0,
	vec3(22.0, 46.0, 92.0) / 255.0, vec3(34.0, 66.0, 120.0) / 255.0, vec3(50.0, 90.0, 150.0) / 255.0);
const vec3 LEDGE[4] = vec3[4](vec3(36.0, 64.0, 112.0) / 255.0, vec3(56.0, 94.0, 150.0) / 255.0,
	vec3(90.0, 136.0, 190.0) / 255.0, vec3(160.0, 204.0, 240.0) / 255.0);
const vec3 MIST = vec3(96.0, 128.0, 172.0) / 255.0;
const vec3 GIANT = vec3(1.0, 2.0, 7.0) / 255.0;
const float BAYER[16] = float[16](0.0, 8.0, 2.0, 10.0, 12.0, 4.0, 14.0, 6.0, 3.0, 11.0, 1.0, 9.0,
	15.0, 7.0, 13.0, 5.0);

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

float bayer(vec2 pixel) {
	vec2 m = mod(pixel, 4.0);
	return BAYER[int(m.y) * 4 + int(m.x)];
}

vec3 ramp5(float level, vec2 pixel) {
	float t = clamp(level, 0.0, 0.9999) * 4.0;
	int i = int(t);
	if ((t - float(i)) * 16.0 > bayer(pixel) + 0.5) {
		i += 1;
	}
	return DEPTH[i];
}

// A ledge of ice: above zero in it.
float ledge(vec2 p, float scale, float salt) {
	return value_noise(p * vec2(scale, scale * 2.6) + salt) * 0.75 + value_noise(p * scale * 4.0 + salt * 3.0) * 0.25 - 0.64;
}

// Something enormous far down: a body, a neck, a head, a tail; above zero in it.
float giant(vec2 p) {
	vec2 cell = floor(p / vec2(700.0, 460.0));
	if (hash12(cell + 0.21) > 0.16) {
		return -1.0;
	}
	vec2 center = (cell + vec2(0.3, 0.3) + vec2(hash12(cell + 1.7), hash12(cell + 2.9)) * 0.4) * vec2(700.0, 460.0);
	vec2 d = p - center;
	float side = hash12(cell + 4.1) < 0.5 ? -1.0 : 1.0;
	float body = 1.0 - length(d / vec2(150.0, 64.0));
	vec2 neck = d - vec2(side * 160.0, -30.0 + sin(d.x * 0.02) * 10.0);
	float head = 1.0 - length(neck / vec2(60.0, 34.0));
	float tail = 1.0 - abs(d.y - sin(d.x * 0.015) * 30.0 - 20.0) / (18.0 * clamp(1.0 - abs(d.x + side * 200.0) / 260.0, 0.0, 1.0) + 0.001);
	if (d.x * side > -60.0) {
		tail = -1.0;
	}
	return max(max(body, head), tail * 0.6);
}

void fragment() {
	vec2 pixel = base_pixel + floor(UV * sea_size);
	vec2 p = pixel + seed_offset;
	float level = 0.38 + (value_noise(p * 0.004) - 0.5) * 0.5 + (value_noise(p * 0.02) - 0.5) * 0.15;
	vec3 color = ramp5(level, pixel);
	if (giant(p) > 0.0) {
		color = mix(color, GIANT, 0.75);
	}
	// Two layers of ledges, the nearer lit at its upper lip.
	float far = ledge(p, 0.012, 91.0);
	if (far > 0.0) {
		color = LEDGE[0];
		if (ledge(p - vec2(0.0, 1.0), 0.012, 91.0) <= 0.0) {
			color = LEDGE[1];
		}
	}
	float near = ledge(p, 0.022, 17.0);
	if (near > 0.0) {
		color = LEDGE[1 + int(clamp(near * 6.0, 0.0, 1.0) * 1.0)];
		if (ledge(p - vec2(0.0, 1.0), 0.022, 17.0) <= 0.0) {
			color = LEDGE[3];
		} else if (ledge(p - vec2(0.0, 2.0), 0.022, 17.0) <= 0.0) {
			color = LEDGE[2];
		}
	}
	// Bands of mist drifting across.
	float band = sin(p.y * 0.045 + value_noise(p * 0.008 + vec2(breath_time * 0.03, 0.0)) * 5.0);
	float mist = smoothstep(0.55, 0.95, band) * (0.5 + 0.5 * value_noise(vec2(p.x * 0.01 + breath_time * 0.08, p.y * 0.02)));
	if (mist * 16.0 > bayer(pixel) + 0.5) {
		color = mix(color, MIST, 0.5);
	}
	// Snow dust settling, and a glint now and then.
	vec2 cell = floor(p / 9.0);
	float h = hash12(cell + 0.5);
	if (h < 0.05) {
		float fall = mod(breath_time * 5.0 + h * 400.0, 9.0);
		vec2 at = cell * 9.0 + vec2(floor(hash12(cell + 3.3) * 8.0), floor(fall));
		if (floor(p) == at) {
			color = LEDGE[3];
		}
	}
	if (hash12(floor(p / 3.0) + floor(breath_time * 0.8) * 7.0) < 0.0004) {
		color = vec3(0.55, 0.7, 0.85);
	}
	COLOR = vec4(color, 1.0);
}
