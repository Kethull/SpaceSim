extends Node
class_name SimulationManager

const MessageData = preload("res://scripts/data/MessageData.gd") # For type hinting

@onready var solar_system: Node2D = $"../SolarSystem" # Path to SolarSystem node in Main.tscn
@onready var resource_manager: Node2D = $"../ResourceManager" # Path to ResourceManager node in Main.tscn
@onready var probe_manager: Node = $"../ProbeManager" # Assuming ProbeManager exists at this path for probe spawning
@onready var modern_ui: Control = $"../UI/HUD" # Path to the ModernUI node
@onready var camera_controller: Node = $"../MainCamera/CameraController" # Path to CameraController

var celestial_body_scene = preload("res://scenes/CelestialBody.tscn")
var resource_scene = preload("res://scenes/Resource.tscn")
var probe_scene = preload("res://scenes/probes/Probe.tscn") # Preload ProbeUnit scene
# var replication_effect_scene = preload("res://effects/ReplicationEffect.tscn") # Commented out until .tscn is created

# References to specific bodies for moon creation or other interactions
var earth_instance = null
var jupiter_instance = null
var saturn_instance = null

# Resource Statistics
var total_initial_resources_value: float = 0.0
var current_total_resources_value: float = 0.0
var resources_by_type_count: Dictionary = {} # e.g., {"mineral": 5, "energy": 3}
var discovered_resources_count: int = 0
var depleted_resources_count: int = 0
var discovered_resources_log: Array[Dictionary] = [] # Log of discovered resources
var total_resources_mined: float = 0.0

# Helper for unique resource discovery tracking
var _discovered_resource_ids: Array[int] = [] # Store instance IDs of uniquely discovered resources

# Replication Statistics
var total_replications: int = 0

# Communication Log
var communication_log: Array[MessageData] = []
var max_communication_log_size: int = 200 # Default, can be overridden by config

# Simulation State
var current_episode: int = 1
var current_step: int = 0
var simulation_speed: float = 1.0
var is_paused: bool = false
var _current_selected_probe_node: ProbeUnit = null # Stores the currently selected probe instance

# UI Update Control
const UI_UPDATE_INTERVAL = 0.25 # seconds
var _ui_update_timer: float = 0.0

@export_group("Stress Test Settings")
@export var enable_stress_test_on_ready: bool = false
@export var stress_test_probe_count: int = 100
@export var stress_test_resource_count: int = 300


# SimulationManager.gd
# Main game logic controller.
# This script will manage the overall simulation state, time, and events.

# Assuming ResourceData and SimulationSaveData are defined/preloaded elsewhere
# For example:
# const ResourceData = preload("res://scripts/data/ResourceData.gd")
# const SimulationSaveData = preload("res://scripts/data/SimulationSaveData.gd")


func _ready():
	print("SimulationManager ready.")
	var cfg_node = get_node_or_null("/root/ConfigManager") # Renamed for clarity
	if cfg_node and cfg_node.has_method("get_config"):
		var game_cfg = cfg_node.get_config()
		if game_cfg: # Ensure game_cfg is not null
			# The properties max_communication_log_entries, communication_log_max_size,
			# and initial_simulation_speed are not defined in GameConfiguration.gd.
			# SimulationManager.gd already defines defaults for max_communication_log_size (line 39)
			# and simulation_speed (line 44).
			# We will simply set Engine.time_scale using the simulation_speed from this script.
			Engine.time_scale = simulation_speed
	
	initialize_simulation()
	_connect_ui_signals()
	
	if enable_stress_test_on_ready:
		# Short delay to ensure everything else is set up, then trigger stress test
		await get_tree().create_timer(0.5).timeout
		trigger_stress_test(stress_test_probe_count, stress_test_resource_count)


	# Play ambient space music
	var audio_manager = get_node_or_null("/root/AudioManager")
	if audio_manager and audio_manager.has_method("play_looping_sound"):
		# Assuming "ambient_space_music" is defined in AudioManager's sound_configs
		# and AudioManager has an "ambient_volume" property or method to get it.
		# If AudioManager.ambient_volume is a direct var:
		# audio_manager.play_looping_sound("ambient_space_music", Vector2.ZERO, audio_manager.ambient_volume, false)
		# If it's a getter:
		# audio_manager.play_looping_sound("ambient_space_music", Vector2.ZERO, audio_manager.get_ambient_volume(), false)
		# For now, let's assume a default volume or that AudioManager handles it internally if volume not passed
		audio_manager.play_looping_sound("ambient_space_music", Vector2.ZERO, 1.0, false) # Placeholder volume 1.0
	elif audio_manager:
		printerr("SimulationManager: AudioManager found, but no play_looping_sound method for ambient music.")
	# else: printerr("SimulationManager: AudioManager not found, cannot play ambient music.")


func initialize_simulation():
	print("Initializing simulation...")
	# Access ConfigManager for global settings if needed later
	# var au_scale = ConfigManager.get_setting("au_scale", 10000.0)
	# print("AU Scale from ConfigManager: %f" % au_scale) # Example
	
	initialize_solar_system()
	print("Solar system initialized.")
	
	initialize_resources()
	print("Resources initialized.")
	
	create_initial_probes() # Create initial probes after resources
	print("Initial probes created.")

func _process(delta):
	if is_paused:
		return

	current_step += 1
	
	# Update UI periodically
	_ui_update_timer += delta
	if _ui_update_timer >= UI_UPDATE_INTERVAL:
		_ui_update_timer = 0.0
		_update_ui_data()
	
	# Main simulation loop.
	# Update game state, handle time progression, etc.

func _create_celestial_body(data: Dictionary):
	var body_instance = celestial_body_scene.instantiate()
	
	body_instance.body_name = data.get("body_name", "Unnamed Body")
	body_instance.mass_kg = data.get("mass_kg", 0.0)
	body_instance.radius_km = data.get("radius_km", 0.0)
	body_instance.display_radius = data.get("display_radius", 10.0)
	body_instance.body_color = data.get("body_color", Color.WHITE)
	
	if data.has("semi_major_axis_au"):
		body_instance.semi_major_axis_au = data.get("semi_major_axis_au")
	if data.has("eccentricity"):
		body_instance.eccentricity = data.get("eccentricity")
	
	body_instance.central_body_name = data.get("central_body_name", "")

	# Add to scene tree. CelestialBody.gd's _ready() should handle its own initialization
	# (like calling calculate_initial_state and setup_visual_appearance)
	# once it's in the tree and its properties are set.
	solar_system.add_child(body_instance)
	
	body_instance.add_to_group("celestial_bodies")
	
	if body_instance.body_name == "Sun":
		body_instance.add_to_group("sun")
		# Sun's global_position is set explicitly in initialize_solar_system after creation.

	return body_instance

