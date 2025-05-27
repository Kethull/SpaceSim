extends Node

# Main.gd
# Root script for the main scene. Handles global input and scene-wide logic.

var camera_controller: Node

func _ready():
	print("Main scene ready.")
	# Get the CameraController node
	# Assuming Camera2D is named MainCamera and CameraController is its child
	var camera_node = get_node_or_null("MainCamera")
	if camera_node:
		camera_controller = camera_node.get_node_or_null("CameraController")
		if camera_controller:
			# Set the Main node itself as the initial target
			camera_controller.set_target(self)
			print("CameraController target set to Main node.")
		else:
			printerr("CameraController node not found under MainCamera.")
	else:
		printerr("MainCamera node not found.")


func _input(event):
	if camera_controller:
		if event.is_action_pressed("ui_accept"): # Using "ui_accept" (Space/Enter) for shake test
			print("Attempting to shake camera via Main.gd input.")
			camera_controller.shake_camera(0.5, 10.0) # Shake for 0.5s with strength 10
		# Temporary input for testing camera shake with number keys
		if event is InputEventKey and event.pressed:
			if event.keycode == KEY_1:
				print("Key 1 pressed: Shaking camera (0.3s, 5 strength)")
				camera_controller.shake_camera(0.3, 5.0)
			elif event.keycode == KEY_2:
				print("Key 2 pressed: Shaking camera (0.7s, 15 strength)")
				camera_controller.shake_camera(0.7, 15.0)

	if event.is_action_pressed("pause_simulation"):
		print("Pause simulation action pressed.")
	if event.is_action_pressed("reset_simulation"):
		print("Reset simulation action pressed.")
		# Add reset logic here if SimulationManager has a reset function
		# if get_tree().get_root().has_node("SimulationManager"):
		# 	get_tree().get_root().get_node("SimulationManager").reset_simulation()

	if event.is_action_pressed("save_simulation"):
		var sl_manager = get_node_or_null("/root/SaveLoadManager")
		if sl_manager:
			print("Main.gd: Save simulation action pressed. Calling SaveLoadManager.quick_save()")
			sl_manager.quick_save()
		else:
			printerr("Main.gd: SaveLoadManager Autoload node not found at /root/SaveLoadManager.")
			
	if event.is_action_pressed("load_simulation"):
		var sl_manager = get_node_or_null("/root/SaveLoadManager")
		if sl_manager:
			print("Main.gd: Load simulation action pressed. Calling SaveLoadManager.quick_load()")
			sl_manager.quick_load()
		else:
			printerr("Main.gd: SaveLoadManager Autoload node not found at /root/SaveLoadManager.")
			
	if event.is_action_pressed("toggle_ui"):
		print("Toggle UI action pressed.")
	if event.is_action_pressed("focus_next_probe"):
		print("Focus next probe action pressed.")
	if event.is_action_pressed("toggle_debug_panel"):
		print("Toggle debug panel action pressed.")
	if event.is_action_pressed("zoom_in"):
		print("Zoom in action pressed.")
	if event.is_action_pressed("zoom_out"):
		print("Zoom out action pressed.")
