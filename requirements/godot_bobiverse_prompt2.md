func create_audio_pools():
    var sound_configs = {
        "thruster": {"file": "res://audio/thruster_loop.ogg", "count": 20},
        "mining_laser": {"file": "res://audio/mining_laser.ogg", "count": 10},
        "communication": {"file": "res://audio/communication_beep.ogg", "count": 5},
        "energy_critical": {"file": "res://audio/energy_warning.ogg", "count": 5},
        "discovery": {"file": "res://audio/discovery_chime.ogg", "count": 8},
        "replication": {"file": "res://audio/replication_success.ogg", "count": 3},
        "explosion": {"file": "res://audio/explosion.ogg", "count": 5}
    }
    
    for sound_type in sound_configs:
        var config = sound_configs[sound_type]
        audio_pools[sound_type] = []
        
        var audio_stream = load(config.file)
        
        for i in range(config.count):
            var audio_player = AudioStreamPlayer2D.new()
            audio_player.stream = audio_stream
            audio_player.autoplay = false
            add_child(audio_player)
            audio_pools[sound_type].append(audio_player)

func play_sound_at_position(sound_type: String, position: Vector2, volume: float = 1.0, pitch: float = 1.0):
    var audio_player = get_available_audio_player(sound_type)
    if not audio_player:
        return
    
    audio_player.global_position = position
    audio_player.volume_db = linear_to_db(volume * sfx_volume * master_volume)
    audio_player.pitch_scale = pitch
    audio_player.play()
    
    if audio_player not in active_audio_sources:
        active_audio_sources.append(audio_player)
    
    # Auto-cleanup when finished
    if not audio_player.finished.is_connected(_on_audio_finished):
        audio_player.finished.connect(_on_audio_finished.bind(audio_player))

func get_available_audio_player(sound_type: String) -> AudioStreamPlayer2D:
    if not audio_pools.has(sound_type):
        return null
    
    var pool = audio_pools[sound_type]
    for player in pool:
        if not player.playing:
            return player
    
    # All players busy, return first one (will interrupt)
    return pool[0]

func play_looping_sound(sound_type: String, position: Vector2, volume: float = 1.0) -> AudioStreamPlayer2D:
    var audio_player = get_available_audio_player(sound_type)
    if not audio_player:
        return null
    
    audio_player.global_position = position
    audio_player.volume_db = linear_to_db(volume * sfx_volume * master_volume)
    
    # Enable looping if the stream supports it
    if audio_player.stream is AudioStreamOggVorbis:
        audio_player.stream.loop = true
    
    audio_player.play()
    
    if audio_player not in active_audio_sources:
        active_audio_sources.append(audio_player)
    
    return audio_player

func stop_looping_sound(audio_player: AudioStreamPlayer2D):
    if audio_player and audio_player.playing:
        audio_player.stop()
        active_audio_sources.erase(audio_player)

func _on_audio_finished(audio_player: AudioStreamPlayer2D):
    active_audio_sources.erase(audio_player)

func set_master_volume(volume: float):
    master_volume = clamp(volume, 0.0, 1.0)
    update_all_volumes()

func set_sfx_volume(volume: float):
    sfx_volume = clamp(volume, 0.0, 1.0)
    update_all_volumes()

func set_ambient_volume(volume: float):
    ambient_volume = clamp(volume, 0.0, 1.0)
    update_all_volumes()

func update_all_volumes():
    for player in active_audio_sources:
        if player and player.playing:
            player.volume_db = linear_to_db(sfx_volume * master_volume)

func load_audio_settings():
    var config_file = ConfigFile.new()
    if config_file.load("user://audio_settings.cfg") == OK:
        master_volume = config_file.get_value("audio", "master_volume", 1.0)
        sfx_volume = config_file.get_value("audio", "sfx_volume", 1.0)
        ambient_volume = config_file.get_value("audio", "ambient_volume", 0.7)

func save_audio_settings():
    var config_file = ConfigFile.new()
    config_file.set_value("audio", "master_volume", master_volume)
    config_file.set_value("audio", "sfx_volume", sfx_volume)
    config_file.set_value("audio", "ambient_volume", ambient_volume)
    config_file.save("user://audio_settings.cfg")
```

## 9. Save/Load System with Resources

### Comprehensive Save Data Structure
```gdscript
# SimulationSaveData.gd
extends Resource
class_name SimulationSaveData

@export var save_version: String = "1.0"
@export var save_timestamp: String = ""
@export var episode_count: int = 0
@export var current_step: int = 0
@export var total_resources_mined: float = 0.0
@export var simulation_running: bool = false

@export var probes: Array[ProbeData] = []
@export var resources: Array[ResourceData] = []
@export var celestial_bodies: Array[CelestialBodyData] = []
@export var messages: Array[MessageData] = []

@export var camera_position: Vector2 = Vector2.ZERO
@export var camera_zoom: float = 1.0
@export var selected_probe_id: int = -1

@export var performance_stats: Dictionary = {}

# ProbeData.gd
extends Resource
class_name ProbeData

@export var id: int = 0
@export var generation: int = 0
@export var position: Vector2 = Vector2.ZERO
@export var velocity: Vector2 = Vector2.ZERO
@export var rotation: float = 0.0
@export var angular_velocity: float = 0.0
@export var energy: float = 0.0
@export var max_energy: float = 100000.0
@export var is_alive: bool = true
@export var current_task: String = "idle"
@export var current_target_id: int = -1
@export var trail_points: Array[Vector2] = []

# AI state
@export var ai_enabled: bool = true
@export var last_action: Array[int] = [0, 0, 0, 0, 0]
@export var action_history: Array[Array] = []

# ResourceData.gd
extends Resource
class_name ResourceData

@export var position: Vector2 = Vector2.ZERO
@export var current_amount: float = 0.0
@export var max_amount: float = 20000.0
@export var resource_type: String = "mineral"
@export var regeneration_rate: float = 0.0
@export var discovered_by: Array[int] = []
@export var harvest_difficulty: float = 1.0

# CelestialBodyData.gd
extends Resource
class_name CelestialBodyData

@export var name: String = ""
@export var position: Vector2 = Vector2.ZERO
@export var velocity: Vector2 = Vector2.ZERO
@export var mass_kg: float = 0.0
@export var radius_km: float = 0.0
@export var orbit_points: Array[Vector2] = []

# MessageData.gd
extends Resource
class_name MessageData

@export var sender_id: int = 0
@export var message_type: String = ""
@export var position: Vector2 = Vector2.ZERO
@export var timestamp: int = 0
@export var data: Dictionary = {}
```

### Save/Load Manager
```gdscript
# SaveLoadManager.gd (AutoLoad)
extends Node

var current_save_data: SimulationSaveData
var autosave_enabled: bool = true
var autosave_interval: float = 300.0  # 5 minutes
var max_autosaves: int = 5
var last_autosave_time: float = 0.0

signal save_completed(save_path: String)
signal load_completed(save_data: SimulationSaveData)
signal save_failed(error_message: String)
signal load_failed(error_message: String)

func _ready():
    # Create save directory if it doesn't exist
    DirAccess.make_dir_absolute("user://saves/")

func _process(delta):
    if autosave_enabled:
        last_autosave_time += delta
        if last_autosave_time >= autosave_interval:
            last_autosave_time = 0.0
            autosave()

func save_simulation(file_name: String = "") -> bool:
    var save_data = create_save_data()
    
    if file_name.is_empty():
        var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
        file_name = "simulation_" + timestamp + ".tres"
    
    var save_path = "user://saves/" + file_name
    
    var error = ResourceSaver.save(save_data, save_path)
    if error == OK:
        print("Simulation saved to: ", save_path)
        save_completed.emit(save_path)
        return true
    else:
        var error_msg = "Failed to save simulation: " + str(error)
        print(error_msg)
        save_failed.emit(error_msg)
        return false

func load_simulation(file_path: String) -> bool:
    if not ResourceLoader.exists(file_path):
        var error_msg = "Save file does not exist: " + file_path
        print(error_msg)
        load_failed.emit(error_msg)
        return false
    
    var save_data = ResourceLoader.load(file_path)
    if not save_data is SimulationSaveData:
        var error_msg = "Invalid save file format: " + file_path
        print(error_msg)
        load_failed.emit(error_msg)
        return false
    
    current_save_data = save_data
    apply_save_data(save_data)
    
    print("Simulation loaded from: ", file_path)
    load_completed.emit(save_data)
    return true

func create_save_data() -> SimulationSaveData:
    var save_data = SimulationSaveData.new()
    
    # Basic simulation state
    save_data.save_timestamp = Time.get_datetime_string_from_system()
    save_data.episode_count = get_simulation_manager().episode_count
    save_data.current_step = get_simulation_manager().current_step
    save_data.total_resources_mined = get_simulation_manager().total_resources_mined
    save_data.simulation_running = get_simulation_manager().simulation_running
    
    # Camera state
    var camera = get_tree().get_first_node_in_group("camera")
    if camera:
        save_data.camera_position = camera.global_position
        save_data.camera_zoom = camera.zoom.x
    
    # UI state
    var ui = get_tree().get_first_node_in_group("ui")
    if ui and ui.has_method("get_selected_probe_id"):
        save_data.selected_probe_id = ui.get_selected_probe_id()
    
    # Probe data
    for probe in get_tree().get_nodes_in_group("probes"):
        var probe_data = ProbeData.new()
        probe_data.id = probe.probe_id
        probe_data.generation = probe.generation
        probe_data.position = probe.global_position
        probe_data.velocity = probe.linear_velocity
        probe_data.rotation = probe.rotation
        probe_data.angular_velocity = probe.angular_velocity
        probe_data.energy = probe.current_energy
        probe_data.max_energy = probe.max_energy
        probe_data.is_alive = probe.is_alive
        probe_data.current_task = probe.current_task
        probe_data.current_target_id = probe.current_target_id
        probe_data.trail_points = probe.trail_points.duplicate()
        
        # AI state
        if probe.ai_agent:
            probe_data.ai_enabled = probe.ai_agent.use_external_ai
            probe_data.last_action = probe.ai_agent.current_action.duplicate()
        
        save_data.probes.append(probe_data)
    
    # Resource data
    for resource in get_tree().get_nodes_in_group("resources"):
        var resource_data = ResourceData.new()
        resource_data.position = resource.global_position
        resource_data.current_amount = resource.current_amount
        resource_data.max_amount = resource.max_amount
        resource_data.resource_type = resource.resource_type
        resource_data.regeneration_rate = resource.regeneration_rate
        resource_data.discovered_by = resource.discovered_by.duplicate()
        resource_data.harvest_difficulty = resource.harvest_difficulty
        
        save_data.resources.append(resource_data)
    
    # Celestial body data
    for body in get_tree().get_nodes_in_group("celestial_bodies"):
        var body_data = CelestialBodyData.new()
        body_data.name = body.body_name
        body_data.position = body.global_position
        body_data.velocity = body.linear_velocity
        body_data.mass_kg = body.mass_kg
        body_data.radius_km = body.radius_km
        body_data.orbit_points = body.orbit_points.duplicate()
        
        save_data.celestial_bodies.append(body_data)
    
    return save_data

func apply_save_data(save_data: SimulationSaveData):
    var sim_manager = get_simulation_manager()
    if not sim_manager:
        push_error("SimulationManager not found")
        return
    
    # Stop current simulation
    sim_manager.simulation_running = false
    
    # Clear existing entities
    clear_simulation_entities()
    
    # Restore simulation state
    sim_manager.episode_count = save_data.episode_count
    sim_manager.current_step = save_data.current_step
    sim_manager.total_resources_mined = save_data.total_resources_mined
    
    # Restore camera state
    var camera = get_tree().get_first_node_in_group("camera")
    if camera:
        camera.global_position = save_data.camera_position
        camera.zoom = Vector2.ONE * save_data.camera_zoom
    
    # Restore probes
    restore_probes(save_data.probes)
    
    # Restore resources
    restore_resources(save_data.resources)
    
    # Restore celestial bodies (positions and velocities)
    restore_celestial_bodies(save_data.celestial_bodies)
    
    # Resume simulation
    sim_manager.simulation_running = save_data.simulation_running
    
    print("Save data applied successfully")

func clear_simulation_entities():
    # Clear probes
    for probe in get_tree().get_nodes_in_group("probes"):
        probe.queue_free()
    
    # Clear messages
    for message in get_tree().get_nodes_in_group("messages"):
        message.queue_free()
    
    # Resources will be updated in place

func restore_probes(probe_data_array: Array[ProbeData]):
    var probe_scene = preload("res://probes/Probe.tscn")
    var probe_manager = get_tree().get_first_node_in_group("probe_manager")
    
    for probe_data in probe_data_array:
        var probe = probe_scene.instantiate()
        
        # Restore basic properties
        probe.probe_id = probe_data.id
        probe.generation = probe_data.generation
        probe.global_position = probe_data.position
        probe.linear_velocity = probe_data.velocity
        probe.rotation = probe_data.rotation
        probe.angular_velocity = probe_data.angular_velocity
        probe.current_energy = probe_data.energy
        probe.max_energy = probe_data.max_energy
        probe.is_alive = probe_data.is_alive
        probe.current_task = probe_data.current_task
        probe.current_target_id = probe_data.current_target_id
        probe.trail_points = probe_data.trail_points.duplicate()
        
        probe_manager.add_child(probe)
        probe.add_to_group("probes")
        
        # Restore AI state
        if probe.ai_agent and probe_data.ai_enabled:
            probe.ai_agent.current_action = probe_data.last_action.duplicate()
        
        # Connect signals
        get_simulation_manager().connect_probe_signals(probe)

func restore_resources(resource_data_array: Array[ResourceData]):
    var existing_resources = get_tree().get_nodes_in_group("resources")
    
    # Update existing resources or create new ones
    for i in range(resource_data_array.size()):
        var resource_data = resource_data_array[i]
        var resource = null
        
        if i < existing_resources.size():
            resource = existing_resources[i]
        else:
            # Create new resource if needed
            var resource_scene = preload("res://resources/Resource.tscn")
            resource = resource_scene.instantiate()
            get_tree().get_first_node_in_group("resource_manager").add_child(resource)
            resource.add_to_group("resources")
        
        # Restore resource properties
        resource.global_position = resource_data.position
        resource.current_amount = resource_data.current_amount
        resource.max_amount = resource_data.max_amount
        resource.resource_type = resource_data.resource_type
        resource.regeneration_rate = resource_data.regeneration_rate
        resource.discovered_by = resource_data.discovered_by.duplicate()
        resource.harvest_difficulty = resource_data.harvest_difficulty
        
        # Update visual state
        resource.update_visual_state()

func restore_celestial_bodies(body_data_array: Array[CelestialBodyData]):
    var existing_bodies = get_tree().get_nodes_in_group("celestial_bodies")
    
    for body_data in body_data_array:
        # Find matching celestial body by name
        var matching_body = null
        for body in existing_bodies:
            if body.body_name == body_data.name:
                matching_body = body
                break
        
        if matching_body:
            # Restore position and velocity
            matching_body.global_position = body_data.position
            matching_body.linear_velocity = body_data.velocity
            matching_body.orbit_points = body_data.orbit_points.duplicate()

