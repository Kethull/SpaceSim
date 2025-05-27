extends Resource
class_name CelestialBodyData

@export var body_name: String = ""
@export var global_transform: Transform2D = Transform2D.IDENTITY
@export var linear_velocity: Vector2 = Vector2.ZERO
@export var orbit_points: PackedVector2Array = []
# @export var mass: float = 1.0 # Example: if mass can change
# @export var radius: float = 50.0 # Example: if radius can change

func _init(p_name: String = ""):
	body_name = p_name

func to_dict() -> Dictionary:
	return {
		"body_name": body_name,
		"global_transform_origin_x": global_transform.origin.x,
		"global_transform_origin_y": global_transform.origin.y,
		"global_transform_rotation": global_transform.get_rotation(),
		"global_transform_scale_x": global_transform.get_scale().x,
		"global_transform_scale_y": global_transform.get_scale().y,
		"linear_velocity_x": linear_velocity.x,
		"linear_velocity_y": linear_velocity.y,
		"orbit_points": orbit_points
	}

static func from_dict(data: Dictionary) -> CelestialBodyData:
	var new_body_data = CelestialBodyData.new()
	new_body_data.body_name = data.get("body_name", "")
	
	var origin = Vector2(data.get("global_transform_origin_x", 0.0), data.get("global_transform_origin_y", 0.0))
	var rotation = data.get("global_transform_rotation", 0.0)
	var scale = Vector2(data.get("global_transform_scale_x", 1.0), data.get("global_transform_scale_y", 1.0))
	new_body_data.global_transform = Transform2D(rotation, origin).scaled_local(scale)
	
	new_body_data.linear_velocity = Vector2(data.get("linear_velocity_x", 0.0), data.get("linear_velocity_y", 0.0))
	new_body_data.orbit_points = data.get("orbit_points", PackedVector2Array())
	return new_body_data