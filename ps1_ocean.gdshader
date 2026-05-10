shader_type spatial;
render_mode blend_mix, depth_draw_opaque;

uniform float wave_frequency = 2.0;
uniform float wave_amplitude = 0.12;
uniform float wave_speed = 0.5;

uniform sampler3D noise_texture : source_color; 

uniform vec4 caustic_color : source_color = vec4(0.173, 0.122, 0.0, 1.0);
uniform float caustic_scale = 2.0;
uniform float caustic_speed = 0.1;
uniform float caustic_intensity : hint_range(0.0, 4.0) = 1.0;
uniform float caustic_sharpness : hint_range(0.0, 1.0) = 0.5;
uniform float caustic_falloff : hint_range(0.0, 0.2) = 0.1;

uniform vec4 water_color : source_color = vec4(0.2, 0.45, 0.5, 1.0); 
uniform vec4 deep_water_color : source_color = vec4(0.05, 0.2, 0.3, 1.0); 
uniform float pixelization_amount : hint_range(0.0, 1.0) = 0.08;

uniform sampler2D DEPTH_TEXTURE : hint_depth_texture, filter_nearest;
uniform float color_deep_fade_distance : hint_range(0.0, 10.0, 0.1) = 3.0;

uniform vec3 foam_color : source_color = vec3(1.0, 1.0, 1.0);
uniform float foam_scale = 4.0;
uniform float foam_speed = 0.8;
uniform float foam_distance : hint_range(0.0, 2.0, 0.01) = 0.4; 
uniform float foam_noise_influence : hint_range(0.0, 2.0, 0.01) = 0.7; 

varying vec3 v_normal;

void vertex() {
    VERTEX.y += sin(VERTEX.x * wave_frequency + TIME * wave_speed) * wave_amplitude;
    VERTEX.y += cos(VERTEX.z * wave_frequency * 0.5 + TIME * wave_speed * 0.8) * wave_amplitude;
    
    float height_x = sin((VERTEX.x + 0.1) * wave_frequency + TIME * wave_speed) * wave_amplitude +
                     cos(VERTEX.z * wave_frequency * 0.5 + TIME * wave_speed * 0.8) * wave_amplitude;
    float height_z = sin(VERTEX.x * wave_frequency + TIME * wave_speed) * wave_amplitude +
                     cos((VERTEX.z + 0.1) * wave_frequency * 0.5 + TIME * wave_speed * 0.8) * wave_amplitude;
    
    vec3 tangent = normalize(vec3(0.1, height_x - VERTEX.y, 0.0));
    vec3 binormal = normalize(vec3(0.0, height_z - VERTEX.y, 0.1));
    v_normal = cross(tangent, binormal);
}

void fragment() {    
    vec2 pixelated_uv = UV;
    if (pixelization_amount > 0.001) {
        float pixel_size = pixelization_amount * 0.05; 
        pixelated_uv = floor(UV / pixel_size) * pixel_size;
    }

    // depth fade
    float depth_tex = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    vec3 ndc;
    #if CURRENT_RENDERER == RENDERER_COMPATIBILITY
        // Compatibility (OpenGL) uses a [-1, 1] Z range for NDC
        ndc = vec3(SCREEN_UV, depth_tex) * 2.0 - 1.0;
    #else
        // Forward+ and Mobile (Vulkan) use a [0, 1] Z range for NDC
        ndc = vec3(SCREEN_UV * 2.0 - 1.0, depth_tex);
    #endif
    vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    view.xyz /= view.w;

    vec3 world_terrain_pos = (INV_VIEW_MATRIX * vec4(view.xyz, 1.0)).xyz;
    vec3 world_water_pos = (INV_VIEW_MATRIX * vec4(VERTEX, 1.0)).xyz;

    float depth_blend = max(0.0, world_water_pos.y - world_terrain_pos.y);

    float depth_color_blend = clamp(depth_blend / max(0.001, color_deep_fade_distance), 0.0, 1.0);
    vec3 final_color = mix(water_color.rgb, deep_water_color.rgb, depth_color_blend);

    // caustics
    vec3 uvw_1 = vec3(pixelated_uv * caustic_scale, TIME * caustic_speed);
    vec3 uvw_2 = vec3(pixelated_uv * caustic_scale * 0.8, (TIME + 5.0) * caustic_speed * -0.7);

    float noise1 = texture(noise_texture, uvw_1).r;
    float noise2 = texture(noise_texture, uvw_2).r;

    float caustics_raw = 1.0 - abs(noise1 - noise2);
    float caustics = smoothstep(caustic_sharpness - caustic_falloff, caustic_sharpness + caustic_falloff, caustics_raw);
    
    final_color += caustics * caustic_color.rgb * caustic_intensity;
    
    // foam
    vec3 foam_uvw = vec3(pixelated_uv * foam_scale, TIME * foam_speed);
    float foam_noise = texture(noise_texture, foam_uvw).r;
    
    float eroded_depth = depth_blend + (foam_noise * foam_noise_influence);
    float foam_mask = step(eroded_depth, foam_distance); // keep it pixelated
    vec3 textured_foam = foam_color * (0.7 + 0.3 * foam_noise);
    
    final_color = mix(final_color, textured_foam, foam_mask);
    
    ALBEDO = final_color;
    ALPHA = water_color.a; 
}