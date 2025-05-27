extends RigidBody2D
class_name CelestialBody

## Emitted when the celestial body is clicked.
signal body_clicked(body: CelestialBody)

@export_group("Physical Properties")
## The name of the celestial body.
@export var body_name: String = "Celestial Body"
## The mass of the body in kilograms.
@export var mass_kg: float = 1.0e22 # Default to a large rock
## The radius of the body in kilometers.
@export var radius_km: float = 1000.0
## The visual radius of the body in pixels for display purposes.
@export var display_radius: float = 50.0
## The color of the body.
@export var body_color: Color = Color.WHITE
## The color of the atmosphere glow, if any.
@export var atmosphere_color: Color = Color(1.0, 1.0, 1.0, 0.2)
## The scale factor for the atmosphere glow relative to the body's display_radius.
@export var atmosphere_scale: float = 1.5
## The unique identifier for this body, typically its name.
@export var body_id: String = ""
## Optional: Audio key for a looping ambient sound for this body (e.g., "earth_ambient"). Must be defined in AudioManager.
@export var ambient_sound_key: String = ""

@export_group("Orbital Elements (J2000.0)")
## The name of the central body this object orbits. Leave empty for the system's primary star or if not orbiting.
@export var central_body_name: String = ""
## Semi-major axis in astronomical units (AU).
@export var semi_major_axis_au: float = 0.0
## Eccentricity of the orbit (0 for circular, <1 for elliptical).
@export var eccentricity: float = 0.0
## Inclination of the orbit in degrees.
@export var inclination_deg: float = 0.0
## Longitude of the ascending node in degrees.
@export var longitude_of_ascending_node_deg: float = 0.0
## Argument of periapsis in degrees.
@export var argument_of_periapsis_deg: float = 0.0
## Mean anomaly at epoch in degrees.
@export var mean_anomaly_at_epoch_deg: float = 0.0
## Epoch time for the orbital elements (e.g., J2000.0). Not directly used in simple Kepler solver yet.
# @export var epoch_jd: float = 2451545.0 # J2000.0

@onready var visual_component: Node2D = $VisualComponent
@onready var body_sprite: Sprite2D = $VisualComponent/BodySprite
@onready var atmosphere_glow: Sprite2D = $VisualComponent/AtmosphereGlow
@onready var body_collision_shape: CollisionShape2D = $BodyCollisionShape
@onready var orbit_trail: Line2D = $OrbitTrail
@onready var gravity_field: Area2D = $GravityField
@onready var gravity_shape: CollisionShape2D = $GravityField/GravityShape
@onready var config_manager = get_node("/root/ConfigManager") # Access autoload

const PlanetAtmosphereShader = preload("res://shaders/PlanetAtmosphere.gdshader")

var central_body: CelestialBody = null
var orbit_points: Array[Vector2] = []
var previous_acceleration: Vector2 = Vector2.ZERO
var previous_position: Vector2 = Vector2.ZERO # Added for Verlet integration
var ambient_audio_player: AudioStreamPlayer2D = null

const G: float = 6.67430e-11 # Gravitational constant (m^3 kg^-1 s^-2)
const AU_TO_METERS: float = 1.496e11 # Astronomical Unit in meters

