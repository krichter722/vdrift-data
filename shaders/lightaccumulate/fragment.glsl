varying vec2 tu0coord;
varying vec3 eyespace_view_direction;

uniform sampler2D tu0_2D;
uniform sampler2D tu1_2D;
uniform sampler2D tu2_2D;
uniform sampler2D tu3_2D;

#ifndef _REFLECTIONDISABLED_
uniform samplerCube tu4_cube; //reflection map
#endif

uniform sampler2D tu5_2D;

// shadowed directional light
uniform vec3 directlight_eyespace_direction;

float unpackFloatFromVec2i(const vec2 value)
{
	const vec2 unpack_constants = vec2(1.0/256.0, 1.0);
	return dot(unpack_constants,value);
}

vec3 sphericalToXYZ(const vec2 spherical)
{
	vec3 xyz;
	float theta = spherical.x*3.14159265358979323846;
	vec2 sincosTheta = vec2(sin(theta),cos(theta));
	vec2 sincosPhi = vec2(sqrt(1.0-spherical.y*spherical.y), spherical.y);
	xyz.x = sincosTheta.y*sincosPhi.x;
	xyz.y = sincosTheta.x*sincosPhi.x;
	xyz.z = spherical.y;
	return xyz;
}

#define GAMMA 2.2
vec3 UnGammaCorrect(vec3 color)
{
	return pow(color, vec3(1.0/GAMMA,1.0/GAMMA,1.0/GAMMA));
}
vec3 GammaCorrect(vec3 color)
{
	return pow(color, vec3(GAMMA,GAMMA,GAMMA));
}
#undef GAMMA

#define PI 3.14159265

float cos_clamped(const vec3 V1, const vec3 V2)
{
	return max(0.0,dot(V1,V2));
}

vec3 CommonBRDF(const vec3 brdf, const vec3 E_l, const float omega_i)
{
	return brdf * E_l * omega_i;
}

vec3 FresnelEquation(const vec3 Rf0, const float omega_i)
{
	return Rf0 + (vec3(1.,1.,1.)-Rf0)*pow(1.0-omega_i,5.0);
}

// equation 7.49, Real-Time Rendering (third edition) by Akenine-Moller, Haines, Hoffman
vec3 RealTimeRenderingBRDF(const vec3 cdiff, const float m, const vec3 Rf0, const float alpha_h, const float omega_h)
{
	return cdiff/PI + ((m+8.0)/(8.0*PI))*FresnelEquation(Rf0,alpha_h)*pow(omega_h,m);
}

void main()
{
	vec2 screen = vec2(SCREENRESX,SCREENRESY);
	vec2 screencoord = gl_FragCoord.xy/screen;
	
	// retrieve g-buffer
	float gbuf_depth = texture2D(tu3_2D, screencoord).r;
	
	// early discard
	if (gbuf_depth == 1) discard;
	
	vec4 gbuf_material_properties = texture2D(tu0_2D, screencoord);
	vec4 gbuf_normal_xy = texture2D(tu1_2D, screencoord);
	vec4 gbuf_diffuse_albedo = texture2D(tu2_2D, screencoord);
	
	// decode g-buffer
	vec3 cdiff = GammaCorrect(gbuf_diffuse_albedo.rgb); //diffuse reflectance
	float notshadow = gbuf_diffuse_albedo.a; //direct light occlusion multiplier
	vec3 Rf0 = GammaCorrect(gbuf_material_properties.rgb); //fresnel reflectance value at zero degrees
	float m = gbuf_material_properties.a*256.0+1.0; //micro-scale roughness
	float mpercent = gbuf_material_properties.a;
	vec2 normal_spherical = vec2(unpackFloatFromVec2i(gbuf_normal_xy.xy),unpackFloatFromVec2i(gbuf_normal_xy.zw))*2.0-vec2(1.0,1.0);
	vec3 normal = sphericalToXYZ(normal_spherical);
	
	// determine view vector
	vec3 V = normalize(-eyespace_view_direction);
	
	// determine half vector
	vec3 H = normalize(V+directlight_eyespace_direction);
	
	float alpha_h = dot(V,H); //cosine of angle between half vector and view direction
	float omega_h = cos_clamped(H,normal); //clamped cosine of angle between half vector and normal
	
	vec4 final = vec4(0.0,0.0,0.0,1.0);
	
	#ifdef _INITIAL_
		// determine reflection vector and lookup into reflection texture
		vec3 R = reflect(-V,normal);
		vec3 reflection = vec3(0,0,0);
		vec3 ambient = vec3(0.5,0.5,0.5);
		float ambient_reflection_lod = 5;
		vec3 refmapdir = R;
		#ifdef _REFLECTIONDYNAMIC_
		refmapdir = vec3(-R.z, R.x, -R.y);
		#endif
		
		#ifndef _REFLECTIONDISABLED_
		reflection = GammaCorrect(textureCubeLod(tu4_cube, refmapdir, mix(ambient_reflection_lod,0.0,mpercent)).rgb);
		//ambient = GammaCorrect(textureCubeLod(tu4_cube, normal, ambient_reflection_lod).rgb);
		#endif
		
		const float reflectionstrength = 0.5;
		
		// add reflection light
		final.rgb += FresnelEquation(vec3(0,0,0),cos_clamped(V,normal))*Rf0*reflection*reflectionstrength;
		
		float ambientstrength = 0.7*(1.0-texture2D(tu5_2D, screencoord).r);
		
		// add ambient light
		final.rgb += ambient*cdiff*ambientstrength;
		
		// generate parameters for directional light
		const float sunstrength = 2.0;
		vec3 E_l = vec3(1,1,0.8)*notshadow*sunstrength; //incoming light intensity/color
		float omega_i = cos_clamped(directlight_eyespace_direction,normal); //clamped cosine of angle between incoming light direction and surface normal
		
		//final.rgb = ambient*ambientstrength;
	#endif
	
	#ifdef _OMNI_
		float eyespace_z = gl_ProjectionMatrix[3].z / (gbuf_depth * -2.0 + 1.0 - gl_ProjectionMatrix[2].z); //http://www.opengl.org/discussion_boards/ubbthreads.php?ubb=showflat&Number=277938
		vec3 gbuf_eyespace_pos = vec3(eyespace_view_direction.xy/eyespace_view_direction.z*eyespace_z,eyespace_z); //http://lumina.sourceforge.net/Tutorials/Deferred_shading/Point_light.html
		vec3 light_center = gl_ModelViewMatrix[3].xyz;
		float attenuation_radius = 1.0;
		float falloff_radius = 1.0;
		float dist = max(0.01,distance(gbuf_eyespace_pos,light_center));
		float attenuation = max(0.0,(-dist/falloff_radius+1.0)*attenuation_radius/dist);
		vec3 E_l = gl_Color.rgb*attenuation;
		vec3 light_direction = -normalize(gbuf_eyespace_pos - light_center);
		float omega_i = cos_clamped(light_direction,normal); //clamped cosine of angle between incoming light direction and surface normal
	#endif
	
	// add source light
	final.rgb += CommonBRDF(RealTimeRenderingBRDF(cdiff, m, Rf0, alpha_h, omega_h),E_l,omega_i);
	
	gl_FragColor = final;
}
