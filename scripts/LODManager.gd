extends Node

# Predefined distance thresholds for LOD levels.
# These can be configured via Project Settings or a config file.
# Level 0: High detail (closest)
# Level 1: Medium detail
# Level 2: Low detail (farthest)
var base_lod_distances: Array[float] = [500.0, 1500.0, 3000.0] # Default distances
var current_lod_distances: Array[float] = [] # Effective distances after quality adjustment

const MAX_LOD_LEVEL_NODES: int = 2 # Max index for LOD nodes (LOD0, LOD1, LOD2)

var camera_node: Camera2D = null
var managed_objects: Array = [] # Array of Dictionaries: {"node": Node2D, "lod_children": [Node2D, Node2D, Node2D], "current_lod": -1}
var current_lod_quality_level: AdaptiveQualityManager.Quality = AdaptiveQualityManager.Quality.MEDIUM

@onready var config_manager = get_node_or_null("/root/ConfigManager")

# It's assumed LODManager is an AutoLoad singleton.

func _ready():
	print("LODManager Initialized.")
	
	if config_manager and config_manager.config:
		base_lod_distances = config_manager.get_setting("general", "lod_base_distances", [500.0, 1500.0, 3000.0])
		var initial_quality_str = config_manager.get_setting("general", "adaptive_quality_initial_level", "MEDIUM")
		match initial_quality_str.to_upper():
			"LOW": current_lod_quality_level = AdaptiveQualityManager.Quality.LOW
			"HIGH": current_lod_quality_level = AdaptiveQualityManager.Quality.HIGH
			_: current_lod_quality_level = AdaptiveQualityManager.Quality.MEDIUM
	else:
		# Fallback if config_manager is not ready or doesn't have the settings
		current_lod_quality_level = AdaptiveQualityManager.Quality.MEDIUM
		
	# Initialize current_lod_distances based on initial quality
	_apply_lod_distance_multipliers(current_lod_quality_level)
	print("LODManager: Initial LOD quality level: %s, distances: %s" % [AdaptiveQualityManager.Quality.keys()[current_lod_quality_level], current_lod_distances])

	# Attempt to get camera if not set by main scene quickly
	if not is_instance_valid(camera_node):
		camera_node = get_viewport().get_camera_2d()
		if not is_instance_valid(camera_node):
			print_rich("[color=yellow]LODManager: Main camera not found on ready. Call update_camera_node() from your main scene or camera script.[/color]")
	# Ensure LOD_DISTANCES is sorted if it can be configured dynamically
	# LOD_DISTANCES.sort()

func update_camera_node(new_camera: Camera2D):
	if is_instance_valid(new_camera):
		camera_node = new_camera
		print("LODManager: Camera node updated.")
	else:
		push_warning("LODManager: Attempted to set an invalid camera node.")

func register_object(object_node: Node2D):
	if not is_instance_valid(object_node):
		push_warning("LODManager: Attempted to register an invalid object.")
		return

	var lod0 = object_node.get_node_or_null("LOD0") as Node2D
	var lod1 = object_node.get_node_or_null("LOD1") as Node2D
	var lod2 = object_node.get_node_or_null("LOD2") as Node2D

	if not is_instance_valid(lod0): # LOD0 is mandatory
		push_warning("LODManager: Object %s does not have a LOD0 child. Cannot register for LOD." % object_node.name)
		return

	# Ensure all LOD nodes start in a consistent state (LOD0 visible, others not)
	lod0.visible = true
	if is_instance_valid(lod1): lod1.visible = false
	if is_instance_valid(lod2): lod2.visible = false
	
	managed_objects.append({
		"node": object_node,
		"lod_children": [lod0, lod1, lod2], # Store even if null, for consistent indexing
		"current_lod": 0 # Start with LOD0 active
	})
	# print_debug("LODManager: Registered object %s" % object_node.name)


