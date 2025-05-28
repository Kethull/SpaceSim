# scripts/probes/Probe.gd
class_name ProbeUnit # Renamed to avoid conflict with scripts/Probe.gd
extends RigidBody2D

const MessageData = preload("res://scripts/data/MessageData.gd")
const CommunicationBeamScene = preload("res://effects/CommunicationBeam.tscn")

@onready var _config_manager_instance = get_node_or_null("/root/ConfigManager")

# Signals
signal resource_discovered(probe: ProbeUnit, resource_data: Dictionary) # Changed to pass Dictionary
signal probe_destroyed(probe: ProbeUnit)
signal communication_sent(message: MessageData)
signal replication_requested(parent_probe: ProbeUnit) # New signal for replication

# Exported properties
@export var probe_id: String = "UNINITIALIZED_PROBE_ID"
@export var generation: int = 0
@export var probe_mass: float = 1.0
@export var max_energy_capacity: float = 100.0
@export var current_energy: float = 100.0
@export var energy_decay_rate_override: float = -1.0
@export var max_velocity: float = 200.0
@export var max_angular_velocity: float = PI
@export var moment_of_inertia_override: float = -1.0

# Movement and Thruster related variables
var thrust_ramp_ratio: float = 0.0
var rotation_ramp_ratio: float = 0.0
var is_thrusting: bool = false # True if thrust is commanded (level_idx > 0)
var is_applying_torque: bool = false # True if torque is commanded (level_idx > 0 and direction != 0)

# New state variables for indexed actions
var current_thrust_level_idx: int = 0
var current_torque_level_idx: int = 0
var current_commanded_rotation_direction: int = 0 # -1 for left, 0 for none, 1 for right

# AI and State related variables
var is_mining_active: bool = false
var stored_resources: float = 0.0
var communication_cooldown_remaining: float = 0.0
var replication_cooldown_remaining: float = 0.0
var target_resource_idx_ai: int = -1 # AI's observed index for its target
var current_target_resource_node: Node = null
var times_replicated: int = 0 # Statistics: times this probe has replicated

var nearby_observed_resources_cache: Array = [] # Cache of resource Nodes
var probes_in_comm_range: Array[ProbeUnit] = [] # Probes currently in communication range
var known_resource_locations: Dictionary = {} # {Vector2_pos: {"type": "mineral", "timestamp": 12345}}

# Audio player references for looping sounds
var thruster_audio_player: AudioStreamPlayer2D = null
var mining_laser_audio_player: AudioStreamPlayer2D = null
var energy_critical_sound_played: bool = false # Flag for energy warning

# Flags for AIAgent reward calculation
var _last_communication_successful: bool = false
var _just_replicated: bool = false
var last_ai_target_idx_decision: int = -1 # For AIAgent's inaction detection

# @onready variables for child nodes
@onready var collision_shape_2d: CollisionShape2D = $CollisionShape2D
@onready var visual_component: Node2D = $VisualComponent
@onready var hull_sprite: Sprite2D = $VisualComponent/HullSprite
@onready var solar_panels: Node2D = $VisualComponent/SolarPanels
@onready var left_panel: Sprite2D = $VisualComponent/SolarPanels/LeftPanel
@onready var right_panel: Sprite2D = $VisualComponent/SolarPanels/RightPanel
@onready var communication_dish: Sprite2D = $VisualComponent/CommunicationDish
@onready var sensor_array_visual: Sprite2D = $VisualComponent/SensorArray # Visual sprite
@onready var status_lights: Node2D = $VisualComponent/StatusLights

@onready var thruster_system: Node2D = $ThrusterSystem
@onready var sensor_array_area: Area2D = $SensorArray # Area2D for detection
@onready var sensor_shape: CollisionShape2D = $SensorArray/SensorShape
@onready var communication_range: Area2D = $CommunicationRange
@onready var comm_shape: CollisionShape2D = $CommunicationRange/CommShape
@onready var movement_trail: Line2D = $MovementTrail
@onready var mining_laser: Line2D = $MiningLaser
@onready var ai_agent: Node = $AIAgent
@onready var energy_system: Node = $EnergySystem # Placeholder
# Removed: @onready var audio_component: AudioStreamPlayer2D = $AudioComponent

# Visual effect variables
var trail_points: Array[Vector2] = []
var is_selected: bool = false
var _base_hull_color: Color = Color.WHITE

var is_alive: bool = true

func _ready() -> void:
	if not _config_manager_instance:
		printerr("ConfigManager (Autoload) at path '/root/ConfigManager' not found in Probe.gd _ready(). Critical features may fail.")
	var cfg_initial = _config_manager_instance.get_config() if _config_manager_instance else null
	
	if cfg_initial:
		if probe_mass <= 0.001:
			var _temp_val_L96 = cfg_initial.get("probe_mass")
			if _temp_val_L96 != null:
				probe_mass = _temp_val_L96
			else:
				probe_mass = 1.0
	mass = probe_mass

	if cfg_initial:
		if max_energy_capacity <= 0.001:
			var _temp_val_L100 = cfg_initial.get("initial_energy")
			if _temp_val_L100 != null:
				max_energy_capacity = _temp_val_L100
			else:
				max_energy_capacity = 100.0
	
	if current_energy > max_energy_capacity or (current_energy <= 0.001 and max_energy_capacity > 0):
		current_energy = max_energy_capacity

	if moment_of_inertia_override >= 0:
		inertia = moment_of_inertia_override
	elif collision_shape_2d and collision_shape_2d.shape and collision_shape_2d.shape is CircleShape2D:
		var radius = collision_shape_2d.shape.radius
		inertia = 0.5 * mass * radius * radius if mass > 0 and radius > 0 else 10.0
		if inertia <= 0: inertia = 10.0
	else:
		inertia = 10.0

	gravity_scale = 0.0
	set_collision_layer_value(2, true)
	set_collision_mask_value(1, true)
	set_collision_mask_value(2, false)
	set_collision_mask_value(3, true)
	add_to_group("probes")

	setup_visual_appearance()
	setup_sensor_systems()
	setup_thruster_system()

	if sensor_array_area:
		sensor_array_area.body_entered.connect(_on_sensor_body_entered)
		sensor_array_area.body_exited.connect(_on_sensor_body_exited)
		if sensor_array_area.has_signal("area_entered"): # For resources that are Area2D
			sensor_array_area.area_entered.connect(_on_sensor_area_entered)
		if sensor_array_area.has_signal("area_exited"): # For resources that are Area2D
			sensor_array_area.area_exited.connect(_on_sensor_area_exited)
	else:
		printerr("Probe %s: SensorArrayArea not found." % probe_id)

	if communication_range:
		communication_range.area_entered.connect(_on_communication_range_entered)
		communication_range.area_exited.connect(_on_communication_range_exited) # Connect exited signal
	else:
		printerr("Probe %s: CommunicationRange not found." % probe_id)

	if ai_agent and ai_agent.has_method("initialize"):
		ai_agent.initialize(self)
	else:
		printerr("Probe %s: AIAgent node issue." % probe_id)