func _ready():
	gravity_scale = 0 # We will apply gravity manually
	
	# Configure integration method
	if config_manager and config_manager.config:
		if config_manager.config.integration_method == "verlet":
			custom_integrator = true
			#print("[%s] Using Verlet integration." % body_name) # Optional: for debugging
		#else:
			#print("[%s] Using Godot default integration." % body_name) # Optional: for debugging
	
	# Collision layers and masks
	# Layer 1: CelestialBodies
	# Layer 2: Probes
	# Layer 3: Projectiles (example)
	set_collision_layer_value(1, true)  # This body is a CelestialBody
	set_collision_mask_value(1, true)   # Collide with other CelestialBodies (for n-body, though not primary interaction method)
	set_collision_mask_value(2, true)   # Probes can collide with this body
	
	if body_id == "":
		body_id = body_name # Default body_id to body_name if not set

	setup_visual_appearance()
	calculate_initial_state()
	
	# Connect input_event signal for click detection
	self.input_event.connect(_on_input_event)
	
	add_to_group("celestial_bodies")
	
	# Set GravityField properties
	# The gravity field itself doesn't need to collide with other celestial bodies for n-body physics
	# It's primarily for probes or other objects that might react to entering an SOI.
	# We can adjust its collision layer/mask if specific interactions are needed.
	# For now, let's assume probes are on layer 2 and gravity field should detect them.
	gravity_field.set_collision_layer_value(1, false) # Gravity field is not a physical body itself
	gravity_field.set_collision_mask_value(2, true)  # Detect Probes (layer 2)

	# Play ambient sound if configured
	if not ambient_sound_key.is_empty():
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("play_looping_sound"):
			# The volume_multiplier is 1.0 because AudioManager handles category volumes (ambient_volume)
			ambient_audio_player = audio_manager.play_looping_sound(ambient_sound_key, global_position, 1.0)
			if not is_instance_valid(ambient_audio_player):
				printerr("CelestialBody %s: Failed to start ambient sound '%s'." % [body_name, ambient_sound_key])
		elif audio_manager:
			printerr("CelestialBody %s: AudioManager found, but no play_looping_sound method for ambient sound." % body_name)
		# else: printerr("CelestialBody %s: AudioManager not found for ambient sound." % body_name) # Optional: less verbose

	# Register with LODManager
	var lod_manager = get_node_or_null("/root/LODManager")
	if lod_manager and lod_manager.has_method("register_object"):
		lod_manager.register_object(self)
	elif lod_manager:
		push_warning("CelestialBody %s: LODManager found, but no register_object method." % body_name)
	#else:
		#push_warning("CelestialBody %s: LODManager not found for registration." % body_name) # Can be noisy

func setup_visual_appearance():
	if body_sprite:
		body_sprite.modulate = body_color
		# Scale sprite to match display_radius. Assuming icon.svg is 128x128.
		# This might need adjustment if your placeholder is different or you want a fixed pixel size.
		var texture_size : Vector2 = body_sprite.texture.get_size() if body_sprite.texture else Vector2(128,128)
		if texture_size.x > 0 and texture_size.y > 0:
			body_sprite.scale = Vector2(display_radius * 2.0 / texture_size.x, display_radius * 2.0 / texture_size.y)

	if atmosphere_glow:
		var mat = ShaderMaterial.new()
		mat.shader = PlanetAtmosphereShader
		mat.set_shader_parameter("atmosphere_color", atmosphere_color) # Initial color
		mat.set_shader_parameter("atmosphere_thickness", 0.1) # Example, can be exported or configured
		mat.set_shader_parameter("glow_intensity", 1.0) # Example
		mat.set_shader_parameter("rotation_speed", 0.05) # Example
		atmosphere_glow.material = mat
		
		# Scale sprite to match display_radius. Assuming icon.svg is 128x128.
		# The shader works on UVs, so the sprite's texture and scale are important.
		# We want the atmosphere to encompass the body.
		var glow_texture_size : Vector2 = atmosphere_glow.texture.get_size() if atmosphere_glow.texture else Vector2(128,128)
		if glow_texture_size.x > 0 and glow_texture_size.y > 0:
			var glow_display_radius = display_radius * atmosphere_scale # Make atmosphere slightly larger
			atmosphere_glow.scale = Vector2(glow_display_radius * 2.0 / glow_texture_size.x, glow_display_radius * 2.0 / glow_texture_size.y)
		atmosphere_glow.visible = atmosphere_color.a > 0.01 # Hide if base color is transparent

	if body_collision_shape and body_collision_shape.shape is CircleShape2D:
		(body_collision_shape.shape as CircleShape2D).radius = display_radius
	
	if gravity_shape and gravity_shape.shape is CircleShape2D:
		# Example: Gravity field is 5x the display radius. This is arbitrary and can be configured.
		# Or, it could be based on actual SOI calculations if available.
		(gravity_shape.shape as CircleShape2D).radius = display_radius * config_manager.get_setting("simulation", "gravity_field_radius_multiplier", 5.0)

	setup_orbit_trail_style() # Call the new style function


