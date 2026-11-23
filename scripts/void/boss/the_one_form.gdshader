shader_type canvas_item;
render_mode unshaded;

// CanvasGroup shader of the Only One's body (the_one_body.gd). The group buffer
// holds the assembled body. Phase IV turns it into an almost empty silhouette: its
// edges crawl, the inside is the Void with fragments of the old form showing
// through, a cold violet rim around it all. A hit flashes it pale violet.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
// 0 = the body as painted, 1 = only a silhouette of the Void is left.
uniform float void_amount = 0.0;
// How far the edges crawl, in screen pixels.
uniform float distort = 0.0;
uniform float flash = 0.0;
// A cold rim along the whole silhouette, so the dark body stands out from the floor.
uniform float rim_amount = 0.0;
uniform float time = 0.0;
uniform vec4 rim_color : source_color = vec4(0.72, 0.58, 1.0, 1.0);
uniform vec4 void_color : source_color = vec4(0.02, 0.0, 0.05, 1.0);

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

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

vec4 body_at(vec2 uv) {
	vec4 c = textureLod(screen_texture, uv, 0.0);
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	return c;
}

void fragment() {
	// Crawl on a coarse grid (one body texel is 3 world units), so it stays pixel art.
	vec2 cell = floor(world_position / 3.0);
	float t = floor(time * 12.0);
	vec2 crawl = vec2(value_noise(cell / 3.0 + vec2(t * 0.37, 0.0)),
		value_noise(cell / 3.0 + vec2(0.0, t * 0.41) + 17.0)) - 0.5;
	vec2 uv = SCREEN_UV + crawl * distort * SCREEN_PIXEL_SIZE * 2.0;
	vec4 c = body_at(uv);
	float empty = 0.0;
	if ((void_amount > 0.0 || rim_amount > 0.0) && c.a > 0.0) {
		// Where the silhouette meets empty space.
		vec2 step_uv = SCREEN_PIXEL_SIZE * 3.0;
		empty += step(body_at(uv + vec2(step_uv.x, 0.0)).a, 0.01);
		empty += step(body_at(uv - vec2(step_uv.x, 0.0)).a, 0.01);
		empty += step(body_at(uv + vec2(0.0, step_uv.y)).a, 0.01);
		empty += step(body_at(uv - vec2(0.0, step_uv.y)).a, 0.01);
	}
	if (rim_amount > 0.0 && empty > 0.0) {
		c.rgb = mix(c.rgb, rim_color.rgb, rim_amount);
	}
	if (void_amount > 0.0 && c.a > 0.0) {
		// Fragments of the former body drift inside the silhouette.
		float fragment = step(0.66, value_noise(cell / 4.0 + vec2(time * 0.6, -time * 0.4)));
		vec3 inside = mix(void_color.rgb, c.rgb, fragment);
		c.rgb = mix(c.rgb, inside, void_amount);
		if (empty > 0.0) {
			c.rgb = mix(c.rgb, rim_color.rgb, void_amount);
		}
	}
	c.rgb = mix(c.rgb, vec3(0.86, 0.8, 1.0), flash);
	COLOR *= c;
}