func setup_sensor_systems() -> void:
	if not sensor_array_area or not sensor_shape:
		printerr("Probe %s: SensorArrayArea or SensorShape not found for setup." % probe_id)
		return

	var cfg = _config_manager_instance.get_config() if _config_manager_instance else null
	if not cfg:
		printerr("Probe %s: ConfigManager not available for sensor setup. Using defaults." % probe_id)
		if sensor_shape.shape is CircleShape2D:
			(sensor_shape.shape as CircleShape2D).radius = 150.0 # Default sensor range
		return

	var sensor_range_val = cfg.get("sensor_range")
	# var sensor_angle_deg = cfg.get("sensor_angle_degrees", 90.0) # Not directly used by CircleShape2D

	if sensor_shape.shape is CircleShape2D:
		(sensor_shape.shape as CircleShape2D).radius = sensor_range_val
		# print_debug("Probe %s: Sensor range set to %.1f" % [probe_id, sensor_range_val])
	else:
		printerr("Probe %s: SensorShape is not a CircleShape2D. Cannot set radius." % probe_id)
	
	# Sensor angle would typically be handled by filtering detected bodies/areas in the
	# _on_sensor_body_entered/_on_sensor_area_entered methods if a cone shape is desired,
	# as Area2D CollisionShapes don't have a direct angle property for circles.
	# For now, it's a full circle detection up to sensor_range_val.

func setup_visual_appearance() -> void:
	if not visual_component or not hull_sprite: return
	var colors = [Color.WHITE, Color.LIGHT_BLUE, Color.LIGHT_GREEN, Color.YELLOW, Color.ORANGE, Color.PINK, Color.CYAN, Color.MAGENTA]
	hull_sprite.modulate = colors[generation % colors.size()]
	_base_hull_color = hull_sprite.modulate
	
	var cfg_visual = _config_manager_instance.get_config() if _config_manager_instance else null
	if cfg_visual:
		var probe_scale_config = cfg_visual.get("probe_size")
		if probe_scale_config is float or probe_scale_config is int:
			visual_component.scale = Vector2(probe_scale_config, probe_scale_config)
		elif probe_scale_config is Vector2:
			visual_component.scale = probe_scale_config
		else: visual_component.scale = Vector2.ONE
	else: visual_component.scale = Vector2.ONE

func _physics_process(delta: float) -> void:
	if not is_alive: return

	_update_cooldowns(delta)
	_process_mining(delta)

	if ai_agent and ai_agent.has_method("update_step"):
		ai_agent.update_step(delta)

	update_action_smoothing(delta)
	update_movement_trail()
	update_visual_effects()

	var actual_decay_rate: float
	var cfg_physics = _config_manager_instance.get_config() if _config_manager_instance else null
	if energy_decay_rate_override >= 0: actual_decay_rate = energy_decay_rate_override
	elif cfg_physics:
		var decay_rate_from_config = cfg_physics.get("energy_decay_rate")
		actual_decay_rate = decay_rate_from_config if decay_rate_from_config != null else 0.1 # Default if key is missing or value is null
	else: actual_decay_rate = 0.1
	current_energy = max(0.0, current_energy - actual_decay_rate * delta)

	# Energy critical sound logic
	var energy_ratio = current_energy / max_energy_capacity if max_energy_capacity > 0.001 else 0.0
	var audio_manager_node = get_node_or_null("/root/AudioManager")
	if energy_ratio < 0.1 and not energy_critical_sound_played:
		if audio_manager_node:
			audio_manager_node.play_sound_at_position("energy_critical", global_position)
		energy_critical_sound_played = true
	elif energy_ratio > 0.15 and energy_critical_sound_played: # Reset flag when energy recovers a bit
		energy_critical_sound_played = false

	if current_energy <= 0.0001: die()

func die() -> void:
	if not is_alive: return
	is_alive = false

	var audio_manager_node = get_node_or_null("/root/AudioManager")
	if audio_manager_node:
		audio_manager_node.play_sound_at_position("explosion", global_position)
		if is_instance_valid(thruster_audio_player):
			audio_manager_node.stop_looping_sound(thruster_audio_player)
			thruster_audio_player = null
		if is_instance_valid(mining_laser_audio_player):
			audio_manager_node.stop_looping_sound(mining_laser_audio_player)
			mining_laser_audio_player = null
			
	set_collision_layer_value(2, false)
	var tween = create_tween()
	if is_instance_valid(visual_component):
		tween.parallel().tween_property(visual_component, "modulate", Color.RED, 1.0)
		tween.parallel().tween_property(visual_component, "scale", Vector2.ZERO, 1.0)
	tween.tween_callback(queue_free)
	probe_destroyed.emit(self)

func _integrate_forces(state: PhysicsDirectBodyState2D) -> void:
	var cfg = _config_manager_instance.get_config() if _config_manager_instance else null
	if not cfg:
		# Minimal default behavior if no config
		var d_max_vel = 150.0; var d_max_ang_vel = PI/2.0
		if state.linear_velocity.length_squared() > d_max_vel*d_max_vel: state.linear_velocity = state.linear_velocity.normalized()*d_max_vel
		if abs(state.angular_velocity) > d_max_ang_vel: state.angular_velocity = sign(state.angular_velocity)*d_max_ang_vel
		return

	if is_thrusting and current_thrust_level_idx > 0 and thrust_ramp_ratio > 0.01:
		var _temp_val_L254 = cfg.get("thrust_force_magnitudes")
		var thrust_magnitudes
		if _temp_val_L254 != null:
			thrust_magnitudes = _temp_val_L254
		else:
			thrust_magnitudes = [0.0, 200.0]
		if current_thrust_level_idx < thrust_magnitudes.size():
			var thrust_force = thrust_magnitudes[current_thrust_level_idx]
			var actual_thrust = thrust_force * thrust_ramp_ratio
			state.apply_central_force(Vector2(1, 0).rotated(rotation) * actual_thrust)
			var _temp_val_L259 = cfg.get("thrust_energy_cost_factor")
			var _actual_val_L259 = _temp_val_L259 if _temp_val_L259 != null else 0.1
			current_energy -= abs(actual_thrust) * _actual_val_L259 * state.step
		else: printerr("Probe %s: Invalid thrust_idx %d" % [probe_id, current_thrust_level_idx])

	if is_applying_torque and current_torque_level_idx > 0 and current_commanded_rotation_direction != 0 and rotation_ramp_ratio > 0.01:
		var _temp_val_L263 = cfg.get("torque_magnitudes")
		var torque_mags
		if _temp_val_L263 != null:
			torque_mags = _temp_val_L263
		else:
			torque_mags = [0.0, 30.0]
		if current_torque_level_idx < torque_mags.size():
			var torque_magnitude = torque_mags[current_torque_level_idx]
			var actual_torque = torque_magnitude * current_commanded_rotation_direction * rotation_ramp_ratio
			state.apply_torque(actual_torque)
			var _temp_val_L268 = cfg.get("rotation_energy_cost_factor")
			var _actual_val_L268 = _temp_val_L268 if _temp_val_L268 != null else 0.05
			current_energy -= abs(actual_torque) * _actual_val_L268 * state.step
		else: printerr("Probe %s: Invalid torque_idx %d" % [probe_id, current_torque_level_idx])
	
	var _temp_val_L271 = cfg.get("max_velocity")
	var m_vel = _temp_val_L271 if _temp_val_L271 != null else 200.0
	if state.linear_velocity.length_squared() > m_vel * m_vel:
		state.linear_velocity = state.linear_velocity.normalized() * m_vel
	var _temp_val_L274 = cfg.get("max_angular_velocity")
	var m_ang_vel = _temp_val_L274 if _temp_val_L274 != null else PI
	if abs(state.angular_velocity) > m_ang_vel:
		state.angular_velocity = sign(state.angular_velocity) * m_ang_vel

