extends Control
class_name ModernUI

@onready var hud: Control = self # The script is on the HUD node, so 'self' is the HUD.
@onready var probe_list_panel: Panel = $"HUD#ProbeListPanel"
@onready var selected_probe_panel: Panel = $"HUD#SelectedProbePanel"
@onready var system_stats_panel: Panel = $"HUD#SystemStatsPanel"
@onready var debug_panel: Panel = $"HUD#DebugPanel"

var selected_probe_id: int = -1
var probe_data_cache: Dictionary = {}
var animation_tween: Tween

@onready var performance_monitor = get_node_or_null("/root/PerformanceMonitor")
@onready var adaptive_quality_manager = get_node_or_null("/root/AdaptiveQualityManager")

signal probe_selected(probe_id: int)
signal simulation_speed_changed(new_speed: float)
signal ui_action_requested(action_type: String, data: Dictionary)

func _ready():
	# Check if essential UI panels were found after @onready initialization
	if probe_list_panel == null:
		push_error("ModernUI Error: ProbeListPanel node not found. Expected path: 'HUD#ProbeListPanel'. Probe list UI will not be functional.")
	if selected_probe_panel == null:
		push_error("ModernUI Error: SelectedProbePanel node not found. Expected path: 'HUD#SelectedProbePanel'. Selected probe UI will not be functional.")
	if system_stats_panel == null:
		push_error("ModernUI Error: SystemStatsPanel node not found. Expected path: 'HUD#SystemStatsPanel'. System stats UI will not be functional.")
	
	# Handle debug_panel separately as its necessity depends on ConfigManager.config.debug_mode
	if debug_panel == null:
		if ConfigManager.get_setting("general", "debug_mode", false):
			push_error("ModernUI Error: DebugPanel node not found while debug_mode is enabled. Expected path: 'HUD#DebugPanel'. Debug UI will not be functional.")
		# else: # If debug_mode is false, missing debug_panel might be acceptable or logged differently.
			# print_debug("ModernUI Info: DebugPanel node not found, but debug_mode is disabled.")

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
	if probe_list_panel == null:
		return # Error logged in _ready

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
	if selected_probe_panel == null:
		return # Error logged in _ready

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
	if system_stats_panel == null:
		return # Error logged in _ready

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
	if debug_panel == null:
		# If debug_panel is null, we can't set its visibility or add children.
		# Error/warning for missing node (if debug_mode is true) is handled in _ready.
		return

	if not ConfigManager.get_setting("general", "debug_mode", false):
		debug_panel.visible = false # This is safe now because debug_panel is confirmed not null
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
   
	# Stress test button
	var stress_test_button = Button.new()
	stress_test_button.text = "Stress Test (100P, 300R)"
	stress_test_button.pressed.connect(_on_stress_test_button_pressed)
	controls.add_child(stress_test_button)
	
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
	# Check if any of the essential panels for animation are available
	if probe_list_panel == null and selected_probe_panel == null and system_stats_panel == null:
		push_warning("ModernUI Warning: All animation target panels (ProbeList, SelectedProbe, SystemStats) are null. Skipping panel glow animations.")
		return # Don't proceed if no panels to animate

	animation_tween = create_tween()
	animation_tween.set_loops()
	
	# Animate panel appearances
	animate_panel_glow()

