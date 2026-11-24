shader_type canvas_item;
// Red damage vignette, drawn in blocks and a few alpha steps so it matches the
// pixel art. Coordinates are the rect's own (it covers the screen, Y down).
// `direction` (normalized, Y down) limits it to the side facing the hit; a zero
// vector shows the whole edge.

uniform vec4 color : source_color = vec4(0.85, 0.05, 0.08, 0.6);
uniform float strength : hint_range(0.0, 1.0) = 0.0;
uniform vec2 direction = vec2(0.0);
uniform vec2 rect_size = vec2(1280.0, 800.0);
// Red from `inner` (0 = center, 1 = middle of a side) up to full at `outer`.
uniform float inner = 0.62;
uniform float outer = 1.2;
uniform float block = 6.0;
uniform float steps = 6.0;

void fragment() {
	vec2 cell = (floor(UV * rect_size / block) + 0.5) * block;
	vec2 from_center = (cell / rect_size - 0.5) * 2.0;
	// 1 at the middle of each side, about 1.4 in the corners.
	float edge = length(from_center);
	float a = smoothstep(inner, outer, edge);
	if (length(direction) > 0.5) {
		vec2 side = normalize(from_center * rect_size);
		a *= smoothstep(0.1, 0.85, dot(side, direction));
	}
	a = floor(clamp(a * strength, 0.0, 1.0) * steps + 0.5) / steps;
	COLOR = vec4(color.rgb, a * color.a);
}
