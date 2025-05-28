# Resource.gd
extends Area2D
class_name GameResource

# @export_group("Resource Properties")
# @export var resource_type: String = "mineral"
# @export var max_amount: float = 20000.0

# # const HarvestEffectScene = preload("res://effects/HarvestEffect.tscn") # Temporarily commented out
# # const DiscoveryEffectScene = preload("res://effects/DiscoveryEffect.tscn") # Temporarily commented out

# # Placeholder audio paths - ensure these files exist in res://audio/
# const DISCOVERY_SOUND_PATH = "res://audio/discovery_chime.ogg"
# const HARVEST_SOUND_PATH = "res://audio/mining_laser.ogg"
# @export var current_amount: float = 20000.0 # This line is now effectively active
# @export var regeneration_rate: float = 0.0
# @export var harvest_difficulty: float = 1.0

# @onready var resource_sprite: Sprite2D = $ResourceSprite
# @onready var glow_effect: Sprite2D = $GlowEffect
# @onready var amount_label: Label = $AmountLabel
# @onready var particle_effect: GPUParticles2D = $ParticleEffect
# @onready var audio_component: AudioStreamPlayer2D = $AudioComponent
# @onready var collection_area: CollisionShape2D = $CollectionShape

# var discovered_by: Array[int] = []  # Probe IDs that discovered this resource # This line is now effectively active
# var being_harvested_by: Array = [] # Array[Probe] - Godot 4.x type hint
# var glow_tween: Tween
# var _loaded_harvest_sound: AudioStream = null

# signal resource_depleted(resource: GameResource) # This line is now effectively active
# signal resource_discovered(resource: GameResource, discovering_probe: Node) # This line is now effectively active
# signal resource_harvested(resource: GameResource, harvesting_probe: Node, amount: float) # Probe class might not be defined yet, use Node

# var _config = null # Cache for ConfigManager.config

# Actual class members needed
var current_amount: float = 20000.0 
var discovered_by: Array = [] # Array of probe IDs
var max_amount: float = 0.0
var resource_type: String = "unknown"
var regeneration_rate: float = 0.0

signal resource_depleted(resource: Node)
signal resource_discovered(resource: Node, discovering_probe: Node)


func _ready():
    pass
    # var config_manager_node = get_node_or_null("/root/ConfigManager")
    # if config_manager_node and (config_manager_node.has_method("get_config") or config_manager_node.has("config")):
    #     _config = config_manager_node.config if config_manager_node.has("config") else config_manager_node.get_config()
    # else:
    #     printerr("Resource.gd: ConfigManager or its config not found.")

    # Configure collision detection
    set_collision_layer_value(3, true)  # Resources layer
    set_collision_mask_value(2, true)   # Detect probes
    
    # Add to groups
    add_to_group("resources")

    # Preload sounds
    # if ResourceLoader.exists(HARVEST_SOUND_PATH):
    #     _loaded_harvest_sound = load(HARVEST_SOUND_PATH)
    # else:
    #     printerr("Resource.gd: Harvest sound not found at %s" % HARVEST_SOUND_PATH)
            
    # Setup visual appearance
    # setup_visual_appearance()
    
    # Setup particle effects
    # setup_particle_effects()
    
    # Connect signals
    body_entered.connect(_on_body_entered)
    body_exited.connect(_on_body_exited)
    
    # Start glow animation
    # start_glow_animation()

# func setup_visual_appearance():
    # pass # Temporarily pass

# func setup_particle_effects():
    # pass # Temporarily pass

# func start_glow_animation():
    # pass # Temporarily pass

# func update_glow_intensity(intensity: float):
    # pass # Temporarily pass

# func _physics_process(delta):
    # pass # Temporarily pass

# func process_harvesting(delta):
    # pass # Temporarily pass

func harvest(amount: float) -> float:
    var harvested_amount = min(amount, current_amount)
    current_amount -= harvested_amount
    
    var audio_manager = get_node_or_null("/root/AudioManager")
    if audio_manager and harvested_amount > 0:
        # Play harvest sound at the resource's location
        # Consider if this sound should be played by the probe instead, if it's a laser sound.
        # For now, playing it at the resource as a generic "being harvested" sound.
        audio_manager.play_sound_at_position("mining_laser", global_position) # Assuming "mining_laser" is a suitable sound
        
    if current_amount <= 0:
        resource_depleted.emit(self)
        # Optionally queue_free() or hide if it doesn't regenerate
    
    # update_visual_state() # Uncomment if you have this method
    return harvested_amount

# func update_visual_state():
    # pass # Temporarily pass

# func create_harvest_effect(harvesting_probe: Node): # Probe class might not be defined yet
    # pass # Temporarily pass

func discover(discovering_probe: Node): # Probe class might not be defined yet
    if discovering_probe and discovering_probe.has_method("get_id"):
        var probe_id_val = discovering_probe.get_id() # Assuming get_id() returns a type suitable for Array.has()
        var already_discovered = false
        for id_in_list in discovered_by: # Check if probe_id_val is already in the list
            if id_in_list == probe_id_val:
                already_discovered = true
                break
        
        if not already_discovered:
            discovered_by.append(probe_id_val)
            resource_discovered.emit(self, discovering_probe)
            # print_debug("Resource %s discovered by probe %s" % [name, probe_id_val])
            
            var audio_manager = get_node_or_null("/root/AudioManager")
            if audio_manager:
                audio_manager.play_sound_at_position("discovery", global_position)
            
            # create_discovery_effect() # Uncomment if you have this method
    # else:
        # printerr("Resource %s: discover() called with invalid probe." % name)


func get_resource_data() -> Dictionary:
    return {
        "type": resource_type,
        "amount": current_amount,
        "type_id": get_resource_type_id(),
        "max_amount": max_amount
    }

func get_resource_type_id() -> int:
    match resource_type:
        "mineral": return 0
        "energy": return 1
        "rare_earth": return 2
        "water": return 3
        _: return 0 # Default or handle error appropriately

func get_current_amount() -> float:
    return current_amount

func _on_body_entered(body):
    pass # Temporarily pass

func _on_body_exited(body):
    pass # Temporarily pass

# func _notification(what):
    # pass # Temporarily pass