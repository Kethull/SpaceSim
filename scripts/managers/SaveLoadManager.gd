extends Node
class_name SaveLoadManager

const ProbeDataRes = preload("res://scripts/data/ProbeData.gd")
const CelestialBodyDataRes = preload("res://scripts/data/CelestialBodyData.gd")
# SimulationSaveData and ResourceData should be findable by class_name if scripts are correct

signal save_started()
signal save_completed(file_path: String)
signal save_failed(error_code: int, file_path: String) # Using Godot's Error enum

signal load_started(file_path: String)
signal load_completed(file_path: String)
signal load_failed(error_code: int, file_path: String) # Using Godot's Error enum

signal autosave_initiated(file_path: String)
signal autosave_completed(file_path: String)
signal autosave_failed(error_code: int, file_path: String)

const SAVE_DIR := "user://saves/"
const SAVE_FILE_EXTENSION := ".tres"
const AUTOSAVE_PREFIX := "autosave_"
const QUICK_SAVE_FILENAME := "quicksave" + SAVE_FILE_EXTENSION
const SAVE_VERSION := "1.0"

@export var autosave_interval: float = 300.0 # Seconds (5 minutes)
@export var max_autosaves: int = 5

var simulation_manager # SimulationManager
var camera_2d # Camera2D
# var ui_manager # Reference to your main UI manager if it holds state like selected probe

var autosave_timer: Timer

func _ready():
	if not DirAccess.dir_exists_absolute(SAVE_DIR):
		var err = DirAccess.make_dir_recursive_absolute(SAVE_DIR)
		if err != OK:
			printerr("SaveLoadManager: Failed to create save directory: ", SAVE_DIR, " Error: ", err)
			# Potentially disable save/load functionality or notify user

	autosave_timer = Timer.new()
	autosave_timer.wait_time = autosave_interval
	autosave_timer.one_shot = false # Keep repeating
	autosave_timer.autostart = true
	autosave_timer.timeout.connect(autosave)
	add_child(autosave_timer)
	
	# It's good practice to get node references here if they are static in the scene tree
	# For dynamically spawned things or singletons, you might get them on-demand.
	# Assuming SimulationManager is an autoload or easily accessible
	# simulation_manager = get_node("/root/SimulationManager") # Adjust path as needed
	# camera_2d = get_viewport().get_camera_2d() # Or however you access your main camera

#region Public API
func save_simulation(file_name_override: String = ""):
	emit_signal("save_started")
	var file_name: String
	if file_name_override.is_empty():
		file_name = "savegame_" + Time.get_datetime_string_from_system(false, true).replace(":", "-") + SAVE_FILE_EXTENSION
	else:
		if not file_name_override.ends_with(SAVE_FILE_EXTENSION):
			file_name = file_name_override + SAVE_FILE_EXTENSION
		else:
			file_name = file_name_override
			
	var file_path = SAVE_DIR.path_join(file_name)
	
	var save_data = create_save_data()
	if not save_data:
		printerr("SaveLoadManager: Failed to create save data object.")
		emit_signal("save_failed", ERR_CANT_CREATE, file_path)
		return

	var error = ResourceSaver.save(save_data, file_path)
	if error == OK:
		print("SaveLoadManager: Simulation saved successfully to ", file_path)
		emit_signal("save_completed", file_path)
		if file_name.begins_with(AUTOSAVE_PREFIX):
			cleanup_old_autosaves()
	else:
		printerr("SaveLoadManager: Error saving simulation to ", file_path, ". Error code: ", error)
		emit_signal("save_failed", error, file_path)

func load_simulation(file_path: String):
	emit_signal("load_started", file_path)
	if not FileAccess.file_exists(file_path):
		printerr("SaveLoadManager: File not found: ", file_path)
		emit_signal("load_failed", ERR_FILE_NOT_FOUND, file_path)
		return

	var loaded_resource = ResourceLoader.load(file_path, "SimulationSaveData", ResourceLoader.CACHE_MODE_IGNORE)
	if loaded_resource == null or not loaded_resource is SimulationSaveData:
		printerr("SaveLoadManager: Failed to load or incorrect resource type from ", file_path)
		emit_signal("load_failed", ERR_CANT_OPEN, file_path) # Or a more specific error
		return

	var save_data: SimulationSaveData = loaded_resource as SimulationSaveData

	# Basic version check
	if save_data.save_version != SAVE_VERSION:
		push_warning("SaveLoadManager: Loading save file with different version. Current: %s, File: %s. Potential compatibility issues." % [SAVE_VERSION, save_data.save_version])
		# For more advanced handling, you'd have migration logic here.

	var success = apply_save_data(save_data)
	if success:
		print("SaveLoadManager: Simulation loaded successfully from ", file_path)
		emit_signal("load_completed", file_path)
	else:
		printerr("SaveLoadManager: Failed to apply save data from ", file_path)
		# This error is more about internal logic failing, might need a custom error or use a general one.
		emit_signal("load_failed", ERR_PARSE_ERROR, file_path) # Placeholder for "failed to apply"

