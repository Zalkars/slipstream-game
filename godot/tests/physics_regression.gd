extends Node

# 0.8.0 weather braking physics: grip by surface, FPS independence,
# determinism per seed, legacy (SLIP1) physics, and that the renderer never
# touches the simulation RNG.

var failures := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var game := Game.new()
	game.use_3d_cars = false
	add_child(game)
	game.set_process(false)
	check_mu_table()
	check_puddle_grip(game)
	check_braking_by_weather(game)
	check_fps_independence(game)
	check_determinism(game)
	check_legacy_physics(game)
	check_weather_schedule(game)
	check_render_keeps_run_rng(game)
	check_fog_banks()
	print("[physics] grip table, puddles, wet braking, FPS independence, deterministic and legacy weather, render RNG isolation, fog banks: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(1 if failures else 0)


func check_mu_table() -> void:
	check(is_equal_approx(Game.surface_mu(0.0, 0.0, false), 1.0), "Dry grip is 1.0")
	check(is_equal_approx(Game.surface_mu(1.0, 0.0, false), 0.70), "Wet grip is ~0.7")
	check(is_equal_approx(Game.surface_mu(1.0, 1.0, false), 0.50), "Deep puddle grip is ~0.5")
	check(is_equal_approx(Game.surface_mu(0.2, 0.0, true), 0.35), "Aquaplaning grip is 0.35")
	var damp := Game.surface_mu(0.5, 0.0, false)
	check(damp < 1.0 and damp > 0.7, "Damp road sits between dry and wet")


func _prepare(game: Game, wet: float, seed_val := 99) -> void:
	game.challenge_config = {"type": "daily", "seed": seed_val, "car_index": 0, "tod": 0.2, "weather": 0}
	game.start_run()
	game.wetness = wet
	game.weather_timer = 9999.0
	game._rewind_invuln = 9999.0
	game.puddles = []
	game.cars.clear()
	game.spawn_t = 9999.0
	game.item_t = 9999.0
	game._rear_spawn_t = 9999.0
	game.road_event_t = 9999.0


func check_puddle_grip(game: Game) -> void:
	_prepare(game, 1.0)
	game.puddles = [{"x": (game.player_x - game.road_x) / game.road_w, "y": fposmod(game.player_y - game.scroll, Game.ROAD_CYCLE),
		"rx": 60.0, "ry": 120.0, "rot": 0.0, "phase": 0.0}]
	var depth := game.puddle_depth_at(game.player_x, game.player_y)
	check(depth > 0.9, "Player standing in the middle of a full puddle: depth=%f" % depth)
	game.speed = game.top_speed
	game._update_grip(1.0 / 60.0)
	check(game.aquaplane_t > 0.0 and is_equal_approx(game.grip_mu, Game.MU_AQUAPLANE), "Deep water at speed must aquaplane")
	game.puddles = []
	for i in range(40):
		game._update_grip(1.0 / 60.0)
	check(game.aquaplane_t <= 0.0, "Aquaplaning is short")
	check(is_equal_approx(game.grip_mu, Game.MU_WET), "Out of the puddle the wet grip returns")
	game.wetness = 0.2
	check(game.puddle_depth_at(game.player_x, game.player_y) == 0.0, "No puddles without rain")


# Braking from top speed for 0.4 s: wet roads take longer to shed speed, but
# only by a weighty margin, not a punishing one.
func _brake_test(game: Game, wet: float, fps: int) -> float:
	_prepare(game, wet)
	game.t = 80.0
	game.speed = game.top_speed
	game.set_braking(true)
	var dt := 1.0 / float(fps)
	var n := int(round(0.4 * float(fps)))
	for i in range(n):
		game.wetness = wet
		game._tick(dt)
	game.set_braking(false)
	return game.speed


func check_braking_by_weather(game: Game) -> void:
	var dry := _brake_test(game, 0.0, 60)
	var wet := _brake_test(game, 1.0, 60)
	var start := game.top_speed
	check(wet > dry + 5.0, "Wet braking must be slower: dry %.1f wet %.1f" % [dry, wet])
	check(start - wet > (start - dry) * 0.65, "Wet braking must stay usable (>65%% of dry): %.1f vs %.1f" % [start - wet, start - dry])
	print("[physics] speed after 0.4 s braking from %.0f: dry %.1f, wet %.1f" % [start, dry, wet])


func check_fps_independence(game: Game) -> void:
	var speeds: Array = []
	for fps in [30, 60, 120, 144]:
		speeds.append(_brake_test(game, 1.0, fps))
	for v in speeds:
		check(absf(float(v) - float(speeds[1])) < float(speeds[1]) * 0.01, "Wet braking must not depend on FPS: %s" % str(speeds))
	print("[physics] wet braking at 30/60/120/144 FPS: ", speeds)


func _scripted_run(game: Game, seed_val: int) -> Dictionary:
	game.challenge_config = {"type": "daily", "seed": seed_val, "car_index": 2, "tod": 0.3, "weather": Game.WEATHER_STORM}
	game.start_run()
	game._rewind_invuln = 9999.0
	for i in range(900):
		if i % 120 == 30:
			game.move_lane(1 if (i / 120) % 2 == 0 else -1)
		game.set_braking(i % 200 > 150)
		game._rewind_invuln = 9999.0
		game._tick(1.0 / 60.0)
	return {"scroll": game.scroll, "x": game.player_x, "speed": game.speed, "cars": game.cars.size(),
		"rng": game.run_rng.state, "wet": game.wetness, "mu": game.grip_mu}


func check_determinism(game: Game) -> void:
	var a := _scripted_run(game, 4242)
	var b := _scripted_run(game, 4242)
	check(a == b, "Same seed + inputs must reproduce the run exactly: %s vs %s" % [a, b])
	check(float(a.wet) > 0.3, "Storm run must be wet")


func check_legacy_physics(game: Game) -> void:
	game.challenge_config = {"type": "duel", "seed": 7, "car_index": 0, "tod": 0.2, "weather": 3, "physics": 1, "samples": [], "end_scroll": 0.0}
	game.start_run()
	check(game.physics_version == 1, "SLIP1 duels race with physics 1")
	game.challenge_config["physics"] = 2
	game.start_run()
	check(game.physics_version == 2 and game.weather_timer == 55.0 and game.fog_amount > 0.0,
		"SLIP2 duels retain the old storm profile and opening interval")
	var expected := RandomNumberGenerator.new()
	expected.state = game.run_rng.state
	var pool := [Game.WEATHER_RAIN, Game.WEATHER_RAIN, Game.WEATHER_CLOUDY]
	var next: int = pool[expected.randi() % pool.size()]
	var duration := expected.randf_range(55.0, 88.0) if next == Game.WEATHER_RAIN else expected.randf_range(65.0, 105.0)
	game._next_weather()
	check(game.weather_state == next and game.weather_timer == duration and game.run_rng.state == expected.state,
		"SLIP2 duels preserve the old weather sequence and RNG draws")
	game.challenge_config = {}
	game.start_run()
	check(game.physics_version == Game.PHYSICS_VERSION, "Normal runs use the current physics")
	check(int(game.build_challenge_payload("X").get("physics", 0)) == Game.PHYSICS_VERSION, "Shared codes carry the physics version")


func check_weather_schedule(game: Game) -> void:
	var counts := [0, 0, 0, 0, 0]
	for roll in range(100):
		counts[Game.WEATHER.pick(roll)] += 1
	check(counts == [75, 15, 5, 1, 4], "Clear and cloudy weather dominate, with separate rain, storm and fog odds")
	var sequences: Array = []
	for tod in [0.2, 0.72]:
		game.challenge_config = {"type": "daily", "seed": 441, "tod": tod, "weather": Game.WEATHER_CLEAR}
		game.start_run()
		var traffic_rng := game.run_rng.state
		var sequence: Array = []
		for i in range(500):
			game._next_weather()
			sequence.append([game.weather_state, game.weather_timer])
		check(game.run_rng.state == traffic_rng, "Weather rolls leave the traffic RNG alone")
		check(sequence.any(func(entry: Array) -> bool: return entry[0] == Game.WEATHER_RAIN)
			and sequence.any(func(entry: Array) -> bool: return entry[0] == Game.WEATHER_FOG),
			"Both rain and fog occur at every time of day")
		sequences.append(sequence)
	check(sequences[0] == sequences[1], "The weather sequence does not depend on the time of day")
	game._snap_challenge_weather(0.72, Game.WEATHER_CLOUDY)
	check(game.rain_amount == 0.0 and game.fog_fx.density_now() == 0.0, "Cloudy nights have no drizzle or fog")
	game._snap_challenge_weather(0.2, Game.WEATHER_RAIN)
	check(game.rain_amount > 0.0 and game.fog_fx.density_now() == 0.0, "Rain does not spawn fog")
	game._snap_challenge_weather(0.2, Game.WEATHER_FOG)
	check(game.rain_amount == 0.0 and game.fog_fx.density_now() > 0.0, "Fog does not start rain")
	game.challenge_config = {}
	game.start_run(true)
	check(game.get_night_factor() == 0.0 and game.weather_state == Game.WEATHER_CLEAR,
		"Driver training starts with a clear day")


# Rendering frames (rain, sparks, fog, drops) must never draw from run_rng.
func check_render_keeps_run_rng(game: Game) -> void:
	game.challenge_config = {"type": "daily", "seed": 31337, "car_index": 0, "tod": 0.7, "weather": Game.WEATHER_STORM}
	game.start_run()
	game._rewind_invuln = 9999.0
	for i in range(30):
		game._tick(1.0 / 60.0)
	var before: int = game.run_rng.state
	for lv in [GfxPresets.LOW, GfxPresets.ULTRA]:
		game.set_graphics(lv, 60)
		for i in range(20):
			game.render_stack.frame(1.0 / 60.0)
		if game.contact_fx != null and game.contact_fx.has_method("spark_burst"):
			game.contact_fx.spark_burst(Vector2(game.player_x, game.player_y), Vector2.RIGHT, 1.0)
			game.render_stack.frame(1.0 / 60.0)
	check(game.run_rng.state == before, "Render systems must not consume run_rng")


func check_fog_banks() -> void:
	for v in [0.0, 1234.0, 98765.0]:
		check(FogFx.bank_at(555, v) == FogFx.bank_at(555, v), "Fog banks are a pure function of seed and distance")
		var b := FogFx.bank_at(555, v)
		check(b >= 0.35 and b <= 1.25, "Fog bank in range")
	check(FogFx.bank_at(1, 5000.0) != FogFx.bank_at(2, 5000.0), "Different seeds give different fog")
