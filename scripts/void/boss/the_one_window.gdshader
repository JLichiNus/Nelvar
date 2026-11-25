shader_type canvas_item;
render_mode unshaded;

// The chest aperture holds a pale core. Its violet shell swells on wind-up
// and when the body flares, changing one texel at a time.
uniform float time = 0.0;
uniform float charge = 0.0;
uniform float visibility = 1.0;
uniform vec2 core_texel = vec2(8.0, 11.0);
uniform vec4 violet : source_color = vec4(0.62, 0.4, 1.0, 1.0);
uniform vec4 pale : source_color = vec4(0.9, 0.84, 1.0, 1.0);
uniform vec4 deep : source_color = vec4(0.32, 0.12, 0.7, 1.0);
uniform vec4 void_color : source_color = vec4(0.02, 0.0, 0.05, 1.0);

void fragment() {
	if (COLOR.a < 0.01 || visibility < 0.01) {
		discard;
	}
	vec2 p = abs(floor(UV / TEXTURE_PIXEL_SIZE) - core_texel);
	float d = p.x + p.y * 0.72;
	float beat = 0.5 + 0.5 * sin(time * (3.8 + charge * 2.5));
	float radius = 0.47 + charge * 0.8 + beat * 0.31;
	float shell = clamp(1.42 + charge * 0.93 - d, 0.0, 1.0);
	float heart = 1.0 - smoothstep(radius, radius + 0.5, d);
	vec3 ink = mix(void_color.rgb, deep.rgb, 0.38 + 0.27 * beat);
	ink = mix(ink, violet.rgb, shell);
	ink = mix(ink, pale.rgb, heart * (0.84 + 0.16 * charge));
	COLOR = vec4(ink, COLOR.a * visibility);
}