func initialize_solar_system():
	if not solar_system:
		printerr("SolarSystem node not found in SimulationManager! Path used: ../SolarSystem. Ensure this node exists in Main.tscn at the correct path.")
		return

	# 1. Create the Sun
	# The Sun must be created and added to the scene tree first so that planets 
	# can reference it by name when their own _ready() functions are called.
	var sun_data = {
		"body_name": "Sun",
		"mass_kg": 1.9885e30,
		"radius_km": 695700.0,
		"display_radius": 200.0, # Visual scale suggestion
		"body_color": Color.YELLOW,
		"central_body_name": "" # Sun has no central body
	}
	var sun_instance = _create_celestial_body(sun_data)
	sun_instance.global_position = Vector2.ZERO # Explicitly set Sun at the origin

	# 2. Create Planets
	# Planets are created next. Their _ready() functions will look for "Sun".
	var planets_data = [
		{ "body_name": "Mercury", "mass_kg": 0.33011e24, "radius_km": 2439.7, "body_color": Color.GRAY, "semi_major_axis_au": 0.387, "eccentricity": 0.206, "display_radius": 8.0, "central_body_name": "Sun" },
		{ "body_name": "Venus", "mass_kg": 4.8675e24, "radius_km": 6051.8, "body_color": Color(0.9, 0.85, 0.7), "semi_major_axis_au": 0.723, "eccentricity": 0.007, "display_radius": 15.0, "central_body_name": "Sun" },
		{ "body_name": "Earth", "mass_kg": 5.97237e24, "radius_km": 6371.0, "body_color": Color.BLUE, "semi_major_axis_au": 1.0, "eccentricity": 0.017, "display_radius": 16.0, "central_body_name": "Sun" },
		{ "body_name": "Mars", "mass_kg": 0.64171e24, "radius_km": 3389.5, "body_color": Color.RED, "semi_major_axis_au": 1.524, "eccentricity": 0.093, "display_radius": 10.0, "central_body_name": "Sun" },
		{ "body_name": "Jupiter", "mass_kg": 1898.19e24, "radius_km": 69911.0, "body_color": Color.ORANGE, "semi_major_axis_au": 5.203, "eccentricity": 0.048, "display_radius": 60.0, "central_body_name": "Sun" },
		{ "body_name": "Saturn", "mass_kg": 568.34e24, "radius_km": 58232.0, "body_color": Color(0.9, 0.85, 0.6), "semi_major_axis_au": 9.537, "eccentricity": 0.054, "display_radius": 50.0, "central_body_name": "Sun" },
		{ "body_name": "Uranus", "mass_kg": 86.813e24, "radius_km": 25362.0, "body_color": Color.CYAN, "semi_major_axis_au": 19.191, "eccentricity": 0.047, "display_radius": 30.0, "central_body_name": "Sun" },
		{ "body_name": "Neptune", "mass_kg": 102.413e24, "radius_km": 24622.0, "body_color": Color.DARK_BLUE, "semi_major_axis_au": 30.069, "eccentricity": 0.009, "display_radius": 28.0, "central_body_name": "Sun" }
	]

	for planet_data in planets_data:
		var planet_instance = _create_celestial_body(planet_data)
		if planet_data.body_name == "Earth":
			earth_instance = planet_instance
		elif planet_data.body_name == "Jupiter":
			jupiter_instance = planet_instance
		elif planet_data.body_name == "Saturn":
			saturn_instance = planet_instance
	
	# 3. Add Major Moons
	# Moons are created last. Their _ready() functions will look for their respective parent planets by name.
	# Earth's Moon
	if earth_instance:
		var moon_data_earth = { "body_name": "Moon", "mass_kg": 0.07346e24, "radius_km": 1737.4, "body_color": Color.LIGHT_GRAY, "semi_major_axis_au": 0.00257, "eccentricity": 0.055, "display_radius": 4.0, "central_body_name": "Earth" }
		_create_celestial_body(moon_data_earth)
	else:
		printerr("Earth instance not found in SimulationManager, cannot create Moon.")

	# Jupiter's Moons
	if jupiter_instance:
		var moons_data_jupiter = [
			{ "body_name": "Io", "mass_kg": 0.089319e24, "radius_km": 1821.6, "body_color": Color.YELLOW, "semi_major_axis_au": 0.00282, "eccentricity": 0.004, "display_radius": 5.0, "central_body_name": "Jupiter" },
			{ "body_name": "Europa", "mass_kg": 0.04800e24, "radius_km": 1560.8, "body_color": Color(0.8, 0.8, 0.9), "semi_major_axis_au": 0.00449, "eccentricity": 0.009, "display_radius": 4.5, "central_body_name": "Jupiter" },
			{ "body_name": "Ganymede", "mass_kg": 0.14819e24, "radius_km": 2634.1, "body_color": Color.GRAY, "semi_major_axis_au": 0.00716, "eccentricity": 0.001, "display_radius": 6.0, "central_body_name": "Jupiter" },
			{ "body_name": "Callisto", "mass_kg": 0.10759e24, "radius_km": 2410.3, "body_color": Color(0.5, 0.45, 0.4), "semi_major_axis_au": 0.01259, "eccentricity": 0.007, "display_radius": 5.5, "central_body_name": "Jupiter" }
		]
		for moon_data in moons_data_jupiter:
			_create_celestial_body(moon_data)
	else:
		printerr("Jupiter instance not found in SimulationManager, cannot create its moons.")

	# Saturn's Moon
	if saturn_instance:
		var moon_data_saturn = { "body_name": "Titan", "mass_kg": 0.13452e24, "radius_km": 2574.7, "body_color": Color(0.9, 0.7, 0.4), "semi_major_axis_au": 0.00817, "eccentricity": 0.029, "display_radius": 5.0, "central_body_name": "Saturn" }
		_create_celestial_body(moon_data_saturn)
	else:
		printerr("Saturn instance not found in SimulationManager, cannot create Titan.")

func initialize_resources():
	var config_manager_node = get_node_or_null("/root/ConfigManager")
	if not config_manager_node:
		printerr("ConfigManager autoload node not found at /root/ConfigManager!")
		return
	if not config_manager_node.has_method("get_config"):
		printerr("ConfigManager node does not have a 'get_config' method.")
		return
	
	var current_config = config_manager_node.get_config()
	if not current_config:
		printerr("Failed to retrieve config object from ConfigManager.")
		return

	if not resource_manager:
		printerr("ResourceManager node not found in SimulationManager! Path used: ../ResourceManager.")
		return

	var resource_count = current_config.resource_count
	var world_size_au = current_config.world_size_au
	var au_scale = current_config.au_scale
	var resource_amount_range = current_config.resource_amount_range
	var resource_regen_rate = current_config.resource_regen_rate
	
	var world_radius_sim_units = world_size_au * au_scale
	
	var resource_types = ["mineral", "energy", "rare_earth", "water"]
	var placement_attempts = 10 # Max attempts to find a non-colliding spot
	var collision_buffer = 50.0 # Extra buffer around celestial bodies

	print("Attempting to spawn %d resources." % resource_count)

	for i in range(resource_count):
		var resource_instance = resource_scene.instantiate()
		var placed = false
		
		for attempt in range(placement_attempts):
			var random_angle = randf_range(0, TAU)
			var random_radius_factor = randf_range(0.1, 1.0) # Avoid spawning too close to the center (Sun) initially
			var random_dist = world_radius_sim_units * sqrt(random_radius_factor) # sqrt for more uniform distribution
			
			var proposed_position = Vector2(cos(random_angle), sin(random_angle)) * random_dist
			
			var collision = false
			var celestial_bodies = get_tree().get_nodes_in_group("celestial_bodies")
			
			for body in celestial_bodies:
				if not is_instance_valid(body):
					printerr("Invalid celestial body instance encountered during resource placement.")
					continue
				
				# Assuming CelestialBody instances will have a 'display_radius' property.
				var body_pos = body.global_position
				var body_radius = body.display_radius + collision_buffer
				
				if proposed_position.distance_to(body_pos) < body_radius:
					collision = true
					break
			
			if not collision:
				resource_instance.global_position = proposed_position
				placed = true
				break
		
		if not placed:
			print("Could not find a suitable position for resource %d after %d attempts. Skipping." % [i, placement_attempts])
			resource_instance.queue_free() # Clean up unplaced instance
			continue

		# Randomize Properties
		var current_amount = randf_range(resource_amount_range.x, resource_amount_range.y)
		resource_instance.current_amount = current_amount
		resource_instance.max_amount = current_amount # As per instruction
		resource_instance.resource_type = resource_types[randi() % resource_types.size()]
		resource_instance.regeneration_rate = resource_regen_rate # From config

		# Add to ResourceManager
		resource_manager.add_child(resource_instance)
		# Resource adds itself to "resources" group in its _ready() function.

		# Connect signals
		if resource_instance.has_signal("resource_depleted"):
			resource_instance.resource_depleted.connect(_on_resource_depleted.bind(resource_instance))
		else:
			printerr("Resource instance %s does not have signal 'resource_depleted'." % resource_instance.name)
		
		if resource_instance.has_signal("resource_harvested"):
			resource_instance.resource_harvested.connect(_on_resource_harvested.bind(resource_instance))
		else:
			printerr("Resource instance %s does not have signal 'resource_harvested'." % resource_instance.name)


	_initialize_resource_stats()
	print("Finished spawning resources. %d resources added to ResourceManager (potentially less if placement failed)." % resource_manager.get_child_count())
	print("Initial resource stats: total_value=%f, current_value=%f, types=%s" % [total_initial_resources_value, current_total_resources_value, str(resources_by_type_count)])