func update_lods():
	if not is_instance_valid(camera_node):
		# Try to get it again if it wasn't set
		if get_viewport():
			camera_node = get_viewport().get_camera_2d()
		if not is_instance_valid(camera_node):
			return # Still no camera, can't update LODs

	var camera_pos: Vector2 = camera_node.global_position

	for obj_data in managed_objects:
		var object_node: Node2D = obj_data.node
		if not is_instance_valid(object_node): # Object might have been freed
			# Consider removing from managed_objects here if that's a frequent case
			continue

		var distance_to_camera = camera_pos.distance_to(object_node.global_position)
		var target_lod_level = get_lod_level_for_distance(distance_to_camera)
		
		# Clamp target_lod_level to the max index of available LOD children (0, 1, 2)
		target_lod_level = min(target_lod_level, MAX_LOD_LEVEL_NODES)

		if obj_data.current_lod != target_lod_level:
			obj_data.current_lod = target_lod_level
			for i in range(obj_data.lod_children.size()):
				var lod_child: Node2D = obj_data.lod_children[i]
				if is_instance_valid(lod_child):
					lod_child.visible = (i == target_lod_level)
			# print_debug("LODManager: Object %s switched to LOD%s" % [object_node.name, target_lod_level])


func set_quality_level(new_level: AdaptiveQualityManager.Quality):
	if new_level == current_lod_quality_level:
		return
	
	current_lod_quality_level = new_level
	_apply_lod_distance_multipliers(new_level)
	print_rich("[color=olive]LODManager: LOD quality level set to %s. Effective distances: %s[/color]" % [AdaptiveQualityManager.Quality.keys()[new_level], current_lod_distances])
	
	# Force an update of all managed objects' LODs based on new distances
	# This is important because existing objects might now fall into different LOD brackets
	if is_instance_valid(camera_node): # Only if camera is known
		var camera_pos: Vector2 = camera_node.global_position
		for obj_data in managed_objects:
			var object_node: Node2D = obj_data.node
			if not is_instance_valid(object_node):
				continue
			
			var distance_to_camera = camera_pos.distance_to(object_node.global_position)
			var target_lod_level = get_lod_level_for_distance(distance_to_camera) # Uses new current_lod_distances
			target_lod_level = min(target_lod_level, MAX_LOD_LEVEL_NODES)

			# No need to check obj_data.current_lod != target_lod_level, force re-evaluation
			obj_data.current_lod = target_lod_level
			for i in range(obj_data.lod_children.size()):
				var lod_child: Node2D = obj_data.lod_children[i]
				if is_instance_valid(lod_child):
					lod_child.visible = (i == target_lod_level)


func _apply_lod_distance_multipliers(level: AdaptiveQualityManager.Quality):
	var multiplier = 1.0
	if config_manager and config_manager.config:
		match level:
			AdaptiveQualityManager.Quality.LOW:
				multiplier = config_manager.get_setting("general", "lod_distance_multiplier_low", 0.75)
			AdaptiveQualityManager.Quality.MEDIUM:
				multiplier = config_manager.get_setting("general", "lod_distance_multiplier_medium", 1.0)
			AdaptiveQualityManager.Quality.HIGH:
				multiplier = config_manager.get_setting("general", "lod_distance_multiplier_high", 1.25)
	
	current_lod_distances = []
	for dist in base_lod_distances:
		current_lod_distances.append(dist * multiplier)
	# Ensure distances are sorted, especially if multipliers could invert order (unlikely here)
	current_lod_distances.sort()


func get_lod_level_for_distance(distance: float) -> int:
	"""
	Determines the LOD level based on the distance to the camera.
	Returns an integer representing the LOD level (0 for highest detail).
	Uses current_lod_distances.
	"""
	if current_lod_distances.is_empty():
		push_warning("LODManager: current_lod_distances is empty. Defaulting to LOD 0.")
		return 0

	for i in range(current_lod_distances.size()):
		if distance < current_lod_distances[i]:
			return i # LOD level corresponds to the index of the first threshold met

	# If distance is greater than all thresholds, return the lowest detail level index + 1
	return current_lod_distances.size()


# Example of how it might be used (not called automatically yet by this script)
func _process(_delta):
	update_lods() # For objects registered directly with LODManager
