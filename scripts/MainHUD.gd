extends Control
class_name MainHUD
# MainHUD.gd
# Script for the main Heads Up Display.
# Manages UI elements like probe lists, selected probe info, system stats, and debug panels.

@onready var probe_list_panel = $ProbeListPanel
@onready var selected_probe_panel = $SelectedProbePanel
@onready var system_stats_panel = $SystemStatsPanel
@onready var debug_panel = $DebugPanel

func _ready():
    print("MainHUD ready.")
    # Initialize HUD elements.
    # Populate initial data or set default states.
    # Example: update_probe_list([])
    # Example: show_debug_panel(ConfigManager.get_config().debug_mode)

func _process(delta):
    # Update HUD elements that need frequent refreshing.
    # Example: update_selected_probe_info() if a probe is selected.
    pass

# Functions to update specific parts of the HUD:
# func update_probe_list(probes: Array):
# func display_selected_probe_details(probe: Probe):
func update_system_stats(stats: Dictionary):
    if system_stats_panel and stats.has("total_replications"):
        # Assuming system_stats_panel has a label named "TotalReplicationsLabel"
        # or a method to update a specific stat.
        var replications_label = system_stats_panel.get_node_or_null("TotalReplicationsLabel")
        if replications_label and replications_label is Label:
            replications_label.text = "Total Replications: %d" % stats.total_replications
        # else:
            # print_debug("MainHUD: TotalReplicationsLabel not found or not a Label in system_stats_panel.")
    
    # Existing stats updates would go here, e.g.:
	# if system_stats_panel and stats.has("total_probes"):
	#    system_stats_panel.get_node("TotalProbesLabel").text = "Probes: %d" % stats.total_probes

# func toggle_debug_panel(visible: bool):

# Connect signals from other managers (e.g., ProbeManager) to update the HUD.