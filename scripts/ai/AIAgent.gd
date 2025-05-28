extends Node

class_name AIAgent

const MessageData = preload("res://scripts/data/MessageData.gd") # Added for message types

# Exported variables for configuration
@export var use_external_ai: bool = false
@export var ai_server_url: String = "http://localhost:8000/predict" # Default URL for the external AI server
@export var update_frequency: float = 1.0 # Time in seconds between AI updates

# Member variables
var parent_probe: Node # Reference to the ProbeUnit this agent controls
var http_request: HTTPRequest
var current_observation: Dictionary = {}
var current_action: Array = [] # This will be the 5-element array
var last_reward: float = 0.0
var episode_step: int = 0
var current_rotation_direction: int = 0 # -1 for left, 1 for right, 0 for none. Set by decode_action_index.
var _ai_debug_logging_enabled: bool = false
# Performance Profiling
var _time_obs_gather_usec: int = 0
var _time_ai_decision_usec: int = 0
var _time_action_apply_usec: int = 0
var _avg_time_obs_gather_usec: float = 0.0
var _avg_time_ai_decision_usec: float = 0.0
var _avg_time_action_apply_usec: float = 0.0
var _profiling_sample_count: int = 0
const PROFILING_AVG_WINDOW: int = 100 # Average over 100 samples

# State for reward calculation
var previously_mining_target_id: String = ""
var steps_since_significant_action: int = 0
var last_known_position: Vector2 = Vector2.ZERO
var last_known_energy_ratio: float = 0.0
var last_known_stored_resources: float = 0.0
var debug_rewards: bool = false # Set to true to print reward breakdown

@onready var _config_manager_instance = get_node_or_null("/root/ConfigManager")

var q_learning: SimpleQLearning
var last_state_hash: String = ""
var action_timer: float = 0.0
var pending_action: bool = false # To prevent multiple requests if one is ongoing

# Action space parameters
var num_thrust_levels: int = 0
var num_torque_levels: int = 0
var calculated_action_space_size: int = 0

# Signals
signal action_received(action)
signal reward_calculated(reward)

# Constants for 5-element action array: [thrust_level_idx, torque_level_idx, communicate_flag, replicate_flag, target_resource_idx]
const ACTION_THRUST_LEVEL_INDEX = 0
const ACTION_TORQUE_LEVEL_INDEX = 1
const ACTION_COMMUNICATE_INDEX = 2
const ACTION_REPLICATE_INDEX = 3
const ACTION_TARGET_RESOURCE_INDEX = 4
const ACTION_ARRAY_SIZE = 5


func _ready():
	if not _config_manager_instance:
		printerr("ConfigManager (Autoload) at path '/root/ConfigManager' not found in AIAgent.gd _ready(). AI functionality may be impaired.")
	# The original check for _config_manager_instance can remain or be removed if the above printerr is sufficient.
	# For now, let's keep it to ensure subsequent logic that relies on it still works if it *is* null.
	if _config_manager_instance:
		# AI Settings
		self.update_frequency = _config_manager_instance.get_setting("general", "ai_update_interval_sec", 1.0)
		self._ai_debug_logging_enabled = _config_manager_instance.get_setting("general", "ai_debug_logging", false)
		
		# HTTPRequest timeout (moved up for clarity with other config reads)
		if use_external_ai:
			http_request = HTTPRequest.new()
			add_child(http_request)
			http_request.timeout = _config_manager_instance.get_setting("general", "ai_request_timeout", 5.0) # Assuming this key exists or will be added
			http_request.request_completed.connect(_on_ai_response_received)

		# Action space parameters
		var thrust_magnitudes = _config_manager_instance.get_setting("general", "thrust_force_magnitudes", [0.0, 100.0])
		num_thrust_levels = thrust_magnitudes.size()
		
		var torque_magnitudes = _config_manager_instance.get_setting("general", "torque_magnitudes", [0.0, 50.0])
		num_torque_levels = torque_magnitudes.size()
	else:
		printerr("AIAgent: ConfigManager instance not found in _ready. Using default values for AI settings and action space.")
		# Default values if ConfigManager is not available
		self.update_frequency = 1.0 # Default if not loaded
		self._ai_debug_logging_enabled = false # Default if not loaded
		num_thrust_levels = 2 # Off, On
		num_torque_levels = 2 # Off, On
		if use_external_ai: # Fallback for http_request if ConfigManager was missing
			http_request = HTTPRequest.new()
			add_child(http_request)
			http_request.timeout = 5.0
			http_request.request_completed.connect(_on_ai_response_received)

	# Calculate action_space_size:
	# 1 (no-op)
	# + (num_thrust_levels - 1) for thrust actions (level 0 is no thrust)
	# + (num_torque_levels - 1) * 2 for torque actions (left/right for each non-zero magnitude)
	# + 1 for communicate
	# + 1 for replicate
	# + 1 for target_nearest_resource (simplified to target index 0 of observed)
	calculated_action_space_size = 1 # No-op
	if num_thrust_levels > 1: # Ensure there's at least one "on" level
		calculated_action_space_size += (num_thrust_levels - 1)
	if num_torque_levels > 1: # Ensure there's at least one "on" level
		calculated_action_space_size += (num_torque_levels - 1) * 2
	calculated_action_space_size += 1 # Communicate
	calculated_action_space_size += 1 # Replicate
	calculated_action_space_size += 1 # Target nearest resource

	q_learning = SimpleQLearning.new()
	add_child(q_learning) # Ensure it processes and decays epsilon
	
	var ai_config = {} # This was for a nested "ai" dictionary, direct access is better
	if _config_manager_instance:
		q_learning.learning_rate = _config_manager_instance.get_setting("general", "learning_rate", 0.1) # Assuming these are top-level in GameConfiguration
		q_learning.discount_factor = _config_manager_instance.get_setting("general", "discount_factor", 0.99)
		q_learning.epsilon = _config_manager_instance.get_setting("general", "q_epsilon_start", 1.0) # Keep specific q_epsilon if needed
		q_learning.epsilon_decay = _config_manager_instance.get_setting("general", "q_epsilon_decay", 0.001)
		q_learning.min_epsilon = _config_manager_instance.get_setting("general", "q_epsilon_min", 0.01)
		# For persistence
		q_learning.save_on_end = _config_manager_instance.get_setting("general", "q_learning_save_on_episode_end", true)
		q_learning.load_on_start = _config_manager_instance.get_setting("general", "q_learning_load_on_episode_start", true)
		q_learning.table_filename = _config_manager_instance.get_setting("general", "q_learning_table_filename", "q_table_fallback.json")
	else: # Fallbacks if ConfigManager is missing
		q_learning.learning_rate = 0.1
		q_learning.discount_factor = 0.99
		q_learning.epsilon = 1.0
		q_learning.epsilon_decay = 0.001
		q_learning.min_epsilon = 0.01
		q_learning.save_on_end = true
		q_learning.load_on_start = true
		q_learning.table_filename = "q_table_fallback.json"
		
	q_learning.set_action_space_size(calculated_action_space_size)
	
	if _ai_debug_logging_enabled:
		print("AIAgent: Initialized. Update Freq: ", self.update_frequency, "s. Action Space Size: ", calculated_action_space_size)
		print("AIAgent: Q-Learning params: LR=", q_learning.learning_rate, ", DF=", q_learning.discount_factor, ", EpsilonStart=", q_learning.epsilon)
		print("AIAgent: Q-Learning persistence: Load=", q_learning.load_on_start, ", Save=", q_learning.save_on_end, ", File=", q_learning.table_filename)


