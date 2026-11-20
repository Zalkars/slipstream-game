extends Node

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

	check_slingshot(game)
	check_chrono_shield(game)
	check_all_car_perks(game)
	check_traffic_signals_and_events(game)
	check_challenge_codec_and_determinism(game)
	await check_main_duel_and_daily_rewards()

	print("[features] slingshot, chrono-shield, 9 car perks, road events, signals, ghost codec & duel/daily rewards: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(1 if failures else 0)


func check_slingshot(game: Game) -> void:
	game.challenge_config = {}
	game.car_index = 0
	game.start_run()
	game.cars = [{"lane": game.lane, "x": game.player_x, "y": game.player_y - game.car_h * 2.0, "w": game.car_w, "h": game.car_h, "cur_speed": game.speed}]
	var ready_hits := [0]
	var fired_hits := [0]
	var cb_r := func(): ready_hits[0] += 1
	var cb_f := func(_c: int, _p: int): fired_hits[0] += 1
	game.slingshot_ready.connect(cb_r)
	game.slingshot_fired.connect(cb_f)
	for _i in range(75):
		game._update_slipstream(1.0 / 60.0)
	check(game.slingshot_charge >= 0.99 and ready_hits[0] == 1, "Slipstream must charge Slingshot to ready once")
	# Grace buffer holds briefly after leaving draft
	game.cars.clear()
	game._update_slipstream(0.20)
	check(game.slingshot_charge >= 0.99, "Slingshot grace must survive brief gap before lane snap")
	var nitro_before := game.nitro
	var bonus_before := game.bonus
	game.move_lane(1)
	check(fired_hits[0] == 1 and game.slingshot_t > 0.5 and game.slingshot_charge == 0.0, "Lane change must fire Slingshot Snap")
	check(game.nitro > nitro_before + 0.15 and game.bonus > bonus_before, "Slingshot Snap must award nitro and bonus points")
	game.slingshot_ready.disconnect(cb_r)
	game.slingshot_fired.disconnect(cb_f)


func check_chrono_shield(game: Game) -> void:
	game.challenge_config = {}
	game.car_index = 0
	game.start_run()
	game.nitro = 1.0
	game.rewind_frames = [game._snapshot_state()]
	var shield_hits := [0]
	var cb := func(): shield_hits[0] += 1
	game.chrono_shield_triggered.connect(cb)
	game._crash(true)
	check(shield_hits[0] == 1 and game.rewinding and not game.running, "Full 3 nitros must trigger Chrono-Shield instead of game over")
	game._tick_rewind(0.05)
	check(not game.rewinding and game.running and not game.crashed, "Chrono-Shield rewind must restore active driving state")
	check(game.nitro < 0.01, "Chrono-Shield must consume 3 nitro charges and not restore old nitro from snapshot")
	check(game._rewind_invuln > 1.0, "Chrono-Shield must grant brief post-rewind invulnerability")
	game.chrono_shield_triggered.disconnect(cb)

	# Without 3 full charges, crash ends the run
	game.start_run()
	game.nitro = 0.85
	game.rewind_frames = [game._snapshot_state()]
	game._crash(true)
	check(game.crashed and not game.rewinding, "Partial nitro must not trigger Chrono-Shield")


func check_all_car_perks(game: Game) -> void:
	# 0: HATCH compact hitbox
	game.challenge_config = {}
	game.car_index = 0
	game.start_run()
	check(is_equal_approx(game.hitbox_w_mult, 0.88), "HATCH must have 0.88 hitbox width multiplier")

	# 1: VAN magnet + 35% coin bonus
	game.car_index = 1
	game.start_run()
	game.distance = 100.0
	game.pickup_coins = 0
	game.near = 0
	check(game._coins_total() == 14, "VAN must apply +35% coin multiplier")
	var coin_x := game._lane_x(game.lane + 1)
	game.items = [{"lane": game.lane + 1, "x": coin_x, "y": game.player_y, "kind": 0, "phase": 0.0}]
	game._move_items(0.05)
	check(game.items.is_empty() or float(game.items[0].x) < coin_x, "VAN magnet must pull coins from adjacent lane")

	# 2: SEDAN GT wide cutin
	game.car_index = 2
	game.start_run()
	game.speed = 900.0
	game.nitro = 0.0
	game.move_lane(1)
	check(game._cutin_window > Game.CUTIN_WINDOW, "SEDAN GT must extend cutin window")

	# 3: OFF-ROAD puddles & lightbar signal
	game.car_index = 3
	game.start_run()
	game.wetness = 0.8
	game.puddles = [{"x": 0.5, "y": 0.0, "rx": 120.0, "ry": 120.0, "rot": 0.0, "phase": 0.0}]
	game.scroll = game.player_y
	game.player_x = game.road_x + game.road_w * 0.5
	var n0 := game.nitro
	game._check_offroad_puddles()
	check(game.nitro > n0 and game.bonus >= 85.0, "OFF-ROAD puddle crossing must award points and nitro")

	# 4: MUSCLE nitro ramming
	game.car_index = 4
	game.start_run()
	game.nitro = 1.0
	check(game.tap_nitro() and game.ram_charges == 1, "MUSCLE nitro must grant 1 ram charge")
	var target := {"lane": game.lane, "x": game.player_x, "y": game.player_y - 10.0, "w": game.car_w, "h": game.car_h, "kind": 0, "rel": 0.7, "cur_speed": 400.0, "braking": false, "near": false, "cutin": false}
	game.cars = [target]
	game._move_traffic(1.0 / 60.0, game.speed, game.base_speed, false)
	check(not game.crashed and game.ram_charges == 0 and bool(target.get("rammed", false)), "MUSCLE under nitro must ram passenger car without crashing")

	# 5: PICKUP 4th nitro tank
	game.car_index = 5
	game.start_run()
	check(is_equal_approx(game.nitro, Game.NITRO_SEG * 2.0) and game.max_nitro > 1.3, "PICKUP must start with 2 charges and hold 4 segments")
	game.nitro = game.max_nitro
	game.rewind_frames = [game._snapshot_state()]
	game._crash(true)
	game._tick_rewind(0.05)
	check(absf(game.nitro - Game.NITRO_SEG) < 0.02, "PICKUP Chrono-Shield consumes 3 charges and leaves 4th charge")

	# 6: SPORT carbon brakes
	game.car_index = 6
	game.start_run()
	check(game.brake_heat_mult < 0.6 and game.slingshot_rate_mult > 1.3, "SPORT must heat brakes slower and charge slingshot faster")

	# 7: VOLT EV regen brake
	game.car_index = 7
	game.start_run()
	game.nitro = 0.0
	game.braking = true
	game.speed = 600.0
	game._tick(0.5)
	check(game.nitro > 0.10, "VOLT EV braking must regenerate nitro")

	# 8: HYPER hyperdrive
	game.car_index = 8
	game.start_run()
	game.boosting = true
	game.boost_t = 1.0
	game.speed = 1350.0
	game._tick(0.016)
	check(game.hyperdrive_active and game._effective_score_mult() >= 2, "HYPER above 310 km/h must activate Hyperdrive 2x score")


func check_traffic_signals_and_events(game: Game) -> void:
	game.challenge_config = {}
	game.car_index = 0
	game.start_run()
	var c := {"lane": 1, "x": game._lane_x(1), "y": 400.0, "w": game.car_w, "h": game.car_h, "kind": 0, "rel": 0.7, "cur_speed": 400.0, "braking": false}
	game.cars = [c]
	check(game._try_start_lane_change(c, false), "Car with open neighbors must start signaling lane change")
	var sig := int(c.get("signal_dir", 0))
	check(sig != 0 and float(c.get("signal_t", 0.0)) > 1.0, "Turn signal must telegraph before moving")
	for _i in range(85):
		game._update_traffic_signals(1.0 / 60.0)
	check(int(c.lane) == 1 + sig, "Car must move into signaled lane after telegraph finishes")

	# Wall safety check: 3 other lanes blocked at same Y -> 4th must refuse lane change
	game.cars = [
		{"lane": 0, "x": game._lane_x(0), "y": 400.0, "w": game.car_w, "h": game.car_h},
		{"lane": 2, "x": game._lane_x(2), "y": 400.0, "w": game.car_w, "h": game.car_h},
		{"lane": 3, "x": game._lane_x(3), "y": 400.0, "w": game.car_w, "h": game.car_h},
	]
	check(not game._lane_wall_safe(400.0, 1), "Lane safety guard must reject changes that block all 4 lanes")

	# Radar fast check
	game.start_run()
	game.road_event_type = Game.EVENT_RADAR
	game.road_event = {"type": Game.EVENT_RADAR, "mode": "fast", "target_kmh": 200, "y": game.player_y - 10.0, "warned": true, "resolved": false}
	game.speed = 980.0
	var c_before := game.pickup_coins
	game._update_road_events(0.05, 50.0)
	check(game.pickup_coins == c_before + 25, "Passing speed radar above target km/h must award 25 coins")

	# Roadworks barrier crash
	game.start_run()
	game.closed_lane = 0
	game.lane = 0
	game.player_x = game._lane_x(0)
	game.road_event_type = Game.EVENT_ROADWORKS
	game.road_event = {"type": Game.EVENT_ROADWORKS, "head_y": game.player_y + 600.0, "taper_len": 440.0, "zone_len": 2600.0, "warned": true, "cone_hit": true}
	game._update_road_events(0.016, 10.0)
	check(game.crashed, "Hitting solid roadworks barrier must crash player")


func check_challenge_codec_and_determinism(game: Game) -> void:
	# Determinism across two identical seeded runs
	var cfg := {"type": "duel", "seed": 987654, "car_index": 4, "tod": 0.68, "weather": Game.WEATHER_STORM, "name": "АЛЕКС", "score": 12000, "distance": 900, "end_scroll": 12000.0, "samples": [{"scroll": 0.0, "x_norm": 0.375, "flags": 0}]}
	var snapshots := []
	for run_i in range(2):
		game.challenge_config = cfg.duplicate(true)
		game.start_run()
		for _step in range(180):
			game._tick(1.0 / 30.0)
		var car_sig: Array = []
		for c in game.cars:
			car_sig.append([int(c.lane), snapped(float(c.y), 0.01), str(c.silhouette)])
		snapshots.append([game.weather_state, game.free_lane, car_sig, game.items.size()])
	check(snapshots[0] == snapshots[1], "Identical challenge seeds must produce identical traffic & road state")

	# Codec roundtrip + telegram text wrapping + marathon downsampling + corruption check
	var samples: Array = []
	for i in range(1400):
		samples.append({"scroll": float(i * 120), "x_norm": 0.375 if i % 2 == 0 else 0.625, "flags": i % 4})
	var payload := {
		"seed": 445566,
		"car_index": 6,
		"score": 54321,
		"distance": 4210,
		"near": 19,
		"tod": 0.68,
		"weather": 3,
		"step_ms": 200,
		"end_time": 280.0,
		"name": "Максим",
		"samples": samples,
	}
	var code := ChallengeCodec.encode(payload)
	check(code.begins_with("SLIP2-") and code.length() < 900, "Encoded marathon ghost must stay compact: len=%d" % code.length())
	var msg := ChallengeCodec.format_share_message(payload, code, false)
	var decoded := ChallengeCodec.decode(msg)
	check(bool(decoded.get("ok", false)), "Codec must extract and decode code from Telegram message")
	check(int(decoded.seed) == 445566 and int(decoded.car_index) == 6 and int(decoded.score) == 54321, "Decoded metadata must match")
	check(str(decoded.name) == "Максим", "Decoded UTF-8 rival name must match")
	var gs := ChallengeCodec.sample_ghost(decoded, 10.0)
	check(not bool(gs.finished) and float(gs.scroll) > 0.0, "Ghost sampler must interpolate active trace")
	var gs_end := ChallengeCodec.sample_ghost(decoded, 300.0)
	check(bool(gs_end.finished), "Ghost sampler must report finished past end_time")
	check(int(decoded.get("physics", 0)) == 2, "New codes carry physics version 2")
	# 0.7.0 codes stay playable, with the physics they were recorded under.
	var legacy_payload := payload.duplicate()
	legacy_payload["physics"] = 1
	var legacy := ChallengeCodec.encode(legacy_payload)
	check(legacy.begins_with("SLIP1-"), "Legacy physics must encode as SLIP1")
	var legacy_dec := ChallengeCodec.decode("Challenge: " + legacy)
	check(bool(legacy_dec.get("ok", false)) and int(legacy_dec.get("physics", 0)) == 1, "SLIP1 code must decode with physics 1")
	var forged := ChallengeCodec.decode("SLIP2-" + legacy.substr(6))
	check(not bool(forged.get("ok", false)), "Prefix must match the payload version")
	var bad := ChallengeCodec.decode("SLIP1-abc123invalid")
	check(not bool(bad.get("ok", false)), "Invalid challenge payload must be rejected")
	var missing := ChallengeCodec.decode("hello world without code")
	check(not bool(missing.get("ok", false)), "Message without SLIP1 code must be rejected")

	var d1 := ChallengeCodec.daily_challenge({"year": 2026, "month": 11, "day": 19})
	var d2 := ChallengeCodec.daily_challenge({"year": 2026, "month": 11, "day": 20})
	check(int(d1.seed) != int(d2.seed), "Daily challenge seed must vary across dates")


func check_main_duel_and_daily_rewards() -> void:
	Sfx.set_music_enabled(false)
	var main = load("res://tests/main_without_persistence.gd").new()
	main.cars_3d = false
	main.music_on = false
	main.tutorial_done = true
	add_child(main)
	main.game.set_process(false)

	# Daily challenge grants bronze/silver/gold once per day
	main._sync_daily_date()
	var daily := ChallengeCodec.daily_challenge()
	main.active_challenge = daily
	main.start_game()
	var coins_before: int = main.coins
	main.game.score = float(int(daily.silver) + 100)
	main.game.distance = 0.0
	main.game.pickup_coins = 0
	main.game.near = 0
	main.game.finish_run()
	# Record bonus (+25 since best was 0) + bronze (100) + silver (200) = 325
	check(main.daily_tier == 2 and main.coins == coins_before + 325, "Daily challenge must award Bronze+Silver once")
	# Second attempt hitting Silver again must NOT double-pay Bronze/Silver
	var coins_after_first: int = main.coins
	main.active_challenge = daily
	main.start_game()
	main.game.score = float(int(daily.silver) + 50)
	main.game.distance = 0.0
	main.game.finish_run()
	check(main.coins == coins_after_first, "Daily challenge must not double-pay claimed tiers")

	# Duel victory awards +150 once per code_id
	var duel := {"type": "duel", "id": "testduel123", "seed": 12345, "car_index": 0, "score": 1000, "distance": 500, "tod": 0.15, "weather": 0, "name": "БОБ", "end_scroll": 6000.0, "samples": [{"scroll": 0.0, "x_norm": 0.375, "flags": 0}]}
	main.active_challenge = duel
	main.start_game()
	var cb: int = main.coins
	main.game.score = 1500
	main.game.distance = 0.0
	main.game.finish_run()
	check(main.coins == cb + 150 and main.beaten_duels.has("testduel123"), "First duel win must award +150 coins")
	main.active_challenge = duel
	main.start_game()
	var cb2: int = main.coins
	main.game.score = 1600
	main.game.distance = 0.0
	main.game.finish_run()
	check(main.coins == cb2, "Repeating already-beaten duel must not double-pay +150")

	main.free()