func autosave():
    if not autosave_enabled:
        return
    
    var timestamp = Time.get_datetime_string_from_system().replace(":", "-")
    var autosave_name = "autosave_" + timestamp + ".tres"
    
    if save_simulation(autosave_name):
        # Clean up old autosaves
        cleanup_old_autosaves()

func cleanup_old_autosaves():
    var dir = DirAccess.open("user://saves/")
    if not dir:
        return
    
    var autosave_files = []
    dir.list_dir_begin()
    var file_name = dir.get_next()
    
    while file_name != "":
        if file_name.begins_with("autosave_") and file_name.ends_with(".tres"):
            autosave_files.append(file_name)
        file_name = dir.get_next()
    
    # Sort by modification time (newest first)
    autosave_files.sort_custom(func(a, b): 
        var time_a = FileAccess.get_modified_time("user://saves/" + a)
        var time_b = FileAccess.get_modified_time("user://saves/" + b)
        return time_a > time_b
    )
    
    # Remove excess autosaves
    for i in range(max_autosaves, autosave_files.size()):
        dir.remove(autosave_files[i])
        print("Removed old autosave: ", autosave_files[i])

func get_simulation_manager():
    return get_tree().get_first_node_in_group("simulation_manager")

func get_save_files() -> Array[String]:
    var save_files = []
    var dir = DirAccess.open("user://saves/")
    if not dir:
        return save_files
    
    dir.list_dir_begin()
    var file_name = dir.get_next()
    
    while file_name != "":
        if file_name.ends_with(".tres"):
            save_files.append(file_name)
        file_name = dir.get_next()
    
    return save_files

func delete_save_file(file_name: String) -> bool:
    var file_path = "user://saves/" + file_name
    var dir = DirAccess.open("user://saves/")
    if dir and dir.file_exists(file_name):
        return dir.remove(file_name) == OK
    return false
```

## 10. Performance Optimization System

### Object Pooling Manager
```gdscript
# ObjectPoolManager.gd (AutoLoad)
extends Node

var pools: Dictionary = {}
var active_objects: Dictionary = {}

class ObjectPool:
    var pool_name: String
    var scene_path: String
    var pool_size: int
    var available_objects: Array = []
    var in_use_objects: Array = []
    
    func _init(name: String, path: String, size: int):
        pool_name = name
        scene_path = path
        pool_size = size
        create_pool()
    
    func create_pool():
        var scene = load(scene_path)
        for i in range(pool_size):
            var obj = scene.instantiate()
            obj.set_meta("pooled", true)
            obj.set_meta("pool_name", pool_name)
            available_objects.append(obj)

func create_pool(pool_name: String, scene_path: String, pool_size: int):
    if pools.has(pool_name):
        push_warning("Pool already exists: " + pool_name)
        return
    
    pools[pool_name] = ObjectPool.new(pool_name, scene_path, pool_size)
    active_objects[pool_name] = []

func get_object(pool_name: String) -> Node:
    if not pools.has(pool_name):
        push_error("Pool does not exist: " + pool_name)
        return null
    
    var pool = pools[pool_name]
    
    if pool.available_objects.is_empty():
        # Pool exhausted, expand it
        expand_pool(pool_name, pool.pool_size * 2)
    
    var obj = pool.available_objects.pop_back()
    pool.in_use_objects.append(obj)
    active_objects[pool_name].append(obj)
    
    # Reset object state
    if obj.has_method("reset_for_pool"):
        obj.reset_for_pool()
    
    return obj

func return_object(obj: Node):
    if not obj.has_meta("pooled") or not obj.has_meta("pool_name"):
        push_error("Object is not from a pool")
        return
    
    var pool_name = obj.get_meta("pool_name")
    if not pools.has(pool_name):
        push_error("Pool does not exist: " + pool_name)
        return
    
    var pool = pools[pool_name]
    
    if obj in pool.in_use_objects:
        pool.in_use_objects.erase(obj)
        pool.available_objects.append(obj)
        active_objects[pool_name].erase(obj)
        
        # Hide and disable object
        obj.visible = false
        if obj.has_method("set_physics_process"):
            obj.set_physics_process(false)
        if obj.has_method("set_process"):
            obj.set_process(false)

func expand_pool(pool_name: String, new_size: int):
    if not pools.has(pool_name):
        return
    
    var pool = pools[pool_name]
    var scene = load(pool.scene_path)
    
    for i in range(pool.pool_size, new_size):
        var obj = scene.instantiate()
        obj.set_meta("pooled", true)
        obj.set_meta("pool_name", pool_name)
        pool.available_objects.append(obj)
    
    pool.pool_size = new_size
    print("Expanded pool '", pool_name, "' to size: ", new_size)

func get_pool_stats(pool_name: String) -> Dictionary:
    if not pools.has(pool_name):
        return {}
    
    var pool = pools[pool_name]
    return {
        "total_size": pool.pool_size,
        "available": pool.available_objects.size(),
        "in_use": pool.in_use_objects.size()
    }

func initialize_common_pools():
    # Create pools for commonly used objects
    create_pool("particle_effects", "res://effects/ParticleEffect.tscn", 50)
    create_pool("ui_elements", "res://ui/UIElement.tscn", 20)
    create_pool("audio_sources", "res://audio/AudioSource.tscn", 30)
    create_pool("visual_effects", "res://effects/VisualEffect.tscn", 25)

func _ready():
    initialize_common_pools()
```

### LOD (Level of Detail) System
```gdscript
# LODManager.gd
extends Node

var lod_objects: Array[LODObject] = []
var camera_position: Vector2 = Vector2.ZERO
var update_frequency: float = 0.5  # Update LOD twice per second
var update_timer: float = 0.0

class LODObject:
    var node: Node2D
    var lod_distances: Array[float]
    var current_lod: int = 0
    var lod_nodes: Array[Node] = []
    
    func _init(target_node: Node2D, distances: Array[float]):
        node = target_node
        lod_distances = distances
        setup_lod_nodes()
    
    func setup_lod_nodes():
        # Assuming LOD nodes are children named LOD0, LOD1, etc.
        for i in range(4):  # Support up to 4 LOD levels
            var lod_node = node.get_node_or_null("LOD" + str(i))
            if lod_node:
                lod_nodes.append(lod_node)
            else:
                break
    
    func update_lod(distance: float):
        var new_lod = calculate_lod_level(distance)
        if new_lod != current_lod:
            set_lod_level(new_lod)
    
    func calculate_lod_level(distance: float) -> int:
        for i in range(lod_distances.size()):
            if distance <= lod_distances[i]:
                return i
        return lod_distances.size()  # Furthest LOD
    
    func set_lod_level(lod_level: int):
        current_lod = lod_level
        
        # Hide all LOD nodes
        for lod_node in lod_nodes:
            lod_node.visible = false
        
        # Show appropriate LOD node
        if lod_level < lod_nodes.size():
            lod_nodes[lod_level].visible = true

func _ready():
    # Register all objects that need LOD management
    register_lod_objects()

func _process(delta):
    update_timer += delta
    if update_timer >= update_frequency:
        update_timer = 0.0
        update_all_lods()

func register_lod_objects():
    # Register celestial bodies
    for body in get_tree().get_nodes_in_group("celestial_bodies"):
        var distances = [1000.0, 5000.0, 20000.0]  # LOD distances
        add_lod_object(body, distances)
    
    # Register probes (if they have LOD nodes)
    for probe in get_tree().get_nodes_in_group("probes"):
        if probe.has_node("LOD0"):
            var distances = [500.0, 2000.0, 10000.0]
            add_lod_object(probe, distances)

func add_lod_object(node: Node2D, lod_distances: Array[float]):
    var lod_obj = LODObject.new(node, lod_distances)
    lod_objects.append(lod_obj)

func remove_lod_object(node: Node2D):
    for i in range(lod_objects.size() - 1, -1, -1):
        if lod_objects[i].node == node:
            lod_objects.remove_at(i)
            break

func update_camera_position(new_position: Vector2):
    camera_position = new_position

func update_all_lods():
    for lod_obj in lod_objects:
        if lod_obj.node and is_instance_valid(lod_obj.node):
            var distance = camera_position.distance_to(lod_obj.node.global_position)
            lod_obj.update_lod(distance)
        else:
            # Remove invalid objects
            lod_objects.erase(lod_obj)

func get_lod_stats() -> Dictionary:
    var stats = {"lod_0": 0, "lod_1": 0, "lod_2": 0, "lod_3": 0, "culled": 0}
    
    for lod_obj in lod_objects:
        var lod_key = "lod_" + str(lod_obj.current_lod)
        if stats.has(lod_key):
            stats[lod_key] += 1
        else:
            stats["culled"] += 1
    
    return stats
```

## 11. Implementation Timeline & Priority

### Phase 1: Core Foundation (Weeks 1-2)
1. **Project Setup & Configuration**
   - Create Godot project structure
   - Implement GameConfiguration resource system
   - Set up ConfigManager AutoLoad
   - Create basic scene hierarchy

2. **Core Physics Implementation**
   - Implement CelestialBody scene with orbital mechanics
   - Create basic Probe scene with RigidBody2D physics
   - Set up gravitational force calculations
   - Implement Verlet integration for celestial bodies

3. **Basic Resource System**
   - Create Resource scene with harvest mechanics
   - Implement resource discovery and depletion
   - Add basic particle effects for resources

### Phase 2: AI Integration & Simulation Logic (Weeks 3-4)
1. **AI Agent System**
   - Implement AIAgent component with HTTP communication
   - Create fallback Q-learning system
   - Add observation space generation
   - Implement action space processing

2.# Complete Godot Bobiverse Simulation - Comprehensive Implementation Guide

## Project Overview
Create a complete Bobiverse orbital simulation in Godot 4.x, converting from the existing Python/Pygame implementation while leveraging Godot's native features for better performance, easier development, and enhanced visuals. This implementation must preserve ALL existing features while utilizing Godot's engine strengths.

## 1. Project Structure & Scene Architecture

### Main Scene Hierarchy
```
Main (Node2D)
├── SimulationManager (Node) - Main game logic controller
├── SolarSystem (Node2D) - Container for all celestial bodies
│   ├── Sun (CelestialBody)
│   ├── Planets (Node2D)
│   │   ├── Mercury (CelestialBody)
│   │   ├── Venus (CelestialBody)
│   │   ├── Earth (CelestialBody)
│   │   │   └── Moon (CelestialBody)
│   │   ├── Mars (CelestialBody)
│   │   ├── Jupiter (CelestialBody)
│   │   │   ├── Io (CelestialBody)
│   │   │   ├── Europa (CelestialBody)
│   │   │   ├── Ganymede (CelestialBody)
│   │   │   └── Callisto (CelestialBody)
│   │   ├── Saturn (CelestialBody)
│   │   │   └── Titan (CelestialBody)
│   │   ├── Uranus (CelestialBody)
│   │   └── Neptune (CelestialBody)
│   └── AsteroidBelt (Node2D)
├── ProbeManager (Node2D) - Container for all probes
├── ResourceManager (Node2D) - Container for all resources
├── ParticleManager (Node2D) - Container for all particle effects
├── Camera2D - Main camera with smooth following
├── UI (CanvasLayer)
│   ├── HUD (Control)
│   ├── ProbeListPanel (Panel)
│   ├── SelectedProbePanel (Panel)
│   ├── SystemStatsPanel (Panel)
│   └── DebugPanel (Panel) - For development/debugging
└── Background (ParallaxBackground)
    ├── StarField1 (ParallaxLayer) - Far stars
    ├── StarField2 (ParallaxLayer) - Mid stars
    └── StarField3 (ParallaxLayer) - Near stars
```

## 2. Configuration System

### GameConfiguration Resource
Create a comprehensive configuration system using Godot Resources:

```gdscript
# GameConfiguration.gd
extends Resource
class_name GameConfiguration

# === World Configuration ===
@export_group("World Settings")
@export var world_size_au: float = 10.0
@export var asteroid_belt_inner_au: float = 2.2
@export var asteroid_belt_outer_au: float = 3.2
@export var asteroid_count: int = 500
@export var asteroid_mass_range: Vector2 = Vector2(1e10, 1e15)

# === Physics Configuration ===
@export_group("Physics Settings")
@export var timestep_seconds: float = 3600.0
@export var integration_method: String = "verlet"
@export var gravitational_constant: float = 6.67430e-20
@export var au_scale: float = 10000.0

# === Probe Configuration ===
@export_group("Probe Settings")
@export var max_probes: int = 20
@export var initial_probes: int = 1
@export var max_energy: float = 100000.0
@export var initial_energy: float = 90000.0
@export var replication_cost: float = 80000.0
@export var replication_min_energy: float = 99900.0
@export var probe_mass: float = 8.0
@export var thrust_force_magnitudes: Array[float] = [0.0, 0.08, 0.18, 0.32]
@export var thrust_energy_cost_factor: float = 0.001
@export var energy_decay_rate: float = 0.001
@export var max_velocity: float = 10000.0
@export var moment_of_inertia: float = 5.0
@export var torque_magnitudes: Array[float] = [0.0, 0.008, 0.018]
@export var max_angular_velocity: float = PI / 4
@export var communication_range: float = 100.0

# === Resource Configuration ===
@export_group("Resource Settings")
@export var resource_count: int = 15
@export var resource_amount_range: Vector2 = Vector2(10000, 20000)
@export var resource_regen_rate: float = 0.0
@export var harvest_rate: float = 2.0
@export var harvest_distance: float = 5.0
@export var discovery_range: float = 12.5

# === RL Configuration ===
@export_group("Reinforcement Learning")
@export var episode_length_steps: int = 50000
@export var learning_rate: float = 3e-4
@export var batch_size: int = 64
@export var observation_space_size: int = 25
@export var num_observed_resources: int = 3
@export var reward_factors: Dictionary = {
    "mining": 0.05,
    "high_energy": 0.1,
    "proximity": 1.95,
    "reach_target": 2.0,
    "stay_alive": 0.02
}

# === Visualization Configuration ===
@export_group("Visualization")
@export var screen_width: int = 1400
@export var screen_height: int = 900
@export var target_fps: int = 60
@export var probe_size: int = 12
@export var enable_particle_effects: bool = true
@export var enable_organic_ships: bool = true
@export var max_trail_points: int = 500
@export var max_orbit_points: int = 1000

# === Debug Configuration ===
@export_group("Debug Settings")
@export var debug_mode: bool = false
@export var show_orbital_mechanics: bool = true
@export var show_energy_conservation: bool = true
@export var memory_warn_mb: int = 2048
```

### Configuration AutoLoad
```gdscript
# ConfigManager.gd (AutoLoad)
extends Node

var config: GameConfiguration
var config_path: String = "user://game_config.tres"

func _ready():
    load_configuration()

func load_configuration():
    if ResourceLoader.exists(config_path):
        config = ResourceLoader.load(config_path)
    else:
        config = GameConfiguration.new()
        save_configuration()

func save_configuration():
    ResourceSaver.save(config, config_path)

