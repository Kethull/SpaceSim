extends Resource
class_name ProbeData

## General Info
@export var probe_id: String = ""
@export var generation: int = 0
@export var unique_id: String = "" # Persists across save/load, different from scene node name

## State
@export var global_transform: Transform2D = Transform2D.IDENTITY
@export var linear_velocity: Vector2 = Vector2.ZERO
@export var angular_velocity: float = 0.0
@export var energy: float = 100.0
@export var status: String = "idle" # e.g., "idle", "moving", "mining", "replicating", "communicating"
@export var current_task: String = "" # More specific task, e.g., "move_to_target", "mine_resource_X"
@export var target_celestial_body_name: String = "" # Name of the target celestial body
@export var target_resource_id: String = "" # ID of the target resource
@export var target_probe_id: String = "" # ID of the target probe for communication/replication
@export var target_position: Vector2 = Vector2.ZERO # General target position if not a specific entity

## Trail
@export var trail_points: PackedVector2Array = []

## AI State (Simplified for now, expand as needed)
@export var ai_state_variables: Dictionary = {} # For general AI state like last_action, current_observation
# For Q-learning, q_table can be large. Consider if it's always saved or re-learned.
# @export var q_table: Dictionary = {} # Example: { "state_hash": { "action1": q_value, ... } }

## Communication & Knowledge
@export var known_resource_locations: Dictionary = {} # { "resource_id": Vector2(position) }
@export var known_probe_locations: Dictionary = {} # { "probe_id": Vector2(position) }
@export var message_buffer: Array[MessageData] = [] # For messages this probe is holding

func _init(p_id: String = "", gen: int = 0, p_uid: String = ""):
	var rng := RandomNumberGenerator.new()
	rng.randomize() # Ensure it's seeded
	probe_id = p_id
	generation = gen
	unique_id = p_uid if p_uid != "" else str(Time.get_ticks_usec()) + "_" + str(rng.randi_range(1000, 9999))

func to_dict() -> Dictionary:
	return {
		"probe_id": probe_id,
		"generation": generation,
		"unique_id": unique_id,
		"global_transform_origin_x": global_transform.origin.x,
		"global_transform_origin_y": global_transform.origin.y,
		"global_transform_rotation": global_transform.get_rotation(),
		"global_transform_scale_x": global_transform.get_scale().x,
		"global_transform_scale_y": global_transform.get_scale().y,
		"linear_velocity_x": linear_velocity.x,
		"linear_velocity_y": linear_velocity.y,
		"angular_velocity": angular_velocity,
		"energy": energy,
		"status": status,
		"current_task": current_task,
		"target_celestial_body_name": target_celestial_body_name,
		"target_resource_id": target_resource_id,
		"target_probe_id": target_probe_id,
		"target_position_x": target_position.x,
		"target_position_y": target_position.y,
		"trail_points": trail_points,
		"ai_state_variables": ai_state_variables,
		"known_resource_locations": known_resource_locations,
		"known_probe_locations": known_probe_locations,
		"message_buffer": message_buffer.map(func(msg_data): return msg_data.to_dict())
	}

static func from_dict(data: Dictionary) -> ProbeData:
	var new_probe_data = ProbeData.new()
	var temp_rng := RandomNumberGenerator.new() # Create a temporary RNG for static method
	temp_rng.randomize() # Ensure it's seeded
	new_probe_data.probe_id = data.get("probe_id", "")
	new_probe_data.generation = data.get("generation", 0)
	new_probe_data.unique_id = data.get("unique_id", str(Time.get_ticks_usec()) + "_" + str(temp_rng.randi_range(1000,9999)))
	var origin = Vector2(data.get("global_transform_origin_x", 0.0), data.get("global_transform_origin_y", 0.0))
	var rotation = data.get("global_transform_rotation", 0.0)
	var scale = Vector2(data.get("global_transform_scale_x", 1.0), data.get("global_transform_scale_y", 1.0))
	new_probe_data.global_transform = Transform2D(rotation, origin).scaled_local(scale) # More robust way to set transform
	new_probe_data.linear_velocity = Vector2(data.get("linear_velocity_x", 0.0), data.get("linear_velocity_y", 0.0))
	new_probe_data.angular_velocity = data.get("angular_velocity", 0.0)
	new_probe_data.energy = data.get("energy", 100.0)
	new_probe_data.status = data.get("status", "idle")
	new_probe_data.current_task = data.get("current_task", "")
	new_probe_data.target_celestial_body_name = data.get("target_celestial_body_name", "")
	new_probe_data.target_resource_id = data.get("target_resource_id", "")
	new_probe_data.target_probe_id = data.get("target_probe_id", "")
	new_probe_data.target_position = Vector2(data.get("target_position_x", 0.0), data.get("target_position_y", 0.0))
	new_probe_data.trail_points = data.get("trail_points", PackedVector2Array())
	new_probe_data.ai_state_variables = data.get("ai_state_variables", {})
	new_probe_data.known_resource_locations = data.get("known_resource_locations", {})
	new_probe_data.known_probe_locations = data.get("known_probe_locations", {})
	var msg_buffer_data = data.get("message_buffer", [])
	for msg_dict in msg_buffer_data:
		new_probe_data.message_buffer.append(MessageData.from_dict(msg_dict))
	return new_probe_data