func quick_save():
	save_simulation(QUICK_SAVE_FILENAME)

func quick_load():
	var q_path = SAVE_DIR.path_join(QUICK_SAVE_FILENAME)
	if FileAccess.file_exists(q_path):
		load_simulation(q_path)
	else:
		print("SaveLoadManager: Quick save file not found: ", q_path)
		emit_signal("load_failed", ERR_FILE_NOT_FOUND, q_path)

func get_save_files() -> Array[Dictionary]:
	var save_files_info: Array[Dictionary] = []
	var dir = DirAccess.open(SAVE_DIR)
	if dir:
		dir.list_dir_begin()
		var file_name = dir.get_next()
		while file_name != "":
			if not dir.current_is_dir() and file_name.ends_with(SAVE_FILE_EXTENSION):
				var full_path = SAVE_DIR.path_join(file_name)
				var loaded_sdata_res = ResourceLoader.load(full_path, "SimulationSaveData", ResourceLoader.CACHE_MODE_IGNORE)
				var save_resource: SimulationSaveData = null
				if loaded_sdata_res is SimulationSaveData:
					save_resource = loaded_sdata_res
				
				var file_mod_time = FileAccess.get_modified_time(full_path) if FileAccess.file_exists(full_path) else 0
				var display_timestamp = file_mod_time
				var save_game_name = "Unknown Save (%s)" % file_name # Default name
				var episode = 0
				var step = 0
				var version_str = "N/A"

				if save_resource:
					save_game_name = save_resource.save_name if not save_resource.save_name.is_empty() else file_name
					# Prioritize timestamp from save data if it's valid (float and > 0)
					if save_resource.save_timestamp is float and save_resource.save_timestamp > 0.0:
						display_timestamp = int(save_resource.save_timestamp) # Convert float to int for consistency if needed by UI
					episode = save_resource.current_episode
					step = save_resource.current_step
					version_str = save_resource.save_version
				
				save_files_info.append({
					"file_name": file_name,
					"path": full_path,
					"timestamp_raw": display_timestamp, # For sorting
					"timestamp_readable": Time.get_datetime_string_from_unix_time(display_timestamp),
					"save_game_name": save_game_name,
					"episode": episode,
					"step": step,
					"version": version_str
				})
			file_name = dir.get_next()
		dir.list_dir_end()
		# Sort by timestamp, newest first
		save_files_info.sort_custom(func(a, b): return a.timestamp_raw > b.timestamp_raw)
	else:
		printerr("SaveLoadManager: Could not open save directory: ", SAVE_DIR)
	return save_files_info

func delete_save_file(file_path: String) -> bool:
	if not file_path.begins_with(SAVE_DIR) or not file_path.ends_with(SAVE_FILE_EXTENSION):
		printerr("SaveLoadManager: Invalid file path for deletion: ", file_path)
		return false
	
	var dir = DirAccess.open(SAVE_DIR) # Need to use DirAccess for user:// deletions
	if dir:
		var err = dir.remove(file_path.get_file()) # remove expects just the filename within the dir
		if err == OK:
			print("SaveLoadManager: Deleted save file: ", file_path)
			return true
		else:
			printerr("SaveLoadManager: Failed to delete save file: ", file_path, " Error: ", err)
			return false
	printerr("SaveLoadManager: Could not open save directory for deletion: ", SAVE_DIR)
	return false

#endregion

