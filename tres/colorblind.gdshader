// colorblind.gdshader: daltonize filter for ScreenFilter (Scripts/screen_filter.gd).
// mode 1 = protanopia, 2 = deuteranopia, 3 = tritanopia. The frame is converted to LMS cone space,
// the deficiency is simulated, and the colour difference it loses is shifted into channels the
// viewer can still tell apart (Fidaner et al. daltonization).
shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform int mode = 0;

void fragment() {
	vec3 c = texture(screen_texture, SCREEN_UV).rgb;
	// RGB -> LMS (columns are the R, G, B contributions)
	mat3 rgb2lms = mat3(vec3(17.8824, 3.45565, 0.0299566), vec3(43.5161, 27.1554, 0.184309), vec3(4.11935, 3.86714, 1.46709));
	mat3 lms2rgb = mat3(vec3(0.0809444479, -0.0102485335, -0.000365296938), vec3(-0.130504409, 0.0540193266, -0.00412161469), vec3(0.116721066, -0.113614708, 0.693511405));
	vec3 lms = rgb2lms * c;
	vec3 sim = lms;
	if (mode == 1) {
		sim.x = 2.02344 * lms.y - 2.52581 * lms.z;
	} else if (mode == 2) {
		sim.y = 0.494207 * lms.x + 1.24827 * lms.z;
	} else if (mode == 3) {
		sim.z = -0.395913 * lms.x + 0.801109 * lms.y;
	}
	vec3 seen = lms2rgb * sim;
	vec3 err = c - seen;
	vec3 shift = vec3(0.0, 0.7 * err.r + err.g, 0.7 * err.r + err.b);
	COLOR = vec4(clamp(c + shift, 0.0, 1.0), 1.0);
}
