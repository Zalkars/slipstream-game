extends Node

var failures := 0
var turns := 0
var boosts := 0
var undos := 0

func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)

func touch(control: Control, id: int, down: bool, pos := Vector2(40, 40), canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = pos
	event.pressed = down
	event.canceled = canceled
	control._gui_input(event)

func _ready() -> void:
	call_deferred("run")

func run() -> void:
	var game := Game.new()
	add_child(game)
	game.set_process(false)
	game.start_run()
	var zones := ZonesPad.new()
	add_child(zones)
	zones.size = Vector2(720, 260)
	zones.set_process(false)
	zones.lane_left.connect(func(): turns += 1; game.move_lane(-1))
	zones.lane_right.connect(func(): turns += 1; game.move_lane(1))
	zones.brake_changed.connect(game.set_braking)
	zones.lane_undo.connect(func(side: int): undos += 1; game.undo_lane(side))
	var initial_nitro := game.nitro
	for i in range(4):
		touch(zones, 0, true)
		touch(zones, 0, false)
	check(turns == 4 and game.nitro == initial_nitro and not game.boosting, "Fast steering taps must not spend nitro")
	var lane_before := game.lane
	touch(zones, 0, true, Vector2(680, 40))
	check(turns == 5 and game.lane == lane_before + 1, "A zone turns on touch-down, without a buffer delay")
	touch(zones, 1, true)
	check(game.braking and undos == 1 and game.lane == lane_before, "A brake chord takes back the turn of its first thumb")
	touch(zones, 1, false)
	zones._process(0.4)
	touch(zones, 0, false, Vector2(680, 40))
	check(not game.braking and turns == 5 and game.lane == lane_before, "Brake release must not steer")

	var button := NitroButton.new()
	add_child(button)
	button.size = Vector2(148, 148)
	button.tapped.connect(func(): boosts += 1; game.tap_nitro())
	touch(button, 2, true)
	check(boosts == 1 and game.boosting, "Nitro fires on the press, not the release")
	touch(button, 3, true)
	touch(button, 3, false)
	check(boosts == 1 and button._down, "Another finger must not fire nitro again")
	touch(button, 2, false)
	check(boosts == 1, "Releasing the nitro button does not fire it again")
	touch(button, 2, true)
	touch(button, 2, false, Vector2(40, 40), true)
	touch(button, 2, true)
	touch(button, 2, false, Vector2(200, 40))
	check(boosts == 3, "Every press fires once; canceled or outside releases fire nothing")
	touch(button, 2, true)
	button.reset()
	touch(button, 2, false)
	check(boosts == 4 and not button._down, "Reset clears the press without firing again")

	var art = game.race_art
	for car: Dictionary in Cars.LIST:
		check(not art.take(car).is_empty(), "Missing player sprite: " + car.name)
	var catalogue_count := 0
	for sil: String in Game.PALETTE.SILHOUETTES:
		for index in range(Game.TRAFFIC_COLORS.size()):
			for appearance: Dictionary in Game.PALETTE.variants(sil, index):
				check(not art.take(appearance).is_empty(), "Missing catalogue appearance: " + str(appearance))
				catalogue_count += 1
	print("[regression] complete appearance catalogue: ", catalogue_count, " checked")
	var seen_silhouettes: Dictionary = {}
	seed(1729)
	for i in range(4000):
		game.cars.clear()
		game._spawn(false)
		for car: Dictionary in game.cars:
			check(not art.take(car).is_empty(), "Missing traffic sprite: " + str(car))
			seen_silhouettes[str(car.silhouette)] = true
		game.cars.clear()
		game._spawn_rear(game.base_speed)
		for car: Dictionary in game.cars:
			check(not art.take(car).is_empty(), "Missing rear sprite: " + str(car))
			seen_silhouettes[str(car.silhouette)] = true
	for sil: String in Game.PALETTE.SILHOUETTES:
		check(seen_silhouettes.has(sil), "Traffic never spawned silhouette: " + sil)
	for color: Color in Game.TRAFFIC_COLORS:
		check(not art.take({"kind": 0, "color": color}).is_empty(), "Missing tutorial car")
	for sprite: Dictionary in art._cache.values():
		var texture: Texture2D = art._pages[int(sprite.page)]
		check(Rect2(Vector2.ZERO, texture.get_size()).encloses(sprite.region), "Atlas region outside texture")
	check(art._vp == null and art._model == null and art.get_child_count() == 0, "Gameplay must not create 3D bakery")
	var cached_appearance: Dictionary = game._race_sprite(game._player_art)
	var texture_refs: Array = []
	for tex in art._pages:
		texture_refs.append(weakref(tex))
	game.rewind_frames.append(game._snapshot_state())
	game.use_3d_cars = false
	check(art._pages.is_empty() and art._cache.is_empty(), "2D must release atlas ownership")
	for ref: WeakRef in texture_refs:
		check(ref.get_ref() == null, "A cached appearance or snapshot retains an atlas in 2D")
	check(not cached_appearance.has("tex"), "Appearance descriptors must not own textures")
	check(game._race_sprite(Cars.LIST[0]).is_empty(), "2D toggle must retain fallback")
	game.use_3d_cars = true
	check(not game._race_sprite(game._player_art).is_empty(), "Switching back to 3D must restore cached appearances")
	var flat := Game.new()
	flat.use_3d_cars = false
	add_child(flat)
	flat.set_process(false)
	check(flat.race_art._pages.is_empty(), "Starting in 2D must not load atlases")
	flat.free()
	await check_controls_and_tutorial(game, zones, button)
	check_menu_controls()
	check_pass_audio_routing()
	print("[regression] multitouch, pause, tutorial, 8000 traffic spawns, catalogue, atlas release/reload: ", "PASS" if failures == 0 else "FAIL (%d)" % failures)
	if "--benchmark" in OS.get_cmdline_user_args() and failures == 0:
		zones.queue_free()
		button.queue_free()
		Engine.max_fps = 0
		game.set_process(true)
		for enabled in [true, false]:
			game.use_3d_cars = enabled
			seed(1729)
			game.start_run()
			game._rewind_invuln = 10000.0
			var frames: Array = []
			var last := Time.get_ticks_usec()
			for i in range(1800):
				await get_tree().process_frame
				var now := Time.get_ticks_usec()
				if i > 30:
					frames.append((now - last) / 1000.0)
				last = now
			if enabled and "--capture" in OS.get_cmdline_user_args():
				await RenderingServer.frame_post_draw
				get_viewport().get_texture().get_image().save_png(ProjectSettings.globalize_path("res://../.work/race_gameplay.png"))
			frames.sort()
			var total := 0.0
			for ms: float in frames:
				total += ms
			print("[perf] 3D=", enabled, " avg=%.2f p95=%.2f max=%.2f ms" % [total / frames.size(), frames[int(frames.size() * 0.95)], frames.back()])
	get_tree().quit(1 if failures else 0)


func check_menu_controls() -> void:
	var icon := IconButton.new()
	var toggle := ToggleSwitch.new()
	var slider := VolumeSlider.new()
	var controls := Control.new()
	add_child(controls)
	for control in [icon, toggle, slider]:
		controls.add_child(control)
	icon.size = Vector2(76, 76)
	toggle.size = Vector2(116, 58)
	slider.size = Vector2(300, 48)
	var presses := [0]
	icon.pressed.connect(func(): presses[0] += 1)
	touch(icon, 1, true)
	touch(icon, 2, false)
	touch(icon, 1, false, Vector2(40, 40), true)
	check(presses[0] == 0, "Icon must ignore unrelated and canceled releases")
	touch(icon, 1, true)
	touch(icon, 1, false, Vector2(140, 40))
	check(presses[0] == 0, "Icon must ignore releases outside its bounds")
	touch(icon, 1, true)
	touch(icon, 1, false)
	check(presses[0] == 1, "Normal tap must activate icon once")

	toggle.on = false
	touch(toggle, 1, true)
	touch(toggle, 2, true)
	touch(toggle, 2, false)
	touch(toggle, 1, false, Vector2(40, 40), true)
	check(not toggle.on, "Second finger and canceled release must not flip the switch")
	touch(toggle, 1, true)
	touch(toggle, 1, false)
	check(toggle.on, "Normal tap must flip the switch")

	touch(slider, 1, true)
	var first_value := slider.value
	touch(slider, 2, true, Vector2(220, 25))
	touch(slider, 2, false, Vector2(220, 25))
	check(slider.value == first_value and slider._dragging, "Second finger must not take over slider")
	var drag := InputEventScreenDrag.new()
	drag.index = 1
	drag.position = Vector2(120, 25)
	slider._gui_input(drag)
	check(slider.value > first_value, "First finger must keep control of the slider")
	touch(slider, 1, false, Vector2(120, 25), true)
	check(not slider._dragging, "Canceled drag must release the slider")
	controls.free()


func check_pass_audio_routing() -> void:
	# Traffic pass-bys (World), the own car (Engine), weather (Ambient) and UI
	# must all follow the player's SFX volume and mute.
	for bus_name in ["Engine", "World", "Ambient", "UI"]:
		var bus := AudioServer.get_bus_index(bus_name)
		check(bus >= 0, "Audio bus must exist: " + bus_name)
		check(AudioServer.get_bus_send(bus) == &"SFX", "Game audio must use the SFX volume and mute: " + bus_name)
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("SFX")) == &"Master", "SFX must feed Master")
	check(AudioServer.get_bus_send(AudioServer.get_bus_index("Music")) == &"Master", "Music must feed Master")