func _initialize_resource_stats():
	total_initial_resources_value = 0.0
	current_total_resources_value = 0.0
	resources_by_type_count = {}
	discovered_resources_count = 0
	depleted_resources_count = 0
	total_resources_mined = 0.0
	_discovered_resource_ids.clear()
	discovered_resources_log.clear()

	if not resource_manager:
		printerr("ResourceManager not available for _initialize_resource_stats")
		return

	for r_node_variant in resource_manager.get_children():
		var r_node = r_node_variant as GameResource
		if r_node:
			total_initial_resources_value += r_node.max_amount
			current_total_resources_value += r_node.current_amount
			
			var r_type: String = r_node.resource_type
			if not resources_by_type_count.has(r_type):
				resources_by_type_count[r_type] = 0
			resources_by_type_count[r_type] += 1

func _find_resource_at_position(pos: Vector2, tolerance: float = 1.0) -> GameResource:
	if not resource_manager: return null
	for r_node_variant in resource_manager.get_children():
		var r_node = r_node_variant as GameResource
		if r_node:
			if r_node.global_position.distance_to(pos) < tolerance:
				return r_node
	return null

func create_initial_probes():
	if not probe_manager:
		printerr("ProbeManager node not found in SimulationManager! Path used: ../ProbeManager. Cannot create initial probes.")
		return

	if not probe_scene:
		printerr("ProbeUnit scene not loaded, cannot create initial probes.")
		return

	var config_manager_node = get_node_or_null("/root/ConfigManager")
	if not config_manager_node or not config_manager_node.has_method("get_config"):
		printerr("ConfigManager not available or does not have get_config method. Cannot determine initial_probe_count.")
		return
	
	var current_config = config_manager_node.get_config()
	# GameConfiguration has 'initial_probes' as a direct property.
	# We check if current_config itself is null, then access the property.
	if not current_config: # Check if config object was retrieved
		printerr("Failed to retrieve config object from ConfigManager. Defaulting to 1 probe for initial_probes.")
		current_config = {"initial_probes": 1} # Fallback to a dictionary if GameConfiguration is missing
	elif not current_config.has_meta("initial_probes") and not "initial_probes" in current_config: # Check if property exists, GameConfiguration is a Resource
		# This check is more for safety; 'initial_probes' is an @export var in GameConfiguration.
		# If GameConfiguration is loaded correctly, 'initial_probes' should exist.
		# If current_config became a Dictionary due to earlier fallback, this 'in' check is valid.
		printerr("'initial_probes' property not found in the loaded GameConfiguration. Defaulting to 1 probe.")
		# To ensure num_probes_to_create can still be fetched if current_config is a GameConfiguration without the property (unlikely for @export)
		# or if it's our fallback dictionary.
		if not ("initial_probes" in current_config): # If it's a GameConfiguration that somehow lost the prop
			current_config = {"initial_probes": 1} # Re-ensure fallback if it was a GameConfig missing the prop
	# If current_config is a valid GameConfiguration, current_config.initial_probes will be used by .get()
	# If current_config is the fallback dictionary, .get() will also work.

		printerr("initial_probes not found in ConfigManager.config. Defaulting to 1 probe.")
		current_config = {"initial_probes": 1} # Fallback

	var num_probes_to_create = current_config.get("initial_probes", 1)
	print("Attempting to create %d initial probes." % num_probes_to_create)

	for i in range(num_probes_to_create):
		var probe_instance = probe_scene.instantiate()
		if not probe_instance:
			printerr("Failed to instantiate probe_scene for probe %d." % i)
			continue

		# Position probes in a slight spread around origin for now
		var angle = TAU * float(i) / float(num_probes_to_create)
		var distance_from_origin = 150.0 + (i * 20.0) # Spread them out a bit
		probe_instance.global_position = Vector2(cos(angle), sin(angle)) * distance_from_origin
		
		probe_instance.probe_id = "ProbeUnit-%d" % (i + 1) # Assign a unique ID, e.g., ProbeUnit-1, ProbeUnit-2
		probe_instance.generation = 0 # Initial probes are generation 0
		
		# Other properties like mass, energy will be set by ProbeUnit.gd's _ready()
		# using ConfigManager values or its own defaults if not overridden.

		probe_manager.add_child(probe_instance)
		connect_probe_signals(probe_instance) # Assuming connect_probe_signals is robust
		print("Created initial probe: ID %s (Gen %d) at %s" % [probe_instance.probe_id, probe_instance.generation, str(probe_instance.global_position)])

func connect_probe_signals(probe_instance: ProbeUnit): # Changed type hint to ProbeUnit
	if not is_instance_valid(probe_instance):
		printerr("Attempted to connect signals for an invalid probe instance.")
		return

	if probe_instance.has_signal("resource_discovered"):
		probe_instance.resource_discovered.connect(_on_resource_discovered_by_probe.bind(probe_instance))
	else:
		printerr("ProbeUnit instance %s does not have signal 'resource_discovered'." % probe_instance.name)
	
	# Connect other probe signals if needed in the future
	# probe_instance.probe_destroyed.connect(_on_probe_destroyed.bind(probe_instance))
	# probe_instance.energy_critical.connect(_on_probe_energy_critical.bind(probe_instance))
	
	if probe_instance.has_signal("communication_sent"):
		probe_instance.communication_sent.connect(_on_probe_communication_sent) # No bind needed if message is passed
	else:
		printerr("ProbeUnit instance %s does not have signal 'communication_sent'." % probe_instance.name)

	if probe_instance.has_signal("replication_requested"):
		probe_instance.replication_requested.connect(_on_replication_requested.bind(probe_instance))
	else:
		printerr("ProbeUnit instance %s does not have signal 'replication_requested'." % probe_instance.name)


func _on_probe_communication_sent(message: MessageData):
	if not is_instance_valid(message): # Should be a MessageData resource
		printerr("SimulationManager: Received invalid message object in _on_probe_communication_sent.")
		return
	
	communication_log.append(message)
	if communication_log.size() > max_communication_log_size:
		communication_log.pop_front() # Remove the oldest message
	
	var cfg_node = get_node_or_null("/root/ConfigManager")
	if cfg_node and cfg_node.has_method("get_config"):
		var game_cfg = cfg_node.get_config()
		if game_cfg and game_cfg.get("ai_debug_logging", false):
			print("SIM_LOG: Comm Event: Sender: %s, Target: %s, Type: %s, Pos: %s, Data: %s" % [message.sender_id, message.target_id, message.message_type, str(message.position), str(message.data)])