func initialize(probe: Node):
	parent_probe = probe
	episode_step = 0
	last_reward = 0.0
	current_observation = {}
	current_action = [] # Reset to empty or default
	last_state_hash = ""
	action_timer = 0.0
	pending_action = false
	previously_mining_target_id = ""
	steps_since_significant_action = 0
	if parent_probe and parent_probe.is_instance_valid():
		last_known_position = parent_probe.global_position
		if parent_probe.has_method("get_observation_data"): # Get initial energy/resources
			var initial_obs_for_reward_state = parent_probe.get_observation_data()
			last_known_energy_ratio = initial_obs_for_reward_state.get("energy_ratio", 0.0)
			last_known_stored_resources = initial_obs_for_reward_state.get("stored_resources", 0.0)
	else:
		last_known_position = Vector2.ZERO
		last_known_energy_ratio = 0.0
		last_known_stored_resources = 0.0


	if not parent_probe:
		printerr("AIAgent: Parent probe not set during initialization!")
		return

	# Connect to probe signals for reward calculation
	if parent_probe.has_signal("resource_discovered"):
		parent_probe.resource_discovered.connect(_on_resource_discovered) # Expects (probe, resource_data: Dictionary)
	else:
		printerr("AIAgent: Probe is missing 'resource_discovered' signal.")
	
	# Remove energy_critical signal connection as it's handled in calculate_reward directly
	# if parent_probe.has_signal("energy_critical"):
	# 	parent_probe.energy_critical.connect(_on_energy_critical)
	# else:
	# 	printerr("AIAgent: Probe is missing 'energy_critical' signal.")

	# TODO: Connect to probe's collision signal if implemented
	# if parent_probe.has_signal("collision_occurred"):
	# 	parent_probe.collision_occurred.connect(_on_collision_occurred) # Needs _on_collision_occurred method
	
	# Initial observation
	if parent_probe.has_method("get_observation_data"):
		current_observation = parent_probe.get_observation_data()
		last_state_hash = hash_observation(current_observation)
	else:
		printerr("AIAgent: Parent probe does not have 'get_observation_data' method.")


func update_step(delta: float):
	if not parent_probe or not parent_probe.is_instance_valid() or not parent_probe.is_alive:
		return

	action_timer += delta
	if action_timer >= update_frequency:
		action_timer = 0.0
		if not pending_action:
			request_action()

func request_action():
	if not parent_probe or not parent_probe.is_instance_valid() or not parent_probe.has_method("get_observation_data"):
		printerr("AIAgent: Cannot request action, parent probe or get_observation_data missing.")
		return

	var start_obs_time = Time.get_ticks_usec()
	current_observation = parent_probe.get_observation_data()
	_time_obs_gather_usec = Time.get_ticks_usec() - start_obs_time
	_update_average_timing(_time_obs_gather_usec, "_avg_time_obs_gather_usec")

	# Decision time will be measured within the respective functions
	if use_external_ai and http_request:
		request_external_action()
	else:
		request_builtin_action()

func request_external_action():
	if pending_action:
		return
	pending_action = true
	
	var start_decision_time = Time.get_ticks_usec() # Moved here

	var flat_observation = flatten_observation(current_observation)
	
	var expected_obs_size = -1
	if _config_manager_instance:
		expected_obs_size = _config_manager_instance.get_setting("general", "observation_space_size", -1)
		
	if expected_obs_size != -1: 
		if flat_observation.size() != expected_obs_size:
			printerr("AIAgent: MISMATCH in observation size! Actual: ", flat_observation.size(), ", Expected: ", expected_obs_size, " Array: ", flat_observation)

	var body = JSON.stringify({"observation": flat_observation, "last_reward": last_reward, "episode_step": episode_step})
	var headers = ["Content-Type: application/json"]
	
	var error = http_request.request(ai_server_url, headers, HTTPClient.METHOD_POST, body)
	# Note: _time_ai_decision_usec for external AI will be more complex as it's async.
	# The time measured here is just for initiating the request.
	# A more accurate measure would be from request start to _on_ai_response_received.
	# For now, this captures the local part of starting the decision.
	_time_ai_decision_usec = Time.get_ticks_usec() - start_decision_time
	_update_average_timing(_time_ai_decision_usec, "_avg_time_ai_decision_usec")

	if error != OK:
		printerr("AIAgent: HTTP request failed immediately. Error code: ", error, ". Falling back to built-in AI.")
		pending_action = false
		# If falling back, the decision time for built-in will be captured by that call.
		request_builtin_action()