#region Autosave
func autosave():
	if simulation_manager and simulation_manager.is_simulation_running(): # Only autosave if sim is running
		print("SaveLoadManager: Initiating autosave...")
		var autosave_file_name = AUTOSAVE_PREFIX + Time.get_datetime_string_from_system(false, true).replace(":", "-") + SAVE_FILE_EXTENSION
		emit_signal("autosave_initiated", SAVE_DIR.path_join(autosave_file_name))
		# Temporarily disconnect to avoid signal loop if save_simulation emits autosave_completed
		if save_completed.is_connected(on_autosave_operation_completed):
			save_completed.disconnect(on_autosave_operation_completed)
		if save_failed.is_connected(on_autosave_operation_failed):
			save_failed.disconnect(on_autosave_operation_failed)
			
		save_completed.connect(on_autosave_operation_completed)
		save_failed.connect(on_autosave_operation_failed)
		
		save_simulation(autosave_file_name)
	else:
		print("SaveLoadManager: Autosave skipped (simulation not running or manager not found).")

func on_autosave_operation_completed(file_path: String):
	if file_path.get_file().begins_with(AUTOSAVE_PREFIX):
		emit_signal("autosave_completed", file_path)
		cleanup_old_autosaves()
	# Disconnect to avoid multiple calls if a manual save happens right after
	if save_completed.is_connected(on_autosave_operation_completed):
		save_completed.disconnect(on_autosave_operation_completed)
	if save_failed.is_connected(on_autosave_operation_failed):
		save_failed.disconnect(on_autosave_operation_failed)

func on_autosave_operation_failed(error_code: int, file_path: String):
	if file_path.get_file().begins_with(AUTOSAVE_PREFIX):
		emit_signal("autosave_failed", error_code, file_path)
	# Disconnect
	if save_completed.is_connected(on_autosave_operation_completed):
		save_completed.disconnect(on_autosave_operation_completed)
	if save_failed.is_connected(on_autosave_operation_failed):
		save_failed.disconnect(on_autosave_operation_failed)

func cleanup_old_autosaves():
	var dir = DirAccess.open(SAVE_DIR)
	if not dir:
		printerr("SaveLoadManager: Cannot open save directory for cleanup: ", SAVE_DIR)
		return

	var autosave_files: Array[Dictionary] = []
	dir.list_dir_begin()
	var file_name = dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.begins_with(AUTOSAVE_PREFIX) and file_name.ends_with(SAVE_FILE_EXTENSION):
			autosave_files.append({
				"name": file_name,
				"timestamp": FileAccess.get_modified_time(SAVE_DIR.path_join(file_name))
			})
		file_name = dir.get_next()
	dir.list_dir_end()

	if autosave_files.size() > max_autosaves:
		autosave_files.sort_custom(func(a, b): return a.timestamp < b.timestamp) # Sort oldest first
		var num_to_delete = autosave_files.size() - max_autosaves
		for i in range(num_to_delete):
			var path_to_delete = SAVE_DIR.path_join(autosave_files[i].name)
			print("SaveLoadManager: Cleaning up old autosave: ", path_to_delete)
			var err = dir.remove(autosave_files[i].name) # remove expects just filename
			if err != OK:
				printerr("SaveLoadManager: Failed to delete old autosave ", path_to_delete, ". Error: ", err)
#endregion

