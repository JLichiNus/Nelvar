shader_type canvas_item;
// Wind through pixel text: during a gust a narrow band of one or two pixel rows
// slides one pixel downwind and runs down the letters, like a ripple. Only a
// couple of rows move at a time and the wind calms between gusts, so the text
// stays readable.
// Glyphs need a transparent column on each side (tools/gen_ui.py adds it).

uniform float art_pixel = 3.0;   // size of one font pixel in canvas units
uniform float speed = 9.0;
uniform float band_width = 0.8;  // 0..1, higher = thinner band
uniform float gust_period = 3.5; // seconds between gusts

varying vec2 local_pos;
varying vec4 tint;

void vertex() {
	local_pos = VERTEX;
	tint = COLOR;
}

void fragment() {
	float row = floor(local_pos.y / art_pixel);
	float column = floor(local_pos.x / art_pixel);
	float gust = step(0.5, sin(TIME * TAU / gust_period));
	float wave = sin(TIME * speed - row * 0.55 + column * 0.04);
	float shift = step(band_width, wave) * gust;
	COLOR = texture(TEXTURE, UV - vec2(shift * TEXTURE_PIXEL_SIZE.x, 0.0)) * tint;
}
