shader_type spatial;
render_mode cull_disabled, depth_draw_opaque;

group_uniforms Waves;
uniform float wave_frequency = 3.275;
uniform float wave_amplitude = 0.05;
uniform float wave_speed = 0.4;
group_uniforms OrbShape;

uniform float droop_amount : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float droop_bulge : hint_range(0.0, 1.0, 0.01) = 0.12;
uniform float droop_curve : hint_range(0.5, 4.0, 0.05) = 1.8;

group_uniforms Noise;
uniform sampler3D noise_texture : source_color;

group_uniforms Caustics;
uniform vec4 caustic_color : source_color = vec4(0.4397409, 0.10399803, 0.0, 1.0);
uniform float caustic_scale = 100.0;
uniform float caustic_speed = 0.025;
uniform float caustic_intensity : hint_range(0.0, 4.0) = 1.978;
uniform float caustic_sharpness : hint_range(0.0, 1.0) = 0.913;
uniform float caustic_falloff : hint_range(0.0, 0.2) = 0.097;

group_uniforms Color;
uniform vec4 lava_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform vec4 deep_lava_color : source_color = vec4(1.8247963, 0.69283086, 0.0, 1.0);
uniform float pixelization_amount : hint_range(0.0, 1.0) = 0.0;

group_uniforms Foam;
uniform vec3 foam_color : source_color = vec3(3.2944162, 1.1031802, 0.44331938);
uniform float foam_scale = 40.0;
uniform float foam_speed = 0.03;
uniform float edge_foam_amount : hint_range(0.0, 1.0, 0.01) = 0.45;
uniform float edge_foam_fresnel_power : hint_range(0.1, 8.0, 0.05) = 2.5;
uniform float foam_noise_influence : hint_range(0.0, 2.0, 0.01) = 0.03;

group_uniforms Surface;
uniform float emission_strength : hint_range(0.0, 8.0, 0.05) = 1.35;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.08;
uniform float metallic_value : hint_range(0.0, 1.0, 0.01) = 0.02;
uniform float specular_value : hint_range(0.0, 1.0, 0.01) = 0.5;
group_uniforms;


void vertex() {
	float droop_mask = pow(clamp(1.0 - NORMAL.y, 0.0, 1.0), droop_curve);
	VERTEX.y -= droop_amount * droop_mask;
	VERTEX.xz *= 1.0 + (droop_bulge * droop_mask);

	VERTEX.y += sin(VERTEX.x * wave_frequency + TIME * wave_speed) * wave_amplitude;
	VERTEX.y += cos(VERTEX.z * wave_frequency * 0.5 + TIME * wave_speed * 0.8) * wave_amplitude;
}


void fragment() {
	vec2 pixelated_uv = UV;
	if (pixelization_amount > 0.001) {
		float pixel_size = pixelization_amount * 0.05;
		pixelated_uv = floor(UV / pixel_size) * pixel_size;
	}

	vec3 view_direction = normalize(VIEW);
	float fresnel = pow(1.0 - clamp(dot(normalize(NORMAL), view_direction), 0.0, 1.0), edge_foam_fresnel_power);
	float vertical_blend = clamp(1.0 - ((VERTEX.y + 0.5) * 0.9), 0.0, 1.0);
	float color_blend = clamp(max(vertical_blend, fresnel * 0.35), 0.0, 1.0);
	vec3 final_color = mix(lava_color.rgb, deep_lava_color.rgb, color_blend);

	vec3 uvw_1 = vec3(pixelated_uv * caustic_scale, TIME * caustic_speed);
	vec3 uvw_2 = vec3(pixelated_uv * caustic_scale * 0.8, (TIME + 5.0) * caustic_speed * -0.7);
	float noise_1 = texture(noise_texture, uvw_1).r;
	float noise_2 = texture(noise_texture, uvw_2).r;
	float caustics_raw = 1.0 - abs(noise_1 - noise_2);
	float caustics = smoothstep(caustic_sharpness - caustic_falloff, caustic_sharpness + caustic_falloff, caustics_raw);
	final_color += caustics * caustic_color.rgb * caustic_intensity;

	vec3 foam_uvw = vec3(pixelated_uv * foam_scale, TIME * foam_speed);
	float foam_noise = texture(noise_texture, foam_uvw).r;
	float foam_mask = clamp(fresnel + (foam_noise * foam_noise_influence), 0.0, 1.0);
	foam_mask = smoothstep(1.0 - edge_foam_amount, 1.0, foam_mask);

	vec3 textured_foam = foam_color * (0.7 + 0.3 * foam_noise);
	final_color = mix(final_color, textured_foam, foam_mask);

	ALBEDO = final_color;
	EMISSION = final_color * emission_strength;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
}