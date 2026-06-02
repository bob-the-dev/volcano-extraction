shader_type canvas_item;

uniform sampler2D exploration_mask : filter_linear, repeat_disable;
uniform vec2 mask_uv_origin = vec2(0.0, 0.0);
uniform vec2 mask_uv_size = vec2(1.0, 1.0);
uniform float reveal_softness : hint_range(0.001, 0.5, 0.001) = 0.14;
uniform vec2 player_uv = vec2(-1.0, -1.0);
uniform vec2 focus_world_size = vec2(1.0, 1.0);
uniform float player_reveal_radius_world = 0.0;
uniform float player_reveal_softness_world = 1.0;


void fragment() {
	vec2 safe_mask_uv_size = max(mask_uv_size, vec2(0.0001, 0.0001));
	vec2 mask_uv = (UV - mask_uv_origin) / safe_mask_uv_size;
	float revealed = 0.0;
	if (mask_uv.x >= 0.0 && mask_uv.x <= 1.0 && mask_uv.y >= 0.0 && mask_uv.y <= 1.0) {
		revealed = texture(exploration_mask, mask_uv).r;
	}

	float persistent_visible = smoothstep(0.5 - reveal_softness, 0.5 + reveal_softness, revealed);
	float player_visible = 0.0;
	if (player_uv.x >= 0.0 && player_uv.y >= 0.0) {
		vec2 world_offset = (UV - player_uv) * focus_world_size;
		float world_distance = length(world_offset);
		player_visible = 1.0 - smoothstep(
			player_reveal_radius_world,
			player_reveal_radius_world + max(player_reveal_softness_world, 0.0001),
			world_distance
		);
	}

	float visible = max(persistent_visible, player_visible);
	vec4 minimap_color = texture(TEXTURE, UV) * COLOR;
	COLOR = vec4(minimap_color.rgb, minimap_color.a * visible);
}