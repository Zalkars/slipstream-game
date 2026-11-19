extends SceneTree

# Throw-away frame-time probe: the real Game node, first race in 3D (cold sprite
# cache), then the same run in 2D.

const GAME := preload("res://scripts/game.gd")


func _initialize() -> void:
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


func _run_frames(game, count: int) -> Array:
	var out: Array = []
	var last := Time.get_ticks_usec()
	for i in range(count):
		await process_frame
		var now := Time.get_ticks_usec()
		out.append(float(now - last) / 1000.0)
		last = now
	return out


func _run() -> void:
	await process_frame
	var game = GAME.new()
	game.name = "Game"
	root.add_child(game)
	game.use_3d_cars = true
	await process_frame
	await process_frame

	game.start_run()
	var cold: Array = await _run_frames(game, 420)
	_stats("3D cold", cold)
	print("[frame] sprites after run ", game.race_art.cached_count())

	game.start_run()
	var warm: Array = await _run_frames(game, 420)
	_stats("3D warm", warm)
	print("[frame] sprites after run ", game.race_art.cached_count())

	game.use_3d_cars = false
	game.start_run()
	var flat: Array = await _run_frames(game, 420)
	_stats("2D", flat)
	quit(0)
