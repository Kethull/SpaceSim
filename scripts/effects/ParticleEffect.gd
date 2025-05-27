extends Node2D
class_name ParticleEffect

# Base class for particle effects managed by AdvancedParticleManager.
# Individual effect scenes (e.g., ThrusterExhaustEffect.gd) should extend this.

var active: bool = false
var current_quality_level: AdaptiveQualityManager.Quality = AdaptiveQualityManager.Quality.MEDIUM # Default

func set_current_quality_level(new_level: AdaptiveQualityManager.Quality):
	current_quality_level = new_level
	# Specific effects can override this or use this value in their setup methods
	# to adjust particle parameters (amount, lifetime, speed, shaders etc.)
	# print_debug("%s quality level set to %s" % [self.name, AdaptiveQualityManager.Quality.keys()[new_level]])


# Called by AdvancedParticleManager when the effect is retrieved from thepool.
func activate_effect():
	visible = true
	active = true
	# Reset any state, start particles, timers, etc.
	# Example: if has_node("GPUParticles2D"): get_node("GPUParticles2D").emitting = true

# Called by AdvancedParticleManager to return the effect to the pool.
func deactivate_effect():
	visible = false
	active = false
	# Stop particles, reset state for reuse.
	# Example: if has_node("GPUParticles2D"): get_node("GPUParticles2D").emitting = false
	# Example: if has_node("Timer"): get_node("Timer").stop()

# Implement this in derived classes to indicate when the effect is finished.
# For example, after all particles have dissipated or a timer has run out.
func is_active() -> bool:
	# Default implementation: effect is active until explicitly deactivated.
	# Override this in specific effect scripts.
	# e.g., return get_node("GPUParticles2D").emitting or not get_node("Timer").is_stopped()
	return active

# Placeholder for LOD adjustment.
# Called by AdvancedParticleManager or the effect itself.
func set_lod_level(lod_level: int):
	# Adjust particle count, shader parameters, or disable sub-effects based on LOD.
	# Example:
	# var particles = get_node_or_null("GPUParticles2D")
	# if particles:
	#     match lod_level:
	#         0: # High detail
	#             particles.amount_ratio = 1.0
	#             # Enable complex shader features
	#         1: # Medium detail
	#             particles.amount_ratio = 0.5
	#             # Simplify shader
	#         2: # Low detail
	#             particles.amount_ratio = 0.2
	#             # Disable some sub-emitters or shader features
	#         _:
	#             particles.amount_ratio = 1.0
	pass

# --- Example setup methods for different effects ---
# These should be implemented in the specific effect scripts (e.g., ThrusterExhaustEffect.gd)

func setup_thruster_effect(_position: Vector2, _direction: Vector2, _intensity: float):
	# print_debug("Base ParticleEffect: setup_thruster_effect called. Implement in derived script.")
	activate_effect()
	pass

func setup_mining_effect(_start_pos: Vector2, _target_pos: Vector2, _intensity: float):
	# print_debug("Base ParticleEffect: setup_mining_effect called. Implement in derived script.")
	activate_effect()
	pass

func setup_communication_effect(_start_pos: Vector2, _end_pos: Vector2):
	# print_debug("Base ParticleEffect: setup_communication_effect called. Implement in derived script.")
	activate_effect()
	pass

func setup_energy_field_effect(_position: Vector2, _radius: float, _duration: float):
	# print_debug("Base ParticleEffect: setup_energy_field_effect called. Implement in derived script.")
	activate_effect()
	pass

func setup_explosion_effect(_position: Vector2, _scale: float):
	# print_debug("Base ParticleEffect: setup_explosion_effect called. Implement in derived script.")
	activate_effect()
	pass

func setup_replication_effect(_position: Vector2, _duration: float):
	# print_debug("Base ParticleEffect: setup_replication_effect called. Implement in derived script.")
	activate_effect()
	pass