@tool
extends StaticBody3D

## Procedural floor tile with rounded corners.

# Export parameters
@export_group("Dimensions")
@export var tile_size: float = 2.0:
	set(value):
		tile_size = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export var tile_height: float = 0.1:
	set(value):
		tile_height = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export_range(0.0, 0.5) var corner_radius: float = 0.15:
	set(value):
		corner_radius = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

@export_range(4, 16) var corner_segments: int = 8:
	set(value):
		corner_segments = value
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
		push_warning("ProceduralFloorTile: Child nodes not ready yet")
		return
	
	_is_regenerating = true
	_generate_floor_tile(mesh_node)
	_generate_collision(mesh_node, collision_node)
	_is_regenerating = false


## Generates the floor tile mesh with rounded corners.
func _generate_floor_tile(mesh_node: MeshInstance3D) -> void:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Calculate dimensions
	var half_size := tile_size * 0.5
	var inset := corner_radius
	var y_bottom := 0.0
	var y_top := tile_height
	
	# Create main quad (center rectangle minus corners)
	# We'll create 5 sections: center + 4 corner areas
	
	# Center rectangle (full tile minus corners)
	_add_rectangle_top_bottom(surface_tool, 
		Vector2(-half_size + inset, -half_size + inset),
		Vector2(half_size - inset, half_size - inset),
		y_top, y_bottom)
	
	# Four corner rectangles (connecting center to rounded corners)
	# Top edge - add only north side face
	_add_rectangle_with_sides(surface_tool,
		Vector2(-half_size + inset, -half_size),
		Vector2(half_size - inset, -half_size + inset),
		y_top, y_bottom, true, false, false, false)  # North only
	
	# Bottom edge - add only south side face
	_add_rectangle_with_sides(surface_tool,
		Vector2(-half_size + inset, half_size - inset),
		Vector2(half_size - inset, half_size),
		y_top, y_bottom, false, true, false, false)  # South only
	
	# Left edge - add only west side face
	_add_rectangle_with_sides(surface_tool,
		Vector2(-half_size, -half_size + inset),
		Vector2(-half_size + inset, half_size - inset),
		y_top, y_bottom, false, false, true, false)  # West only
	
	# Right edge - add only east side face
	_add_rectangle_with_sides(surface_tool,
		Vector2(half_size - inset, -half_size + inset),
		Vector2(half_size, half_size - inset),
		y_top, y_bottom, false, false, false, true)  # East only
	
	# Four rounded corners
	_add_rounded_corner(surface_tool, Vector2(-half_size + inset, -half_size + inset), PI, y_top, y_bottom)      # Top-left
	_add_rounded_corner(surface_tool, Vector2(half_size - inset, -half_size + inset), PI * 1.5, y_top, y_bottom) # Top-right
	_add_rounded_corner(surface_tool, Vector2(half_size - inset, half_size - inset), 0.0, y_top, y_bottom)       # Bottom-right
	_add_rounded_corner(surface_tool, Vector2(-half_size + inset, half_size - inset), PI * 0.5, y_top, y_bottom) # Bottom-left
	
	# Add connecting side faces between straight edges and rounded corners
	# Top-left corner connections
	_add_vertical_face(surface_tool, 
		Vector2(-half_size + inset, -half_size), 
		Vector2(-half_size + inset, -half_size + inset), y_top, y_bottom)  # Connects top edge to top-left corner
	_add_vertical_face(surface_tool,
		Vector2(-half_size, -half_size + inset),
		Vector2(-half_size + inset, -half_size + inset), y_top, y_bottom)  # Connects left edge to top-left corner
	
	# Top-right corner connections
	_add_vertical_face(surface_tool,
		Vector2(half_size - inset, -half_size + inset),
		Vector2(half_size - inset, -half_size), y_top, y_bottom)  # Connects top-right corner to top edge
	_add_vertical_face(surface_tool,
		Vector2(half_size - inset, -half_size + inset),
		Vector2(half_size, -half_size + inset), y_top, y_bottom)  # Connects top-right corner to right edge
	
	# Bottom-right corner connections
	_add_vertical_face(surface_tool,
		Vector2(half_size, half_size - inset),
		Vector2(half_size - inset, half_size - inset), y_top, y_bottom)  # Connects right edge to bottom-right corner
	_add_vertical_face(surface_tool,
		Vector2(half_size - inset, half_size - inset),
		Vector2(half_size - inset, half_size), y_top, y_bottom)  # Connects bottom-right corner to bottom edge
	
	# Bottom-left corner connections
	_add_vertical_face(surface_tool,
		Vector2(-half_size + inset, half_size - inset),
		Vector2(-half_size + inset, half_size), y_top, y_bottom)  # Connects bottom-left corner to bottom edge
	_add_vertical_face(surface_tool,
		Vector2(-half_size + inset, half_size - inset),
		Vector2(-half_size, half_size - inset), y_top, y_bottom)  # Connects left edge to bottom-left corner
	
	# Generate normals and commit
	surface_tool.generate_normals()
	var array_mesh := surface_tool.commit()
	mesh_node.mesh = array_mesh


