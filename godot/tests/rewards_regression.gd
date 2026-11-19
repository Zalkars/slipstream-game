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
	check_rewind_rewards(game)
	check_slipstream_scores(game)
	check_particle_density(game)
	check_back_and_version(game)
	await check_crash_rewards_and_reset()
	print("[rewards] rewind coins, score/effects, navigation, crash rewards, progress reset: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(1 if failures else 0)

func check_rewind_rewards(game: Game) -> void:
	game.start_run()
	game.pickup_coins = 5
	game.distance = 120.0
	game.near = 2
	game.items = [{"x": game.player_x, "y": game.player_y, "phase": 0.0, "kind": 0}]
	var expected_before := game._coins_total()
	for attempt in range(3):
		game.rewind_frames = [game._snapshot_state()]
		game._move_items(0.0)
		check(game.pickup_coins == 17 and game.items.is_empty(), "Coin must award 12 exactly once before rewind")
		game._begin_rewind()
		game._tick_rewind(0.04)
		check(not game.rewinding and game.running, "Rewind must finish")
		check(game._coins_total() == expected_before and game.items.size() == 1, "Rewind must restore both the coin and its unclaimed reward")
	game._move_items(0.0)
	check(game._coins_total() == expected_before + 12, "Recollecting after repeated rewinds must not duplicate coins")
	game.start_run()
	check(game.pickup_coins == 0, "New run must reset pickup coins")

func check_slipstream_scores(game: Game) -> void:
	for fps in [30, 60, 120, 144]:
		game.start_run()
		game.slip = 0.5
		game.cars = [{"x": game.player_x, "y": game.player_y - game.car_h * 4.25, "w": game.car_w}]
		for frame in range(fps * 10):
			game._update_slipstream(1.0 / fps)
		check(absf(game.bonus - 600.0) < 0.01, "Identical slipstream must award 600 points at %d FPS, got %f" % [fps, game.bonus])
		print("[rewards] slipstream ", fps, " FPS: ", game.bonus)
	game.bonus = 0.0
	game.braking = true
	game._update_slipstream(1.0 / 60.0)
	check(game.bonus == 0.0, "Braking must not award slipstream points")

func particle_count(game: Game, mode: String, fps: int) -> int:
	game.start_run()
	game.speed = 500.0
	game.slip = 0.5 if mode == "slip" else 0.0
	game.rain_amount = 1.0 if mode == "rain" else 0.0
	game.braking = mode == "brake"
	game.overheated = mode == "overheat"
	seed(1729)
	var total := 0
	for frame in range(fps * 10):
		game.particles.clear()
		game._update_fx(1.0 / fps)
		total += game.particles.size()
	return total

func check_particle_density(game: Game) -> void:
	for mode in ["brake", "overheat", "slip", "rain"]:
		var counts: Array = []
		for fps in [30, 60, 120, 144]:
			counts.append(particle_count(game, mode, fps))
		check(counts[0] > 0, "Effect must still emit particles: " + mode)
		check(counts.all(func(count): return count == counts[0]), "Effect density must not depend on FPS: %s %s" % [mode, counts])
		print("[rewards] ", mode, " particles at 30/60/120/144 FPS: ", counts)
	game.start_run()
	game.slip = 0.0
	game.rain_amount = 0.0
	game._update_fx(0.005)
	game.start_run()
	game.braking = true
	game._update_fx(0.012)
	check(game.particles.is_empty(), "New run must not inherit a partial emission interval")

func check_back_and_version(game: Game) -> void:
	game.start_run()
	var main = load("res://tests/main_without_persistence.gd").new()
	main.game = game
	var controls := Node.new()
	add_child(controls)
	main.settings = Control.new()
	main.pause_panel = Control.new()
	main.pad_left = PadButton.new()
	main.pad_right = PadButton.new()
	main.brake_btn = PadButton.new()
	main.nitro_btn = NitroButton.new()
	main.zones_pad = ZonesPad.new()
	for control in [main.settings, main.pause_panel, main.pad_left, main.pad_right, main.brake_btn, main.nitro_btn, main.zones_pad]:
		controls.add_child(control)
	main.settings.visible = true
	main.pause_panel.visible = false
	main.settings_from_pause = true
	main.in_game = true
	main.paused = true
	game.paused = true
	main.tutorial_active = true
	main.tutorial_done = false
	main._on_back()
	check(not main.settings.visible and main.pause_panel.visible, "Back in paused settings must return to pause")
	check(main.tutorial_active and not main.tutorial_done and main.save_calls == 0, "Closing settings must not skip or save completion of a tutorial")
	main._on_back()
	check(not main.paused and not game.paused and not main.pause_panel.visible, "Back from pause must resume the lesson")
	check(main.tutorial_active and main.save_calls == 0, "Resuming must preserve unfinished tutorial")
	main._on_back()
	check(not main.tutorial_active and main.tutorial_done and main.save_calls == 1, "Back in the running lesson must retain the explicit skip behavior")
	check(main.version == str(ProjectSettings.get_setting("application/config/version")), "Menu version must come from project settings")
	controls.free()
	main.free()


func check_crash_rewards_and_reset() -> void:
	Sfx.set_music_enabled(false)
	var main = load("res://tests/main_without_persistence.gd").new()
	main.cars_3d = false
	main.music_on = false
	main.tutorial_done = true
	add_child(main)
	main.game.set_process(false)
	main.start_game()
	main.game.score = 1234
	main.game.distance = 1200.0
	main.game.pickup_coins = 24
	main.game.near = 4
	main.game.finish_run()
	check(main.coins == 477 and main.best == 1234 and main.save_calls == 1,
		"Crash must save coins and record before showing results")
	main._toggle_pause()
	main.show_menu()
	main.start_game()
	await get_tree().create_timer(0.5).timeout
	main.game.score = 100
	main.game.pickup_coins = 12
	main.game.finish_run()
	await get_tree().create_timer(0.65).timeout
	check(not main.result_open and main.save_calls == 2 and main.coins == 489,
		"Earlier result timer must not finish the new run or award coins again")
	await get_tree().create_timer(0.5).timeout
	check(main.result_open and main.result_score.text == "100" and main.save_calls == 2,
		"Only the new result should appear after its own delay")

	main.owned = [0, 8]
	main.selected = 8
	main.start_game()
	main.game.score = 2000
	main.game.pickup_coins = 24
	main._toggle_pause()
	main._show_settings(true)
	main._show_confirm()
	main._do_reset()
	main.game.finish_run()
	check(main.menu.visible and not main.in_game and not main.game.running and main.game.car_index == 0,
		"Reset from pause must discard the old race and car")
	check(main.coins == 300 and main.best == 0 and main.owned == [0] and main.save_calls == 3,
		"Discarded race must not restore the old progress")
	main.free()
