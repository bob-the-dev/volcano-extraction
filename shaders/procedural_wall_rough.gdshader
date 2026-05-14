shader_type spatial;
render_mode depth_draw_opaque, cull_back;

uniform vec4 albedo_color : source_color = vec4(0.46421015, 0.18448496, 0.0, 1.0);
uniform vec4 emission_color : source_color = vec4(0.676924, 0.0, 0.0835629, 1.0);
uniform float emission_energy = 0.27;
uniform float roughness_value : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float metallic_value : hint_range(0.0, 1.0, 0.01) = 0.0;
uniform float specular_value : hint_range(0.0, 1.0, 0.01) = 0.0;

uniform float bulge_strength : hint_range(0.0, 0.15, 0.001) = 0.035;
uniform float bulge_scale : hint_range(0.25, 12.0, 0.01) = 3.4;
uniform float bulge_detail_scale : hint_range(0.5, 32.0, 0.01) = 11.0;
uniform float bulge_detail_strength : hint_range(0.0, 1.0, 0.01) = 0.35;
uniform float vertical_noise_scale : hint_range(0.1, 4.0, 0.01) = 0.7;
uniform float bulge_base_fade_start : hint_range(0.0, 0.5, 0.01) = 0.04;
uniform float bulge_base_fade_end : hint_range(0.0, 0.75, 0.01) = 0.18;

varying float wall_noise_value;

float hash13(vec3 p) {
	return fract(sin(dot(p, vec3(127.1, 311.7, 191.999))) * 43758.5453123);
}

float value_noise_3d(vec3 sample_position) {
	vec3 cell = floor(sample_position);
	vec3 local = fract(sample_position);
	vec3 smooth_local = local * local * (3.0 - 2.0 * local);

	float c000 = hash13(cell + vec3(0.0, 0.0, 0.0));
	float c100 = hash13(cell + vec3(1.0, 0.0, 0.0));
	float c010 = hash13(cell + vec3(0.0, 1.0, 0.0));
	float c110 = hash13(cell + vec3(1.0, 1.0, 0.0));
	float c001 = hash13(cell + vec3(0.0, 0.0, 1.0));
	float c101 = hash13(cell + vec3(1.0, 0.0, 1.0));
	float c011 = hash13(cell + vec3(0.0, 1.0, 1.0));
	float c111 = hash13(cell + vec3(1.0, 1.0, 1.0));

	float x00 = mix(c000, c100, smooth_local.x);
	float x10 = mix(c010, c110, smooth_local.x);
	float x01 = mix(c001, c101, smooth_local.x);
	float x11 = mix(c011, c111, smooth_local.x);
	float y0 = mix(x00, x10, smooth_local.y);
	float y1 = mix(x01, x11, smooth_local.y);
	return mix(y0, y1, smooth_local.z);
}

float fbm(vec3 sample_position) {
	float value = 0.0;
	float amplitude = 0.5;
	float frequency = 1.0;

	for (int octave = 0; octave < 4; octave++) {
		value += value_noise_3d(sample_position * frequency) * amplitude;
		frequency *= 2.0;
		amplitude *= 0.5;
	}

	return value;
}

void vertex() {
	vec3 world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	vec3 coarse_sample = vec3(world_position.x, world_position.y * vertical_noise_scale, world_position.z) * bulge_scale;
	vec3 detail_sample = vec3(world_position.x, world_position.y * vertical_noise_scale, world_position.z) * bulge_detail_scale;
	float coarse_noise = fbm(coarse_sample);
	float detail_noise = fbm(detail_sample);
	float centered_noise = ((coarse_noise - 0.5) * 2.0) + ((detail_noise - 0.5) * 2.0) * bulge_detail_strength;
	float vertical_mask = smoothstep(bulge_base_fade_start, bulge_base_fade_end, VERTEX.y);

	wall_noise_value = centered_noise;
	VERTEX += normalize(NORMAL) * centered_noise * bulge_strength * vertical_mask;
}

void fragment() {
	float surface_variation = 1.0 + wall_noise_value * 0.08;
	ALBEDO = albedo_color.rgb * surface_variation;
	EMISSION = emission_color.rgb * emission_energy * surface_variation;
	ROUGHNESS = roughness_value;
	METALLIC = metallic_value;
	SPECULAR = specular_value;
}