func flatten_observation(obs: Dictionary) -> Array:
	var flat_obs = []
	var obs_space_size = 25 # Default
	if _config_manager_instance:
		obs_space_size = _config_manager_instance.get_setting("general", "observation_space_size", 25)

	var world_bounds_x = 10000.0
	var world_bounds_y = 10000.0
	var max_probe_speed = 1000.0
	var max_probe_angular_vel = PI
	var num_observed_resources = 3
	var max_res_dist_norm = 1000.0
	var max_res_amount_norm = 20000.0
	var num_observed_celestial_bodies = 2
	var max_celestial_dist_norm = 10000.0
	var celestial_mass_norm_factor = 1e24
	var max_gravity_influence_norm = 0.01

	if _config_manager_instance:
		world_bounds_x = _config_manager_instance.get_setting("general", "world_bounds_x", 10000.0)
		world_bounds_y = _config_manager_instance.get_setting("general", "world_bounds_y", 10000.0)
		max_probe_speed = _config_manager_instance.get_setting("general", "max_probe_speed_for_norm", 1000.0)
		max_probe_angular_vel = _config_manager_instance.get_setting("general", "max_probe_angular_vel_for_norm", PI)
		num_observed_resources = _config_manager_instance.get_setting("general", "num_observed_resources", 3)
		max_res_dist_norm = _config_manager_instance.get_setting("general", "max_resource_distance_for_norm", 1000.0)
		max_res_amount_norm = _config_manager_instance.get_setting("general", "max_resource_amount_for_norm", 20000.0)
		num_observed_celestial_bodies = _config_manager_instance.get_setting("general", "num_observed_celestial_bodies", 2)
		max_celestial_dist_norm = _config_manager_instance.get_setting("general", "max_celestial_distance_for_norm", 10000.0)
		celestial_mass_norm_factor = _config_manager_instance.get_setting("general", "celestial_mass_norm_factor", 1e24)
		max_gravity_influence_norm = _config_manager_instance.get_setting("general", "max_gravity_influence_for_norm", 0.01)

	var probe_pos = obs.get("position", Vector2.ZERO)
	flat_obs.append(probe_pos.x / world_bounds_x)
	flat_obs.append(probe_pos.y / world_bounds_y)
	var probe_vel = obs.get("velocity", Vector2.ZERO)
	flat_obs.append(probe_vel.x / max_probe_speed)
	flat_obs.append(probe_vel.y / max_probe_speed)
	flat_obs.append(fposmod(obs.get("rotation", 0.0), 2 * PI) / (2 * PI))
	flat_obs.append(obs.get("angular_velocity", 0.0) / max_probe_angular_vel)
	flat_obs.append(obs.get("energy_ratio", 0.0))

	var nearby_resources = obs.get("nearby_resources", [])
	for i in range(num_observed_resources):
		if i < nearby_resources.size():
			var resource = nearby_resources[i]
			var res_pos = resource.get("position", Vector2.ZERO)
			flat_obs.append(res_pos.x / world_bounds_x)
			flat_obs.append(res_pos.y / world_bounds_y)
			flat_obs.append(resource.get("distance", max_res_dist_norm) / max_res_dist_norm)
			flat_obs.append(resource.get("amount", 0.0) / max_res_amount_norm)
		else:
			flat_obs.append_array([0.0, 0.0, 1.0, 0.0])

	var nearby_celestial_bodies = obs.get("nearby_celestial_bodies", [])
	for i in range(num_observed_celestial_bodies):
		if i < nearby_celestial_bodies.size():
			var body = nearby_celestial_bodies[i]
			flat_obs.append(body.get("distance", max_celestial_dist_norm) / max_celestial_dist_norm)
			flat_obs.append(body.get("gravity_influence", 0.0) / max_gravity_influence_norm)
			flat_obs.append(body.get("mass", 0.0) / celestial_mass_norm_factor)
		else:
			flat_obs.append_array([1.0, 0.0, 0.0])

	while flat_obs.size() < obs_space_size:
		flat_obs.append(0.0)
	if flat_obs.size() > obs_space_size:
		flat_obs = flat_obs.slice(0, obs_space_size)
	return flat_obs

func request_builtin_action():
	if not parent_probe or not parent_probe.is_instance_valid():
		printerr("AIAgent: Built-in action requested, but parent probe is invalid.")
		return

	var start_decision_time = Time.get_ticks_usec() # Moved here (was already here, but confirming)
	var state_hash = hash_observation(current_observation)
	var action_index = q_learning.get_action(state_hash)
	current_action = decode_action_index(action_index)
	_time_ai_decision_usec = Time.get_ticks_usec() - start_decision_time
	_update_average_timing(_time_ai_decision_usec, "_avg_time_ai_decision_usec")
	
	if _ai_debug_logging_enabled and parent_probe and parent_probe.has_get("probe_id"):
		print("Probe %s (Built-in AI): Step %d, State: %s, Action Index: %d (%s), Epsilon: %.4f, QTable Size: %d, DecisionTime: %.3fms" % [parent_probe.get("probe_id"), episode_step, state_hash, action_index, _action_to_string(current_action), q_learning.epsilon, q_learning.q_table.size(), _time_ai_decision_usec / 1000.0])
	
	apply_action(current_action) # apply_action will record its own time
	
	var reward = calculate_reward() # Calculate reward AFTER action is applied and state potentially changes
	
	if _ai_debug_logging_enabled and parent_probe and parent_probe.has_get("probe_id"):
		print("Probe %s (Built-in AI): Action applied, Reward: %.4f" % [parent_probe.get("probe_id"), reward])

	var next_observation_data = parent_probe.get_observation_data() # Get new state
	var next_state_hash = hash_observation(next_observation_data) # next_observation_data should be passed here
	q_learning.update_q_value(state_hash, action_index, reward, next_state_hash)
	
	if _ai_debug_logging_enabled and parent_probe and parent_probe.has_get("probe_id"):
		print("Probe %s (Built-in AI): Q-Update: PrevS: %s, A: %d, R: %.2f, NextS: %s" % [parent_probe.get("probe_id"), state_hash, action_index, reward, next_state_hash])

	last_reward = reward
	last_state_hash = next_state_hash # Update last_state_hash for the next iteration
	episode_step += 1
	action_received.emit(current_action)
	reward_calculated.emit(reward)

func hash_observation(obs: Dictionary) -> String:
	# print("Hashing observation: ", obs) # For debugging state hashing input
	var parts = []
	parts.append("p%s%s" % [int(obs.get("position", Vector2.ZERO).x / 100), int(obs.get("position", Vector2.ZERO).y / 100)])
	parts.append("e%s" % [int(obs.get("energy_ratio", 0.0) * 10)]) # Use energy_ratio
	parts.append("r%s" % [int(obs.get("stored_resources", 0.0) / 10)])
	parts.append("m%s" % [1 if obs.get("is_mining_active", false) else 0]) # Use is_mining_active

	var nearby_resources_list = obs.get("nearby_resources", [])
	if not nearby_resources_list.is_empty():
		var res = nearby_resources_list[0]
		parts.append("nr%s" % [int(res.get("distance", 1000)/200)])
		parts.append("nrt%s" % [res.get("type_id", 0)])
	else:
		parts.append("nrX")
	var state_hash_str = "_".join(parts)
	# print("Observation: ", obs, " -> State Hash: ", state_hash_str) # For debugging state hashing output
	return state_hash_str


func decode_action_index(index: int) -> Array:
	# Action array: [thrust_level_idx, torque_level_idx, communicate_flag, replicate_flag, target_resource_idx]
	var action_array = [0, 0, 0, 0, -1] # Default: [no_thrust_idx, no_torque_idx, no_comm, no_repl, no_target]
	current_rotation_direction = 0 # Reset rotation direction for this action decision

	var current_decoded_action_idx = 0

	# Action 0: No-op
	if index == current_decoded_action_idx:
		return action_array
	current_decoded_action_idx += 1

	# Thrust actions: (num_thrust_levels - 1) actions
	# Thrust level index 0 is "off", so actual thrust levels start from index 1.
	if num_thrust_levels > 1:
		for i in range(1, num_thrust_levels): # Iterate for thrust_level_idx 1, 2, ... up to num_thrust_levels-1
			if index == current_decoded_action_idx:
				action_array[ACTION_THRUST_LEVEL_INDEX] = i
				return action_array
			current_decoded_action_idx += 1
	
	# Torque actions: (num_torque_levels - 1) * 2 actions
	# Torque level index 0 is "off".
	if num_torque_levels > 1:
		for i in range(1, num_torque_levels): # Iterate for torque_level_idx 1, 2, ...
			# Left Torque for magnitude index i
			if index == current_decoded_action_idx:
				action_array[ACTION_TORQUE_LEVEL_INDEX] = i
				current_rotation_direction = -1 # Left
				return action_array
			current_decoded_action_idx += 1
			# Right Torque for magnitude index i
			if index == current_decoded_action_idx:
				action_array[ACTION_TORQUE_LEVEL_INDEX] = i
				current_rotation_direction = 1 # Right
				return action_array
			current_decoded_action_idx += 1

	# Communicate action: 1 action
	if index == current_decoded_action_idx:
		action_array[ACTION_COMMUNICATE_INDEX] = 1
		return action_array
	current_decoded_action_idx += 1

	# Replicate action: 1 action
	if index == current_decoded_action_idx:
		action_array[ACTION_REPLICATE_INDEX] = 1
		return action_array
	current_decoded_action_idx += 1

	# Target nearest resource action: 1 action
	# This action will set target_resource_idx to 0, meaning "target the first resource in the observed list".
	# Probe.gd's set_target_resource_by_observed_index(0) will handle this.
	if index == current_decoded_action_idx:
		action_array[ACTION_TARGET_RESOURCE_INDEX] = 0 # Target first observed
		return action_array
	# current_decoded_action_idx += 1 # No increment needed after the last defined action type

	# Fallback if index is out of defined range
	printerr("AIAgent: decode_action_index received out-of-bounds index: ", index, " (max expected: ", calculated_action_space_size - 1, "). Returning No-Op.")
	return [0,0,0,0,-1] # Return default no-op
