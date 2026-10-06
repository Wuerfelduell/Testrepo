class_name AIPersonality
extends Resource
## Scoring preferences only. They do not grant extra movement, actions or dice.

@export var id: StringName = &"brute"
@export var hit_weight: float = 2.0
@export var damage_weight: float = 2.0
@export var kill_weight: float = 24.0
@export var danger_weight: float = 2.0
@export var cover_weight: float = 1.0
@export var height_weight: float = 1.0
@export var spacing_weight: float = 0.0
@export var retreat_weight: float = 1.0
@export var opportunity_weight: float = 2.0
@export var preferred_distance: float = 1.25