func validate_configuration() -> bool:
    # Comprehensive validation logic
    if config.world_size_au <= 0:
        push_error("World size must be positive")
        return false
    
    if config.asteroid_belt_inner_au >= config.asteroid_belt_outer_au:
        push_error("Asteroid belt inner radius must be less than outer radius")
        return false
    
    if config.max_probes <= 0 or config.initial_probes <= 0:
        push_error("Probe counts must be positive")
        return false
    
    # Add more validation as needed
    return true
```

## 3. Core Game Objects & Components

### CelestialBody Scene (CelestialBody.tscn)
**Inherits:** RigidBody2D

```gdscript
# CelestialBody.gd
extends RigidBody2D
class_name CelestialBody

@export_group("Physical Properties")
@export var body_name: String = ""
@export var mass_kg: float = 0.0
@export var radius_km: float = 0.0
@export var display_radius: float = 50.0
@export var body_color: Color = Color.WHITE

@export_group("Orbital Elements (J2000.0)")
@export var semi_major_axis_au: float = 0.0
@export var eccentricity: float = 0.0
@export var inclination_deg: float = 0.0
@export var longitude_ascending_node_deg: float = 0.0
@export var argument_perihelion_deg: float = 0.0
@export var mean_anomaly_epoch_deg: float = 0.0
@export var central_body_name: String = ""

@onready var visual_component: Node2D = $VisualComponent
@onready var orbit_trail: Line2D = $OrbitTrail
@onready var gravity_field: Area2D = $GravityField
@onready var atmosphere_glow: Sprite2D = $VisualComponent/AtmosphereGlow

var orbit_points: Array[Vector2] = []
var previous_acceleration: Vector2 = Vector2.ZERO
var central_body: CelestialBody = null

signal body_clicked(body: CelestialBody)

func _ready():
    # Configure physics
    gravity_scale = 0  # We handle our own gravity
    set_collision_layer_value(1, true)  # Celestial bodies layer
    set_collision_mask_value(2, true)   # Interact with probes
    
    # Setup visual appearance
    setup_visual_appearance()
    
    # Initialize orbital mechanics
    calculate_initial_state()
    
    # Connect signals
    input_event.connect(_on_input_event)

func setup_visual_appearance():
    var sprite = $VisualComponent/BodySprite
    sprite.modulate = body_color
    
    # Scale sprite to match display radius
    var texture_size = sprite.texture.get_size()
    var scale_factor = (display_radius * 2) / max(texture_size.x, texture_size.y)
    sprite.scale = Vector2.ONE * scale_factor
    
    # Setup atmosphere glow if applicable
    if body_name in ["Earth", "Venus", "Jupiter", "Saturn"]:
        atmosphere_glow.modulate = body_color * 0.3
        atmosphere_glow.modulate.a = 0.5
        atmosphere_glow.scale = sprite.scale * 1.5

func calculate_initial_state():
    if central_body_name.is_empty() or body_name == "Sun":
        return  # Sun or bodies without central body
    
    # Find central body
    central_body = find_central_body()
    if not central_body:
        push_error("Central body not found: " + central_body_name)
        return
    
    # Calculate initial position and velocity using orbital elements
    var state = calculate_state_from_orbital_elements()
    global_position = central_body.global_position + state.position
    linear_velocity = state.velocity

func calculate_state_from_orbital_elements() -> Dictionary:
    # Convert AU to simulation units
    var a_sim = semi_major_axis_au * ConfigManager.config.au_scale
    var mu = ConfigManager.config.gravitational_constant * central_body.mass_kg
    
    # Solve Kepler's equation
    var M_rad = deg_to_rad(mean_anomaly_epoch_deg)
    var E_rad = solve_kepler_equation(M_rad, eccentricity)
    
    # Calculate true anomaly
    var nu_rad = 2.0 * atan2(
        sqrt(1.0 + eccentricity) * sin(E_rad / 2.0),
        sqrt(1.0 - eccentricity) * cos(E_rad / 2.0)
    )
    
    # Calculate distance
    var r = a_sim * (1.0 - eccentricity * cos(E_rad))
    
    # Position in orbital plane
    var x_orb = r * cos(nu_rad)
    var y_orb = r * sin(nu_rad)
    
    # Velocity in orbital plane
    var sqrt_mu_a = sqrt(mu * a_sim)
    var vx_orb = -sqrt_mu_a * sin(E_rad) / r
    var vy_orb = sqrt_mu_a * sqrt(1.0 - eccentricity * eccentricity) * cos(E_rad) / r
    
    # Transform from orbital plane to simulation plane (simplified 2D)
    var angle_sum = deg_to_rad(argument_perihelion_deg + longitude_ascending_node_deg)
    var cos_angle = cos(angle_sum)
    var sin_angle = sin(angle_sum)
    
    var position = Vector2(
        cos_angle * x_orb - sin_angle * y_orb,
        sin_angle * x_orb + cos_angle * y_orb
    )
    
    var velocity = Vector2(
        cos_angle * vx_orb - sin_angle * vy_orb,
        sin_angle * vx_orb + cos_angle * vy_orb
    )
    
    return {"position": position, "velocity": velocity}

func solve_kepler_equation(M: float, e: float, tolerance: float = 1e-10) -> float:
    var E = M + e * sin(M)  # Initial guess
    
    for i in range(100):  # Max iterations
        var f = E - e * sin(E) - M
        var f_prime = 1.0 - e * cos(E)
        
        if abs(f) < tolerance:
            break
            
        if abs(f_prime) < 1e-12:
            break  # Avoid division by zero
            
        E = E - f / f_prime
    
    return E

func _integrate_forces(state: PhysicsDirectBodyState2D):
    # Calculate gravitational forces from all other celestial bodies
    var total_force = Vector2.ZERO
    
    for body in get_tree().get_nodes_in_group("celestial_bodies"):
        if body == self:
            continue
            
        var celestial_body = body as CelestialBody
        if not celestial_body:
            continue
            
        var distance_vector = celestial_body.global_position - global_position
        var distance_sq = distance_vector.length_squared()
        
        if distance_sq < 1e-6:  # Avoid division by zero
            continue
            
        var force_magnitude = ConfigManager.config.gravitational_constant * mass_kg * celestial_body.mass_kg / distance_sq
        var force_direction = distance_vector.normalized()
        total_force += force_direction * force_magnitude
    
    # Apply gravitational force
    state.apply_central_force(total_force)
    
    # Store acceleration for Verlet integration
    previous_acceleration = total_force / mass_kg

func _physics_process(_delta):
    # Update orbit trail
    update_orbit_trail()
    
    # Check for probe interactions in gravity field
    check_gravity_field_interactions()

func update_orbit_trail():
    orbit_points.append(global_position)
    
    # Limit trail length
    while orbit_points.size() > ConfigManager.config.max_orbit_points:
        orbit_points.pop_front()
    
    # Update Line2D points
    orbit_trail.clear_points()
    for point in orbit_points:
        orbit_trail.add_point(point)

func check_gravity_field_interactions():
    # Apply gravitational influence to probes in range
    var bodies = gravity_field.get_overlapping_bodies()
    for body in bodies:
        if body is Probe:
            var probe = body as Probe
            var distance_vector = global_position - probe.global_position
            var distance = distance_vector.length()
            
            if distance > 0:
                var force_magnitude = ConfigManager.config.gravitational_constant * mass_kg * probe.mass / (distance * distance)
                var force = distance_vector.normalized() * force_magnitude
                probe.apply_external_force(force, "gravity_" + body_name)

func find_central_body() -> CelestialBody:
    for body in get_tree().get_nodes_in_group("celestial_bodies"):
        var celestial_body = body as CelestialBody
        if celestial_body and celestial_body.body_name == central_body_name:
            return celestial_body
    return null

func _on_input_event(_viewport, event, _shape_idx):
    if event is InputEventMouseButton and event.pressed:
        body_clicked.emit(self)
```

### Scene Structure for CelestialBody.tscn:
```
CelestialBody (RigidBody2D)
├── CollisionShape2D (CircleShape2D with radius matching display_radius)
├── VisualComponent (Node2D)
│   ├── BodySprite (Sprite2D) - Main planet/moon texture
│   ├── AtmosphereGlow (Sprite2D) - Atmospheric effects with glow shader
│   └── StatusLights (Node2D) - Visual indicators for active systems
├── OrbitTrail (Line2D) - Orbital trail rendering
│   └── [Configure: width=2, default_color=Color.GRAY with 50% alpha]
├── GravityField (Area2D) - Gravitational influence zone
│   └── GravityShape (CollisionShape2D) - Larger radius for gravity effects
└── AudioComponent (AudioStreamPlayer2D) - Ambient planetary sounds
```

### Probe Scene (Probe.tscn)
**Inherits:** RigidBody2D

```gdscript
# Probe.gd
extends RigidBody2D
class_name Probe

@export_group("Probe Properties")
@export var probe_id: int = 0
@export var generation: int = 0
@export var mass: float = 8.0

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

# State variables
var is_alive: bool = true
var is_mining: bool = false
var is_thrusting: bool = false
var is_communicating: bool = false
var current_target_id: int = -1
var current_task: String = "idle"

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
    
    # Connect signals
    sensor_array.body_entered.connect(_on_sensor_body_entered)
    sensor_array.body_exited.connect(_on_sensor_body_exited)
    communication_range.area_entered.connect(_on_communication_range_entered)
    
    # Initialize AI agent
    ai_agent.initialize(self)

func setup_visual_appearance():
    # Configure probe visual based on generation and energy
    var base_color = Color.CYAN
    if generation > 0:
        base_color = base_color.lerp(Color.YELLOW, min(generation * 0.1, 0.5))
    
    var hull_sprite = visual_component.get_node("HullSprite")
    hull_sprite.modulate = base_color
    
    # Scale based on probe size config
    var scale_factor = ConfigManager.config.probe_size / 24.0  # Assuming base sprite is 24px
    visual_component.scale = Vector2.ONE * scale_factor

func setup_sensor_systems():
    # Configure sensor array range
    var sensor_shape = sensor_array.get_node("SensorShape") as CollisionShape2D
    var circle_shape = CircleShape2D.new()
    circle_shape.radius = ConfigManager.config.discovery_range
    sensor_shape.shape = circle_shape
    
    # Configure communication range
    var comm_shape = communication_range.get_node("CommShape") as CollisionShape2D
    var comm_circle = CircleShape2D.new()
    comm_circle.radius = ConfigManager.config.communication_range
    comm_shape.shape = comm_circle

func setup_thruster_system():
    # Configure all thruster particle systems
    var main_thruster = thruster_system.get_node("MainThruster") as GPUParticles2D
    configure_thruster_particles(main_thruster, Vector2(0, 1))  # Rear-facing
    
    # RCS thrusters
    configure_thruster_particles(thruster_system.get_node("RCSThrusterN"), Vector2(0, -1))
    configure_thruster_particles(thruster_system.get_node("RCSThrusterS"), Vector2(0, 1))
    configure_thruster_particles(thruster_system.get_node("RCSThrusterE"), Vector2(1, 0))
    configure_thruster_particles(thruster_system.get_node("RCSThrusterW"), Vector2(-1, 0))

func configure_thruster_particles(thruster: GPUParticles2D, direction: Vector2):
    var material = ParticleProcessMaterial.new()
    
    # Emission
    material.emission.amount = 50
    material.emission.rate = 50.0
    
    # Direction and velocity
    material.direction = Vector3(direction.x, direction.y, 0)
    material.initial_velocity_min = 50.0
    material.initial_velocity_max = 150.0
    material.angular_velocity_min = -180.0
    material.angular_velocity_max = 180.0
    
    # Scale and color
    material.scale_min = 0.3
    material.scale_max = 1.2
    material.color = Color.CYAN
    
    # Add color ramp for temperature effect
    var gradient = Gradient.new()
    gradient.add_point(0.0, Color.WHITE)
    gradient.add_point(0.3, Color.CYAN)
    gradient.add_point(0.7, Color.BLUE)
    gradient.add_point(1.0, Color.TRANSPARENT)
    
    var texture = GradientTexture1D.new()
    texture.gradient = gradient
    material.color_ramp = texture
    
    # Lifetime
    material.lifetime = 2.0
    
    thruster.process_material = material
    thruster.emitting = false

func _integrate_forces(state: PhysicsDirectBodyState2D):
    # Apply external forces (gravity from celestial bodies)
    var total_external_force = Vector2.ZERO
    for force_name in external_forces:
        total_external_force += external_forces[force_name]
    state.apply_central_force(total_external_force)
    
    # Apply thrust forces
    if is_thrusting and current_thrust_level > 0:
        var thrust_magnitude = ConfigManager.config.thrust_force_magnitudes[current_thrust_level]
        var thrust_force = Vector2(0, -thrust_magnitude).rotated(rotation)  # Forward direction
        thrust_force *= thrust_ramp_ratio
        state.apply_central_force(thrust_force)
        
        # Apply energy cost
        var energy_cost = thrust_magnitude * ConfigManager.config.thrust_energy_cost_factor
        consume_energy(energy_cost)
    
    # Apply torque for rotation
    if current_torque_level > 0:
        var torque_magnitude = ConfigManager.config.torque_magnitudes[current_torque_level]
        var applied_torque = torque_magnitude * rotation_ramp_ratio
        
        # Determine rotation direction based on AI action
        if ai_agent.current_rotation_direction > 0:
            applied_torque = -applied_torque  # Clockwise
        
        state.apply_torque(applied_torque)
        
        # Apply energy cost for rotation
        var energy_cost = torque_magnitude * 0.1  # Rotational energy cost factor
        consume_energy(energy_cost)
    
    # Limit velocities
    if state.linear_velocity.length() > max_velocity:
        state.linear_velocity = state.linear_velocity.normalized() * max_velocity
    
    if abs(state.angular_velocity) > max_angular_velocity:
        state.angular_velocity = sign(state.angular_velocity) * max_angular_velocity

func _physics_process(delta):
    # Update energy decay
    current_energy -= ConfigManager.config.energy_decay_rate * delta
    
    # Check for death
    if current_energy <= 0 and is_alive:
        die()
    
    # Update visual effects based on energy
    update_visual_effects()
    
    # Update movement trail
    update_movement_trail()
    
    # Update AI agent
    if is_alive:
        ai_agent.update_step(delta)
    
    # Update action smoothing
    update_action_smoothing(delta)
    
    # Check for low energy warning
    if current_energy < max_energy * 0.25 and is_alive:
        energy_critical.emit(self, current_energy)

func update_visual_effects():
    # Update status lights based on energy level
    var status_lights = visual_component.get_node("StatusLights")
    var energy_ratio = current_energy / max_energy
    
    for light in status_lights.get_children():
        var light_sprite = light as Sprite2D
        if energy_ratio < 0.1:
            light_sprite.modulate = Color.RED
        elif energy_ratio < 0.3:
            light_sprite.modulate = Color.YELLOW
        else:
            light_sprite.modulate = Color.GREEN
        
        # Pulsing effect for low energy
        if energy_ratio < 0.3:
            var pulse = (sin(Time.get_ticks_msec() * 0.01) + 1.0) * 0.5
            light_sprite.modulate.a = 0.5 + pulse * 0.5

func update_movement_trail():
    trail_points.append(global_position)
    
    # Limit trail length
    while trail_points.size() > ConfigManager.config.max_trail_points:
        trail_points.pop_front()
    
    # Update Line2D
    movement_trail.clear_points()
    for point in trail_points:
        movement_trail.add_point(point)

