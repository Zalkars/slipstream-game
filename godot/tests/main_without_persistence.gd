extends "res://scripts/main.gd"

# Catch accidental persistence calls without reading or writing a player profile.
var save_calls := 0

func _load() -> void:
	pass

func _save() -> void:
	save_calls += 1
