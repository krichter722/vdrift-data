#ifdef _SHADOWS_
varying vec4 projshadow_0;
#ifdef _CSM2_
varying vec4 projshadow_1;
#endif
#ifdef _CSM3_
varying vec4 projshadow_2;
#endif
#endif

varying vec2 texcoord_2d;
varying vec3 normal_eye;
varying vec3 viewdir;

void main()
{
	//transform the vertex
	gl_Position = ftransform();
	//gl_Position = gl_ProjectionMatrix * gl_ModelViewMatrix * gl_Vertex;
	//gl_Position = gl_ProjectionMatrix * gl_TextureMatrixInverse[3] * gl_TextureMatrix[3] * gl_ModelViewMatrix * gl_Vertex;
	
	#ifdef _SHADOWS_
	//projshadow_0 = gl_TextureMatrix[4] * (gl_TextureMatrix[2] * (gl_ModelViewMatrix * gl_Vertex));
	//projshadow_1 = gl_TextureMatrix[5] * (gl_TextureMatrix[2] * (gl_ModelViewMatrix * gl_Vertex));
	projshadow_0 = gl_TextureMatrix[4] * gl_TextureMatrixInverse[3] * gl_ModelViewMatrix * gl_Vertex;
	#ifdef _CSM2_
	projshadow_1 = gl_TextureMatrix[5] * gl_TextureMatrixInverse[3] * gl_ModelViewMatrix * gl_Vertex;
	#endif
	#ifdef _CSM3_
	projshadow_2 = gl_TextureMatrix[6] * gl_TextureMatrixInverse[3] * gl_ModelViewMatrix * gl_Vertex;
	#endif
	//projshadow_0 = gl_TextureMatrix[4] * gl_Vertex;
	//projshadow_1 = gl_TextureMatrix[5] * gl_Vertex;
	#endif
	
	//set the color
	gl_FrontColor = gl_Color;
	
	//set the texture coordinates
	texcoord_2d = vec2(gl_MultiTexCoord0);
	
	//compute the eyespace normal
	normal_eye = gl_NormalMatrix * gl_Normal;
	
	//compute the eyespace position
	vec4 ecposition = gl_ModelViewMatrix * gl_Vertex;
	
	//compute the eyespace view direction
	viewdir = vec3(ecposition)/ecposition.w;
}
