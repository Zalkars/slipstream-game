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
	# Keep the editor from importing the screenshots as game resources.
	if not FileAccess.file_exists("res://shots/.gdignore"):
		FileAccess.open("res://shots/.gdignore", FileAccess.WRITE).close()
	var game := Game.new()
	game.use_3d_cars = true
	add_child(game)
	await get_tree().process_frame
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
# frame cap off. Desktop numbers only show relative cost between presets.
func _perf(game, presets: Array) -> void:
	Engine.max_fps = 0
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	for lv in presets:
		game.set_graphics(lv, 60)
		game.challenge_config = {}
		game.start_run()
		game._snap_challenge_weather(0.70, 3)
		game.weather_timer = 999.0
		var times: Array = []
		for i in range(240):
			game._rewind_invuln = 999.0
			game.time_of_day = 0.70
			var t0 := Time.get_ticks_usec()
			await get_tree().process_frame
			if i >= 60:
				times.append(float(Time.get_ticks_usec() - t0) / 1000.0)
		times.sort()
		var avg := 0.0
		for v in times:
			avg += v
		avg /= float(times.size())
		print("[perf] %s night storm: avg %.2f ms, p50 %.2f, p95 %.2f" % [GfxPresets.KEYS[lv], avg, times[times.size() / 2], times[int(times.size() * 0.95)]])