func update_action_smoothing(delta):
    # Update thrust ramping
    if is_thrusting and current_thrust_level > 0:
        thrust_ramp_ratio = min(1.0, thrust_ramp_ratio + delta * 2.0)  # Ramp up
        steps_in_current_thrust += 1
    else:
        thrust_ramp_ratio = max(0.0, thrust_ramp_ratio - delta * 3.0)  # Ramp down faster
    
    # Update rotation ramping
    if current_torque_level > 0:
        rotation_ramp_ratio = min(1.0, rotation_ramp_ratio + delta * 3.0)
        steps_in_current_rotation += 1
    else:
        rotation_ramp_ratio = max(0.0, rotation_ramp_ratio - delta * 4.0)
    
    # Update thruster particle effects
    update_thruster_effects()

func update_thruster_effects():
    var main_thruster = thruster_system.get_node("MainThruster") as GPUParticles2D
    
    if is_thrusting and thrust_ramp_ratio > 0.1:
        main_thruster.emitting = true
        main_thruster.amount_ratio = thrust_ramp_ratio
        
        # Update particle color based on thrust level
        var material = main_thruster.process_material as ParticleProcessMaterial
        var intensity = thrust_ramp_ratio * current_thrust_level / float(ConfigManager.config.thrust_force_magnitudes.size() - 1)
        material.color = Color.CYAN.lerp(Color.WHITE, intensity)
        
        # Play thruster audio
        if not audio_component.playing:
            audio_component.play()
    else:
        main_thruster.emitting = false
        audio_component.stop()

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
    
    # Visual death effect
    var tween = create_tween()
    tween.parallel().tween_property(visual_component, "modulate", Color.RED, 1.0)
    tween.parallel().tween_property(visual_component, "scale", Vector2.ZERO, 1.0)
    tween.tween_callback(queue_free)
    
    probe_destroyed.emit(self)

func attempt_replication():
    if current_energy >= ConfigManager.config.replication_cost and is_alive:
        current_energy -= ConfigManager.config.replication_cost
        replication_requested.emit(self)

func start_mining(target_resource):
    if not is_alive:
        return
    
    is_mining = true
    current_task = "mining"
    
    # Show mining laser
    mining_laser.clear_points()
    mining_laser.add_point(global_position)
    mining_laser.add_point(target_resource.global_position)
    mining_laser.default_color = Color.GREEN
    mining_laser.width = 3.0
    mining_laser.visible = true
    
    # Start mining particles
    var mining_particles = thruster_system.get_node("MiningParticles") as GPUParticles2D
    mining_particles.emitting = true
    mining_particles.global_position = target_resource.global_position

func stop_mining():
    is_mining = false
    current_task = "idle"
    mining_laser.visible = false
    
    var mining_particles = thruster_system.get_node("MiningParticles") as GPUParticles2D
    mining_particles.emitting = false

func send_communication(target_position: Vector2, message_type: String):
    if not is_alive:
        return
    
    is_communicating = true
    communication_sent.emit(self, target_position, message_type)
    
    # Create communication beam effect
    var beam_effect = preload("res://effects/CommunicationBeam.tscn").instantiate()
    get_tree().current_scene.add_child(beam_effect)
    beam_effect.setup_beam(global_position, target_position)

func get_observation_data() -> Dictionary:
    # Generate comprehensive observation data for AI
    var observation = {
        "position": global_position,
        "velocity": linear_velocity,
        "rotation": rotation,
        "angular_velocity": angular_velocity,
        "energy": current_energy,
        "energy_ratio": current_energy / max_energy,
        "is_mining": is_mining,
        "is_thrusting": is_thrusting,
        "current_target_id": current_target_id,
        "nearby_resources": get_nearby_resources(),
        "nearby_probes": get_nearby_probes(),
        "nearby_celestial_bodies": get_nearby_celestial_bodies(),
        "sensor_data": get_sensor_readings()
    }
    return observation

func get_nearby_resources() -> Array:
    var resources = []
    var bodies = sensor_array.get_overlapping_bodies()
    
    for body in bodies:
        if body is Resource:
            var resource = body as Resource
            var distance = global_position.distance_to(resource.global_position)
            resources.append({
                "position": resource.global_position,
                "amount": resource.current_amount,
                "distance": distance,
                "type": resource.resource_type
            })
    
    # Sort by distance
    resources.sort_custom(func(a, b): return a.distance < b.distance)
    
    # Return only closest N resources
    return resources.slice(0, ConfigManager.config.num_observed_resources)

func get_nearby_probes() -> Array:
    var probes = []
    var areas = communication_range.get_overlapping_areas()
    
    for area in areas:
        var probe = area.get_parent() as Probe
        if probe and probe != self and probe.is_alive:
            var distance = global_position.distance_to(probe.global_position)
            probes.append({
                "position": probe.global_position,
                "velocity": probe.linear_velocity,
                "energy": probe.current_energy,
                "distance": distance,
                "generation": probe.generation,
                "id": probe.probe_id
            })
    
    probes.sort_custom(func(a, b): return a.distance < b.distance)
    return probes.slice(0, 5)  # Return closest 5 probes

func get_nearby_celestial_bodies() -> Array:
    var bodies = []
    
    for body in get_tree().get_nodes_in_group("celestial_bodies"):
        var celestial_body = body as CelestialBody
        if celestial_body:
            var distance = global_position.distance_to(celestial_body.global_position)
            if distance < 5000:  # Only include bodies within reasonable range
                bodies.append({
                    "name": celestial_body.body_name,
                    "position": celestial_body.global_position,
                    "mass": celestial_body.mass_kg,
                    "distance": distance,
                    "gravity_influence": calculate_gravity_influence(celestial_body)
                })
    
    bodies.sort_custom(func(a, b): return a.distance < b.distance)
    return bodies.slice(0, 3)

func calculate_gravity_influence(celestial_body: CelestialBody) -> float:
    var distance = global_position.distance_to(celestial_body.global_position)
    if distance < 1e-6:
        return 0.0
    
    return ConfigManager.config.gravitational_constant * celestial_body.mass_kg / (distance * distance)

func get_sensor_readings() -> Dictionary:
    return {
        "energy_sensors": {
            "solar_input": calculate_solar_energy_input(),
            "heat_signature": current_energy / max_energy
        },
        "proximity_sensors": {
            "collision_risk": calculate_collision_risk(),
            "gravity_gradient": calculate_gravity_gradient()
        },
        "navigation_sensors": {
            "velocity_magnitude": linear_velocity.length(),
            "angular_velocity_magnitude": abs(angular_velocity),
            "heading": rotation
        }
    }

func calculate_solar_energy_input() -> float:
    # Calculate solar energy based on distance from Sun
    var sun = get_tree().get_first_node_in_group("sun")
    if not sun:
        return 0.0
    
    var distance_to_sun = global_position.distance_to(sun.global_position)
    var solar_constant = 1361.0  # W/m² at 1 AU
    var au_distance = distance_to_sun / ConfigManager.config.au_scale
    
    return solar_constant / (au_distance * au_distance)

func calculate_collision_risk() -> float:
    # Simple collision risk assessment
    var risk = 0.0
    var bodies = sensor_array.get_overlapping_bodies()
    
    for body in bodies:
        if body == self:
            continue
        
        var distance = global_position.distance_to(body.global_position)
        var relative_velocity = (linear_velocity - body.linear_velocity).length()
        
        if distance > 0 and relative_velocity > 0:
            var time_to_collision = distance / relative_velocity
            if time_to_collision < 10.0:  # 10 seconds
                risk += 1.0 / time_to_collision
    
    return min(risk, 1.0)

func calculate_gravity_gradient() -> float:
    # Measure change in gravitational field
    var current_gravity = Vector2.ZERO
    for force_name in external_forces:
        if force_name.begins_with("gravity_"):
            current_gravity += external_forces[force_name]
    
    return current_gravity.length()

func _on_sensor_body_entered(body):
    if body is Resource:
        var resource = body as Resource
        resource_discovered.emit(self, resource.global_position, resource.current_amount)

func _on_sensor_body_exited(body):
    # Handle sensor exit events if needed
    pass

func _on_communication_range_entered(area):
    # Handle probe entering communication range
    var other_probe = area.get_parent() as Probe
    if other_probe and other_probe != self:
        # Could trigger automatic information exchange
        pass
```

### Scene Structure for Probe.tscn:
```
Probe (RigidBody2D)
├── CollisionShape2D (CircleShape2D)
├── VisualComponent (Node2D)
│   ├── HullSprite (Sprite2D) - Main probe body with organic ship texture
│   ├── SolarPanels (Node2D)
│   │   ├── LeftPanel (Sprite2D)
│   │   └── RightPanel (Sprite2D)
│   ├── CommunicationDish (Sprite2D)
│   ├── SensorArray (Sprite2D) - Visual representation of sensors
│   └── StatusLights (Node2D)
│       ├── StatusLight1 (Sprite2D)
│       ├── StatusLight2 (Sprite2D)
│       └── StatusLight3 (Sprite2D)
├── ThrusterSystem (Node2D)
│   ├── MainThruster (GPUParticles2D) - Primary propulsion
│   ├── RCSThrusterN (GPUParticles2D) - North RCS
│   ├── RCSThrusterS (GPUParticles2D) - South RCS
│   ├── RCSThrusterE (GPUParticles2D) - East RCS
│   ├── RCSThrusterW (GPUParticles2D) - West RCS
│   └── MiningParticles (GPUParticles2D) - Mining effect particles
├── SensorArray (Area2D) - Detection and resource discovery
│   └── SensorShape (CollisionShape2D) - Large circle for detection range
├── CommunicationRange (Area2D) - Inter-probe communication
│   └── CommShape (CollisionShape2D) - Communication range circle
├── MovementTrail (Line2D) - Visual trail of movement
├── MiningLaser (Line2D) - Mining beam visualization
├── AIAgent (Node) - RL/AI behavior controller
├── EnergySystem (Node) - Energy management system
└── AudioComponent (AudioStreamPlayer2D) - Thruster and system sounds
```

### Resource Scene (Resource.tscn)
**Inherits:** Area2D

```gdscript
# Resource.gd
extends Area2D
class_name Resource

@export_group("Resource Properties")
@export var resource_type: String = "mineral"
@export var max_amount: float = 20000.0
@export var current_amount: float = 20000.0
@export var regeneration_rate: float = 0.0
@export var harvest_difficulty: float = 1.0

@onready var resource_sprite: Sprite2D = $ResourceSprite
@onready var glow_effect: Sprite2D = $GlowEffect
@onready var amount_label: Label = $AmountLabel
@onready var particle_effect: GPUParticles2D = $ParticleEffect
@onready var audio_component: AudioStreamPlayer2D = $AudioComponent
@onready var collection_area: CollisionShape2D = $CollectionShape

var discovered_by: Array[int] = []  # Probe IDs that discovered this resource
var being_harvested_by: Array[Probe] = []
var glow_tween: Tween

signal resource_depleted(resource: Resource)
signal resource_discovered(resource: Resource, discovering_probe: Probe)
signal resource_harvested(resource: Resource, harvesting_probe: Probe, amount: float)

func _ready():
    # Configure collision detection
    set_collision_layer_value(3, true)  # Resources layer
    set_collision_mask_value(2, true)   # Detect probes
    
    # Add to groups
    add_to_group("resources")
    
    # Setup visual appearance
    setup_visual_appearance()
    
    # Setup particle effects
    setup_particle_effects()
    
    # Connect signals
    body_entered.connect(_on_body_entered)
    body_exited.connect(_on_body_exited)
    
    # Start glow animation
    start_glow_animation()

func setup_visual_appearance():
    # Set resource color based on type and amount
    var color_map = {
        "mineral": Color.GREEN,
        "energy": Color.CYAN,
        "rare_earth": Color.YELLOW,
        "water": Color.BLUE
    }
    
    var base_color = color_map.get(resource_type, Color.WHITE)
    resource_sprite.modulate = base_color
    
    # Scale sprite based on amount
    var amount_ratio = current_amount / max_amount
    var scale_factor = 0.5 + (amount_ratio * 1.5)  # Scale from 0.5 to 2.0
    resource_sprite.scale = Vector2.ONE * scale_factor
    
    # Setup glow effect
    glow_effect.modulate = base_color * 0.7
    glow_effect.modulate.a = 0.6
    glow_effect.scale = resource_sprite.scale * 1.8

func setup_particle_effects():
    # Configure ambient resource particles
    var material = ParticleProcessMaterial.new()
    
    material.emission.amount = int(20 * (current_amount / max_amount))
    material.emission.rate = 10.0
    
    # Circular emission around resource
    material.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
    material.emission_sphere_radius = 30.0
    
    # Gentle floating motion
    material.direction = Vector3(0, -1, 0)
    material.initial_velocity_min = 5.0
    material.initial_velocity_max = 15.0
    material.gravity = Vector3(0, -2, 0)
    material.scale_min = 0.2
    material.scale_max = 0.8
    
    # Resource-appropriate color
    var color_map = {
        "mineral": Color.GREEN,
        "energy": Color.CYAN,
        "rare_earth": Color.YELLOW,
        "water": Color.BLUE
    }
    material.color = color_map.get(resource_type, Color.WHITE)
    
    # Lifetime and fading
    material.lifetime = 4.0
    var gradient = Gradient.new()
    gradient.add_point(0.0, Color.WHITE)
    gradient.add_point(0.8, material.color)
    gradient.add_point(1.0, Color.TRANSPARENT)
    
    var texture = GradientTexture1D.new()
    texture.gradient = gradient
    material.color_ramp = texture
    
    particle_effect.process_material = material

func start_glow_animation():
    glow_tween = create_tween()
    glow_tween.set_loops()
    
    var intensity_variation = 0.3 + (current_amount / max_amount) * 0.4
    glow_tween.tween_method(update_glow_intensity, 0.4, 1.0, 2.0)
    glow_tween.tween_method(update_glow_intensity, 1.0, 0.4, 2.0)

func update_glow_intensity(intensity: float):
    if glow_effect:
        glow_effect.modulate.a = intensity * 0.6

func _physics_process(delta):
    # Regenerate resource if applicable
    if regeneration_rate > 0 and current_amount < max_amount:
        current_amount = min(max_amount, current_amount + regeneration_rate * delta)
        update_visual_state()
    
    # Update amount label
    if amount_label.visible:
        amount_label.text = str(int(current_amount))
    
    # Process harvesting
    process_harvesting(delta)

func process_harvesting(delta):
    for probe in being_harvested_by:
        if not probe or not probe.is_alive:
            continue
        
        var distance = global_position.distance_to(probe.global_position)
        if distance <= ConfigManager.config.harvest_distance:
            var harvest_amount = ConfigManager.config.harvest_rate * delta * harvest_difficulty
            var actual_harvested = harvest(harvest_amount)
            
            if actual_harvested > 0:
                # Give energy to the harvesting probe
                probe.current_energy = min(probe.max_energy, probe.current_energy + actual_harvested * 0.1)
                resource_harvested.emit(self, probe, actual_harvested)
                
                # Visual and audio feedback
                create_harvest_effect(probe)

