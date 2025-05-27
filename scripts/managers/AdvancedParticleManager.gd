extends Node
class_name AdvancedParticleManager

# Manages pooling and activation of various particle effects.
# Should be set up as an AutoLoad singleton named "AdvancedParticleManager".

const ParticleEffect = preload("res://scripts/effects/ParticleEffect.gd")

var particle_pools: Dictionary = {}
var active_effects: Array[ParticleEffect] = [] # Array of active ParticleEffect instances

@onready var lod_manager = get_node_or_null("/root/LODManager") # Assuming LODManager is an AutoLoad
@onready var config_manager = get_node_or_null("/root/ConfigManager")

var current_particle_quality_level: AdaptiveQualityManager.Quality = AdaptiveQualityManager.Quality.MEDIUM


# Pre-defined configurations for particle effect pools.
# User needs to create the corresponding .tscn files in res://effects/
const POOL_CONFIGS = {
	"thruster_exhaust": {"count": 50, "scene_path": "res://effects/ThrusterExhaust.tscn"},
	"mining_sparks": {"count": 20, "scene_path": "res://effects/MiningSparks.tscn"},
	"communication_pulse": {"count": 10, "scene_path": "res://effects/CommunicationPulse.tscn"},
	"energy_field": {"count": 15, "scene_path": "res://effects/EnergyField.tscn"},
	"explosion": {"count": 5, "scene_path": "res://effects/Explosion.tscn"},
	"replication_effect": {"count": 10, "scene_path": "res://effects/ReplicationEffect.tscn"}
}

func _ready():
	if not lod_manager:
		push_warning("AdvancedParticleManager: LODManager not found. LOD features for particles will be disabled.")
	create_particle_pools()
	
	# Set initial quality based on config if available
	if config_manager and config_manager.config:
		var initial_quality_str = config_manager.config.get("adaptive_quality_initial_level", "MEDIUM")
		match initial_quality_str.to_upper():
			"LOW": current_particle_quality_level = AdaptiveQualityManager.Quality.LOW
			"HIGH": current_particle_quality_level = AdaptiveQualityManager.Quality.HIGH
			_: current_particle_quality_level = AdaptiveQualityManager.Quality.MEDIUM
	print("AdvancedParticleManager: Initial particle quality level: %s" % AdaptiveQualityManager.Quality.keys()[current_particle_quality_level])


func set_quality_level(new_level: AdaptiveQualityManager.Quality):
	if new_level == current_particle_quality_level:
		return
	current_particle_quality_level = new_level
	print_rich("[color=lightblue]AdvancedParticleManager: Particle quality level set to %s[/color]" % AdaptiveQualityManager.Quality.keys()[current_particle_quality_level])
	# Future: Could iterate active_effects and call set_current_quality_level if effects should change mid-flight.
	# For now, new effects will use the new quality level.

func create_particle_pools():
	for effect_type in POOL_CONFIGS:
		var config = POOL_CONFIGS[effect_type]
		particle_pools[effect_type] = []
		
		var scene_res = load(config.scene_path)
		if not scene_res:
			push_error("AdvancedParticleManager: Failed to load scene for '%s' at path: %s. User needs to create this scene." % [effect_type, config.scene_path])
			continue # Skip this pool if scene doesn't exist

		for i in range(config.count):
			var effect_instance = scene_res.instantiate()
			if not effect_instance is ParticleEffect:
				push_error("AdvancedParticleManager: Instantiated effect '%s' does not extend ParticleEffect. Please ensure the root node of '%s' has a script that extends ParticleEffect." % [effect_type, config.scene_path])
				effect_instance.queue_free() # Clean up invalid instance
				continue # Skip this instance
			
			effect_instance.name = "%s_%s" % [effect_type, i] # Unique name for debugging
			add_child(effect_instance) # Manager owns the effect nodes
			effect_instance.deactivate_effect() # Start inactive and hidden
			particle_pools[effect_type].append(effect_instance)
		print_debug("AdvancedParticleManager: Created pool for '%s' with %s instances." % [effect_type, particle_pools[effect_type].size()])

