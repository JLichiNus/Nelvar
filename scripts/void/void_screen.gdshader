shader_type canvas_item;
render_mode unshaded;

// Screen effects of the Void fight (void_screen.gd), drawn over the world only
// while something is happening: a shockwave ring that bends the picture, the
// picture tearing into shifted slices, colour fringes, a flash.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec2 shock_center = vec2(0.5);
// Ring radius in screen heights; strength 0 = no shockwave.
uniform float shock_radius = 0.0;
uniform float shock_strength = 0.0;
uniform float glitch = 0.0;
uniform float time = 0.0;
uniform vec4 flash_color : source_color = vec4(1.0);
uniform float flash_amount = 0.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 uv = SCREEN_UV;
	float aspect = SCREEN_PIXEL_SIZE.y / SCREEN_PIXEL_SIZE.x;
	float ring = 0.0;
	if (shock_strength > 0.0) {
		vec2 d = (uv - shock_center) * vec2(aspect, 1.0);
		float dist = length(d);
		ring = max(0.0, 1.0 - abs(dist - shock_radius) / 0.05) * shock_strength;
		if (dist > 0.0001) {
			uv -= d / dist * ring * 0.022 / vec2(aspect, 1.0);
		}
	}
	if (glitch > 0.0) {
		// Torn slices, shifted sideways; they change a dozen times a second.
		float tick = floor(time * 14.0);
		float slice = floor(uv.y * 36.0);
		if (hash12(vec2(slice, tick)) < glitch * 0.45) {
			uv.x += (hash12(vec2(slice + 7.0, tick)) - 0.5) * 0.07 * glitch;
		}
	}
	float fringe = glitch * 0.006 + ring * 0.008;
	vec3 color;
	color.r = textureLod(screen_texture, uv + vec2(fringe, 0.0), 0.0).r;
	color.g = textureLod(screen_texture, uv, 0.0).g;
	color.b = textureLod(screen_texture, uv - vec2(fringe, 0.0), 0.0).b;
	// The ring itself glows faintly violet.
	color += vec3(0.35, 0.2, 0.6) * ring * 0.35;
	color = mix(color, flash_color.rgb, flash_amount);
	COLOR = vec4(color, 1.0);
}
