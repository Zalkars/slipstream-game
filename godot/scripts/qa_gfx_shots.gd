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
	var frames := int(_arg("frames", "150"))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var game := Game.new()
	game.use_3d_cars = true
	add_child(game)
	await get_tree().process_frame
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
					game._rewind_invuln = 999.0
					if i == frames - 40:
						game.set_braking(true)
					await get_tree().process_frame
				game.set_braking(false)
				await RenderingServer.frame_post_draw
				var img := get_viewport().get_texture().get_image()
				var path := "res://shots/gfx_%s%s_%s_%s.png" % [tag, GfxPresets.KEYS[lv], tod_name, w_name]
				img.save_png(ProjectSettings.globalize_path(path))
				print("[shots] ", path)
	get_tree().quit(0)
