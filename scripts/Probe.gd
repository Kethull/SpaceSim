# Probe.gd
extends RigidBody2D
class_name Probe

var ConfigManager # Will hold the ConfigManager singleton instance

# ConfigManager is expected to be an autoload singleton, accessible globally.

const EnergyFieldShader = preload("res://shaders/EnergyField.gdshader")

@export_group("Probe Properties")
@export var probe_id: int = 0
@export var generation: int = 0
@export var probe_mass: float = 8.0 # Renamed from mass to avoid conflict

@export_group("Energy System")
@export var max_energy: float = 100000.0
@export var current_energy: float = 90000.0
@export var energy_decay_rate: float = 0.001

@export_group("Movement")
@export var max_velocity: float = 10000.0
@export var max_angular_velocity: float = PI / 4
@export var moment_of_inertia: float = 5.0

@onready var visual_component: Node2D = $VisualComponent
@onready var thruster_system: Node2D = $ThrusterSystem
@onready var sensor_array: Area2D = $SensorArray
@onready var communication_range: Area2D = $CommunicationRange
@onready var movement_trail: Line2D = $MovementTrail
@onready var mining_laser: Line2D = $MiningLaser
@onready var ai_agent: Node = $AIAgent
@onready var energy_system: Node = $EnergySystem
@onready var audio_component: AudioStreamPlayer2D = $AudioComponent

@onready var status_light: PointLight2D = null
@onready var main_thruster_light: PointLight2D = null
@onready var energy_field_sprite: Sprite2D = null
var energy_field_timer: Timer = null

const G: float = 6.67430e-11 # Gravitational constant (m^3 kg^-1 s^-2)
# const AU_TO_METERS: float = 1.496e11 # Not directly used here yet, but good for reference

# Debug Visuals
var _debug_label: Label
var _debug_target_line: Line2D
var _show_debug_visuals: bool = false

# State variables
var is_alive: bool = true
var is_mining: bool = false
var is_thrusting: bool = false
var is_communicating: bool = false
var current_target_id: int = -1
var current_task: String = "idle"
var target_resource: GameResource = null # To store the resource being mined

# Action state for RL
var current_thrust_level: int = 0
var current_torque_level: int = 0
var thrust_ramp_ratio: float = 0.0
var rotation_ramp_ratio: float = 0.0
var steps_in_current_thrust: int = 0
var steps_in_current_rotation: int = 0
var last_action_timestamp: int = -1
var target_resource_idx: int = -1
var time_since_last_target_switch: int = 0
var last_thrust_application_step: int = -1

# External forces (from celestial bodies)
var external_forces: Dictionary = {}

# Trail points
var trail_points: Array[Vector2] = []

# Signals
signal probe_destroyed(probe: Probe)
signal resource_discovered(probe: Probe, resource_position: Vector2, amount: float)
signal communication_sent(from_probe: Probe, to_position: Vector2, message_type: String)
signal replication_requested(parent_probe: Probe)
signal energy_critical(probe: Probe, energy_level: float)