func setup_orbit_trail_style():
	if orbit_trail:
		orbit_trail.width = 2.0 # As per prompt example
		
		var trail_color = body_color.lerp(Color.GRAY, 0.5) # Mix body color with gray
		trail_color.a = 0.5 # Semi-transparent
		orbit_trail.default_color = trail_color

		# Optional: Add a gradient for fading trail
		var gradient = Gradient.new()
		# For Gradient resource in Godot 4, use add_point(offset, color)
		gradient.add_point(0.0, trail_color) # Start point of the gradient
		
		var end_color = trail_color # Start with the trail color
		end_color.a = 0.0 # Fade to fully transparent
		gradient.add_point(1.0, end_color) # End point of the gradient
		
		orbit_trail.gradient = gradient


func calculate_initial_state():
	central_body = find_central_body()
	if central_body:
		var state_vector = calculate_state_from_orbital_elements(
			central_body.mass_kg,
			semi_major_axis_au,
			eccentricity,
			inclination_deg,
			longitude_of_ascending_node_deg,
			argument_of_periapsis_deg,
			mean_anomaly_at_epoch_deg
		)
		# Convert position from meters (relative to central body) to global Godot units
		# and velocity from m/s to Godot units/s.
		var sim_scale = config_manager.get_setting("simulation", "simulation_scale", 1.0) # pixels per meter
		
		global_position = central_body.global_position + state_vector[0] * sim_scale
		linear_velocity = state_vector[1] * sim_scale
		
		#print("%s initial state relative to %s: Pos: %s m, Vel: %s m/s" % [body_name, central_body.body_name, state_vector[0], state_vector[1]])
		#print("%s initial global pos: %s, initial vel: %s" % [body_name, global_position, linear_velocity])
	else:
		# If no central body, assume it's the primary star or a static object at its given position.
		# Its global_position is set by the editor or instantiation.
		# Linear velocity could be set directly in editor or remain (0,0)
		#print("%s has no central body, using editor position and velocity." % body_name)
		pass # Position and velocity are as set in editor or by spawner

	# Initialize previous_position for Verlet integration
	if config_manager and config_manager.config and config_manager.config.integration_method == "verlet":
		var dt = get_physics_process_delta_time()
		if dt <= 0: # Fallback if called before first physics tick or dt is invalid
			var ticks_per_second = Engine.get_physics_ticks_per_second()
			if ticks_per_second > 0:
				dt = 1.0 / ticks_per_second
			else:
				dt = 1.0 / 60.0 # Absolute fallback if ticks_per_second is somehow not positive
			#print("[%s] Warning: physics_process_delta_time was <= 0 in calculate_initial_state. Using dt = %s" % [body_name, dt])
		previous_position = global_position - linear_velocity * dt
		#print("[%s] Initialized previous_position for Verlet: %s (global_pos: %s, lin_vel: %s, dt: %s)" % [body_name, previous_position, global_position, linear_velocity, dt])


