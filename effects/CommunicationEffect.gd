extends Line2D
class_name CommunicationEffect

@export var duration: float = 0.75
@export var fade_out_time: float = 0.25

var _time_elapsed: float = 0.0
var _initial_modulate: Color

func _ready():
	_initial_modulate = modulate
	# Ensure the line is not drawn until setup
	clear_points()

func setup_effect(start_pos: Vector2, end_pos: Vector2, effect_duration: float = -1.0):
	if effect_duration > 0:
		duration = effect_duration
	
	clear_points()
	add_point(start_pos)
	add_point(end_pos)
	
	# Reset visual properties
	modulate = _initial_modulate
	_time_elapsed = 0.0
	
	# Default line properties (can be set in the scene as well)
	if width_curve == null: # Check if a curve is already set
		var curve = Curve.new()
		curve.add_point(Vector2(0, 1), 0, 0) # Start width factor
		curve.add_point(Vector2(1, 1), 0, 0) # End width factor
		width_curve = curve # Apply a default curve if none exists
	
	if default_color.a < 0.01 and modulate.a < 0.01 : # If fully transparent by default
		default_color.a = 1.0 # Make it visible
		modulate.a = 1.0

	set_as_top_level(true) # Draw on top, independent of parent transform for global positions

func _process(delta: float):
	_time_elapsed += delta
	
	if _time_elapsed >= duration:
		queue_free()
		return
	
	# Fade out logic
	if _time_elapsed > (duration - fade_out_time):
		var fade_progress = (_time_elapsed - (duration - fade_out_time)) / fade_out_time
		modulate.a = _initial_modulate.a * (1.0 - fade_progress)
	else:
		modulate.a = _initial_modulate.a

# Optional: Method to return to an object pool instead of queue_free()
# func return_to_pool():
#    if get_parent() and get_parent().has_method("return_pooled_object"):
#        get_parent().return_pooled_object(self.scene_file_path, self) # Assuming scene_file_path is set
#    else:
#        queue_free() # Fallback if no pool