func setup_thruster_system() -> void:
	if not thruster_system: return
	var main_thruster = thruster_system.get_node_or_null("MainThruster")
	if main_thruster is GPUParticles2D: configure_thruster_particles(main_thruster, Vector2(0, 1))
	var rcs_thrusters_cfg = {"RCSThrusterN": Vector2(0,-1),"RCSThrusterS": Vector2(0,1),"RCSThrusterE": Vector2(1,0),"RCSThrusterW": Vector2(-1,0)}
	for t_name in rcs_thrusters_cfg:
		var rcs_node = thruster_system.get_node_or_null(t_name)
		if rcs_node is GPUParticles2D: configure_thruster_particles(rcs_node, rcs_thrusters_cfg[t_name])
	# Old audio_component logic removed

func configure_thruster_particles(thruster: GPUParticles2D, direction: Vector2) -> void:
	if not thruster: return
	var mat = ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_POINT
	mat.direction = Vector3(direction.x, direction.y, 0.0).normalized()
	mat.initial_velocity_min = 50.0; mat.initial_velocity_max = 100.0
	mat.gravity = Vector3.ZERO
	mat.damping_min = 5.0; mat.damping_max = 10.0
	mat.scale_min = 0.05; mat.scale_max = 0.2
	var sc_curve = Curve.new(); sc_curve.add_point(Vector2(0,1)); sc_curve.add_point(Vector2(0.5,0.7)); sc_curve.add_point(Vector2(1,0.1))
	mat.scale_curve = sc_curve
	var cr_ramp = Gradient.new(); cr_ramp.add_point(0.0,Color(1,0.8,0.2,1)); cr_ramp.add_point(0.7,Color(0.8,0.2,0,0.8)); cr_ramp.add_point(1.0,Color(0.5,0.5,0.5,0))
	mat.color_ramp = cr_ramp
	thruster.process_material = mat
	thruster.amount = 50; thruster.lifetime = 0.5; thruster.one_shot = false
	thruster.speed_scale = 1.0; thruster.explosiveness = 0.1; thruster.randomness = 0.5
	thruster.fixed_fps = 0; thruster.local_coords = true; thruster.emitting = false

func update_action_smoothing(delta: float) -> void:
	var cfg = _config_manager_instance.get_config() if _config_manager_instance else null
	var rup_spd = 2.0; var rdown_spd = 3.0; var rot_rup_spd = 2.5; var rot_rdown_spd = 3.5
	if cfg:
		rup_spd = _config_manager_instance.get_setting("probe", "rup_spd", 2.0)
		rdown_spd = _config_manager_instance.get_setting("probe", "thrust_ramp_down_speed", 3.0)
		rot_rup_spd = _config_manager_instance.get_setting("probe", "rotation_ramp_up_speed", 2.5)
		rot_rdown_spd = _config_manager_instance.get_setting("probe", "rotation_ramp_down_speed", 3.5)

	if is_thrusting and current_thrust_level_idx > 0:
		thrust_ramp_ratio = min(1.0, thrust_ramp_ratio + rup_spd * delta)
	else:
		thrust_ramp_ratio = max(0.0, thrust_ramp_ratio - rdown_spd * delta)

	if is_applying_torque and current_torque_level_idx > 0 and current_commanded_rotation_direction != 0:
		rotation_ramp_ratio = min(1.0, rotation_ramp_ratio + rot_rup_spd * delta)
	else:
		rotation_ramp_ratio = max(0.0, rotation_ramp_ratio - rot_rdown_spd * delta)
	update_thruster_effects()

# --- Action Execution Methods ---
func set_thrust_level(level_idx: int) -> void:
	var cfg = _config_manager_instance.get_config()
	if not cfg: is_thrusting = false; current_thrust_level_idx = 0; return
	var _temp_val_L330 = cfg.get("thrust_force_magnitudes")
	var thrust_mags = _temp_val_L330 if _temp_val_L330 != null else []
	if level_idx >= 0 and level_idx < thrust_mags.size():
		current_thrust_level_idx = level_idx
		is_thrusting = (level_idx > 0)
	else: current_thrust_level_idx = 0; is_thrusting = false; printerr("Probe %s: Invalid thrust_idx %d" % [probe_id, level_idx])

func set_torque_level(level_idx: int, direction: int) -> void:
	var cfg = _config_manager_instance.get_config()
	if not cfg: is_applying_torque = false; current_torque_level_idx = 0; current_commanded_rotation_direction = 0; return
	var _temp_val_L339 = cfg.get("torque_magnitudes")
	var torque_mags = _temp_val_L339 if _temp_val_L339 != null else []
	if level_idx >= 0 and level_idx < torque_mags.size():
		if direction >= -1 and direction <= 1:
			current_torque_level_idx = level_idx
			current_commanded_rotation_direction = direction
			is_applying_torque = (level_idx > 0 and direction != 0)
		else: current_torque_level_idx=0; current_commanded_rotation_direction=0; is_applying_torque=false; printerr("Probe %s: Invalid torque_dir %d" % [probe_id, direction])
	else: current_torque_level_idx=0; current_commanded_rotation_direction=0; is_applying_torque=false; printerr("Probe %s: Invalid torque_idx %d" % [probe_id, level_idx])

func attempt_communication() -> void: # This is likely AI triggered, should use new system.
	# TODO: Refactor AI to call send_communication directly with specific message types and payloads.
	# For now, this will send a generic broadcast ping using the new system.
	_last_communication_successful = send_communication(null, MessageData.MessageType.GENERAL_BROADCAST, {"ping_content": "generic_ping_from_attempt_comm"})
	# print_debug("Probe %s: attempt_communication() resulted in: %s" % [probe_id, _last_communication_successful])