#region Core Serialization/Deserialization Logic
func create_save_data() -> SimulationSaveData:
	if not simulation_manager:
		# Attempt to get SimulationManager if not already set (e.g. if SaveLoadManager is an AutoLoad)
		simulation_manager = get_tree().get_root().get_node_or_null("SimulationManager") # Common AutoLoad path
		if not simulation_manager:
			simulation_manager = get_node_or_null("/root/Main/SimulationManager") # Path if Main is root and SM is child
			if not simulation_manager:
				printerr("SaveLoadManager: SimulationManager not found!")
				return null
	
	if not camera_2d:
		# Attempt to get the current camera
		camera_2d = get_viewport().get_camera_2d()
		if not camera_2d:
			printerr("SaveLoadManager: Main Camera2D not found!")
			# Saving can proceed without camera, but log it.
			
	var save_data = SimulationSaveData.new()
	save_data.save_version = SAVE_VERSION
	save_data.save_timestamp = Time.get_unix_time_from_system()
	save_data.save_name = "Save Game - " + Time.get_datetime_string_from_unix_time(save_data.save_timestamp)

	# 1. Basic Simulation Info
	save_data.current_episode = simulation_manager.current_episode
	save_data.current_step = simulation_manager.current_step
	save_data.total_resources_mined = simulation_manager.total_resources_mined
	save_data.simulation_running = simulation_manager.is_simulation_running()
	# save_data.selected_probe_id = ui_manager.get_selected_probe_id() if ui_manager else "" # Example

	# 2. Camera State
	if camera_2d:
		save_data.camera_position = camera_2d.global_position
		save_data.camera_zoom = camera_2d.zoom
	else:
		save_data.camera_position = Vector2.ZERO
		save_data.camera_zoom = Vector2.ONE

	# 3. Probes
	var probes_in_scene = get_tree().get_nodes_in_group("probes")
	for probe_node in probes_in_scene:
		if not probe_node is Probe: continue # Type check
		var p: Probe = probe_node as Probe
		var probe_data = ProbeDataRes.new(str(p.probe_id), p.generation, p.unique_id) # Convert p.probe_id to String
		probe_data.global_transform = p.global_transform
		probe_data.linear_velocity = p.linear_velocity
		# probe_data.angular_velocity = p.angular_velocity # Probe.gd doesn't have this yet
		probe_data.energy = p.energy
		probe_data.status = p.current_status_to_string() # Assuming a method to get status string
		probe_data.current_task = p.current_task_to_string() # Assuming a method
		
		if p.target_celestial_body:
			probe_data.target_celestial_body_name = p.target_celestial_body.body_name
		if p.target_resource:
			probe_data.target_resource_id = p.target_resource.resource_id 
		# probe_data.target_probe_id = p.target_probe.unique_id if p.target_probe else "" # If applicable
		probe_data.target_position = p.target_position
		
		probe_data.trail_points = p.get_trail_points() # Assuming Probe has get_trail_points()
		
		# AI State - basic example
		if p.ai_agent:
			probe_data.ai_state_variables = p.ai_agent.get_state_for_save() # Needs method in AIAgent
			# probe_data.q_table = p.ai_agent.q_learning_module.q_table if p.ai_agent.q_learning_module else {}

		# Communication & Knowledge
		probe_data.known_resource_locations = p.known_resource_locations
		probe_data.known_probe_locations = p.known_probe_locations
		# probe_data.message_buffer = p.message_buffer # Assuming message_buffer in Probe holds MessageData resources

		save_data.probes.append(probe_data)

	# 4. Resources
	var resources_in_scene = get_tree().get_nodes_in_group("resources")
	for resource_node in resources_in_scene:
		if not resource_node is GameResource: continue
		var r: GameResource = resource_node as GameResource
		var resource_data = ResourceData.new() # ResourceData is class_name
		resource_data.resource_id = r.resource_id # Assuming GameResource has resource_id
		resource_data.resource_type = r.resource_type_to_string() # Method to get string
		resource_data.quantity = r.quantity
		resource_data.max_quantity = r.max_quantity
		resource_data.global_position = r.global_position
		resource_data.is_discovered = r.is_discovered
		resource_data.is_depleted = r.is_depleted
		save_data.resources.append(resource_data)
		
	# 5. Celestial Bodies
	var bodies_in_scene = get_tree().get_nodes_in_group("celestial_bodies")
	for body_node in bodies_in_scene:
		if not body_node is CelestialBody: continue # Type check
		var cb: CelestialBody = body_node as CelestialBody
		var body_data = CelestialBodyDataRes.new(cb.body_name)
		body_data.global_transform = cb.global_transform
		body_data.linear_velocity = cb.linear_velocity # Assuming CelestialBody has linear_velocity
		body_data.orbit_points = cb.get_orbit_points() # Assuming CelestialBody has get_orbit_points()
		save_data.celestial_bodies.append(body_data)

	# 6. Communication Log
	if simulation_manager.communication_log: # communication_log is Array[MessageData]
		save_data.communication_log = simulation_manager.communication_log.duplicate() # Duplicate to be safe

	return save_data

