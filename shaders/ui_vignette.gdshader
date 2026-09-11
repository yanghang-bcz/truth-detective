shader_type canvas_item;
render_mode blend_mix, unshaded;
// 暗角。把玩家的注意力收到画面中间，同时让边缘的界面元素自然退后。

uniform float strength : hint_range(0.0, 2.0) = 0.80;
uniform float inner : hint_range(0.0, 1.5) = 0.30;
uniform float outer : hint_range(0.0, 2.0) = 0.98;
uniform vec4 tint : source_color = vec4(0.016, 0.024, 0.032, 1.0);

void fragment() {
	vec2 c = (UV - 0.5) * vec2(1.0, 1.10);
	float d = length(c);
	float v = smoothstep(inner, outer, d) * strength;
	COLOR = vec4(tint.rgb, clamp(v, 0.0, 1.0));
}
