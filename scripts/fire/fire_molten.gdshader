shader_type canvas_item;

// Glowing pixels of the fire forge's sprites (NelvarFireArt keys them by alpha):
//   FLOW  — lava running down a volcano or a lavafall, in bright and dark streaks that
//           fall, darker along its edges;
//   HOT   — the hottest spots (crater pools, seams, flower hearts): they churn and flicker;
//   EMBER — coals in bark, stone and twigs: they breathe slowly, each at its own pace.
// Every other pixel is drawn as it is.

const int FLOW_KEY = 250;
const int HOT_KEY = 251;
const int EMBER_KEY = 252;
// Art pixels per second the streaks fall.
const float SPEED = 5.0;
const vec3 LAVA[5] = vec3[5](vec3(150.0, 40.0, 26.0) / 255.0, vec3(212.0, 76.0, 34.0) / 255.0,
	vec3(246.0, 130.0, 52.0) / 255.0, vec3(255.0, 196.0, 96.0) / 255.0, vec3(255.0, 236.0, 160.0) / 255.0);
const vec3 COAL = vec3(110.0, 30.0, 24.0) / 255.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

int key_of(vec4 texel) {
	return int(round(texel.a * 255.0));
}

// The node's modulate (art painted late fades in): COLOR in vertex(); the pixels written
// here take it on, the rest have it already.
varying vec4 tint;

void vertex() {
	tint = COLOR;
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	int key = key_of(texel);
	vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE);
	if (key == FLOW_KEY) {
		float streak = fract((pixel.y - TIME * SPEED) / 7.0 + hash12(vec2(pixel.x, 4.7)) * 0.5);
		vec3 color = streak < 0.16 ? LAVA[3] : (streak < 0.55 ? LAVA[2] : LAVA[1]);
		bool left = key_of(texture(TEXTURE, UV - vec2(TEXTURE_PIXEL_SIZE.x, 0.0))) != FLOW_KEY;
		bool right = key_of(texture(TEXTURE, UV + vec2(TEXTURE_PIXEL_SIZE.x, 0.0))) != FLOW_KEY;
		if (left || right) {
			color = streak < 0.16 ? LAVA[2] : LAVA[0];
		}
		COLOR = vec4(color, 1.0) * tint;
	} else if (key == HOT_KEY) {
		float churn = hash12(pixel + floor(TIME * 3.0 + hash12(pixel) * 3.0) * 5.3);
		COLOR = vec4(churn < 0.2 ? LAVA[4] : (churn < 0.75 ? LAVA[3] : LAVA[2]), 1.0) * tint;
	} else if (key == EMBER_KEY) {
		float breath = 0.5 + 0.5 * sin(TIME * (1.2 + hash12(pixel * 1.7) * 1.6) + hash12(pixel) * 6.28);
		vec3 color = breath > 0.82 ? LAVA[3] : (breath > 0.35 ? LAVA[2] : (breath > 0.12 ? LAVA[1] : COAL));
		COLOR = vec4(color, 1.0) * tint;
	}
}
