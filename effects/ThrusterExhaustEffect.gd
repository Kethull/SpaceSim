extends ParticleEffect
class_name ThrusterExhaustEffect

# Assuming the ThrusterExhaust.tscn scene has a GPUParticles2D node named "Particles"
@onready var particles_node: GPUParticles2D = get_node_or_null("GPUParticles2D")

var base_amount: int = 16 # Default base amount for LOD 0

func _ready():
	if not particles_node:
		printerr("ThrusterExhaustEffect: GPUParticles2D node not found. Ensure it's named 'GPUParticles2D' in the scene.")
	else:
		# Store the initial amount configured in the editor for LOD 0 scaling
		base_amount = particles_node.amount
		particles_node.emitting = false # Start non-emitting

func activate_effect():
	super.activate_effect()
	if particles_node:
		particles_node.restart() # Restart to ensure fresh emission
		particles_node.emitting = true
	# print_debug("ThrusterExhaustEffect activated")

func deactivate_effect():
	super.deactivate_effect()
	if particles_node:
		particles_node.emitting = false
	# print_debug("ThrusterExhaustEffect deactivated")

func is_active() -> bool:
	if particles_node:
		return particles_node.emitting or particles_node.is_emitting() # Check both just in case
	return active # Fallback to base class 'active' if no particle node

func setup_thruster_effect(_position: Vector2, direction: Vector2, intensity: float):
	super.setup_thruster_effect(_position, direction, intensity)
	if not particles_node:
		return

	# Set position and rotation based on the parent probe/object
	# The AdvancedParticleManager already handles positioning the effect node itself.
	# Here, we adjust the emission direction of the particles if needed.
	# Assuming particles_node.process_material is a ParticleProcessMaterial or ShaderMaterial
	if particles_node.process_material is ParticleProcessMaterial:
		var mat: ParticleProcessMaterial = particles_node.process_material
		
		# Direction is local to the GPUParticles2D node.
		# If the GPUParticles2D node itself is rotated with the thruster,
		# then initial_direction might just be (0, 1) or (0, -1) depending on its local orientation.
		# For simplicity, let's assume the GPUParticles2D node is oriented such that positive Y is outward.
		# The 'direction' parameter passed is in global space. We need to transform it to local if particle node isn't aligned.
		# However, AdvancedParticleManager parents the effect to the thruster node, so local direction might be simpler.
		# Let's assume the effect node itself will be rotated by its parent.
		# So, the particle emission direction within the effect node can be fixed (e.g., along its local Y axis).
		mat.initial_velocity_min = 20.0 * intensity
		mat.initial_velocity_max = 50.0 * intensity
		mat.gravity = Vector3(direction.x, direction.y, 0) * 0.0 # No gravity, but use direction for initial spread if desired
		# mat.direction = Vector3(0, 1, 0) # Example: Emit along local Y+
		# This needs to align with how ThrusterExhaust.tscn is built.
		# For now, let's assume the GPUParticles2D node itself is rotated by its parent (the effect node).

	elif particles_node.process_material is ShaderMaterial:
		# Handle shader material parameters if used for direction/intensity
		var shader_mat: ShaderMaterial = particles_node.process_material
		if shader_mat.has_shader_parameter("intensity_multiplier"):
			shader_mat.set_shader_parameter("intensity_multiplier", intensity)
		# Direction might be handled by rotating the Node2D itself.

	# Adjust amount based on intensity, respecting LOD level later
	particles_node.amount = int(base_amount * clampf(intensity, 0.5, 2.0))

	activate_effect() # Ensure it's emitting

func set_lod_level(lod_level: int):
	super.set_lod_level(lod_level)
	if not particles_node:
		return

	match lod_level:
		0: # High detail
			particles_node.amount_ratio = 1.0
			particles_node.draw_order = GPUParticles2D.DRAW_ORDER_LIFETIME # Example
			# particles_node.visibility_aabb = AABB(Vector3(-100,-100,-100), Vector3(200,200,200)) # Ensure visible
		1: # Medium detail
			particles_node.amount_ratio = 0.5
			# particles_node.visibility_aabb = AABB(Vector3(-50,-50,-50), Vector3(100,100,100))
		2: # Low detail
			particles_node.amount_ratio = 0.2
			# particles_node.visibility_aabb = AABB(Vector3(-20,-20,-20), Vector3(40,40,40))
		_: # Default to high if unknown LOD
			particles_node.amount_ratio = 1.0
	
	# If amount is directly controlled (not ratio), adjust base_amount scaling:
	# var scale_factor = 1.0
	# match lod_level:
	# 	0: scale_factor = 1.0
	# 	1: scale_factor = 0.5
	# 	2: scale_factor = 0.2
	# particles_node.amount = int(base_amount * scale_factor * clampf(current_intensity_cache, 0.5, 2.0))
	# (Requires caching intensity if setup_thruster_effect isn't called on LOD change)

	# print_debug("ThrusterExhaustEffect LOD set to %s, amount_ratio: %s" % [lod_level, particles_node.amount_ratio])

# Note: The user needs to create 'effects/ThrusterExhaust.tscn'.
# The root node of this scene should have this script 'ThrusterExhaustEffect.gd' attached.
# It should also contain a child node named "GPUParticles2D" of type GPUParticles2D.
# Configure the GPUParticles2D node in the editor for desired appearance (texture, colors, lifetime, etc.).
# The 'process_material' of the GPUParticles2D should be a ParticleProcessMaterial.