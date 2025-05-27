extends Node

var config: Resource # Changed from GameConfiguration to Resource to avoid cyclic dependency if GameConfiguration.gd is not yet fully processed by Godot
var config_path: String = "user://game_config.tres"

func _ready():
	load_configuration()

func load_configuration():
	if ResourceLoader.exists(config_path):
		config = ResourceLoader.load(config_path)
		if not config is GameConfiguration: # Check if the loaded resource is of the correct type
			push_warning("Loaded configuration is not of type GameConfiguration. Creating a new one.")
			create_new_config()
	else:
		create_new_config()

	# Ensure config is always a GameConfiguration instance after loading or creating
	if not config is GameConfiguration:
		push_error("ConfigManager: config is not a GameConfiguration instance after load/create.")
		# Fallback to a new instance if something went wrong
		config = load("res://scripts/GameConfiguration.gd").new()


func create_new_config():
	config = load("res://scripts/GameConfiguration.gd").new() # Load the script and instantiate
	save_configuration()

func save_configuration():
	if config is GameConfiguration: # Ensure we are saving a valid GameConfiguration object
		var error = ResourceSaver.save(config, config_path)
		if error != OK:
			push_error("Error saving configuration: " + str(error))
	else:
		push_error("Attempted to save an invalid configuration object.")


func get_config() -> GameConfiguration:
	if config is GameConfiguration:
		return config as GameConfiguration
	push_warning("ConfigManager: get_config() called but config is not (yet) a GameConfiguration. Returning new instance.")
	# This might happen if accessed very early. Consider if a null return or a different handling is better.
	return load("res://scripts/GameConfiguration.gd").new()


func validate_configuration() -> bool:
	var current_config = get_config()
	if not current_config: # Should not happen with current get_config logic
		push_error("Validation failed: Configuration not loaded.")
		return false

	if current_config.world_size_au <= 0:
		push_error("World size must be positive")
		return false
	
	if current_config.asteroid_belt_inner_au >= current_config.asteroid_belt_outer_au:
		push_error("Asteroid belt inner radius must be less than outer radius")
		return false
	
	if current_config.max_probes <= 0 or current_config.initial_probes <= 0:
		push_error("Probe counts must be positive")
		return false
	
	if not (current_config.integration_method in ["euler", "verlet", "rk4"]):
		push_warning("Invalid integration_method: " + current_config.integration_method + ". Defaulting to 'verlet'.")
		current_config.integration_method = "verlet" # Correct to a valid default

	# Add more validation as needed
	# Example: Check if au_scale is positive
	if current_config.au_scale <= 0:
		push_error("AU scale must be positive.")
		return false

	# Example: Check array sizes if necessary (e.g., thrust_force_magnitudes)
	if current_config.thrust_force_magnitudes.is_empty():
		push_warning("thrust_force_magnitudes array is empty. This might cause issues.")
		# Depending on requirements, this could be an error or just a warning.

	print("Configuration validated successfully.")
	return true

# Call validate_configuration after loading/creating to ensure integrity
func _notification(what):
	if what == NOTIFICATION_POSTINITIALIZE: # Or a custom signal after _ready if needed
		if not Engine.is_editor_hint(): # Don't run validation in editor unless specifically intended
			if not validate_configuration():
				push_error("Initial configuration validation failed. Check settings.")
