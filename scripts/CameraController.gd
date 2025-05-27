extends Node2D

# Configurable properties
@export var follow_speed: float = 5.0
@export var zoom_speed: float = 0.1
@export var min_zoom: float = 0.5
@export var max_zoom: float = 2.0
@export var smooth_transitions: bool = true # Placeholder, actual smoothing logic for target change can be added

var target_node: Node2D = null
var current_zoom: float = 1.0

@onready var camera: Camera2D = get_parent() if get_parent() is Camera2D else null

func _ready():
	if not camera:
		printerr("CameraController must be a child of a Camera2D node.")
		return
	current_zoom = camera.zoom.x # Initialize with camera's current zoom
	set_process_input(true)
	set_physics_process(true)

	# Inform LODManager about this camera
	var lod_manager = get_node_or_null("/root/LODManager")
	if lod_manager and lod_manager.has_method("update_camera_node"):
		lod_manager.update_camera_node(camera)
	elif lod_manager:
		push_warning("CameraController: LODManager found, but no update_camera_node method.")
	#else:
		#push_warning("CameraController: LODManager not found.") # Can be noisy

func _physics_process(delta: float):
	if not camera:
		return

	if is_instance_valid(target_node):
		var target_position = target_node.global_position
		if smooth_transitions:
			camera.global_position = camera.global_position.lerp(target_position, follow_speed * delta)
		else:
			camera.global_position = target_position

func _input(event: InputEvent):
	if not camera:
		return

	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			current_zoom -= zoom_speed
			current_zoom = clamp(current_zoom, min_zoom, max_zoom)
			camera.zoom = Vector2(current_zoom, current_zoom)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			current_zoom += zoom_speed
			current_zoom = clamp(current_zoom, min_zoom, max_zoom)
			camera.zoom = Vector2(current_zoom, current_zoom)

func set_target(node: Node2D):
	"""Sets the target for the camera to follow."""
	target_node = node
	if not is_instance_valid(target_node):
		print("CameraController: Target node is not valid.")
	else:
		print("CameraController: New target set to: ", target_node.name)


func shake_camera(duration: float, strength: float):
	"""
	Placeholder for camera shake functionality.
	For now, it just prints to the console.
	"""
	print("CameraController: Shaking camera for ", duration, " seconds with strength ", strength)
	# Actual shake implementation would involve rapidly offsetting the camera
	# for the given duration. This could be done with a Timer and random offsets.
	# Example:
	# var shake_timer = Timer.new()
	# shake_timer.wait_time = duration
	# shake_timer.one_shot = true
	# shake_timer.connect("timeout", self, "_on_shake_timer_timeout", [camera_original_offset])
	# add_child(shake_timer)
	# shake_timer.start()
	# # During the shake, in _physics_process, apply random offset based on strength
	# # Store original offset before shake starts to restore it.

func _on_shake_timer_timeout(original_offset):
	# Restore camera offset if an actual shake was implemented
	# camera.offset = original_offset
	# print("Camera shake finished")
	pass