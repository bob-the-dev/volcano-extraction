@tool
extends StaticBody3D

## Procedural rock wall with 4 tapered pillars rising from base platform.
## Each pillar has independent height control and pillars blend together.

# Export parameters
@export_group("Height Configuration")
@export var base_height: float = 1.0:
	set(value):
		base_height = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_nw_offset: float = 0.0:
	set(value):
		corner_nw_offset = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_ne_offset: float = 0.0:
	set(value):
		corner_ne_offset = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_sw_offset: float = 0.0:
	set(value):
		corner_sw_offset = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_se_offset: float = 0.0:
	set(value):
		corner_se_offset = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export_group("Geometry Configuration")
@export var base_thickness: float = 0.1:
	set(value):
		base_thickness = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var pillar_base_radius: float = 0.2:
	set(value):
		pillar_base_radius = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var pillar_top_radius: float = 0.08:
	set(value):
		pillar_top_radius = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export_range(4, 12) var radial_segments: int = 8:
	set(value):
		radial_segments = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export_range(2, 8) var height_segments: int = 4:
	set(value):
		height_segments = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export_range(2, 6) var bridge_segments: int = 3:
	set(value):
		bridge_segments = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export_range(0.0, 0.4) var pillar_inset: float = 0.15:
	set(value):
		pillar_inset = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

# Node references
@onready var surface_mesh: MeshInstance3D = $Surface
@onready var collision_shape: CollisionShape3D = $CollisionShape3D

# Private variables
var _is_regenerating: bool = false


func _ready() -> void:
	# Generate meshes on ready
	if is_inside_tree():
		_regenerate()


## Regenerates all meshes. Called when parameters change in editor.
func _regenerate() -> void:
	if _is_regenerating:
		return
	
	# Ensure we're in the scene tree
	if not is_inside_tree():
		return
	
	# Check if child nodes exist
	if not is_instance_valid(surface_mesh) or not is_instance_valid(collision_shape):
		push_warning("ProceduralWall: Child nodes not ready yet")
		return
	
	_is_regenerating = true
	_generate_wall()
	_generate_collision()
	_is_regenerating = false


## Generates the complete volumetric wall with base, pillars, and bridges.
func _generate_wall() -> void:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate all geometry components
	_generate_base(surface_tool)
	_generate_pillars(surface_tool)
	_generate_bridge_connections(surface_tool)
	
	# Generate flat normals for faceted appearance
	surface_tool.generate_normals()
	
	# Commit to mesh
	var array_mesh := surface_tool.commit()
	surface_mesh.mesh = array_mesh


## Generates the base platform (1x1 slab at ground level).
func _generate_base(surface_tool: SurfaceTool) -> void:
	var half_size: float = 0.5
	var y_bottom: float = 0.0
	var y_top: float = base_thickness
	
	# Bottom face vertices
	var btm_nw := Vector3(-half_size, y_bottom, -half_size)
	var btm_ne := Vector3(half_size, y_bottom, -half_size)
	var btm_sw := Vector3(-half_size, y_bottom, half_size)
	var btm_se := Vector3(half_size, y_bottom, half_size)
	
	# Top face vertices
	var top_nw := Vector3(-half_size, y_top, -half_size)
	var top_ne := Vector3(half_size, y_top, -half_size)
	var top_sw := Vector3(-half_size, y_top, half_size)
	var top_se := Vector3(half_size, y_top, half_size)
	
	# Top face (2 triangles)
	surface_tool.add_vertex(top_nw)
	surface_tool.add_vertex(top_ne)
	surface_tool.add_vertex(top_sw)
	
	surface_tool.add_vertex(top_sw)
	surface_tool.add_vertex(top_ne)
	surface_tool.add_vertex(top_se)
	
	# Bottom face (2 triangles, reversed winding)
	surface_tool.add_vertex(btm_nw)
	surface_tool.add_vertex(btm_ne)
	surface_tool.add_vertex(btm_sw)
	
	surface_tool.add_vertex(btm_ne)
	surface_tool.add_vertex(btm_se)
	surface_tool.add_vertex(btm_sw)
	
	# Side faces (4 walls, each with 2 triangles)
	# Front (z = -half_size)
	surface_tool.add_vertex(top_nw)
	surface_tool.add_vertex(top_ne)
	surface_tool.add_vertex(btm_nw)
	surface_tool.add_vertex(btm_nw)
	surface_tool.add_vertex(top_ne)
	surface_tool.add_vertex(btm_ne)
	
	# Right (x = half_size)
	surface_tool.add_vertex(top_ne)
	surface_tool.add_vertex(top_se)
	surface_tool.add_vertex(btm_ne)
	surface_tool.add_vertex(btm_ne)
	surface_tool.add_vertex(top_se)
	surface_tool.add_vertex(btm_se)
	
	# Back (z = half_size)
	surface_tool.add_vertex(top_se)
	surface_tool.add_vertex(top_sw)
	surface_tool.add_vertex(btm_se)
	surface_tool.add_vertex(btm_se)
	surface_tool.add_vertex(top_sw)
	surface_tool.add_vertex(btm_sw)
	
	# Left (x = -half_size)
	surface_tool.add_vertex(top_sw)
	surface_tool.add_vertex(top_nw)
	surface_tool.add_vertex(btm_sw)
	surface_tool.add_vertex(btm_sw)
	surface_tool.add_vertex(top_nw)
	surface_tool.add_vertex(btm_nw)


