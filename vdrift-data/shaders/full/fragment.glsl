uniform sampler2D tu0_2D; //diffuse map
uniform sampler2D tu1_2D; //misc map (includes gloss on R channel, metallic on G channel, ...
uniform samplerCube tu3_cube; //ambient light cube map

//width and height of the diffuse texture, in pixels
uniform float diffuse_texture_width;
uniform float diffuse_texture_height;

#ifdef _SHADOWS_
#ifdef _SHADOWSULTRA_
uniform sampler2D tu4_2D; //close shadow map
#else
uniform sampler2DShadow tu4_2D; //close shadow map
#endif
#ifdef _CSM2_
uniform sampler2DShadow tu5_2D; //far shadow map
#endif
#ifdef _CSM3_
uniform sampler2DShadow tu6_2D; //far far shadow map
#endif
#endif

#define _FANCIERSHADOWBLENDING_

#ifndef _REFLECTIONDISABLED_
uniform samplerCube tu2_cube; //reflection map
#endif

uniform sampler2D tu8_2D; //additive map (for brake lights)

#ifdef _EDGECONTRASTENHANCEMENT_
uniform sampler2DShadow tu7_2D; //edge contrast enhancement depth map
#endif

uniform vec3 lightposition;

varying vec2 texcoord_2d;
varying vec3 normal_eye;
varying vec3 viewdir;
#ifdef _SHADOWS_
varying vec4 projshadow_0;
#ifdef _CSM2_
varying vec4 projshadow_1;
#endif
#ifdef _CSM3_
varying vec4 projshadow_2;
#endif
#endif

#if ( defined (_SHADOWS_) && ( defined (_SHADOWSULTRA_) || defined (_SHADOWSVHIGH_) ) ) || defined (_EDGECONTRASTENHANCEMENT_)
vec2 poissonDisk[16];
#endif

#ifdef _SHADOWSULTRA_
#define    BLOCKER_SEARCH_NUM_SAMPLES 16
#define    PCF_NUM_SAMPLES 16
#define    NEAR_PLANE 9.5
#define    LIGHT_WORLD_SIZE .05
#define    LIGHT_FRUSTUM_WIDTH 3.75
// Assuming that LIGHT_FRUSTUM_WIDTH == LIGHT_FRUSTUM_HEIGHT
#define LIGHT_SIZE_UV (LIGHT_WORLD_SIZE / LIGHT_FRUSTUM_WIDTH)

float unpackFloatFromVec4i(const vec4 value)
{
	const vec4 bitSh = vec4(1.0 / (256.0 * 256.0 * 256.0), 1.0 / (256.0 * 256.0), 1.0 / 256.0, 1.0);
	return(dot(value, bitSh));
}

float unpackFloatFromVec3i(const vec3 value)
{
	const vec3 bitSh = vec3(1.0 / (256.0 * 256.0), 1.0 / 256.0, 1.0);
	return(dot(value, bitSh));
}

float unpackFloatFromVec2i(const vec2 value)
{
	const vec2 unpack_constants = vec2(1.0/256.0, 1.0);
	return dot(unpack_constants,value);
}

float shadow_comparison(sampler2D tu, vec2 uv, float comparison)
{
	float lookupvalue = unpackFloatFromVec3i(texture2D(tu, uv).rgb);
	//if (lookupvalue < 0.5+1.5/256.0) lookupvalue -= 1.0/256.0;
	//return clamp((lookupvalue - comparison)*100.0,-0.5,0.5)+0.5;
	return lookupvalue > comparison ? 1.0 : 0.0;
}

float PenumbraSize(float zReceiver, float zBlocker) //Parallel plane estimation
{
	return (zReceiver - zBlocker) / zBlocker;
}

