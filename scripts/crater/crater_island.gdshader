shader_type canvas_item;
render_mode unshaded;

// A floating island of the volcano (NelvarCraterIsland): the forge's black plates with
// glowing seams (fire_common's plates()), on a raft a thinner crust of small plates. Its
// south face shows as a dark row lit red from below. It warns before it sinks (its seams
// flare, lava bubbles along its edge), sinks from the edge inwards with a seam of lava
// eating in, comes up red-hot and cools; under weight it cracks.
//
// TEXTURE is its mask (R: in from the edge, G: south face, A: island), one texel per art
// pixel; the pattern is the island's own and floats with it.

uniform float time = 0.0;
uniform vec2 seed_offset;
// 0..1: under the lava from the edge in.
uniform float sink = 0.0;
// 0..1 in the seconds before it sinks by itself.
uniform float warn = 0.0;
// 1 just come up, 0 cooled.
uniform float hot = 0.0;
// Weight on it, 0..1.
uniform float crack = 0.0;
uniform float raft = 0.0;

#include "res://scripts/fire/fire_common.gdshaderinc"

void fragment() {
	vec4 m = texture(TEXTURE, UV);
	if (m.a < 0.5) {
		discard;
	}
	vec2 px = floor(UV / TEXTURE_PIXEL_SIZE);
	vec2 np = px + seed_offset;
	float inside = m.r;
	float face = floor(m.g * 255.0 + 0.5);
	if (inside <= sink) {
		discard;
	}
	vec3 color;
	if (raft > 0.5) {
		// A raft: a crust of small floes with red joints.
		vec3 c = cells(np / 3.5);
		color = c.y < 0.08 ? PAL[LAVA + 1] : ramp(CRUST, 3, 0.25 + c.z * 0.7 + (value_noise(np * 0.4) - 0.5) * 0.2, px);
		if (c.y < 0.05 && sin(time * 2.1 + c.z * 30.0) > 0.4) {
			color = PAL[LAVA + 2];
		}
	} else {
		// Bigger plates than the forge's: an island is a raft of a few of them.
		color = plates(px, np * 0.75, -10.0);
	}
	// The lake lights everything round it (fire_glow): the stone is kept darker so the
	// islands stay black under that light; seams keep their glow.
	if (color.r < 0.4) {
		color *= 0.72;
	}
	// Weight opens wide cracks across it, glowing deeper as it settles.
	if (crack > 0.45) {
		vec3 big = cells(np / 13.0 + 31.0);
		float open = (crack - 0.45) * 0.14;
		if (big.y < open) {
			color = crack > 0.8 ? PAL[LAVA + 3] : PAL[LAVA + 1];
		}
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
	// The outline: a near-black edge against the lava, and the south face lit from below.
	if (inside < 0.03 + sink) {
		color = PAL[FLOW_EDGE];
	} else if (inside < 0.06 + sink) {
		color = PAL[CRUST];
	}
	if (sink > 0.0 && inside < sink + 0.06) {
		color = inside < sink + 0.03 ? PAL[LAVA + 4] : PAL[LAVA + 2];
	} else if (face > 0.5) {
		color = face < 1.5 ? PAL[LAVA] : PAL[CRUST];
	}
	COLOR = vec4(color, 1.0);
}
