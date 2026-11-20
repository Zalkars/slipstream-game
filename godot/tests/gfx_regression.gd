extends Node

# 0.8.0 render pipeline: preset table, Auto benchmark mapping, dynamic
# resolution and preset application on a live Game.

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	check_preset_table()
	check_benchmark_mapping()
	check_dynamic_resolution()
	check_preset_application()
	print("[gfx] presets, auto benchmark, dynamic resolution, preset application: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(1 if failures else 0)


func check_preset_table() -> void:
	var prev := {}
	for lv in [GfxPresets.LOW, GfxPresets.MEDIUM, GfxPresets.HIGH, GfxPresets.ULTRA]:
		var p := GfxPresets.params(lv)
		check(int(p.level) == lv, "Preset must report its level")
		if not prev.is_empty():
			for key in ["lights", "shadow_lights", "rain_density", "fog_octaves", "max_sparks", "post_scale"]:
				check(float(p[key]) >= float(prev[key]), "Higher preset must not lower " + key)
		prev = p
	check(int(GfxPresets.params(GfxPresets.LOW).shadow_lights) == 0, "Low has no shadow casters")
	check(int(GfxPresets.params(GfxPresets.MEDIUM).shadow_lights) == 2, "Medium: 2 shadow casters")
	check(int(GfxPresets.params(GfxPresets.HIGH).shadow_lights) == 4, "High: 4 shadow casters")
	check(int(GfxPresets.params(GfxPresets.ULTRA).shadow_lights) == 8, "Ultra: 8 shadow casters")
	check(not bool(GfxPresets.params(GfxPresets.LOW).bloom), "Low has no bloom")
	check(int(GfxPresets.params(GfxPresets.LOW).screen_drops) == 0, "Screen drops start at Medium")
	check(int(GfxPresets.params(GfxPresets.MEDIUM).screen_drops) > 0, "Medium has screen drops")
	check(is_equal_approx(float(GfxPresets.params(GfxPresets.LOW).post_scale), 0.25), "Low post buffers at 1/4")
	check(is_equal_approx(float(GfxPresets.params(GfxPresets.MEDIUM).post_scale), 0.5), "Medium post buffers at 1/2")
	check(is_equal_approx(float(GfxPresets.params(GfxPresets.ULTRA).post_scale), 1.0), "Ultra post buffers at full")
	for key in ["auto", "low", "medium", "high", "ultra"]:
		check(GfxPresets.key_from_level(GfxPresets.level_from_key(key)) == key, "Preset key round trip: " + key)
	check(GfxPresets.level_from_key("garbage") == GfxPresets.AUTO, "Unknown key falls back to Auto")


func check_benchmark_mapping() -> void:
	check(GfxPresets.pick_from_benchmark(5.0) == GfxPresets.ULTRA, "Fast device -> Ultra")
	check(GfxPresets.pick_from_benchmark(11.0) == GfxPresets.HIGH, "11 ms -> High")
	check(GfxPresets.pick_from_benchmark(18.0) == GfxPresets.MEDIUM, "18 ms -> Medium")
	check(GfxPresets.pick_from_benchmark(30.0) == GfxPresets.LOW, "Slow device -> Low")
	check(GfxPresets.pick_from_benchmark(0.0) == GfxPresets.MEDIUM, "No measurement -> Medium")


func check_dynamic_resolution() -> void:
	var d := GfxPresets.DynamicRes.new()
	d.reset(0.5, 60)
	check(is_equal_approx(d.scale(), 0.5), "Dynamic res starts at the preset scale")
	for i in range(240):
		d.feed(1.0 / 30.0)
	check(d.scale() < 0.5, "Sustained slow frames must reduce the post buffers")
	var low := d.scale()
	for i in range(60 * 70):
		d.feed(1.0 / 60.0)
	check(d.scale() > low, "Calm frames must probe the resolution back up")
	check(d.scale() <= 0.5 + 0.001, "Never above the preset scale")
	d.reset(0.5, 60)
	d.feed(1.0)  # a hitch says nothing about load
	check(is_equal_approx(d.scale(), 0.5), "Single hitch must be ignored")


func check_preset_application() -> void:
	var game := Game.new()
	game.use_3d_cars = false
	add_child(game)
	game.set_process(false)
	for lv in [GfxPresets.LOW, GfxPresets.MEDIUM, GfxPresets.HIGH, GfxPresets.ULTRA]:
		game.set_graphics(lv, 60)
		var rs: RenderStack = game.render_stack
		check(rs.level == lv, "Render stack must take the new level")
		check(int(rs.params.level) == lv, "Render stack params follow the level")
		check(rs.bloom.enabled == bool(GfxPresets.params(lv).bloom), "Bloom toggles with the preset")
		check(is_equal_approx(rs.road_buffer.scale, float(GfxPresets.params(lv).road_buffer_scale)), "Road buffer scale follows the preset")
		for s in rs.systems:
			if "params" in s:
				check(int(s.params.get("level", -9)) == lv, "Every system receives the preset: " + str(s))
	# The render stack must survive simulated frames on every preset.
	game.start_run()
	for lv in [GfxPresets.LOW, GfxPresets.ULTRA]:
		game.set_graphics(lv, 60)
		for i in range(30):
			game._tick(1.0 / 60.0)
			game.render_stack.frame(1.0 / 60.0)
	check(game.running or game.crashed, "Run must survive preset switches")
	game.queue_free()