func calculate_state_from_orbital_elements(central_mass_kg: float, a_au: float, e: float, i_deg: float, raan_deg: float, arg_p_deg: float, M_deg: float) -> Array:
	if central_mass_kg <= 0: 
		printerr("Central body mass must be positive for orbital calculations.")
		return [Vector2.ZERO, Vector2.ZERO] # Return zero state
	if a_au <= 0 and e < 1.0: # Parabolic/Hyperbolic might have a_au <= 0 conceptually, but we handle elliptical/circular here
		printerr("Semi-major axis must be positive for elliptical/circular orbits.")
		return [Vector2.ZERO, Vector2.ZERO]

	var mu = G * central_mass_kg # Standard gravitational parameter (m^3/s^2)
	var a_m = a_au * AU_TO_METERS # Semi-major axis in meters

	# Mean anomaly to radians
	var M_rad = deg_to_rad(M_deg)

	# Solve Kepler's equation for eccentric anomaly (E)
	var E_rad = solve_kepler_equation(M_rad, e)

	# True anomaly (nu)
	var nu_rad: float
	if e < 1.0 - 1e-9: # Elliptical
		# Using atan2 for quadrant correctness is important
		var cos_E = cos(E_rad)
		var sin_E = sin(E_rad)
		nu_rad = atan2(sqrt(1.0 - e*e) * sin_E, cos_E - e)
	elif e < 1.0 + 1e-9: # Near-parabolic, treat as parabolic for nu (M=0 for parabola, E=0)
		# This simplified case might not be robust for all near-parabolic.
		# For true parabolic, one would use different equations.
		# Assuming M_deg was for a bound orbit, if e is ~1, this is an edge case.
		# For simplicity, if e is very close to 1, we might approximate E ~ M for small M.
		# However, the Kepler solver should handle e close to 1 if M is reasonable.
		# If E_rad is valid, proceed.
		var cos_E = cos(E_rad)
		var sin_E = sin(E_rad)
		if abs(cos_E - e) < 1e-9: # Avoid division by zero if cos_E = e
			nu_rad = PI if sin_E < 0 else 0 # Or handle based on E_rad
		else:
			nu_rad = atan2(sqrt(abs(1.0 - e*e)) * sin_E, cos_E - e) # abs for 1-e*e if e slightly > 1
	else: # Hyperbolic (not fully supported by this Kepler solver for M)
		printerr("Hyperbolic orbits (e >= 1) require a different form of Kepler's equation or mean anomaly definition.")
		# For hyperbolic, E is hyperbolic eccentric anomaly H. M = e sinh(H) - H
		# This solver is for elliptical.
		return [Vector2.ZERO, Vector2.ZERO]


	# Distance from central body (r)
	var r_m = a_m * (1.0 - e * cos(E_rad))

	# Position in orbital plane (perifocal frame: x towards periapsis, y 90 deg in direction of motion)
	var x_orb_m = r_m * cos(nu_rad)
	var y_orb_m = r_m * sin(nu_rad)
	var pos_orb_m = Vector2(x_orb_m, y_orb_m)

	# Velocity in orbital plane
	var v_val_orb = sqrt(mu * (2.0/r_m - 1.0/a_m)) if a_m > 0 else sqrt(2.0 * mu / r_m) # Vis-viva or parabolic
	if r_m <= 0: v_val_orb = 0 # Avoid division by zero if r_m is somehow zero

	var vel_x_orb_m: float
	var vel_y_orb_m: float
	
	if abs(e - 1.0) < 1e-9 : # Parabolic case (simplified, assumes M=0, E=0, nu=0 at periapsis)
		# This part is tricky for general M with e~1.
		# If we are at periapsis (nu=0):
		# vel_x_orb_m = 0
		# vel_y_orb_m = sqrt(2*mu/r_m)
		# More general form for velocity components in perifocal frame:
		vel_x_orb_m = -sqrt(mu / (a_m * (1.0 - e*e))) * sin(nu_rad) if a_m * (1.0 - e*e) > 0 else 0
		vel_y_orb_m =  sqrt(mu / (a_m * (1.0 - e*e))) * (e + cos(nu_rad)) if a_m * (1.0 - e*e) > 0 else 0
		# This needs a_m * (1-e^2) to be non-zero (p, semi-latus rectum). For e=1, this is problematic.
		# Fallback for e=1 (parabolic) if needed, or ensure Kepler solver handles it.
		# For now, let's use the common formulation which is more robust for e < 1.
		# The term sqrt(mu * a_m) / r_m is also used.
		if r_m > 0:
			vel_x_orb_m = - (sqrt(mu * a_m) / r_m) * sin(E_rad) if e < 1.0 else -sqrt(mu/r_m) * sin(nu_rad) # Simplified for parabolic
			vel_y_orb_m =   (sqrt(mu * a_m) * sqrt(1.0 - e*e) / r_m) * cos(E_rad) if e < 1.0 else sqrt(mu/r_m) * (1.0 + cos(nu_rad)) # Simplified for parabolic
		else:
			vel_x_orb_m = 0
			vel_y_orb_m = 0

	else: # Elliptical (e < 1)
		# Standard formulas for velocity components in perifocal frame:
		# h = sqrt(mu * a_m * (1 - e*e)) ; specific angular momentum
		# vel_x_orb_m = (mu/h) * (-sin(nu_rad))
		# vel_y_orb_m = (mu/h) * (e + cos(nu_rad))
		# Or using E:
		if r_m > 0:
			vel_x_orb_m = - (a_m / r_m) * sqrt(mu / a_m) * sin(E_rad)
			vel_y_orb_m =   (a_m / r_m) * sqrt(mu / a_m) * sqrt(1.0 - e*e) * cos(E_rad)
		else: # r_m is zero, implies collision or invalid state
			vel_x_orb_m = 0
			vel_y_orb_m = 0
			
	var vel_orb_m = Vector2(vel_x_orb_m, vel_y_orb_m)

	# Convert angles to radians for rotation
	var i_rad = deg_to_rad(inclination_deg)
	var raan_rad = deg_to_rad(longitude_of_ascending_node_deg)
	var arg_p_rad = deg_to_rad(argument_of_periapsis_deg)

	# Rotation matrix components (from orbital to ecliptic/inertial frame)
	# PQR transformation vectors
	var Px = cos(arg_p_rad) * cos(raan_rad) - sin(arg_p_rad) * sin(raan_rad) * cos(i_rad)
	var Py = cos(arg_p_rad) * sin(raan_rad) + sin(arg_p_rad) * cos(raan_rad) * cos(i_rad)
	var Pz = sin(arg_p_rad) * sin(i_rad) # We are in 2D, so Pz component of position is 0

	var Qx = -sin(arg_p_rad) * cos(raan_rad) - cos(arg_p_rad) * sin(raan_rad) * cos(i_rad)
	var Qy = -sin(arg_p_rad) * sin(raan_rad) + cos(arg_p_rad) * cos(raan_rad) * cos(i_rad)
	var Qz = cos(arg_p_rad) * sin(i_rad) # We are in 2D, so Qz component of position is 0

	# For 2D simulation, we assume orbits are in the XY plane (i=0 or i=180 if retrograde)
	# If i_deg is non-zero, it implies a 3D orbit. For 2D, we effectively project.
	# A common simplification for 2D is to assume i=0, then raan and arg_p define orientation in the plane.
	# If i=0, then Px=cos(arg_p+raan), Py=sin(arg_p+raan), Qx=-sin(arg_p+raan), Qy=cos(arg_p+raan)
	# Let's use the angle of periapsis from the reference direction (e.g. x-axis)
	# This angle would be longitude_of_periapsis = raan + arg_p (if i=0)
	# Or simply use arg_p if raan is reference for the orbital plane itself.
	# For this 2D engine, let's assume inclination is handled by the 2D projection,
	# and (raan + arg_p) is the angle of periapsis from the global X-axis.
	# Or, more simply, that the orbital elements are already "flattened" for 2D.
	# The prompt implies J2000.0 elements, which are 3D.
	# For a 2D Godot view, we need to project. A common way is to view from "above" the ecliptic.
	# Position: x_ecl = x_orb * Px + y_orb * Qx, y_ecl = x_orb * Py + y_orb * Qy
	# Velocity: vx_ecl = vx_orb * Px + vy_orb * Qx, vy_ecl = vx_orb * Py + vy_orb * Qy

	# Simplified 2D rotation: assume inclination is about Z axis, then project to XY.
	# If we treat inclination as rotation around X-axis, then Y and Z are affected.
	# For a top-down 2D view (projection onto XY plane of J2000.0):
	# x_final = x_orb * (cos(arg_p_rad) * cos(raan_rad) - sin(arg_p_rad) * sin(raan_rad) * cos(i_rad)) + \
	#           y_orb * (-sin(arg_p_rad) * cos(raan_rad) - cos(arg_p_rad) * sin(raan_rad) * cos(i_rad))
	# y_final = x_orb * (cos(arg_p_rad) * sin(raan_rad) + sin(arg_p_rad) * cos(raan_rad) * cos(i_rad)) + \
	#           y_orb * (-sin(arg_p_rad) * sin(raan_rad) + cos(arg_p_rad) * cos(raan_rad) * cos(i_rad))
	# This is the standard transformation. Godot's Y is down.
	# We need to decide on coordinate system mapping. Assume J2000 X-Y is Godot X-Y for now.
	
	var pos_final_m = Vector2(
		pos_orb_m.x * Px + pos_orb_m.y * Qx,
		pos_orb_m.x * Py + pos_orb_m.y * Qy  # Godot Y is typically down, J2000 Y is typically up/sideways.
											# If J2000 is +Y up, then this might need negation or consistent frame.
											# For now, direct mapping.
	)
	
	var vel_final_m = Vector2(
		vel_orb_m.x * Px + vel_orb_m.y * Qx,
		vel_orb_m.x * Py + vel_orb_m.y * Qy
	)

	# If Godot's Y is down, and orbital math assumes Y is up (typical cartesian),
	# we might need to flip the Y component of the final vectors if the central body is at (0,0) in Godot.
	# However, since positions are relative to central_body.global_position, this should be fine.
	# The key is consistency. If sim_scale maps meters to pixels directly.

	return [pos_final_m, vel_final_m]


