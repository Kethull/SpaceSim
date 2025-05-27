extends Resource
class_name SimulationSaveData

@export var save_version: String = "1.0"
@export var save_timestamp: float = 0.0 # Changed to float
@export var current_episode: int = 0 # Renamed from episode_count for consistency with SaveLoadManager
@export var current_step: int = 0
@export var total_resources_mined: float = 0.0 # Note: This is also tracked in SimulationManager, ensure consistency or decide source of truth.
@export var simulation_running: bool = false

# Preload known data types
const ResourceData = preload("res://scripts/data/ResourceData.gd")
# Placeholder for other data types until they are created:
# const ProbeData = preload("res://scripts/data/ProbeData.gd")
# const CelestialBodyData = preload("res://scripts/data/CelestialBodyData.gd")
# const MessageData = preload("res://scripts/data/MessageData.gd") # MessageData has class_name

# Ensure these use the specific class names if available and error-free
const ProbeDataRes = preload("res://scripts/data/ProbeData.gd")
const CelestialBodyDataRes = preload("res://scripts/data/CelestialBodyData.gd")
const MessageDataRes = preload("res://scripts/data/MessageData.gd")
# ResourceData has class_name ResourceData, should be fine

@export var probes: Array[ProbeDataRes] = []
@export var resources: Array[ResourceData] = [] # ResourceData has class_name
@export var celestial_bodies: Array[CelestialBodyDataRes] = []
@export var communication_log: Array[MessageDataRes] = []

@export var camera_position: Vector2 = Vector2.ZERO
@export var camera_zoom: Vector2 = Vector2.ONE # Zoom is a Vector2
@export var selected_probe_id: String = "" # Selected probe ID is likely a string

@export var performance_stats: Dictionary = {} # Keep if used

# Added to store SimulationManager's specific stats as discussed
# @export var sim_mgr_stats: Dictionary = {} # This might be redundant if basic sim info covers it

# Added from prompt for SaveLoadManager
@export var save_name: String = ""