func _action_to_string(action: Array) -> String:
	if action.is_empty() or action.size() != ACTION_ARRAY_SIZE:
		return "InvalidAction"
	
	var parts = []
	parts.append("T%d" % action[ACTION_THRUST_LEVEL_INDEX])
	parts.append("Q%d" % action[ACTION_TORQUE_LEVEL_INDEX]) # Direction is implicit or handled by current_rotation_direction
	if action[ACTION_COMMUNICATE_INDEX] == 1:
		parts.append("Comm")
	if action[ACTION_REPLICATE_INDEX] == 1:
		parts.append("Repl")
	if action[ACTION_TARGET_RESOURCE_INDEX] != -1:
		parts.append("Target%d" % action[ACTION_TARGET_RESOURCE_INDEX])
	
	if parts.is_empty() and action[ACTION_THRUST_LEVEL_INDEX] == 0 and action[ACTION_TORQUE_LEVEL_INDEX] == 0:
		return "NoOp"
	elif parts.is_empty(): # Should not happen if NoOp is caught, but as a fallback
		return "ActionArray:" + str(action)

	return "|".join(parts)
func get_performance_metrics() -> Dictionary:
	return {
		"avg_obs_gather_ms": (_avg_time_obs_gather_usec / 1000.0) if _profiling_sample_count > 0 else 0.0,
		"avg_ai_decision_ms": (_avg_time_ai_decision_usec / 1000.0) if _profiling_sample_count > 0 else 0.0,
		"avg_action_apply_ms": (_avg_time_action_apply_usec / 1000.0) if _profiling_sample_count > 0 else 0.0,
		"current_obs_gather_ms": (_time_obs_gather_usec / 1000.0),
		"current_ai_decision_ms": (_time_ai_decision_usec / 1000.0),
		"current_action_apply_ms": (_time_action_apply_usec / 1000.0)
	}

func _update_average_timing(new_time_usec: int, avg_variable_name: String):
	# This is a bit manual due to GDScript's limitations with direct variable references by string.
	# A more complex solution might use a dictionary to hold averages if many more were added.
	var current_total_time: float
	match avg_variable_name:
		"_avg_time_obs_gather_usec":
			current_total_time = _avg_time_obs_gather_usec * _profiling_sample_count
			_avg_time_obs_gather_usec = (current_total_time + new_time_usec) / (_profiling_sample_count + 1)
		"_avg_time_ai_decision_usec":
			current_total_time = _avg_time_ai_decision_usec * _profiling_sample_count
			_avg_time_ai_decision_usec = (current_total_time + new_time_usec) / (_profiling_sample_count + 1)
		"_avg_time_action_apply_usec":
			current_total_time = _avg_time_action_apply_usec * _profiling_sample_count
			_avg_time_action_apply_usec = (current_total_time + new_time_usec) / (_profiling_sample_count + 1)

	if _profiling_sample_count >= PROFILING_AVG_WINDOW:
		# Reset window by just taking the new value as the start of a new average set
		# This provides a rolling window effect over many samples, rather than a strict reset.
		# For a strict reset, you'd set the average to new_time_usec and _profiling_sample_count to 0.
		# Let's do a simpler approach: reset and start over for simplicity.
		match avg_variable_name:
			"_avg_time_obs_gather_usec": _avg_time_obs_gather_usec = new_time_usec
			"_avg_time_ai_decision_usec": _avg_time_ai_decision_usec = new_time_usec
			"_avg_time_action_apply_usec": _avg_time_action_apply_usec = new_time_usec
		if avg_variable_name == "_avg_time_action_apply_usec": # Only reset count once per full cycle
			_profiling_sample_count = 0 
	
	if avg_variable_name == "_avg_time_action_apply_usec": # Increment only once per full cycle
		_profiling_sample_count += 1

func _on_ai_response_received(result: int, response_code: int, headers: PackedStringArray, body: PackedByteArray):
	pending_action = false
	var response_body_str = body.get_string_from_utf8()

	if result != HTTPRequest.RESULT_SUCCESS:
		printerr("AIAgent: HTTP request failed. Result code: ", result, ". Falling back to built-in AI.")
		request_builtin_action()
		return
	
	if response_code != 200:
		printerr("AIAgent: AI server returned non-200 response. Code: ", response_code, ". Body: ", response_body_str, ". Falling back to built-in AI.")
		request_builtin_action()
		return

	var parse_result = JSON.parse_string(response_body_str)
	if parse_result == null:
		printerr("AIAgent: Failed to parse JSON response from AI server. Response: ", response_body_str, ". Falling back to built-in AI.")
		request_builtin_action()
		return
		
	var json_data = parse_result
	if not typeof(json_data) == TYPE_DICTIONARY or not json_data.has("action"):
		printerr("AIAgent: Invalid or missing 'action' key in JSON response. Parsed: ", json_data, ". Falling back to built-in AI.")
		request_builtin_action()
		return

	current_action = json_data["action"]
	if not typeof(current_action) == TYPE_ARRAY:
		printerr("AIAgent: 'action' field in JSON is not an array. Received: ", current_action, ". Falling back to built-in AI.")
		request_builtin_action()
		return
	if current_action.size() != ACTION_ARRAY_SIZE:
		printerr("AIAgent: External AI action array size mismatch. Expected %d, got %d. Action: %s. Falling back." % [ACTION_ARRAY_SIZE, current_action.size(), str(current_action)])
		request_builtin_action() # Fallback if action structure is wrong
		return
		
	apply_action(current_action)
	
	if _ai_debug_logging_enabled and parent_probe and parent_probe.has_get("probe_id"):
		var external_ai_initiation_time_ms = _time_ai_decision_usec / 1000.0
		var obs_summary = "Obs(size:%d)" % flatten_observation(current_observation).size() if current_observation else "Obs(nil)"
		print("Probe %s (Ext. AI): Recv Action: %s. HTTP: %d. InitTime: %.3fms. Obs: %s" % [parent_probe.get("probe_id"), _action_to_string(current_action), response_code, external_ai_initiation_time_ms, obs_summary])
		
	var reward = calculate_reward()

	if _ai_debug_logging_enabled and parent_probe and parent_probe.has_get("probe_id"):
		print("Probe %s (External AI): Reward calculated: %.4f" % [parent_probe.get("probe_id"), reward])

	last_reward = reward
	episode_step += 1
	action_received.emit(current_action)
	reward_calculated.emit(reward)