func harvest(amount: float) -> float:
    if current_amount <= 0:
        return 0.0
    
    var harvested = min(amount, current_amount)
    current_amount -= harvested
    
    update_visual_state()
    
    if current_amount <= 0:
        resource_depleted.emit(self)
        # Don't destroy immediately - allow for potential regeneration
    
    return harvested

func update_visual_state():
    # Update visual appearance based on current amount
    var amount_ratio = current_amount / max_amount
    
    # Update sprite scale
    var scale_factor = 0.3 + (amount_ratio * 1.2)
    resource_sprite.scale = Vector2.ONE * scale_factor
    glow_effect.scale = resource_sprite.scale * 1.8
    
    # Update particle count
    var material = particle_effect.process_material as ParticleProcessMaterial
    if material:
        material.emission.amount = max(5, int(20 * amount_ratio))
    
    # Update glow intensity
    var base_color = resource_sprite.modulate
    glow_effect.modulate = base_color * (0.4 + amount_ratio * 0.6)
    
    # Hide if completely depleted
    if current_amount <= 0:
        visible = false
        set_collision_mask_value(2, false)
    else:
        visible = true
        set_collision_mask_value(2, true)

func create_harvest_effect(harvesting_probe: Probe):
    # Create visual effect for harvesting
    var effect = preload("res://effects/HarvestEffect.tscn").instantiate()
    get_tree().current_scene.add_child(effect)
    effect.global_position = global_position
    effect.setup_effect(global_position, harvesting_probe.global_position)
    
    # Play harvest sound
    if not audio_component.playing:
        audio_component.play()

func discover(discovering_probe: Probe):
    if discovering_probe.probe_id not in discovered_by:
        discovered_by.append(discovering_probe.probe_id)
        resource_discovered.emit(self, discovering_probe)
        
        # Visual discovery effect
        var discovery_effect = preload("res://effects/DiscoveryEffect.tscn").instantiate()
        get_tree().current_scene.add_child(discovery_effect)
        discovery_effect.global_position = global_position

func _on_body_entered(body):
    if body is Probe:
        var probe = body as Probe
        if probe.is_alive:
            # Check if within harvest distance
            var distance = global_position.distance_to(probe.global_position)
            if distance <= ConfigManager.config.harvest_distance:
                if probe not in being_harvested_by:
                    being_harvested_by.append(probe)
                    probe.start_mining(self)
            
            # Check for discovery
            if distance <= ConfigManager.config.discovery_range:
                discover(probe)

func _on_body_exited(body):
    if body is Probe:
        var probe = body as Probe
        if probe in being_harvested_by:
            being_harvested_by.erase(probe)
            probe.stop_mining()
```

### Scene Structure for Resource.tscn:
```
Resource (Area2D)
├── CollectionShape (CollisionShape2D) - Circle for harvest/discovery range
├── ResourceSprite (Sprite2D) - Main resource visual
├── GlowEffect (Sprite2D) - Pulsing glow with shader material
├── AmountLabel (Label) - Shows current resource amount
├── ParticleEffect (GPUParticles2D) - Ambient resource particles
└── AudioComponent (AudioStreamPlayer2D) - Harvest and discovery sounds
```

## 4. AI/RL Integration System

### AI Agent Component
```gdscript
# AIAgent.gd
extends Node
class_name AIAgent

@export var use_external_ai: bool = true  # Use Python RL server vs built-in
@export var ai_server_url: String = "http://localhost:8000"
@export var update_frequency: float = 0.1  # AI decisions per second

var parent_probe: Probe
var http_request: HTTPRequest
var current_observation: Dictionary
var current_action: Array = [0, 0, 0, 0, 0]  # [thrust, torque, communicate, replicate, target]
var last_reward: float = 0.0
var episode_step: int = 0
var current_rotation_direction: int = 0  # -1, 0, 1 for left, none, right

# Built-in simple RL for fallback
var q_learning: SimpleQLearning
var last_state_hash: String = ""

# Action smoothing
var action_timer: float = 0.0
var pending_action: bool = false

signal action_received(action: Array)
signal reward_calculated(reward: float)

func _ready():
    # Setup HTTP client for external AI
    if use_external_ai:
        http_request = HTTPRequest.new()
        add_child(http_request)
        http_request.request_completed.connect(_on_ai_response_received)
        http_request.timeout = 1.0  # 1 second timeout
    
    # Setup fallback Q-learning
    q_learning = SimpleQLearning.new()
    q_learning.action_space_size = 5  # Number of discrete actions
    add_child(q_learning)

func initialize(probe: Probe):
    parent_probe = probe
    episode_step = 0
    
    # Connect to probe signals for reward calculation
    probe.resource_discovered.connect(_on_resource_discovered)
    probe.energy_critical.connect(_on_energy_critical)

func update_step(delta: float):
    if not parent_probe or not parent_probe.is_alive:
        return
    
    action_timer += delta
    
    # Request new action at specified frequency
    if action_timer >= update_frequency:
        action_timer = 0.0
        request_action()

func request_action():
    current_observation = parent_probe.get_observation_data()
    episode_step += 1
    
    if use_external_ai and http_request:
        request_external_action()
    else:
        request_builtin_action()

func request_external_action():
    # Prepare observation data for external AI
    var observation_array = flatten_observation(current_observation)
    
    var request_data = {
        "observation": observation_array,
        "probe_id": parent_probe.probe_id,
        "episode_step": episode_step,
        "last_reward": last_reward
    }
    
    var json_string = JSON.stringify(request_data)
    var headers = ["Content-Type: application/json"]
    
    # Make async request to AI server
    var error = http_request.request(ai_server_url + "/predict", headers, HTTPClient.METHOD_POST, json_string)
    if error != OK:
        print("Failed to send AI request: ", error)
        # Fallback to built-in AI
        request_builtin_action()

func flatten_observation(obs: Dictionary) -> Array:
    # Convert complex observation dictionary to flat array for RL model
    var flat_obs = []
    
    # Probe state (7 values)
    flat_obs.append(obs.position.x / 10000.0)  # Normalized position
    flat_obs.append(obs.position.y / 10000.0)
    flat_obs.append(obs.velocity.x / 1000.0)   # Normalized velocity
    flat_obs.append(obs.velocity.y / 1000.0)
    flat_obs.append(obs.rotation / (2 * PI))   # Normalized rotation
    flat_obs.append(obs.angular_velocity / PI) # Normalized angular velocity
    flat_obs.append(obs.energy_ratio)          # Already normalized
    
    # Resource observations (3 resources × 4 values = 12 values)
    var resources = obs.get("nearby_resources", [])
    for i in range(3):  # Fixed number for consistent observation space
        if i < resources.size():
            var resource = resources[i]
            flat_obs.append(resource.position.x / 10000.0)
            flat_obs.append(resource.position.y / 10000.0)
            flat_obs.append(resource.distance / 1000.0)
            flat_obs.append(resource.amount / 20000.0)
        else:
            flat_obs.append_array([0.0, 0.0, 0.0, 0.0])  # Padding
    
    # Celestial bodies (2 bodies × 3 values = 6 values)
    var celestial_bodies = obs.get("nearby_celestial_bodies", [])
    for i in range(2):
        if i < celestial_bodies.size():
            var body = celestial_bodies[i]
            flat_obs.append(body.distance / 10000.0)
            flat_obs.append(body.gravity_influence * 1000.0)  # Scale up small values
            flat_obs.append(body.mass / 1e24)  # Normalize mass
        else:
            flat_obs.append_array([0.0, 0.0, 0.0])
    
    # Ensure exact size matches config
    while flat_obs.size() < ConfigManager.config.observation_space_size:
        flat_obs.append(0.0)
    flat_obs = flat_obs.slice(0, ConfigManager.config.observation_space_size)
    
    return flat_obs

func request_builtin_action():
    # Use simple Q-learning as fallback
    var state_hash = hash_observation(current_observation)
    var action_index = q_learning.get_action(state_hash)
    
    # Convert single action index to multi-dimensional action
    current_action = decode_action_index(action_index)
    apply_action(current_action)
    
    # Update Q-learning with previous experience
    if not last_state_hash.is_empty():
        var reward = calculate_reward()
        q_learning.update_q_value(last_state_hash, action_index, reward, state_hash)
        last_reward = reward
    
    last_state_hash = state_hash

func hash_observation(obs: Dictionary) -> String:
    # Create simple state hash for Q-learning
    var pos_hash = str(int(obs.position.x / 100)) + "," + str(int(obs.position.y / 100))
    var energy_hash = str(int(obs.energy_ratio * 10))
    var resource_hash = ""
    
    if obs.has("nearby_resources") and obs.nearby_resources.size() > 0:
        var closest = obs.nearby_resources[0]
        resource_hash = str(int(closest.distance / 50))
    
    return pos_hash + "_" + energy_hash + "_" + resource_hash

func decode_action_index(index: int) -> Array:
    # Convert single action index to multi-dimensional action array
    # This is a simplified mapping - real implementation would be more sophisticated
    match index:
        0: return [0, 0, 0, 0, 0]  # No action
        1: return [1, 0, 0, 0, 0]  # Thrust forward
        2: return [0, 1, 0, 0, 0]  # Rotate left
        3: return [0, 2, 0, 0, 0]  # Rotate right
        4: return [0, 0, 0, 0, 1]  # Target closest resource
        _: return [0, 0, 0, 0, 0]

