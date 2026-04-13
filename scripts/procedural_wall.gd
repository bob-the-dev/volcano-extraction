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

@export_range(0.0, 0.4) var pillar_inset: float = 0.15:
	set(value):
		pillar_inset = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export_group("Pillar Radii")
@export var corner_nw_base_radius: float = 0.5:
	set(value):
		corner_nw_base_radius = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_nw_top_radius: float = 0.1:
	set(value):
		corner_nw_top_radius = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_ne_base_radius: float = 0.5:
	set(value):
		corner_ne_base_radius = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_ne_top_radius: float = 0.1:
	set(value):
		corner_ne_top_radius = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_sw_base_radius: float = 0.5:
	set(value):
		corner_sw_base_radius = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_sw_top_radius: float = 0.1:
	set(value):
		corner_sw_top_radius = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_se_base_radius: float = 0.5:
	set(value):
		corner_se_base_radius = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_se_top_radius: float = 0.1:
	set(value):
		corner_se_top_radius = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export_group("Pillar Top Offset")
@export var corner_nw_top_inset: float = 0.0:
	set(value):
		corner_nw_top_inset = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_ne_top_inset: float = 0.0:
	set(value):
		corner_ne_top_inset = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_sw_top_inset: float = 0.0:
	set(value):
		corner_sw_top_inset = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var corner_se_top_inset: float = 0.0:
	set(value):
		corner_se_top_inset = value
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
	
	# Get nodes directly (more reliable in @tool scripts)
	var mesh_node := get_node_or_null("Surface") as MeshInstance3D
	var collision_node := get_node_or_null("CollisionShape3D") as CollisionShape3D
	
	# Check if child nodes exist
	if not mesh_node or not collision_node:
		push_warning("ProceduralWall: Child nodes not ready yet")
		return
	
	_is_regenerating = true
	_generate_wall(mesh_node)
	_generate_collision(mesh_node, collision_node)
	_is_regenerating = false


## Generates the complete volumetric wall with base and pillars.
func _generate_wall(mesh_node: MeshInstance3D) -> void:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Generate all geometry components
	_generate_base(surface_tool)
	_generate_pillars(surface_tool)
	
	# Generate flat normals for faceted appearance
	surface_tool.generate_normals()
	
	# Commit to mesh
	var array_mesh := surface_tool.commit()
	mesh_node.mesh = array_mesh


## Generates the base platform (1x1 slab at ground level).
func _generate_base(surface_tool: SurfaceTool) -> void:
	var half_size: float = 0.5
	var y_bottom: float = 0.0
	var y_top: float = 0.05  # Thin base platform
	
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
	var half_size: float = 0.5
	# Position pillars centered around origin, with inset from edges
	var inset_from_edge: float = half_size - pillar_inset
	var corners := [
		{
			"pos": Vector3(-inset_from_edge, 0.0, -inset_from_edge),
			"height": corner_heights.nw,
			"base_radius": corner_nw_base_radius,
			"top_radius": corner_nw_top_radius,
			"top_inset": corner_nw_top_inset
		},
		{
			"pos": Vector3(inset_from_edge, 0.0, -inset_from_edge),
			"height": corner_heights.ne,
			"base_radius": corner_ne_base_radius,
			"top_radius": corner_ne_top_radius,
			"top_inset": corner_ne_top_inset
		},
		{
			"pos": Vector3(-inset_from_edge, 0.0, inset_from_edge),
			"height": corner_heights.sw,
			"base_radius": corner_sw_base_radius,
			"top_radius": corner_sw_top_radius,
			"top_inset": corner_sw_top_inset
		},
		{
			"pos": Vector3(inset_from_edge, 0.0, inset_from_edge),
			"height": corner_heights.se,
			"base_radius": corner_se_base_radius,
			"top_radius": corner_se_top_radius,
			"top_inset": corner_se_top_inset
		}
	]
	
	for corner in corners:
		_add_tapered_cylinder(surface_tool, corner.pos, corner.height, corner.base_radius, corner.top_radius, corner.top_inset)


## Adds a single tapered cylinder to the mesh.
func _add_tapered_cylinder(surface_tool: SurfaceTool, base_pos: Vector3, height: float, base_radius: float, top_radius: float, top_inset: float) -> void:
	var rings: Array = []
	
	# Calculate direction toward center for top offset
	var center := Vector3.ZERO
	var to_center := (center - base_pos).normalized()
	
	# Generate vertex rings from bottom to top
	for h_idx in range(height_segments + 1):
		var t: float = float(h_idx) / float(height_segments)
		var y: float = base_pos.y + height * t
		var radius: float = lerp(base_radius, top_radius, t)
		
		# Apply top inset: move center position toward wall center
		var inset_offset := to_center * top_inset * t
		var ring_center := base_pos + inset_offset
		
		var ring: Array = []
		for r_idx in range(radial_segments):
			var angle: float = (float(r_idx) / float(radial_segments)) * TAU
			var x: float = ring_center.x + cos(angle) * radius
			var z: float = ring_center.z + sin(angle) * radius
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
	# Calculate top center with inset applied (reuse to_center from above)
	var top_center := base_pos + Vector3(0, height, 0) + to_center * top_inset
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


## Generates collision shape matching the surface geometry.
func _generate_collision(mesh_node: MeshInstance3D, collision_node: CollisionShape3D) -> void:
	if not mesh_node or not collision_node:
		push_error("ProceduralWall: Required nodes not found!")
		return
	
	# Create collision from surface mesh
	if mesh_node.mesh:
		var mesh_data := mesh_node.mesh.create_trimesh_shape()
		if mesh_data:
			collision_node.shape = mesh_data
			# Ensure owner is set in editor
			if Engine.is_editor_hint() and get_tree() and get_tree().edited_scene_root:
				if collision_node.owner != get_tree().edited_scene_root:
					collision_node.owner = get_tree().edited_scene_root
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