func apply_action(action: Array):
	var start_apply_time = Time.get_ticks_usec()

	if not parent_probe or not parent_probe.is_instance_valid():
		_time_action_apply_usec = Time.get_ticks_usec() - start_apply_time # Still record time even if error
		_update_average_timing(_time_action_apply_usec, "_avg_time_action_apply_usec")
		printerr("AIAgent: Cannot apply action, parent probe is missing or invalid.")
		return
	if action.is_empty() or action.size() != ACTION_ARRAY_SIZE:
		_time_action_apply_usec = Time.get_ticks_usec() - start_apply_time # Still record time even if error
		_update_average_timing(_time_action_apply_usec, "_avg_time_action_apply_usec")
		printerr("AIAgent: Received invalid action array. Size: %d, Content: %s" % [action.size(), str(action)])
		return # Do not proceed with invalid action

	# 1. Thrust Control
	var thrust_level_idx = int(action[ACTION_THRUST_LEVEL_INDEX])
	if parent_probe.has_method("set_thrust_level"):
		parent_probe.set_thrust_level(thrust_level_idx) # Probe validates index
	else:
		printerr("AIAgent: Parent probe missing 'set_thrust_level' method.")

	# 2. Torque Control
	var torque_level_idx = int(action[ACTION_TORQUE_LEVEL_INDEX])
	# self.current_rotation_direction is set by decode_action_index or should be from external AI if applicable
	# For external AI, if it sends torque_level_idx > 0, it should also specify direction.
	# For now, relying on self.current_rotation_direction set by decode_action_index for built-in.
	# External AI would need to provide a compatible action array or this logic needs adjustment.
	var direction_to_apply = self.current_rotation_direction # From built-in Q-learning decode
	if use_external_ai:
		# If external AI, it might send direction differently. Task implies 5-element array.
		# For now, assume external AI's action array structure matches and direction is implicit
		# or needs to be part of its own logic if it doesn't use our decode_action_index.
		# This part might need refinement based on external AI's output contract.
		# If torque_level_idx > 0 and direction is 0, it's ambiguous.
		# Let's assume for external AI, if torque_level_idx > 0, it implies some rotation.
		# The prompt says: "Clarify if torque_level itself should determine magnitude *and* direction"
		# Current setup: torque_level_idx for magnitude, self.current_rotation_direction for direction.
		# This is fine for built-in. For external, it must provide compatible values.
		pass # Using self.current_rotation_direction

	if parent_probe.has_method("set_torque_level"):
		parent_probe.set_torque_level(torque_level_idx, direction_to_apply) # Probe validates index & direction
	else:
		printerr("AIAgent: Parent probe missing 'set_torque_level' method.")
	
	# 3. Communication
	var comm_command = int(action[ACTION_COMMUNICATE_INDEX])
	if comm_command == 1:
		if parent_probe.has_method("send_communication") and parent_probe.has_method("get_nearby_probes") and parent_probe.has_method("get_observation_data"):
			var target_probe_for_comm: ProbeUnit = null
			var nearby_probes_list = parent_probe.get_nearby_probes()
			if not nearby_probes_list.is_empty():
				target_probe_for_comm = nearby_probes_list[0] # Simple: pick the first one

			var comm_message_type: MessageData.MessageType = MessageData.MessageType.PROBE_STATUS # Default
			var comm_payload: Dictionary = {"status": "nominal", "energy_ratio": parent_probe.current_energy / parent_probe.max_energy_capacity if parent_probe.max_energy_capacity > 0 else 0.0}

			# Try to share resource location if mining or has a target
			var obs_for_comm = parent_probe.get_observation_data()
			var current_target_node_for_comm = parent_probe.get_current_target_node() # Method from ProbeUnit

			if is_instance_valid(current_target_node_for_comm) and current_target_node_for_comm.is_in_group("resources"):
				if parent_probe.is_mining_active or obs_for_comm.get("current_target_resource_id", "") != "":
					comm_message_type = MessageData.MessageType.RESOURCE_LOCATION
					var resource_data_payload = {}
					resource_data_payload["resource_pos"] = current_target_node_for_comm.global_position
					# Try to get type from the resource node itself
					if current_target_node_for_comm.has_method("get_resource_data"):
						var r_data_map = current_target_node_for_comm.get_resource_data()
						resource_data_payload["resource_type"] = r_data_map.get("type", "unknown")
						resource_data_payload["resource_id"] = current_target_node_for_comm.name # or r_data_map.get("id")
					elif current_target_node_for_comm.has_property("resource_type"): # Fallback
						resource_data_payload["resource_type"] = current_target_node_for_comm.get("resource_type")
						resource_data_payload["resource_id"] = current_target_node_for_comm.name
					else:
						resource_data_payload["resource_type"] = "unknown"
						resource_data_payload["resource_id"] = current_target_node_for_comm.name
					
					comm_payload = resource_data_payload
					if _ai_debug_logging_enabled:
						print("Probe %s: AI decided to share resource location: %s" % [parent_probe.probe_id, str(comm_payload)])
			
			# If target_probe_for_comm is null, send_communication handles it as a broadcast
			parent_probe.send_communication(target_probe_for_comm, comm_message_type, comm_payload)
		else:
			printerr("AIAgent: Parent probe missing 'send_communication' or 'get_nearby_probes' or 'get_observation_data' or 'get_current_target_node' method.")

	# 4. Replication
	var repl_command = int(action[ACTION_REPLICATE_INDEX])
	if repl_command == 1:
		if parent_probe.has_method("attempt_replication"):
			parent_probe.attempt_replication()
		else:
			printerr("AIAgent: Parent probe missing 'attempt_replication' method.")
			
	# 5. Target Resource
	var target_idx_input = int(action[ACTION_TARGET_RESOURCE_INDEX]) # Index relative to observed resources
	if parent_probe.has_method("set_target_resource_by_observed_index"):
		parent_probe.set_target_resource_by_observed_index(target_idx_input) # Probe validates index
	else:
		printerr("AIAgent: Parent probe missing 'set_target_resource_by_observed_index' method.")

	_time_action_apply_usec = Time.get_ticks_usec() - start_apply_time
	_update_average_timing(_time_action_apply_usec, "_avg_time_action_apply_usec")

	if _ai_debug_logging_enabled and parent_probe and parent_probe.has_get("probe_id"):
		print("Probe %s: Applied action %s. ApplyTime: %.3fms" % [parent_probe.get("probe_id"), _action_to_string(action), _time_action_apply_usec / 1000.0])