void FindBlocker(in vec2 poissonDisk[16], in sampler2D tu,
		 out float avgBlockerDepth,
		 out float numBlockers,
		 vec2 uv, float zReceiver )
{
	//This uses similar triangles to compute what
	//area of the shadow map we should search
	//float searchWidth = LIGHT_SIZE_UV * (zReceiver - NEAR_PLANE) / zReceiver;
	float searchWidth = 10.0/2048.0;
	//float searchWidth = LIGHT_SIZE_UV;
	float blockerSum = 0;
	numBlockers = 0;
	for( int i = 0; i < BLOCKER_SEARCH_NUM_SAMPLES; ++i )
	{
		//float shadowMapDepth = tDepthMap.SampleLevel(PointSampler,uv + poissonDisk[i] * searchWidth,0);
		float shadowMapDepth = unpackFloatFromVec3i(texture2D(tu, uv + poissonDisk[i] * searchWidth).rgb);
		if ( shadowMapDepth < zReceiver ) {
			blockerSum += shadowMapDepth;
			numBlockers++;
		}
	}
	avgBlockerDepth = blockerSum / numBlockers;
}

float PCF_Filter( in vec2 poissonDisk[16], in sampler2D tu, in vec2 uv, in float zReceiver, in float filterRadiusUV )
{
	float sum = 0.0f;
	for ( int i = 0; i < PCF_NUM_SAMPLES; ++i )
	{
		vec2 offset = poissonDisk[i] * filterRadiusUV;
		sum += shadow_comparison(tu, uv + offset, zReceiver);
	}
	return sum / PCF_NUM_SAMPLES;
	//vec2 offset = vec2(1.0/2048.0,1.0/2048.0);
	//vec2 offset = vec2(0.0,0.0);
	//return unpackFloatFromVec4i(texture2D(tu, uv + offset)) >= zReceiver ? 1.0 : 0.0;
	//return unpackFloatFromVec3i(texture2D(tu, uv + offset).rgb) > zReceiver + 1.0/(256.0*256.0) ? 1.0 : 0.0;
	//return unpackFloatFromVec3i(texture2D(tu, uv + offset).rgb) > zReceiver + 1.0/(256.0*4.0) ? 1.0 : 0.0;
	//return unpackFloatFromVec2i(texture2D(tu, uv + offset).rg) >= zReceiver ? 1.0 : 0.0;
}

float PCSS ( in vec2 poissonDisk[16], in sampler2D tu, vec3 coords )
{
	vec2 uv = coords.xy;
	float zReceiver = coords.z; // Assumed to be eye-space z in this code
	// STEP 1: blocker search
	float avgBlockerDepth = 0;
	float numBlockers = 0;
	FindBlocker( poissonDisk, tu, avgBlockerDepth, numBlockers, uv, zReceiver );
	if( numBlockers < 1 )
		//There are no occluders so early out (this saves filtering)
		return 1.0f;
	// STEP 2: penumbra size
	float penumbraRatio = PenumbraSize(zReceiver, avgBlockerDepth);
	//float filterRadiusUV = penumbraRatio * LIGHT_SIZE_UV * NEAR_PLANE / coords.z;
	float filterRadiusUV = clamp(penumbraRatio*0.05,0,20.0/2048.0);
	//float filterRadiusUV = penumbraRatio*(256.0/2048.0);
	// STEP 3: filtering
	return PCF_Filter( poissonDisk, tu, uv, zReceiver, filterRadiusUV );
}

float shadow_lookup(sampler2D tu, vec3 coords)
#else
float shadow_lookup(sampler2DShadow tu, vec3 coords)
#endif
{
	#ifdef _SHADOWSULTRA_
	float notshadowfinal = PCSS(poissonDisk, tu, coords);
	#else
	#ifdef _SHADOWSVHIGH_
	float notshadowfinal = 0.0;
	float radius = 3.0/2048.0;
	for (int i = 0; i < 16; i++)
		notshadowfinal += float(shadow2D(tu,coords + radius*vec3(poissonDisk[i],0.0)).r);
	notshadowfinal *= 1.0/16.0;
	#else
	//no PCF
	float notshadowfinal = float(shadow2D(tu, coords).r);
	#endif
	#endif
	
	return notshadowfinal;
}

