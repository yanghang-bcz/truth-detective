shader_type spatial;
render_mode unshaded, blend_add, depth_draw_never, cull_back, fog_disabled;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
varying vec3 local_surface;
void vertex() { local_surface=VERTEX; }
void fragment() {
	// Fixed orthographic camera: integrate a soft cone through a proxy box.
	// Opaque scene depth truncates the integration at walls, props and ground.
	vec3 direction=normalize((inverse(MODEL_MATRIX)*vec4(-INV_VIEW_MATRIX[2].xyz,0.0)).xyz);
	float depth=textureLod(depth_texture,SCREEN_UV,0.0).r;
	vec4 scene_position=INV_PROJECTION_MATRIX*vec4(SCREEN_UV*2.0-1.0,depth,1.0);
	scene_position.xyz/=scene_position.w;
	float travel=clamp(VERTEX.z-scene_position.z,0.0,5.6);
	float integrated=0.0;
	for (int i=0;i<40;i++) {
		float t=(float(i)+0.5)*0.14;
		vec3 p=local_surface+direction*t;
		float downward=1.4-p.y;
		float radius=0.12+downward*0.56;
		float radial=length(p.xz)/max(radius,0.1);
		float density=exp(-radial*radial*3.2)*(1.0-smoothstep(0.65,1.0,radial));
		density*=smoothstep(0.0,0.20,downward)*(1.0-smoothstep(2.4,2.8,downward));
		if (t<travel && downward>0.0 && downward<2.8) integrated+=density*0.14;
	}
	ALBEDO=vec3(1.0,0.66,0.29);
	ALPHA=clamp(integrated*0.075,0.0,0.30);
}