func animate_panel_glow():
	# Add subtle glow animation to active panels
	var panels = [probe_list_panel, selected_probe_panel, system_stats_panel]
	var panel_names = ["ProbeListPanel", "SelectedProbePanel", "SystemStatsPanel"] # For better error messages
	
	if animation_tween == null: # Ensure tween is initialized
		push_warning("ModernUI Warning: animation_tween is null in animate_panel_glow. Animations might not have been set up correctly.")
		return

	for i in range(panels.size()):
		var panel = panels[i]
		if panel == null:
			push_warning("ModernUI Warning: Panel '%s' is null. Skipping animation for this panel." % panel_names[i])
			continue

		var style_box = panel.get_theme_stylebox("panel")
		if style_box is StyleBoxFlat:
			var original_color = style_box.border_color
			# Ensure the tween is valid before adding to it
			if animation_tween.is_valid():
				animation_tween.parallel().tween_method(
					func(color):
						if is_instance_valid(panel) and is_instance_valid(style_box): style_box.border_color = color,
					original_color,
					original_color * 1.3,
					2.0
				).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
				animation_tween.parallel().tween_method(
					func(color):
						if is_instance_valid(panel) and is_instance_valid(style_box): style_box.border_color = color,
					original_color * 1.3,
					original_color,
					2.0
				).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT).set_delay(2.0)
			else:
				push_warning("ModernUI Warning: animation_tween became invalid during animate_panel_glow for panel '%s'." % panel_names[i])
		elif panel != null: # Only warn if panel exists but stylebox is not StyleBoxFlat
			push_warning("ModernUI Warning: Panel '%s' does not have a StyleBoxFlat for 'panel' theme. Cannot animate glow." % panel_names[i])

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
	var _temp_val_L375 = simulation_data.get("probes")
	var _actual_val_L375 = _temp_val_L375 if _temp_val_L375 != null else {}
	update_probe_list(_actual_val_L375)
	update_selected_probe_info(simulation_data.get("selected_probe"))
	var _temp_val_L377 = simulation_data.get("stats")
	var _actual_val_L377 = _temp_val_L377 if _temp_val_L377 != null else {}
	update_system_stats(_actual_val_L377)
	var _temp_val_L378 = simulation_data.get("debug_info")
	var _actual_val_L378 = _temp_val_L378 if _temp_val_L378 != null else {}
	update_debug_info(_actual_val_L378)