## Generates 4 tapered cylindrical pillars at grid corners.
func _generate_pillars(surface_tool: SurfaceTool) -> void:
	var corner_heights := _get_corner_heights()
	# Position pillars with inset from edges (0.15 means 0.15 units from edge toward center)
	var corners := [
		{"pos": Vector3(pillar_inset, base_thickness, pillar_inset), "height": corner_heights.nw},
		{"pos": Vector3(1.0 - pillar_inset, base_thickness, pillar_inset), "height": corner_heights.ne},
		{"pos": Vector3(pillar_inset, base_thickness, 1.0 - pillar_inset), "height": corner_heights.sw},
		{"pos": Vector3(1.0 - pillar_inset, base_thickness, 1.0 - pillar_inset), "height": corner_heights.se}
	]
	
	for corner in corners:
		_add_tapered_cylinder(surface_tool, corner.pos, corner.height)


## Adds a single tapered cylinder to the mesh.
func _add_tapered_cylinder(surface_tool: SurfaceTool, base_pos: Vector3, height: float) -> void:
	var rings: Array = []
	
	# Generate vertex rings from bottom to top
	for h_idx in range(height_segments + 1):
		var t: float = float(h_idx) / float(height_segments)
		var y: float = base_pos.y + height * t
		var radius: float = lerp(pillar_base_radius, pillar_top_radius, t)
		
		var ring: Array = []
		for r_idx in range(radial_segments):
			var angle: float = (float(r_idx) / float(radial_segments)) * TAU
			var x: float = base_pos.x + cos(angle) * radius
			var z: float = base_pos.z + sin(angle) * radius
			ring.append(Vector3(x, y, z))
		rings.append(ring)
	
	# Generate side faces (quads as 2 triangles)
	for h_idx in range(height_segments):
		var ring_bottom: Array = rings[h_idx]
		var ring_top: Array = rings[h_idx + 1]
		
		for r_idx in range(radial_segments):
			var next_r_idx: int = (r_idx + 1) % radial_segments
			
			var v1: Vector3 = ring_bottom[r_idx]
			var v2: Vector3 = ring_bottom[next_r_idx]
			var v3: Vector3 = ring_top[r_idx]
			var v4: Vector3 = ring_top[next_r_idx]
			
			# First triangle
			surface_tool.add_vertex(v1)
			surface_tool.add_vertex(v2)
			surface_tool.add_vertex(v3)
			
			# Second triangle
			surface_tool.add_vertex(v2)
			surface_tool.add_vertex(v4)
			surface_tool.add_vertex(v3)
	
	# Top cap
	var top_ring: Array = rings[height_segments]
	var top_center := base_pos + Vector3(0, height, 0)
	for r_idx in range(radial_segments):
		var next_r_idx: int = (r_idx + 1) % radial_segments
		surface_tool.add_vertex(top_center)
		surface_tool.add_vertex(top_ring[r_idx])
		surface_tool.add_vertex(top_ring[next_r_idx])
	
	# Bottom cap (connects to base platform)
	var bottom_ring: Array = rings[0]
	var bottom_center := base_pos
	for r_idx in range(radial_segments):
		var next_r_idx: int = (r_idx + 1) % radial_segments
		surface_tool.add_vertex(bottom_center)
		surface_tool.add_vertex(bottom_ring[next_r_idx])
		surface_tool.add_vertex(bottom_ring[r_idx])


