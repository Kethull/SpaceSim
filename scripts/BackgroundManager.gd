extends ParallaxBackground
class_name BackgroundManager
# BackgroundManager.gd
# Manages the parallax background layers (star fields).

# References to ParallaxLayer nodes (if needed for dynamic changes)
# @onready var star_field_far = $StarFieldFar
# @onready var star_field_mid = $StarFieldMid
# @onready var star_field_near = $StarFieldNear

func _ready():
    print("BackgroundManager ready.")
    # Initialization for background elements.
    # For example, dynamically loading textures for star fields or adjusting parameters.
    # Ensure motion_mirroring is set appropriately for the screen size or view.
    # The motion_mirroring values in the .tscn should ideally match screen_width/height from GameConfiguration.

func _process(delta):
    # The ParallaxBackground node itself handles the scrolling based on camera movement.
    # Additional logic can be added here if needed, e.g., changing star density,
    # adding/removing layers, or other visual effects.
    pass

# You might want to add functions to:
# - Change star textures or colors.
# - Adjust parallax speeds dynamically.
# - Respond to game events (e.g., entering a nebula might change the background).