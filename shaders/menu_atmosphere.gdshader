shader_type canvas_item;
uniform bool paused = false;
float noise(vec2 p) { return fract(sin(dot(p, vec2(127.1,311.7)))*43758.5453); }
void fragment() {
 vec2 uv=UV;
 float left_shade=1.0-smoothstep(0.15,0.8,uv.x);
 float edge=pow(abs(uv.y-0.5)*2.0,3.0);
 float ripple=sin(uv.y*24.0+sin(uv.x*6.0+TIME*0.13)*1.4-TIME*0.24);
 float grain=(noise(floor(uv*vec2(1920.0,1080.0))+floor(TIME*12.0))-0.5)*0.018;
 vec3 ink=vec3(0.012,0.025,0.027)+ripple*0.003+grain;
 float alpha=paused ? 0.67 : clamp(0.18+left_shade*0.78+edge*0.24,0.0,0.97);
 COLOR=vec4(ink,alpha);
}
