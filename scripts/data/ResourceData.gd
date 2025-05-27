extends Resource
class_name ResourceData

@export var position: Vector2 = Vector2.ZERO
@export var current_amount: float = 0.0
@export var max_amount: float = 20000.0
@export var resource_type: String = "mineral"
@export var regeneration_rate: float = 0.0
@export var discovered_by: Array[int] = []
@export var harvest_difficulty: float = 1.0