func get_effect(effect_type: String) -> ParticleEffect:
	if not particle_pools.has(effect_type):
		push_error("AdvancedParticleManager: Unknown particle effect type requested: '%s'" % effect_type)
		return null
	
	var pool = particle_pools[effect_type]
	for effect_instance in pool:
		if not effect_instance.is_active():
			effect_instance.activate_effect() # Activate it before returning
			if effect_instance.has_method("set_current_quality_level"):
				effect_instance.set_current_quality_level(current_particle_quality_level)
			return effect_instance
	
	# Pool exhausted, try to create a new one if allowed, or warn.
	# For now, we just warn. Could implement dynamic pool growth.
	push_warning("AdvancedParticleManager: Particle pool exhausted for type: '%s'. Consider increasing pool size." % effect_type)
	# Optionally, instantiate a new one on-the-fly if critical:
	# var config = POOL_CONFIGS[effect_type]
	# var scene_res = load(config.scene_path)
	# if scene_res:
	#     var new_effect = scene_res.instantiate()
	#     if new_effect is ParticleEffect:
	#         add_child(new_effect)
	#         new_effect.activate_effect()
	#         particle_pools[effect_type].append(new_effect) # Add to pool for future reuse
	#         active_effects.append(new_effect) # Add to active list
	#         return new_effect
	return null

func _process(delta):
	# Clean up finished effects and apply LOD
	for i in range(active_effects.size() - 1, -1, -1):
		var effect = active_effects[i]
		if not effect.is_active():
			effect.deactivate_effect() # Ensure it's fully reset
			active_effects.remove_at(i)
		else:
			# Apply LOD if LODManager is available and effect is visible
			if lod_manager and effect.is_inside_tree() and effect.is_visible_in_tree():
				var camera = get_viewport().get_camera_2d()
				if camera:
					var distance_to_camera = effect.global_position.distance_to(camera.global_position)
					var lod_level = lod_manager.get_lod_level_for_distance(distance_to_camera) # Assumes LODManager has this method
					effect.set_lod_level(lod_level)


# --- Public methods to create specific effects ---

func create_thruster_effect(position: Vector2, direction: Vector2, intensity: float, parent_node: Node2D = null):
	var effect = get_effect("thruster_exhaust")
	if effect:
		if parent_node:
			# Reparent to keep effect with moving object, but manage lifetime here
			var old_parent = effect.get_parent()
			if old_parent != parent_node:
				if old_parent: old_parent.remove_child(effect)
				parent_node.add_child(effect)
		effect.global_position = position # Set global position after reparenting
		effect.setup_thruster_effect(effect.global_position, direction, intensity) # Modified to take direction and intensity
		if not active_effects.has(effect): active_effects.append(effect)

func create_mining_effect(start_pos: Vector2, target_pos: Vector2, intensity: float):
	var effect = get_effect("mining_sparks")
	if effect:
		effect.global_position = start_pos # Or an appropriate position
		effect.setup_mining_effect(start_pos, target_pos, intensity)
		if not active_effects.has(effect): active_effects.append(effect)

func create_communication_effect(start_pos: Vector2, end_pos: Vector2):
	var effect = get_effect("communication_pulse")
	if effect:
		effect.global_position = start_pos # Or an appropriate position
		effect.setup_communication_effect(start_pos, end_pos)
		if not active_effects.has(effect): active_effects.append(effect)

func create_energy_field_effect(position: Vector2, radius: float, duration: float, parent_node: Node2D = null):
	var effect = get_effect("energy_field")
	if effect:
		if parent_node:
			var old_parent = effect.get_parent()
			if old_parent != parent_node:
				if old_parent: old_parent.remove_child(effect)
				parent_node.add_child(effect)
		effect.global_position = position
		effect.setup_energy_field_effect(effect.global_position, radius, duration) # Assuming ParticleEffect has this
		if not active_effects.has(effect): active_effects.append(effect)

func create_explosion_effect(position: Vector2, scale: float):
	var effect = get_effect("explosion")
	if effect:
		# Explosions usually aren't parented as the parent might be destroyed
		var current_parent = effect.get_parent()
		if current_parent != self: # Ensure it's a child of the manager
			if current_parent: current_parent.remove_child(effect)
			add_child(effect)
		effect.global_position = position
		effect.setup_explosion_effect(effect.global_position, scale) # Assuming ParticleEffect has this
		if not active_effects.has(effect): active_effects.append(effect)

func create_replication_effect(position: Vector2, duration: float):
	var effect = get_effect("replication_effect")
	if effect:
		effect.global_position = position
		effect.setup_replication_effect(effect.global_position, duration) # Assuming ParticleEffect has this
		if not active_effects.has(effect): active_effects.append(effect)