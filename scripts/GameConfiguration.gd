extends Resource
class_name GameConfiguration

# === World Configuration ===
@export_group("World Settings")
@export var world_size_au: float = 10.0
@export var asteroid_belt_inner_au: float = 2.2
@export var asteroid_belt_outer_au: float = 3.2
@export var asteroid_count: int = 500
@export var asteroid_mass_range: Vector2 = Vector2(1e10, 1e15)

# === Physics Configuration ===
@export_group("Physics Settings")
@export var timestep_seconds: float = 3600.0
@export var integration_method: String = "verlet" # Options: "euler", "verlet", "rk4"
@export var gravitational_constant: float = 6.67430e-20 # km^3 kg^-1 s^-2 (scaled for simulation)
@export var au_scale: float = 10000.0 # Arbitrary units for display and simulation scale (1 AU = 10000 units)
@export var max_gravitational_acceleration: float = 10000.0 # Max acceleration in simulation units/s^2 (tune as needed)
@export var n_body_interaction_max_distance_meters: float = 1.0e15 # Max distance in meters for N-body gravitational interaction between celestial bodies.

# === Probe Configuration ===
@export_group("Probe Settings")
@export var max_probes: int = 20
@export var initial_probes: int = 1
@export var max_energy: float = 100000.0
@export var initial_energy: float = 90000.0
@export var replication_cost: float = 80000.0
@export var replication_min_energy: float = 99900.0 # Must be near max to replicate
@export var probe_mass: float = 8.0 # kg, relatively small
@export var thrust_force_magnitudes: Array[float] = [0.0, 0.08, 0.18, 0.32] # N, scaled
@export var thrust_energy_cost_factor: float = 0.001 # Energy per unit of thrust per second
@export var energy_decay_rate: float = 0.001 # Passive energy loss per second
@export var max_velocity: float = 10000.0 # Simulation units per second
@export var moment_of_inertia: float = 5.0 # kg*m^2 (or simulation equivalent)
@export var torque_magnitudes: Array[float] = [0.0, 0.008, 0.018] # Nm, scaled
@export var max_angular_velocity: float = PI / 4 # rad/s
@export var communication_range: float = 100.0 # Simulation units
@export var communication_energy_cost: float = 5.0 # Energy cost per communication action
@export var communication_cooldown: float = 5.0 # Seconds between communication attempts
@export var replication_cooldown_sec: float = 60.0 # Seconds, probe-specific cooldown
@export var replication_mutation_chance: float = 0.05 # Chance of any mutation during replication
@export var replication_mutation_factor_small: float = 0.1 # +/- factor for small mutations

# === Resource Configuration ===
@export_group("Resource Settings")
@export var resource_count: int = 15
@export var resource_amount_range: Vector2 = Vector2(10000, 20000) # Min/max amount per node
@export var resource_regen_rate: float = 0.0 # Per second, if applicable
@export var harvest_rate: float = 2.0 # Units per second
@export var harvest_distance: float = 5.0 # Simulation units
@export var discovery_range: float = 12.5 # Simulation units, for probes to detect resources

# === RL Configuration ===
@export_group("Reinforcement Learning")
@export var episode_length_steps: int = 50000
@export var learning_rate: float = 3e-4
@export var batch_size: int = 64
@export var observation_space_size: int = 25 # Number of features in the observation vector
@export var num_observed_resources: int = 3 # How many nearest resources to include in observation
@export var num_observed_probes: int = 5 # How many nearest probes to include in observation
@export var num_observed_celestial_bodies: int = 3 # How many nearest celestial bodies to include in observation
@export var celestial_observation_range_au: float = 5.0 # Max distance in AU to observe celestial bodies
@export var reward_factors: Dictionary = {
    # Existing
    "mining": 0.05,                     # Reward for active mining
    "high_energy": 0.1,                 # Reward for energy > 75%
    "proximity": 1.95,                  # Scaled reward for being close to target
    "reach_target": 2.0,                # One-time bonus for reaching/mining a new target
    "stay_alive": 0.02,                 # Small reward per step for surviving

    # New Factors
    "low_energy_penalty": -0.5,         # Penalty for energy < 25%
    "critical_energy_penalty": -2.0,    # Penalty for energy < 10%
    "discovery_bonus": 1.5,             # Bonus for discovering a new resource (via signal)
    "replication_success": 3.0,         # Reward for successful replication
    "thrust_cost": -0.01,               # Penalty per unit of thrust applied
    "torque_cost": -0.005,              # Penalty per unit of torque applied
    "inaction_penalty": -0.1,           # Penalty if no significant state change for a while
    "collision_penalty": -5.0,          # Penalty for collision (if probe emits signal)
    "communication_success": 0.2,       # Reward for successful communication action
    "target_lost_penalty": -0.5,        # Penalty if current target becomes invalid/lost
    "no_target_penalty": -0.05,         # Small penalty if no target is selected for a while
    "stored_resource_factor": 0.001     # Small reward per unit of stored resource
}
@export var discount_factor: float = 0.99 # Q-Learning discount factor
@export var q_epsilon_start: float = 1.0 # Q-Learning initial epsilon for exploration
@export var q_epsilon_decay: float = 0.001 # Q-Learning epsilon decay rate per update
@export var q_epsilon_min: float = 0.01 # Q-Learning minimum epsilon
@export var max_probe_g_force_for_norm: float = 1000.0 # For normalizing gravity gradient sensor