func apply_save_data(save_data: SimulationSaveData) -> bool:
	if not simulation_manager:
		simulation_manager = get_tree().get_root().get_node_or_null("SimulationManager")
		if not simulation_manager:
			simulation_manager = get_node_or_null("/root/Main/SimulationManager")
			if not simulation_manager:
				printerr("SaveLoadManager: SimulationManager not found during apply_save_data!")
				return false
				
	if not camera_2d:
		camera_2d = get_viewport().get_camera_2d()
		# Not finding camera is not fatal for loading state, but log it.
		if not camera_2d: print("SaveLoadManager: Main Camera2D not found during apply_save_data.")

	# Pause simulation during load
	var originally_running = simulation_manager.is_simulation_running()
	simulation_manager.set_simulation_running(false)

	# Clear existing dynamic entities
	clear_simulation_entities()

	# 1. Restore Basic Simulation Info
	simulation_manager.current_episode = save_data.current_episode
	simulation_manager.current_step = save_data.current_step
	simulation_manager.total_resources_mined = save_data.total_resources_mined
	# simulation_manager.selected_probe_id = save_data.selected_probe_id # If UI manager handles this

	# 2. Restore Camera State
	if camera_2d:
		camera_2d.global_position = save_data.camera_position
		camera_2d.zoom = save_data.camera_zoom
	
	# 3. Restore Entities
	if not restore_celestial_bodies(save_data.celestial_bodies): return false # Bodies first, probes might target them
	if not restore_resources(save_data.resources): return false
	if not restore_probes(save_data.probes): return false # Probes last, may depend on others

	# 4. Restore Communication Log
	simulation_manager.communication_log = save_data.communication_log.duplicate()
	# Potentially update UI for communication log here

	# Resume simulation if it was running
	if save_data.simulation_running or originally_running: # Resume if it was running in save OR before load
		simulation_manager.set_simulation_running(true)
	
	print("SaveLoadManager: Save data applied.")
	return true

func clear_simulation_entities():
	# Clear probes
	for probe_node in get_tree().get_nodes_in_group("probes"):
		if is_instance_valid(probe_node): # Ensure node is valid before queue_free
			# simulation_manager.probe_manager.remove_probe(probe_node) # If ProbeManager handles removal
			probe_node.queue_free()
	
	# Clear dynamically added resources if they are not part of the main scene structure
	# If resources are part of the main scene and just updated, this might not be needed
	# For this example, assuming resources are dynamically managed or can be cleared/re-added.
	# for res_node in get_tree().get_nodes_in_group("resources"):
		# if res_node.owner == null: # A way to check if it was dynamically added
			# res_node.queue_free()

	# Clear visual messages or other dynamic elements if any
	# e.g., get_tree().call_group("communication_visuals", "queue_free")
	
	# Reset relevant lists in SimulationManager if needed
	simulation_manager.communication_log.clear()
	# simulation_manager.probe_manager.probes.clear() # If ProbeManager has a list

	print("SaveLoadManager: Cleared existing simulation entities.")


func restore_probes(probe_data_array: Array[ProbeDataRes]) -> bool: # Use preloaded type
	if not simulation_manager or not simulation_manager.probe_manager:
		printerr("SaveLoadManager: SimulationManager or ProbeManager not found for restoring probes.")
		return false
	
	var probe_scene = load("res://scenes/probes/Probe.tscn") # Adjust path as needed
	if not probe_scene:
		printerr("SaveLoadManager: Failed to load Probe.tscn for restoring probes.")
		return false

	for pd in probe_data_array:
		var new_probe: Probe = probe_scene.instantiate() as Probe
		if not new_probe:
			printerr("SaveLoadManager: Failed to instantiate probe from Probe.tscn.")
			continue

		if pd.probe_id.is_valid_int():
			new_probe.probe_id = int(pd.probe_id) # Convert pd.probe_id to int
		else:
			printerr("SaveLoadManager: Invalid probe_id format in save data: ", pd.probe_id)
			# Assign a default or skip this probe? For now, let it be default from Probe.gd _init
		new_probe.generation = pd.generation
		new_probe.unique_id = pd.unique_id
		new_probe.global_transform = pd.global_transform
		new_probe.linear_velocity = pd.linear_velocity
		# new_probe.angular_velocity = pd.angular_velocity
		new_probe.energy = pd.energy
		new_probe.force_status_from_save(pd.status) # Needs method in Probe to set status directly
		new_probe.force_task_from_save(pd.current_task) # Needs method in Probe
		
		# Target restoration needs care - entities must exist or be findable
		# This might need to happen in a second pass after all entities are created
		if not pd.target_celestial_body_name.is_empty():
			new_probe.target_celestial_body = simulation_manager.solar_system.get_celestial_body_by_name(pd.target_celestial_body_name)
		if not pd.target_resource_id.is_empty():
			new_probe.target_resource = simulation_manager.resource_manager.get_resource_by_id(pd.target_resource_id)
		# new_probe.target_probe = simulation_manager.probe_manager.get_probe_by_id(pd.target_probe_id) # If applicable
		new_probe.target_position = pd.target_position
		
		new_probe.set_trail_points(pd.trail_points) # Needs method in Probe
		
		if new_probe.ai_agent and pd.ai_state_variables:
			new_probe.ai_agent.apply_state_from_save(pd.ai_state_variables) # Needs method in AIAgent
			# if pd.q_table and new_probe.ai_agent.q_learning_module:
				# new_probe.ai_agent.q_learning_module.q_table = pd.q_table

		new_probe.known_resource_locations = pd.known_resource_locations.duplicate(true)
		new_probe.known_probe_locations = pd.known_probe_locations.duplicate(true)
		# new_probe.message_buffer = pd.message_buffer.duplicate(true) # Ensure deep copy of MessageData resources

		# Add to scene and manager
		# The parent for probes might be SimulationManager, ProbeManager, or a dedicated node
		var probes_container = get_tree().get_root().get_node_or_null("Main/Probes") # Example path
		if not probes_container: probes_container = simulation_manager # Fallback or adjust
		probes_container.add_child(new_probe)
		
		simulation_manager.probe_manager.register_probe(new_probe) # Assuming ProbeManager has register_probe
		simulation_manager.connect_probe_signals(new_probe) # Reconnect signals

	print("SaveLoadManager: Probes restored.")
	return true