func attempt_replication() -> bool:
	_just_replicated = false # Reset at the start of an attempt
	var cfg = _config_manager_instance.get_config()
	if not cfg:
		printerr("Probe %s: ConfigManager not available for attempt_replication." % probe_id)
		return false

	if replication_cooldown_remaining > 0:
		var _temp_val_L362 = cfg.get("ai_debug_logging")
		var _actual_val_L362 = _temp_val_L362 if _temp_val_L362 != null else false
		if _actual_val_L362:
			print_debug("Probe %s: Replication attempt failed - Cooldown active (%.1fs left)." % [probe_id, replication_cooldown_remaining])
		return false

	var _temp_val_L366 = cfg.get("replication_cost")
	var cost_energy = _temp_val_L366 if _temp_val_L366 != null else 80000.0
	var _temp_val_L367 = cfg.get("replication_min_energy")
	var min_energy_to_attempt = _temp_val_L367 if _temp_val_L367 != null else 90000.0 # Absolute minimum energy to even try
	# var resource_cost = cfg.get("replication_resource_cost", 500.0) # Assuming resources are not a direct cost for now as per prompt focus

	# Refined Energy Checks:
	# 1. Must have at least min_energy_to_attempt to consider replication.
	if current_energy < min_energy_to_attempt:
		var _temp_val_L373 = cfg.get("ai_debug_logging")
		var _actual_val_L373 = _temp_val_L373 if _temp_val_L373 != null else false
		if _actual_val_L373:
			print_debug("Probe %s: Replication attempt failed - Below minimum energy threshold to attempt (need %.1f, have %.1f)." % [probe_id, min_energy_to_attempt, current_energy])
		return false

	# 2. Must have enough energy to cover the actual replication_cost.
	if current_energy < cost_energy:
		var _temp_val_L379 = cfg.get("ai_debug_logging")
		var _actual_val_L379 = _temp_val_L379 if _temp_val_L379 != null else false
		if _actual_val_L379:
			print_debug("Probe %s: Replication attempt failed - Insufficient energy for cost (need %.1f, have %.1f)." % [probe_id, cost_energy, current_energy])
		return false
	
	# Optional: Check if after paying cost, energy would be too low (e.g., below a survival threshold)
	# For now, the prompt implies min_energy_to_attempt is the primary gate before cost.

	# Deduct cost BEFORE emitting signal
	current_energy -= cost_energy
	# stored_resources -= resource_cost # If resource costs were involved

	# Emit signal for SimulationManager to handle actual child creation
	replication_requested.emit(self)
	
	# Reset cooldown and update stats AFTER successfully emitting the request
	# The actual success of creating a child is handled by SimulationManager.
	# The probe considers its part done once the request is made and cost paid.
	var _temp_val_L396 = cfg.get("replication_cooldown_sec")
	replication_cooldown_remaining = _temp_val_L396 if _temp_val_L396 != null else 60.0 # Use new config key
	times_replicated += 1
	_just_replicated = true # Flag for AI reward system

	var _temp_val_L400 = cfg.get("ai_debug_logging")
	var _actual_val_L400 = _temp_val_L400 if _temp_val_L400 != null else false
	if _actual_val_L400:
		print_debug("Probe %s: Replication requested. Energy deducted: %.1f. Cooldown set. Times replicated: %d." % [probe_id, cost_energy, times_replicated])

	if visual_component: # Simple visual feedback for request
		var tween = create_tween()
		tween.tween_property(visual_component, "modulate", Color.PALE_GREEN, 0.3)
		tween.tween_property(visual_component, "modulate", _base_hull_color, 0.3).set_delay(0.3)
	
	return true # Request was successfully made

# Called by SimulationManager if replication fails globally (e.g. max probes reached)
# This allows the probe to reclaim its spent energy.
func replication_globally_failed():
	var cfg = _config_manager_instance.get_config()
	if not cfg: return

	var _temp_val_L416 = cfg.get("replication_cost")
	var cost_energy = _temp_val_L416 if _temp_val_L416 != null else 80000.0
	current_energy += cost_energy # Refund energy
	# stored_resources += resource_cost # Refund resources if they were used

	# Reset cooldown and stats as if it never happened from this probe's perspective for this attempt
	replication_cooldown_remaining = 0.0 # Allow immediate re-try if conditions change
	times_replicated = max(0, times_replicated -1) # Decrement if it was incremented
	_just_replicated = false # Clear flag

	var _temp_val_L425 = cfg.get("ai_debug_logging")
	var _actual_val_L425 = _temp_val_L425 if _temp_val_L425 != null else false
	if _actual_val_L425:
		print_debug("Probe %s: Replication globally failed. Energy refunded. Cooldown reset." % probe_id)


func set_target_resource_by_observed_index(observed_idx: int) -> void:
	last_ai_target_idx_decision = observed_idx # Store AI's choice for inaction detection
	target_resource_idx_ai = observed_idx # Store AI's choice for its own reference
	
	if observed_idx < 0 or observed_idx >= nearby_observed_resources_cache.size():
		current_target_resource_node = null
		# target_resource_idx_ai = -1 # Already set to observed_idx, which would be invalid
		if is_mining_active: stop_mining()
		# print_debug("Probe %s: Cleared target due to invalid observed_idx: %d" % [probe_id, observed_idx])
		return
		
	var res_cand = nearby_observed_resources_cache[observed_idx]
	if res_cand is Node and res_cand.is_in_group("resources") and is_instance_valid(res_cand):
		current_target_resource_node = res_cand
		# target_resource_idx_ai = observed_idx # Already set
		# print_debug("Probe %s: Set target to observed_idx %d (Node: %s)" % [probe_id, observed_idx, res_cand.name])
	else:
		current_target_resource_node = null
		# target_resource_idx_ai = -1 # Already set to observed_idx, which points to invalid candidate
		if is_mining_active: stop_mining()
		# print_debug("Probe %s: Failed to set target from observed_idx %d, candidate invalid." % [probe_id, observed_idx])

# Helper method to safely clear target
func clear_target_resource():
	if is_mining_active:
		stop_mining()
	current_target_resource_node = null
	target_resource_idx_ai = -1

# Helper method to safely set target with validation
func set_target_resource_node(resource_node: Node) -> bool:
	if not resource_node or not is_instance_valid(resource_node):
		clear_target_resource()
		return false
		
	if not resource_node.is_in_group("resources"):
		clear_target_resource()
		return false
		
	current_target_resource_node = resource_node
	return true
# --- Mining Logic ---
func start_mining() -> void:
	if not current_target_resource_node or not is_instance_valid(current_target_resource_node): if is_mining_active: stop_mining(); return
	var cfg = _config_manager_instance.get_config(); if not cfg: if is_mining_active: stop_mining(); return
	var _temp_val_L474 = cfg.get("harvest_distance")
	var mining_dist = _temp_val_L474 if _temp_val_L474 != null else 50.0
	if global_position.distance_squared_to(current_target_resource_node.global_position) <= mining_dist * mining_dist:
		if not is_mining_active:
			is_mining_active = true
			var audio_manager_node = get_node_or_null("/root/AudioManager")
			if audio_manager_node and not is_instance_valid(mining_laser_audio_player):
				mining_laser_audio_player = audio_manager_node.play_looping_sound("mining_laser", current_target_resource_node.global_position)
		if mining_laser: mining_laser.clear_points(); mining_laser.add_point(Vector2.ZERO); mining_laser.add_point(to_local(current_target_resource_node.global_position)); mining_laser.visible = true
	else: if is_mining_active: stop_mining()
			
func stop_mining() -> void:
	if is_mining_active:
		is_mining_active = false
		var audio_manager_node = get_node_or_null("/root/AudioManager")
		if audio_manager_node and is_instance_valid(mining_laser_audio_player):
			audio_manager_node.stop_looping_sound(mining_laser_audio_player)
			mining_laser_audio_player = null
	if mining_laser: mining_laser.visible = false