func _ready():
	# Get the ConfigManager singleton
	if get_tree().has_singleton("ConfigManager"):
		ConfigManager = get_tree().get_root().get_node("ConfigManager")
	else:
		push_error("Probe.gd: ConfigManager singleton not found!")
		# Fallback or error handling if ConfigManager is crucial and not found
		# For now, we'll let it proceed, and usages of ConfigManager will check if it's null

	# Configure physics
	gravity_scale = 0  # We handle our own gravity
	set_collision_layer_value(2, true)  # Probes layer
	set_collision_mask_value(1, true)   # Interact with celestial bodies
	set_collision_mask_value(3, true)   # Interact with resources
	
	# Add to groups
	add_to_group("probes")
	
	# Initialize components
	setup_visual_appearance()
	setup_sensor_systems()
	setup_thruster_system()
	setup_advanced_visual_effects() # New function call
	_initialize_movement_trail_style()
	
	# Connect signals
	sensor_array.body_entered.connect(_on_sensor_body_entered)
	sensor_array.body_exited.connect(_on_sensor_body_exited)
	# communication_range.area_entered.connect(_on_communication_range_entered) # Stubbed for now
	
	# Initialize AI agent
	if ai_agent and ai_agent.has_method("initialize"):
		ai_agent.initialize(self)
	
	# Initialize Debug Visuals
	_debug_label = Label.new()
	_debug_label.name = "DebugLabel"
	_debug_label.text = "Initializing..."
	_debug_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_debug_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	# Basic font size, can be configured via theme or properties
	_debug_label.add_theme_font_size_override("font_size", 12) 
	_debug_label.modulate = Color(1,1,0,0.7) # Yellow, slightly transparent
	_debug_label.position = Vector2(0, -30) # Offset above the probe
	add_child(_debug_label)
	
	_debug_target_line = Line2D.new()
	_debug_target_line.name = "DebugTargetLine"
	_debug_target_line.width = 1.5
	_debug_target_line.default_color = Color(0, 1, 0, 0.6) # Green, slightly transparent
	add_child(_debug_target_line)
	
	if ConfigManager and ConfigManager.config:
		_show_debug_visuals = ConfigManager.config.get("ai_show_debug_visuals", false)
	
	_debug_label.visible = _show_debug_visuals
	_debug_target_line.visible = _show_debug_visuals

	# Register with LODManager
	var lod_manager = get_node_or_null("/root/LODManager")
	if lod_manager and lod_manager.has_method("register_object"):
		lod_manager.register_object(self)
	elif lod_manager:
		push_warning("Probe %d: LODManager found, but no register_object method." % probe_id)
	#else:
		#push_warning("Probe %d: LODManager not found for registration." % probe_id) # Can be noisy

func setup_visual_appearance():
	# Configure probe visual based on generation and energy
	var base_color = Color.CYAN
	if generation > 0:
		base_color = base_color.lerp(Color.YELLOW, min(generation * 0.1, 0.5))
	
	var hull_sprite = visual_component.get_node("HullSprite") as Sprite2D
	if hull_sprite:
		hull_sprite.modulate = base_color
	
	# Scale based on probe size config
	if ConfigManager and ConfigManager.has_method("get_config") and ConfigManager.get_config():
		var scale_factor = ConfigManager.get_config().probe_size / 24.0  # Assuming base sprite is 24px
		visual_component.scale = Vector2.ONE * scale_factor

func setup_sensor_systems():
	# Configure sensor array range
	var sensor_shape = sensor_array.get_node("SensorShape") as CollisionShape2D
	if sensor_shape and ConfigManager and ConfigManager.has_method("get_config") and ConfigManager.get_config():
		var circle_shape = CircleShape2D.new()
		circle_shape.radius = ConfigManager.get_config().discovery_range
		sensor_shape.shape = circle_shape
	# Set collision layer (none) and mask (detect Resources on layer 3)
	sensor_array.collision_layer = 0
	sensor_array.collision_mask = 1 << 2 # Detect layer 3 (Resources)
	
	# Configure communication range
	var comm_shape = communication_range.get_node("CommShape") as CollisionShape2D
	if comm_shape and ConfigManager and ConfigManager.has_method("get_config") and ConfigManager.get_config():
		var comm_circle = CircleShape2D.new()
		comm_circle.radius = ConfigManager.get_config().communication_range
		comm_shape.shape = comm_circle
	# Set collision layer (none) and mask (detect Probes on layer 2)
	communication_range.collision_layer = 0
	communication_range.collision_mask = 1 << 1 # Detect layer 2 (Probes)

