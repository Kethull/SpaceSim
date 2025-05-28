# AudioManager.gd (AutoLoad)
extends Node

var audio_pools: Dictionary = {}
var active_audio_sources: Array[Node] = [] # Stores AudioStreamPlayer or AudioStreamPlayer2D

# Store volume settings as linear values (0.0 to 1.0) for logic and saving.
# These will be converted to dB when applied to players.
var _master_volume_linear: float = 1.0
var _sfx_volume_linear: float = 1.0
var _ambient_volume_linear: float = 0.7

const DEFAULT_MASTER_VOLUME_LINEAR = 1.0
const DEFAULT_SFX_VOLUME_LINEAR = 1.0
const DEFAULT_AMBIENT_VOLUME_LINEAR = 0.7

func _ready():
	create_audio_pools()
	load_audio_settings() # This will set the _linear vars and then update player volumes

func create_audio_pools():
	return
	# Sound configurations: file path, pool count, and audio bus name.
	# Ensure audio bus names ("Master", "SFX", "Ambient") exist in your Godot project's audio bus layout.
	# If buses are not set up, sounds will play on the "Master" bus by default.
	var sound_configs = {
		"thruster": {"file": "res://audio/thruster_loop.ogg", "count": 20, "bus": "SFX"},
		"mining_laser": {"file": "res://audio/mining_laser.ogg", "count": 10, "bus": "SFX"},
		"communication": {"file": "res://audio/communication_beep.ogg", "count": 5, "bus": "SFX"},
		"energy_critical": {"file": "res://audio/energy_warning.ogg", "count": 5, "bus": "SFX"},
		"discovery": {"file": "res://audio/discovery_chime.ogg", "count": 8, "bus": "SFX"},
		"replication": {"file": "res://audio/replication_success.ogg", "count": 3, "bus": "SFX"},
		"explosion": {"file": "res://audio/explosion.ogg", "count": 5, "bus": "SFX"},
		"ambient_space_music": {"file": "res://audio/ambient_space_loop.ogg", "count": 1, "bus": "Ambient"},
		# --- User: Add paths for these optional ambient sounds if you have them and uncomment ---
		# "earth_ambient": {"file": "res://audio/earth_ambient_loop.ogg", "count": 1, "bus": "Ambient"},
		# "gas_giant_ambient": {"file": "res://audio/gas_giant_ambient_loop.ogg", "count": 1, "bus": "Ambient"},
		# "ice_world_ambient": {"file": "res://audio/ice_world_ambient_loop.ogg", "count": 1, "bus": "Ambient"},
		# "volcanic_ambient": {"file": "res://audio/volcanic_ambient_loop.ogg", "count": 1, "bus": "Ambient"},
	}

	for sound_type in sound_configs:
		var config = sound_configs[sound_type]
		audio_pools[sound_type] = []

		if not FileAccess.file_exists(config.file):
			printerr("AudioManager: Audio file not found for '%s' at path: %s. Skipping pool creation." % [sound_type, config.file])
			continue

		var audio_stream = load(config.file)
		if not audio_stream:
			printerr("AudioManager: Failed to load audio stream for '%s' from path: %s." % [sound_type, config.file])
			continue

		for i in range(config.count):
			var audio_player_node: Node
			# Determine player type based on intended use (e.g., global music vs. positional SFX)
			# Ambient space music is explicitly non-positional. Other ambient sounds (like planet ambiances) might be positional.
			if sound_type == "ambient_space_music": # Global, non-positional
				audio_player_node = AudioStreamPlayer.new()
			else: # Default to positional (2D)
				audio_player_node = AudioStreamPlayer2D.new()
			
			audio_player_node.stream = audio_stream
			audio_player_node.autoplay = false
			if audio_player_node.has_method("set_bus"): # Godot 4
				audio_player_node.set_bus(config.bus)
			elif audio_player_node.has_setter("bus"): # Godot 3.x
				audio_player_node.bus = config.bus
			
			add_child(audio_player_node)
			audio_pools[sound_type].append(audio_player_node)
	print("AudioManager: Audio pools created.")

func get_available_audio_player(sound_type: String) -> Node:
	if not audio_pools.has(sound_type) or audio_pools[sound_type].is_empty():
		printerr("AudioManager: No pool or empty pool for sound_type '%s'." % sound_type)
		return null

	var pool = audio_pools[sound_type]
	for player_node in pool:
		if not player_node.playing:
			return player_node
	return pool[0] # All players busy, reuse the first one

