shader_type spatial;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p),f=fract(p);f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
varying vec3 world_position;
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 float fine=noise(world_position.xz*80.0);
 
 ALBEDO=mix(vec3(0.15,0.19,0.20),vec3(0.20,0.25,0.27),fine);
 ROUGHNESS=1.0;
 SPECULAR=0.0;
 METALLIC=0.0;
}
