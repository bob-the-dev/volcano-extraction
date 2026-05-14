# Fog Of War Volumetric Reference

This file keeps the previous FogVolume-based fog-of-war implementation after the project switched to a blur-mask post-process.

## Previous exports

```gdscript
@export_group("Fog Of War")
## Covers the generated map with local volumetric fog that is gradually carved away by exploration.
@export var enable_fog_of_war: bool = true
## Density applied to the full-map fog volume. Higher values hide more of the map.
@export var fog_of_war_cover_density: float = 0.7
## Negative density used by reveal volumes to subtract the cover fog.
@export var fog_of_war_reveal_density: float = -0.9
## Number of cells around the player to reveal when entering a new grid cell.
@export_range(0, 6, 1) var fog_of_war_reveal_radius_cells: int = 2
## Extra width applied to each reveal cell so nearby walls and edges become readable.
@export_range(1.0, 3.0, 0.05) var fog_of_war_reveal_size_multiplier: float = 1.45
## Softness applied to both the cover volume and reveal volume edges.
@export_range(0.0, 1.0, 0.01) var fog_of_war_edge_fade: float = 0.25
## Bottom padding added under the lowest terrain height covered by fog.
@export_range(0.0, 5.0, 0.05) var fog_of_war_bottom_padding: float = 0.75
## Top padding added above the highest terrain height covered by fog.
@export_range(0.0, 8.0, 0.05) var fog_of_war_top_padding: float = 3.5
## Albedo tint used by the cover fog volumes.
@export var fog_of_war_cover_color: Color = Color(0.2, 0.22, 0.24, 1.0)
## Optional emissive tint to stop dense fog-of-war from going fully black.
@export var fog_of_war_cover_emission: Color = Color(0.02, 0.02, 0.02, 1.0)
```

## Previous runtime state

```gdscript
var _fog_of_war_cover_volume: FogVolume
var _fog_of_war_cover_material: FogMaterial
var _fog_of_war_reveal_material: FogMaterial
var _fog_of_war_reveal_volumes: Dictionary = {}
var _fog_of_war_revealed_cells: Dictionary = {}
var _fog_of_war_player: Node3D = null
var _fog_of_war_last_player_grid_key: String = ""
var _fog_of_war_volume_center_y: float = 0.0
var _fog_of_war_volume_height: float = 0.0
```

## Previous FogVolume logic