func _on_resource_discovered_by_probe(discovering_probe: ProbeUnit, resource_data: Dictionary): # Changed type hint and params based on ProbeUnit signal
	if not is_instance_valid(discovering_probe):
		print("Received resource_discovered signal from an invalid probe.")
		return
	
	# The signal from ProbeUnit now sends: probe: ProbeUnit, resource_data: Dictionary
	# resource_data is: {"id":res_node.name, "position":res_node.global_position, "type":r_data.get("type","unknown"), "amount":r_data.get("amount",0.0)}
	var res_pos: Vector2 = resource_data.get("position", Vector2.INF)
	var res_name: String = resource_data.get("id", "UnknownResource")
	var res_type: String = resource_data.get("type", "unknown")
	var res_amount: float = resource_data.get("amount", 0.0)
	
	# We might not have the actual GameResource node here if it's just data.
	# For logging, we can use the data provided.
	# If we need the node instance ID, we'd have to find it, but the signal is about the *event* of discovery.
	# Let's assume for now the `resource_data["id"]` (which is `res_node.name`) is unique enough for logging.
	# If `get_instance_id()` is crucial, the signal from ProbeUnit would need to pass the node itself, or its ID.
	# The current `resource_discovered` signal in ProbeUnit passes a dictionary.
	
	var discovered_resource_node = _find_resource_at_position(res_pos) # Try to find it anyway for instance ID
	var resource_instance_id_for_log = -1
	if is_instance_valid(discovered_resource_node):
		resource_instance_id_for_log = discovered_resource_node.get_instance_id()
	
	
	var discovery_event = {
		"probe_id": discovering_probe.probe_id,
		"resource_id": resource_instance_id_for_log, # May be -1 if node not found by this manager
		"resource_name": res_name,
		"resource_type": res_type,
		"position": res_pos,
		"amount_at_discovery": res_amount, # Amount at the time of discovery by the probe
		"timestamp": Time.get_ticks_msec()
	}
	discovered_resources_log.append(discovery_event)
	print("Discovery Logged: ProbeUnit %s found %s (ResID: %s) at %s. Type: %s, Amount: %f" % [discovering_probe.probe_id, res_name, str(resource_instance_id_for_log), str(res_pos), res_type, res_amount])
	
	var resource_instance_id = resource_instance_id_for_log # Use the ID we found, or -1
	if resource_instance_id != -1 and not resource_instance_id in _discovered_resource_ids : # Ensure valid ID before using .name
		_discovered_resource_ids.append(resource_instance_id)
		discovered_resources_count += 1
		var name_to_log = res_name
		if is_instance_valid(discovered_resource_node):
			name_to_log = discovered_resource_node.name
		print("Resource %s (ID: %s) is a new unique discovery. Total discovered: %d" % [name_to_log, str(resource_instance_id), discovered_resources_count])

func _on_resource_harvested(resource_node: GameResource, harvesting_probe: ProbeUnit, amount_harvested: float):
	if not is_instance_valid(resource_node) or not is_instance_valid(harvesting_probe):
		print("Received resource_harvested signal with invalid node(s).")
		return

	current_total_resources_value -= amount_harvested
	total_resources_mined += amount_harvested
	
	print("Resource %s (ID: %s) harvested by ProbeUnit %s. Amount: %f. Resource current: %f. ProbeUnit energy: %f. Sim total current value: %f, total mined: %f" % [
		resource_node.name, str(resource_node.get_instance_id()), harvesting_probe.name, amount_harvested,
		resource_node.current_amount, harvesting_probe.current_energy if harvesting_probe.has_method("get_current_energy") else harvesting_probe.current_energy if harvesting_probe.has("current_energy") else "N/A",
		current_total_resources_value, total_resources_mined
	])

func _on_resource_depleted(resource_node: GameResource):
	if not is_instance_valid(resource_node):
		print("Received resource_depleted signal from an invalid node.")
		return

	depleted_resources_count += 1
	# current_total_resources_value should have been updated by the final harvest.
	# If a resource depletes without full harvest (e.g. self-depletion), adjust here.
	
	print("Resource depleted: %s (ID: %s) at %s. Total depleted: %d. Sim total current value: %f" % [
		resource_node.name, str(resource_node.get_instance_id()), str(resource_node.global_position),
		depleted_resources_count, current_total_resources_value
	])

# --- Save/Load Functionality ---
# Ensure ResourceData and SimulationSaveData classes are defined and loaded, e.g.:
# const ResourceData = preload("res://scripts/data/ResourceData.gd")
# const SimulationSaveData = preload("res://scripts/data/SimulationSaveData.gd")

func create_save_data(): # -> SimulationSaveData: # Add return type if class is loaded
	var save_data = SimulationSaveData.new() if ClassDB.can_instantiate("SimulationSaveData") else {} # Fallback to Dictionary
	
	# save_data.simulation_time = ...
	# save_data.episode_count = ...
	# save_data.probes = ...
	# save_data.celestial_bodies_state = ...

	var resources_data_list: Array = [] # Array[ResourceData]
	if resource_manager:
		for r_node_variant in resource_manager.get_children():
			var r_node = r_node_variant as GameResource
			if r_node:
				var r_data = ResourceData.new() if ClassDB.can_instantiate("ResourceData") else {} # Fallback
				r_data.position = r_node.global_position
				r_data.current_amount = r_node.current_amount
				r_data.max_amount = r_node.max_amount
				r_data.resource_type = r_node.resource_type
				r_data.regeneration_rate = r_node.regeneration_rate
				r_data.discovered_by = r_node.discovered_by.duplicate(true)
				r_data.harvest_difficulty = r_node.harvest_difficulty if r_node.has("harvest_difficulty") else 1.0
				
				resources_data_list.append(r_data)
	save_data.resources = resources_data_list
	
	# Save SimulationManager's own stats if they are not easily recalculated
	save_data.sim_mgr_stats = {
		"total_initial_resources_value": total_initial_resources_value,
		"current_total_resources_value": current_total_resources_value,
		"resources_by_type_count": resources_by_type_count.duplicate(true),
		"discovered_resources_count": discovered_resources_count,
		"depleted_resources_count": depleted_resources_count,
		"total_resources_mined": total_resources_mined,
		"discovered_resource_ids": _discovered_resource_ids.duplicate(true),
		"discovered_resources_log": discovered_resources_log.duplicate(true)
	}

	print("SimulationManager: create_save_data called. Saved %d resources." % resources_data_list.size())
	return save_data