func setup_thruster_system():
	# Configure all thruster particle systems
	# Placeholder: Detailed particle configuration can be deferred.
	# Ensure nodes exist as per Probe.tscn
	var main_thruster = thruster_system.get_node_or_null("MainThruster") as GPUParticles2D
	if main_thruster:
		pass # configure_thruster_particles(main_thruster, Vector2(0, 1)) # Rear-facing
	
	# RCS thrusters
	# configure_thruster_particles(thruster_system.get_node_or_null("RCSThrusterN") as GPUParticles2D, Vector2(0, -1))
	# configure_thruster_particles(thruster_system.get_node_or_null("RCSThrusterS") as GPUParticles2D, Vector2(0, 1))
	# configure_thruster_particles(thruster_system.get_node_or_null("RCSThrusterE") as GPUParticles2D, Vector2(1, 0))
	# configure_thruster_particles(thruster_system.get_node_or_null("RCSThrusterW") as GPUParticles2D, Vector2(-1, 0))
	pass

# func configure_thruster_particles(thruster: GPUParticles2D, direction: Vector2): # Stubbed for now
	# var material = ParticleProcessMaterial.new()
	# material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	# material.emission_sphere_radius = 1.0
	# material.direction = Vector3(direction.x, direction.y, 0)
	# material.spread = 15.0
	# material.gravity = Vector3.ZERO
	# material.initial_velocity_min = 20.0
	# material.initial_velocity_max = 40.0
	# material.angular_velocity_min = -30.0
	# material.angular_velocity_max = 30.0
	# material.scale_min = 0.05
	# material.scale_max = 0.15
	# material.color = Color(0.5, 0.7, 1.0, 0.8) # Light blueish
	# material.lifetime = 0.5
	# thruster.process_material = material
	# thruster.amount = 8
	# thruster.emitting = false

func setup_advanced_visual_effects():
	# Status Light
	status_light = PointLight2D.new()
	status_light.name = "StatusLight"
	# Attempt to load a small circle texture for light, fallback to icon.svg
	var light_texture = load("res://assets/textures/small_circle_glow.png") if FileAccess.file_exists("res://assets/textures/small_circle_glow.png") else preload("res://icon.svg")
	status_light.texture = light_texture
	status_light.texture_scale = 0.05 if light_texture.resource_path.contains("small_circle_glow") else 0.1
	status_light.color = Color.CYAN
	status_light.energy = 0.8
	status_light.range_item_cull_mask = 1 # Assuming default cull mask
	visual_component.add_child(status_light) # Add to visual component to follow probe

	# Main Thruster Light (attached near where a main thruster would be)
	main_thruster_light = PointLight2D.new()
	main_thruster_light.name = "MainThrusterLight"
	main_thruster_light.texture = light_texture # Reuse light texture
	main_thruster_light.texture_scale = 0.08 if light_texture.resource_path.contains("small_circle_glow") else 0.15
	main_thruster_light.color = Color(1.0, 0.7, 0.2, 1.0) # Orangey
	main_thruster_light.energy = 1.5
	main_thruster_light.enabled = false # Off by default
	# Position it at the "rear" of the probe visual. Assuming visual_component is centered.
	# And probe points "up" (negative Y in local coords for forward thrust)
	var hull_sprite = visual_component.get_node_or_null("HullSprite") as Sprite2D
	var rear_offset = Vector2(0, 15) # Default if no hull sprite
	if hull_sprite and hull_sprite.texture:
		rear_offset = Vector2(0, hull_sprite.texture.get_height() * visual_component.scale.y / 2 + 5)
	main_thruster_light.position = rear_offset
	visual_component.add_child(main_thruster_light)

	# Energy Field Sprite
	energy_field_sprite = Sprite2D.new()
	energy_field_sprite.name = "EnergyFieldSprite"
	var field_material = ShaderMaterial.new()
	field_material.shader = EnergyFieldShader
	field_material.set_shader_parameter("field_color", Color(0.2, 1.0, 0.8))
	field_material.set_shader_parameter("field_strength", 1.0)
	field_material.set_shader_parameter("pulse_speed", 2.0)
	energy_field_sprite.material = field_material
	# Use a white circle texture if available, otherwise fallback
	var field_texture = load("res://assets/textures/white_circle.png") if FileAccess.file_exists("res://assets/textures/white_circle.png") else preload("res://icon.svg")
	energy_field_sprite.texture = field_texture
	
	var sprite_scale = 1.0 # Default scale
	if hull_sprite and hull_sprite.texture: # Scale field to be larger than hull
		var max_dim_hull = max(hull_sprite.texture.get_width(), hull_sprite.texture.get_height()) * visual_component.scale.x
		var field_tex_width = energy_field_sprite.texture.get_width() if energy_field_sprite.texture else 128.0
		sprite_scale = (max_dim_hull + 20.0) / field_tex_width # Adjust based on field texture size
	else: # Fallback scale if no hull sprite
		var field_tex_width = energy_field_sprite.texture.get_width() if energy_field_sprite.texture else 128.0
		sprite_scale = (50.0) / field_tex_width # Assuming a default probe size around 50px

	energy_field_sprite.scale = Vector2.ONE * sprite_scale
	energy_field_sprite.visible = false
	visual_component.add_child(energy_field_sprite)

	energy_field_timer = Timer.new()
	energy_field_timer.name = "EnergyFieldTimer"
	energy_field_timer.one_shot = true
	energy_field_timer.timeout.connect(_on_energy_field_timer_timeout)
	add_child(energy_field_timer)