```gdscript
func _setup_fog_of_war() -> void:
	_fog_of_war_cover_volume = null
	_fog_of_war_cover_material = null
	_fog_of_war_reveal_material = null
	_fog_of_war_reveal_volumes.clear()
	_fog_of_war_revealed_cells.clear()
	_fog_of_war_last_player_grid_key = ""
	_fog_of_war_player = null
	_fog_of_war_volume_center_y = 0.0
	_fog_of_war_volume_height = 0.0

	if not enable_fog_of_war or _cells.is_empty():
		return

	var fog_bounds: Dictionary = _get_fog_of_war_bounds()
	if fog_bounds.is_empty():
		push_warning("[FogOfWar] Could not determine fog bounds for generated map")
		return

	_fog_of_war_cover_material = FogMaterial.new()
	_fog_of_war_cover_material.albedo = fog_of_war_cover_color
	_fog_of_war_cover_material.emission = fog_of_war_cover_emission
	_fog_of_war_cover_material.density = fog_of_war_cover_density
	_fog_of_war_cover_material.edge_fade = fog_of_war_edge_fade

	_fog_of_war_reveal_material = FogMaterial.new()
	_fog_of_war_reveal_material.albedo = fog_of_war_cover_color
	_fog_of_war_reveal_material.emission = Color(0.0, 0.0, 0.0, 1.0)
	_fog_of_war_reveal_material.density = fog_of_war_reveal_density
	_fog_of_war_reveal_material.edge_fade = fog_of_war_edge_fade

	_fog_of_war_volume_center_y = fog_bounds.get("center_y", 0.0)
	_fog_of_war_volume_height = fog_bounds.get("height", 0.0)

	var cover_volume: FogVolume = FogVolume.new()
	cover_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	cover_volume.material = _fog_of_war_cover_material
	cover_volume.size = fog_bounds.get("size", Vector3.ZERO)
	cover_volume.position = fog_bounds.get("center", Vector3.ZERO)
	add_child(cover_volume)
	_spawned_objects.append(cover_volume)
	_fog_of_war_cover_volume = cover_volume

	_fog_of_war_player = NodeUtils.find(self, "player", ["../Player"])
	if _fog_of_war_player == null:
		push_warning("[FogOfWar] Player not found. Exploration reveals will not update.")
		return

	_update_fog_of_war_visibility(true)


func _update_fog_of_war_visibility(force_reveal: bool = false) -> void:
	if not enable_fog_of_war or _cells.is_empty() or _fog_of_war_cover_volume == null:
		return

	if _fog_of_war_player == null or not is_instance_valid(_fog_of_war_player):
		_fog_of_war_player = NodeUtils.find(self, "player", ["../Player"])
		if _fog_of_war_player == null:
			return

	var player_grid: Vector2 = _world_to_grid(Vector2(_fog_of_war_player.global_position.x, _fog_of_war_player.global_position.z))
	var player_grid_pos: Vector2i = Vector2i(int(player_grid.x), int(player_grid.y))
	var player_grid_key: String = _grid_position_key(player_grid_pos)
	if not force_reveal and player_grid_key == _fog_of_war_last_player_grid_key:
		return

	_fog_of_war_last_player_grid_key = player_grid_key
	_reveal_fog_of_war_cells(player_grid_pos)


func _reveal_fog_of_war_cells(center_grid_pos: Vector2i) -> void:
	for x_offset in range(-fog_of_war_reveal_radius_cells, fog_of_war_reveal_radius_cells + 1):
		for y_offset in range(-fog_of_war_reveal_radius_cells, fog_of_war_reveal_radius_cells + 1):
			var offset: Vector2 = Vector2(float(x_offset), float(y_offset))
			if offset.length() > float(fog_of_war_reveal_radius_cells) + 0.35:
				continue

			var grid_pos: Vector2i = Vector2i(center_grid_pos.x + x_offset, center_grid_pos.y + y_offset)
			_reveal_fog_of_war_cell(grid_pos)


func _reveal_fog_of_war_cell(grid_pos: Vector2i) -> void:
	var cell: Cell = _get_cell_at(Vector2(float(grid_pos.x), float(grid_pos.y)))
	if cell == null or not cell.filled:
		return

	var grid_key: String = _grid_position_key(grid_pos)
	if _fog_of_war_revealed_cells.has(grid_key):
		return

	var reveal_volume: FogVolume = FogVolume.new()
	reveal_volume.shape = RenderingServer.FOG_VOLUME_SHAPE_BOX
	reveal_volume.material = _fog_of_war_reveal_material
	reveal_volume.size = Vector3(
		cell_size * fog_of_war_reveal_size_multiplier,
		_fog_of_war_volume_height,
		cell_size * fog_of_war_reveal_size_multiplier
	)

	var world_pos: Vector3 = _cell_to_world(cell.position)
	reveal_volume.position = Vector3(world_pos.x, _fog_of_war_volume_center_y, world_pos.z)
	add_child(reveal_volume)
	_spawned_objects.append(reveal_volume)

	_fog_of_war_reveal_volumes[grid_key] = reveal_volume
	_fog_of_war_revealed_cells[grid_key] = true


func _get_fog_of_war_bounds() -> Dictionary:
	if _cells.is_empty():
		return {}

	var half_cell: float = cell_size * 0.5
	var min_x: float = INF
	var max_x: float = -INF
	var min_z: float = INF
	var max_z: float = -INF

	for cell in _cells:
		if not cell.filled:
			continue

		var world_pos: Vector3 = _cell_to_world(cell.position)
		min_x = minf(min_x, world_pos.x - half_cell)
		max_x = maxf(max_x, world_pos.x + half_cell)
		min_z = minf(min_z, world_pos.z - half_cell)
		max_z = maxf(max_z, world_pos.z + half_cell)

	if min_x == INF or min_z == INF:
		return {}

	var min_y: float = _get_depth_level_world_height(4.0) - fog_of_war_bottom_padding
	var max_y: float = _get_depth_level_world_height(0.0) + fog_of_war_top_padding
	var size_x: float = max_x - min_x
	var size_z: float = max_z - min_z
	var size_y: float = maxf(max_y - min_y, 0.1)
	var center: Vector3 = Vector3(
		(min_x + max_x) * 0.5,
		(min_y + max_y) * 0.5,
		(min_z + max_z) * 0.5
	)

	return {
		"center": center,
		"size": Vector3(size_x, size_y, size_z),
		"center_y": center.y,
		"height": size_y
	}
```
