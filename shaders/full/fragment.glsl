#version 120

uniform sampler2D tu0_2D; //diffuse map
uniform sampler2D tu1_2D; //misc map (includes gloss on R channel, ...
#ifdef _SHADOWS_
uniform sampler2DShadow tu4_2D; //close shadow map
uniform sampler2DShadow tu5_2D; //far shadow map
#endif
#ifndef _REFLECTIONDISABLED_
uniform samplerCube tu2_cube; //reflection map
#endif
uniform sampler2D tu3_2D; //additive map (for brake lights)

uniform vec3 lightposition;

varying vec2 texcoord_2d;
varying vec3 normal_eye;
varying vec3 viewdir;
#ifdef _SHADOWS_
varying vec4 projshadow_0;
varying vec4 projshadow_1;
#endif

void main()
{
	#ifdef _SHADOWS_
	vec3 shadowcoords0 = projshadow_0.xyz;
	vec3 shadowcoords1 = projshadow_1.xyz;
	
	float bound = 1.0;
	float fade = 10000.0;
	
	bool effect0 = (shadowcoords0.x < 0.0 || shadowcoords0.x > 1.0) ||
		(shadowcoords0.y < 0.0 || shadowcoords0.y > 1.0) ||
		(shadowcoords0.z < 0.0 || shadowcoords0.z > 1.0);
	
	bool effect1 = (shadowcoords1.x < 0.0 || shadowcoords1.x > 1.0) ||
		(shadowcoords1.y < 0.0 || shadowcoords1.y > 1.0) ||
		(shadowcoords1.z < 0.0 || shadowcoords1.z > 1.0);
	
	float notshadowfinal = 1.0;
	if (!effect0)
	{
		//no PCF
		notshadowfinal = shadow2D(tu4_2D, shadowcoords0).r;
		
		//2x2 PCF
		/*notshadowfinal = 0.0;
		float radius = 0.000977;
		for (int v=-1; v<=1; v+=2)
			for (int u=-1; u<=1; u+=2)
			{
				notshadowfinal += shadow2D(tu4_2D,
					shadowcoords[0] + radius*vec3(u, v, 0.0)).r;
			}
		notshadowfinal *= 0.25;*/
		
		//3x3 PCF
		/*notshadowfinal = 0.0;
		float radius = 0.000977;
		for (int v=-1; v<=1; v++)
			for (int u=-1; u<=1; u++)
			{
				notshadowfinal += shadow2D(tu4_2D,
					shadowcoords[0] + radius*vec3(u, v, 0.0)).r;
			}
		notshadowfinal *= 0.1111;*/
	}
	else if (!effect1)
	{
		notshadowfinal = shadow2D(tu5_2D, shadowcoords1).r;
	}
	#else
	float notshadowfinal = 1.0;
	#endif
	
	vec3 normnormal = normalize(normal_eye);
	vec3 normviewdir = normalize(viewdir);
	vec3 normlightposition = normalize(lightposition);
	
	vec4 tu0_2D_val = texture2D(tu0_2D, texcoord_2d);
	vec4 tu1_2D_val = texture2D(tu1_2D, texcoord_2d);
	vec4 tu3_2D_val = texture2D(tu3_2D, texcoord_2d);
	
	vec3 texcolor = tu0_2D_val.rgb;
	float gloss = tu1_2D_val.r;
	float metallic = tu1_2D_val.g;
	
	float difdot = dot(normnormal,normlightposition);
	
	vec3 diffuse = texcolor*max(difdot,0.0)*notshadowfinal;
	
	vec3 ambient = texcolor;//*(1.0+min(difdot,0.0));
	
	float specval = max(dot(reflect(normviewdir,normnormal),normlightposition),0.0);
	//vec3 halfvec = normalize(normviewdir + normlightposition);
	//float specval = max(0.0,dot(normnormal,halfvec));
	
	float env_factor = min(pow(1.0-max(0.0,dot(-normviewdir,normnormal)),3.0),0.6)*0.75+0.2;
	
	float spec = ((max((pow(specval,512.0)-0.5)*2.0,0.0))*metallic+pow(specval,12.0)*(0.4+(1.0-metallic)*0.8))*gloss;
	
	#ifndef _REFLECTIONDISABLED_
	vec3 refmapdir = reflect(normviewdir,normnormal);
	refmapdir = mat3(gl_TextureMatrix[2]) * refmapdir;
	vec3 specular_environment = textureCube(tu2_cube, refmapdir).rgb*metallic*env_factor;
	#else
	vec3 specular_environment = vec3(0,0,0);
	#endif
	float inv_environment = 1.0 - (env_factor*metallic);
	
	float invgloss = (1.0-gloss);
	
	vec3 finalcolor = (ambient*0.5 + diffuse*0.8*max(0.7,invgloss))*(inv_environment*0.5+0.5) + vec3(spec)*notshadowfinal + specular_environment*max(0.5,notshadowfinal) + tu3_2D_val.rgb;
	
	//do post-processing
	finalcolor = clamp(finalcolor,0.0,1.0);
	finalcolor = ((finalcolor-0.5)*1.2)+0.5;
	
	gl_FragColor.rgb = finalcolor;
	/*float r = 0;
	if (!effect0)
	  r = 1;
	float g = 0;
	if (!effect1)
	  g = 1;
	gl_FragColor.rgb = vec3(r,g,0);*/
	//gl_FragColor.rgb = vec3(pow(specval,1.0));
	//gl_FragColor.rgb = textureCube(tu2_cube, refmapdir).rgb;
	//gl_FragColor.rgb = normviewdir;
	//gl_FragColor.rgb = normnormal;
	//gl_FragColor.rgb = vec3(max(dot(normnormal,normalize(vec3(gl_LightSource[0].position))),0.0));
	//gl_FragColor.rgb = normlightposition;
	//gl_FragColor.rgb = vec3(max(dot(normnormal,normlightposition),0.0));
	//gl_FragColor.rgb = tu0_2D_val.rgb;
	//gl_FragColor = vec4(1.0, 0.0, 0.0, 1.0);
	
	gl_FragColor.a = tu0_2D_val.a*gl_Color.a;
}