func solve_kepler_equation(M: float, e: float, tolerance: float = 1e-10) -> float:
	# Solves M = E - e * sin(E) for E, using Newton-Raphson method.
	# M and E should be in radians.
	var E: float
	if e < 0.8:
		E = M # Initial guess
	else:
		E = PI # Initial guess for high eccentricity

	var dE: float = 1.0 # Ensure loop runs at least once
	var max_iterations = config_manager.get_setting("simulation", "kepler_max_iterations", 100)
	var iter_count = 0
	
	while abs(dE) > tolerance and iter_count < max_iterations:
		# f(E) = E - e * sin(E) - M
		# f'(E) = 1 - e * cos(E)
		var fE = E - e * sin(E) - M
		var f_prime_E = 1.0 - e * cos(E)
		
		if abs(f_prime_E) < 1e-10: # Avoid division by zero if derivative is too small
			# This can happen near certain points, may need a different approach or indicate a problem
			printerr("Kepler solver: Derivative too small at E = %s, M = %s, e = %s" % [E, M, e])
			# Could try a small perturbation or a bisection step here if robust_solver needed
			break 
			
		dE = fE / f_prime_E
		E = E - dE
		iter_count += 1
	
	if iter_count >= max_iterations:
		printerr("Kepler solver reached max iterations (%s) for M=%s, e=%s. Result E=%s, error=%s" % [max_iterations, M, e, E, dE])

	return E