func play_sound_at_position(sound_type: String, position: Vector2, volume_multiplier: float = 1.0, pitch: float = 1.0):
	var audio_player = get_available_audio_player(sound_type) as AudioStreamPlayer2D
	if not is_instance_valid(audio_player):
		printerr("AudioManager: Could not get AudioStreamPlayer2D for SFX sound_type '%s'." % sound_type)
		return

	audio_player.global_position = position
	var final_linear_volume = _master_volume_linear * _sfx_volume_linear * volume_multiplier
	audio_player.volume_db = linear_to_db(clamp(final_linear_volume, 0.0001, 1.0)) # Clamp to avoid -inf dB for 0
	audio_player.pitch_scale = pitch
	
	if audio_player.stream is AudioStreamOggVorbis or audio_player.stream is AudioStreamMP3:
		audio_player.stream.loop = false # Ensure one-shot sounds don't loop by mistake
		
	audio_player.play()

	if not active_audio_sources.has(audio_player):
		active_audio_sources.append(audio_player)

	if not audio_player.finished.is_connected(_on_audio_finished):
		audio_player.finished.connect(_on_audio_finished.bind(audio_player))

func play_looping_sound(sound_type: String, position: Vector2, volume_multiplier: float = 1.0, is_positional: bool = true) -> Node:
	var audio_player_node = get_available_audio_player(sound_type)
	if not is_instance_valid(audio_player_node):
		printerr("AudioManager: Could not get audio player for looping sound_type '%s'." % sound_type)
		return null

	var base_category_linear_volume = _sfx_volume_linear # Default to SFX
	var player_bus_name = "SFX" # Default
	if audio_player_node.has_method("get_bus"): player_bus_name = audio_player_node.get_bus()
	elif audio_player_node.has_property("bus"): player_bus_name = audio_player_node.bus

	if player_bus_name == "Ambient":
		base_category_linear_volume = _ambient_volume_linear
	
	var final_linear_volume = _master_volume_linear * base_category_linear_volume * volume_multiplier
	var final_volume_db = linear_to_db(clamp(final_linear_volume, 0.0001, 1.0))

	if is_positional:
		var audio_player_2d = audio_player_node as AudioStreamPlayer2D
		if not is_instance_valid(audio_player_2d):
			printerr("AudioManager: Expected AudioStreamPlayer2D for positional loop '%s', got %s." % [sound_type, typeof(audio_player_node)])
			return null
		audio_player_2d.global_position = position
		audio_player_2d.volume_db = final_volume_db
	else:
		var audio_player_1d = audio_player_node as AudioStreamPlayer
		if not is_instance_valid(audio_player_1d):
			printerr("AudioManager: Expected AudioStreamPlayer for non-positional loop '%s', got %s." % [sound_type, typeof(audio_player_node)])
			return null
		audio_player_1d.volume_db = final_volume_db
	
	if audio_player_node.stream is AudioStreamOggVorbis or audio_player_node.stream is AudioStreamMP3:
		audio_player_node.stream.loop = true
	
	audio_player_node.play()

	if not active_audio_sources.has(audio_player_node):
		active_audio_sources.append(audio_player_node)
	return audio_player_node

func stop_looping_sound(audio_player_node: Node):
	if is_instance_valid(audio_player_node) and audio_player_node.playing:
		audio_player_node.stop()
		if active_audio_sources.has(audio_player_node):
			active_audio_sources.erase(audio_player_node)

func _on_audio_finished(audio_player_node: Node):
	if active_audio_sources.has(audio_player_node):
		active_audio_sources.erase(audio_player_node)

func set_master_volume(volume_linear: float):
	_master_volume_linear = clamp(volume_linear, 0.0, 1.0)
	_update_all_player_volumes_based_on_linear()

func set_sfx_volume(volume_linear: float):
	_sfx_volume_linear = clamp(volume_linear, 0.0, 1.0)
	_update_all_player_volumes_based_on_linear()

func set_ambient_volume(volume_linear: float):
	_ambient_volume_linear = clamp(volume_linear, 0.0, 1.0)
	_update_all_player_volumes_based_on_linear()