func _process_mining(delta: float) -> void:
	if not is_mining_active:
		return
		
	# Critical: Check target validity at the beginning AND before each access
	if not current_target_resource_node or not is_instance_valid(current_target_resource_node):
		print("Probe._process_mining: current_target_resource_node became null or invalid. Stopping mining.")
		stop_mining()
		return
		
	var cfg = _config_manager_instance.get_config()
	if not cfg:
		# According to prompt's fixed code, just return. If mining was active, it remains so.
		# Subsequent logic needing cfg won't run. If cfg becomes available, it might proceed next frame.
		return
		
	var _temp_val_L509 = cfg.get("harvest_distance")
	var harvest_distance_value = _temp_val_L509 if _temp_val_L509 != null else 50.0
	
	# Double-check validity before accessing global_position
	if not current_target_resource_node or not is_instance_valid(current_target_resource_node):
		print("Probe._process_mining: current_target_resource_node became invalid before distance check. Stopping mining.")
		stop_mining()
		return
		
	var distance_sq = global_position.distance_squared_to(current_target_resource_node.global_position)
	if distance_sq > harvest_distance_value * harvest_distance_value:
		stop_mining()
		return
		
	# Continue with rest of mining logic, always checking validity before access
	if mining_laser and mining_laser.visible:
		# Check again before accessing position for laser
		if current_target_resource_node and is_instance_valid(current_target_resource_node):
			mining_laser.set_point_position(1, to_local(current_target_resource_node.global_position))
		# If target became invalid here, the laser won't update, but subsequent checks for harvesting will catch it.

	# --- Integrated rest of original function's logic (lines 485-498 of original) with safety checks ---
	
	# Mining energy cost (cfg is confirmed valid at this point)
	var _temp_val_L532 = cfg.get("mining_energy_cost_per_second")
	var mining_energy_cost_value = _temp_val_L532 if _temp_val_L532 != null else 1.0
		
	if current_energy < mining_energy_cost_value * delta:
		stop_mining()
		return
	current_energy -= mining_energy_cost_value * delta
	
	# Actual harvesting from resource
	# CRITICAL: Re-check target validity before any operations on current_target_resource_node for harvesting.
	if not current_target_resource_node or not is_instance_valid(current_target_resource_node):
		print("Probe._process_mining: current_target_resource_node became invalid before harvest operations. Stopping mining.")
		stop_mining()
		return

	if current_target_resource_node.has_method("harvest"):
		var _temp_val_L547 = cfg.get("harvest_rate")
		var harvest_rate_value = _temp_val_L547 if _temp_val_L547 != null else 10.0
		var harvested_amount = current_target_resource_node.harvest(harvest_rate_value * delta) # This might invalidate the node
		
		if harvested_amount > 0:
			stored_resources += harvested_amount
		
		# Check if resource depleted after harvesting
		# CRITICAL: Re-check validity of current_target_resource_node as harvest() might have freed it or changed its state.
		if not current_target_resource_node or not is_instance_valid(current_target_resource_node):
			print("Probe._process_mining: current_target_resource_node became invalid during/after harvest, before depletion check. Stopping mining.")
			stop_mining()
			return

		# This check is only performed if the node is still valid.
		if current_target_resource_node.has_method("get_current_amount") and \
		   current_target_resource_node.get_current_amount() <= 0.001: # Use epsilon for float comparison
			stop_mining()
			return
	else:
		# This case means current_target_resource_node is valid but lacks "harvest" method.
		print("Probe._process_mining: Target resource node (%s) is valid but does not have 'harvest' method. Stopping mining." % str(current_target_resource_node))
		stop_mining()
		return
func _update_cooldowns(delta: float):
	if communication_cooldown_remaining > 0: communication_cooldown_remaining = max(0.0, communication_cooldown_remaining - delta)
	if replication_cooldown_remaining > 0: replication_cooldown_remaining = max(0.0, replication_cooldown_remaining - delta)

func update_thruster_effects() -> void:
	var main_thruster_particles = thruster_system.get_node_or_null("MainThruster")
	var eff_thrusting = is_thrusting and current_thrust_level_idx > 0 and thrust_ramp_ratio > 0.01

	if main_thruster_particles is GPUParticles2D:
		main_thruster_particles.emitting = eff_thrusting
		if eff_thrusting:
			if main_thruster_particles.process_material is ParticleProcessMaterial:
				var mat = main_thruster_particles.process_material as ParticleProcessMaterial
				if mat.color_ramp: mat.color_ramp.set_color(0, Color(1,0.8,0.2,1).lerp(Color(1,1,0.8,1), thrust_ramp_ratio))
	
	# Audio Management for thrusters
	var audio_manager_node = get_node_or_null("/root/AudioManager")
	if audio_manager_node:
		if eff_thrusting:
			if not is_instance_valid(thruster_audio_player) or not thruster_audio_player.playing:
				if is_instance_valid(thruster_audio_player): # Stop if it exists but isn't playing (e.g. was stopped externally)
					audio_manager_node.stop_looping_sound(thruster_audio_player)
				thruster_audio_player = audio_manager_node.play_looping_sound("thruster", global_position)
		else: # Not effectively thrusting
			if is_instance_valid(thruster_audio_player) and thruster_audio_player.playing:
				audio_manager_node.stop_looping_sound(thruster_audio_player)
				thruster_audio_player = null # Clear reference after stopping

	var rcs_nodes = {"N": thruster_system.get_node_or_null("RCSThrusterN"), "S": thruster_system.get_node_or_null("RCSThrusterS"), "E": thruster_system.get_node_or_null("RCSThrusterE"), "W": thruster_system.get_node_or_null("RCSThrusterW")}
	var eff_rotating = is_applying_torque and current_torque_level_idx > 0 and current_commanded_rotation_direction != 0 and rotation_ramp_ratio > 0.01
	for key in rcs_nodes:
		var rcs_node = rcs_nodes[key]
		if rcs_node is GPUParticles2D:
			var should_emit = false
			if eff_rotating: # Simplified RCS logic
				if (current_commanded_rotation_direction < 0 and (key == "E" or key == "W")) or \
				   (current_commanded_rotation_direction > 0 and (key == "E" or key == "W")):
					should_emit = true
			rcs_node.emitting = should_emit

# --- Sensor System Implementation ---
func _on_sensor_body_entered(body: Node2D) -> void: _handle_sensor_interaction(body, true)
func _on_sensor_body_exited(body: Node2D) -> void: _handle_sensor_interaction(body, false)
func _on_sensor_area_entered(area: Area2D) -> void: # For resources that are Area2D
	if is_instance_valid(area) and is_instance_valid(area.owner): _handle_sensor_interaction(area.owner, true)
func _on_sensor_area_exited(area: Area2D) -> void: # For resources that are Area2D
	if is_instance_valid(area) and is_instance_valid(area.owner): _handle_sensor_interaction(area.owner, false)

func _handle_sensor_interaction(node: Node2D, entered: bool) -> void:
	if not is_instance_valid(node): return
	if node.is_in_group("resources"):
		var res_node = node
		if entered:
			var in_cache = false; for entry in nearby_observed_resources_cache: if entry == res_node: in_cache = true; break
			if not in_cache: nearby_observed_resources_cache.append(res_node)
			if res_node.has_method("get_resource_data"): # For discovery signal
				var r_data = res_node.get_resource_data()
				var _temp_type_L627 = r_data.get("type")
				var _actual_type_L627 = _temp_type_L627 if _temp_type_L627 != null else "unknown"
				var _temp_amount_L627 = r_data.get("amount")
				var _actual_amount_L627 = _temp_amount_L627 if _temp_amount_L627 != null else 0.0
				resource_discovered.emit(self, {"id":res_node.name, "position":res_node.global_position, "type":_actual_type_L627, "amount":_actual_amount_L627})
		else: # Exited
			for i in range(nearby_observed_resources_cache.size()-1, -1, -1): if nearby_observed_resources_cache[i]==res_node: nearby_observed_resources_cache.remove_at(i); break
			# CRITICAL: Clear target if it was the exiting resource
			if current_target_resource_node == res_node:
				clear_target_resource()
	# elif node.is_in_group("celestial_bodies"): pass
	# elif node.is_in_group("probes") and node != self: pass

