class_name ColorCombinationPicker
extends RefCounted

const COLORS_JSON_PATH: String = "res://colors.json"

static var _is_loaded: bool = false
static var _colors: Array[Dictionary] = []
static var _combination_ids: Array[int] = []


static func get_colors_for_combination(combination_id: int) -> Array[Dictionary]:
	if not _ensure_loaded():
		return []

	var matching_colors: Array[Dictionary] = []
	for color_entry in _colors:
		var combination_values: Variant = color_entry.get("combinations", [])
		if not combination_values is Array:
			continue
		for combination_value in combination_values:
			if int(combination_value) == combination_id:
				matching_colors.append(color_entry)
				break
	return matching_colors


static func get_combination_ids_for_color(color_identifier: Variant) -> Array[int]:
	if not _ensure_loaded():
		return []

	var color_entry: Dictionary = _find_color_entry(color_identifier)
	if color_entry.is_empty():
		return []

	var combination_ids: Array[int] = []
	var combination_values: Variant = color_entry.get("combinations", [])
	if not combination_values is Array:
		return combination_ids

	for combination_value in combination_values:
		combination_ids.append(int(combination_value))
	return combination_ids


static func get_random_combination() -> Dictionary:
	if not _ensure_loaded():
		return {}

	var combination_id: int = get_random_combination_id()
	if combination_id < 0:
		return {}

	return {
		"combination_id": combination_id,
		"colors": get_colors_for_combination(combination_id)
	}


static func get_random_combination_for_color(color_identifier: Variant) -> Dictionary:
	if not _ensure_loaded():
		return {}

	var available_ids: Array[int] = get_combination_ids_for_color(color_identifier)
	if available_ids.is_empty():
		return {}

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var selection_index: int = rng.randi_range(0, available_ids.size() - 1)
	var combination_id: int = available_ids[selection_index]
	return {
		"combination_id": combination_id,
		"colors": get_colors_for_combination(combination_id)
	}


static func get_random_combination_id() -> int:
	if not _ensure_loaded() or _combination_ids.is_empty():
		return -1

	var rng: RandomNumberGenerator = RandomNumberGenerator.new()
	rng.randomize()
	var selection_index: int = rng.randi_range(0, _combination_ids.size() - 1)
	return _combination_ids[selection_index]


static func get_max_combination_id() -> int:
	if not _ensure_loaded() or _combination_ids.is_empty():
		return -1
	return _combination_ids[_combination_ids.size() - 1]


static func get_color(color_entry: Dictionary) -> Color:
	var color_hex: String = str(color_entry.get("hex", "#000000"))
	return Color.from_string(color_hex, Color.BLACK)


static func get_color_luminance(color_entry: Dictionary) -> float:
	var color_value: Color = get_color(color_entry)
	return (color_value.r * 0.2126) + (color_value.g * 0.7152) + (color_value.b * 0.0722)


static func sort_colors_by_luminance(color_entries: Array[Dictionary]) -> Array[Dictionary]:
	var sorted_entries: Array[Dictionary] = []
	for color_entry in color_entries:
		var inserted: bool = false
		var entry_luminance: float = get_color_luminance(color_entry)
		for insert_index in range(sorted_entries.size()):
			var existing_luminance: float = get_color_luminance(sorted_entries[insert_index])
			if entry_luminance < existing_luminance:
				sorted_entries.insert(insert_index, color_entry)
				inserted = true
				break
		if not inserted:
			sorted_entries.append(color_entry)
	return sorted_entries


static func _ensure_loaded() -> bool:
	if _is_loaded:
		return true

	var file: FileAccess = FileAccess.open(COLORS_JSON_PATH, FileAccess.READ)
	if file == null:
		push_error("ColorCombinationPicker: Could not open %s" % COLORS_JSON_PATH)
		return false

	var file_text: String = file.get_as_text()
	var parsed_value: Variant = JSON.parse_string(file_text)
	if not parsed_value is Dictionary:
		push_error("ColorCombinationPicker: colors.json root is not a dictionary.")
		return false

	var parsed_dictionary: Dictionary = parsed_value
	var color_values: Variant = parsed_dictionary.get("colors", [])
	if not color_values is Array:
		push_error("ColorCombinationPicker: colors.json does not contain a valid colors array.")
		return false

	_colors.clear()
	_combination_ids.clear()
	for color_value in color_values:
		if not color_value is Dictionary:
			continue

		var color_entry: Dictionary = color_value
		_colors.append(color_entry)

		var combination_values: Variant = color_entry.get("combinations", [])
		if not combination_values is Array:
			continue

		for combination_value in combination_values:
			var combination_id: int = int(combination_value)
			if not _combination_ids.has(combination_id):
				_combination_ids.append(combination_id)

	_combination_ids.sort()
	_is_loaded = true
	return true


static func _find_color_entry(color_identifier: Variant) -> Dictionary:
	if not _ensure_loaded():
		return {}

	if color_identifier is Dictionary:
		return color_identifier

	if color_identifier is int:
		for color_entry in _colors:
			if int(color_entry.get("index", -1)) == int(color_identifier):
				return color_entry
		return {}

	var identifier_text: String = str(color_identifier).strip_edges().to_lower()
	if identifier_text.is_empty():
		return {}

	for color_entry in _colors:
		var entry_name: String = str(color_entry.get("name", "")).to_lower()
		var entry_slug: String = str(color_entry.get("slug", "")).to_lower()
		var entry_hex: String = str(color_entry.get("hex", "")).to_lower()
		if identifier_text == entry_name or identifier_text == entry_slug or identifier_text == entry_hex:
			return color_entry

	return {}