func _integrate_forces(state: PhysicsDirectBodyState2D):
	var total_gravitational_force = Vector2.ZERO
	if ConfigManager and ConfigManager.config:
		var sim_scale = ConfigManager.config.get("simulation_scale", 1.0) # pixels per meter
		var use_n_body = ConfigManager.config.get("use_n_body_gravity", true) # Assuming this applies to probes too
		var max_interaction_dist_meters = ConfigManager.config.n_body_interaction_max_distance_meters
		
		if use_n_body:
			var celestial_bodies = get_tree().get_nodes_in_group("celestial_bodies")
			for body_node in celestial_bodies:
				if not body_node is CelestialBody:
					continue
				
				var celestial_body: CelestialBody = body_node
				
				var direction_vector_pixels = celestial_body.global_position - global_position
				var distance_pixels = direction_vector_pixels.length()
				
				if distance_pixels == 0:
					continue
					
				var distance_meters = distance_pixels / sim_scale
				
				if distance_meters > max_interaction_dist_meters:
					continue # Skip if too far
					
				if distance_meters < 1.0: # Avoid extreme forces at very close (sub-meter) distances
					distance_meters = 1.0
				
				# Newton's law of universal gravitation: F = G * (m1 * m2) / r^2
				# probe_mass is this probe's mass in kg
				var force_magnitude_newtons = (G * probe_mass * celestial_body.mass_kg) / (distance_meters * distance_meters)
				
				# Convert force from Newtons to Godot physics units
				# Acceleration_m_s2 = Force_newtons / probe_mass
				# Force_engine = Acceleration_m_s2 * sim_scale (assuming RigidBody2D.mass = 1 for probe in physics engine terms)
				# Or, more directly, if RigidBody2D.mass is set to probe_mass, then Force_engine = Force_newtons * scale_factor
				# For consistency with CelestialBody.gd, let's use the acceleration approach.
				# The probe's RigidBody2D.mass should ideally be 1 if we use this, or adjust calculation.
				# Assuming probe's RigidBody2D.mass is 1 for this calculation.
				var acceleration_m_s2 = force_magnitude_newtons / probe_mass
				var force_godot_units = direction_vector_pixels.normalized() * (acceleration_m_s2 * sim_scale)
				
				total_gravitational_force += force_godot_units

	# Apply calculated gravitational force
	state.apply_central_force(total_gravitational_force)

	# Apply other external forces (if any, from the dictionary - this might be for non-gravitational forces)
	var other_forces = Vector2.ZERO
	for force_name in external_forces: # This dict might be for thrusters, impacts, etc. if not gravity
		other_forces += external_forces[force_name]
	if other_forces.length_squared() > 0: # Only apply if there are other forces
		state.apply_central_force(other_forces)
	
	# Apply thrust forces
	if is_thrusting and current_thrust_level > 0 and ConfigManager and ConfigManager.has_method("get_config") and ConfigManager.get_config():
		var current_config = ConfigManager.get_config()
		if current_config: # Ensure current_config is not null
			var thrust_magnitude = current_config.thrust_force_magnitudes[current_thrust_level] if current_config.has_method("has") and current_config.has("thrust_force_magnitudes") and current_thrust_level < current_config.thrust_force_magnitudes.size() else 10.0
			var thrust_force = Vector2(0, -thrust_magnitude).rotated(rotation)  # Forward direction
			# thrust_force *= thrust_ramp_ratio # Simplified for now
			state.apply_central_force(thrust_force)
			set_thruster_glow(true)
			
			# Apply energy cost
			var energy_cost_factor = current_config.thrust_energy_cost_factor if current_config.has_method("has") and current_config.has("thrust_energy_cost_factor") else 0.1
			var energy_cost = thrust_magnitude * energy_cost_factor
			consume_energy(energy_cost * state.step) # Multiply by state.step for per-second rate
	else:
		if is_thrusting: # is_thrusting might be true but level is 0
			set_thruster_glow(false)
			is_thrusting = false # Ensure this is reset if thrust_level became 0
		elif main_thruster_light and main_thruster_light.enabled: # If not thrusting for any other reason
			set_thruster_glow(false)

	# Apply torque for rotation (minimal for now)
	if current_torque_level > 0 and ConfigManager and ConfigManager.has_method("get_config") and ConfigManager.get_config():
		var current_config = ConfigManager.get_config()
		if current_config: # Ensure current_config is not null
			var torque_magnitude = current_config.torque_magnitudes[current_torque_level] if current_config.has_method("has") and current_config.has("torque_magnitudes") and current_torque_level < current_config.torque_magnitudes.size() else 1.0
			var applied_torque = torque_magnitude # * rotation_ramp_ratio # Simplified for now
			
			# Determine rotation direction based on AI action (simplified)
			# if ai_agent.current_rotation_direction > 0: # Assuming ai_agent has this, simplified
				# applied_torque = -applied_torque  # Clockwise
			
			state.apply_torque(applied_torque)
			
			# Apply energy cost for rotation
			var energy_cost = torque_magnitude * 0.1  # Rotational energy cost factor
			consume_energy(energy_cost * state.step) # Multiply by state.step for per-second rate
	
	# Limit velocities
	if state.linear_velocity.length() > max_velocity:
		state.linear_velocity = state.linear_velocity.normalized() * max_velocity
	
	if abs(state.angular_velocity) > max_angular_velocity:
		state.angular_velocity = sign(state.angular_velocity) * max_angular_velocity

