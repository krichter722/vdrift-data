uniform sampler2D tu0_2D; // diffuse texture
uniform sampler2D tu3_2D; // existing depth
uniform vec4 color_tint;

varying vec2 tu0coord;

#ifdef _VCOLOR_
varying vec4 vcolor;
#endif

void main()
{
	vec3 screen = gl_FragCoord.xyz/vec3(SCREENRESX,SCREENRESY,1.0);
	float gbuf_depth = texture2D(tu3_2D, screen.xy).r;
	
	//if (screen.z > gbuf_depth) discard;
	
	vec4 diffuse = texture2D(tu0_2D, tu0coord);
	
#ifdef _VCOLOR_
	diffuse *= vcolor;
#else
	diffuse *= color_tint;
#endif
	
	const float softfactor = 100.0;
	float alpha = mix(0.0, diffuse.a, clamp((gbuf_depth - screen.z)*softfactor,0.0,1.0));
	
	// pre-multiply alpha
	diffuse.rgb *= alpha;
	diffuse.a = 1;
	
	gl_FragColor = diffuse;
	
	//gl_FragColor.a = 1;
	//gl_FragColor.rgb = vec3(1,1,1)*(gbuf_depth);
}
