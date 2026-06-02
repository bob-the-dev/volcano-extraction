shader_type spatial;

render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

uniform sampler2D heightmap : filter_linear, repeat_disable;
uniform sampler2D wall_heightmap : filter_linear, repeat_disable;
uniform sampler2D exploration_mask : filter_linear, repeat_disable;
uniform float amplitude = 1.0;
uniform float wall_amplitude = 0.0;
uniform vec2 heightmap_texel_size = vec2(0.01, 0.01);
uniform vec4 low_color : source_color = vec4(0.08, 0.11, 0.18, 1.0);
uniform vec4 high_color : source_color = vec4(0.18, 0.22, 0.29, 1.0);
uniform vec4 ridge_color : source_color = vec4(0.42, 0.16, 0.12, 1.0);
uniform vec2 mask_uv_origin = vec2(0.0, 0.0);
uniform vec2 mask_uv_size = vec2(1.0, 1.0);
uniform float reveal_softness : hint_range(0.001, 0.5, 0.001) = 0.14;
uniform float slope_strength = 1.6;

varying float v_base_height;
varying float v_wall_height;
varying vec3 v_derived_normal;


float sample_combined_height(vec2 uv) {
	float terrain_height = texture(heightmap, uv).r * amplitude;
	float wall_height = texture(wall_heightmap, uv).r * wall_amplitude;
	return terrain_height + wall_height;
}


void vertex() {
	float base_height = texture(heightmap, UV).r;
	float wall_height = texture(wall_heightmap, UV).r;
	VERTEX.y += (base_height * amplitude) + (wall_height * wall_amplitude);
	v_base_height = base_height;
	v_wall_height = wall_height;

	vec2 texel = max(heightmap_texel_size, vec2(0.0001, 0.0001));
	float left_height = sample_combined_height(UV - vec2(texel.x, 0.0));
	float right_height = sample_combined_height(UV + vec2(texel.x, 0.0));
	float down_height = sample_combined_height(UV - vec2(0.0, texel.y));
	float up_height = sample_combined_height(UV + vec2(0.0, texel.y));
	v_derived_normal = normalize(vec3((left_height - right_height) * slope_strength, 2.0, (down_height - up_height) * slope_strength));
}


void fragment() {
	vec2 safe_mask_uv_size = max(mask_uv_size, vec2(0.0001, 0.0001));
	vec2 mask_uv = mask_uv_origin + (UV * safe_mask_uv_size);
	float revealed = 0.0;
	if (mask_uv.x >= 0.0 && mask_uv.x <= 1.0 && mask_uv.y >= 0.0 && mask_uv.y <= 1.0) {
		revealed = texture(exploration_mask, mask_uv).r;
	}
	float visible = smoothstep(0.5 - reveal_softness, 0.5 + reveal_softness, revealed);
	if (visible <= 0.001) {
		discard;
	}

	float ridge_mix = clamp(v_wall_height * 1.35, 0.0, 1.0);
	float height_mix = clamp(v_base_height + (v_wall_height * 0.35), 0.0, 1.0);
	vec3 terrain_color = mix(low_color.rgb, high_color.rgb, height_mix);
	terrain_color = mix(terrain_color, ridge_color.rgb, ridge_mix);

	float upness = clamp(normalize(v_derived_normal).y, 0.0, 1.0);
	float slope_shade = mix(0.74, 1.0, pow(upness, 1.5));
	float height_glow = mix(0.92, 1.08, height_mix);

	ALBEDO = terrain_color * slope_shade * height_glow;
	ALPHA = visible;
}