#ifdef _EDGECONTRASTENHANCEMENT_
float GetEdgeContrastEnhancementFactor(in sampler2DShadow tu, in vec3 coords)
{
	float factor = 0.0;
	float radius = 3.0/1024.0;
	for (int i = 0; i < 8; i++)
		factor += float(shadow2D(tu,coords + radius*vec3(poissonDisk[i],0.0)).r);
	factor *= 1.0/8.0;
	return factor;
}
#endif

//post-processing functions
vec3 ContrastSaturationBrightness(vec3 color, float con, float sat, float brt)
{
	// Increase or decrease theese values to adjust r, g and b color channels seperately
	const float AvgLumR = 0.5;
	const float AvgLumG = 0.5;
	const float AvgLumB = 0.5;
	
	const vec3 LumCoeff = vec3(0.2125, 0.7154, 0.0721);
	
	vec3 AvgLumin = vec3(AvgLumR, AvgLumG, AvgLumB);
	vec3 brtColor = color * brt;
	vec3 intensity = vec3(dot(brtColor, LumCoeff));
	vec3 satColor = mix(intensity, brtColor, sat);
	vec3 conColor = mix(AvgLumin, satColor, con);
	return conColor;
}
#define BlendScreenf(base, blend) 		(1.0 - ((1.0 - base) * (1.0 - blend)))
#define BlendSoftLightf(base, blend) 	((blend < 0.5) ? (2.0 * base * blend + base * base * (1.0 - 2.0 * blend)) : (sqrt(base) * (2.0 * blend - 1.0) + 2.0 * base * (1.0 - blend)))
#define BlendOverlayf(base, blend) 	(base < 0.5 ? (2.0 * base * blend) : (1.0 - 2.0 * (1.0 - base) * (1.0 - blend)))
#define Blend(base, blend, funcf) 		vec3(funcf(base.r, blend.r), funcf(base.g, blend.g), funcf(base.b, blend.b))
#define BlendOverlay(base, blend) 		Blend(base, blend, BlendOverlayf)
#define BlendSoftLight(base, blend) 	Blend(base, blend, BlendSoftLightf)
#define BlendScreen(base, blend) 		Blend(base, blend, BlendScreenf)
#define GammaCorrection(color, gamma)								pow(color, 1.0 / gamma)
#define LevelsControlInputRange(color, minInput, maxInput)				min(max(color - vec3(minInput), vec3(0.0)) / (vec3(maxInput) - vec3(minInput)), vec3(1.0))
#define LevelsControlInput(color, minInput, gamma, maxInput)				GammaCorrection(LevelsControlInputRange(color, minInput, maxInput), gamma)

