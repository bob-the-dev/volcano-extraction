shader_type spatial;
render_mode cull_back;

// Parameters for controlling the bevel smoothness
uniform float bevel_radius : hint_range(0.0, 1.0) = 0.3;
uniform float bevel_smoothness : hint_range(0.0, 1.0) = 0.8;
uniform vec3 base_color : source_color = vec3(0.8, 0.8, 0.8);
uniform float ambient_occlusion_strength : hint_range(0.0, 1.0) = 0.3;

// Vertex color channels used to encode edge information:
// r: distance to nearest edge (0 = at edge, 1 = center of platform)
// g: depth level (0-4 normalized to 0.0-1.0)
// b: normal Y component hint for beveling
// a: unused

varying vec3 vertex_color;
varying vec3 world_pos;
varying vec3 original_normal;

void vertex() {
	// Store vertex color for fragment shader
	vertex_color = COLOR.rgb;
	
	// Get distance to edge from red channel (0 = edge, 1 = center)
	float edge_dist = COLOR.r;
	
	// Get depth transition info from blue channel (0-1, where 1 means vertical wall)
	float is_vertical_wall = COLOR.b;
	
	// Apply bevel displacement
	if (edge_dist < bevel_radius && is_vertical_wall > 0.5) {
		// We're near an edge on a vertical surface - apply rounding
		float normalized_dist = edge_dist / bevel_radius;
		
		// Use smoothstep for nice curved falloff
		float displacement_amount = smoothstep(0.0, 1.0, 1.0 - normalized_dist) * bevel_smoothness;
		
		// Displace vertex inward and adjust height for rounded bevel effect
		// The normal provides direction for displacement
		VERTEX += NORMAL * displacement_amount * bevel_radius * 0.5;
	}
	
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	original_normal = NORMAL;
}

void fragment() {
	// Base color with depth-based darkness
	float depth_level = vertex_color.g;
	vec3 color = base_color * (1.0 - depth_level * 0.15);
	
	// Add ambient occlusion in corners and edges
	float edge_dist = vertex_color.r;
	float ao = mix(1.0 - ambient_occlusion_strength, 1.0, edge_dist);
	
	ALBEDO = color * ao;
	ROUGHNESS = 0.9;
	METALLIC = 0.0;
}
