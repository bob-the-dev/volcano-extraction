shader_type spatial;

render_mode blend_mix, cull_back, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(0.18, 0.66, 0.25, 1.0);
uniform vec4 tint_color : source_color = vec4(0.97, 0.86, 0.38, 1.0);
uniform vec3 focus_world_position = vec3(0.0, 0.0, 0.0);

uniform float intact_radius : hint_range(0.0, 20.0, 0.1) = 1.2;
uniform float dissolve_radius : hint_range(0.1, 30.0, 0.1) = 8.5;
uniform float near_dot_density : hint_range(1.0, 32.0, 0.1) = 10.0;
uniform float far_dot_density : hint_range(1.0, 32.0, 0.1) = 4.0;
uniform float near_fill_ratio : hint_range(0.05, 1.0, 0.01) = 0.96;
uniform float far_fill_ratio : hint_range(0.05, 1.0, 0.01) = 0.42;
uniform float edge_softness : hint_range(0.001, 0.25, 0.001) = 0.04;
uniform float cell_jitter : hint_range(0.0, 1.0, 0.01) = 0.32;
uniform float color_noise_strength : hint_range(0.0, 1.0, 0.01) = 0.24;
uniform float tint_strength : hint_range(0.0, 1.0, 0.01) = 0.7;
uniform float wobble_strength : hint_range(0.0, 0.5, 0.001) = 0.08;
uniform float emission_strength : hint_range(0.0, 4.0, 0.01) = 0.28;

varying vec3 world_position;
varying vec3 world_normal;


float hash12(vec2 value) {
	vec3 hashed = fract(vec3(value.xyx) * 0.1031);
	hashed += dot(hashed, hashed.yzx + 33.33);
	return fract((hashed.x + hashed.y) * hashed.z);
}


vec2 dominant_axis_uv(vec3 value, vec3 normal_value) {
	vec3 abs_normal = abs(normal_value);
	if (abs_normal.z >= abs_normal.x && abs_normal.z >= abs_normal.y) {
		return value.xy;
	}
	if (abs_normal.x >= abs_normal.y) {
		return value.zy;
	}
	return value.xz;
}


void vertex() {
	vec3 base_world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	float focus_distance = distance(base_world_position, focus_world_position);
	float effect_amount = smoothstep(intact_radius, dissolve_radius, focus_distance);
	float wobble_wave = sin((base_world_position.x * 3.1) + (TIME * 1.7));
	float wobble_detail = cos((base_world_position.z * 4.3) - (TIME * 1.25));
	float wobble_offset = wobble_wave * wobble_detail;
	VERTEX += NORMAL * wobble_offset * wobble_strength * effect_amount;

	world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}


void fragment() {
	float focus_distance = distance(world_position, focus_world_position);
	float effect_amount = smoothstep(intact_radius, dissolve_radius, focus_distance);

	vec2 pattern_uv = dominant_axis_uv(world_position, normalize(world_normal));
	float dot_density = mix(near_dot_density, far_dot_density, effect_amount);
	vec2 scaled_uv = pattern_uv * dot_density;
	vec2 cell_index = floor(scaled_uv);
	vec2 cell_uv = fract(scaled_uv) - vec2(0.5, 0.5);

	float cell_noise = hash12(cell_index);
	float jitter_angle = cell_noise * TAU;
	vec2 jitter_offset = vec2(cos(jitter_angle), sin(jitter_angle));
	cell_uv -= jitter_offset * cell_jitter * effect_amount * 0.18;

	float fill_ratio = mix(near_fill_ratio, far_fill_ratio, effect_amount);
	float dot_radius = clamp(fill_ratio * 0.5, 0.04, 0.49);
	float dot_distance = length(cell_uv);
	float dot_mask = 1.0 - smoothstep(dot_radius - edge_softness, dot_radius + edge_softness, dot_distance);
	if (dot_mask <= 0.001) {
		discard;
	}

	float animated_noise = hash12(cell_index + vec2(floor(TIME * 2.0), 19.0));
	float color_noise = ((animated_noise - 0.5) * color_noise_strength) + (effect_amount * tint_strength);
	float tint_mix = clamp(color_noise, 0.0, 1.0);
	vec3 final_color = mix(base_color.rgb, tint_color.rgb, tint_mix);
	final_color *= mix(1.0, 1.14, effect_amount);

	ALBEDO = final_color;
	EMISSION = tint_color.rgb * effect_amount * dot_mask * emission_strength;
	METALLIC = 0.0;
	ROUGHNESS = mix(0.9, 0.5, effect_amount);
}