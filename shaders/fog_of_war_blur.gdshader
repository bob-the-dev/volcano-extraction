shader_type spatial;

render_mode unshaded, fog_disabled, cull_disabled, depth_draw_never;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap, repeat_disable;
uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest, repeat_disable;
uniform sampler2D exploration_mask_texture : filter_linear, repeat_disable;

uniform vec2 exploration_world_origin = vec2(0.0, 0.0);
uniform vec2 exploration_world_size = vec2(1.0, 1.0);
uniform float blur_mip_level : hint_range(0.0, 20.0, 0.1) = 8;
uniform float reveal_softness : hint_range(0.001, 0.5, 0.001) = 0.3;
uniform bool debug_show_mask = false;


void vertex() {
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}


vec3 reconstruct_world_position(vec2 screen_uv, float depth_raw) {
	vec3 ndc = vec3(screen_uv * 2.0 - 1.0, depth_raw);
	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	return (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
}


void fragment() {
	vec3 sharp_color = texture(SCREEN_TEXTURE, SCREEN_UV).rgb;
	float depth_raw = texture(DEPTH_TEXTURE, SCREEN_UV).r;

	if (depth_raw <= 0.00001) {
		ALBEDO = sharp_color;
		ALPHA = 1.0;
		return;
	}

	if (exploration_world_size.x <= 0.0001 || exploration_world_size.y <= 0.0001) {
		ALBEDO = sharp_color;
		ALPHA = 1.0;
		return;
	}

	vec3 world_position = reconstruct_world_position(SCREEN_UV, depth_raw);
	vec2 mask_uv = (world_position.xz - exploration_world_origin) / exploration_world_size;
	if (mask_uv.x < 0.0 || mask_uv.x > 1.0 || mask_uv.y < 0.0 || mask_uv.y > 1.0) {
		ALBEDO = sharp_color;
		ALPHA = 1.0;
		return;
	}

	float revealed = texture(exploration_mask_texture, mask_uv).r;
	float reveal_mask = smoothstep(0.5 - reveal_softness, 0.5 + reveal_softness, revealed);
	if (debug_show_mask) {
		vec3 debug_color = mix(vec3(1.0, 0.1, 0.05), vec3(0.05, 0.9, 0.2), reveal_mask);
		ALBEDO = mix(sharp_color, debug_color, 0.85);
		ALPHA = 1.0;
		return;
	}

	vec3 blurred_color = textureLod(SCREEN_TEXTURE, SCREEN_UV, blur_mip_level).rgb;

	ALBEDO = mix(blurred_color, sharp_color, reveal_mask);
	ALPHA = 1.0;
}