extends Node2D

# This script controls the discovery particle effect.

@onready var particles: GPUParticles2D = $GPUParticles2D

# Called when the node enters the scene tree for the first time.
func _ready():
	if not particles:
		printerr("DiscoveryEffect: GPUParticles2D node not found!")
		return
	# Ensure the effect plays once and then frees itself.
	particles.one_shot = true
	particles.emitting = false # Start non-emitting, will be triggered by play_effect

	# Connect the finished signal to queue_free to clean up after playing.
	# Similar to HarvestEffect, GPUParticles2D doesn't have a direct 'finished' signal for one_shot.
	# We'll use a Timer to queue_free after the particle lifetime.
	var timer = Timer.new()
	add_child(timer)
	# Set wait_time to be slightly longer than the particle lifetime to ensure all particles are gone.
	# This assumes 'lifetime' property of GPUParticles2D is set appropriately in the scene.
	timer.wait_time = particles.lifetime + 0.5 
	timer.one_shot = true
	timer.timeout.connect(queue_free)
	# The timer will be started in play_effect, after emitting is set to true.


# Call this function to play the discovery visual effect.
func play_effect():
	if not particles:
		printerr("DiscoveryEffect.play_effect: GPUParticles2D node not found!")
		return
	
	# Position is set by the spawner (Resource.gd)
	particles.emitting = true
	
	# Start the cleanup timer
	var timer = get_child(0) # Assuming the timer is the first child added in _ready
	if timer is Timer:
		timer.start()
	else:
		printerr("DiscoveryEffect: Cleanup timer not found!")

	print("DiscoveryEffect: Played at ", global_position)