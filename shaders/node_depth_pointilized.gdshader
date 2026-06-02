shader_type spatial;

render_mode blend_mix, cull_back, depth_draw_opaque;

uniform vec4 base_color : source_color = vec4(0.18, 0.66, 0.25, 1.0);
uniform vec4 tint_color : source_color = vec4(0.97, 0.86, 0.38, 1.0);
uniform sampler2D albedo_texture : source_color;
uniform bool use_albedo_texture = false;

uniform float effect_start_depth : hint_range(0.0, 40.0, 0.1) = 3.0;
uniform float effect_end_depth : hint_range(0.1, 60.0, 0.1) = 10.0;
uniform float flatten_strength : hint_range(0.0, 1.0, 0.01) = 1.0;
uniform float near_dot_density : hint_range(1.0, 48.0, 0.1) = 16.0;
uniform float far_dot_density : hint_range(1.0, 48.0, 0.1) = 7.0;
uniform float near_fill_ratio : hint_range(0.05, 1.0, 0.01) = 1.0;
uniform float far_fill_ratio : hint_range(0.05, 1.0, 0.01) = 0.38;
uniform int circles_per_cell = 3;
uniform float edge_softness : hint_range(0.001, 0.25, 0.001) = 0.04;
uniform float horizontal_scatter : hint_range(0.0, 1.0, 0.01) = 0.28;
uniform float vertical_scatter : hint_range(0.0, 0.5, 0.01) = 0.08;
uniform float color_noise_strength : hint_range(0.0, 0.5, 0.01) = 0.05;
uniform float tint_strength : hint_range(0.0, 1.0, 0.01) = 0.24;
uniform float emission_strength : hint_range(0.0, 4.0, 0.01) = 0.15;
uniform float debug_effect_override : hint_range(-1.0, 1.0, 0.01) = -1.0;
uniform int debug_view_mode = 0;
uniform bool debug_disable_discard = false;

varying vec2 flattened_view_offset;
varying vec2 base_uv;
varying float node_effect_amount;


float hash12(vec2 value) {
	vec3 hashed = fract(vec3(value.xyx) * 0.1031);
	hashed += dot(hashed, hashed.yzx + 33.33);
	return fract((hashed.x + hashed.y) * hashed.z);
}


void vertex() {
	vec4 view_center = MODELVIEW_MATRIX * vec4(0.0, 0.0, 0.0, 1.0);
	vec4 view_vertex = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	float node_depth = max(-view_center.z, 0.0);
	float effect_amount = smoothstep(effect_start_depth, effect_end_depth, node_depth);
	float flatten_amount = effect_amount * flatten_strength;

	view_vertex.z = mix(view_vertex.z, view_center.z, flatten_amount);
	flattened_view_offset = view_vertex.xy - view_center.xy;
	base_uv = UV;
	node_effect_amount = effect_amount;
	POSITION = PROJECTION_MATRIX * view_vertex;
}


void fragment() {
	float effect_amount = node_effect_amount;
	if (debug_effect_override >= 0.0) {
		effect_amount = clamp(debug_effect_override, 0.0, 1.0);
	}
	float abstract_amount = smoothstep(0.12, 0.82, effect_amount);
	vec3 source_rgb = base_color.rgb;
	if (use_albedo_texture) {
		source_rgb = texture(albedo_texture, base_uv).rgb;
	}

	float dot_density = mix(near_dot_density, far_dot_density, effect_amount);
	vec2 scaled_uv = flattened_view_offset * dot_density;
	vec2 cell_index = floor(scaled_uv);
	vec2 cell_uv = fract(scaled_uv) - vec2(0.5, 0.5);

	float fill_ratio = mix(near_fill_ratio, far_fill_ratio, effect_amount);
	float dot_radius = clamp(fill_ratio * 0.5, 0.04, 0.49);
	int active_circle_count = circles_per_cell;
	if (active_circle_count < 1) {
		active_circle_count = 1;
	} else if (active_circle_count > 4) {
		active_circle_count = 4;
	}
	float dot_mask = 0.0;
	for (int circle_index = 0; circle_index < 4; circle_index++) {
		if (circle_index >= active_circle_count) {
			continue;
		}

		float index_value = float(circle_index);
		vec2 circle_seed = cell_index + vec2((index_value * 17.0) + 3.0, (index_value * 29.0) + 11.0);
		float horizontal_offset = ((hash12(circle_seed) * 2.0) - 1.0) * horizontal_scatter * effect_amount;
		float vertical_offset = ((hash12(circle_seed + vec2(13.0, 19.0)) * 2.0) - 1.0) * vertical_scatter * effect_amount;
		float anchor_scale = 1.0;
		if (circle_index == 0) {
			anchor_scale = 0.35;
		}

		vec2 circle_uv = cell_uv - (vec2(horizontal_offset, vertical_offset) * anchor_scale);
		float radius_variation = mix(0.82, 1.0, hash12(circle_seed + vec2(5.0, 7.0)));
		float circle_radius = dot_radius * radius_variation;
		float circle_distance = length(circle_uv);
		float circle_mask = 1.0 - smoothstep(circle_radius - edge_softness, circle_radius + edge_softness, circle_distance);
		dot_mask = max(dot_mask, circle_mask);
	}

	float visibility_mask = mix(1.0, dot_mask, abstract_amount);
	if (visibility_mask <= 0.001 && !debug_disable_discard) {
		discard;
	}

	float static_noise = (hash12(cell_index + vec2(7.0, 17.0)) - 0.5) * color_noise_strength * effect_amount;
	float tint_mix = clamp((effect_amount * tint_strength) + static_noise, 0.0, 1.0);
	vec3 abstract_color = mix(source_rgb, tint_color.rgb, tint_mix);
	abstract_color *= mix(1.0, 1.1, effect_amount);
	vec3 final_color = mix(source_rgb, abstract_color, abstract_amount);
	float grid_debug = max(step(0.46, abs(cell_uv.x)), step(0.46, abs(cell_uv.y)));

	if (debug_view_mode == 1) {
		final_color = vec3(effect_amount);
	} else if (debug_view_mode == 2) {
		final_color = vec3(dot_mask);
	} else if (debug_view_mode == 3) {
		final_color = source_rgb;
	} else if (debug_view_mode == 4) {
		final_color = mix(vec3(dot_mask), vec3(1.0, 0.2, 0.2), grid_debug);
	}

	ALBEDO = final_color;
	EMISSION = vec3(0.0);
	if (debug_view_mode == 0) {
		EMISSION = tint_color.rgb * dot_mask * abstract_amount * emission_strength;
	}
	METALLIC = 0.0;
	ROUGHNESS = mix(0.92, 0.58, effect_amount);
}