# === AI Settings ===
@export_group("AI Settings")
@export var ai_update_interval_sec: float = 1.0 # How often AI requests a new action
@export var ai_debug_logging: bool = false # Enable detailed AI decision logging
@export var ai_show_debug_visuals: bool = false # Show AI-related in-world debug visuals
@export var q_learning_save_on_episode_end: bool = true # Save Q-table at the end of an episode
@export var q_learning_load_on_episode_start: bool = true # Load Q-table at the start of an episode
@export var q_learning_table_filename: String = "q_table_fallback.json" # Filename for the Q-table
@export var ai_request_timeout: float = 5.0 # Timeout in seconds for external AI HTTP requests

# === Visualization Configuration ===
@export_group("Visualization")
@export var screen_width: int = 1400
@export var screen_height: int = 900
@export var target_fps: int = 60
@export var probe_size: int = 12 # pixels
@export var enable_particle_effects: bool = true
@export var enable_organic_ships: bool = true # If true, probes might have slightly varied appearances
@export var max_trail_points: int = 500 # For probe trails
@export var max_orbit_points: int = 1000 # For celestial body orbit trails
@export var probe_movement_trail_update_interval_frames: int = 5 # Physics frames between probe trail updates
@export var celestial_body_orbit_trail_update_interval_frames: int = 5 # Physics frames between orbit trail updates

# === Debug Configuration ===
@export_group("Debug Settings")
@export var debug_mode: bool = false
@export var show_orbital_mechanics: bool = true # Display orbital paths, apoapsis, periapsis
@export var show_energy_conservation: bool = true # Log energy changes
@export var memory_warn_mb: int = 2048 # Warn if memory usage exceeds this

@export_group("Performance & Quality")
# Adaptive Quality System
@export var adaptive_quality_enabled: bool = true
@export var adaptive_quality_fps_low: float = 30.0
@export var adaptive_quality_fps_medium_target: float = 45.0 # FPS target to try and reach from LOW
@export var adaptive_quality_fps_high: float = 55.0
@export var adaptive_quality_fps_medium_fallback: float = 50.0 # FPS target to fallback to from HIGH
@export var adaptive_quality_update_interval: float = 1.0 # Seconds
@export var adaptive_quality_min_time_in_level: float = 5.0 # Seconds to stay in a quality level
@export var adaptive_quality_initial_level: String = "MEDIUM" # "LOW", "MEDIUM", "HIGH"

# LOD System
@export var lod_base_distances: Array[float] = [500.0, 1500.0, 3000.0] # Base distances for LOD transitions
@export var lod_distance_multiplier_low: float = 0.75 # Multiplier for LOW quality
@export var lod_distance_multiplier_medium: float = 1.0 # Multiplier for MEDIUM quality
@export var lod_distance_multiplier_high: float = 1.25 # Multiplier for HIGH quality

# Particle Quality Settings (General Multipliers)
# Specific particle effects will need to interpret these.
@export var particle_amount_multiplier_low: float = 0.5
@export var particle_amount_multiplier_medium: float = 1.0
@export var particle_amount_multiplier_high: float = 1.0 # Max quality might not exceed standard
@export var particle_lifetime_multiplier_low: float = 0.75
@export var particle_lifetime_multiplier_medium: float = 1.0
@export var particle_lifetime_multiplier_high: float = 1.0
# Example: A specific particle effect might also have a "disable_on_low_quality: bool" property
# that it checks based on the quality level passed to it.

@export_group("Simulation Settings")
@export var gravity_field_radius_multiplier: float = 5.0
@export var simulation_scale: float = 1.0  # pixels per meter
@export var kepler_max_iterations: int = 100
@export var enable_gravity_field_interactions: bool = true

@export_group("Performance Settings Extended")
@export var enable_orbit_trails: bool = true

@export_group("Probe Settings Extended")
@export var rup_spd: float = 2.0  # thrust ramp up speed
@export var thrust_ramp_down_speed: float = 3.0
@export var rotation_ramp_up_speed: float = 2.5
@export var rotation_ramp_down_speed: float = 3.5
@export var sensor_range: float = 150.0
@export var mining_energy_cost_per_second: float = 1.0

# === World/Physics Settings ===
@export var world_bounds_x: float = 10000.0
@export var world_bounds_y: float = 10000.0
@export var max_probe_speed_for_norm: float = 1000.0
@export var max_probe_angular_vel_for_norm: float = 3.14159
@export var max_resource_distance_for_norm: float = 1000.0
@export var max_resource_amount_for_norm: float = 20000.0
@export var max_celestial_distance_for_norm: float = 10000.0
@export var celestial_mass_norm_factor: float = 1e24
@export var max_gravity_influence_for_norm: float = 0.01