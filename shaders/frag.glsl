#version 430

out vec4 fs_color;
in vec2 vs_texel_coord;

uniform sampler2D t0;

void main()
{
	fs_color=sqrt(texture(t0,vs_texel_coord));
	//fs_color=texture(t0,vs_texel_coord);
}