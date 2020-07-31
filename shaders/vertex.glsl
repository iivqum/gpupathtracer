#version 430
layout(location=0) in vec3 atrb_pos; 
layout(location=1) in vec2 atrb_tex_coord; 

out vec2 vs_texel_coord;

void main()
{
	gl_Position.xyz=atrb_pos.xyz;
	vs_texel_coord=atrb_tex_coord;
}