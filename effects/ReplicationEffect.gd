extends GPUParticles2D

# Called when the node enters the scene tree for the first time.
func _ready():
	emitting = false # Start without emitting, will be triggered by play_effect
	one_shot = true # Effect should play once
	
	var mat = ParticleProcessMaterial.new()
	
	# Emission
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 5.0
	
	# Direction & Spread
	mat.direction = Vector3(0, 0, 0) # Emit outwards from sphere center
	mat.spread = 180.0 # Full sphere
	
	# Velocity
	mat.initial_velocity_min = 50.0
	mat.initial_velocity_max = 150.0
	
	# Gravity
	mat.gravity = Vector3(0, 0, 0) # No gravity
	
	# Damping
	mat.damping_min = 20.0
	mat.damping_max = 40.0
	
	# Scale
	mat.scale_min = 0.5
	mat.scale_max = 1.5
	var scale_curve = Curve.new()
	scale_curve.add_point(Vector2(0, 0.2))
	scale_curve.add_point(Vector2(0.3, 1.0))
	scale_curve.add_point(Vector2(1.0, 0.0))
	mat.scale_curve = scale_curve
	
	# Color
	var color_ramp = Gradient.new()
	color_ramp.add_point(0.0, Color.CYAN.lightened(0.3))
	color_ramp.add_point(0.5, Color.LIGHT_BLUE)
	color_ramp.add_point(1.0, Color.TRANSPARENT) # Fade to transparent
	mat.color_ramp = color_ramp
	
	# Hue Variation
	mat.hue_variation_min = -0.1
	mat.hue_variation_max = 0.1
	
	process_material = mat
	
	amount = 60
	lifetime = 0.8
	speed_scale = 1.5
	explosiveness = 0.7
	randomness = 0.5
	
	finished.connect(_on_particles_finished)

func play_effect(pos: Vector2):
	global_position = pos
	emitting = true
	# print_debug("ReplicationEffect: Playing at %s" % str(pos))

func _on_particles_finished():
	# print_debug("ReplicationEffect: Finished, queueing free.")
	queue_free()