float GetShadows()
{
	#if ( defined (_SHADOWS_) && ( defined (_SHADOWSULTRA_) || defined (_SHADOWSVHIGH_) ) ) || defined (_EDGECONTRASTENHANCEMENT_)
	poissonDisk[0] = vec2( -0.94201624, -0.39906216 );
	poissonDisk[1] = vec2( 0.94558609, -0.76890725 );
	poissonDisk[2] = vec2( -0.094184101, -0.92938870 );
	poissonDisk[3] = vec2( 0.34495938, 0.29387760 );
	poissonDisk[4] = vec2( -0.91588581, 0.45771432 );
	poissonDisk[5] = vec2( -0.81544232, -0.87912464 );
	poissonDisk[6] = vec2( -0.38277543, 0.27676845 );
	poissonDisk[7] = vec2( 0.97484398, 0.75648379 );
	poissonDisk[8] = vec2( 0.44323325, -0.97511554 );
	poissonDisk[9] = vec2( 0.53742981, -0.47373420 );
	poissonDisk[10] = vec2( -0.26496911, -0.41893023 );
	poissonDisk[11] = vec2( 0.79197514, 0.19090188 );
	poissonDisk[12] = vec2( -0.24188840, 0.99706507 );
	poissonDisk[13] = vec2( -0.81409955, 0.91437590 );
	poissonDisk[14] = vec2( 0.19984126, 0.78641367 );
	poissonDisk[15] = vec2( 0.14383161, -0.14100790 );
	#endif
	
	#ifdef _SHADOWS_
	
	#ifdef _CSM3_
	const int numcsm = 3;
	#else
	#ifdef _CSM2_
	const int numcsm = 2;
	#else
	const int numcsm = 1;
	#endif
	#endif
	
	vec3 shadowcoords[numcsm];
	
	shadowcoords[0] = projshadow_0.xyz;
	#ifdef _CSM2_
	shadowcoords[1] = projshadow_1.xyz;
	#endif
	#ifdef _CSM3_
	shadowcoords[2] = projshadow_2.xyz;
	#endif
	
	#ifndef _FANCIERSHADOWBLENDING_
	const float boundmargin = 0.1;
	const float boundmax = 1.0 - boundmargin;
	const float boundmin = 0.0 + boundmargin;
	
	bool effect[numcsm];
	
	for (int i = 0; i < numcsm; i++)
	{
		effect[i] = (shadowcoords[i].x < boundmin || shadowcoords[i].x > boundmax) ||
		(shadowcoords[i].y < boundmin || shadowcoords[i].y > boundmax) ||
		(shadowcoords[i].z < boundmin || shadowcoords[i].z > boundmax);
	}
	#endif //no fancier shadow blending
	
	/*bool effect0 = viewdir.z < -8;
	bool effect1 = viewdir.z < -50;
	bool effect2 = viewdir.z < -100;*/
	
	/*effect0 = true;
	effect1 = false;
	effect2 = false;*/
	
	//shadow lookup that works better with ATI cards:  no early out
	float notshadow[numcsm];
	notshadow[0] = shadow_lookup(tu4_2D, shadowcoords[0]);
	#ifdef _CSM2_
	notshadow[1] = shadow2D(tu5_2D, shadowcoords[1]).r;
	#endif
	#ifdef _CSM3_
	notshadow[2] = shadow2D(tu6_2D, shadowcoords[2]).r;
	#endif
	
	//simple shadow mixing, no shadow fade-in
	#ifndef _FANCIERSHADOWBLENDING_
	float notshadowfinal = notshadow[0];
	#ifdef _CSM3_
	notshadowfinal = mix(notshadowfinal,mix(notshadow[1],notshadow[2],float(effect[1])),float(effect[0]));
	notshadowfinal = max(notshadowfinal,float(effect[2]));
	#else //CSM2
	notshadowfinal = mix(notshadowfinal,notshadow[1],float(effect[0]));
	notshadowfinal = max(notshadowfinal,float(effect[1]));
	#endif
	#endif //no fancier shadow blending
	
	//fancy shadow mixing, gives shadow fade-in
	#ifdef _FANCIERSHADOWBLENDING_
	const float bound = 1.0;
	const float fade = 10.0;
	float effect[numcsm];
	
	for (int i = 0; i < numcsm; ++i)
	//for (int i = 3; i < 4; ++i)
	{
		shadowcoords[i] = clamp(shadowcoords[i], 0.0, bound);
		float xf1 = 1.0-min(1.0,shadowcoords[i].x*fade);
		float xf2 = max(0.0,shadowcoords[i].x*fade-(fade-1.0));
		float yf1 = 1.0-min(1.0,shadowcoords[i].y*fade);
		float yf2 = max(0.0,shadowcoords[i].y*fade-(fade-1.0));
		float zf1 = 1.0-min(1.0,shadowcoords[i].z*fade);
		float zf2 = max(0.0,shadowcoords[i].z*fade-(fade-1.0));
		effect[i] = max(xf1,max(xf2,max(yf1,max(yf2,max(zf1,zf2)))));
		//notshadow[i] = max(notshadow[i],effect[i]);
	}
	
	float notshadowfinal = notshadow[0];
	#ifdef _CSM3_
	notshadowfinal = mix(notshadowfinal,mix(notshadow[1],notshadow[2],effect[1]),effect[0]);
	notshadowfinal = max(notshadowfinal,effect[2]);
	#else
	#ifdef _CSM2_
	notshadowfinal = mix(notshadowfinal,notshadow[1],effect[0]);
	notshadowfinal = max(notshadowfinal,effect[1]);
	#else
	notshadowfinal = max(notshadowfinal,effect[0]);
	#endif
	#endif
	#endif //fancier shadow blending
	
	#else //no SHADOWS
	float notshadowfinal = 1.0;
	#endif

	return notshadowfinal;
}