func restore_resources(resource_data_array: Array[ResourceData]) -> bool:
	if not simulation_manager or not simulation_manager.resource_manager:
		printerr("SaveLoadManager: ResourceManager not found for restoring resources.")
		return false

	# This is a simple approach: update existing by index/ID or clear and recreate.
	# For a robust system, you'd match by a persistent ID.
	# The prompt's example updates by index if counts match.
	
	var existing_resources = get_tree().get_nodes_in_group("resources")
	
	# Option 1: Clear and recreate (simpler if dynamic)
	# for res_node in existing_resources: res_node.queue_free()
	# simulation_manager.resource_manager.clear_all_resources() # If manager holds list
	# var resource_scene = load("res://scenes/Resource.tscn") # Path to your Resource scene
	# if not resource_scene: printerr("Failed to load Resource.tscn"); return false
	# for rd in resource_data_array:
	# 	var new_res: ResourceNode = resource_scene.instantiate()
	#   ... set properties from rd ...
	#   simulation_manager.resource_manager.add_resource_node(new_res)
	#   get_tree().get_root().get_node("Main/Resources").add_child(new_res) # Example path

	# Option 2: Update existing if possible (more complex, assumes static scene setup or matching IDs)
	# This example assumes resources are somewhat static or can be identified.
	# If resource_id is reliable and unique:
	for rd in resource_data_array: # ResourceData is class_name
		var found_resource: GameResource = simulation_manager.resource_manager.get_resource_node_by_id(rd.resource_id)
		if found_resource:
			# Assuming GameResource has these methods/properties or they need to be added
			# found_resource.resource_type_from_string(rd.resource_type)
			found_resource.quantity = rd.quantity
			found_resource.max_quantity = rd.max_quantity # Assuming this can be set
			found_resource.global_position = rd.global_position # Might be problematic if physics moves them
			found_resource.is_discovered = rd.is_discovered
			found_resource.is_depleted = rd.is_depleted
			found_resource.update_visual_state() # Method to refresh visuals
		else:
			# If not found, you might need to spawn it. This part depends heavily on game structure.
			printerr("SaveLoadManager: Could not find existing resource with ID: ", rd.resource_id, " to update. Spawning new is not implemented in this example.")
			# Consider spawning a new one if appropriate for your game design
			# var new_res = resource_scene.instantiate()... etc.

	print("SaveLoadManager: Resources restored/updated.")
	return true


func restore_celestial_bodies(body_data_array: Array[CelestialBodyDataRes]) -> bool: # Use preloaded type
	if not simulation_manager or not simulation_manager.solar_system:
		printerr("SaveLoadManager: SolarSystem manager not found for restoring celestial bodies.")
		return false

	for bd in body_data_array:
		var body_node: CelestialBody = simulation_manager.solar_system.get_celestial_body_by_name(bd.body_name)
		if body_node:
			body_node.global_transform = bd.global_transform # Position, rotation, scale
			body_node.linear_velocity = bd.linear_velocity
			body_node.set_orbit_points(bd.orbit_points) # Needs method in CelestialBody
			# body_node.update_trail() # If trail needs manual refresh
		else:
			printerr("SaveLoadManager: Celestial body not found by name: ", bd.body_name)
			# Celestial bodies are usually part of the main scene, so not finding one is an issue.
			# If they can be dynamic, spawning logic would be needed here.
			# return false # Could be critical

	print("SaveLoadManager: Celestial bodies restored.")
	return true
#endregion