# --- Communication System ---
func _on_communication_range_entered(area: Area2D) -> void:
	if is_instance_valid(area) and is_instance_valid(area.owner) and area.owner != self and area.owner is ProbeUnit:
		var probe_node: ProbeUnit = area.owner
		if not probe_node in probes_in_comm_range:
			probes_in_comm_range.append(probe_node)
			# print_debug("Probe %s: Probe %s entered comm range. Total: %s" % [probe_id, probe_node.probe_id, probes_in_comm_range.size()])

func _on_communication_range_exited(area: Area2D) -> void:
	if is_instance_valid(area) and is_instance_valid(area.owner) and area.owner is ProbeUnit:
		var probe_node: ProbeUnit = area.owner
		if probe_node in probes_in_comm_range:
			probes_in_comm_range.erase(probe_node)
			# print_debug("Probe %s: Probe %s exited comm range. Total: %s" % [probe_id, probe_node.probe_id, probes_in_comm_range.size()])

func get_nearby_probes() -> Array[ProbeUnit]:
	# Return a copy to prevent external modification of the internal list
	# Also filter out any potentially invalidated probes, though area_exited should handle it.
	var valid_probes: Array[ProbeUnit] = []
	for p in probes_in_comm_range:
		if is_instance_valid(p):
			valid_probes.append(p)
		else:
			# This case should ideally be rare if exited signals are reliable
			# print_debug("Probe %s: Found invalid probe in probes_in_comm_range during get_nearby_probes()" % probe_id)
			pass # Will be cleaned up on next access or if it formally exits
	probes_in_comm_range = valid_probes # Clean up internal list as well
	return valid_probes


# target_probe = null for broadcast
func send_communication(target_probe: ProbeUnit, message_type: MessageData.MessageType, payload: Dictionary = {}) -> bool:
	_last_communication_successful = false
	var cfg = _config_manager_instance.get_config()
	if not cfg:
		printerr("Probe %s: ConfigManager not available for send_communication." % probe_id)
		return false

	if communication_cooldown_remaining > 0:
		# print_debug("Probe %s: Communication failed - Cooldown active (%.1fs left)." % [probe_id, communication_cooldown_remaining])
		return false

	var _temp_val_L678 = cfg.get("communication_energy_cost")
	var energy_cost = _temp_val_L678 if _temp_val_L678 != null else 5.0 # Default if not in config
	if current_energy < energy_cost:
		# print_debug("Probe %s: Communication failed - Insufficient energy (need %.1f, have %.1f)." % [probe_id, energy_cost, current_energy])
		return false

	current_energy -= energy_cost
	var _temp_val_L684 = cfg.get("communication_cooldown")
	communication_cooldown_remaining = _temp_val_L684 if _temp_val_L684 != null else 5.0 # Default if not in config
	
	var msg_target_id = target_probe.probe_id if is_instance_valid(target_probe) else "BROADCAST"
	# MessageData constructor handles timestamp and sets global_position from sender
	var message := MessageData.new(probe_id, msg_target_id, message_type, global_position, payload)

	if communication_dish: # Visual feedback
		var tween = create_tween()
		tween.tween_property(communication_dish, "modulate", Color.LIGHT_BLUE.lightened(0.5), 0.2)
		tween.tween_property(communication_dish, "modulate", communication_dish.modulate, 0.3).set_delay(0.2)
	
	var audio_manager_node = get_node_or_null("/root/AudioManager")
	if audio_manager_node and audio_manager_node.has_method("play_sound_at_position"):
		audio_manager_node.play_sound_at_position("communication", global_position)
	elif audio_manager_node:
		printerr("Probe %s: AudioManager found, but no play_sound_at_position method." % probe_id)
	# else: printerr("Probe %s: AudioManager not found at /root/AudioManager." % probe_id) # Optional: less verbose if not found
	
	var main_scene_node = get_tree().current_scene if get_tree() else get_parent() # Fallback to parent if tree not ready

	var sent_to_at_least_one = false
	if is_instance_valid(target_probe):
		if target_probe.has_method("receive_message"):
			target_probe.receive_message(message)
			sent_to_at_least_one = true
			# print_debug("Probe %s: Sent direct message to %s: %s" % [probe_id, target_probe.probe_id, message.message_type])
			if CommunicationBeamScene and main_scene_node:
				var beam_instance = CommunicationBeamScene.instantiate()
				main_scene_node.add_child(beam_instance) # Add to main scene or effects layer
				beam_instance.setup_effect(global_position, target_probe.global_position)
	else: # Broadcast
		var nearby_probes_list: Array[ProbeUnit] = get_nearby_probes()
		var _temp_val_L716 = cfg.get("ai_debug_logging")
		var _actual_val_L716 = _temp_val_L716 if _temp_val_L716 != null else false
		if nearby_probes_list.is_empty() and _actual_val_L716:
			print_debug("Probe %s: Broadcast message type %s, but no probes in range." % [probe_id, MessageData.MessageType.keys()[message_type]])

		for other_probe in nearby_probes_list:
			if other_probe.has_method("receive_message"):
				other_probe.receive_message(message)
				sent_to_at_least_one = true
				if CommunicationBeamScene and main_scene_node:
					var beam_instance = CommunicationBeamScene.instantiate()
					main_scene_node.add_child(beam_instance)
					beam_instance.setup_effect(global_position, other_probe.global_position)
		# if sent_to_at_least_one or nearby_probes_list.is_empty(): # Log even if no one to send to for broadcast
			# print_debug("Probe %s: Broadcast message to %d probes: %s" % [probe_id, nearby_probes_list.size(), MessageData.MessageType.keys()[message_type]])


	communication_sent.emit(message) # Emit signal regardless of direct/broadcast for logging
	_last_communication_successful = sent_to_at_least_one # Considered successful if sent to target or any in broadcast
	
	var _temp_val_debug_logging = cfg.get("ai_debug_logging")
	var actual_debug_logging = _temp_val_debug_logging if _temp_val_debug_logging != null else false

	if actual_debug_logging and _last_communication_successful:
		print_debug("Probe %s: Sent '%s'. Target: %s. Payload: %s. Energy left: %.1f" % [probe_id, MessageData.MessageType.keys()[message_type], msg_target_id, str(payload), current_energy])
	elif actual_debug_logging and not sent_to_at_least_one and not is_instance_valid(target_probe):
		# Log broadcast attempt even if no one received, if debug is on
		pass # Already logged above if list was empty

	return _last_communication_successful