func swipe_touch(game: Game, id: int, down: bool, pos: Vector2, canceled := false) -> void:
	var event := InputEventScreenTouch.new()
	event.index = id
	event.position = pos
	event.pressed = down
	event.canceled = canceled
	game._unhandled_input(event)


func swipe_drag(game: Game, id: int, pos: Vector2) -> void:
	var event := InputEventScreenDrag.new()
	event.index = id
	event.position = pos
	game._unhandled_input(event)


func check_controls_and_tutorial(game: Game, zones: ZonesPad, button: NitroButton) -> void:
	zones.reset()
	var lane0 := game.lane
	touch(zones, 8, true, Vector2(680, 40))
	touch(zones, 8, false, Vector2(680, 40), true)
	zones._process(0.5)
	check(game.lane == lane0 and zones.touches.is_empty(), "A canceled zone tap takes its turn back")
	touch(zones, 8, true, Vector2(680, 40))
	touch(zones, 9, true)
	touch(zones, 9, false, Vector2(40, 40), true)
	zones._process(0.5)
	touch(zones, 8, false, Vector2(680, 40))
	check(game.lane == lane0 and not game.braking, "A canceled braking finger leaves no turn behind")

	var brake := PadButton.new()
	brake.kind = "brake"
	add_child(brake)
	brake.set_process(false)
	brake.held_changed.connect(game.set_braking)
	touch(brake, 1, true)
	touch(brake, 2, true)
	touch(brake, 2, false)
	check(brake._down and game.braking, "Brake must stay held by the first finger")
	touch(brake, 3, false)
	check(brake._down, "Unknown finger release must not release brake")
	touch(brake, 1, false, Vector2(40, 40), true)
	check(not brake._down and not game.braking, "Canceling the last brake finger must release")

	game.start_run()
	game.control_mode = "swipe"
	swipe_touch(game, 1, true, Vector2(200, 900))
	swipe_touch(game, 2, true, Vector2(200, 1100))
	swipe_drag(game, 1, Vector2(200, 895))
	check(not game.boosting, "Second finger must not change the swipe origin")
	swipe_drag(game, 2, Vector2(200, 700))
	swipe_touch(game, 2, false, Vector2(200, 700))
	check(not game.boosting and game._swipe_touch_id == 1, "Second finger cannot trigger or finish the gesture")
	swipe_drag(game, 1, Vector2(200, 800))
	check(game.boosting, "Owner upward swipe must still trigger nitro")
	swipe_touch(game, 1, false, Vector2(200, 800))
	game.start_run()
	swipe_touch(game, 1, true, Vector2(200, 900))
	swipe_touch(game, 1, false, Vector2(200, 600), true)
	check(not game.boosting, "Canceled swipe must not spend nitro")
	swipe_touch(game, 1, true, Vector2(200, 900))
	swipe_drag(game, 1, Vector2(200, 1000))
	check(game.braking, "Downward swipe must brake")
	swipe_touch(game, 2, false, Vector2(200, 1100))
	check(game.braking, "Other finger release must not release swipe braking")
	swipe_touch(game, 1, false, Vector2(200, 1000))
	check(not game.braking, "Owner release must release swipe braking")
	swipe_touch(game, 1, true, Vector2(200, 900))
	swipe_touch(game, 1, false, Vector2(200, 1000))
	check(not game.braking, "Release-only downward gesture must not leave a stuck brake")

	game.control_mode = "buttons"
	game.set_braking(true)
	game._unhandled_input(InputEventMouseMotion.new())
	check(game.braking, "Unrelated unhandled input must not cancel button braking")
	game.set_braking(false)

	# Exercise the actual Main pause/resume code without loading or saving a profile.
	var main = load("res://scripts/main.gd").new()
	main.game = game
	main.pad_left = PadButton.new()
	main.pad_right = PadButton.new()
	main.pad_right.kind = "right"
	add_child(main.pad_left)
	add_child(main.pad_right)
	main.pad_left.set_process(false)
	main.pad_right.set_process(false)
	main.brake_btn = brake
	main.nitro_btn = button
	main.zones_pad = zones
	main.pause_panel = Control.new()
	add_child(main.pause_panel)
	main.in_game = true
	main.control_mode = "buttons"
	game.control_mode = "buttons"
	game.lane = 0
	main.pad_right.pressed.connect(func(): game.move_lane(1))
	touch(main.pad_right, 4, true)
	main._toggle_pause()
	main.pad_right._process(1.0)
	main._toggle_pause()
	main.pad_right._process(1.0)
	check(game.lane == 1 and not main.pad_right._down, "Resume must not repeat a stale steering press")
	touch(main.pad_right, 4, false)
	main._notification(NOTIFICATION_APPLICATION_FOCUS_OUT)
	check(main.paused and not main.pad_right._down, "Focus loss must clear driving input")

	main.tutorial_panel = Control.new()
	main.tutorial_title = Label.new()
	main.tutorial_text = Label.new()
	main.tutorial_panel.add_child(main.tutorial_title)
	main.tutorial_panel.add_child(main.tutorial_text)
	add_child(main.tutorial_panel)
	main.tutorial_active = true
	main.tutorial_step = 3
	main.tutorial_timer = 1.6
	game.nitro = 0.0
	main._process(10.0)
	check(main.tutorial_timer == 1.6 and game.nitro == 0.0 and not main._nitro_prompted, "Paused tutorial must not advance or refill nitro")
	main._toggle_pause()
	main.control_mode = "zones"
	main._process(0.2)
	check(main._nitro_prompted and game.nitro == 1.0, "Tutorial must resume normally")
	check(not "Дважды" in main.tutorial_text.text and "по центру" in main.tutorial_text.text, "Nitro tutorial must describe the dedicated centre button")
	main._refresh_tutorial_prompt()
	check(not "Дважды" in main.tutorial_text.text, "Refreshed tutorial must not suggest double-tap")
	game.rewinding = true
	var timer: float = main.tutorial_timer
	main._process(2.0)
	check(main.tutorial_timer == timer, "Tutorial must not advance during rewind")
	game.rewinding = false
	# A hidden button must discard fingers even when no release event arrives.
	touch(brake, 1, true)
	brake.hide()
	check(not brake._down, "Hiding controls must release held input")
	main.pad_left.queue_free()
	main.pad_right.queue_free()
	main.pause_panel.queue_free()
	main.tutorial_panel.queue_free()
	brake.queue_free()
	main.free()
	await get_tree().process_frame