## Generates bridge connections between adjacent pillars.
func _generate_bridge_connections(surface_tool: SurfaceTool) -> void:
	var corner_heights := _get_corner_heights()
	var corners := [
		{"pos": Vector3(pillar_inset, base_thickness, pillar_inset), "height": corner_heights.nw},
		{"pos": Vector3(1.0 - pillar_inset, base_thickness, pillar_inset), "height": corner_heights.ne},
		{"pos": Vector3(1.0 - pillar_inset, base_thickness, 1.0 - pillar_inset), "height": corner_heights.se},
		{"pos": Vector3(pillar_inset, base_thickness, 1.0 - pillar_inset), "height": corner_heights.sw}
	]
	
	# Connect each pair: 0→1, 1→2, 2→3, 3→0
	for i in range(4):
		var corner_a: Dictionary = corners[i]
		var corner_b: Dictionary = corners[(i + 1) % 4]
		_add_bridge(surface_tool, corner_a.pos, corner_a.height, corner_b.pos, corner_b.height)


## Adds a bridge connection between two pillar positions.
func _add_bridge(surface_tool: SurfaceTool, pos_a: Vector3, height_a: float, pos_b: Vector3, height_b: float) -> void:
	var rings: Array = []
	
	# Generate rings along path from A to B
	for seg_idx in range(bridge_segments + 1):
		var t: float = float(seg_idx) / float(bridge_segments)
		
		# Interpolate position and properties
		var center: Vector3 = pos_a.lerp(pos_b, t)
		var height: float = lerp(height_a, height_b, t)
		var base_radius: float = pillar_base_radius * 0.7  # Slightly thinner than pillar base
		var top_radius: float = pillar_top_radius * 0.7
		
		# Sample at mid-height of pillars for connection
		var sample_height: float = height * 0.5
		var radius: float = lerp(base_radius, top_radius, 0.5)
		
		var ring_y: float = center.y + sample_height
		
		var ring: Array = []
		for r_idx in range(radial_segments):
			var angle: float = (float(r_idx) / float(radial_segments)) * TAU
			var offset := Vector3(cos(angle) * radius, 0, sin(angle) * radius)
			ring.append(Vector3(center.x + offset.x, ring_y, center.z + offset.z))
		rings.append(ring)
	
	# Generate connecting geometry between rings
	for seg_idx in range(bridge_segments):
		var ring_a: Array = rings[seg_idx]
		var ring_b: Array = rings[seg_idx + 1]
		
		for r_idx in range(radial_segments):
			var next_r_idx: int = (r_idx + 1) % radial_segments
			
			var v1: Vector3 = ring_a[r_idx]
			var v2: Vector3 = ring_a[next_r_idx]
			var v3: Vector3 = ring_b[r_idx]
			var v4: Vector3 = ring_b[next_r_idx]
			
			# First triangle
			surface_tool.add_vertex(v1)
			surface_tool.add_vertex(v2)
			surface_tool.add_vertex(v3)
			
			# Second triangle
			surface_tool.add_vertex(v2)
			surface_tool.add_vertex(v4)
			surface_tool.add_vertex(v3)


## Generates collision shape matching the surface geometry.
func _generate_collision() -> void:
	# Use the pre-existing CollisionShape3D from the scene
	if not collision_shape:
		push_error("ProceduralWall: CollisionShape3D node missing from scene!")
		return
	
	# Create collision from surface mesh
	if surface_mesh and surface_mesh.mesh:
		var mesh_data := surface_mesh.mesh.create_trimesh_shape()
		if mesh_data:
			collision_shape.shape = mesh_data
			print("ProceduralWall: Collision shape updated successfully")
		else:
			push_error("ProceduralWall: Failed to create trimesh shape from mesh!")
	else:
		push_error("ProceduralWall: Surface mesh is invalid, cannot create collision!")


## Returns a dictionary with calculated corner heights.
func _get_corner_heights() -> Dictionary:
	return {
		"nw": base_height + corner_nw_offset,
		"ne": base_height + corner_ne_offset,
		"sw": base_height + corner_sw_offset,
		"se": base_height + corner_se_offset
	}

