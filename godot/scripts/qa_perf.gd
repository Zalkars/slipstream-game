extends SceneTree

# Throw-away benchmark for the race sprite bakery: how long a geometry rebuild,
# a material-only recolour and a full bake actually take.

const RACE := preload("res://scripts/race_art.gd")

var _ra


func _initialize() -> void:
	call_deferred("_run")


func _ms(a: int, b: int) -> String:
	return "%.2f ms" % (float(b - a) / 1000.0)


func _verts(n: Node) -> int:
	var total := 0
	var stack: Array = [n]
	while stack.size() > 0:
		var x: Node = stack.pop_back()
		if x is MeshInstance3D and (x as MeshInstance3D).mesh != null:
			var arr := (x as MeshInstance3D).mesh.surface_get_arrays(0)
			var v: PackedVector3Array = arr[Mesh.ARRAY_VERTEX]
			total += v.size()
		for c in x.get_children():
			stack.push_back(c)
	return total


func _run() -> void:
	_ra = RACE.new()
	root.add_child(_ra)
	await process_frame
	await process_frame

	var a := {"silhouette": "sedan", "color": "#e8e7e3", "stripe": false, "stripe_color": "#f0ede4"}
	var b := {"silhouette": "sedan", "color": "#3d4147", "stripe": true, "stripe_color": "#f0ede4"}
	var c := {"silhouette": "sport", "color": "#3d4147", "stripe": false, "stripe_color": "#f0ede4"}

	var t0 := Time.get_ticks_usec()
	_ra._model.show_car(a)
	var t1 := Time.get_ticks_usec()
	print("[perf] build sedan fresh     ", _ms(t0, t1))

	t0 = Time.get_ticks_usec()
	_ra._model.show_car(b)
	t1 = Time.get_ticks_usec()
	print("[perf] recolour + stripe      ", _ms(t0, t1))

	t0 = Time.get_ticks_usec()
	_ra._model.show_car(c)
	t1 = Time.get_ticks_usec()
	print("[perf] build sport            ", _ms(t0, t1))

	t0 = Time.get_ticks_usec()
	_ra._model.show_car(b)
	t1 = Time.get_ticks_usec()
	print("[perf] switch back to sedan   ", _ms(t0, t1))
	print("[perf] verts sedan            ", _verts(_ra._model))

	# full bake path (rebuild + 2 frames + readback + alpha bounds)
	t0 = Time.get_ticks_usec()
	await _ra.render_preview(b)
	t1 = Time.get_ticks_usec()
	print("[perf] bake sedan striped     ", _ms(t0, t1))

	t0 = Time.get_ticks_usec()
	await _ra.render_preview(a)
	t1 = Time.get_ticks_usec()
	print("[perf] bake sedan plain       ", _ms(t0, t1))

	t0 = Time.get_ticks_usec()
	await _ra.render_preview({"silhouette": "sedan", "color": "#7a1f24", "stripe": false, "stripe_color": "#f0ede4"})
	t1 = Time.get_ticks_usec()
	print("[perf] bake sedan new colour  ", _ms(t0, t1))

	print("[perf] tex count ", _ra.cached_count())
	quit(0)
