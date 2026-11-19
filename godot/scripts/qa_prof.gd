extends SceneTree

# Throw-away: per-builder timings from a throw-away instrumented model copy.

const MODEL := preload("res://scripts/car_model_prof.gd")
const CARS := preload("res://scripts/cars.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	await process_frame
	var m := MODEL.new()
	root.add_child(m)
	await process_frame
	for i in range(CARS.LIST.size()):
		var c: Dictionary = CARS.get_car(i)
		m.show_car({
			"silhouette": c.silhouette,
			"color": c.color,
			"stripe": bool(c.stripe),
			"stripe_color": c.stripe_color,
		})
	quit(0)
