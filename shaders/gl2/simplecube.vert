#if __VERSION__ > 120
#define attribute in
#define varying out
#endif

uniform mat4 ModelViewProjMatrix;

attribute vec3 VertexPosition;
attribute vec2 VertexTexCoord;

varying vec3 tu0coord;

void main()
{
	gl_Position = ModelViewProjMatrix * vec4(VertexPosition, 1.0);

	vec2 screenpos = (VertexTexCoord - vec2(0.5, 0.5)) * 2.0;
	tu0coord = vec3(screenpos.x, screenpos.y, -0.5);
}
