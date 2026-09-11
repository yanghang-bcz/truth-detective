shader_type spatial;
render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;
float noise(vec2 p) {
	return sin(p.x*0.63+sin(p.y*0.41))*sin(p.y*0.37+p.x*0.21)*0.5+0.5;
}
void fragment() {
	vec2 p=(UV-0.5)*200.0;
	float edge=smoothstep(11.0,19.0,length(p*vec2(0.83,1.0)));
	float drift=noise(p+vec2(TIME*0.05,TIME*0.026));
	ALBEDO=vec3(0.105,0.147,0.163);
	ALPHA=edge*(0.16+drift*0.085);
}