func load_simulation(save_data): # save_data: SimulationSaveData
	print("SimulationManager: load_simulation called.")
	if not save_data or not save_data.has("resources"):
		printerr("Load_simulation: No save data or no resources in save data.")
		return

	# Restore other simulation aspects first
	# ...

	# Restore Resources
	if resource_manager:
		for child in resource_manager.get_children():
			if child is GameResource: # Check against GameResource
				child.queue_free()
		
		print("Cleared old resources. Loading %d resources from save data." % save_data.resources.size())
		for r_data in save_data.resources:
			var res_instance = resource_scene.instantiate() as GameResource # Cast to GameResource
			if not res_instance:
				printerr("Failed to instantiate resource scene for loading.")
				continue

			res_instance.global_position = r_data.get("position", Vector2.ZERO)
			res_instance.current_amount = r_data.get("current_amount", 0.0)
			res_instance.max_amount = r_data.get("max_amount", 100.0)
			res_instance.resource_type = r_data.get("resource_type", "unknown")
			res_instance.regeneration_rate = r_data.get("regeneration_rate", 0.0)
			res_instance.discovered_by = r_data.get("discovered_by", []).duplicate(true)
			if res_instance.has_setter("harvest_difficulty"):
				res_instance.set("harvest_difficulty", r_data.get("harvest_difficulty", 1.0))
			elif res_instance.has("harvest_difficulty"):
				res_instance.harvest_difficulty = r_data.get("harvest_difficulty", 1.0)


			resource_manager.add_child(res_instance)
			if res_instance.has_method("update_visual_state"):
				res_instance.update_visual_state()

			if res_instance.has_signal("resource_depleted"):
				res_instance.resource_depleted.connect(_on_resource_depleted.bind(res_instance))
			if res_instance.has_signal("resource_harvested"):
				res_instance.resource_harvested.connect(_on_resource_harvested.bind(res_instance))
	
	# Restore SimulationManager's stats
	if save_data.has("sim_mgr_stats"):
		var stats = save_data.sim_mgr_stats
		total_initial_resources_value = stats.get("total_initial_resources_value", 0.0)
		current_total_resources_value = stats.get("current_total_resources_value", 0.0)
		resources_by_type_count = stats.get("resources_by_type_count", {}).duplicate(true)
		discovered_resources_count = stats.get("discovered_resources_count", 0)
		depleted_resources_count = stats.get("depleted_resources_count", 0)
		total_resources_mined = stats.get("total_resources_mined", 0.0)
		_discovered_resource_ids = stats.get("discovered_resource_ids", []).duplicate(true)
		discovered_resources_log = stats.get("discovered_resources_log", []).duplicate(true)
		print("Restored SimulationManager stats from save data.")
	else:
		# Fallback: Recalculate if not saved explicitly
		_initialize_resource_stats()
		_rebuild_discovery_stats_from_loaded_resources()
		print("Re-initialized/rebuilt SimulationManager stats as they were not in save data.")


	print("Resources loaded. Final stats: total_value=%f, current_value=%f, types=%s, discovered=%d, depleted=%d, mined=%f" % [total_initial_resources_value, current_total_resources_value, str(resources_by_type_count), discovered_resources_count, depleted_resources_count, total_resources_mined])

func _rebuild_discovery_stats_from_loaded_resources():
	_discovered_resource_ids.clear()
	discovered_resources_count = 0
	# discovered_resources_log is restored directly if saved, or remains empty/rebuilt if needed.

	if not resource_manager: return

	for r_node_variant in resource_manager.get_children():
		var r_node = r_node_variant as GameResource # Changed cast to GameResource
		if r_node:
			if r_node.discovered_by and not r_node.discovered_by.is_empty():
				var r_id = r_node.get_instance_id()
				if not r_id in _discovered_resource_ids:
					_discovered_resource_ids.append(r_id)
					discovered_resources_count +=1
	print("Rebuilt discovery stats: %d unique resources currently marked as discovered." % discovered_resources_count)


func _on_replication_requested(parent_probe: ProbeUnit):
	var cfg_node = get_node_or_null("/root/ConfigManager")
	if not cfg_node or not cfg_node.has_method("get_config"):
		printerr("SimulationManager: ConfigManager not found for replication request.")
		if is_instance_valid(parent_probe) and parent_probe.has_method("replication_globally_failed"):
			parent_probe.replication_globally_failed()
		return

	var config = cfg_node.get_config()
	var max_probes_allowed = config.get("max_probes", 20)
	var current_probe_count = get_tree().get_nodes_in_group("probes").size()

	if current_probe_count >= max_probes_allowed:
		if config.get("ai_debug_logging", false):
			print_debug("SimulationManager: Replication denied for ProbeUnit %s. Max probe limit (%d) reached. Current: %d" % [parent_probe.probe_id, max_probes_allowed, current_probe_count])
		if is_instance_valid(parent_probe) and parent_probe.has_method("replication_globally_failed"):
			parent_probe.replication_globally_failed()
		return

	create_child_probe(parent_probe)


func create_child_probe(parent_probe: ProbeUnit):
	if not is_instance_valid(parent_probe):
		printerr("SimulationManager: Cannot create child probe, parent_probe is invalid.")
		return

	var cfg_node = get_node_or_null("/root/ConfigManager")
	if not cfg_node or not cfg_node.has_method("get_config"):
		printerr("SimulationManager: ConfigManager not found for create_child_probe.")
		return
	var config = cfg_node.get_config()

	var child_probe = probe_scene.instantiate() as ProbeUnit
	if not child_probe:
		printerr("SimulationManager: Failed to instantiate probe_scene for child probe.")
		return

	# Property Inheritance and Variation
	child_probe.generation = parent_probe.generation + 1
	child_probe.probe_id = "ProbeUnit-G%d-%s" % [child_probe.generation, OS.get_unique_id().substr(0,6)] # Simple unique ID

	# Initial Energy for child
	child_probe.current_energy = config.get("initial_energy", 50000.0)
	child_probe.max_energy_capacity = config.get("max_energy", 100000.0) # Base max energy

	# Genetic Variations
	var mutation_chance = config.get("replication_mutation_chance", 0.05)
	var mutation_factor = config.get("replication_mutation_factor_small", 0.1)

	if randf() < mutation_chance:
		var mutated_property_log = "Mutations: "
		# Mutate max_energy_capacity
		var original_max_energy = child_probe.max_energy_capacity
		child_probe.max_energy_capacity *= (1.0 + randf_range(-mutation_factor, mutation_factor))
		child_probe.max_energy_capacity = max(child_probe.max_energy_capacity, config.get("initial_energy", 10000.0) * 0.5) # Ensure it's not too low
		mutated_property_log += "max_energy (%.0f -> %.0f), " % [original_max_energy, child_probe.max_energy_capacity]
		
		# Ensure current energy is not more than new max capacity after mutation
		child_probe.current_energy = min(child_probe.current_energy, child_probe.max_energy_capacity)

		# Mutate one of the thrust_force_magnitudes (excluding level 0)
		var thrust_magnitudes: Array[float] = config.get("thrust_force_magnitudes", [0.0, 0.08, 0.18, 0.32]).duplicate() # Get a copy
		if thrust_magnitudes.size() > 1:
			var rand_idx = randi_range(1, thrust_magnitudes.size() - 1) # Pick a non-zero thrust level
			var original_thrust = thrust_magnitudes[rand_idx]
			thrust_magnitudes[rand_idx] *= (1.0 + randf_range(-mutation_factor, mutation_factor))
			thrust_magnitudes[rand_idx] = max(0.01, thrust_magnitudes[rand_idx]) # Ensure not negative or zero
			# This mutated thrust_magnitudes array isn't directly set on the child probe here,
			# as ProbeUnit.gd reads it from ConfigManager. This implies child probes would need
			# their own override mechanism or this mutation needs to be stored differently.
			# For now, logging the intent. A more complex system would store these overrides on the probe.
			mutated_property_log += "thrust_level_%d (%.3f -> %.3f)" % [rand_idx, original_thrust, thrust_magnitudes[rand_idx]]
		
		if config.get("ai_debug_logging", false):
			print_debug("ProbeUnit %s (Child of %s): %s" % [child_probe.probe_id, parent_probe.probe_id, mutated_property_log])

	# Positioning: Slightly offset from parent
	var offset_direction = Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)).normalized()
	var parent_radius = 20.0 # Default, ideally get from parent's collision shape
	if parent_probe.get_node_or_null("CollisionShape2D") and parent_probe.get_node_or_null("CollisionShape2D").shape is CircleShape2D:
		parent_radius = (parent_probe.get_node_or_null("CollisionShape2D").shape as CircleShape2D).radius
	child_probe.global_position = parent_probe.global_position + offset_direction * parent_radius * 2.5

	if probe_manager:
		probe_manager.add_child(child_probe)
		connect_probe_signals(child_probe)
		total_replications += 1

		if config.get("ai_debug_logging", false) or true: # Keep this log for now
			print("SimulationManager: Child ProbeUnit %s (Gen %d) created from Parent %s. Pos: %s. Total Replications: %d" % [child_probe.probe_id, child_probe.generation, parent_probe.probe_id, str(child_probe.global_position.round()), total_replications])

		# Play replication sound
		var audio_manager_node = get_node_or_null("/root/AudioManager")
		if audio_manager_node and audio_manager_node.has_method("play_sound_at_position"):
			audio_manager_node.play_sound_at_position("replication", parent_probe.global_position)
		elif audio_manager_node:
			printerr("SimulationManager: AudioManager found, but no play_sound_at_position method for replication sound.")
		# else: printerr("SimulationManager: AudioManager not found for replication sound.")

		# Instantiate and play replication effect
		# if replication_effect_scene and get_node_or_null("/root/Main/ParticleManager"): # Check for ParticleManager
		#	 var effect_instance = replication_effect_scene.instantiate()
		#	 var particle_mgr = get_node("/root/Main/ParticleManager")
		#	 particle_mgr.add_child(effect_instance) # Add to a dedicated manager or main scene
		#	 if effect_instance.has_method("play_effect"):
		#		 effect_instance.play_effect(parent_probe.global_position)
		#	 else:
		#		 effect_instance.global_position = parent_probe.global_position # Fallback
		# elif replication_effect_scene: # Check if scene is loaded before printing error about ParticleManager
		#	 printerr("SimulationManager: ReplicationEffect scene loaded, but ParticleManager not found at /root/Main/ParticleManager.")
		# elif FileAccess.file_exists("res://effects/ReplicationEffect.tscn"): # If scene not loaded but file exists
		#	 printerr("SimulationManager: ReplicationEffect.tscn exists but failed to preload. ParticleManager not checked.")
		# else: # If file doesn't even exist
		#	 print_debug("SimulationManager: ReplicationEffect.tscn not found, visual effect skipped.")


	else:
		printerr("SimulationManager: ProbeManager not found, cannot add child probe to scene.")
		child_probe.queue_free() # Clean up