func _on_ai_response_received(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
    if response_code == 200:
        var json = JSON.new()
        var parse_result = json.parse(body.get_string_from_utf8())
        
        if parse_result == OK and json.data.has("action"):
            current_action = json.data.action
            apply_action(current_action)
            action_received.emit(current_action)
        else:
            print("Failed to parse AI response")
            request_builtin_action()  # Fallback
    else:
        print("AI server error: ", response_code)
        request_builtin_action()  # Fallback

func apply_action(action: Array):
    if not parent_probe or not parent_probe.is_alive:
        return
    
    # action = [thrust_level, torque_level, communicate, replicate, target_resource]
    
    # Apply thrust action
    var thrust_level = action[0] if action.size() > 0 else 0
    if thrust_level > 0 and thrust_level < ConfigManager.config.thrust_force_magnitudes.size():
        parent_probe.current_thrust_level = thrust_level
        parent_probe.is_thrusting = true
    else:
        parent_probe.current_thrust_level = 0
        parent_probe.is_thrusting = false
    
    # Apply rotation action
    var torque_level = action[1] if action.size() > 1 else 0
    if torque_level > 0 and torque_level < ConfigManager.config.torque_magnitudes.size():
        parent_probe.current_torque_level = torque_level
        current_rotation_direction = 1 if torque_level % 2 == 1 else -1  # Odd = right, even = left
    else:
        parent_probe.current_torque_level = 0
        current_rotation_direction = 0
    
    # Apply communication action
    var communicate = action[2] if action.size() > 2 else 0
    if communicate > 0:
        # Find nearest probe and send communication
        var nearby_probes = current_observation.get("nearby_probes", [])
        if nearby_probes.size() > 0:
            var target_probe = nearby_probes[0]
            parent_probe.send_communication(target_probe.position, "resource_location")
    
    # Apply replication action
    var replicate = action[3] if action.size() > 3 else 0
    if replicate > 0:
        parent_probe.attempt_replication()
    
    # Apply targeting action
    var target_action = action[4] if action.size() > 4 else 0
    if target_action > 0:
        var nearby_resources = current_observation.get("nearby_resources", [])
        var target_index = (target_action - 1) % max(1, nearby_resources.size())
        if target_index < nearby_resources.size():
            parent_probe.current_target_id = target_index
            parent_probe.target_resource_idx = target_index

func calculate_reward() -> float:
    if not parent_probe:
        return 0.0
    
    var reward = 0.0
    var config_rewards = ConfigManager.config.reward_factors
    
    # Stay alive bonus
    if parent_probe.is_alive:
        reward += config_rewards.get("stay_alive", 0.02)
    
    # Energy level rewards/penalties
    var energy_ratio = parent_probe.current_energy / parent_probe.max_energy
    if energy_ratio > 0.75:
        reward += config_rewards.get("high_energy", 0.1)
    elif energy_ratio < 0.25:
        reward -= 0.1  # Low energy penalty
    elif energy_ratio < 0.1:
        reward -= 0.3  # Critical energy penalty
    
    # Mining reward
    if parent_probe.is_mining:
        reward += config_rewards.get("mining", 0.05)
    
    # Proximity to target resource reward
    if parent_probe.target_resource_idx >= 0:
        var nearby_resources = current_observation.get("nearby_resources", [])
        if parent_probe.target_resource_idx < nearby_resources.size():
            var target_resource = nearby_resources[parent_probe.target_resource_idx]
            var distance = target_resource.distance
            var proximity_reward = config_rewards.get("proximity", 1.95) * exp(-distance / 100.0)
            reward += proximity_reward
    
    # Efficiency penalties
    if parent_probe.is_thrusting and parent_probe.current_thrust_level > 0:
        # Small penalty for fuel consumption
        reward -= 0.001 * parent_probe.current_thrust_level
    
    return reward

func _on_resource_discovered(probe: Probe, resource_position: Vector2, amount: float):
    # Bonus reward for discovering new resources
    last_reward += 0.5 * (amount / 20000.0)  # Scale by resource size

func _on_energy_critical(probe: Probe, energy_level: float):
    # Penalty for reaching critical energy
    last_reward -= 0.2

# Simple Q-Learning implementation for fallback
class_name SimpleQLearning
extends Node

var q_table: Dictionary = {}
var learning_rate: float = 0.1
var discount_factor: float = 0.95
var epsilon: float = 0.1
var epsilon_decay: float = 0.995
var min_epsilon: float = 0.01
var action_space_size: int = 5

func _ready():
    # Decay epsilon over time
    var timer = Timer.new()
    timer.wait_time = 1.0
    timer.timeout.connect(_decay_epsilon)
    add_child(timer)
    timer.start()

func _decay_epsilon():
    epsilon = max(min_epsilon, epsilon * epsilon_decay)

func get_action(state: String) -> int:
    if randf() < epsilon:
        return randi() % action_space_size  # Explore
    else:
        return get_best_action(state)  # Exploit

func get_best_action(state: String) -> int:
    if not q_table.has(state):
        initialize_state(state)
    
    var best_action = 0
    var best_value = q_table[state][0]
    
    for i in range(1, action_space_size):
        if q_table[state][i] > best_value:
            best_value = q_table[state][i]
            best_action = i
    
    return best_action

func get_max_q_value(state: String) -> float:
    if not q_table.has(state):
        initialize_state(state)
    
    var max_value = q_table[state][0]
    for i in range(1, action_space_size):
        max_value = max(max_value, q_table[state][i])
    
    return max_value

func update_q_value(state: String, action: int, reward: float, next_state: String):
    if not q_table.has(state):
        initialize_state(state)
    
    var current_q = q_table[state][action]
    var max_next_q = get_max_q_value(next_state)
    var new_q = current_q + learning_rate * (reward + discount_factor * max_next_q - current_q)
    q_table[state][action] = new_q

func initialize_state(state: String):
    q_table[state] = []
    for i in range(action_space_size):
        q_table[state].append(0.0)
```

## 5. Simulation Manager System

### Main Simulation Controller
```gdscript
# SimulationManager.gd
extends Node
class_name SimulationManager

@export var max_simulation_steps: int = 50000
@export var simulation_speed: float = 1.0
@export var auto_pause_on_events: bool = true

@onready var solar_system: Node2D = $"../SolarSystem"
@onready var probe_manager: Node2D = $"../ProbeManager"
@onready var resource_manager: Node2D = $"../ResourceManager"
@onready var ui_system: Control = $"../UI"
@onready var camera: Camera2D = $"../Camera2D"

var current_step: int = 0
var simulation_running: bool = false
var episode_count: int = 0
var total_resources_mined: float = 0.0
var simulation_start_time: float = 0.0

# Performance monitoring
var frame_time_accumulator: float = 0.0
var frame_count: int = 0
var average_fps: float = 60.0

# Save/Load
var autosave_interval: float = 300.0  # 5 minutes
var last_autosave: float = 0.0

signal simulation_started()
signal simulation_paused()
signal simulation_ended()
signal episode_completed(episode_num: int, total_steps: int)
signal probe_count_changed(new_count: int)

func _ready():
    # Initialize simulation
    initialize_simulation()
    
    # Connect signals
    connect_system_signals()
    
    # Start first episode
    start_new_episode()

func initialize_simulation():
    # Validate configuration
    if not ConfigManager.validate_configuration():
        push_error("Invalid configuration detected")
        return
    
    # Initialize solar system
    initialize_solar_system()
    
    # Initialize resources
    initialize_resources()
    
    # Setup camera
    setup_camera()
    
    # Initialize UI
    setup_ui()
    
    print("Simulation initialized successfully")

func initialize_solar_system():
    # Create celestial bodies based on configuration
    var sun_scene = preload("res://celestial_bodies/CelestialBody.tscn")
    var sun_instance = sun_scene.instantiate()
    
    # Configure Sun
    sun_instance.body_name = "Sun"
    sun_instance.mass_kg = 1.9885e30
    sun_instance.radius_km = 695700.0
    sun_instance.display_radius = 500.0
    sun_instance.body_color = Color.YELLOW
    sun_instance.global_position = Vector2(ConfigManager.config.world_size_au * ConfigManager.config.au_scale / 2, 
                                           ConfigManager.config.world_size_au * ConfigManager.config.au_scale / 2)
    
    solar_system.add_child(sun_instance)
    sun_instance.add_to_group("celestial_bodies")
    sun_instance.add_to_group("sun")
    
    # Create planets and moons
    create_planets()

func create_planets():
    var planet_data = {
        "Mercury": {"mass": 0.33011e24, "radius": 2439.7, "color": Color.GRAY, "sma": 0.387098, "ecc": 0.205630},
        "Venus": {"mass": 4.8675e24, "radius": 6051.8, "color": Color(1.0, 0.8, 0.3), "sma": 0.723332, "ecc": 0.006772},
        "Earth": {"mass": 5.97237e24, "radius": 6371.0, "color": Color.BLUE, "sma": 1.00000261, "ecc": 0.01671123},
        "Mars": {"mass": 0.64171e24, "radius": 3389.5, "color": Color.RED, "sma": 1.523679, "ecc": 0.09340},
        "Jupiter": {"mass": 1898.19e24, "radius": 69911.0, "color": Color.ORANGE, "sma": 5.2044, "ecc": 0.0489},
        "Saturn": {"mass": 568.34e24, "radius": 58232.0, "color": Color(0.9, 0.8, 0.6), "sma": 9.5826, "ecc": 0.0565},
        "Uranus": {"mass": 86.813e24, "radius": 25362.0, "color": Color.CYAN, "sma": 19.2184, "ecc": 0.0457},
        "Neptune": {"mass": 102.413e24, "radius": 24622.0, "color": Color.BLUE, "sma": 30.110, "ecc": 0.0113}
    }
    
    var planet_scene = preload("res://celestial_bodies/CelestialBody.tscn")
    
    for planet_name in planet_data:
        var data = planet_data[planet_name]
        var planet = planet_scene.instantiate()
        
        planet.body_name = planet_name
        planet.mass_kg = data.mass
        planet.radius_km = data.radius
        planet.body_color = data.color
        planet.semi_major_axis_au = data.sma
        planet.eccentricity = data.ecc
        planet.central_body_name = "Sun"
        planet.display_radius = max(20, data.radius / 1000)  # Scale for visibility
        
        solar_system.add_child(planet)
        planet.add_to_group("celestial_bodies")
        
        # Create major moons for gas giants
        if planet_name == "Jupiter":
            create_jupiter_moons(planet)
        elif planet_name == "Earth":
            create_earth_moon(planet)
        elif planet_name == "Saturn":
            create_saturn_moons(planet)

func create_jupiter_moons(jupiter: CelestialBody):
    var moon_data = {
        "Io": {"mass": 0.089319e24, "radius": 1821.6, "sma": 0.002819, "color": Color.YELLOW},
        "Europa": {"mass": 0.04800e24, "radius": 1560.8, "sma": 0.004486, "color": Color(0.8, 0.8, 1.0)},
        "Ganymede": {"mass": 0.14819e24, "radius": 2634.1, "sma": 0.007155, "color": Color.GRAY},
        "Callisto": {"mass": 0.10759e24, "radius": 2410.3, "sma": 0.012585, "color": Color(0.4, 0.3, 0.2)}
    }
    
    create_moons(jupiter, moon_data)

func create_earth_moon(earth: CelestialBody):
    var moon_data = {
        "Moon": {"mass": 0.07346e24, "radius": 1737.4, "sma": 0.00257, "color": Color.LIGHT_GRAY}
    }
    
    create_moons(earth, moon_data)

func create_saturn_moons(saturn: CelestialBody):
    var moon_data = {
        "Titan": {"mass": 0.13452e24, "radius": 2574.7, "sma": 0.008168, "color": Color(0.9, 0.7, 0.4)}
    }
    
    create_moons(saturn, moon_data)

func create_moons(parent_planet: CelestialBody, moon_data: Dictionary):
    var moon_scene = preload("res://celestial_bodies/CelestialBody.tscn")
    
    for moon_name in moon_data:
        var data = moon_data[moon_name]
        var moon = moon_scene.instantiate()
        
        moon.body_name = moon_name
        moon.mass_kg = data.mass
        moon.radius_km = data.radius
        moon.body_color = data.color
        moon.semi_major_axis_au = data.sma
        moon.central_body_name = parent_planet.body_name
        moon.display_radius = max(10, data.radius / 200)
        
        solar_system.add_child(moon)
        moon.add_to_group("celestial_bodies")

func initialize_resources():
    var resource_scene = preload("res://resources/Resource.tscn")
    
    for i in range(ConfigManager.config.resource_count):
        var resource = resource_scene.instantiate()
        
        # Random position within world bounds
        var world_size = ConfigManager.config.world_size_au * ConfigManager.config.au_scale
        resource.global_position = Vector2(
            randf() * world_size,
            randf() * world_size
        )
        
        # Random resource properties
        resource.current_amount = randf_range(
            ConfigManager.config.resource_amount_range.x,
            ConfigManager.config.resource_amount_range.y
        )
        resource.max_amount = resource.current_amount
        resource.regeneration_rate = ConfigManager.config.resource_regen_rate
        
        # Random resource type
        var types = ["mineral", "energy", "rare_earth", "water"]
        resource.resource_type = types[randi() % types.size()]
        
        resource_manager.add_child(resource)
        resource.add_to_group("resources")
        
        # Connect signals
        resource.resource_depleted.connect(_on_resource_depleted)
        resource.resource_harvested.connect(_on_resource_harvested)

func setup_camera():
    camera.enabled = true
    camera.zoom = Vector2.ONE * 0.1  # Start zoomed out
    
    # Setup smooth camera following
    var camera_controller = preload("res://systems/CameraController.gd").new()
    camera.add_child(camera_controller)

func setup_ui():
    # Initialize UI panels with simulation data
    var hud = ui_system.get_node("HUD")
    var probe_list = ui_system.get_node("ProbeListPanel")
    var selected_probe = ui_system.get_node("SelectedProbePanel")
    var stats_panel = ui_system.get_node("SystemStatsPanel")
    
    # Connect UI signals
    if probe_list.has_signal("probe_selected"):
        probe_list.probe_selected.connect(_on_probe_selected)

func connect_system_signals():
    # Connect to various system signals for coordinated behavior
    pass

func start_new_episode():
    episode_count += 1
    current_step = 0
    total_resources_mined = 0.0
    simulation_start_time = Time.get_time_dict_from_system()["unix"]
    
    # Clear existing probes
    clear_all_probes()
    
    # Create initial probes
    create_initial_probes()
    
    # Reset simulation state
    simulation_running = true
    
    simulation_started.emit()
    print("Started episode ", episode_count)

func create_initial_probes():
    var probe_scene = preload("res://probes/Probe.tscn")
    
    for i in range(ConfigManager.config.initial_probes):
        var probe = probe_scene.instantiate()
        
        # Assign unique ID
        probe.probe_id = i + 1
        probe.generation = 0
        
        # Random starting position near world center
        var world_size = ConfigManager.config.world_size_au * ConfigManager.config.au_scale
        var center = Vector2(world_size / 2, world_size / 2)
        var offset = Vector2(randf_range(-1000, 1000), randf_range(-1000, 1000))
        probe.global_position = center + offset
        
        # Initialize with full energy
        probe.current_energy = ConfigManager.config.initial_energy
        probe.max_energy = ConfigManager.config.max_energy
        
        probe_manager.add_child(probe)
        probe.add_to_group("probes")
        
        # Connect probe signals
        connect_probe_signals(probe)
        
        print("Created probe ", probe.probe_id, " at ", probe.global_position)

func connect_probe_signals(probe: Probe):
    probe.probe_destroyed.connect(_on_probe_destroyed)
    probe.replication_requested.connect(_on_replication_requested)
    probe.resource_discovered.connect(_on_resource_discovered_by_probe)
    probe.communication_sent.connect(_on_communication_sent)

func clear_all_probes():
    for probe in get_tree().get_nodes_in_group("probes"):
        probe.queue_free()

func _physics_process(delta):
    if not simulation_running:
        return
    
    # Update simulation step
    current_step += 1
    
    # Check for episode end conditions
    check_episode_end_conditions()
    
    # Update performance metrics
    update_performance_metrics(delta)
    
    # Autosave periodically
    handle_autosave(delta)
    
    # Update UI with current state
    update_ui_data()

func check_episode_end_conditions():
    # Check maximum steps
    if current_step >= max_simulation_steps:
        end_episode("max_steps_reached")
        return
    
    # Check if all probes are dead
    var living_probes = get_tree().get_nodes_in_group("probes").filter(func(p): return p.is_alive)
    if living_probes.size() == 0:
        end_episode("all_probes_dead")
        return
    
    # Check for other termination conditions
    # (e.g., all resources depleted, specific objectives met)

func end_episode(reason: String):
    simulation_running = false
    
    var episode_stats = {
        "episode": episode_count,
        "steps": current_step,
        "reason": reason,
        "resources_mined": total_resources_mined,
        "final_probe_count": get_tree().get_nodes_in_group("probes").size(),
        "duration_seconds": Time.get_time_dict_from_system()["unix"] - simulation_start_time
    }
    
    print("Episode ", episode_count, " ended: ", reason)
    print("Stats: ", episode_stats)
    
    episode_completed.emit(episode_count, current_step)
    simulation_ended.emit()
    
    # Optionally start new episode automatically
    if auto_restart_episodes:
        call_deferred("start_new_episode")

func update_performance_metrics(delta):
    frame_time_accumulator += delta
    frame_count += 1
    
    if frame_time_accumulator >= 1.0:  # Update every second
        average_fps = frame_count / frame_time_accumulator
        frame_time_accumulator = 0.0
        frame_count = 0
        
        # Check for performance issues
        if average_fps < 30:
            print("Warning: Low FPS detected: ", average_fps)

func handle_autosave(delta):
    last_autosave += delta
    if last_autosave >= autosave_interval:
        last_autosave = 0.0
        autosave_simulation()

func autosave_simulation():
    var save_data = create_save_data()
    var save_path = "user://autosave_episode_" + str(episode_count) + ".tres"
    ResourceSaver.save(save_data, save_path)
    print("Autosaved to: ", save_path)

func create_save_data() -> SimulationSaveData:
    var save_data = SimulationSaveData.new()
    
    save_data.episode_count = episode_count
    save_data.current_step = current_step
    save_data.total_resources_mined = total_resources_mined
    save_data.simulation_running = simulation_running
    
    # Save probe data
    for probe in get_tree().get_nodes_in_group("probes"):
        var probe_data = ProbeData.new()
        probe_data.id = probe.probe_id
        probe_data.position = probe.global_position
        probe_data.velocity = probe.linear_velocity
        probe_data.energy = probe.current_energy
        probe_data.generation = probe.generation
        probe_data.is_alive = probe.is_alive
        save_data.probes.append(probe_data)
    
    # Save resource data
    for resource in get_tree().get_nodes_in_group("resources"):
        var resource_data = ResourceData.new()
        resource_data.position = resource.global_position
        resource_data.current_amount = resource.current_amount
        resource_data.max_amount = resource.max_amount
        resource_data.resource_type = resource.resource_type
        save_data.resources.append(resource_data)
    
    return save_data

func load_simulation(save_data: SimulationSaveData):
    # Clear current simulation
    clear_all_probes()
    
    # Restore simulation state
    episode_count = save_data.episode_count
    current_step = save_data.current_step
    total_resources_mined = save_data.total_resources_mined
    simulation_running = save_data.simulation_running
    
    # Restore probes
    var probe_scene = preload("res://probes/Probe.tscn")
    for probe_data in save_data.probes:
        var probe = probe_scene.instantiate()
        probe.probe_id = probe_data.id
        probe.global_position = probe_data.position
        probe.linear_velocity = probe_data.velocity
        probe.current_energy = probe_data.energy
        probe.generation = probe_data.generation
        probe.is_alive = probe_data.is_alive
        
        probe_manager.add_child(probe)
        probe.add_to_group("probes")
        connect_probe_signals(probe)
    
    # Update resources
    var resources = get_tree().get_nodes_in_group("resources")
    for i in range(min(resources.size(), save_data.resources.size())):
        var resource = resources[i]
        var resource_data = save_data.resources[i]
        resource.global_position = resource_data.position
        resource.current_amount = resource_data.current_amount
        resource.max_amount = resource_data.max_amount
        resource.resource_type = resource_data.resource_type
        resource.update_visual_state()

func update_ui_data():
    # Update UI elements with current simulation data
    var stats_panel = ui_system.get_node("SystemStatsPanel")
    if stats_panel.has_method("update_stats"):
        var stats = {
            "episode": episode_count,
            "step": current_step,
            "fps": average_fps,
            "probe_count": get_tree().get_nodes_in_group("probes").size(),
            "resources_mined": total_resources_mined,
            "active_resources": get_tree().get_nodes_in_group("resources").filter(func(r): return r.current_amount > 0).size()
        }
        stats_panel.update_stats(stats)

# Signal handlers
func _on_probe_destroyed(probe: Probe):
    print("Probe ", probe.probe_id, " destroyed")
    probe_count_changed.emit(get_tree().get_nodes_in_group("probes").size() - 1)

func _on_replication_requested(parent_probe: Probe):
    create_child_probe(parent_probe)

func create_child_probe(parent: Probe):
    var probe_scene = preload("res://probes/Probe.tscn")
    var child_probe = probe_scene.instantiate()
    
    # Generate new unique ID
    var existing_ids = []
    for probe in get_tree().get_nodes_in_group("probes"):
        existing_ids.append(probe.probe_id)
    
    var new_id = 1
    while new_id in existing_ids:
        new_id += 1
    
    # Configure child probe
    child_probe.probe_id = new_id
    child_probe.generation = parent.generation + 1
    child_probe.current_energy = ConfigManager.config.initial_energy
    child_probe.max_energy = ConfigManager.config.max_energy
    
    # Position near parent
    var offset = Vector2(randf_range(-100, 100), randf_range(-100, 100))
    child_probe.global_position = parent.global_position + offset
    
    probe_manager.add_child(child_probe)
    child_probe.add_to_group("probes")
    connect_probe_signals(child_probe)
    
    print("Probe ", parent.probe_id, " replicated. Created probe ", new_id, " (generation ", child_probe.generation, ")")
    probe_count_changed.emit(get_tree().get_nodes_in_group("probes").size())

func _on_resource_discovered_by_probe(probe: Probe, resource_position: Vector2, amount: float):
    print("Probe ", probe.probe_id, " discovered resource at ", resource_position, " with amount ", amount)

func _on_communication_sent(from_probe: Probe, to_position: Vector2, message_type: String):
    print("Probe ", from_probe.probe_id, " sent ", message_type, " to ", to_position)

func _on_resource_depleted(resource: Resource):
    print("Resource depleted at ", resource.global_position)

func _on_resource_harvested(resource: Resource, harvesting_probe: Probe, amount: float):
    total_resources_mined += amount
    print("Probe ", harvesting_probe.probe_id, " harvested ", amount, " from resource")

func _on_probe_selected(probe_id: int):
    # Handle probe selection for camera following and UI updates
    var selected_probe = null
    for probe in get_tree().get_nodes_in_group("probes"):
        if probe.probe_id == probe_id:
            selected_probe = probe
            break
    
    if selected_probe:
        camera.get_child(0).set_target(selected_probe)  # Assuming camera controller is first child

# Input handling
func _input(event):
    if event.is_action_pressed("pause_simulation"):
        toggle_simulation_pause()
    elif event.is_action_pressed("reset_simulation"):
        start_new_episode()
    elif event.is_action_pressed("save_simulation"):
        manual_save_simulation()
    elif event.is_action_pressed("load_simulation"):
        show_load_dialog()

func toggle_simulation_pause():
    simulation_running = !simulation_running
    if simulation_running:
        simulation_started.emit()
        print("Simulation resumed")
    else:
        simulation_paused.emit()
        print("Simulation paused")

func manual_save_simulation():
    var save_data = create_save_data()
    var save_path = "user://manual_save_" + str(Time.get_unix_time_from_system()) + ".tres"
    ResourceSaver.save(save_data, save_path)
    print("Manual save completed: ", save_path)

func show_load_dialog():
    # Implementation would show file dialog for loading saved simulations
    pass
```

## 6. Advanced UI System

### Modern UI Implementation
```gdscript
# ModernUI.gd
extends Control
class_name ModernUI

@onready var hud: Control = $HUD
@onready var probe_list_panel: Panel = $ProbeListPanel
@onready var selected_probe_panel: Panel = $SelectedProbePanel
@onready var system_stats_panel: Panel = $SystemStatsPanel
@onready var debug_panel: Panel = $DebugPanel

var selected_probe_id: int = -1
var probe_data_cache: Dictionary = {}
var animation_tween: Tween

signal probe_selected(probe_id: int)
signal simulation_speed_changed(new_speed: float)
signal ui_action_requested(action_type: String, data: Dictionary)

func _ready():
    setup_ui_panels()
    setup_animations()
    setup_input_handlers()

func setup_ui_panels():
    # Configure probe list panel
    setup_probe_list_panel()
    
    # Configure selected probe panel
    setup_selected_probe_panel()
    
    # Configure system stats panel
    setup_system_stats_panel()
    
    # Configure debug panel
    setup_debug_panel()

func setup_probe_list_panel():
    var scroll_container = ScrollContainer.new()
    var vbox = VBoxContainer.new()
    
    scroll_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    vbox.set_h_size_flags(Control.SIZE_EXPAND_FILL)
    
    probe_list_panel.add_child(scroll_container)
    scroll_container.add_child(vbox)
    
    # Style the panel
    var style_box = StyleBoxFlat.new()
    style_box.bg_color = Color(0.1, 0.15, 0.2, 0.9)
    style_box.border_width_left = 2
    style_box.border_width_right = 2
    style_box.border_width_top = 2
    style_box.border_width_bottom = 2
    style_box.border_color = Color(0.3, 0.5, 0.8, 0.8)
    style_box.corner_radius_top_left = 8
    style_box.corner_radius_top_right = 8
    style_box.corner_radius_bottom_left = 8
    style_box.corner_radius_bottom_right = 8
    
    probe_list_panel.add_theme_stylebox_override("panel", style_box)

func setup_selected_probe_panel():
    var vbox = VBoxContainer.new()
    vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    vbox.add_theme_constant_override("separation", 10)
    
    # Probe info section
    var info_section = create_info_section("Probe Information")
    vbox.add_child(info_section)
    
    # Energy display
    var energy_section = create_energy_display()
    vbox.add_child(energy_section)
    
    # Action controls
    var control_section = create_probe_controls()
    vbox.add_child(control_section)
    
    selected_probe_panel.add_child(vbox)

func create_info_section(title: String) -> VBoxContainer:
    var section = VBoxContainer.new()
    
    # Title label
    var title_label = Label.new()
    title_label.text = title
    title_label.add_theme_font_size_override("font_size", 18)
    title_label.add_theme_color_override("font_color", Color.WHITE)
    section.add_child(title_label)
    
    # Info container
    var info_container = VBoxContainer.new()
    info_container.name = "InfoContainer"
    section.add_child(info_container)
    
    return section

func create_energy_display() -> Control:
    var container = HBoxContainer.new()
    
    # Energy bar
    var energy_bar = ProgressBar.new()
    energy_bar.name = "EnergyBar"
    energy_bar.max_value = 100
    energy_bar.value = 90
    energy_bar.set_h_size_flags(Control.SIZE_EXPAND_FILL)
    
    # Style the progress bar
    var bar_style = StyleBoxFlat.new()
    bar_style.bg_color = Color.GREEN
    bar_style.corner_radius_top_left = 4
    bar_style.corner_radius_top_right = 4
    bar_style.corner_radius_bottom_left = 4
    bar_style.corner_radius_bottom_right = 4
    energy_bar.add_theme_stylebox_override("fill", bar_style)
    
    var bg_style = StyleBoxFlat.new()
    bg_style.bg_color = Color(0.2, 0.2, 0.2)
    bg_style.corner_radius_top_left = 4
    bg_style.corner_radius_top_right = 4
    bg_style.corner_radius_bottom_left = 4
    bg_style.corner_radius_bottom_right = 4
    energy_bar.add_theme_stylebox_override("background", bg_style)
    
    # Energy label
    var energy_label = Label.new()
    energy_label.name = "EnergyLabel"
    energy_label.text = "90000 / 100000"
    energy_label.add_theme_color_override("font_color", Color.WHITE)
    
    container.add_child(energy_bar)
    container.add_child(energy_label)
    
    return container

func create_probe_controls() -> VBoxContainer:
    var controls = VBoxContainer.new()
    controls.add_theme_constant_override("separation", 5)
    
    # Manual control buttons
    var button_container = HBoxContainer.new()
    
    var thrust_button = Button.new()
    thrust_button.text = "Thrust"
    thrust_button.name = "ThrustButton"
    thrust_button.pressed.connect(_on_manual_thrust_pressed)
    
    var rotate_left_button = Button.new()
    rotate_left_button.text = "◄"
    rotate_left_button.name = "RotateLeftButton"
    rotate_left_button.pressed.connect(_on_rotate_left_pressed)
    
    var rotate_right_button = Button.new()
    rotate_right_button.text = "►"
    rotate_right_button.name = "RotateRightButton"
    rotate_right_button.pressed.connect(_on_rotate_right_pressed)
    
    var replicate_button = Button.new()
    replicate_button.text = "Replicate"
    replicate_button.name = "ReplicateButton"
    replicate_button.pressed.connect(_on_replicate_pressed)
    
    button_container.add_child(thrust_button)
    button_container.add_child(rotate_left_button)
    button_container.add_child(rotate_right_button)
    button_container.add_child(replicate_button)
    
    controls.add_child(button_container)
    
    # AI control toggle
    var ai_toggle = CheckBox.new()
    ai_toggle.text = "AI Control Enabled"
    ai_toggle.name = "AIToggle"
    ai_toggle.button_pressed = true
    ai_toggle.toggled.connect(_on_ai_toggle_changed)
    
    controls.add_child(ai_toggle)
    
    return controls

func setup_system_stats_panel():
    var vbox = VBoxContainer.new()
    vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    vbox.add_theme_constant_override("separation", 8)
    
    # Title
    var title = Label.new()
    title.text = "System Statistics"
    title.add_theme_font_size_override("font_size", 16)
    title.add_theme_color_override("font_color", Color.WHITE)
    vbox.add_child(title)
    
    # Stats container
    var stats_container = VBoxContainer.new()
    stats_container.name = "StatsContainer"
    vbox.add_child(stats_container)
    
    system_stats_panel.add_child(vbox)

func setup_debug_panel():
    if not ConfigManager.config.debug_mode:
        debug_panel.visible = false
        return
    
    var vbox = VBoxContainer.new()
    vbox.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
    
    # Debug controls
    var debug_controls = create_debug_controls()
    vbox.add_child(debug_controls)
    
    # Performance metrics
    var perf_metrics = create_performance_display()
    vbox.add_child(perf_metrics)
    
    debug_panel.add_child(vbox)

func create_debug_controls() -> VBoxContainer:
    var controls = VBoxContainer.new()
    
    # Speed control
    var speed_container = HBoxContainer.new()
    var speed_label = Label.new()
    speed_label.text = "Simulation Speed:"
    var speed_slider = HSlider.new()
    speed_slider.name = "SpeedSlider"
    speed_slider.min_value = 0.1
    speed_slider.max_value = 5.0
    speed_slider.value = 1.0
    speed_slider.step = 0.1
    speed_slider.value_changed.connect(_on_speed_changed)
    
    speed_container.add_child(speed_label)
    speed_container.add_child(speed_slider)
    controls.add_child(speed_container)
    
    # Debug buttons
    var button_container = HBoxContainer.new()
    
    var pause_button = Button.new()
    pause_button.text = "Pause/Resume"
    pause_button.pressed.connect(_on_pause_pressed)
    
    var reset_button = Button.new()
    reset_button.text = "Reset Episode"
    reset_button.pressed.connect(_on_reset_pressed)
    
    var save_button = Button.new()
    save_button.text = "Quick Save"
    save_button.pressed.connect(_on_save_pressed)
    
    button_container.add_child(pause_button)
    button_container.add_child(reset_button)
    button_container.add_child(save_button)
    controls.add_child(button_container)
    
    return controls

func create_performance_display() -> VBoxContainer:
    var perf_display = VBoxContainer.new()
    perf_display.name = "PerformanceDisplay"
    
    var title = Label.new()
    title.text = "Performance Metrics"
    title.add_theme_font_size_override("font_size", 14)
    perf_display.add_child(title)
    
    var metrics_container = VBoxContainer.new()
    metrics_container.name = "MetricsContainer"
    perf_display.add_child(metrics_container)
    
    return perf_display

func setup_animations():
    animation_tween = create_tween()
    animation_tween.set_loops()
    
    # Animate panel appearances
    animate_panel_glow()

func animate_panel_glow():
    # Add subtle glow animation to active panels
    var panels = [probe_list_panel, selected_probe_panel, system_stats_panel]
    
    for panel in panels:
        var style_box = panel.get_theme_stylebox("panel")
        if style_box is StyleBoxFlat:
            var original_color = style_box.border_color
            animation_tween.parallel().tween_method(
                func(color): style_box.border_color = color,
                original_color,
                original_color * 1.3,
                2.0
            )
            animation_tween.parallel().tween_method(
                func(color): style_box.border_color = color,
                original_color * 1.3,
                original_color,
                2.0
            )

func setup_input_handlers():
    # Setup keyboard shortcuts
    set_process_input(true)

func _input(event):
    if event.is_action_pressed("toggle_ui"):
        toggle_ui_visibility()
    elif event.is_action_pressed("focus_next_probe"):
        focus_next_probe()
    elif event.is_action_pressed("toggle_debug_panel"):
        debug_panel.visible = !debug_panel.visible

func update_ui_data(simulation_data: Dictionary):
    update_probe_list(simulation_data.get("probes", {}))
    update_selected_probe_info(simulation_data.get("selected_probe"))
    update_system_stats(simulation_data.get("stats", {}))
    update_debug_info(simulation_data.get("debug_info", {}))

func update_probe_list(probes_data: Dictionary):
    var container = probe_list_panel.get_node("ScrollContainer/VBoxContainer")
    
    # Clear existing items
    for child in container.get_children():
        child.queue_free()
    
    # Add probe items
    for probe_id in probes_data:
        var probe_data = probes_data[probe_id]
        var probe_item = create_probe_list_item(probe_id, probe_data)
        container.add_child(probe_item)

func create_probe_list_item(probe_id: int, probe_data: Dictionary) -> Control:
    var item_container = HBoxContainer.new()
    item_container.set_h_size_flags(Control.SIZE_EXPAND_FILL)
    
    # Probe info
    var info_vbox = VBoxContainer.new()
    info_vbox.set_h_size_flags(Control.SIZE_EXPAND_FILL)
    
    var name_label = Label.new()
    name_label.text = "Probe " + str(probe_id)
    name_label.add_theme_color_override("font_color", Color.WHITE)
    
    var status_label = Label.new()
    var energy_ratio = probe_data.get("energy", 0) / probe_data.get("max_energy", 1)
    status_label.text = "Energy: " + str(int(energy_ratio * 100)) + "%"
    
    if energy_ratio > 0.7:
        status_label.add_theme_color_override("font_color", Color.GREEN)
    elif energy_ratio > 0.3:
        status_label.add_theme_color_override("font_color", Color.YELLOW)
    else:
        status_label.add_theme_color_override("font_color", Color.RED)
    
    info_vbox.add_child(name_label)
    info_vbox.add_child(status_label)
    
    # Select button
    var select_button = Button.new()
    select_button.text = "Select"
    select_button.pressed.connect(_on_probe_selected.bind(probe_id))
    
    # Status indicator
    var status_indicator = ColorRect.new()
    status_indicator.size = Vector2(20, 20)
    if probe_data.get("is_alive", false):
        status_indicator.color = Color.GREEN if energy_ratio > 0.3 else Color.YELLOW
    else:
        status_indicator.color = Color.RED
    
    item_container.add_child(status_indicator)
    item_container.add_child(info_vbox)
    item_container.add_child(select_button)
    
    # Style for selection highlight
    if probe_id == selected_probe_id:
        var highlight_style = StyleBoxFlat.new()
        highlight_style.bg_color = Color(0.3, 0.5, 0.8, 0.3)
        item_container.add_theme_stylebox_override("panel", highlight_style)
    
    return item_container

func update_selected_probe_info(probe_data):
    if not probe_data:
        selected_probe_panel.visible = false
        return
    
    selected_probe_panel.visible = true
    
    # Update info section
    var info_container = selected_probe_panel.get_node("VBoxContainer/InfoContainer")
    update_probe_info_display(info_container, probe_data)
    
    # Update energy display
    var energy_bar = selected_probe_panel.get_node("VBoxContainer/EnergyBar")
    var energy_label = selected_probe_panel.get_node("VBoxContainer/EnergyLabel")
    
    if energy_bar and energy_label:
        var energy_ratio = probe_data.energy / probe_data.max_energy
        energy_bar.value = energy_ratio * 100
        energy_label.text = str(int(probe_data.energy)) + " / " + str(int(probe_data.max_energy))
        
        # Update energy bar color
        var bar_style = energy_bar.get_theme_stylebox("fill")
        if bar_style is StyleBoxFlat:
            if energy_ratio > 0.7:
                bar_style.bg_color = Color.GREEN
            elif energy_ratio > 0.3:
                bar_style.bg_color = Color.YELLOW
            else:
                bar_style.bg_color = Color.RED

func update_probe_info_display(container: Control, probe_data: Dictionary):
    # Clear existing info
    for child in container.get_children():
        child.queue_free()
    
    # Add probe information
    var info_items = [
        ["ID", str(probe_data.get("id", "Unknown"))],
        ["Generation", str(probe_data.get("generation", 0))],
        ["Position", "(" + str(int(probe_data.get("position", Vector2.ZERO).x)) + ", " + str(int(probe_data.get("position", Vector2.ZERO).y)) + ")"],
        ["Velocity", str(probe_data.get("velocity", Vector2.ZERO).length()).pad_decimals(1) + " u/s"],
        ["Task", probe_data.get("current_task", "Idle")],
        ["Target", str(probe_data.get("current_target_id", "None"))],
        ["Status", "Alive" if probe_data.get("is_alive", false) else "Dead"]
    ]
    
    for item in info_items:
        var info_line = HBoxContainer.new()
        
        var key_label = Label.new()
        key_label.text = item[0] + ":"
        key_label.set_custom_minimum_size(Vector2(80, 0))
        key_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
        
        var value_label = Label.new()
        value_label.text = item[1]
        value_label.add_theme_color_override("font_color", Color.WHITE)
        
        info_line.add_child(key_label)
        info_line.add_child(value_label)
        container.add_child(info_line)

func update_system_stats(stats_data: Dictionary):
    var stats_container = system_stats_panel.get_node("VBoxContainer/StatsContainer")
    
    # Clear existing stats
    for child in stats_container.get_children():
        child.queue_free()
    
    # Add statistics
    var stat_items = [
        ["Episode", str(stats_data.get("episode", 0))],
        ["Step", str(stats_data.get("step", 0))],
        ["FPS", str(stats_data.get("fps", 60)).pad_decimals(1)],
        ["Active Probes", str(stats_data.get("probe_count", 0))],
        ["Resources Mined", str(stats_data.get("resources_mined", 0)).pad_decimals(1)],
        ["Active Resources", str(stats_data.get("active_resources", 0))],
        ["Simulation Speed", str(stats_data.get("sim_speed", 1.0)) + "x"]
    ]
    
    for item in stat_items:
        var stat_line = create_stat_line(item[0], item[1])
        stats_container.add_child(stat_line)

func create_stat_line(key: String, value: String) -> Control:
    var line = HBoxContainer.new()
    
    var key_label = Label.new()
    key_label.text = key + ":"
    key_label.set_custom_minimum_size(Vector2(100, 0))
    key_label.add_theme_color_override("font_color", Color.LIGHT_GRAY)
    
    var value_label = Label.new()
    value_label.text = value
    value_label.add_theme_color_override("font_color", Color.WHITE)
    
    line.add_child(key_label)
    line.add_child(value_label)
    
    return line

func update_debug_info(debug_data: Dictionary):
    if not debug_panel.visible:
        return
    
    var metrics_container = debug_panel.get_node("VBoxContainer/PerformanceDisplay/MetricsContainer")
    if not metrics_container:
        return
    
    # Clear existing metrics
    for child in metrics_container.get_children():
        child.queue_free()
    
    # Add performance metrics
    var metrics = [
        ["Memory Usage", str(debug_data.get("memory_mb", 0)) + " MB"],
        ["Physics Time", str(debug_data.get("physics_time_ms", 0)) + " ms"],
        ["Render Time", str(debug_data.get("render_time_ms", 0)) + " ms"],
        ["AI Update Time", str(debug_data.get("ai_time_ms", 0)) + " ms"],
        ["Particle Count", str(debug_data.get("particle_count", 0))],
        ["Node Count", str(debug_data.get("node_count", 0))]
    ]
    
    for metric in metrics:
        var metric_line = create_stat_line(metric[0], metric[1])
        metrics_container.add_child(metric_line)

func toggle_ui_visibility():
    var panels = [probe_list_panel, selected_probe_panel, system_stats_panel]
    var target_alpha = 0.0 if panels[0].modulate.a > 0.5 else 1.0
    
    var tween = create_tween()
    tween.set_parallel(true)
    
    for panel in panels:
        tween.tween_property(panel, "modulate:a", target_alpha, 0.3)

func focus_next_probe():
    # Cycle through available probes
    var probe_ids = probe_data_cache.keys()
    if probe_ids.is_empty():
        return
    
    probe_ids.sort()
    var current_index = probe_ids.find(selected_probe_id)
    var next_index = (current_index + 1) % probe_ids.size()
    
    selected_probe_id = probe_ids[next_index]
    probe_selected.emit(selected_probe_id)

# Signal handlers
func _on_probe_selected(probe_id: int):
    selected_probe_id = probe_id
    probe_selected.emit(probe_id)

func _on_manual_thrust_pressed():
    if selected_probe_id >= 0:
        ui_action_requested.emit("manual_thrust", {"probe_id": selected_probe_id})

func _on_rotate_left_pressed():
    if selected_probe_id >= 0:
        ui_action_requested.emit("manual_rotate", {"probe_id": selected_probe_id, "direction": "left"})

func _on_rotate_right_pressed():
    if selected_probe_id >= 0:
        ui_action_requested.emit("manual_rotate", {"probe_id": selected_probe_id, "direction": "right"})

func _on_replicate_pressed():
    if selected_probe_id >= 0:
        ui_action_requested.emit("manual_replicate", {"probe_id": selected_probe_id})

func _on_ai_toggle_changed(enabled: bool):
    if selected_probe_id >= 0:
        ui_action_requested.emit("toggle_ai", {"probe_id": selected_probe_id, "enabled": enabled})

func _on_speed_changed(new_speed: float):
    simulation_speed_changed.emit(new_speed)

func _on_pause_pressed():
    ui_action_requested.emit("toggle_pause", {})

func _on_reset_pressed():
    ui_action_requested.emit("reset_episode", {})

func _on_save_pressed():
    ui_action_requested.emit("quick_save", {})
```

## 7. Enhanced Visual Effects & Shaders

### Advanced Particle Effects
```gdscript
# AdvancedParticleManager.gd
extends Node2D
class_name AdvancedParticleManager

var particle_pools: Dictionary = {}
var active_effects: Array[ParticleEffect] = []

func _ready():
    # Pre-create particle pools for performance
    create_particle_pools()

func create_particle_pools():
    var pool_configs = {
        "thruster_exhaust": {"count": 50, "scene": preload("res://effects/ThrusterExhaust.tscn")},
        "mining_sparks": {"count": 20, "scene": preload("res://effects/MiningSparks.tscn")},
        "communication_pulse": {"count": 10, "scene": preload("res://effects/CommunicationPulse.tscn")},
        "energy_field": {"count": 15, "scene": preload("res://effects/EnergyField.tscn")},
        "explosion": {"count": 5, "scene": preload("res://effects/Explosion.tscn")}
    }
    
    for effect_type in pool_configs:
        var config = pool_configs[effect_type]
        particle_pools[effect_type] = []
        
        for i in range(config.count):
            var effect = config.scene.instantiate()
            effect.visible = false
            add_child(effect)
            particle_pools[effect_type].append(effect)

func get_effect(effect_type: String) -> ParticleEffect:
    if not particle_pools.has(effect_type):
        push_error("Unknown particle effect type: " + effect_type)
        return null
    
    var pool = particle_pools[effect_type]
    for effect in pool:
        if not effect.is_active():
            return effect
    
    # Pool exhausted, create new effect
    push_warning("Particle pool exhausted for type: " + effect_type)
    return null

func create_thruster_effect(position: Vector2, direction: Vector2, intensity: float):
    var effect = get_effect("thruster_exhaust")
    if effect:
        effect.setup_thruster_effect(position, direction, intensity)
        active_effects.append(effect)

func create_mining_effect(start_pos: Vector2, target_pos: Vector2, intensity: float):
    var effect = get_effect("mining_sparks")
    if effect:
        effect.setup_mining_effect(start_pos, target_pos, intensity)
        active_effects.append(effect)

func create_communication_effect(start_pos: Vector2, end_pos: Vector2):
    var effect = get_effect("communication_pulse")
    if effect:
        effect.setup_communication_effect(start_pos, end_pos)
        active_effects.append(effect)

func _process(_delta):
    # Clean up finished effects
    for i in range(active_effects.size() - 1, -1, -1):
        var effect = active_effects[i]
        if not effect.is_active():
            active_effects.remove_at(i)
```

### Custom Shaders
Create shader files for enhanced visual effects:

**ThrusterExhaust.gdshader:**
```glsl
shader_type canvas_item;

uniform float intensity : hint_range(0.0, 2.0) = 1.0;
uniform vec3 flame_color : source_color = vec3(0.2, 0.8, 1.0);
uniform float temperature : hint_range(1000.0, 4000.0) = 3000.0;
uniform float time_scale : hint_range(0.1, 5.0) = 2.0;

varying vec2 world_position;

vec3 temperature_to_color(float temp) {
    // Blackbody radiation approximation
    if (temp < 2500.0) {
        return vec3(1.0, 0.4, 0.1); // Red-orange
    } else if (temp < 3500.0) {
        return vec3(1.0, 0.8, 0.3); // Yellow-white
    } else {
        return vec3(0.8, 0.9, 1.0); // Blue-white
    }
}

void fragment() {
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);
    
    // Create turbulent flame effect
    float noise1 = sin(UV.x * 10.0 + TIME * time_scale) * 0.1;
    float noise2 = cos(UV.y * 8.0 + TIME * time_scale * 0.7) * 0.1;
    float turbulence = noise1 + noise2;
    
    // Flame shape with turbulence
    float flame_mask = 1.0 - smoothstep(0.2, 0.5, dist + turbulence);
    flame_mask *= intensity;
    
    // Temperature-based color
    vec3 color = temperature_to_color(temperature);
    color = mix(color, flame_color, 0.3);
    
    // Add intensity variation
    float intensity_var = 0.8 + 0.2 * sin(TIME * time_scale * 3.0);
    color *= intensity_var;
    
    COLOR = vec4(color, flame_mask * intensity);
}
```

**PlanetAtmosphere.gdshader:**
```glsl
shader_type canvas_item;