func find_central_body() -> CelestialBody:
	if central_body_name.is_empty():
		return null
	
	# Potential issue: get_tree().get_nodes_in_group() might not be ready if bodies are added dynamically
	# and this is called very early. Consider a manager or a slight delay if issues arise.
	# For _ready(), it should generally be fine if all bodies are part of the initial scene.
	var bodies = get_tree().get_nodes_in_group("celestial_bodies")
	for body_node in bodies:
		if body_node is CelestialBody and body_node.body_id == central_body_name:
			if body_node == self:
				printerr("CelestialBody '%s' cannot orbit itself." % body_name)
				return null
			return body_node
	
	printerr("Central body '%s' not found for '%s'." % [central_body_name, body_name])
	return null

func _integrate_forces(state: PhysicsDirectBodyState2D):
	# N-body gravitational interaction
	var total_force = Vector2.ZERO
	var bodies = get_tree().get_nodes_in_group("celestial_bodies")
	var sim_scale = config_manager.get_setting("simulation", "simulation_scale", 1.0) # pixels per meter
	var use_n_body = config_manager.get_setting("simulation", "use_n_body_gravity", true)
	var max_interaction_dist_meters = config_manager.config.n_body_interaction_max_distance_meters if config_manager and config_manager.config else 1.0e18 # Default large if no config

	if not use_n_body:
		# If n-body is off, forces are only applied if explicitly handled elsewhere (e.g. fixed orbits)
		# Or, if this body is only influenced by its primary central_body via Keplerian motion,
		# then _integrate_forces might not apply additional forces unless perturbations are modeled.
		# For now, if n-body is off, we assume Keplerian motion handles it and no extra forces here.
		# However, RigidBody2D still integrates velocity unless it's static or kinematic.
		# If we want pure Keplerian motion, this body should probably be KinematicBody2D
		# and have its position set directly in _physics_process.
		# Since it's RigidBody2D, it will respond to forces. If n-body is off,
		# it will just continue with its initial velocity unless other forces act on it.
		return

	for other_body_node in bodies:
		if other_body_node == self or not other_body_node is CelestialBody:
			continue

		var other_body: CelestialBody = other_body_node
		
		var direction_vector_pixels = other_body.global_position - global_position
		var distance_pixels = direction_vector_pixels.length()
		
		if distance_pixels == 0: # Avoid division by zero
			continue

		var distance_meters = distance_pixels / sim_scale

		if distance_meters > max_interaction_dist_meters:
			continue # Skip force calculation if bodies are too far apart

		if distance_meters < 1.0: # Avoid extreme forces at very close (sub-meter) distances
			distance_meters = 1.0
			
		# Newton's law of universal gravitation: F = G * (m1 * m2) / r^2
		var force_magnitude_newtons = (G * mass_kg * other_body.mass_kg) / (distance_meters * distance_meters)
		
		# Convert force from Newtons to Godot physics units (force = mass * acceleration)
		# Godot's apply_central_force expects force in "engine units".
		# If mass in RigidBody2D is 1 (default), then force is effectively acceleration.
		# Here, mass_kg is real mass. RigidBody2D.mass is its physics mass.
		# Let's assume RigidBody2D.mass is set to 1 for all celestial bodies for simplicity,
		# and we scale the force accordingly, or that force units are consistent.
		# If RigidBody2D.mass = 1, then Force_engine = Acceleration_physics_units
		# Acceleration_physics_units = Acceleration_m_s2 * sim_scale
		# Force_newtons / mass_kg = Acceleration_m_s2
		# So, Force_engine = (Force_newtons / mass_kg) * sim_scale
		var acceleration_m_s2 = force_magnitude_newtons / mass_kg
		var force_godot_units = direction_vector_pixels.normalized() * (acceleration_m_s2 * sim_scale)
		
		# This applies force scaled as if RigidBody2D.mass is 1.
		# If RigidBody2D.mass is actual mass_kg, then force_godot_units = direction_vector_pixels.normalized() * force_magnitude_newtons * (some_scaling_factor_if_needed)
		# For now, using the acceleration approach.
		total_force += force_godot_units

	var final_force = total_force
	var actual_acceleration = Vector2.ZERO

	if mass_kg > 1e-6: # Avoid division by zero for massless or near-massless bodies
		var calculated_acceleration = total_force / mass_kg
		# Assuming config_manager.config holds the GameConfiguration resource instance
		if calculated_acceleration.length() > config_manager.config.max_gravitational_acceleration:
			actual_acceleration = calculated_acceleration.normalized() * config_manager.config.max_gravitational_acceleration
			final_force = actual_acceleration * mass_kg
		else:
			actual_acceleration = calculated_acceleration
			# final_force remains total_force, which is consistent as it equals actual_acceleration * mass_kg
	else: # Should not happen for celestial bodies, but as a safeguard
		final_force = Vector2.ZERO # No force if no mass
		actual_acceleration = Vector2.ZERO # Ensure actual_acceleration is zeroed for consistency

	# Apply potentially limited gravitational force
	state.apply_central_force(final_force)

	# Store actual acceleration for Verlet integration (Step 10) or other uses
	previous_acceleration = actual_acceleration