func calculate_reward() -> float:
	if not parent_probe or not parent_probe.is_instance_valid(): return 0.0

	var total_reward: float = 0.0
	var reward_components: Dictionary = {} # For debugging

	var rf = {} # Reward Factors
	if _config_manager_instance:
		rf = _config_manager_instance.get_setting("general", "reward_factors", {})
	else: # Fallback defaults matching GameConfiguration structure
		rf = { "stay_alive": 0.02, "mining": 0.05, "high_energy": 0.1,
			   "low_energy_penalty": -0.5, "critical_energy_penalty": -2.0,
			   "proximity": 1.95, "reach_target": 2.0, "discovery_bonus": 1.5,
			   "replication_success": 3.0, "thrust_cost": -0.01, "torque_cost": -0.005,
			   "inaction_penalty": -0.1, "collision_penalty": -5.0,
			   "communication_success": 0.2, "target_lost_penalty": -0.5,
			   "no_target_penalty": -0.05, "stored_resource_factor": 0.001,
			   "replication_attempt_reward": 0.01, "communication_failed_penalty": -0.02,
			   "inaction_steps_threshold": 10
			 }

	# --- Get current probe state ---
	var obs_data = {}
	if parent_probe.has_method("get_observation_data"):
		obs_data = parent_probe.get_observation_data()
	else:
		printerr("AIAgent: Probe %s missing get_observation_data for reward calculation." % parent_probe.probe_id if parent_probe else "N/A")
		return 0.0

	var energy_ratio = obs_data.get("energy_ratio", 0.0)
	var is_mining = obs_data.get("is_mining_active", false)
	var current_target_id_from_obs = obs_data.get("current_target_resource_id", "") # Target ID from probe's perspective
	var distance_to_target = obs_data.get("target_resource_distance", -1.0)
	var stored_res = obs_data.get("stored_resources", 0.0)
	
	var probe_is_thrusting = false
	if parent_probe.has_method("is_currently_thrusting"):
		probe_is_thrusting = parent_probe.is_currently_thrusting()
	elif parent_probe.has_get("is_thrusting"):
		probe_is_thrusting = parent_probe.get("is_thrusting")

	var probe_is_applying_torque = false
	if parent_probe.has_method("is_currently_applying_torque"):
		probe_is_applying_torque = parent_probe.is_currently_applying_torque()
	elif parent_probe.has_get("is_applying_torque"):
		probe_is_applying_torque = parent_probe.get("is_applying_torque")
		
	var current_thrust_idx = 0
	if parent_probe.has_get("current_thrust_level_idx"): # Actual thrust level index being applied
		current_thrust_idx = parent_probe.get("current_thrust_level_idx")
		
	var current_torque_idx = 0
	if parent_probe.has_get("current_torque_level_idx"): # Actual torque level index being applied
		current_torque_idx = parent_probe.get("current_torque_level_idx")

	# 1. Survival Reward
	var survival_r = rf.get("stay_alive", 0.02)
	total_reward += survival_r
	reward_components["survival"] = survival_r

	# 2. Mining Reward
	if is_mining:
		var mining_r = rf.get("mining", 0.05)
		total_reward += mining_r
		reward_components["mining_active"] = mining_r

	# 3. Energy Management
	if energy_ratio < 0.1:
		var crit_energy_p = rf.get("critical_energy_penalty", -2.0)
		total_reward += crit_energy_p
		reward_components["energy_critical"] = crit_energy_p
	elif energy_ratio < 0.25:
		var low_energy_p = rf.get("low_energy_penalty", -0.5)
		total_reward += low_energy_p
		reward_components["energy_low"] = low_energy_p
	elif energy_ratio > 0.75:
		var high_energy_r = rf.get("high_energy", 0.1)
		total_reward += high_energy_r
		reward_components["energy_high"] = high_energy_r
	
	# 4. Proximity to Target (AI's intended target)
	var ai_target_resource_idx = -1
	if current_action.size() == ACTION_ARRAY_SIZE: # Check if current_action is populated
		ai_target_resource_idx = int(current_action[ACTION_TARGET_RESOURCE_INDEX])

	if ai_target_resource_idx != -1 and parent_probe.has_method("get_distance_to_observed_resource_idx"):
		var dist_to_ai_target = parent_probe.get_distance_to_observed_resource_idx(ai_target_resource_idx)
		if dist_to_ai_target >= 0: # Valid distance
			var proximity_factor = rf.get("proximity", 1.95)
			var cfg_ai750 = _config_manager_instance.get_config() if _config_manager_instance else null
			var normalization_factor = cfg_ai750.get_setting("general", "max_resource_distance_for_norm", 1000.0) if cfg_ai750 else 1000.0
			if normalization_factor <= 0: normalization_factor = 1000.0
			var proximity_r = proximity_factor * exp(-dist_to_ai_target / (normalization_factor / 10.0))
			total_reward += proximity_r
			reward_components["proximity_to_ai_target"] = proximity_r

	# 5. Reaching Target (Mining a new target that was the AI's intended target)
	if is_mining and current_target_id_from_obs != "" and current_target_id_from_obs != previously_mining_target_id:
		# Check if this current_target_id_from_obs corresponds to what AI intended
		var ai_intended_this_target = false
		if parent_probe.has_method("get_resource_id_for_observed_idx") and ai_target_resource_idx != -1:
			if parent_probe.get_resource_id_for_observed_idx(ai_target_resource_idx) == current_target_id_from_obs:
				ai_intended_this_target = true
		
		if ai_intended_this_target:
			var reach_target_r = rf.get("reach_target", 2.0)
			total_reward += reach_target_r
			reward_components["reached_new_ai_target"] = reach_target_r
		previously_mining_target_id = current_target_id_from_obs
	elif not is_mining and previously_mining_target_id != "": # Reset if stopped mining
		previously_mining_target_id = ""
	
	# 6. Resource Discovery (Handled by _on_resource_discovered signal, adds to last_reward accumulated for next step)

	# 7. Replication Reward
	if current_action.size() == ACTION_ARRAY_SIZE and int(current_action[ACTION_REPLICATE_INDEX]) == 1:
		var repl_attempted_r = rf.get("replication_attempt_reward", 0.01)
		total_reward += repl_attempted_r
		reward_components["replication_attempt"] = repl_attempted_r
		if parent_probe.has_method("get_just_replicated_flag") and parent_probe.get_just_replicated_flag():
			var repl_success_r = rf.get("replication_success", 3.0)
			total_reward += repl_success_r
			reward_components["replication_success_confirmed"] = repl_success_r

	# 8. Efficiency Penalties
	if probe_is_thrusting and current_thrust_idx > 0 : # Cost only if thrust level > 0
		var thrust_p = rf.get("thrust_cost", -0.01) * float(current_thrust_idx)
		total_reward += thrust_p
		reward_components["thrust_cost"] = thrust_p
	if probe_is_applying_torque and current_torque_idx > 0: # Cost only if torque level > 0
		var torque_p = rf.get("torque_cost", -0.005) * float(current_torque_idx)
		total_reward += torque_p
		reward_components["torque_cost"] = torque_p

	# 9. Inaction Penalty
	var position_changed = (parent_probe.global_position.distance_squared_to(last_known_position) > 1.0)
	var energy_changed_significantly = abs(last_known_energy_ratio - energy_ratio) > 0.005
	var resources_changed = abs(last_known_stored_resources - stored_res) > 0.1
	var ai_changed_target_decision = false # Did AI pick a new target_resource_idx this step?
	if current_action.size() == ACTION_ARRAY_SIZE:
		var new_target_idx_decision = int(current_action[ACTION_TARGET_RESOURCE_INDEX])
		if parent_probe.has_get("last_ai_target_idx_decision"): # Requires probe to store this
			if new_target_idx_decision != parent_probe.get("last_ai_target_idx_decision") and new_target_idx_decision != -1:
				ai_changed_target_decision = true
			parent_probe.set("last_ai_target_idx_decision", new_target_idx_decision) # Update for next step

	if not position_changed and not energy_changed_significantly and not resources_changed and not is_mining and not ai_changed_target_decision:
		steps_since_significant_action += 1
	else:
		steps_since_significant_action = 0
	
	if steps_since_significant_action > rf.get("inaction_steps_threshold", 10):
		var inaction_p = rf.get("inaction_penalty", -0.1)
		total_reward += inaction_p
		reward_components["inaction"] = inaction_p
	
	# 10. Collision Penalty (Conceptual: signal `probe_collided` adds to `last_reward` for next step)

	# 11. Communication Reward
	if current_action.size() == ACTION_ARRAY_SIZE and int(current_action[ACTION_COMMUNICATE_INDEX]) == 1:
		var comm_success = false
		if parent_probe.has_method("get_last_communication_success_flag"): # Probe sets this
			comm_success = parent_probe.get_last_communication_success_flag()
		
		if comm_success:
			var comm_r = rf.get("communication_success", 0.2)
			total_reward += comm_r
			reward_components["communication_successful"] = comm_r
		else:
			var comm_fail_p = rf.get("communication_failed_penalty", -0.02)
			total_reward += comm_fail_p
			reward_components["communication_failed_or_no_effect"] = comm_fail_p

	# 12. Target Lost / No Target Penalty (based on AI's decision vs probe's reality)
	var probe_has_valid_target_node = parent_probe.has_method("get_current_target_node") and parent_probe.get_current_target_node() != null
	
	if ai_target_resource_idx != -1 and not probe_has_valid_target_node: # AI picked a target, but probe couldn't validate/find it
		var target_lost_p = rf.get("target_lost_penalty", -0.5)
		total_reward += target_lost_p
		reward_components["ai_target_lost_or_invalid"] = target_lost_p
	elif ai_target_resource_idx == -1: # AI has no target selected
		var no_target_p = rf.get("no_target_penalty", -0.05)
		total_reward += no_target_p
		reward_components["no_target_selected_by_ai"] = no_target_p
		
	# 13. Stored Resources Reward
	var stored_res_r = stored_res * rf.get("stored_resource_factor", 0.001)
	total_reward += stored_res_r
	reward_components["stored_resources_value"] = stored_res_r

	# Update last known states for next step's inaction/change detection
	last_known_position = parent_probe.global_position
	last_known_energy_ratio = energy_ratio
	last_known_stored_resources = stored_res

	# Incorporate event-based rewards (like discovery, collision) accumulated in `last_reward`
	# These are from signals that fired *before* this `calculate_reward` call for the current step's action.
	total_reward += self.last_reward # Add rewards from events like discovery
	if self.last_reward != 0.0:
		reward_components["event_bonuses_or_penalties"] = self.last_reward
	self.last_reward = 0.0 # Reset for the next accumulation period

	if debug_rewards:
		var probe_id_str = parent_probe.probe_id if parent_probe and parent_probe.has_get("probe_id") else "N/A"
		print("\n--- Reward Breakdown (Probe: %s, Step: %d, Total: %.4f) ---" % [probe_id_str, episode_step, total_reward])
		var sorted_keys = reward_components.keys()
		sorted_keys.sort()
		for component_key in sorted_keys:
			print("  %s: %.4f" % [component_key, reward_components[component_key]])
		print("-------------------------------------------------")

	return total_reward