func _physics_process(delta):
	# Update energy decay
	if ConfigManager and ConfigManager.has_method("get_config") and ConfigManager.get_config():
		var current_config = ConfigManager.get_config()
		if current_config: # Ensure current_config is not null
			current_energy -= current_config.energy_decay_rate * delta
	
	# Check for death
	if current_energy <= 0 and is_alive:
		die()
	
	# Update visual effects based on energy (stubbed)
	update_status_light()
	
	# Update movement trail
	update_movement_trail()
	
	# Update AI agent (stubbed)
	# if is_alive and ai_agent and ai_agent.has_method("update_step"):
		# ai_agent.update_step(delta)
	
	_update_debug_visuals() # Call to update debug visuals
	
	# Harvesting logic
	if is_mining and is_instance_valid(target_resource) and is_alive:
		if ConfigManager and ConfigManager.has_method("get_config") and ConfigManager.get_config():
			var current_config = ConfigManager.get_config()
			if current_config: # Ensure current_config is not null
				var distance_to_target = global_position.distance_to(target_resource.global_position)
				if distance_to_target <= current_config.harvest_distance:
					# The actual harvesting (reducing resource amount and giving energy to probe)
					# is handled by Resource.gd's process_harvesting, which is called
					# because the probe is in the Resource's CollectionShape.
					# Here, we just ensure the probe *knows* it's mining.
					# The Resource.gd script will call target_resource.harvest()
					# and then give energy to the probe.
					# This probe-side call to harvest is more for if the Resource itself
					# doesn't have an active harvesting loop based on bodies in its area.
					# However, the prompt implies Resource.gd's process_harvesting is the main driver.
					# Let's stick to the prompt: Probe calls target_resource.harvest()
					
					var amount_to_harvest = current_config.harvest_rate * delta * target_resource.harvest_difficulty
					var actual_harvested = target_resource.harvest(amount_to_harvest)
					
					# Energy gain is handled by Resource.gd's process_harvesting,
					# which calls probe.current_energy += ...
					# So, no explicit energy gain here in Probe.gd from this call.
					# The call to target_resource.harvest() will trigger signals
					# and logic within Resource.gd.
					if actual_harvested <= 0 and target_resource.current_amount <= 0:
						# Resource might be depleted by this harvest attempt or already depleted
						stop_mining() # Stop if resource is gone
				else:
					# Target is out of range, stop mining
					# This case should ideally be handled by Resource's _on_body_exited
					# calling probe.stop_mining(), but good to have a fallback.
					if is_instance_valid(target_resource): # Check again before calling stop_mining
						print("Probe %d: Target %s out of harvest range. Stopping mining." % [probe_id, target_resource.name])
						stop_mining()
		else:
			if is_instance_valid(target_resource): # Check before logging
				print("Probe %d: ConfigManager not available for harvesting %s." % [probe_id, target_resource.name])
			stop_mining() # Cannot harvest without config
	elif is_mining and not is_instance_valid(target_resource):
		# Target became invalid (e.g., freed)
		print("Probe %d: Target resource became invalid. Stopping mining." % probe_id)
		stop_mining()
		
	# Update action smoothing (stubbed)
	# update_action_smoothing(delta)
	
	# Check for low energy warning
	if current_energy < max_energy * 0.25 and is_alive:
		energy_critical.emit(self, current_energy)

