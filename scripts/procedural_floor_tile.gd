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

@export_group("Corner Displacement")
## Offset for top-left corner. Set by procedural map generator based on grid position + noise.
@export var corner_offset_tl: Vector2 = Vector2.ZERO:
	set(value):
		corner_offset_tl = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

## Offset for top-right corner. Set by procedural map generator based on grid position + noise.
@export var corner_offset_tr: Vector2 = Vector2.ZERO:
	set(value):
		corner_offset_tr = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

## Offset for bottom-right corner. Set by procedural map generator based on grid position + noise.
@export var corner_offset_br: Vector2 = Vector2.ZERO:
	set(value):
		corner_offset_br = value
		if Engine.is_editor_hint():
			call_deferred("_regenerate")

## Offset for bottom-left corner. Set by procedural map generator based on grid position + noise.
@export var corner_offset_bl: Vector2 = Vector2.ZERO:
	set(value):
		corner_offset_bl = value
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


## Generates the floor tile mesh with rounded corners using clean extrusion.
func _generate_floor_tile(mesh_node: MeshInstance3D) -> void:
	var surface_tool := SurfaceTool.new()
	surface_tool.begin(Mesh.PRIMITIVE_TRIANGLES)
	
	# Calculate dimensions
	var y_bottom := 0.0
	var y_top := tile_height
	
	# Generate perimeter points of the rounded rectangle
	var perimeter := _generate_rounded_rect_perimeter()
	
	# Triangulate top face
	_triangulate_rounded_rect(surface_tool, perimeter, y_top, false)
	
	# Triangulate bottom face (reversed winding)
	_triangulate_rounded_rect(surface_tool, perimeter, y_bottom, true)
	
	# Generate side walls by connecting perimeter points
	for i in range(perimeter.size()):
		var p1 := perimeter[i]
		var p2 := perimeter[(i + 1) % perimeter.size()]
		
		var p1_top := Vector3(p1.x, y_top, p1.y)
		var p2_top := Vector3(p2.x, y_top, p2.y)
		var p1_btm := Vector3(p1.x, y_bottom, p1.y)
		var p2_btm := Vector3(p2.x, y_bottom, p2.y)
		
		# Add quad as 2 triangles (outward facing)
		surface_tool.add_vertex(p1_top)
		surface_tool.add_vertex(p2_top)
		surface_tool.add_vertex(p1_btm)
		
		surface_tool.add_vertex(p1_btm)
		surface_tool.add_vertex(p2_top)
		surface_tool.add_vertex(p2_btm)
	
	# Generate normals and commit
	surface_tool.generate_normals()
	var array_mesh := surface_tool.commit()
	mesh_node.mesh = array_mesh


## Generates the perimeter vertices of a rounded rectangle (clockwise).
func _generate_rounded_rect_perimeter() -> Array[Vector2]:
	var perimeter: Array[Vector2] = []
	var half_size := tile_size * 0.5
	var inset := corner_radius
	
	# Corner centers (with displacement applied)
	var tl_center := Vector2(-half_size + inset, -half_size + inset) + corner_offset_tl  # Top-left
	var tr_center := Vector2(half_size - inset, -half_size + inset) + corner_offset_tr   # Top-right
	var br_center := Vector2(half_size - inset, half_size - inset) + corner_offset_br    # Bottom-right
	var bl_center := Vector2(-half_size + inset, half_size - inset) + corner_offset_bl   # Bottom-left
	
	var angle_step := (PI * 0.5) / corner_segments
	
	# Trace perimeter clockwise starting from top-left corner end
	# Top edge (left to right) - connect from top-left corner to top-right corner
	perimeter.append(tl_center + Vector2(0, -corner_radius))  # End of top-left arc
	perimeter.append(tr_center + Vector2(0, -corner_radius))  # Start of top-right arc
	
	# Top-right corner arc (start angle: -PI/2, end angle: 0)
	for i in range(1, corner_segments + 1):
		var angle := -PI * 0.5 + (i * angle_step)
		var point := tr_center + Vector2(cos(angle), sin(angle)) * corner_radius
		perimeter.append(point)
	
	# Right edge (top to bottom)
	perimeter.append(br_center + Vector2(corner_radius, 0))  # Start of bottom-right arc
	
	# Bottom-right corner arc (start angle: 0, end angle: PI/2)
	for i in range(1, corner_segments + 1):
		var angle := 0.0 + (i * angle_step)
		var point := br_center + Vector2(cos(angle), sin(angle)) * corner_radius
		perimeter.append(point)
	
	# Bottom edge (right to left)
	perimeter.append(bl_center + Vector2(0, corner_radius))  # Start of bottom-left arc
	
	# Bottom-left corner arc (start angle: PI/2, end angle: PI)
	for i in range(1, corner_segments + 1):
		var angle := PI * 0.5 + (i * angle_step)
		var point := bl_center + Vector2(cos(angle), sin(angle)) * corner_radius
		perimeter.append(point)
	
	# Left edge (bottom to top)
	perimeter.append(tl_center + Vector2(-corner_radius, 0))  # Start of top-left arc
	
	# Top-left corner arc (start angle: PI, end angle: 3*PI/2)
	for i in range(1, corner_segments + 1):
		var angle := PI + (i * angle_step)
		var point := tl_center + Vector2(cos(angle), sin(angle)) * corner_radius
		perimeter.append(point)
	
	return perimeter


## Triangulates a rounded rectangle face using fan triangulation from center.
func _triangulate_rounded_rect(surface_tool: SurfaceTool, perimeter: Array[Vector2], y_level: float, reverse_winding: bool) -> void:
	# Calculate center point
	var center := Vector2.ZERO
	
	# Use fan triangulation from center
	var center_3d := Vector3(center.x, y_level, center.y)
	
	for i in range(perimeter.size()):
		var p1 := perimeter[i]
		var p2 := perimeter[(i + 1) % perimeter.size()]
		
		var p1_3d := Vector3(p1.x, y_level, p1.y)
		var p2_3d := Vector3(p2.x, y_level, p2.y)
		
		if reverse_winding:
			# Reverse winding for bottom face (facing down)
			surface_tool.add_vertex(center_3d)
			surface_tool.add_vertex(p1_3d)
			surface_tool.add_vertex(p2_3d)
		else:
			# Normal winding for top face (facing up, perimeter is clockwise so reverse)
			surface_tool.add_vertex(center_3d)
			surface_tool.add_vertex(p2_3d)
			surface_tool.add_vertex(p1_3d)


## Generates collision shape from mesh.
func _generate_collision(mesh_node: MeshInstance3D, collision_node: CollisionShape3D) -> void:
	if not mesh_node.mesh:
		return
	
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(mesh_node.mesh.get_faces())
	collision_node.shape = shape
