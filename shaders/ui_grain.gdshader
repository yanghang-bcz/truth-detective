shader_type canvas_item;
render_mode blend_add, unshaded;
// 极轻的胶片颗粒。存在的意义不是"复古"，而是让大片纯色区域（尤其是深蓝底）
// 不再是一块死板的色块，画面有"呼吸"的错觉。

uniform float amount : hint_range(0.0, 0.2) = 0.030;
uniform float speed : hint_range(0.0, 60.0) = 12.0;

float hash12(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33);
	return fract((p3.x + p3.y) * p3.z);
}

void fragment() {
	vec2 p = floor(UV * vec2(1600.0, 1000.0));
	float n = hash12(p + floor(TIME * speed) * 13.7);
	COLOR = vec4(vec3(n * amount), 1.0);
}
