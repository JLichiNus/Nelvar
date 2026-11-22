shader_type canvas_item;
// Main menu background: the same place in one of the four realities.
// from_* is the reality currently shown, to_* the one flowing in.
// The node's own texture is only used for sizing (same size as all backgrounds).
//
// fx masks: R = glints (water, ice, snow), G = pulsing glow (lava, embers),
//           B = gentle sway (foliage, grass, clouds).

uniform sampler2D from_tex : filter_nearest;
uniform sampler2D from_fx : filter_nearest, hint_default_black;
uniform vec4 from_glow : source_color = vec4(1.0);
uniform sampler2D to_tex : filter_nearest;
uniform sampler2D to_fx : filter_nearest, hint_default_black;
uniform vec4 to_glow : source_color = vec4(1.0);

// Reality wave: grows from `origin` (texture UV) while progress goes 0 -> 1.
uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec2 origin = vec2(0.2, 0.5);
uniform vec4 edge_color : source_color = vec4(1.0);
uniform float wave_band = 0.09;
uniform float wave_distortion = 0.012;

// "Breathing" of the living environment: xy = point in texture UV,
// z = radius in UV.y units (0 disables the point).
uniform vec3 breath_points[4];
uniform vec4 breath_phase = vec4(0.0, 1.7, 3.1, 4.6);
uniform vec4 breath_speed = vec4(0.8, 0.7, 0.9, 0.6);
uniform float breath_amount = 0.16;

uniform float sway_amount = 1.2;
uniform float glint_amount = 0.3;
uniform float glow_amount = 0.5;
uniform float vignette = 0.35;

// Small per-launch palette drift ("the menu mutates too").
uniform float hue_shift = 0.0;
uniform vec4 tint : source_color = vec4(1.0);

float hash(vec2 p) {
	return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

float value_noise(vec2 p) {
	vec2 i = floor(p);
	vec2 f = fract(p);
	vec2 u = f * f * (3.0 - 2.0 * f);
	float a = hash(i);
	float b = hash(i + vec2(1.0, 0.0));
	float c = hash(i + vec2(0.0, 1.0));
	float d = hash(i + vec2(1.0, 1.0));
	return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// Ordered 4x4 Bayer threshold in [0, 1): crisp pixel-art dithering.
float bayer2(vec2 a) {
	a = floor(a);
	return fract(a.x / 2.0 + a.y * a.y * 0.75);
}

float bayer4(vec2 a) {
	return bayer2(0.5 * a) * 0.25 + bayer2(a);
}

vec3 rgb2hsv(vec3 c) {
	vec4 k = vec4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
	vec4 p = mix(vec4(c.bg, k.wz), vec4(c.gb, k.xy), step(c.b, c.g));
	vec4 q = mix(vec4(p.xyw, c.r), vec4(c.r, p.yzx), step(p.x, c.r));
	float d = q.x - min(q.w, q.y);
	float e = 1.0e-10;
	return vec3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
}

vec3 hsv2rgb(vec3 c) {
	vec3 p = abs(fract(c.xxx + vec3(1.0, 2.0 / 3.0, 1.0 / 3.0)) * 6.0 - 3.0);
	return c.z * mix(vec3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// One reality with its living details applied.
vec3 reality(sampler2D tex, sampler2D fx, vec4 glow, vec2 uv, vec2 tex_size) {
	float sway_mask = texture(fx, uv).b;
	float sway = sin(TIME * 1.4 + uv.y * 38.0 + uv.x * 7.0) + 0.4 * sin(TIME * 2.3 + uv.x * 23.0);
	vec2 suv = uv + vec2(sway_mask * sway * sway_amount / tex_size.x, 0.0);
	vec3 c = texture(tex, suv).rgb;
	vec3 m = texture(fx, suv).rgb;
	// Glints: slow diagonal light bands; snapped to texels so they stay pixel-crisp.
	vec2 texel = floor(suv * tex_size);
	float band = sin(TIME * 1.8 + texel.x * 0.21 - texel.y * 0.45);
	float sparkle = step(0.985, hash(texel + floor(TIME * 3.0)));
	float glint = pow(max(band, 0.0), 10.0) + sparkle * 0.6;
	c += m.r * glint * glint_amount;
	// Glow: lava and embers breathe heat.
	float heat = 0.5 + 0.5 * sin(TIME * 1.6 + value_noise(texel * 0.08 + TIME * 0.3) * 6.28);
	c += glow.rgb * m.g * heat * glow_amount;
	return c;
}

void fragment() {
	vec2 tex_size = 1.0 / TEXTURE_PIXEL_SIZE;
	vec2 aspect = vec2(tex_size.x / tex_size.y, 1.0);
	vec2 uv = UV;

	for (int i = 0; i < 4; i++) {
		vec3 point = breath_points[i];
		if (point.z <= 0.0) {
			continue;
		}
		vec2 d = (UV - point.xy) * aspect;
		float falloff = 1.0 - smoothstep(0.0, point.z, length(d));
		// Sharpened sine: a short swell every few seconds, still otherwise.
		float pulse = pow(max(0.0, sin(TIME * breath_speed[i] + breath_phase[i])), 8.0);
		uv -= d / aspect * falloff * pulse * breath_amount;
	}

	// Reality wave front, slightly irregular so it reads as something alive.
	vec2 rel = (UV - origin) * aspect;
	float dist = length(rel) + (value_noise(UV * aspect * 7.0) - 0.5) * 0.1;
	vec2 far_corner = max(origin, vec2(1.0) - origin) * aspect;
	float front = progress * (length(far_corner) + wave_band + 0.08);
	float active = step(0.0001, progress) * step(progress, 0.9999);
	// Refraction ripple riding on the front.
	float ring = exp(-pow((dist - front) / 0.045, 2.0)) * active;
	uv += normalize(rel + vec2(1.0e-5)) / aspect * ring * wave_distortion;

	vec2 cell = floor(UV * tex_size);
	float k = (front - dist) / wave_band;
	float threshold = bayer4(cell);
	float shown = step(threshold, k);

	vec3 color;
	if (shown > 0.5) {
		color = reality(to_tex, to_fx, to_glow, uv, tex_size);
	} else {
		color = reality(from_tex, from_fx, from_glow, uv, tex_size);
	}
	// Glowing edge: the pixels just about to change.
	float edge = step(threshold - 0.35, k) * (1.0 - shown) * active;
	color = mix(color, edge_color.rgb, edge * 0.85);
	// Soft light along the front and a faint overall flash.
	color += edge_color.rgb * ring * 0.18;
	color += edge_color.rgb * sin(progress * PI) * 0.05;

	vec3 hsv = rgb2hsv(color);
	hsv.x = fract(hsv.x + hue_shift);
	color = hsv2rgb(hsv) * tint.rgb;

	vec2 v = (UV - 0.5) * aspect;
	color *= 1.0 - vignette * smoothstep(0.45, 1.15, length(v));
	COLOR = vec4(color, 1.0);
}