## Adds a rectangular section with only top and bottom faces.
func _add_rectangle_top_bottom(surface_tool: SurfaceTool, min_corner: Vector2, max_corner: Vector2, y_top: float, y_bottom: float) -> void:
	# Top face
	var nw_top := Vector3(min_corner.x, y_top, min_corner.y)
	var ne_top := Vector3(max_corner.x, y_top, min_corner.y)
	var sw_top := Vector3(min_corner.x, y_top, max_corner.y)
	var se_top := Vector3(max_corner.x, y_top, max_corner.y)
	
	surface_tool.add_vertex(nw_top)
	surface_tool.add_vertex(ne_top)
	surface_tool.add_vertex(sw_top)
	
	surface_tool.add_vertex(sw_top)
	surface_tool.add_vertex(ne_top)
	surface_tool.add_vertex(se_top)
	
	# Bottom face (reversed winding)
	var nw_btm := Vector3(min_corner.x, y_bottom, min_corner.y)
	var ne_btm := Vector3(max_corner.x, y_bottom, min_corner.y)
	var sw_btm := Vector3(min_corner.x, y_bottom, max_corner.y)
	var se_btm := Vector3(max_corner.x, y_bottom, max_corner.y)
	
	surface_tool.add_vertex(nw_btm)
	surface_tool.add_vertex(sw_btm)
	surface_tool.add_vertex(ne_btm)
	
	surface_tool.add_vertex(ne_btm)
	surface_tool.add_vertex(sw_btm)
	surface_tool.add_vertex(se_btm)


## Adds a rectangular section with selective side faces.
func _add_rectangle_with_sides(surface_tool: SurfaceTool, min_corner: Vector2, max_corner: Vector2, y_top: float, y_bottom: float, 
								add_north: bool, add_south: bool, add_west: bool, add_east: bool) -> void:
	# Add top and bottom first
	_add_rectangle_top_bottom(surface_tool, min_corner, max_corner, y_top, y_bottom)
	
	# Add only requested side faces
	var nw_top := Vector3(min_corner.x, y_top, min_corner.y)
	var ne_top := Vector3(max_corner.x, y_top, min_corner.y)
	var sw_top := Vector3(min_corner.x, y_top, max_corner.y)
	var se_top := Vector3(max_corner.x, y_top, max_corner.y)
	
	var nw_btm := Vector3(min_corner.x, y_bottom, min_corner.y)
	var ne_btm := Vector3(max_corner.x, y_bottom, min_corner.y)
	var sw_btm := Vector3(min_corner.x, y_bottom, max_corner.y)
	var se_btm := Vector3(max_corner.x, y_bottom, max_corner.y)
	
	if add_north:
		# North face
		surface_tool.add_vertex(nw_top)
		surface_tool.add_vertex(ne_top)
		surface_tool.add_vertex(nw_btm)
		
		surface_tool.add_vertex(nw_btm)
		surface_tool.add_vertex(ne_top)
		surface_tool.add_vertex(ne_btm)
	
	if add_south:
		# South face
		surface_tool.add_vertex(se_top)
		surface_tool.add_vertex(sw_top)
		surface_tool.add_vertex(se_btm)
		
		surface_tool.add_vertex(se_btm)
		surface_tool.add_vertex(sw_top)
		surface_tool.add_vertex(sw_btm)
	
	if add_west:
		# West face
		surface_tool.add_vertex(sw_top)
		surface_tool.add_vertex(nw_top)
		surface_tool.add_vertex(sw_btm)
		
		surface_tool.add_vertex(sw_btm)
		surface_tool.add_vertex(nw_top)
		surface_tool.add_vertex(nw_btm)
	
	if add_east:
		# East face
		surface_tool.add_vertex(ne_top)
		surface_tool.add_vertex(se_top)
		surface_tool.add_vertex(ne_btm)
		
		surface_tool.add_vertex(ne_btm)
		surface_tool.add_vertex(se_top)
		surface_tool.add_vertex(se_btm)


