shader_type spatial;

render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, shadows_disabled;

uniform vec4 fog_color : source_color = vec4(0.48, 0.5, 0.53, 0.95);
uniform float inner_radius = 17.0;
uniform float outer_radius = 23.0;
uniform float density = 0.55;
uniform float vertical_fade_start = 6.0;
uniform float vertical_fade_end = 9.0;

varying vec3 local_position;


void vertex() {
	local_position = VERTEX;
}


void fragment() {
	float radial_distance = length(local_position.xz);
	if (radial_distance < inner_radius || radial_distance > outer_radius) {
		discard;
	}

	float radial_alpha = smoothstep(inner_radius, outer_radius, radial_distance);
	float vertical_distance = abs(local_position.y);
	float vertical_alpha = 1.0 - smoothstep(vertical_fade_start, vertical_fade_end, vertical_distance);
	float alpha = radial_alpha * vertical_alpha * density * fog_color.a;
	if (alpha <= 0.001) {
		discard;
	}

	ALBEDO = fog_color.rgb;
	ALPHA = alpha;
}