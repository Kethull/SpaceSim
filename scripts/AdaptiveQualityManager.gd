extends Node

enum Quality { LOW, MEDIUM, HIGH }

var current_quality_level: Quality = Quality.MEDIUM
var target_quality_level: Quality = Quality.MEDIUM

# Configurable thresholds (ideally from GameConfiguration)
var fps_threshold_low: float = 30.0 # Below this, try to go to Quality.LOW
var fps_threshold_medium_target: float = 45.0 # Aim for this when recovering from LOW
var fps_threshold_high: float = 55.0  # Above this, try to go to Quality.HIGH
var fps_threshold_medium_fallback: float = 50.0 # Fallback to medium if dropping from HIGH

var update_interval: float = 1.0 # How often to check FPS and adjust (in seconds)
var time_since_last_update: float = 0.0

var time_in_current_level: float = 0.0
var min_time_in_level: float = 5.0 # Minimum time to stay in a quality level to avoid rapid switching

@onready var config_manager = get_node_or_null("/root/ConfigManager")
@onready var advanced_particle_manager = get_node_or_null("/root/AdvancedParticleManager")
@onready var lod_manager = get_node_or_null("/root/LODManager")
# @onready var world_environment = get_node_or_null("/root/Main/WorldEnvironment") # If post-processing is managed here

func _ready():
	print("AdaptiveQualityManager Initialized.")
	if config_manager and config_manager.config:
		fps_threshold_low = config_manager.get_setting("general", "adaptive_quality_fps_low", 30.0)
		fps_threshold_medium_target = config_manager.get_setting("general", "adaptive_quality_fps_medium_target", 45.0)
		fps_threshold_high = config_manager.get_setting("general", "adaptive_quality_fps_high", 55.0)
		fps_threshold_medium_fallback = config_manager.get_setting("general", "adaptive_quality_fps_medium_fallback", 50.0)
		update_interval = config_manager.get_setting("general", "adaptive_quality_update_interval", 1.0)
		min_time_in_level = config_manager.get_setting("general", "adaptive_quality_min_time_in_level", 5.0)

		var initial_quality_str = config_manager.get_setting("general", "adaptive_quality_initial_level", "MEDIUM")
		match initial_quality_str.to_upper():
			"LOW":
				current_quality_level = Quality.LOW
				target_quality_level = Quality.LOW
			"HIGH":
				current_quality_level = Quality.HIGH
				target_quality_level = Quality.HIGH
			_: # Default to MEDIUM
				current_quality_level = Quality.MEDIUM
				target_quality_level = Quality.MEDIUM
		
	print("AdaptiveQualityManager: Initial quality level set to %s" % Quality.keys()[current_quality_level])
	apply_quality_settings(current_quality_level, true) # Apply initial settings forcefully

func _process(delta: float):
	time_since_last_update += delta
	time_in_current_level += delta

	if time_since_last_update >= update_interval:
		time_since_last_update = 0.0
		check_and_adjust_quality()

func check_and_adjust_quality():
	var current_fps = Performance.get_monitor(Performance.TIME_FPS)
	
	# Determine target quality based on FPS
	if current_quality_level == Quality.HIGH:
		if current_fps < fps_threshold_medium_fallback:
			target_quality_level = Quality.MEDIUM
	elif current_quality_level == Quality.MEDIUM:
		if current_fps < fps_threshold_low:
			target_quality_level = Quality.LOW
		elif current_fps > fps_threshold_high:
			target_quality_level = Quality.HIGH
	elif current_quality_level == Quality.LOW:
		if current_fps > fps_threshold_medium_target: # Try to recover to medium
			target_quality_level = Quality.MEDIUM
			
	if target_quality_level != current_quality_level:
		if time_in_current_level >= min_time_in_level:
			print("AdaptiveQualityManager: FPS is %s. Changing quality from %s to %s" % [current_fps, Quality.keys()[current_quality_level], Quality.keys()[target_quality_level]])
			current_quality_level = target_quality_level
			apply_quality_settings(current_quality_level)
			time_in_current_level = 0.0 # Reset timer for new level
		#else:
			#print_debug("AdaptiveQualityManager: FPS is %s. Target is %s, but min_time_in_level not met for %s." % [current_fps, Quality.keys()[target_quality_level], Quality.keys()[current_quality_level]])


func apply_quality_settings(level: Quality, force_apply: bool = false):
	if not force_apply and level == current_quality_level and time_in_current_level > 0: # Avoid re-applying if already set and not forced
		# This check might be redundant if apply_quality_settings is only called on change.
		# However, good for an initial call.
		pass

	print_rich("[color=cyan]AdaptiveQualityManager: Applying quality settings for level: %s[/color]" % Quality.keys()[level])

	# 1. Adjust Particle Quality
	if is_instance_valid(advanced_particle_manager) and advanced_particle_manager.has_method("set_quality_level"):
		advanced_particle_manager.set_quality_level(level)
	elif is_instance_valid(advanced_particle_manager):
		push_warning("AdaptiveQualityManager: AdvancedParticleManager found, but no set_quality_level method.")
	#else:
		#push_warning("AdaptiveQualityManager: AdvancedParticleManager not found.")


	# 2. Adjust LOD Bias/Settings
	if is_instance_valid(lod_manager) and lod_manager.has_method("set_quality_level"): # Assuming LODManager will have this
		lod_manager.set_quality_level(level)
	elif is_instance_valid(lod_manager):
		push_warning("AdaptiveQualityManager: LODManager found, but no set_quality_level method.")
	#else:
		#push_warning("AdaptiveQualityManager: LODManager not found.")

	# 3. Toggle Post-Processing Effects (Example)
	# if is_instance_valid(world_environment):
	# 	match level:
	# 		Quality.LOW:
	# 			if world_environment.environment: world_environment.environment.glow_enabled = false
	# 			# Disable other effects
	# 		Quality.MEDIUM:
	# 			if world_environment.environment: world_environment.environment.glow_enabled = true
	# 			# Moderate settings
	# 		Quality.HIGH:
	# 			if world_environment.environment: world_environment.environment.glow_enabled = true
	# 			# Full settings

	# 4. Modify Shader Parameters (More complex, placeholder)
	# This would require a system to iterate over relevant materials or use global shader parameters.
	# Example: RenderingServer.global_shader_parameter_set("global_detail_level", level)
	# Or, iterate through nodes in a group "quality_shaders" and call a method on them.
	
	# Notify other systems if needed
	# emit_signal("quality_level_changed", level) # If other systems need to react directly

# signal quality_level_changed(new_level: Quality)