func _initialize_movement_trail_style(): # Call this in _ready
	if not is_instance_valid(movement_trail):
		return

	movement_trail.width = 1.5 # Slightly thinner than orbit trails
	
	var trail_color = Color.LIGHT_SKY_BLUE # Distinct color for probes
	trail_color.a = 0.4
	movement_trail.default_color = trail_color

	var gradient = Gradient.new()
	gradient.add_point(0.0, trail_color)
	var end_color = trail_color
	end_color.a = 0.0
	gradient.add_point(1.0, end_color)
	movement_trail.gradient = gradient

func update_movement_trail():
	if not is_instance_valid(movement_trail) or not ConfigManager or not ConfigManager.config:
		if is_instance_valid(movement_trail): # Only disable if trail exists but config doesn't
			movement_trail.visible = false
		return

	# Use enable_particle_effects to also control trails for simplicity
	if not ConfigManager.config.get("enable_particle_effects", true):
		movement_trail.visible = false
		return
	
	movement_trail.visible = true

	var max_points = ConfigManager.config.max_trail_points
	var trail_update_interval = ConfigManager.config.probe_movement_trail_update_interval_frames

	if trail_update_interval <= 0: # Prevent division by zero or too frequent updates
		trail_update_interval = 1

	if Engine.get_physics_frames() % trail_update_interval == 0:
		trail_points.push_front(global_position)
		if trail_points.size() > max_points:
			trail_points.resize(max_points)

		if movement_trail: # Check again, as it might have become invalid
			movement_trail.clear_points()
			var local_points: Array[Vector2] = []
			for p_global in trail_points:
				local_points.append(movement_trail.to_local(p_global))
			
			if local_points.size() > 1:
				movement_trail.points = PackedVector2Array(local_points)

