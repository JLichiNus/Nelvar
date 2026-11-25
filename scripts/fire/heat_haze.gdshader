shader_type canvas_item;
render_mode unshaded;

// Heat haze over the lava, the fissures and the eruptions (NelvarHeatHaze): rows of
// the picture shift sideways by a whole art pixel and back, unevenly, where the air is
// hot. Everything drawn below shimmers — the ground, the sprites, the player.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform sampler2D glow_tex : filter_linear, repeat_disable;
uniform vec2 glow_origin;
uniform vec2 glow_size = vec2(0.0);
uniform float glow_scale = 8.0;
uniform float texel_size = 4.0;
// World point at the screen's top-left corner and world units per screen pixel.
uniform vec2 view_origin;
uniform float view_scale = 1.0;
uniform float time = 0.0;
uniform vec4 flares[8];
uniform int flare_count = 0;
// The volcano: the air shimmers only where the light map's B channel says (over the
// vent, the boiling patches, the smoke banks), not over all the lava it lights.
uniform bool use_haze_mask = false;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 screen = SCREEN_UV / SCREEN_PIXEL_SIZE;
	vec2 world = view_origin + screen * view_scale;
	vec2 pixel = floor(world / texel_size);
	float heat = 0.0;
	if (glow_size.x > 0.0) {
		// The hot air rises: what shimmers is a little north of the heat.
		vec2 uv = (pixel + vec2(0.5, 6.5) - glow_origin) / (glow_size * glow_scale);
		if (uv.x > 0.0 && uv.y > 0.0 && uv.x < 1.0 && uv.y < 1.0) {
			vec3 g = texture(glow_tex, uv).rgb;
			heat = use_haze_mask ? smoothstep(0.1, 0.85, g.b)
				: max(smoothstep(0.55, 1.0, g.r), smoothstep(0.5, 0.9, g.g) * 0.6);
		}
	}
	for (int i = 0; i < 8; i++) {
		if (i >= flare_count) {
			break;
		}
		float d = length(pixel - flares[i].xy) / max(flares[i].z, 1.0);
		heat = max(heat, clamp(flares[i].w, 0.0, 1.0) * (1.0 - clamp(d, 0.0, 1.0)));
	}
	vec2 uv = SCREEN_UV;
	if (heat > 0.0) {
		// Each art-pixel row wobbles on its own, in short gusts.
		float wave = sin(pixel.y * 0.9 + time * 5.0 + hash12(vec2(pixel.y, 1.7)) * 6.2831);
		float gate = hash12(vec2(pixel.y, floor(time * 6.0 + hash12(vec2(pixel.y, 9.1)) * 6.0)));
		if (gate < heat * 0.8 && abs(wave) > 0.5) {
			uv.x += sign(wave) * texel_size / view_scale * SCREEN_PIXEL_SIZE.x;
		}
	}
	COLOR = vec4(textureLod(screen_texture, uv, 0.0).rgb, 1.0);
}