# Signal Handlers for Rewards (These typically add to self.last_reward, to be included in the *next* cycle's reward calculation)
func _on_resource_discovered(probe_node: Node, resource_data: Dictionary): # Probe.gd should emit (self, data)
	if probe_node == parent_probe: # Ensure it's for this agent's probe
		var rf = {}
		if _config_manager_instance:
			rf = _config_manager_instance.get_setting("general", "reward_factors", {})
		var bonus = rf.get("discovery_bonus", 1.5)
		self.last_reward += bonus # Accumulate event-based reward
		
		if debug_rewards:
			var probe_id_str = parent_probe.probe_id if parent_probe and parent_probe.has_get("probe_id") else "N/A"
			var res_id_str = resource_data.get("id", "Unknown")
			print("Probe %s: Resource Discovery Bonus (for %s) accumulated: +%.2f to self.last_reward (current self.last_reward: %.4f)" % [probe_id_str, res_id_str, bonus, self.last_reward])

# func _on_energy_critical(): # Removed, energy status is checked directly in calculate_reward based on energy_ratio.

# Placeholder for collision signal handler (emitted by Probe.gd)
# func _on_probe_collided(collided_with_type: String, impact_severity: float):
# 	if parent_probe: # Ensure it's for this agent's probe
# var rf = _config_manager_instance.get_setting("general", "reward_factors", {}) if _config_manager_instance else {}
# 		var penalty = rf.get("collision_penalty", -5.0) * impact_severity # Scale penalty by severity
# 		self.last_reward += penalty # Accumulate event-based penalty
# 		if debug_rewards:
# 			var probe_id_str = parent_probe.probe_id if parent_probe and parent_probe.has_get("probe_id") else "N/A"
# 			print("Probe %s: Collision Penalty (with %s, severity %.2f) accumulated: %.2f to self.last_reward (current self.last_reward: %.4f)" % [probe_id_str, collided_with_type, impact_severity, penalty, self.last_reward])

