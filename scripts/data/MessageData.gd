extends Resource
class_name MessageData

# Enum for message types
enum MessageType {
	UNDEFINED,
	RESOURCE_LOCATION,
	ENERGY_REQUEST,
	HELP_SIGNAL,
	PROBE_STATUS,
	GENERAL_BROADCAST,
	TARGET_ACQUIRED,
	OBSTACLE_DETECTED
}

@export var message_id: String = ""             # Unique ID for the message
@export var sender_id: String = ""            # ID of the sending probe
@export var target_id: String = ""            # ID of the target probe ("" or "BROADCAST" for broadcast)
@export var message_type: MessageType = MessageType.UNDEFINED
@export var position: Vector2 = Vector2.ZERO  # Position of sender or relevant event
@export var timestamp: int = 0                # Time.get_ticks_msec()
@export var data: Dictionary = {}             # Payload of the message
# @export var status: String = "pending" # Consider adding if message lifecycle is complex

func _init(p_sender_id: String = "", p_target_id: String = "", p_message_type: MessageType = MessageType.UNDEFINED, p_position: Vector2 = Vector2.ZERO, p_data: Dictionary = {}, p_message_id: String = ""):
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	message_id = p_message_id if p_message_id != "" else str(Time.get_ticks_usec()) + "_" + str(rng.randi_range(10000, 99999))
	sender_id = p_sender_id
	target_id = p_target_id
	message_type = p_message_type
	position = p_position
	timestamp = Time.get_ticks_msec()
	data = p_data

func _to_string() -> String:
	return "MessageData(ID: %s, Sender: %s, Target: %s, Type: %s, Pos: %s, Time: %s, Data: %s)" % [
		message_id,
		sender_id,
		target_id,
		MessageType.keys()[message_type] if message_type >= 0 and message_type < MessageType.keys().size() else "INVALID_TYPE", # Get string name of enum safely
		str(position),
		str(timestamp),
		str(data)
	]

func to_dict() -> Dictionary:
	return {
		"message_id": message_id,
		"sender_id": sender_id,
		"target_id": target_id,
		"message_type": int(message_type), # Store enum as int
		"position_x": position.x,
		"position_y": position.y,
		"timestamp": timestamp,
		"data": data,
		# "status": status
	}

static func from_dict(dict_data: Dictionary) -> MessageData:
	var new_msg_data = MessageData.new()
	# _init called by MessageData.new() will generate an ID if dict_data["message_id"] is missing or empty.
	# If dict_data["message_id"] is present and valid, _init will use it.
	# So, we can directly assign from dict_data, and _init handles the default generation.
	new_msg_data.message_id = dict_data.get("message_id", new_msg_data.message_id) # Preserve generated if not in dict
	new_msg_data.sender_id = dict_data.get("sender_id", "")
	new_msg_data.target_id = dict_data.get("target_id", "")
	
	var type_int = dict_data.get("message_type", MessageType.UNDEFINED)
	if type_int is int and type_int >= 0 and type_int < MessageType.values().size():
		new_msg_data.message_type = MessageType.values()[type_int]
	else:
		new_msg_data.message_type = MessageType.UNDEFINED
		
	new_msg_data.position = Vector2(dict_data.get("position_x", 0.0), dict_data.get("position_y", 0.0))
	new_msg_data.timestamp = dict_data.get("timestamp", 0)
	new_msg_data.data = dict_data.get("data", {})
	# new_msg_data.status = dict_data.get("status", "pending")
	
	return new_msg_data