func _update_all_player_volumes_based_on_linear():
	var players_to_remove = []
	for player_node in active_audio_sources:
		if not is_instance_valid(player_node) or not player_node.playing:
			if not is_instance_valid(player_node): players_to_remove.append(player_node)
			continue

		# This assumes player_node.get("volume_multiplier_original") was set if needed.
		# For now, assume original multiplier was 1.0 for simplicity of this global update.
		var original_volume_multiplier = 1.0 
		if player_node.has_meta("original_volume_multiplier"):
			original_volume_multiplier = player_node.get_meta("original_volume_multiplier")


		var category_linear_volume = _sfx_volume_linear
		var player_bus_name = "SFX"
		if player_node.has_method("get_bus"): player_bus_name = player_node.get_bus()
		elif player_node.has_property("bus"): player_bus_name = player_node.bus
			
		if player_bus_name == "Ambient":
			category_linear_volume = _ambient_volume_linear
		
		var new_effective_linear_volume = _master_volume_linear * category_linear_volume * original_volume_multiplier
		player_node.volume_db = linear_to_db(clamp(new_effective_linear_volume, 0.0001, 1.0))

	for p_rem in players_to_remove:
		active_audio_sources.erase(p_rem)

func load_audio_settings():
	var config_file = ConfigFile.new()
	var path = "user://audio_settings.cfg"
	if config_file.load(path) == OK:
		_master_volume_linear = config_file.get_value("audio", "master_volume_linear", DEFAULT_MASTER_VOLUME_LINEAR)
		_sfx_volume_linear = config_file.get_value("audio", "sfx_volume_linear", DEFAULT_SFX_VOLUME_LINEAR)
		_ambient_volume_linear = config_file.get_value("audio", "ambient_volume_linear", DEFAULT_AMBIENT_VOLUME_LINEAR)
		print("AudioManager: Loaded audio settings from %s" % path)
	else:
		_master_volume_linear = DEFAULT_MASTER_VOLUME_LINEAR
		_sfx_volume_linear = DEFAULT_SFX_VOLUME_LINEAR
		_ambient_volume_linear = DEFAULT_AMBIENT_VOLUME_LINEAR
		print("AudioManager: No audio settings file found at %s. Using defaults and creating one." % path)
		save_audio_settings() # Create a default file if none exists

	_update_all_player_volumes_based_on_linear()

func save_audio_settings():
	var config_file = ConfigFile.new()
	var path = "user://audio_settings.cfg"
	config_file.set_value("audio", "master_volume_linear", _master_volume_linear)
	config_file.set_value("audio", "sfx_volume_linear", _sfx_volume_linear)
	config_file.set_value("audio", "ambient_volume_linear", _ambient_volume_linear)
	
	var err = config_file.save(path)
	if err == OK:
		print("AudioManager: Saved audio settings to %s" % path)
	else:
		printerr("AudioManager: Error saving audio settings to %s. Error code: %s" % [path, err])

func get_expected_audio_files() -> Array[String]:
	var paths: Array[String] = []
	var sound_configs = { # Keep this consistent with create_audio_pools
		"thruster": {"file": "res://audio/thruster_loop.ogg"},
		"mining_laser": {"file": "res://audio/mining_laser.ogg"},
		"communication": {"file": "res://audio/communication_beep.ogg"},
		"energy_critical": {"file": "res://audio/energy_warning.ogg"},
		"discovery": {"file": "res://audio/discovery_chime.ogg"},
		"replication": {"file": "res://audio/replication_success.ogg"},
		"explosion": {"file": "res://audio/explosion.ogg"},
		"ambient_space_music": {"file": "res://audio/ambient_space_loop.ogg"},
		"earth_ambient": {"file": "res://audio/earth_ambient_loop.ogg"},
		"gas_giant_ambient": {"file": "res://audio/gas_giant_ambient_loop.ogg"},
		"ice_world_ambient": {"file": "res://audio/ice_world_ambient_loop.ogg"},
		"volcanic_ambient": {"file": "res://audio/volcanic_ambient_loop.ogg"},
	}
	for sound_type in sound_configs:
		paths.append(sound_configs[sound_type].file)
	return paths

# Getter methods for UI or other systems to query current volume levels (linear 0-1)
func get_master_volume_linear() -> float:
	return _master_volume_linear

func get_sfx_volume_linear() -> float:
	return _sfx_volume_linear

func get_ambient_volume_linear() -> float:
	return _ambient_volume_linear
