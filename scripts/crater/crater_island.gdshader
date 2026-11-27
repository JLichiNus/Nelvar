shader_type canvas_item;
render_mode unshaded;

// A floe of magma crust on the volcano's lake (NelvarCraterIsland): dark plates whose
// seams glow and dim slowly, a red-hot edge where the lava laps at it. Deep inside a
// broad floe the crust has cooled more: thinner, dimmer seams. Its south face shows as
// a dark row lit red from below. A floe that sinks warns first (its seams flare, lava
// bubbles along its edge), sinks from the edge inwards with a seam of lava eating in,
// comes up red-hot and cools.
//
// TEXTURE is its mask (R: in from the edge in quarters of an art pixel, G: south face,
// A: floe), one texel per art pixel; the pattern is the floe's own and floats with it.

uniform float time = 0.0;
uniform vec2 seed_offset;
// 0..1: under the lava from the edge in, of sink_px (art pixels).
uniform float sink = 0.0;
uniform float sink_px = 30.0;
// 0..1 in the seconds before it sinks by itself.
uniform float warn = 0.0;
// 1 just come up, 0 cooled.
uniform float hot = 0.0;

#include "res://scripts/fire/fire_common.gdshaderinc"

void fragment() {
	vec4 m = texture(TEXTURE, UV);
	if (m.a < 0.5) {
		discard;
	}
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	vec2 np = px + seed_offset;
	// Art pixels in from the edge, and the same as a share of how deep sinking eats.
	float depth = m.r * 255.0 / 4.0;
	float inside = depth / sink_px;
	float face = floor(m.g * 255.0 + 0.5);
	if (inside <= sink) {
		discard;
	}
	float cooled = smoothstep(8.0, 40.0, depth);
	// Flat dark plates (no dithering: it drifts as one), seams at least a pixel wide.
	vec3 cell = cells(np / 8.0);
	float tone = cell.z + (value_noise(np / 6.0 + cell.z * 13.0) - 0.5) * 0.4;
	vec3 color = tone < 0.3 ? PAL[CRUST] : (tone < 0.72 ? PAL[CRUST + 1] : PAL[CRUST + 2]);
	if (cell.y < 0.16 - cooled * 0.05) {
		color = sin(time * 1.4 + cell.z * 23.0) > 0.4 + cooled * 0.5 ? PAL[LAVA + 2] : PAL[LAVA + 1];
		// Deep in, many seams have gone out: dark cracks between the plates.
		if (hash12(floor(np / 8.0) + floor(cell.z * 7.0)) < cooled * 0.7) {
			color = PAL[CRUST] * 0.55;
		}
	}
	// The lake lights everything round it (fire_glow): the stone is kept darker so the
	// floes stay dark under that light; seams keep their glow.
	if (color.r < 0.4) {
		color *= 0.72;
	}
	// Before it sinks by itself: the seams flare, bubbles along the edge.
	if (warn > 0.0) {
		vec3 c = cells(np / 6.0);
		if (c.y < 0.07 + warn * 0.06 && sin(time * 9.0 + c.z * 40.0) > 0.6 - warn) {
			color = PAL[LAVA + 4];
		}
		if (inside < 0.12 + warn * 0.1 && hash12(px + floor(time * 8.0) * 3.3) < warn * 0.5) {
			color = hash12(px * 1.7) < 0.5 ? PAL[LAVA + 4] : PAL[LAVA + 3];
		}
	}
	// Red-hot from below as it comes up, cooling plate by plate.
	if (hot > 0.0) {
		vec3 c = cells(np / 6.0);
		float glow = hot * (1.2 - c.z * 0.5);
		if (glow * 16.0 > bayer(px) + 0.5) {
			color = ramp(LAVA, 6, 0.15 + glow * 0.5 - c.y * 1.5, px);
		}
	}
	// The edge: red-hot where the lava laps at it; the south face lit from below.
	if (depth < 1.0) {
		color = PAL[LAVA];
	}
	if (sink > 0.0 && inside < sink + 0.06) {
		color = inside < sink + 0.03 ? PAL[LAVA + 4] : PAL[LAVA + 2];
	} else if (face > 0.5) {
		color = face < 1.5 ? PAL[LAVA] : PAL[CRUST];
	}
	COLOR = vec4(color, 1.0);
}