# --- Inner Class for Simple Q-Learning ---
class SimpleQLearning extends Node:
	var q_table: Dictionary = {}
	var learning_rate: float = 0.1
	var discount_factor: float = 0.99
	var epsilon: float = 1.0
	var epsilon_decay: float = 0.0001
	var min_epsilon: float = 0.01
	var action_space_size: int = 1 # Must be > 0
	var save_on_end: bool = true # Added from config
	var load_on_start: bool = true # Added from config
	var table_filename: String = "q_table_fallback.json" # Added from config

	func _ready():
		# Load Q-table at start if configured
		if load_on_start and table_filename != "":
			load_q_table(table_filename)
		pass

	func _exit_tree(): # Or a more explicit save call from AIAgent
		if save_on_end and table_filename != "":
			save_q_table(table_filename)

	func set_action_space_size(size: int):
		if size > 0:
			action_space_size = size
		else:
			printerr("SimpleQLearning: Attempted to set invalid action_space_size: ", size, ". Defaulting to 1.")
			action_space_size = 1 # Fallback to a minimal valid size

	func initialize_state(state_hash: String):
		if not q_table.has(state_hash):
			q_table[state_hash] = []
			for _i in range(action_space_size):
				# Initialize with small random values or zeros
				# q_table[state_hash].append(randf_range(-0.01, 0.01))
				q_table[state_hash].append(0.0)
		elif q_table[state_hash].size() != action_space_size: # Fix if size mismatch
			printerr("SimpleQLearning: State %s exists with wrong action size. Reinitializing." % state_hash)
			q_table[state_hash] = []
			for _i in range(action_space_size):
				q_table[state_hash].append(0.0)


	func _decay_epsilon():
		if epsilon > min_epsilon:
			epsilon = max(min_epsilon, epsilon - epsilon_decay)
			# Uncomment for frequent epsilon logging:
			# var agent_node = get_parent()
			# if agent_node and agent_node.parent_probe and agent_node.parent_probe.has_get("probe_id"):
			# 	print("Probe %s Epsilon decayed to: %.4f" % [agent_node.parent_probe.get("probe_id"), epsilon])
			# else:
			# 	print("Epsilon decayed to: %.4f" % epsilon)


	func get_best_action(state_hash: String) -> int:
		initialize_state(state_hash) # Ensure state exists
		
		var q_values = q_table[state_hash]
		if q_values.is_empty(): # Should not happen if action_space_size > 0
			printerr("SimpleQLearning: Q-values empty for state %s. Returning random action." % state_hash)
			return randi() % action_space_size if action_space_size > 0 else 0

		var best_action = 0
		var max_q_val = q_values[0]
		for i in range(1, q_values.size()):
			if q_values[i] > max_q_val:
				max_q_val = q_values[i]
				best_action = i
		return best_action

	func get_max_q_value(state_hash: String) -> float:
		initialize_state(state_hash) # Ensure state exists

		var q_values = q_table[state_hash]
		if q_values.is_empty():
			return 0.0

		var max_q_val = q_values[0]
		for i in range(1, q_values.size()):
			if q_values[i] > max_q_val:
				max_q_val = q_values[i]
		return max_q_val

	func get_action(state_hash: String) -> int:
		if action_space_size <= 0:
			printerr("SimpleQLearning: action_space_size is %d. Returning action 0." % action_space_size)
			return 0
			
		initialize_state(state_hash) # Ensure state is initialized

		if randf() < epsilon:
			# Exploration: choose a random action
			return randi() % action_space_size
		else:
			# Exploitation: choose the best action
			return get_best_action(state_hash)

	func update_q_value(state_hash: String, action_index: int, reward: float, next_state_hash: String):
		if action_space_size <= 0:
			printerr("SimpleQLearning: update_q_value called with action_space_size <= 0.")
			return

		initialize_state(state_hash)
		initialize_state(next_state_hash)

		if action_index < 0 or action_index >= action_space_size:
			printerr("SimpleQLearning: action_index %d out of bounds for action_space_size %d." % [action_index, action_space_size])
			# Optionally, clamp or return, but this indicates a deeper issue.
			# For safety, let's clamp it, but this should be investigated if it occurs.
			action_index = clamp(action_index, 0, action_space_size - 1)

		var old_q_value = q_table[state_hash][action_index]
		var max_q_next = get_max_q_value(next_state_hash)
		
		var new_q_value = old_q_value + learning_rate * (reward + discount_factor * max_q_next - old_q_value)
		q_table[state_hash][action_index] = new_q_value
		
		_decay_epsilon() # Decay epsilon after each update
		
		# Monitoring prints (can be conditional, moved to request_builtin_action for better context)
		# var agent_node = get_parent()
		# if agent_node and agent_node.parent_probe and agent_node.parent_probe.has_get("probe_id"):
		# 	print("Probe %s Q-Table size: %d | Current Epsilon: %.4f" % [agent_node.parent_probe.get("probe_id"), q_table.size(), epsilon])
		# else:
		# 	print("Q-Table size: ", q_table.size(), " | Current Epsilon: ", epsilon)


	func save_q_table(file_path: String):
		var file = FileAccess.open(file_path, FileAccess.WRITE)
		if FileAccess.get_open_error() != OK:
			printerr("SimpleQLearning: Failed to open Q-table file for writing: ", file_path)
			return

		var data_to_save = {
			"q_table": q_table,
			"epsilon": epsilon # Save current epsilon to resume learning progress
		}
		var json_string = JSON.stringify(data_to_save, "\t") # Use tabs for pretty print
		file.store_string(json_string)
		file.close()
		print("SimpleQLearning: Q-table saved to ", file_path)

	func load_q_table(file_path: String):
		if not FileAccess.file_exists(file_path):
			printerr("SimpleQLearning: Q-table file not found: ", file_path)
			return false

		var file = FileAccess.open(file_path, FileAccess.READ)
		if FileAccess.get_open_error() != OK:
			printerr("SimpleQLearning: Failed to open Q-table file for reading: ", file_path)
			return false

		var json_string = file.get_as_text()
		file.close()

		var parse_result = JSON.parse_string(json_string)
		if parse_result == null:
			printerr("SimpleQLearning: Failed to parse Q-table JSON from file: ", file_path)
			return false
		
		if typeof(parse_result) == TYPE_DICTIONARY:
			var loaded_data = parse_result as Dictionary
			if loaded_data.has("q_table") and typeof(loaded_data["q_table"]) == TYPE_DICTIONARY:
				q_table = loaded_data["q_table"]
				# Optional: Restore epsilon if saved
				if loaded_data.has("epsilon") and typeof(loaded_data["epsilon"]) == TYPE_FLOAT:
					epsilon = loaded_data["epsilon"]
				print("SimpleQLearning: Q-table loaded from ", file_path, ". Size: ", q_table.size(), " Epsilon: ", epsilon)
				
				# Validate and potentially resize action arrays in loaded q_table
				for state in q_table.keys():
					if q_table[state].size() != action_space_size:
						print("SimpleQLearning: Mismatch in action space size for state '", state, "' in loaded Q-table. Expected ", action_space_size, ", got ", q_table[state].size(), ". Reinitializing state.")
						# Option 1: Reinitialize this state (loses learned values for this state)
						# initialize_state(state)
						# Option 2: Try to adapt (more complex, e.g. pad with 0s or truncate)
						# For now, just warn or reinitialize. Reinitializing is safer if action space changed.
						var temp_actions = []
						for i in range(action_space_size):
							if i < q_table[state].size():
								temp_actions.append(q_table[state][i])
							else:
								temp_actions.append(0.0) # Pad with zeros
						q_table[state] = temp_actions

				return true
			else:
				printerr("SimpleQLearning: Invalid format in Q-table file (missing 'q_table' dictionary): ", file_path)
				return false
		else:
			printerr("SimpleQLearning: Q-table file does not contain a dictionary: ", file_path)
			return false
		return false