uniform vec3 atmosphere_color : source_color = vec3(0.4, 0.7, 1.0);
uniform float atmosphere_thickness : hint_range(0.0, 0.5) = 0.1;
uniform float glow_intensity : hint_range(0.0, 2.0) = 1.0;
uniform float rotation_speed : hint_range(0.0, 2.0) = 0.1;

void fragment() {
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);
    
    // Rotating atmosphere effect
    float angle = atan(UV.y - center.y, UV.x - center.x) + TIME * rotation_speed;
    float atmosphere_noise = sin(angle * 8.0) * 0.02 + cos(angle * 12.0) * 0.01;
    
    // Atmospheric glow
    float atmosphere_mask = 1.0 - smoothstep(0.45, 0.5 + atmosphere_thickness, dist + atmosphere_noise);
    float glow_mask = 1.0 - smoothstep(0.4, 0.6 + atmosphere_thickness, dist);
    
    // Limb darkening effect
    float limb_darkening = 1.0 - pow(dist / 0.5, 0.5);
    
    vec3 final_color = atmosphere_color * glow_intensity * limb_darkening;
    float alpha = (atmosphere_mask + glow_mask * 0.3) * glow_intensity;
    
    COLOR = vec4(final_color, alpha);
}
```

**EnergyField.gdshader:**
```glsl
shader_type canvas_item;