# func update_visual_effects(): # Stubbed
	# pass

# func update_movement_trail(): # Stubbed # This line will be effectively removed by the insertion above if it matches.
	# pass

# func update_action_smoothing(delta): # Stubbed
	# pass

# func update_thruster_effects(): # Stubbed
	# pass

func apply_external_force(force: Vector2, force_name: String):
	external_forces[force_name] = force

func remove_external_force(force_name: String):
	external_forces.erase(force_name)

func consume_energy(amount: float):
	current_energy = max(0.0, current_energy - amount)

func die():
	if not is_alive:
		return
	
	is_alive = false
	set_collision_layer_value(2, false)  # Remove from probe layer
	set_collision_mask_value(1, false)
	set_collision_mask_value(3, false)
	
	# Visual death effect
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(visual_component, "modulate", Color.RED, 1.0)
	tween.tween_property(visual_component, "scale", Vector2.ZERO, 1.0)
	tween.tween_callback(queue_free)
	
	probe_destroyed.emit(self)

# Stubbed functions from original prompt, to be implemented later
func _on_sensor_body_entered(body):
	if body is GameResource:
		var resource: GameResource = body
		# Emit signal with probe, resource position, and current amount
		resource_discovered.emit(self, resource.global_position, resource.current_amount)
		print("Probe %d discovered resource %s at %s with amount %f" % [probe_id, resource.name, str(resource.global_position), resource.current_amount])
		# Future AI logic might decide to target this resource here.
		# For now, discovery is sufficient. Resource.gd handles initiating mining via its own collision.

func _on_sensor_body_exited(body):
	if body is GameResource:
		var resource: GameResource = body
		print("Probe %d: Resource %s exited sensor range." % [probe_id, resource.name])
		# If this resource was the target_resource and it exited sensor range,
		# it doesn't necessarily mean stop_mining, as mining range is different.
		# stop_mining is primarily handled by Resource's CollectionShape exit.

func _on_communication_range_entered(area):
	pass

func attempt_replication():
	print("Probe %d attempting replication (stubbed)." % probe_id)
	# replication_requested.emit(self) # Will be implemented later

func start_mining(resource_node: GameResource):
	if not is_instance_valid(resource_node):
		print("Probe %d: Attempted to start mining an invalid resource node." % probe_id)
		is_mining = false # Ensure it's false
		target_resource = null
		current_task = "idle" # Or previous task
		return

	if is_mining and target_resource == resource_node:
		# Already mining this resource
		return

	print("Probe %d starting mining on %s." % [probe_id, resource_node.name])
	is_mining = true
	target_resource = resource_node
	current_task = "mining"
	# Visuals for mining laser are for a later step (Step 17/19)
	# mining_laser.points = [Vector2.ZERO, to_local(target_resource.global_position)]
	# mining_laser.visible = true

func stop_mining():
	if not is_mining: # Already stopped or was never mining
		return

	var resource_name = "Unknown"
	if is_instance_valid(target_resource):
		resource_name = target_resource.name
		
	print("Probe %d stopping mining on %s." % [probe_id, resource_name])
	is_mining = false
	target_resource = null
	current_task = "idle" # Or revert to a previous task if more complex state mgt is added
	# mining_laser.visible = false

func get_observation_data() -> Dictionary:
	# Basic observation data, will be expanded for RL
	return {
		"position": global_position,
		"velocity": linear_velocity,
		"rotation": rotation,
		"angular_velocity": angular_velocity,
		"current_energy": current_energy,
		"is_alive": is_alive
	}