## Adds a rounded corner section.
func _add_rounded_corner(surface_tool: SurfaceTool, center: Vector2, start_angle: float, y_top: float, y_bottom: float) -> void:
	var angle_step := (PI * 0.5) / corner_segments
	
	for i in range(corner_segments):
		var angle1 := start_angle + (i * angle_step)
		var angle2 := start_angle + ((i + 1) * angle_step)
		
		var p1 := center + Vector2(cos(angle1), sin(angle1)) * corner_radius
		var p2 := center + Vector2(cos(angle2), sin(angle2)) * corner_radius
		
		# Top face triangle
		var center_top := Vector3(center.x, y_top, center.y)
		var p1_top := Vector3(p1.x, y_top, p1.y)
		var p2_top := Vector3(p2.x, y_top, p2.y)
		
		surface_tool.add_vertex(center_top)
		surface_tool.add_vertex(p1_top)
		surface_tool.add_vertex(p2_top)
		
		# Bottom face triangle (reversed)
		var center_btm := Vector3(center.x, y_bottom, center.y)
		var p1_btm := Vector3(p1.x, y_bottom, p1.y)
		var p2_btm := Vector3(p2.x, y_bottom, p2.y)
		
		surface_tool.add_vertex(center_btm)
		surface_tool.add_vertex(p2_btm)
		surface_tool.add_vertex(p1_btm)
		
		# Curved side face (quad as 2 triangles)
		surface_tool.add_vertex(p1_top)
		surface_tool.add_vertex(p2_top)
		surface_tool.add_vertex(p1_btm)
		
		surface_tool.add_vertex(p1_btm)
		surface_tool.add_vertex(p2_top)
		surface_tool.add_vertex(p2_btm)


## Adds a vertical face between two 2D points.
func _add_vertical_face(surface_tool: SurfaceTool, p1: Vector2, p2: Vector2, y_top: float, y_bottom: float) -> void:
	var p1_top := Vector3(p1.x, y_top, p1.y)
	var p2_top := Vector3(p2.x, y_top, p2.y)
	var p1_btm := Vector3(p1.x, y_bottom, p1.y)
	var p2_btm := Vector3(p2.x, y_bottom, p2.y)
	
	# Quad as 2 triangles
	surface_tool.add_vertex(p1_top)
	surface_tool.add_vertex(p2_top)
	surface_tool.add_vertex(p1_btm)
	
	surface_tool.add_vertex(p1_btm)
	surface_tool.add_vertex(p2_top)
	surface_tool.add_vertex(p2_btm)


## Generates collision shape from mesh.
func _generate_collision(mesh_node: MeshInstance3D, collision_node: CollisionShape3D) -> void:
	if not mesh_node.mesh:
		return
	
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh_node.mesh.get_faces())
	collision_node.shape = shape
