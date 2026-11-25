shader_type canvas_item;
render_mode unshaded;

// The group buffer holds the assembled body. The last phase hollows it into a
// crawling silhouette, with light from the old form and stars caught inside.
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform float void_amount = 0.0;
uniform float distort = 0.0;
uniform float flash = 0.0;
uniform float split = 0.0;
uniform float rim_amount = 0.0;
uniform float time = 0.0;
uniform vec4 violet : source_color = vec4(0.62, 0.4, 1.0, 1.0);
uniform vec4 pale : source_color = vec4(0.9, 0.84, 1.0, 1.0);
uniform vec4 deep : source_color = vec4(0.32, 0.12, 0.7, 1.0);
uniform vec4 void_color : source_color = vec4(0.02, 0.0, 0.05, 1.0);

varying vec2 world_position;
varying vec2 world_origin;
varying vec2 screen_texel;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
	world_origin = MODEL_MATRIX[3].xy;
	screen_texel = 3.0 * vec2(length(CANVAS_MATRIX[0].xy), length(CANVAS_MATRIX[1].xy));
}

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

float body_alpha(vec2 uv) {
	return textureLod(screen_texture, uv, 0.0).a;
}

void fragment() {
	vec2 cell = floor((world_position - world_origin) / 3.0);
	vec2 step_uv = screen_texel * SCREEN_PIXEL_SIZE;
	float tick = floor(time * 14.0);
	vec2 uv = SCREEN_UV;
	float streak = 0.0;
	if (split > 0.0) {
		float row = hash12(vec2(floor(cell.y / 2.0), tick));
		streak = step(1.0 - 0.22 * split, row);
		uv.x += (2.0 * step(0.5, fract(row * 11.0)) - 1.0) * step_uv.x * streak;
	}
	if (distort > 0.0) {
		float jitter = hash12(floor(cell / vec2(2.0, 3.0)) + vec2(tick, 13.0));
		float shift = step(1.0 - 0.24 * distort, jitter) - step(jitter, 0.24 * distort);
		uv.x += shift * step_uv.x;
	}
	vec4 body = textureLod(screen_texture, uv, 0.0);
	vec2 horizontal = vec2(step_uv.x, 0.0);
	float left = body_alpha(uv - horizontal);
	float right = body_alpha(uv + horizontal);
	if (body.a > 0.001) {
		vec3 ink = body.rgb / body.a;
		vec2 vertical = vec2(0.0, step_uv.y);
		float edge = 1.0 - min(min(left, right), min(body_alpha(uv - vertical), body_alpha(uv + vertical)));
		float rim = edge * rim_amount;
		if (void_amount > 0.0) {
			float cloud = hash12(floor(cell / 3.0) + vec2(17.0, floor(time * 1.8)));
			float star = step(0.978, hash12(cell));
			float twinkle = 0.45 + 0.55 * sin(time * 3.7 + cloud * 12.0);
			float bright = smoothstep(0.31, 0.77, max(max(ink.r, ink.g), ink.b));
			vec3 abyss = mix(void_color.rgb, deep.rgb, cloud * 0.2);
			abyss = mix(abyss, pale.rgb, star * (0.5 + 0.5 * twinkle));
			abyss = mix(abyss, ink, max(bright, 0.24 * step(0.72, cloud)));
			ink = mix(ink, abyss, void_amount);
			rim = max(rim, edge * void_amount * (0.3 + 0.33 * cloud));
		}
		ink = mix(ink, violet.rgb, rim * (1.0 - 0.7 * clamp(max(ink.r, ink.b), 0.0, 1.0)));
		body.rgb = mix(ink, pale.rgb, flash * 0.92);
	} else {
		float fringe = max(left, right) * max(streak * split, flash);
		body = vec4(left > right ? deep.rgb : violet.rgb, fringe * 0.76);
	}
	COLOR *= body;
}