func update_probe_list(probes_data: Dictionary):
	self.probe_data_cache = probes_data # Cache for focus_next_probe
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
	var _temp_val_L407_1 = probe_data.get("energy")
	var _actual_val_L407_1 = _temp_val_L407_1 if _temp_val_L407_1 != null else 0
	var _temp_val_L407_2 = probe_data.get("max_energy")
	var _actual_val_L407_2 = _temp_val_L407_2 if _temp_val_L407_2 != null else 1
	var energy_ratio = _actual_val_L407_1 / _actual_val_L407_2
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
	var _temp_val_L428 = probe_data.get("is_alive")
	var _actual_val_L428 = _temp_val_L428 if _temp_val_L428 != null else false
	if _actual_val_L428:
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
	var _temp_val_L482 = probe_data.get("id")
	var _actual_val_L482 = _temp_val_L482 if _temp_val_L482 != null else "Unknown"
	var _temp_val_L483 = probe_data.get("generation")
	var _actual_val_L483 = _temp_val_L483 if _temp_val_L483 != null else 0
	var _temp_val_L484 = probe_data.get("position")
	var _actual_val_L484 = _temp_val_L484 if _temp_val_L484 != null else Vector2.ZERO
	var _temp_val_L485 = probe_data.get("velocity")
	var _actual_val_L485 = _temp_val_L485 if _temp_val_L485 != null else Vector2.ZERO
	var _temp_val_L486 = probe_data.get("current_task")
	var _actual_val_L486 = _temp_val_L486 if _temp_val_L486 != null else "Idle"
	var _temp_val_L487 = probe_data.get("current_target_id")
	var _actual_val_L487 = _temp_val_L487 if _temp_val_L487 != null else "None"
	var _temp_val_L488 = probe_data.get("is_alive")
	var _actual_val_L488 = _temp_val_L488 if _temp_val_L488 != null else false
	var info_items = [
		["ID", str(_actual_val_L482)],
		["Generation", str(_actual_val_L483)],
		["Position", "(" + str(int(_actual_val_L484.x)) + ", " + str(int(_actual_val_L484.y)) + ")"],
		["Velocity", str(_actual_val_L485.length()).pad_decimals(1) + " u/s"],
		["Task", _actual_val_L486],
		["Target", str(_actual_val_L487)],
		["Status", "Alive" if _actual_val_L488 else "Dead"]
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
	var _temp_val_L516 = stats_data.get("episode")
	var _actual_val_L516 = _temp_val_L516 if _temp_val_L516 != null else 0
	var _temp_val_L517 = stats_data.get("step")
	var _actual_val_L517 = _temp_val_L517 if _temp_val_L517 != null else 0
	var _temp_val_L518 = stats_data.get("fps")
	var _actual_val_L518 = _temp_val_L518 if _temp_val_L518 != null else 60
	var _temp_val_L519 = stats_data.get("probe_count")
	var _actual_val_L519 = _temp_val_L519 if _temp_val_L519 != null else 0
	var _temp_val_L520 = stats_data.get("resources_mined")
	var _actual_val_L520 = _temp_val_L520 if _temp_val_L520 != null else 0
	var _temp_val_L521 = stats_data.get("active_resources")
	var _actual_val_L521 = _temp_val_L521 if _temp_val_L521 != null else 0
	var _temp_val_L522 = stats_data.get("sim_speed")
	var _actual_val_L522 = _temp_val_L522 if _temp_val_L522 != null else 1.0
	var stat_items = [
		["Episode", str(_actual_val_L516)],
		["Step", str(_actual_val_L517)],
		["FPS", str(_actual_val_L518).pad_decimals(1)],
		["Active Probes", str(_actual_val_L519)],
		["Resources Mined", str(_actual_val_L520).pad_decimals(1)],
		["Active Resources", str(_actual_val_L521)],
		["Simulation Speed", str(_actual_val_L522) + "x"]
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
	
	# Add performance metrics (fetched live)
	var metrics_to_display = []
	
	# FPS
	metrics_to_display.append(["FPS", "%d" % Engine.get_frames_per_second()])
	
	# Memory
	var static_mem_bytes = Performance.get_monitor(Performance.MEMORY_STATIC)
	var static_mem_mb = static_mem_bytes / (1024.0 * 1024.0)
	metrics_to_display.append(["Static Memory", "%.2f MB" % static_mem_mb])
	
	# Removed Dynamic/Physical Memory due to enum name issues. User can re-add if exact name is known.
   
	# Process Times
	var physics_time_sec = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS)
	metrics_to_display.append(["Physics Time", "%.3f ms" % (physics_time_sec * 1000.0)])
	var process_time_sec = Performance.get_monitor(Performance.TIME_PROCESS)
	metrics_to_display.append(["Process Time", "%.3f ms" % (process_time_sec * 1000.0)])
   
	# Object Counts
	metrics_to_display.append(["Object Count", "%d" % Performance.get_monitor(Performance.OBJECT_COUNT)])
	metrics_to_display.append(["Node Count", "%d" % Performance.get_monitor(Performance.OBJECT_NODE_COUNT)])
	metrics_to_display.append(["Orphan Nodes", "%d" % Performance.get_monitor(Performance.OBJECT_ORPHAN_NODE_COUNT)])
	metrics_to_display.append(["Resource Count", "%d" % Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT)]) # Godot resource, not game resource
   
	# Render Info (Draw Calls and Vertices removed due to enum name issues)
	# User can re-add if exact names like RENDER_DRAW_CALLS_IN_FRAME or RENDER_VERTICES_IN_FRAME are confirmed for their Godot version.
	
	# Adaptive Quality
	if is_instance_valid(adaptive_quality_manager):
		var quality_level_str = AdaptiveQualityManager.Quality.keys()[adaptive_quality_manager.current_quality_level]
		metrics_to_display.append(["Quality Level", quality_level_str])
	else:
		metrics_to_display.append(["Quality Level", "N/A"])
   
	# Add metrics from debug_data if they are not covered or are specific (e.g., AI times)
	if debug_data.has("ai_time_ms"):
		var _temp_val_L595 = debug_data.get("ai_time_ms")
		var _actual_val_L595 = _temp_val_L595 if _temp_val_L595 != null else 0
		metrics_to_display.append(["AI Update Time", str(_actual_val_L595) + " ms"])
	if debug_data.has("particle_count"): # This would be game-specific particle count
		var _temp_val_L597 = debug_data.get("particle_count")
		var _actual_val_L597 = _temp_val_L597 if _temp_val_L597 != null else 0
		metrics_to_display.append(["Game Particles", str(_actual_val_L597)])
   
   
	for metric_data in metrics_to_display:
		var metric_line = create_stat_line(metric_data[0], metric_data[1])
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

func _on_stress_test_button_pressed():
	var sim_manager = get_node_or_null("/root/Main/SimulationManager") # Adjust path if Main scene has a different root name
	if sim_manager and sim_manager.has_method("trigger_stress_test"):
		# Default values for the button, can be made configurable later
		sim_manager.trigger_stress_test(100, 300)
		print("ModernUI: Stress test triggered via button.")
	elif sim_manager:
		printerr("ModernUI: SimulationManager found, but no trigger_stress_test method.")
	else:
		printerr("ModernUI: SimulationManager not found at /root/Main/SimulationManager.")