# --- UI Integration Functions ---

func _connect_ui_signals():
	if not is_instance_valid(modern_ui):
		printerr("ModernUI instance not found, cannot connect signals.")
		return
	
	if modern_ui.has_signal("probe_selected"):
		modern_ui.probe_selected.connect(_on_ui_probe_selected)
	else:
		printerr("ModernUI does not have signal 'probe_selected'")
		
	if modern_ui.has_signal("simulation_speed_changed"):
		modern_ui.simulation_speed_changed.connect(_on_ui_simulation_speed_changed)
	else:
		printerr("ModernUI does not have signal 'simulation_speed_changed'")
		
	if modern_ui.has_signal("ui_action_requested"):
		modern_ui.ui_action_requested.connect(_on_ui_action_requested)
	else:
		printerr("ModernUI does not have signal 'ui_action_requested'")

func _update_ui_data(): # This replaces the old update_ui_data
	if not is_instance_valid(modern_ui):
		return

	var simulation_data = _gather_simulation_data_for_ui()
	modern_ui.update_ui_data(simulation_data)

func _gather_simulation_data_for_ui() -> Dictionary:
	var probes_list_data = {}
	if is_instance_valid(probe_manager):
		for i in range(probe_manager.get_child_count()):
			var probe_node = probe_manager.get_child(i)
			if probe_node is ProbeUnit: 
				var p_id_str = ""
				if probe_node.has("probe_id"): # Ensure probe_id property exists
					p_id_str = probe_node.probe_id
				
				var p_id_int = -1
				if typeof(p_id_str) == TYPE_STRING and p_id_str.begins_with("ProbeUnit-"):
					var id_part = p_id_str.trim_prefix("ProbeUnit-")
					if id_part.is_valid_integer():
						p_id_int = id_part.to_int()
				
				if p_id_int != -1: 
					probes_list_data[p_id_int] = {
						"energy": probe_node.current_energy if probe_node.has("current_energy") else 0.0,
						"max_energy": probe_node.max_energy if probe_node.has("max_energy") and probe_node.max_energy > 0 else 1.0,
						"is_alive": probe_node.is_alive if probe_node.has("is_alive") else false
					}

	var selected_probe_data_dict = null
	if is_instance_valid(_current_selected_probe_node):
		if _current_selected_probe_node.has_method("get_details_for_ui"):
			selected_probe_data_dict = _current_selected_probe_node.get_details_for_ui()
		else: 
			var p_id_str = _current_selected_probe_node.probe_id if _current_selected_probe_node.has("probe_id") else ""
			var p_id_int = -1
			if typeof(p_id_str) == TYPE_STRING and p_id_str.begins_with("ProbeUnit-"):
				var id_part = p_id_str.trim_prefix("ProbeUnit-")
				if id_part.is_valid_integer():
					p_id_int = id_part.to_int()
			
			var velocity_vec = Vector2.ZERO
			if _current_selected_probe_node.has_method("get_linear_velocity"): # For RigidBody2D/3D
				velocity_vec = _current_selected_probe_node.get_linear_velocity()
			elif _current_selected_probe_node.has("linear_velocity"): # Property access
				velocity_vec = _current_selected_probe_node.linear_velocity
			elif _current_selected_probe_node.has("velocity"): # Fallback for CharacterBody or custom
				velocity_vec = _current_selected_probe_node.velocity


			selected_probe_data_dict = {
				"id": p_id_int if p_id_int != -1 else p_id_str,
				"generation": _current_selected_probe_node.generation if _current_selected_probe_node.has("generation") else 0,
				"position": _current_selected_probe_node.global_position,
				"velocity": velocity_vec,
				"task": _current_selected_probe_node.get_current_task_name() if _current_selected_probe_node.has_method("get_current_task_name") else "Unknown",
				"target": str(_current_selected_probe_node.get_current_target_id()) if _current_selected_probe_node.has_method("get_current_target_id") else "None",
				"status": "Alive" if (_current_selected_probe_node.has("is_alive") and _current_selected_probe_node.is_alive) else "Dead",
				"energy": _current_selected_probe_node.current_energy if _current_selected_probe_node.has("current_energy") else 0.0,
				"max_energy": _current_selected_probe_node.max_energy if _current_selected_probe_node.has("max_energy") and _current_selected_probe_node.max_energy > 0 else 1.0,
				"ai_enabled": _current_selected_probe_node.is_ai_enabled() if _current_selected_probe_node.has_method("is_ai_enabled") else true
			}

	var stats_data = {
		"episode": current_episode,
		"step": current_step,
		"fps": Performance.get_monitor(0), # TIME_FPS
		"probe_count": probe_manager.get_child_count() if is_instance_valid(probe_manager) else 0,
		"resources_mined": total_resources_mined,
		"active_resources": resource_manager.get_child_count() if is_instance_valid(resource_manager) else 0,
		"sim_speed": simulation_speed
	}

	var static_mem_bytes = OS.get_static_memory_usage()
	var virtual_mem_val = Performance.get_monitor(7) # Performance.MEMORY_VIRTUAL
	var total_mem_bytes = static_mem_bytes
	if virtual_mem_val != null and typeof(virtual_mem_val) != TYPE_NIL: # Check if monitor returns a valid value
		total_mem_bytes += int(virtual_mem_val) # Ensure it's an int before adding
		
	var physics_time_us = Performance.get_monitor(2) # TIME_PHYSICS_PROCESS
	var physics_time_ms = 0.0
	if physics_time_us != null and typeof(physics_time_us) != TYPE_NIL:
		physics_time_ms = float(physics_time_us) / 1000.0
		
	var process_time_us = Performance.get_monitor(1) # TIME_PROCESS
	var render_time_ms = 0.0
	if process_time_us != null and typeof(process_time_us) != TYPE_NIL:
		render_time_ms = float(process_time_us) / 1000.0

	var debug_data = {
		"memory_mb": float(total_mem_bytes) / (1024.0 * 1024.0), # In bytes, convert to MB
		"physics_time_ms": physics_time_ms,
		"render_time_ms": render_time_ms, # Using process time as a proxy for render/frame time
		"ai_time_ms": 0.0, # Placeholder for now
		"particle_count": get_node_or_null("../ParticleManager").get_active_particle_count() if get_node_or_null("../ParticleManager") and get_node_or_null("../ParticleManager").has_method("get_active_particle_count") else 0,
		"node_count": get_tree().get_node_count()
	}
	
	# The ProjectSettings checks for debug_cpu_time_enabled are generally for enabling more detailed timers,
	# but TIME_PROCESS should usually be available. The direct use of monitor(1) above handles this.

	return {
		"probes": probes_list_data,
		"selected_probe": selected_probe_data_dict,
		"stats": stats_data,
		"debug_info": debug_data
	}

