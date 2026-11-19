extends Node

# Throw-away frame-time probe, loaded as a temporary autoload so the real Main
# and Game run with their usual autoloads. Prints frame stats for a cold 3D
# race, a warm one and a 2D one, then quits.

var _last := 0


func _ready() -> void:
	call_deferred("_run")


func _stats(name: String, frames: Array) -> void:
	var total := 0.0
	var worst := 0.0
	var over := 0
	var sorted := frames.duplicate()
	sorted.sort()
	for f in frames:
		total += float(f)
		worst = maxf(worst, float(f))
		if float(f) > 33.4:
			over += 1
	var p95: float = sorted[int(float(sorted.size()) * 0.95)] if sorted.size() > 0 else 0.0
	print("[frame] %-8s avg %.1f ms  p95 %.1f  max %.1f  >33ms %d/%d" % [
		name, total / maxf(1.0, float(frames.size())), p95, worst, over, frames.size()])


func _run_frames(n: int) -> Array:
	var out: Array = []
	_last = Time.get_ticks_usec()
	for i in range(n):
		await get_tree().process_frame
		var now := Time.get_ticks_usec()
		out.append(float(now - _last) / 1000.0)
		_last = now
	return out


func _run() -> void:
	for i in range(30):
		await get_tree().process_frame
	var main = get_tree().current_scene
	if main == null:
		print("[frame] no scene")
		get_tree().quit()
		return
	main.cars_3d = true
	main.game.use_3d_cars = true
	main.start_game(false)
	print("[frame] start sprites ", main.game.race_art.cached_count())

	var cold: Array = await _run_frames(420)
	_stats("3D cold", cold)
	print("[frame] sprites after cold ", main.game.race_art.cached_count())

	main.start_game(false)
	var warm: Array = await _run_frames(420)
	_stats("3D warm", warm)
	print("[frame] sprites after warm ", main.game.race_art.cached_count())

	main.game.use_3d_cars = false
	main.start_game(false)
	var flat: Array = await _run_frames(420)
	_stats("2D", flat)
	get_tree().quit()