func receive_message(message: MessageData) -> void:
	var cfg = _config_manager_instance.get_config()
	var debug_logging
	if cfg:
		var _temp_val_L744 = cfg.get("ai_debug_logging")
		debug_logging = _temp_val_L744 if _temp_val_L744 != null else false
	else:
		debug_logging = false

	if debug_logging:
		print_debug("Probe %s: Received message from %s. Type: %s. Data: %s" % [probe_id, message.sender_id, MessageData.MessageType.keys()[message.message_type], str(message.data)])

	match message.message_type:
		MessageData.MessageType.RESOURCE_LOCATION: # Use enum directly
			var _temp_val_L751 = message.data.get("resource_pos")
			var res_pos: Vector2 = _temp_val_L751 if _temp_val_L751 != null else Vector2.INF # Use INF as invalid default
			var _temp_val_L752 = message.data.get("resource_type")
			var res_type: String = _temp_val_L752 if _temp_val_L752 != null else "unknown"
			var _temp_val_L753 = message.data.get("resource_id")
			var res_id: String = _temp_val_L753 if _temp_val_L753 != null else "" # Optional ID of the resource node

			if res_pos != Vector2.INF:
				# Store with position as key, could also use resource_id if consistently available and unique
				# For simplicity, using position. If multiple resources can be at the exact same spot, this might need refinement.
				if not known_resource_locations.has(res_pos):
					known_resource_locations[res_pos] = {
						"type": res_type,
						"timestamp": message.timestamp,
						"sender_id": message.sender_id, # Good to know who told us
						"resource_id": res_id
					}
					if debug_logging:
						print_debug("Probe %s: Added new known resource location from %s: %s at %s" % [probe_id, message.sender_id, res_type, str(res_pos)])
				else:
					# Optionally update if new info is more recent, or from a more trusted source, etc.
					# For now, just log if it's already known.
					if debug_logging:
						print_debug("Probe %s: Resource location %s already known." % [probe_id, str(res_pos)])
			elif debug_logging:
				print_debug("Probe %s: Received RESOURCE_LOCATION message with invalid position." % probe_id)

		MessageData.MessageType.ENERGY_REQUEST: # Use enum directly
			if debug_logging:
				print_debug("Probe %s: Received ENERGY_REQUEST (not implemented yet)." % probe_id)
			# TODO: Implement energy request handling (e.g., if this probe has surplus energy and AI decides to share)
		
		MessageData.MessageType.HELP_SIGNAL: # Use enum directly
			if debug_logging:
				print_debug("Probe %s: Received HELP_SIGNAL (not implemented yet)." % probe_id)
			# TODO: Implement help signal response (e.g., AI changes behavior to assist)

		MessageData.MessageType.PROBE_STATUS: # Use enum directly
			if debug_logging:
				print_debug("Probe %s: Received PROBE_STATUS from %s (not implemented yet)." % [probe_id, message.sender_id])
			# TODO: Store or react to status of other probes

		MessageData.MessageType.GENERAL_BROADCAST: # Use enum directly
			if debug_logging:
				print_debug("Probe %s: Received GENERAL_BROADCAST from %s: %s" % [probe_id, message.sender_id, str(message.data)])
		_:
			if debug_logging:
				print_debug("Probe %s: Received unknown message type: %s" % [probe_id, MessageData.MessageType.keys()[message.message_type]])


# --- Visual and Trail Updates ---
func update_movement_trail() -> void:
	if not movement_trail: return
	var cfg = _config_manager_instance.get_config(); var max_pts = 50
	if cfg: max_pts = cfg.get("max_trail_points")
	trail_points.push_front(global_position); while trail_points.size() > max_pts: trail_points.pop_back()
	movement_trail.clear_points(); for p in trail_points: movement_trail.add_point(to_local(p))

func update_visual_effects() -> void:
	if hull_sprite: hull_sprite.modulate = _base_hull_color.lightened(0.5) if is_selected else _base_hull_color
	if status_lights:
		var light1 = status_lights.get_node_or_null("StatusLight1")
		if light1 is Sprite2D:
			var er = current_energy/max_energy_capacity if max_energy_capacity > 0 else 0.0
			if er > 0.75:
				light1.modulate = Color.GREEN
			elif er > 0.25:
				light1.modulate = Color.YELLOW
			else:
				light1.modulate = Color.RED
	if mining_laser:
		if is_mining_active and current_target_resource_node and is_instance_valid(current_target_resource_node):
			if not mining_laser.visible: mining_laser.visible=true
			mining_laser.global_position=global_position; mining_laser.clear_points(); mining_laser.add_point(Vector2.ZERO)
			mining_laser.add_point(to_local(current_target_resource_node.global_position))
		elif mining_laser.visible: mining_laser.visible=false

# --- Getters for AI Agent ---
func get_observation_data() -> Dictionary:
	var obs = {}
	obs["position"] = global_position
	obs["velocity"] = linear_velocity
	obs["rotation"] = rotation # Radians
	obs["angular_velocity"] = angular_velocity # Radians/sec
	obs["energy_ratio"] = current_energy / max_energy_capacity if max_energy_capacity > 0 else 0.0
	obs["stored_resources"] = stored_resources
	obs["is_mining_active"] = is_mining_active
	obs["is_thrusting"] = is_thrusting and current_thrust_level_idx > 0
	obs["is_applying_torque"] = is_applying_torque and current_torque_level_idx > 0 and current_commanded_rotation_direction != 0
	
	if current_target_resource_node and is_instance_valid(current_target_resource_node):
		obs["current_target_resource_id"] = current_target_resource_node.name
		obs["target_resource_distance"] = global_position.distance_to(current_target_resource_node.global_position)
		obs["target_resource_relative_angle"] = (current_target_resource_node.global_position - global_position).angle_to(Vector2(1,0).rotated(rotation))
	else:
		obs["current_target_resource_id"] = ""
		obs["target_resource_distance"] = -1.0 
		obs["target_resource_relative_angle"] = 0.0
	obs["ai_target_idx"] = target_resource_idx_ai # AI's own relative index for its target

	var nearby_res_data = []
	for res_node in nearby_observed_resources_cache:
		if is_instance_valid(res_node):
			var r_data = {"id": res_node.name, "position": res_node.global_position, "distance": global_position.distance_to(res_node.global_position)}
			if res_node.has_method("get_resource_data"):
				var internal_data = res_node.get_resource_data()
				var _temp_type_id_L852 = internal_data.get("type_id")
				var _actual_type_id_L852 = _temp_type_id_L852 if _temp_type_id_L852 != null else 0
				r_data["type_id"] = _actual_type_id_L852
				var _temp_amount_L852 = internal_data.get("amount")
				var _actual_amount_L852 = _temp_amount_L852 if _temp_amount_L852 != null else 0.0
				r_data["amount"] = _actual_amount_L852
			elif res_node.has_property("resource_type_id") and res_node.has_property("current_amount"): r_data["type_id"]=res_node.get("resource_type_id"); r_data["amount"]=res_node.get("current_amount")
			else: r_data["type_id"]=0; r_data["amount"]=0.0
			nearby_res_data.append(r_data)
	obs["nearby_resources"] = nearby_res_data
	
	obs["nearby_celestial_bodies"] = [] # Placeholder
	
	var nearby_probe_data = []
	var current_nearby_probes = get_nearby_probes()
	for p_unit in current_nearby_probes:
		if is_instance_valid(p_unit): # Should always be true due to get_nearby_probes logic
			nearby_probe_data.append({
				"id": p_unit.probe_id,
				"position": p_unit.global_position,
				"distance": global_position.distance_to(p_unit.global_position)
				# Add other relevant probe info if needed by AI, e.g., energy level, status
			})
	obs["nearby_probes"] = nearby_probe_data

	# Add known resource locations to observation data (Sub-task 6)
	# This could be the full dict, or a processed version (e.g., closest N unknown)
	# For now, let's provide a simplified list of positions and types
	var known_res_obs_data = []
	for pos_key in known_resource_locations:
		var res_info = known_resource_locations[pos_key]
		var _temp_val_L880 = res_info.get("type")
		var _actual_val_L880 = _temp_val_L880 if _temp_val_L880 != null else "unknown"
		var _temp_val_L881 = res_info.get("timestamp")
		var _actual_val_L881 = _temp_val_L881 if _temp_val_L881 != null else 0
		var _temp_val_L882 = res_info.get("sender_id")
		var _actual_val_L882 = _temp_val_L882 if _temp_val_L882 != null else ""
		known_res_obs_data.append({
			"position": pos_key, # This is already a Vector2
			"type": _actual_val_L880,
			"timestamp": _actual_val_L881,
			"shared_by": _actual_val_L882
		})
	obs["known_resource_locations_shared"] = known_res_obs_data
	
	return obs

