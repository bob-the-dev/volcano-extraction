shader_type spatial;

render_mode unshaded, cull_disabled, blend_mix, depth_prepass_alpha;

uniform sampler2D exploration_mask : filter_linear, repeat_disable;
uniform vec2 mask_uv_origin = vec2(0.0, 0.0);
uniform vec2 mask_uv_size = vec2(1.0, 1.0);
uniform float reveal_softness : hint_range(0.001, 0.5, 0.001) = 0.14;
uniform vec4 lava_color : source_color = vec4(0.0, 0.0, 0.0, 0.65);
uniform vec4 deep_lava_color : source_color = vec4(1.0, 0.48, 0.04, 0.95);
uniform vec4 caustic_color : source_color = vec4(0.44, 0.10, 0.0, 1.0);
uniform vec2 molten_scale = vec2(18.0, 15.0);
uniform vec2 molten_speed = vec2(1.6, 1.1);
uniform float caustic_scale : hint_range(1.0, 128.0, 0.1) = 24.0;
uniform float caustic_speed : hint_range(0.0, 10.0, 0.01) = 2.2;
uniform float caustic_strength : hint_range(0.0, 2.0, 0.01) = 0.28;


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

	float molten_wave = sin((UV.x * molten_scale.x) - (TIME * molten_speed.x)) * cos((UV.y * molten_scale.y) + (TIME * molten_speed.y));
	float molten_mix = clamp((molten_wave * 0.5) + 0.5, 0.0, 1.0);
	vec3 base_color = mix(lava_color.rgb, deep_lava_color.rgb, molten_mix);

	float caustic_wave = sin(((UV.x + UV.y) * caustic_scale) + (TIME * caustic_speed));
	float caustic_mask = pow((caustic_wave * 0.5) + 0.5, 3.0);
	vec3 final_color = base_color + (caustic_color.rgb * caustic_mask * caustic_strength);

	ALBEDO = final_color;
	ALPHA = max(lava_color.a, deep_lava_color.a) * visible;
}