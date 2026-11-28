shader_type canvas_item;
render_mode unshaded;

// A blizzard over the screen (NelvarBlizzard): a pale veil and slanting dashes of
// snow, both as strong as the blizzard is where the player stands. Before one arrives,
// snow already streams along the edge of the screen it comes from. The dashes are
// whole art pixels of the world, carried by the wind.

uniform float strength = 0.0;        // 0..1 at the player
uniform float warning = 0.0;         // 0..1 as a blizzard draws near
uniform vec2 warning_side = vec2(1.0, 0.0);   // screen direction it comes from
uniform vec2 view_origin;            // world point at the screen's top-left corner
uniform float view_scale = 1.0;      // world units per screen pixel
uniform float texel_size = 4.0;
uniform float time = 0.0;

const vec3 VEIL = vec3(228.0, 233.0, 240.0) / 255.0;
const vec3 FLAKE = vec3(250.0, 251.0, 252.0) / 255.0;

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
	return mix(mix(hash12(i), hash12(i + vec2(1.0, 0.0)), u.x),
		mix(hash12(i + vec2(0.0, 1.0)), hash12(i + vec2(1.0, 1.0)), u.x), u.y);
}

// A dash of snow flying with the wind; `speed` in art pixels per second.
bool dash(vec2 pixel, float density, float speed, float salt) {
	vec2 q = vec2(pixel.x - pixel.y * 0.35 - time * speed, pixel.y);
	vec2 cell = floor(q / vec2(18.0, 3.0));
	vec3 h = hash32(cell + salt);
	if (h.x >= density || mod(q.y, 3.0) >= 1.0) {
		return false;
	}
	float start = floor(h.y * 9.0);
	float len = 2.0 + floor(h.z * 7.0);
	float x = mod(q.x, 18.0);
	return x >= start && x < start + len;
}

void fragment() {
	vec2 screen = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 world = view_origin + screen * view_scale;
	vec2 pixel = floor(world / texel_size);
	float s = clamp(strength, 0.0, 1.0);
	// Toward the side the blizzard comes from, snow streams already.
	float edge = smoothstep(0.25, 0.5, dot(SCREEN_UV - 0.5, normalize(warning_side) * 1.4));
	float near = clamp(warning, 0.0, 1.0) * edge;
	float gusts = value_noise(pixel * 0.012 - vec2(time * 0.9, time * 0.1));
	float veil = s * (0.34 + 0.26 * gusts) + near * 0.12;
	vec4 color = vec4(VEIL, veil);
	float density = s * 0.55 + near * 0.35;
	if (density > 0.0 && (dash(pixel, density, 160.0, 0.0) || dash(pixel, density * 0.7, 110.0, 31.0))) {
		color = vec4(FLAKE, 0.55 + 0.35 * s);
	}
	COLOR = color;
}
