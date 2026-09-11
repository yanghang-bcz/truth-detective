shader_type spatial;
render_mode blend_add, depth_draw_never, cull_disabled, shadows_disabled;
void vertex() {
	MODELVIEW_MATRIX=VIEW_MATRIX*mat4(INV_VIEW_MATRIX[0],INV_VIEW_MATRIX[1],INV_VIEW_MATRIX[2],MODEL_MATRIX[3]);
	MODELVIEW_MATRIX=MODELVIEW_MATRIX*mat4(vec4(length(MODEL_MATRIX[0].xyz),0,0,0),vec4(0,length(MODEL_MATRIX[1].xyz),0,0),vec4(0,0,length(MODEL_MATRIX[2].xyz),0),vec4(0,0,0,1));
}
void fragment() {
	float r=length((UV-0.5)*2.0);
	float feather=exp(-r*r*5.5)*(1.0-smoothstep(0.6,1.0,r));
	ALBEDO=vec3(0.9,0.78,0.53);
	EMISSION=vec3(0.45,0.33,0.16);
	ROUGHNESS=1.0;
	ALPHA=feather*COLOR.a*0.72;
}
