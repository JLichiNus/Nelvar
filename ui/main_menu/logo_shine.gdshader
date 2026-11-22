shader_type canvas_item;
// Stone logo: every few seconds a pixel-crisp glint runs across the letters.

uniform float period = 6.0;
uniform float speed = 90.0; // texels per second
uniform float strength = 0.4;

void fragment() {
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	float pos = mod(TIME, period) * speed - 30.0;
	float d = px.x + px.y * 0.8 - pos;
	float band = 1.0 - step(2.0, abs(d));
	// Only the light stone catches the glint, not the outline or shadow.
	float lum = dot(COLOR.rgb, vec3(0.299, 0.587, 0.114));
	float stone = step(0.45, lum) * step(0.99, COLOR.a);
	COLOR.rgb += band * stone * strength;
}
