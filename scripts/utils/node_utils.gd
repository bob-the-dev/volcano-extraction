class_name NodeUtils
extends RefCounted

## Utility class for finding nodes in the scene tree using multiple fallback strategies.
## Provides static helper functions to locate nodes when their exact location is uncertain.


## Finds a node using multiple strategies with automatic fallback.
## 
## Tries methods in order:
## 1. Group lookup (fastest, recommended approach)
## 2. Relative paths (e.g., "../NodeName", "../../NodeName")
## 3. Script path matching (searches parent's children)
## 
## @param from_node: The node to search from (usually 'self')
## @param group: Optional group name to search first
## @param paths: Optional array of relative paths to try
## @param script_contains: Optional script path substring to match
## @param debug: If true, prints which method succeeded
## @return: Found node or null
static func find_node(
	from_node: Node,
	group: String = "",
	paths: Array[String] = [],
	script_contains: String = "",
	debug: bool = false
) -> Node:
	var found_node: Node = null
	
	# Method 1: Try group lookup (fastest and most flexible)
	if group != "":
		found_node = from_node.get_tree().get_first_node_in_group(group)
		if found_node:
			if debug:
				print("[NodeUtils] Found '", found_node.name, "' via group '", group, "'")
			return found_node
	
	# Method 2: Try relative paths (sibling, parent's children, etc.)
	for path in paths:
		found_node = from_node.get_node_or_null(path)
		if found_node:
			if debug:
				print("[NodeUtils] Found '", found_node.name, "' via path '", path, "'")
			return found_node
	
	# Method 3: Search parent's children by script path
	if script_contains != "":
		var parent := from_node.get_parent()
		if parent:
			for child in parent.get_children():
				if child.get_script() and child.get_script().resource_path.contains(script_contains):
					found_node = child
					if debug:
						print("[NodeUtils] Found '", found_node.name, "' via script containing '", script_contains, "'")
					return found_node
	
	# Nothing found
	if debug:
		push_warning("[NodeUtils] Could not find node (group: '", group, "', paths: ", paths, ", script: '", script_contains, "')")
	
	return null


## Simplified version for the common case of group + path fallbacks.
## 
## @param from_node: The node to search from (usually 'self')
## @param group: Group name to search first
## @param fallback_paths: Array of relative paths to try if group fails
## @return: Found node or null
static func find(from_node: Node, group: String, fallback_paths: Array[String]) -> Node:
	return find_node(from_node, group, fallback_paths)


## Finds multiple nodes in a group.
## 
## @param from_node: The node to search from (usually 'self')
## @param group: Group name to search
## @return: Array of nodes in the group (empty if none found)
static func find_all_in_group(from_node: Node, group: String) -> Array[Node]:
	var nodes: Array[Node] = []
	var found := from_node.get_tree().get_nodes_in_group(group)
	for node in found:
		if node is Node:
			nodes.append(node)
	return nodes