func _get_probe_by_int_id(probe_int_id: int) -> ProbeUnit:
	if not is_instance_valid(probe_manager):
		return null
	var target_probe_id_str = "ProbeUnit-" + str(probe_int_id)
	for child in probe_manager.get_children():
		if child is ProbeUnit and child.has("probe_id") and child.probe_id == target_probe_id_str:
			return child
	# printerr("ProbeUnit with int_id %d (string: %s) not found." % [probe_int_id, target_probe_id_str]) # Can be noisy
	return null

# --- UI Signal Handlers ---

func _on_ui_probe_selected(probe_int_id: int):
	# print("UI selected probe with int_id: %d" % probe_int_id) # Can be noisy
	var probe_node = _get_probe_by_int_id(probe_int_id)
	if is_instance_valid(probe_node):
		_current_selected_probe_node = probe_node
		if is_instance_valid(camera_controller) and camera_controller.has_method("set_target_node"):
			camera_controller.set_target_node(probe_node)
		
		if is_instance_valid(modern_ui):
			var detailed_data
			if probe_node.has_method("get_details_for_ui"):
				detailed_data = probe_node.get_details_for_ui()
			else: 
				var p_id_str = probe_node.probe_id if probe_node.has("probe_id") else ""
				var p_id_int_ui = -1
				if typeof(p_id_str) == TYPE_STRING and p_id_str.begins_with("ProbeUnit-"):
					var id_part = p_id_str.trim_prefix("ProbeUnit-")
					if id_part.is_valid_integer():
						p_id_int_ui = id_part.to_int()

				var velocity_vec = Vector2.ZERO
				if probe_node.has_method("get_linear_velocity"):
					velocity_vec = probe_node.get_linear_velocity()
				elif probe_node.has("linear_velocity"):
					velocity_vec = probe_node.linear_velocity
				elif probe_node.has("velocity"):
					velocity_vec = probe_node.velocity

				detailed_data = {
					"id": p_id_int_ui if p_id_int_ui != -1 else p_id_str,
					"generation": probe_node.generation if probe_node.has("generation") else 0,
					"position": probe_node.global_position,
					"velocity": velocity_vec,
					"task": probe_node.get_current_task_name() if probe_node.has_method("get_current_task_name") else "Unknown",
					"target": str(probe_node.get_current_target_id()) if probe_node.has_method("get_current_target_id") else "None",
					"status": "Alive" if (probe_node.has("is_alive") and probe_node.is_alive) else "Dead",
					"energy": probe_node.current_energy if probe_node.has("current_energy") else 0.0,
					"max_energy": probe_node.max_energy if probe_node.has("max_energy") and probe_node.max_energy > 0 else 1.0,
					"ai_enabled": probe_node.is_ai_enabled() if probe_node.has_method("is_ai_enabled") else true
				}
			modern_ui.update_selected_probe_info(detailed_data)
	else:
		_current_selected_probe_node = null
		if is_instance_valid(modern_ui): 
			modern_ui.update_selected_probe_info(null)


func _on_ui_simulation_speed_changed(new_speed: float):
	simulation_speed = new_speed
	Engine.time_scale = simulation_speed
	print("Simulation speed changed to: %f" % new_speed)

func _on_ui_action_requested(action_type: String, data: Dictionary):
	print("UI action requested: %s, Data: %s" % [action_type, str(data)])
	match action_type:
		"toggle_pause":
			_toggle_pause()
		"reset_episode":
			_reset_simulation()
		"quick_save":
			_quick_save_simulation()
		"manual_thrust", "manual_rotate", "manual_replicate", "toggle_ai":
			var probe_int_id_from_data = data.get("probe_id", -1)
			var target_probe_node = null

			if probe_int_id_from_data != -1:
				target_probe_node = _get_probe_by_int_id(probe_int_id_from_data)
			elif is_instance_valid(_current_selected_probe_node): # Fallback to currently selected if no ID in data
				target_probe_node = _current_selected_probe_node
			
			if is_instance_valid(target_probe_node):
				match action_type:
					"manual_thrust":
						if target_probe_node.has_method("apply_manual_thrust"):
							target_probe_node.apply_manual_thrust()
						else:
							printerr("ProbeUnit %s has no method apply_manual_thrust" % target_probe_node.probe_id)
					"manual_rotate":
						var direction = data.get("direction", "left")
						if target_probe_node.has_method("apply_manual_rotation"):
							target_probe_node.apply_manual_rotation(direction)
						else:
							printerr("ProbeUnit %s has no method apply_manual_rotation" % target_probe_node.probe_id)
					"manual_replicate":
						if target_probe_node.has_method("initiate_replication"):
							target_probe_node.initiate_replication()
						else:
							printerr("ProbeUnit %s has no method initiate_replication" % target_probe_node.probe_id)
					"toggle_ai":
						var enabled = data.get("enabled", true)
						if target_probe_node.has_method("set_ai_enabled"):
							target_probe_node.set_ai_enabled(enabled)
						else:
							printerr("ProbeUnit %s has no method set_ai_enabled" % target_probe_node.probe_id)
			else:
				var id_for_error = probe_int_id_from_data if probe_int_id_from_data != -1 else "currently selected (none or invalid)"
				printerr("No valid probe found for action %s (ID: %s)" % [action_type, str(id_for_error)])
		_:
			printerr("Unknown UI action type: %s" % action_type)

# --- Simulation Control Methods ---

func _toggle_pause():
	is_paused = not is_paused
	get_tree().paused = is_paused 
	print("Simulation " + ("paused" if is_paused else "resumed"))

func _reset_simulation():
	print("Resetting simulation...")
	current_episode += 1
	current_step = 0
	is_paused = false
	get_tree().paused = false
	Engine.time_scale = simulation_speed 
	
	_clear_simulation_state_for_reset()
	
	initialize_simulation() 
	
	_update_ui_data() 
	print("Simulation reset complete. Episode: %d" % current_episode)

