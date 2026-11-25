shader_type canvas_item;
render_mode unshaded;

// A splash of lava over the volcano's shore (NelvarLavaSplashes), in art pixels round
// the spot where it comes over: first the lava there bulges and bubbles; then a tongue
// of fresh lava lies on the rock, churning; it sets into a dark crust whose seams glow
// and dim; the crust fades away. Drawn over the floor (or a floe), discarded elsewhere.

uniform float time = 0.0;
uniform float age = 0.0;
// Inland, away from the lava; the tongue's reach and width, art pixels; the decal's side.
uniform vec2 direction = vec2(0.0, 1.0);
uniform float reach_px = 20.0;
uniform float width_px = 30.0;
uniform float size_px = 41.0;
uniform vec2 seed_offset;

#include "res://scripts/fire/fire_common.gdshaderinc"

const float WARN_TIME = 1.3;
const float FRESH_TIME = 3.0;
const float COOL_TIME = 8.0;
const float FADE_TIME = 20.0;

void fragment() {
	vec2 cell = floor(UV * size_px);
	vec2 p = cell - floor(size_px * 0.5) + 0.5;
	vec2 np = cell + seed_offset;
	float u = dot(p, direction);
	float v = dot(p, vec2(-direction.y, direction.x));
	// The tongue: half an ellipse inland from the shore, with a ragged front.
	float rag = (value_noise(np * 0.35) - 0.5) * 0.35 + (value_noise(vec2(v * 0.5, 3.0)) - 0.5) * 0.25;
	float along = max(u, 0.0) / reach_px;
	float across = v / (width_px * 0.5);
	float shape = along * along + across * across + rag;
	if (age < WARN_TIME) {
		// The lava at the shore swells and bubbles; nothing is on the rock yet.
		float swell = age / WARN_TIME;
		float bulge = length(vec2(min(u, 0.0) / (width_px * 0.35), across));
		if (u > 1.0 || bulge > 0.4 + swell * 0.6) {
			discard;
		}
		float churn = hash12(cell + floor(time * (5.0 + swell * 8.0)) * 3.7);
		if (churn > 0.25 + swell * 0.55) {
			discard;
		}
		COLOR = vec4(churn < 0.12 + swell * 0.2 ? PAL[LAVA + 5] : PAL[LAVA + 4], 1.0);
	} else {
		if (shape > 1.0 || u < -2.0) {
			discard;
		}
		float t = age - WARN_TIME;
		vec3 color;
		if (t < FRESH_TIME) {
			// Fresh lava, churning, its front darker as it slows.
			vec3 floe = cells((np + direction * t * 3.0) / 4.0);
			float level = 0.75 - shape * 0.35 - t / FRESH_TIME * 0.2 + (value_noise(np * 0.3 + t) - 0.5) * 0.3;
			color = ramp(LAVA, 6, level, cell);
			if (floe.y < 0.06) {
				color = PAL[LAVA + 5];
			}
			if (shape > 0.82) {
				color = PAL[LAVA + 1];
			}
		} else {
			// A crust with glowing seams that dim as it cools, then fades away.
			float cool = clamp((t - FRESH_TIME) / COOL_TIME, 0.0, 1.0);
			vec3 c = cells(np / 3.0);
			color = ramp(CRUST, 3, 0.2 + c.z * 0.6, cell);
			if (c.y < 0.1 * (1.0 - cool) + 0.02) {
				color = cool < 0.4 ? PAL[LAVA + 2] : (cool < 0.8 ? PAL[LAVA + 1] : PAL[LAVA]);
			}
			if (shape > 0.86) {
				color = PAL[CRUST];
			}
			float gone = clamp((t - FRESH_TIME - COOL_TIME) / FADE_TIME, 0.0, 1.0);
			if (gone * 16.0 > bayer(cell) + 0.5 - shape * 4.0) {
				discard;
			}
		}
		COLOR = vec4(color, 1.0);
	}
}
