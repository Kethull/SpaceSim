extends Node2D

# This script controls the harvest particle effect.

@onready var particles: GPUParticles2D = $GPUParticles2D

# Called when the node enters the scene tree for the first time.
func _ready():
	if not particles:
		printerr("HarvestEffect: GPUParticles2D node not found!")
		return
	# Ensure the effect plays once and then frees itself.
	particles.one_shot = true
	particles.emitting = false # Start non-emitting, will be triggered by setup_effect
	# Connect the finished signal to queue_free to clean up after playing.
	# Note: GPUParticles2D itself doesn't have a 'finished' signal for one_shot.
	# We'll rely on lifetime or a timer if precise cleanup is needed after particles die.
	# For now, we assume the effect is short-lived.
	# A common pattern is to use a Timer node to queue_free after the particle lifetime.
	var timer = Timer.new()
	add_child(timer)
	timer.wait_time = particles.lifetime + 0.5 # A bit longer than particle lifetime
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	timer.start()


# Configures and starts the harvest effect.
# resource_pos: Global position of the resource.
# probe_pos: Global position of the harvesting probe.
func setup_effect(resource_pos: Vector2, probe_pos: Vector2):
	if not particles:
		printerr("HarvestEffect.setup_effect: GPUParticles2D node not found!")
		return

	global_position = resource_pos # Position the effect at the resource

	# Configure particle emission towards the probe
	# This is a simplified approach. A more robust solution might involve
	# setting particle velocity or using a directional emission shape.
	var direction_to_probe = (probe_pos - resource_pos).normalized()
	
	# Assuming the particle process material is a ParticlesMaterial or ShaderMaterial
	# For GPUParticles2D, you typically set these properties in the editor.
	# Here, we'll assume the material is set up for basic emission and we
	# might adjust some parameters if possible via code, or rely on editor setup.
	# For instance, initial_velocity could be influenced by direction_to_probe.
	# However, directly setting particle direction per-particle often requires a custom shader
	# or specific material properties.
	# A simpler approach for a stream is to use a line emission shape or orient the emitter.
	
	# For now, we'll just ensure it emits. The visual representation of "towards probe"
	# would largely be configured in the GPUParticles2D node's ProcessMaterial in the editor.
	# For example, setting gravity to pull towards the probe, or initial velocity.
	
	# Example: if process material allows for it (e.g. ParticleProcessMaterial)
	if particles.process_material is ParticleProcessMaterial:
		# particles.process_material.direction = direction_to_probe # This is a 3D property
		# For 2D, you might set initial_velocity.
		# Let's assume the effect is designed to look like it's going towards a general direction
		# or the probe is close enough that a burst from resource is sufficient.
		# A common way is to set initial_velocity.min/max in the direction.
		var initial_velocity_magnitude = 100.0 # Example speed
		particles.process_material.initial_velocity_min = initial_velocity_magnitude * 0.8
		particles.process_material.initial_velocity_max = initial_velocity_magnitude * 1.2
		# The direction of velocity would be configured in the material's emission shape properties
		# or by rotating the GPUParticles2D node itself if its local X/Y axis is used for emission.
		
		# If the effect is a stream, we might rotate the emitter to point towards the probe
		look_at(probe_pos) # This rotates the Node2D, and thus the GPUParticles2D child

	particles.emitting = true
	print("HarvestEffect: Started at ", global_position, " aiming towards ", probe_pos)