func set_action(action: Array):
	# Placeholder for AI control
	# Example: action = [thrust_level, torque_level, mine_action, replicate_action]
	if action.size() >= 2:
		current_thrust_level = int(action[0])
		current_torque_level = int(action[1])
		is_thrusting = current_thrust_level > 0 # Basic assumption
	# print("Probe %d received action: %s (stubbed)" % [probe_id, str(action)])
	pass

func _update_debug_visuals():
	if not is_instance_valid(_debug_label) or not is_instance_valid(_debug_target_line):
		return

	var should_show_now = false
	if ConfigManager and ConfigManager.config:
		should_show_now = ConfigManager.config.get("ai_show_debug_visuals", false)

	if _show_debug_visuals != should_show_now: # Update if changed
		_show_debug_visuals = should_show_now
		_debug_label.visible = _show_debug_visuals
		_debug_target_line.visible = _show_debug_visuals
	
	if not _show_debug_visuals:
		return

	# Update Label Text
	var ai_action_str = "NoAction"
	if is_instance_valid(ai_agent):
		if ai_agent.has_method("_action_to_string") and ai_agent.current_action != null and not ai_agent.current_action.is_empty():
			ai_action_str = ai_agent._action_to_string(ai_agent.current_action)
		elif ai_agent.current_action != null and not ai_agent.current_action.is_empty(): # Fallback if no _action_to_string
			ai_action_str = str(ai_agent.current_action)
	
	_debug_label.text = "Task: %s\nAction: %s" % [current_task, ai_action_str]
	
	# Update Target Line
	if is_instance_valid(target_resource) and target_resource.is_inside_tree():
		_debug_target_line.clear_points()
		_debug_target_line.add_point(Vector2.ZERO) 
		_debug_target_line.add_point(to_local(target_resource.global_position))
	else:
		_debug_target_line.clear_points()

# --- Advanced Visual Effects Control ---

func update_status_light():
	if not is_instance_valid(status_light):
		return

	if not is_alive:
		status_light.color = Color.BLACK
		status_light.energy = 0
		status_light.enabled = false
		return

	status_light.enabled = true
	var energy_ratio = current_energy / max_energy
	if energy_ratio > 0.75:
		status_light.color = Color.CYAN
		status_light.energy = 0.8
	elif energy_ratio > 0.25:
		status_light.color = Color.YELLOW
		status_light.energy = 1.0
	else:
		status_light.color = Color.RED
		status_light.energy = 1.2
		# Could add blinking effect here with a timer or tween

func set_thruster_glow(is_active: bool):
	if not is_instance_valid(main_thruster_light):
		return
	main_thruster_light.enabled = is_active
	
	# Example: Use AdvancedParticleManager for thruster exhaust
	var apm = get_node_or_null("/root/AdvancedParticleManager")
	if apm:
		if is_active:
			# Calculate thruster position and direction
			var thruster_global_pos = visual_component.to_global(main_thruster_light.position)
			var direction_vector = -global_transform.y.normalized() # Probe's "up" is -Y, so thrust is opposite
			apm.create_thruster_effect(thruster_global_pos, direction_vector, 1.0, self) # Intensity 1.0, parented
		else:
			# How to stop a specific thruster effect?
			# AdvancedParticleManager needs a way to find and stop effects for a given parent/type.
			# For now, effects will time out based on their own logic.
			pass


func activate_energy_field(strength: float = 1.0, duration: float = 2.0):
	if not is_instance_valid(energy_field_sprite) or not is_instance_valid(energy_field_timer):
		return
	
	var mat = energy_field_sprite.material as ShaderMaterial
	if mat:
		mat.set_shader_parameter("field_strength", clampf(strength, 0.1, 2.0))
	
	energy_field_sprite.visible = true
	energy_field_timer.start(duration)
	# Optional: Play a sound effect

func _on_energy_field_timer_timeout():
	if is_instance_valid(energy_field_sprite):
		energy_field_sprite.visible = false
	# Optional: Play sound effect for field down