shader_type canvas_item;

// Waterfalls on the peaks round the earth valley (NelvarMountainPainter._waterfall).
// The painter keys their pixels by alpha: water streams down in light and dark
// streaks, darker along its edges; foam on the ledges and where it lands flickers;
// spray above the landing comes and goes. Every other pixel is drawn as it is.

const int WATER_KEY = 250;
const int FOAM_KEY = 251;
const int MIST_KEY = 252;
// Art pixels per second the streaks fall.
const float SPEED = 10.0;
// The valley's water, dark to light, and its glint (earth_ground.gdshader, WATER).
const vec3 WATER[4] = vec3[4](vec3(52.0, 104.0, 140.0) / 255.0, vec3(70.0, 132.0, 166.0) / 255.0,
	vec3(104.0, 168.0, 196.0) / 255.0, vec3(160.0, 210.0, 226.0) / 255.0);
const vec3 GLINT = vec3(200.0, 232.0, 240.0) / 255.0;
const vec3 FOAM = vec3(236.0, 246.0, 248.0) / 255.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

int key_of(vec4 texel) {
	return int(round(texel.a * 255.0));
}

void fragment() {
	vec4 texel = texture(TEXTURE, UV);
	int key = key_of(texel);
	vec2 pixel = floor(UV / TEXTURE_PIXEL_SIZE);
	if (key == WATER_KEY) {
		// Each column falls with its own streaks; the edges are darker.
		float streak = fract((pixel.y - TIME * SPEED) / 9.0 + hash12(vec2(pixel.x, 4.7)));
		vec3 color = streak < 0.14 ? GLINT : (streak < 0.5 ? WATER[3] : WATER[2]);
		bool left = key_of(texture(TEXTURE, UV - vec2(TEXTURE_PIXEL_SIZE.x, 0.0))) != WATER_KEY;
		bool right = key_of(texture(TEXTURE, UV + vec2(TEXTURE_PIXEL_SIZE.x, 0.0))) != WATER_KEY;
		if (left) {
			color = streak < 0.14 ? WATER[2] : WATER[1];
		} else if (right && streak >= 0.14) {
			color = WATER[2];
		}
		COLOR = vec4(color, 1.0);
	} else if (key == FOAM_KEY) {
		float flicker = hash12(pixel + floor(TIME * 7.0) * 3.1);
		COLOR = vec4(flicker < 0.25 ? WATER[3] : FOAM, 1.0);
	} else if (key == MIST_KEY) {
		float flicker = hash12(pixel + floor(TIME * 5.0) * 7.3);
		COLOR = vec4(FOAM, flicker < 0.5 ? 0.7 : 0.0);
	}
}
