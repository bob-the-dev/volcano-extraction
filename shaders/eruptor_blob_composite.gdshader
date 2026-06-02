shader_type canvas_item;

render_mode unshaded;

uniform sampler2D source_texture : filter_linear, repeat_disable;
uniform vec2 source_texel_size = vec2(0.001, 0.001);
uniform float blur_radius : hint_range(0.0, 12.0, 0.1) = 3.6;
uniform float merge_threshold : hint_range(0.0, 1.0, 0.01) = 0.22;
uniform float edge_softness : hint_range(0.001, 0.5, 0.001) = 0.09;
uniform vec4 source_key_color : source_color = vec4(1.0, 0.0, 1.0, 1.0);
uniform float source_threshold : hint_range(0.0, 1.0, 0.01) = 0.25;
uniform float blob_opacity : hint_range(0.0, 2.0, 0.01) = 0.95;
uniform vec4 deep_color : source_color = vec4(0.22, 0.02, 0.01, 1.0);
uniform vec4 hot_color : source_color = vec4(1.0, 0.45, 0.11, 1.0);
uniform vec4 rim_color : source_color = vec4(1.0, 0.86, 0.48, 1.0);
uniform float glow_strength : hint_range(0.0, 6.0, 0.01) = 1.35;
uniform float noise_strength : hint_range(0.0, 1.0, 0.01) = 0.18;
uniform float noise_scale : hint_range(0.1, 32.0, 0.1) = 9.0;


float source_mask(vec2 uv) {
	vec4 sample_color = texture(source_texture, uv);
	float color_distance = distance(sample_color.rgb, source_key_color.rgb);
	return 1.0 - smoothstep(0.0, source_threshold, color_distance);
}


float blob_field(vec2 uv) {
	vec2 texel = source_texel_size * blur_radius;
	float total = 0.0;
	float weight = 0.0;

	total += source_mask(uv) * 0.24;
	weight += 0.24;

	total += source_mask(uv + vec2(texel.x, 0.0)) * 0.12;
	total += source_mask(uv - vec2(texel.x, 0.0)) * 0.12;
	total += source_mask(uv + vec2(0.0, texel.y)) * 0.12;
	total += source_mask(uv - vec2(0.0, texel.y)) * 0.12;
	weight += 0.48;

	total += source_mask(uv + texel) * 0.07;
	total += source_mask(uv + vec2(texel.x, -texel.y)) * 0.07;
	total += source_mask(uv + vec2(-texel.x, texel.y)) * 0.07;
	total += source_mask(uv - texel) * 0.07;
	weight += 0.28;

	total += source_mask(uv + (texel * 2.0)) * 0.03;
	total += source_mask(uv + vec2(texel.x * 2.0, 0.0)) * 0.03;
	total += source_mask(uv + vec2(0.0, texel.y * 2.0)) * 0.03;
	total += source_mask(uv - vec2(texel.x * 2.0, 0.0)) * 0.03;
	total += source_mask(uv - vec2(0.0, texel.y * 2.0)) * 0.03;
	weight += 0.15;

	return total / max(weight, 0.0001);
}


float noise_value(vec2 uv) {
	vec2 noise_uv = uv * noise_scale;
	float noise_wave = sin((noise_uv.x + TIME * 0.7) * 7.1) * cos((noise_uv.y - TIME * 0.45) * 6.3);
	float detail_wave = sin(((noise_uv.x + noise_uv.y) + (TIME * 0.3)) * 11.7);
	return ((noise_wave * 0.7) + (detail_wave * 0.3)) * 0.5 + 0.5;
}


void fragment() {
	float field = blob_field(UV);
	float blob_alpha = smoothstep(merge_threshold - edge_softness, merge_threshold + edge_softness, field);
	if (blob_alpha <= 0.0001) {
		COLOR = vec4(0.0);
	} else {
		float core = smoothstep(merge_threshold + edge_softness, 1.0, field);
		float rim = clamp(blob_alpha - core, 0.0, 1.0);
		float animated_noise = mix(0.5, noise_value(UV), noise_strength);
		float heat_mix = clamp(core + ((animated_noise - 0.5) * noise_strength), 0.0, 1.0);

		vec3 lava_color = mix(deep_color.rgb, hot_color.rgb, heat_mix);
		lava_color += rim * rim_color.rgb * glow_strength;
		COLOR = vec4(lava_color, blob_alpha * blob_opacity);
	}
}