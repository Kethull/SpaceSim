extends Node2D
class_name ParticleManager
# ParticleManager.gd
# Container for all particle effects in the game.
# Manages creating and pooling particle effects for thrusters, explosions, etc.

func _ready():
    print("ParticleManager ready.")
    # Initialization for particle systems if needed.
    # Pre-load particle scenes or set up particle emitters.

# Functions to trigger specific particle effects at given positions/nodes.
# Example: func play_thrust_effect(position: Vector2, direction: Vector2)
# Example: func play_explosion_effect(position: Vector2)

# Consider using GPUParticles2D or CPUParticles2D nodes as children
# and managing them from this script.