uniform float field_strength : hint_range(0.0, 2.0) = 1.0;
uniform vec3 field_color : source_color = vec3(0.2, 1.0, 0.8);
uniform float pulse_speed : hint_range(0.1, 5.0) = 2.0;
uniform int wave_count : hint_range(3, 10) = 6;

void fragment() {
    vec2 center = vec2(0.5, 0.5);
    float dist = distance(UV, center);
    float angle = atan(UV.y - center.y, UV.x - center.x);
    
    // Create energy waves
    float waves = 0.0;
    for (int i = 0; i < wave_count; i++) {
        float wave_phase = float(i) * 2.0 / float(wave_count);
        waves += sin(dist * 20.0 + TIME * pulse_speed + wave_phase) * 0.5;
    }
    waves = (waves + float(wave_count) * 0.5) / float(wave_count);
    
    // Radial pulse
    float pulse = sin(dist * 15.0 - TIME * pulse_speed * 2.0) * 0.5 + 0.5;
    
    // Combine effects
    float intensity = waves * pulse * field_strength;
    intensity *= 1.0 - smoothstep(0.0, 0.5, dist); // Fade at edges
    
    // Color variation
    vec3 color = field_color;
    color.r += sin(angle * 3.0 + TIME) * 0.1;
    color.g += cos(angle * 4.0 + TIME * 1.3) * 0.1;
    color.b += sin(angle * 5.0 + TIME * 0.7) * 0.1;
    
    COLOR = vec4(color, intensity);
}
```

## 8. Audio System Implementation

### 3D Positional Audio Manager
```gdscript
# AudioManager.gd (AutoLoad)
extends Node

var audio_pools: Dictionary = {}
var active_audio_sources: Array[AudioStreamPlayer2D] = []
var master_volume: float = 1.0
var sfx_volume: float = 1.0
var ambient_volume: float = 0.7

func _ready():
    # Create audio pools for common sounds
    create_audio_pools()
    
    # Load settings
    load_audio_settings()

func create_audio_pools():
    var sound_configs = {
        "thruster": {"file": "res://audio/thruster_loop.ogg", "count": 20},
        "mining_laser": {"file": "res://audio/mining_laser.ogg", "count": 10},
        "communication": {"file": "res://audio/comm