float EffectStrength(float val, float coeff)
{
	return val*coeff+1.0-coeff;
}

vec3 EffectStrength(vec3 val, float coeff)
{
	return val*coeff+vec3(1.0-coeff);
}

float ColorCorrectfloat(in float x)
{
	return pow(x,5.0)*5.23878+pow(x,4.0)*-14.45564+pow(x,3.0)*12.6883+pow(x,2.0)*-3.78462+x*1.31897-.01041;
}

vec3 ColorCorrect(in vec3 val)
{
	return vec3(ColorCorrectfloat(val.r),ColorCorrectfloat(val.g),ColorCorrectfloat(val.b));
}

void main()
{
	float notshadowfinal = GetShadows();
	
	vec3 normnormal = normalize(normal_eye);
	vec3 normviewdir = normalize(viewdir);
	vec3 normlightposition = normalize(lightposition);
	
	vec4 tu0_2D_val = texture2D(tu0_2D, texcoord_2d);
	vec4 tu1_2D_val = texture2D(tu1_2D, texcoord_2d);
	vec4 tu8_2D_val = texture2D(tu8_2D, texcoord_2d);
	
	vec3 texcolor = tu0_2D_val.rgb;
	float gloss = tu1_2D_val.r;
	float metallic = tu1_2D_val.g;
	
	float difdot = dot(normnormal,normlightposition);
	
	float diffusefactor = (1.0-pow(1.0-max(difdot,0.0),2.0))*notshadowfinal;
	//diffusefactor = clamp(diffusefactor, 0.0, 1.0);
	//float diffusefactor = max(difdot,0.0)*notshadowfinal;
	
	float specval = max(dot(reflect(normviewdir,normnormal),normlightposition),0.0);
	//vec3 halfvec = normalize(normviewdir + normlightposition);
	//float specval = max(0.0,dot(normnormal,halfvec));
	
	//float env_factor = min(pow(1.0-max(0.0,dot(-normviewdir,normnormal)),3.0),0.6)*0.75+0.2;
	const float rf0 = 0.05;
	float env_factor = rf0+(1.0-rf0)*pow(1.0-dot(-normviewdir,normnormal),3.0); //Schlick approximation of fresnel reflectance with modified power; see Real Time Rendering third edition p. 233
	env_factor *= 2.0;
	//env_factor *= 0.8; //don't let it get TOO shiny
	env_factor = min(env_factor, 1.0);
	
	//float spec = ((max((pow(specval,512.0)-0.5)*2.0,0.0))*metallic+pow(specval,12.0)*(0.4+(1.0-metallic)*0.8))*gloss;
	//float spec = ((max((pow(specval,512.0)-0.5)*2.0,0.0))*metallic+pow(specval,8.0)*(0.4+(1.0-metallic)*0.8))*gloss;
	//float spec = max((pow(specval,512.0)-0.5)*2.0,0.0)*metallic+mix(pow(specval,4.0)*1.2*gloss,pow(specval,8.0)*gloss*0.5,metallic);
	//vec3 spec = metallic*vec3(2.)*max((pow(specval,512.0)-0.5)*2.0,0.0)+gloss*pow(specval,4.0)*1.2*gloss*mix(vec3(1.),max(vec3(0.),(texcolor-vec3(0.2))*2.0),metallic);//mix(pow(specval,4.0)*1.2*gloss,pow(specval,8.0)*gloss*0.5,metallic);
	vec3 spec = metallic*vec3(2.)*max((pow(specval,512.0)-0.5)*2.0,0.0)+gloss*pow(specval,4.0)*1.2*gloss*(1.0-metallic*0.75);
	
	#ifndef _REFLECTIONDISABLED_
	vec3 refmapdir = reflect(normviewdir,normnormal);
	refmapdir = mat3(gl_TextureMatrix[2]) * refmapdir;
	vec3 specular_environment = textureCube(tu2_cube, refmapdir).rgb;
	#else
	vec3 specular_environment = vec3(0,0,0);
	#endif
	
	vec3 ambientmapdir = mat3(gl_TextureMatrix[2]) * normnormal;
	vec3 ambient_light = textureCube(tu3_cube, ambientmapdir).rgb;
	
	//float inv_environment = 1.0 - (env_factor*metallic);
	//float invgloss = (1.0-gloss);
	
	/*vec3 ambient = texcolor*ambient_light;//*(1.0+min(difdot,0.0));
	vec3 ambientfinal = ambient*0.5;//mix(ambient*0.5,ambient*0.2,metallic);
	//vec3 specularfinal = specular_environment*(env_factor*(metallic*0.5+0.5)+spec*notshadowfinal);
	//vec3 specularfinal = specular_environment*(env_factor*metallic+spec*notshadowfinal);
	//vec3 specularfinal = texcolor*metallic*pow(specval,4.0) + vec3(1.0)*(spec*notshadowfinal) + specular_environment*(env_factor*metallic);
	vec3 specularfinal = spec*notshadowfinal + specular_environment*(env_factor*metallic);
	vec3 additivefinal = tu7_2D_val.rgb;
	
	vec3 diffusefinal = texcolor * diffuse;
	
	//vec3 finalcolor = (ambient*0.5 + diffuse*0.8*max(0.7,invgloss))*(inv_environment*0.5+0.5) + vec3(spec)*notshadowfinal + specular_environment*max(0.5,notshadowfinal) + tu3_2D_val.rgb;
	//vec3 finalcolor = (ambient*0.5 + diffuse*0.8*max(0.7,invgloss))*(1.0-metallic*env_factor) + vec3(spec)*notshadowfinal + specular_environment*max(0.5,notshadowfinal)*env_factor*1.2 + tu3_2D_val.rgb;
	//vec3 finalcolor = (ambientfinal + diffusefinal)*(1.0-metallic*(env_factor*0.65+0.35)) + specularfinal + additivefinal;
	//vec3 finalcolor = ambientfinal + diffuse + specularfinal + additivefinal;
	vec3 finalcolor = ambientfinal*(1.0-metallic)+((diffuse+(1.0-env_factor)*metallic)*texcolor*(1.0-metallic*0.5) + specularfinal)*(1.+metallic*.2) + additivefinal;*/
	
	float viewdotnorm = max(0.0,dot(-normviewdir,normnormal));
	
	vec3 ambient = ambient_light;//*vec3(0.7882353, 0.8784314, 0.8823529);
	//vec3 diffuse = diffusefactor*vec3(0.9686275, 0.9568627, 0.8901961);
	float metallicdiffuse = 0.05;
	//vec3 diffuse = mix(diffusefactor,EffectStrength(diffusefactor,metallicdiffuse),metallic)*vec3(1,1,1);
	float minmetallicdiffuse = 0.7;
	vec3 diffuse = mix(diffusefactor,max(diffusefactor,minmetallicdiffuse),metallic)*vec3(1,1,1);
	vec3 additive = tu8_2D_val.rgb;
	float viewdotnormpow = pow(viewdotnorm,3.0);
	vec3 texcolormod = mix(texcolor,ContrastSaturationBrightness(texcolor,EffectStrength(viewdotnormpow,0.0),EffectStrength(viewdotnormpow,0.5),1.0),metallic);
	//vec3 texcolormod = texcolor;
	//vec3 diffusetexcolor = mix(texcolormod*vec3(0.7882353, 0.8784314, 0.8823529),texcolormod,diffusefactor);
	vec3 diffusetexcolor = texcolormod;
	
	const float saturationeffectmin = 0.3;
	const float saturationeffectmax = 1.5;
	float saturationeffect = mix(1.0,mix(saturationeffectmin,saturationeffectmax,viewdotnorm),metallic);
	const float brightnesseffectmin = 1.0;
	const float brightnesseffectmax = 1.0;
	float brightnesseffect = mix(1.0,mix(brightnesseffectmin,brightnesseffectmax,viewdotnorm),metallic);
	
	const float myrf0 = 0.15;
	float myenv_factor = myrf0+(1.0-myrf0)*pow(1.0-viewdotnorm,3.0); //Schlick approximation of fresnel reflectance with modified power; see Real Time Rendering third edition p. 233
	vec3 specular = mix(0.0,myenv_factor,metallic)*specular_environment*1.0;
	
	const float lightenfactor = 0.6;
	const float lightenpower = 3.0;
	float diffuseadd = mix(0.0,min(pow(viewdotnorm,lightenpower),lightenfactor),metallic);
	
	//vec3 finalcolor = ContrastSaturationBrightness((diffuse + ambient*0.65)*diffusetexcolor,1.0,saturationeffect,brightnesseffect) + specular*0.0 + additive;
	//vec3 finalcolor = BlendOverlay(((diffuse + ambient*0.65)*diffusetexcolor), mix(vec3(0.5),(specular*2.0),metallic)) + additive;
	//vec3 finalcolor = pow((diffuse + ambient*0.65)*diffusetexcolor + specular*1.0,vec3(mix(1.0,1.4,metallic))) + spec*diffusefactor + additive;
	vec3 finalcolor = pow(min(EffectStrength(diffuse,0.5),ambient)*diffusetexcolor + specular*1.0,vec3(mix(1.0,1.4,metallic))) + spec*diffusefactor + additive;
	//float diffusefade = clamp(-viewdir.z*0.01,0.0,1.0)*0.5;
	//vec3 finalcolor = pow(mix(diffuse+ambient*0.5,ambient*1.5,diffusefade)*diffusetexcolor + specular*1.0,vec3(mix(1.0,1.4,metallic))) + spec*diffusefactor + additive;
	//vec3 finalcolor = spec;
	//vec3 finalcolor = vec3(env_factor);
	//vec3 finalcolor = mix(texcolor,max(vec3(0.),(texcolor-vec3(0.2))*2.0),diffusefactor) + additive;
	//vec3 finalcolor = ContrastSaturationBrightness(texcolor, 1.0, diffusefactor*0.5+0.75, 1.0)*(diffuse+ambient*0.9);
	//vec3 finalcolor = ambient*vec3(0.7882353, 0.8784314, 0.8823529);
	
	//do post-processing
	/*const float onethird = 1./3.;
	finalcolor = clamp(finalcolor,0.0,3.0);
	float avg = dot(finalcolor,vec3(onethird));
	//finalcolor *= onethird;
	//finalcolor *= 1.-pow(1.-avg,2.0);
	finalcolor = finalcolor / (avg+2.);
	finalcolor *= 2.5;*/
	//finalcolor /= 3.0;
	//finalcolor = clamp(finalcolor,0.0,1.0);
	//finalcolor = BlendScreen(finalcolor, finalcolor);
	///finalcolor = BlendScreen(finalcolor, finalcolor);
	//finalcolor = mix(BlendOverlay(finalcolor, finalcolor),finalcolor, 0.6);
	//finalcolor = BlendOverlay(finalcolor, finalcolor);
	//finalcolor = ContrastSaturationBrightness(finalcolor, 1.0, 0.5, 1.0);
	//finalcolor = BlendSoftLight(finalcolor, finalcolor);
	//finalcolor = LevelsControlInputRange(finalcolor, 0.07843137, 0.9215686);
	//finalcolor = ContrastSaturationBrightness(finalcolor, 1.5, 0.5, 1.0);
	//finalcolor = texcolor*mix(diffuse,ambient,0.0);
	//finalcolor = mix(diffuse,ambient,0.7);
	//finalcolor = min(EffectStrength(diffuse,0.3),ambient);
	//finalcolor = texcolor*min(EffectStrength(diffuse,0.3),ambient);
	/*finalcolor = clamp(finalcolor,0.0,1.0);
	finalcolor = mix(finalcolor,3.0*finalcolor*finalcolor-2.0*finalcolor*finalcolor*finalcolor,1.0);
	finalcolor = ContrastSaturationBrightness(finalcolor, 1.0, 0.7, 1.0);*/
	finalcolor = ColorCorrect(finalcolor);
	finalcolor = clamp(finalcolor,0.0,1.0);
	//finalcolor = ((finalcolor-0.5)*1.2)+0.5;
	
	//finalcolor *= smoothstep(0.0,1.0,dot(finalcolor,vec3(onethird)))/avg;
	
#ifdef _EDGECONTRASTENHANCEMENT_
	vec3 shadowcoords = vec3(gl_FragCoord.x/SCREENRESX, gl_FragCoord.y/SCREENRESY, gl_FragCoord.z-0.001);
	float edgefactor = GetEdgeContrastEnhancementFactor(tu7_2D, shadowcoords);
	finalcolor *= edgefactor*0.5+0.5;
#endif
	
	gl_FragColor.rgb = finalcolor;
	//gl_FragColor.rgb = vec3(edgefactor);
	//gl_FragColor.rgb = vec3(diffusefade);
	//gl_FragColor.rgb = ambientfinal+diffuse*(1.0-metallic*(env_factor*0.65+0.35)); 
	//gl_FragColor.rgb = specularfinal;
	//gl_FragColor.rgb = vec3(env_factor);
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
	
	//vec2 debugcoords = vec2(gl_FragCoord.x/1024.0,gl_FragCoord.y/768.0);
	//gl_FragColor.rgb = texture2D(tu4_2D, debugcoords).rgb;
	//gl_FragColor.rgb = vec3(unpackFloatFromVec3i(texture2D(tu4_2D, debugcoords).rgb));
	//gl_FragColor.rgb = vec3(unpackFloatFromVec4i(texture2D(tu4_2D, debugcoords)));
	//gl_FragColor.rgb = vec3(unpackFloatFromVec2i(texture2D(tu4_2D, debugcoords).rg));
	
	//float alpha = (tu0_2D_val.a*gl_Color.a-0.5)*20.0+0.5;
	
#ifdef _ALPHATEST_
	//float width = clamp((dFdx(texcoord_2d.x)+dFdy(texcoord_2d.x)) * diffuse_texture_width * 0.5,0.0,0.5);
	//float height = clamp((dFdy(texcoord_2d.y)+dFdy(texcoord_2d.y)) * diffuse_texture_height * 0.5,0.0,0.5);
	float width = clamp(dFdx(texcoord_2d.x) * diffuse_texture_width * 0.5,0.0,0.5);
	//float alphasize = max(width,height);
	float alpha = smoothstep(0.5-width, 0.5+width, tu0_2D_val.a);
	//float alpha = smoothstep(0.5-alphasize, 0.5+alphasize, tu0_2D_val.a);
#else
	float alpha = tu0_2D_val.a;
#endif
	
	//gl_FragColor.rgb = vec3(diffuse_texture_width/1024.0);
	
	gl_FragColor.a = alpha*gl_Color.a;
	//gl_FragColor.a = tu0_2D_val.a;
}