func _physics_process(delta):
	if config_manager and config_manager.config and config_manager.config.integration_method == "verlet":
		# custom_integrator = true was set in _ready.
		# This means _integrate_forces(state) was called by the physics engine,
		# and it calculated total_force and updated self.previous_acceleration.
		# Godot's internal integrator did NOT update position/velocity.
		
		var current_acceleration = previous_acceleration # This is a_t from _integrate_forces

		var new_position = 2.0 * global_position - previous_position + current_acceleration * delta * delta
		
		if delta > 1e-9: # Avoid division by zero if delta is extremely small or zero
			# More standard velocity calculation for Verlet: v(t) = (x(t+dt) - x(t-dt)) / (2*dt)
			# However, the prompt suggested: linear_velocity = (new_position - global_position) / delta
			# which is v(t+dt) = (x(t+dt) - x(t)) / dt. This is also common.
			linear_velocity = (new_position - global_position) / delta
		# else: linear_velocity might become stale or could be set to zero if delta is problematic.

		previous_position = global_position # x(t) becomes x(t-dt) for the next step's perspective
		global_position = new_position      # Update current position to the new calculated position
		
		# Optional: Debug print for Verlet integration
		#print_debug("[%s] Verlet: prev_p=%s, cur_p=%s, new_p=%s, vel=%s, accel=%s, dt=%s" % [body_name, previous_position, global_position, new_position, linear_velocity, current_acceleration, delta])

	# If not "verlet", and custom_integrator is false (default), Godot's internal integrator
	# handles position/velocity updates based on forces applied in _integrate_forces.

	if config_manager.get_setting("performance", "enable_orbit_trails", true):
		update_orbit_trail()
	
	if config_manager.get_setting("simulation", "enable_gravity_field_interactions", true):
		check_gravity_field_interactions()

