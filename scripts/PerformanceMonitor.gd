extends Node

var time_since_last_log: float = 0.0
const LOG_INTERVAL: float = 5.0 # Log metrics every 5 seconds

@onready var probe_manager: Node = get_node_or_null("/root/Main/ProbeManager") # Adjust path if necessary

func _ready():
	print("PerformanceMonitor Initialized.")
	if not probe_manager:
		print("PerformanceMonitor: ProbeManager not found. AI metrics will not be logged.")
	log_all_performance_metrics()

func _process(delta: float):
	time_since_last_log += delta
	if time_since_last_log >= LOG_INTERVAL:
		log_all_performance_metrics()
		time_since_last_log = 0.0

func log_all_performance_metrics():
	# Log Memory Usage
	var static_mem = Performance.get_monitor(Performance.MEMORY_STATIC)
	print("--- Performance Metrics ---")
	print("Memory Usage - Static: %s bytes" % [static_mem])

	# Log AI Performance Metrics
	if probe_manager:
		var active_probes = probe_manager.get_children() # Assuming probes are direct children
		if active_probes.is_empty():
			print("AI Metrics: No active probes found in ProbeManager.")
			return

		print("AI Performance Metrics (per agent):")
		var ai_metrics_found = false
		for probe_node in active_probes:
			if not probe_node.is_class("Node2D") and not probe_node.is_class("RigidBody2D"): # Basic check, better to use class_name if Probe.gd has one
				# Or check if probe_node.has_method("get_probe_id") or similar
				# For now, assume all children of ProbeManager are Probes or have AIAgent
				pass

			var ai_agent = probe_node.get_node_or_null("AIAgent") # Assuming AIAgent is a child named "AIAgent"
			if ai_agent and ai_agent.has_method("get_performance_metrics"):
				ai_metrics_found = true
				var metrics = ai_agent.get_performance_metrics()
				var probe_id = "UnknownProbe"
				if probe_node.has_get("probe_id"): # Assuming Probe.gd has a probe_id property
					probe_id = probe_node.get("probe_id")
				elif probe_node.has_method("get_name"): # Fallback to node name
					probe_id = probe_node.get_name()

				print("  Probe [%s]:" % probe_id)
				print("    Avg Obs Gather: %.3f ms" % metrics.get("avg_obs_gather_ms", 0.0))
				print("    Avg AI Decision: %.3f ms" % metrics.get("avg_ai_decision_ms", 0.0))
				print("    Avg Action Apply: %.3f ms" % metrics.get("avg_action_apply_ms", 0.0))
				# Optional: Log current times too if needed
				# print("    Curr Obs Gather: %.3f ms" % metrics.get("current_obs_gather_ms", 0.0))
				# print("    Curr AI Decision: %.3f ms" % metrics.get("current_ai_decision_ms", 0.0))
				# print("    Curr Action Apply: %.3f ms" % metrics.get("current_action_apply_ms", 0.0))
			elif ai_agent == null:
				# This might be noisy if ProbeManager has non-probe children.
				# print("Debug: Child %s of ProbeManager is not a Probe or has no AIAgent child." % probe_node.name)
				pass
		
		if not ai_metrics_found:
			print("AI Metrics: No AIAgents found or they lack get_performance_metrics method.")
	else:
		print("AI Metrics: ProbeManager not found.")
	print("-------------------------")


func get_current_memory_usage() -> Dictionary: # Kept for compatibility if used elsewhere
	return {
		"static": Performance.get_monitor(Performance.MEMORY_STATIC)
	}