shader_type canvas_item;
render_mode unshaded;

// Шейдер CanvasGroup из occlusion_outline.gd. В буфере группы лежит силуэт
// персонажа (копии его спрайтов); от него остаются только контур и лёгкая
// заливка, и лишь на тех пикселях, где персонажа закрывает препятствие.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec4 outline_color : source_color = vec4(1.0);
uniform vec4 fill_color : source_color = vec4(1.0, 1.0, 1.0, 0.15);
// Толщина контура в мировых пикселях — не зависит от зума камеры.
uniform float outline_width = 3.0;

// Препятствия перед персонажем: текстура и прямоугольник в мире
// (xy — левый верхний угол, zw — размер). Используются первые occluder_count.
uniform int occluder_count = 0;
uniform sampler2D occluder_texture_0 : repeat_disable, filter_nearest;
uniform sampler2D occluder_texture_1 : repeat_disable, filter_nearest;
uniform sampler2D occluder_texture_2 : repeat_disable, filter_nearest;
uniform sampler2D occluder_texture_3 : repeat_disable, filter_nearest;
uniform sampler2D occluder_texture_4 : repeat_disable, filter_nearest;
uniform sampler2D occluder_texture_5 : repeat_disable, filter_nearest;
uniform vec4 occluder_rect_0;
uniform vec4 occluder_rect_1;
uniform vec4 occluder_rect_2;
uniform vec4 occluder_rect_3;
uniform vec4 occluder_rect_4;
uniform vec4 occluder_rect_5;

varying vec2 world_position;


void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}


float covers(sampler2D tex, vec4 rect, vec2 point) {
	vec2 uv = (point - rect.xy) / rect.zw;
	if (uv.x < 0.0 || uv.y < 0.0 || uv.x >= 1.0 || uv.y >= 1.0) {
		return 0.0;
	}
	// Полупрозрачная тень у основания ствола препятствием не считается.
	return step(0.5, texture(tex, uv).a);
}


float occlusion(vec2 point) {
	float hidden = 0.0;
	if (occluder_count > 0) { hidden = max(hidden, covers(occluder_texture_0, occluder_rect_0, point)); }
	if (occluder_count > 1) { hidden = max(hidden, covers(occluder_texture_1, occluder_rect_1, point)); }
	if (occluder_count > 2) { hidden = max(hidden, covers(occluder_texture_2, occluder_rect_2, point)); }
	if (occluder_count > 3) { hidden = max(hidden, covers(occluder_texture_3, occluder_rect_3, point)); }
	if (occluder_count > 4) { hidden = max(hidden, covers(occluder_texture_4, occluder_rect_4, point)); }
	if (occluder_count > 5) { hidden = max(hidden, covers(occluder_texture_5, occluder_rect_5, point)); }
	return hidden;
}


void fragment() {
	// Производные считаем до discard: в неоднородном потоке они не определены.
	vec2 world_per_pixel = max(fwidth(world_position), vec2(1e-4));
	float hidden = occlusion(world_position);
	if (hidden <= 0.0) {
		discard;
	}
	if (texture(screen_texture, SCREEN_UV).a > 0.5) {
		COLOR = fill_color;
	} else {
		vec2 reach = SCREEN_PIXEL_SIZE * outline_width / world_per_pixel;
		float near = 0.0;
		for (int i = 0; i < 8; i++) {
			float angle = float(i) * PI * 0.25;
			vec2 direction = vec2(cos(angle), sin(angle)) * reach;
			near = max(near, texture(screen_texture, SCREEN_UV + direction).a);
			near = max(near, texture(screen_texture, SCREEN_UV + direction * 0.5).a);
		}
		COLOR = vec4(outline_color.rgb, outline_color.a * step(0.5, near));
	}
	COLOR.a *= hidden;
}
