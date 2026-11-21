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
	check_lamp_table()
	await check_followup_render()
	print("[gfx] presets, auto benchmark, dynamic resolution, preset application, lamp anchors, drops, beams, surfaces: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
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


# Lamp anchors (bake_race_lamps.gd): every class in both art modes, lamps on
# the right ends of the body and in left/right order.
func check_lamp_table() -> void:
	var sils: Array = []
	for c: Dictionary in Cars.LIST:
		sils.append(str(c.silhouette))
	sils.append_array(["van", "pickup", "truck", "bus", "offroad", "sport", "hatch", "sedan", "ev", "muscle", "hyper"])
	for sil in sils:
		check(CarLamps.LAMPS.LAMPS_3D.has(sil), "3D lamp anchors for " + sil)
		check(CarLamps.LAMPS.LAMPS_2D.has("player|" + sil) or not Cars.LIST.any(func(c): return str(c.silhouette) == sil),
			"2D player lamp anchors for " + sil)
	for table in [CarLamps.LAMPS.LAMPS_3D, CarLamps.LAMPS.LAMPS_2D]:
		for key in table:
			var a: Dictionary = table[key]
			for cat in ["head", "tail", "ind_f", "ind_r"]:
				check(a.has(cat), "%s has %s" % [key, cat])
			if not (a.has("head") and a.has("tail")):
				continue
			check(float(a.head[0]) < float(a.head[2]) and float(a.tail[0]) < float(a.tail[2]), "Left lamp left of right lamp: " + key)
			check(float(a.head[1]) < 0.3 and float(a.tail[1]) > 0.7, "Headlights at the nose, tail lights at the back: " + key)
			check(float(a.ind_f[0]) <= float(a.head[0]) + 0.02 and float(a.ind_f[2]) >= float(a.head[2]) - 0.02, "Indicators outboard of headlights: " + key)
	# Placement follows the drawn box (2D) or the fitted sprite (3D).
	var out := {}
	CarLamps.points({"head": [0.25, 0.0, 0.75, 0.0]}, Vector2(100, 200), Vector2(80, 160), 0.0, out)
	check(out.head[0].is_equal_approx(Vector2(80, 120)) and out.head[1].is_equal_approx(Vector2(120, 120)), "Anchor maps to screen")


func check_followup_render() -> void:
	var game := Game.new()
	game.use_3d_cars = false
	add_child(game)
	game.set_process(false)
	game.set_graphics(GfxPresets.MEDIUM, 60)
	check(Asphalt.SEG_LEN >= 6000.0 and Asphalt.SEG_BLEND >= 1200.0, "Road surfaces change slowly and blend gradually")
	check(game.render_stack.road_strips.size() == RenderStack.ROAD_STRIPS, "Road drawn in light-culling strips")
	# Screen drops: only ever run down, and gather at the edges.
	game.challenge_config = {"type": "daily", "seed": 5, "car_index": 0, "tod": 0.7, "weather": Game.WEATHER_STORM}
	game.start_run()
	game._rewind_invuln = 9999.0
	var wx: WeatherFx = game.weather_fx
	var edge := 0
	var total := 0
	for i in range(600):
		game.speed = game.top_speed if i > 300 else game.base_speed
		wx.frame(1.0 / 60.0)
		for d in wx.drops:
			check(float(d.v.y) >= -0.001, "Screen drops must never move up")
			total += 1
			if float(d.p.x) < game.W * 0.25 or float(d.p.x) > game.W * 0.75:
				edge += 1
	check(total > 100, "Storm produces screen drops")
	check(float(edge) / maxf(1.0, float(total)) > 0.6, "Drops gather near the screen edges: %d/%d" % [edge, total])
	# Headlights: every traffic car on screen (and just above it) has a beam,
	# whether it got a PointLight2D or the matching fallback.
	game._snap_challenge_weather(0.70, Game.WEATHER_CLEAR)
	game.cars.clear()
	for k in range(10):
		game.cars.append({"lane": k % 4, "x": game._lane_x(k % 4), "y": -150.0 + k * 150.0, "w": game.car_w, "h": game.car_h,
			"kind": 0, "color": Color(0.5, 0.5, 0.5), "rel": 0.7, "cur_speed": 500.0, "braking": false, "silhouette": "sedan"})
	game.lighting_fx.frame(1.0 / 60.0)
	for c in game.cars:
		var found := false
		for ri in range(game.lighting_fx._req_count):
			var r: Dictionary = game.lighting_fx._requests[ri]
			if int(r.kind) == 0 and absf(float(r.pos.x) - float(c.x)) < 4.0 and absf(float(r.pos.y) - (float(c.y) - game.car_h * 0.5)) < game.car_h * 0.2:
				found = true
		check(found, "Traffic car at y=%.0f must have its headlight beam" % float(c.y))
	game.queue_free()
	await get_tree().process_frame