func update_orbit_trail():
	if not config_manager or not config_manager.config:
		push_warning("CelestialBody: ConfigManager not available for orbit trail update.")
		return

	var max_points = config_manager.config.max_orbit_points
	var trail_update_interval = config_manager.config.celestial_body_orbit_trail_update_interval_frames

	if trail_update_interval <= 0: # Avoid division by zero or excessive updates
		trail_update_interval = 1 # Sensible minimum

	if Engine.get_physics_frames() % trail_update_interval == 0:
		orbit_points.push_front(global_position) # Add current position to the front
		if orbit_points.size() > max_points:
			orbit_points.resize(max_points) # Keep trail length limited

		if orbit_trail:
			orbit_trail.clear_points()
			# Orbit trail points are in global coordinates, but Line2D works in local.
			# So, convert global points to local for the Line2D.
			var trail_points_local: Array[Vector2] = []
			for p_global in orbit_points:
				trail_points_local.append(orbit_trail.to_local(p_global))
			
			if trail_points_local.size() > 1:
				orbit_trail.points = PackedVector2Array(trail_points_local)


func check_gravity_field_interactions():
	if not gravity_field:
		return

	var overlapping_bodies = gravity_field.get_overlapping_bodies()
	for body_in_field in overlapping_bodies:
		if body_in_field is RigidBody2D and body_in_field.is_in_group("probes"):
			# var probe = body_in_field # Cast to Probe class if you have it
			# print("Probe '%s' entered gravity field of '%s'" % [probe.name, body_name])
			# Here you could apply SOI-specific logic, e.g., notify the probe,
			# change physics behavior, etc.
			# For now, just a placeholder print.
			if config_manager.get_setting("debug", "print_gravity_field_entries", false):
				print("Object '%s' (likely a Probe) entered gravity field of '%s'" % [body_in_field.name, body_name])
		# Can add checks for other types of bodies if needed

func find_primary_star() -> CelestialBody:
	# Helper to find the main star (assumed to have no central_body_name)
	var bodies = get_tree().get_nodes_in_group("celestial_bodies")
	for body_node in bodies:
		if body_node is CelestialBody:
			var cb = body_node as CelestialBody
			if cb.central_body_name.is_empty():
				return cb
	return null # Should not happen in a well-defined system

func _on_input_event(viewport: Node, event: InputEvent, shape_idx: int):
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.is_pressed():
		#print("Celestial Body clicked: %s" % body_name)
		body_clicked.emit(self)

# Placeholder for future use or if specific cleanup is needed
func _exit_tree():
	if is_instance_valid(ambient_audio_player):
		var audio_manager = get_node_or_null("/root/AudioManager")
		if audio_manager and audio_manager.has_method("stop_looping_sound"):
			audio_manager.stop_looping_sound(ambient_audio_player)
		ambient_audio_player = null # Clear reference
	pass
