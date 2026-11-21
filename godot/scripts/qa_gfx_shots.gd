extends Node

# Visual QA for the 0.8.0 renderer: day/night x clear/rain/storm/fog on the
# chosen presets, written to res://shots. Needs a graphical renderer:
#   godot --path godot --fixed-fps 60 res://tests/GfxShots.tscn -- [--presets=1,3] [--tag=x]

const TODS := {"day": 0.12, "night": 0.70}
const WEATHERS := {"clear": 0, "rain": 2, "storm": 3, "fog": 4}


func _ready() -> void:
	call_deferred("_run")


func _arg(name: String, def: String) -> String:
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--" + name + "="):
			return a.substr(name.length() + 3)
	return def


func _run() -> void:
	var presets: Array = []
	for p in _arg("presets", "1,3").split(","):
		presets.append(int(p))
	var only_w := _arg("weather", "")
	var only_t := _arg("tod", "")
	var tag := _arg("tag", "")
	var frames := int(_arg("frames", "300"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	if _arg("fullsize", "") != "":
		DisplayServer.window_set_size(Vector2i(720, 1560))
	# Keep the editor from importing the screenshots as game resources.
	if not FileAccess.file_exists("res://shots/.gdignore"):
		FileAccess.open("res://shots/.gdignore", FileAccess.WRITE).close()
	var game := Game.new()
	game.use_3d_cars = _arg("cars2d", "") == ""
	if not game.use_3d_cars:
		tag += "2d_"
	add_child(game)
	await get_tree().process_frame
	if _arg("surfaces", "") != "":
		await _surfaces(game, int(_arg("surfaces", "10")), int(presets[0]), tag)
		get_tree().quit(0)
		return
	if _arg("perf", "") != "":
		await _perf(game, presets)
		get_tree().quit(0)
		return
	for lv in presets:
		for tod_name in TODS:
			if only_t != "" and tod_name != only_t:
				continue
			for w_name in WEATHERS:
				if only_w != "" and w_name != only_w:
					continue
				game.set_graphics(lv, 60)
				game.challenge_config = {}
				seed(4242)
				game.start_run()
				game.run_rng.seed = 777
				game._snap_challenge_weather(float(TODS[tod_name]), int(WEATHERS[w_name]))
				game.weather_timer = 999.0
				game._rewind_invuln = 999.0
				for i in range(frames):
					game.time_of_day = float(TODS[tod_name])
					if i < frames - 2:
						game._rewind_invuln = 999.0
					if i == frames - 40:
						game.set_braking(true)
					if i == frames - 8 and game.contact_fx != null:
						# A scrape against the left rail, so sparks show up in the shots.
						game.contact_fx.spark_burst(Vector2(game.player_x - game.car_w * 0.5, game.player_y - 40.0), Vector2(-0.6, 1.0), 1.0)
					if i == frames - 2:
						game._rewind_invuln = 0.0  # hide the invulnerability ring
					await get_tree().process_frame
				game.set_braking(false)
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				var path := "res://shots/gfx_%s%s_%s_%s.png" % [tag, GfxPresets.KEYS[lv], tod_name, w_name]
				img.save_png(ProjectSettings.globalize_path(path))
				print("[shots] ", path)
	get_tree().quit(0)


# Frame-time sample per preset in the heaviest scene (night storm), vsync and
# frame cap off, at the full 720x1560 canvas. Reports wall frame time, GPU
# time of every viewport the renderer owns, render-system CPU time (the
# RenderStack frame), draw calls and primitives. Desktop numbers only compare
# presets and before/after; they are not a phone measurement.
func _perf(game, presets: Array) -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if _arg("fullsize", "") != "":
		DisplayServer.window_set_size(Vector2i(720, 1560))
	var root_rid := get_viewport().get_viewport_rid()
	RenderingServer.viewport_set_measure_render_time(root_rid, true)
	var scene := _arg("scene", "night_storm")
	var tod := 0.70 if scene.begins_with("night") else 0.12
	var wx := 3 if scene.ends_with("storm") else 0
	for lv in presets:
		game.set_graphics(lv, 60)
		game.challenge_config = {}
		seed(777)
		game.start_run()
		game.run_rng.seed = 777
		game._snap_challenge_weather(tod, wx)
		game.weather_timer = 999.0
		var vps: Array = [root_rid]
		for vp in game.render_stack.find_children("*", "SubViewport", true, false):
			RenderingServer.viewport_set_measure_render_time(vp.get_viewport_rid(), true)
			vps.append(vp.get_viewport_rid())
		var times: Array = []
		var gpu := 0.0
		var cpu := 0.0
		var dcpu := 0.0
		var per_sys := {}
		var dc := 0.0
		var prims := 0.0
		var n := 0
		for i in range(300):
			game._rewind_invuln = 999.0
			game.time_of_day = tod
			var t0 := Time.get_ticks_usec()
			await get_tree().process_frame
			if i >= 60:
				times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
				var g := 0.0
				for rid in vps:
					g += RenderingServer.viewport_get_measured_render_time_gpu(rid)
				gpu += g
				cpu += float(game.render_stack.get("last_cpu_ms")) if "last_cpu_ms" in game.render_stack else 0.0
				dcpu += float(game.get("draw_cpu_ms")) if "draw_cpu_ms" in game else 0.0
				if "system_ms" in game.render_stack:
					for k in game.render_stack.system_ms:
						per_sys[k] = float(per_sys.get(k, 0.0)) + float(game.render_stack.system_ms[k])
				dc += Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)
				prims += Performance.get_monitor(Performance.RENDER_TOTAL_PRIMITIVES_IN_FRAME)
				n += 1
		times.sort()
		var avg := 0.0
		for v in times:
			avg += v
		avg /= float(times.size())
		print("[perf] %s %s: frame avg %.2f ms p50 %.2f p95 %.2f | gpu %.2f ms | render cpu %.3f ms | game _draw %.3f ms | draw calls %.0f | prims %.0f" % [
			GfxPresets.KEYS[lv], scene, avg, times[times.size() / 2], times[int(times.size() * 0.95)],
			gpu / n, cpu / n, dcpu / n, dc / n, prims / n])
		var parts := []
		for k in per_sys:
			parts.append("%s %.3f" % [k, float(per_sys[k]) / n])
		print("[perf]   per system ms: ", ", ".join(parts))


# Road surface survey: one daylight shot per surface segment (and one across
# each transition), stitched into shots/surfaces.png for review.
func _surfaces(game, n: int, lv: int, tag: String) -> void:
	game.set_graphics(lv, 60)
	var strips: Array = []
	for k in range(n):
		for half in [0.5, 1.0]:
			game.challenge_config = {}
			game.start_run()
			game._snap_challenge_weather(0.12, 0)
			game.cars.clear()
			game.spawn_t = 999.0
			game.scroll = (float(k) + half) * Asphalt.SEG_LEN
			for i in range(6):
				game._rewind_invuln = 999.0
				game.time_of_day = 0.12
				game.spawn_t = 999.0
				await get_tree().process_frame
			await RenderingServer.frame_post_draw
			var img := get_viewport().get_texture().get_image()
			var w := img.get_width()
			var h := img.get_height()
			strips.append(img.get_region(Rect2i(int(w * 0.13), 0, int(w * 0.74), int(h * 0.55))))
	var sw: int = strips[0].get_width()
	var sh: int = strips[0].get_height()
	var sheet := Image.create(sw * strips.size(), sh, false, Image.FORMAT_RGBA8)
	for i in range(strips.size()):
		sheet.blit_rect(strips[i], Rect2i(0, 0, sw, sh), Vector2i(i * sw, 0))
	sheet.save_png(ProjectSettings.globalize_path("res://shots/%ssurfaces.png" % tag))
	print("[shots] res://shots/%ssurfaces.png" % tag)