func _clear_simulation_state_for_reset():
	# Clear dynamic nodes
	if is_instance_valid(probe_manager):
		for child in probe_manager.get_children():
			child.queue_free()
	if is_instance_valid(resource_manager):
		for child in resource_manager.get_children():
			child.queue_free()
	if is_instance_valid(solar_system): 
		for child in solar_system.get_children():
			if child.is_in_group("celestial_bodies"): 
				child.queue_free() # This will remove Sun, planets, moons

	# Reset internal state variables
	_current_selected_probe_node = null
	communication_log.clear()
	discovered_resources_log.clear()
	_discovered_resource_ids.clear()
	
	# Reset resource stats (will be re-initialized by initialize_resources)
	total_initial_resources_value = 0.0
	current_total_resources_value = 0.0
	resources_by_type_count = {}
	discovered_resources_count = 0
	depleted_resources_count = 0
	total_resources_mined = 0.0
	total_replications = 0
	# current_episode and current_step are handled by _reset_simulation directly

func _quick_save_simulation():
	print("Quick save requested.")
	var save_load_manager = get_node_or_null("/root/SaveLoadManager") 
	if save_load_manager and save_load_manager.has_method("save_game_state"):
		var game_state_data = create_save_data() 
		var success = save_load_manager.save_game_state("quicksave.sav", game_state_data)
		if success:
			print("Quick save successful via SaveLoadManager.")
		else:
			printerr("Quick save failed via SaveLoadManager.")
	else:
		printerr("SaveLoadManager not found or no save_game_state method.")


func _quick_load_simulation():
	print("Quick load requested.")
	var save_load_manager = get_node_or_null("/root/SaveLoadManager")
	if save_load_manager and save_load_manager.has_method("load_game_state"):
		var loaded_data = save_load_manager.load_game_state("quicksave.sav")
		if loaded_data:
			_clear_simulation_state_for_reset() # Use the same clearing logic as reset before loading
			load_simulation(loaded_data) # load_simulation should apply the data
			# After loading, ensure simulation state variables like is_paused, Engine.time_scale are correctly set
			# This might need to be part of load_simulation or handled here based on loaded_data
			is_paused = get_tree().paused # Sync with tree state if load_simulation changes it
			Engine.time_scale = simulation_speed # Ensure sim speed is from loaded data or default
			_update_ui_data() 
			print("Quick load successful via SaveLoadManager. Data applied.")
		else:
			printerr("Failed to load quicksave.sav via SaveLoadManager or no data returned.")
	else:
		printerr("SaveLoadManager not found or no load_game_state method.")

# Note: The _clear_for_load function was removed as _clear_simulation_state_for_reset serves a similar purpose.
# Ensure that load_simulation correctly restores all necessary states including current_episode, current_step, simulation_speed, is_paused.
# If SimulationSaveData stores these, load_simulation should apply them.


# --- Stress Test Functionality ---

func trigger_stress_test(num_probes_to_add: int, num_resources_to_add: int):
	print_rich("[color=orange]Starting Stress Test: Adding %d probes and %d resources.[/color]" % [num_probes_to_add, num_resources_to_add])
	
	if num_probes_to_add > 0:
		_spawn_additional_probes(num_probes_to_add)
	if num_resources_to_add > 0:
		_spawn_additional_resources(num_resources_to_add)
		
	print_rich("[color=orange]Stress Test: Spawning complete.[/color]")
	# Force UI update to reflect new counts if needed immediately
	_update_ui_data()

func _spawn_additional_probes(count: int):
	if not is_instance_valid(probe_manager) or not is_instance_valid(probe_scene):
		printerr("Stress Test: ProbeManager or ProbeScene not available. Cannot spawn additional probes.")
		return

	var config = ConfigManager.config if ConfigManager else null
	var world_radius_sim_units = (config.world_size_au * config.au_scale if config else 10.0 * 10000.0) * 0.8 # Spawn within 80% of world radius

	print("Stress Test: Spawning %d additional probes..." % count)
	for i in range(count):
		var probe_instance = probe_scene.instantiate() as ProbeUnit
		if not probe_instance:
			printerr("Stress Test: Failed to instantiate probe_scene for additional probe %d." % i)
			continue

		var random_angle = randf_range(0, TAU)
		var random_dist_factor = randf_range(0.05, 1.0) # Avoid exact center
		var random_dist = world_radius_sim_units * sqrt(random_dist_factor) # sqrt for more uniform distribution
		probe_instance.global_position = Vector2(cos(random_angle), sin(random_angle)) * random_dist
		
		probe_instance.probe_id = "StressProbe-G0-%s" % OS.get_unique_id().substr(0,4)
		probe_instance.generation = 0 # Stress test probes are generation 0 for simplicity

		probe_manager.add_child(probe_instance)
		connect_probe_signals(probe_instance)
	print("Stress Test: Finished spawning %d additional probes." % count)

func _spawn_additional_resources(count: int):
	if not is_instance_valid(resource_manager) or not is_instance_valid(resource_scene):
		printerr("Stress Test: ResourceManager or ResourceScene not available. Cannot spawn additional resources.")
		return

	var config = ConfigManager.config if ConfigManager else null
	if not config:
		printerr("Stress Test: ConfigManager.config not available for resource spawning parameters.")
		return

	# Assuming config is an instance of GameConfiguration resource
	var world_size_au = config.world_size_au
	var au_scale = config.au_scale
	var resource_amount_range = config.resource_amount_range
	var resource_regen_rate = config.resource_regen_rate
	
	var world_radius_sim_units = world_size_au * au_scale
	var resource_types = ["mineral", "energy", "rare_earth", "water"] # Match initialize_resources
	var placement_attempts = 5 # Reduced attempts for stress test spawning
	var collision_buffer = 50.0

	print("Stress Test: Spawning %d additional resources..." % count)
	var spawned_count = 0
	for i in range(count):
		var resource_instance = resource_scene.instantiate() as GameResource
		var placed = false
		
		for attempt in range(placement_attempts):
			var random_angle = randf_range(0, TAU)
			var random_radius_factor = randf_range(0.1, 1.0)
			var random_dist = world_radius_sim_units * sqrt(random_radius_factor)
			var proposed_position = Vector2(cos(random_angle), sin(random_angle)) * random_dist
			
			var collision = false
			var celestial_bodies = get_tree().get_nodes_in_group("celestial_bodies")
			for body in celestial_bodies:
				if not is_instance_valid(body) or not body.has("display_radius"): continue
				if proposed_position.distance_to(body.global_position) < (body.display_radius + collision_buffer):
					collision = true
					break
			
			if not collision:
				resource_instance.global_position = proposed_position
				placed = true
				break
		
		if not placed:
			resource_instance.queue_free()
			continue

		var current_amount = randf_range(resource_amount_range.x, resource_amount_range.y)
		resource_instance.current_amount = current_amount
		resource_instance.max_amount = current_amount
		resource_instance.resource_type = resource_types[randi() % resource_types.size()]
		resource_instance.regeneration_rate = resource_regen_rate

		resource_manager.add_child(resource_instance)
		if resource_instance.has_signal("resource_depleted"):
			resource_instance.resource_depleted.connect(_on_resource_depleted.bind(resource_instance))
		if resource_instance.has_signal("resource_harvested"):
			resource_instance.resource_harvested.connect(_on_resource_harvested.bind(resource_instance))
		spawned_count += 1

	print("Stress Test: Finished spawning %d additional resources (attempted %d)." % [spawned_count, count])
	# Note: _initialize_resource_stats() is not called here to avoid resetting existing stats.
	# If stress test resources should be part of the main stats, this needs adjustment or a separate tracking.
	# For now, they are just added to the simulation.