# --- Utility and Helper Functions ---
func get_id() -> String: return probe_id
func set_selected(selected: bool): is_selected = selected
func apply_damage(amount: float): current_energy -= amount; if current_energy <= 0 and is_alive: die()

# --- Getters for AIAgent specific state flags and helpers ---
func get_last_communication_success_flag() -> bool:
	# This flag indicates if the *last call* to attempt_communication() was successful in broadcasting.
	# It's reset at the beginning of each attempt_communication call.
	return _last_communication_successful

func get_just_replicated_flag() -> bool:
	# This flag indicates if the *last call* to attempt_replication() resulted in a successful spawn.
	# It's reset at the beginning of each attempt_replication call.
	# AIAgent should read it once per cycle if needed.
	return _just_replicated

func get_distance_to_observed_resource_idx(idx: int) -> float:
	if idx >= 0 and idx < nearby_observed_resources_cache.size():
		var res_node = nearby_observed_resources_cache[idx]
		if is_instance_valid(res_node):
			return global_position.distance_to(res_node.global_position)
	# print_debug("Probe %s: get_distance_to_observed_resource_idx: Invalid index %d or node." % [probe_id, idx])
	return -1.0 

func get_resource_id_for_observed_idx(idx: int) -> String:
	if idx >= 0 and idx < nearby_observed_resources_cache.size():
		var res_node = nearby_observed_resources_cache[idx]
		if is_instance_valid(res_node): # Assuming node name is the ID
			return res_node.name 
	# print_debug("Probe %s: get_resource_id_for_observed_idx: Invalid index %d or node." % [probe_id, idx])
	return ""

func is_currently_thrusting() -> bool: # Based on ramp ratio, actual effect
	return is_thrusting and current_thrust_level_idx > 0 and thrust_ramp_ratio > 0.01

func is_currently_applying_torque() -> bool: # Based on ramp ratio, actual effect
	return is_applying_torque and current_torque_level_idx > 0 and current_commanded_rotation_direction != 0 and rotation_ramp_ratio > 0.01

func get_current_target_node() -> Node: # Simple getter for AI to check if its target is valid
	if current_target_resource_node and is_instance_valid(current_target_resource_node):
		return current_target_resource_node
	return null
# --- UI Integration Methods ---

func get_details_for_ui() -> Dictionary:
	# TODO: Populate with actual data
	var velocity_vec = linear_velocity if self is RigidBody2D else Vector2.ZERO
	return {
		"id": probe_id,
		"generation": generation,
		"position": global_position,
		"velocity": velocity_vec,
		"task": get_current_task_name(),
		"target": str(get_current_target_id()),
		"status": "Alive" if is_alive else "Dead",
		"energy": current_energy,
		"max_energy": max_energy_capacity if max_energy_capacity > 0 else 1.0,
		"ai_enabled": is_ai_enabled()
	}

func apply_manual_thrust():
	# Corresponds to a high thrust level, e.g., index 3 if available
	var cfg = _config_manager_instance.get_config()
	if cfg:
		var _temp_val_L953 = cfg.get("thrust_force_magnitudes")
		var thrust_mags = _temp_val_L953 if _temp_val_L953 != null else [0.0, 0.08, 0.18, 0.32]
		var highest_level_idx = thrust_mags.size() - 1
		if highest_level_idx > 0:
			set_thrust_level(highest_level_idx)
			# print_debug("Probe %s: Manual thrust applied (level %d)" % [probe_id, highest_level_idx])
		else:
			# print_debug("Probe %s: Manual thrust - no thrust levels defined." % probe_id)
			set_thrust_level(0) # Ensure it's off
	else:
		# print_debug("Probe %s: Manual thrust - no config." % probe_id)
		set_thrust_level(0) # Ensure it's off

func apply_manual_rotation(direction_str: String):
	# Corresponds to a high torque level, e.g., index 2 if available
	var direction = -1 if direction_str == "left" else 1
	var cfg = _config_manager_instance.get_config()
	if cfg:
		var _temp_val_L970 = cfg.get("torque_magnitudes")
		var torque_mags = _temp_val_L970 if _temp_val_L970 != null else [0.0, 0.008, 0.018]
		var highest_level_idx = torque_mags.size() - 1
		if highest_level_idx > 0:
			set_torque_level(highest_level_idx, direction)
			# print_debug("Probe %s: Manual rotation %s applied (level %d)" % [probe_id, direction_str, highest_level_idx])
		else:
			# print_debug("Probe %s: Manual rotation - no torque levels defined." % probe_id)
			set_torque_level(0,0) # Ensure it's off
	else:
		# print_debug("Probe %s: Manual rotation - no config." % probe_id)
		set_torque_level(0,0) # Ensure it's off

func initiate_replication():
	# This is the probe's internal decision/action to start the process
	# It calls attempt_replication which handles costs and emits the signal
	var success = attempt_replication()
	# print_debug("Probe %s: initiate_replication called, result: %s" % [probe_id, success])

func set_ai_enabled(enabled: bool):
	if ai_agent and ai_agent.has_method("set_enabled"):
		ai_agent.set_enabled(enabled)
		# print_debug("Probe %s: AI control set to %s" % [probe_id, enabled])
	# else:
		# print_debug("Probe %s: AI agent not found or no set_enabled method." % probe_id)

func get_current_task_name() -> String:
	if ai_agent and ai_agent.has_method("get_current_task_display_name"):
		return ai_agent.get_current_task_display_name()
	return "Idle" # Default if no AI or method

func get_current_target_id(): # -> Variant (can be String, int, or null)
	if current_target_resource_node and is_instance_valid(current_target_resource_node):
		return current_target_resource_node.name # Assuming name is a good ID
	# Could also return an ID from AIAgent if it has a different target concept
	return null # Or "None" as a string if preferred by UI

func is_ai_enabled() -> bool:
	if ai_agent and ai_agent.has_method("is_enabled"):
		return ai_agent.is_enabled()
	return true # Default to true if no AI or method to check
