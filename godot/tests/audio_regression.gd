extends Node

# Audio checks that do not need ears: bus layout and routing, every baked asset
# loads (loops flagged as loops), engine data for all nine cars, the rpm/gear
# model, and a driven race through rain, a storm, nitro, braking and a crash
# with traffic voices assigned - without script errors and without touching
# the race RNG.

const BANK := preload("res://scripts/audio/audio_bank.gd")

var failures := 0


func check(ok: bool, message: String) -> void:
	if not ok:
		failures += 1
		push_error(message)


func _ready() -> void:
	call_deferred("run")


func run() -> void:
	check_buses()
	check_assets()
	check_engine_specs()
	await check_driven_race()
	check_volume_settings()
	print("[audio] buses, assets, 9 engines, rpm model, driven race, volume settings: ",
		"PASS" if failures == 0 else "FAIL (%d)" % failures)
	get_tree().quit(1 if failures else 0)


func check_buses() -> void:
	for pair in [["SFX", "Master"], ["Music", "Master"], ["Engine", "SFX"], ["World", "SFX"],
			["Ambient", "SFX"], ["UI", "SFX"]]:
		var idx := AudioServer.get_bus_index(pair[0])
		check(idx >= 0, "bus missing: " + pair[0])
		if idx >= 0:
			check(AudioServer.get_bus_send(idx) == StringName(pair[1]), "bus %s must send to %s" % pair)
	var m := AudioServer.get_bus_index("Master")
	check(AudioServer.get_bus_effect_count(m) >= 2, "Master needs compressor + limiter")
	check(AudioServer.get_bus_effect(m, 0) is AudioEffectCompressor, "Master effect 0 is the compressor")
	for bus in ["World", "Ambient"]:
		var idx := AudioServer.get_bus_index(bus)
		check(AudioServer.get_bus_effect(idx, 0) is AudioEffectLowPassFilter, bus + " needs a low-pass for fog")
		check(AudioServer.get_bus_effect(idx, 1) is AudioEffectReverb, bus + " needs a reverb for echo")


func check_assets() -> void:
	var dirs := ["air", "amb", "brake", "engine", "impact", "nitro", "road", "traffic", "tyre", "ui"]
	var count := 0
	for d in dirs:
		var da := DirAccess.open("res://audio/" + d)
		check(da != null, "audio dir missing: " + d)
		if da == null:
			continue
		for f in da.get_files():
			var name := f.trim_suffix(".import")
			if not name.ends_with(".ogg") or (f.ends_with(".import") and da.file_exists(name)):
				continue
			var s = load("res://audio/%s/%s" % [d, name])
			check(s is AudioStreamOggVorbis, "not an OGG stream: %s/%s" % [d, name])
			if s is AudioStreamOggVorbis:
				check(s.get_length() > 0.05, "empty stream: %s/%s" % [d, name])
				count += 1
	check(count >= 110, "expected the full asset set, found %d" % count)
	for loop_asset in ["engine/muscle_1_on", "tyre/roll_wet", "amb/rain_heavy", "nitro/sustain", "brake/squeal_dry"]:
		var s := BANK.stream(loop_asset, true) as AudioStreamOggVorbis
		check(s != null and s.loop, "loop flag missing: " + loop_asset)


func check_engine_specs() -> void:
	var specs := BANK.engines()
	for car in Cars.LIST:
		var sil: String = car.silhouette
		check(specs.has(sil), "no engine for car " + str(car.name))
		if not specs.has(sil):
			continue
		var refs: Array = specs[sil].refs
		check(refs.size() == 3 and float(refs[0]) < float(refs[1]) and float(refs[1]) < float(refs[2]),
			"engine refs must rise: " + sil)
		for i in range(3):
			for tag in ["on", "off"]:
				check(BANK.stream("engine/%s_%d_%s" % [sil, i, tag], true) != null, "missing loop %s_%d_%s" % [sil, i, tag])
	# Rpm climbs with speed inside a gear and the gear rises with speed.
	var ea = Sfx.engine_audio
	ea.set_car("muscle")
	ea.start()
	var prev_gear := 0
	for step in range(1, 40):
		var st := {"speed": 50.0 * step, "top": 1100.0, "boost": false, "brake": false,
			"overheated": false, "draft": 0.0, "wet": 0.0, "lateral": 0.0, "crashed": false}
		for k in range(20):
			ea.update(1.0 / 60.0, st)
		check(ea.gear >= prev_gear, "gear must not drop while accelerating (%d -> %d)" % [prev_gear, ea.gear])
		prev_gear = ea.gear
		check(ea.rpm > 500.0 and ea.rpm <= float(ea.spec.redline) * 1.13, "rpm out of range: %f" % ea.rpm)
	check(prev_gear >= 5, "high speed must reach a high gear, got %d" % prev_gear)
	ea.stop()


func check_driven_race() -> void:
	var game := Game.new()
	game.use_3d_cars = false
	add_child(game)
	await get_tree().process_frame
	check(Sfx._game() == game, "game must bind itself to Sfx")
	game.start_run()
	Sfx.play_engine()
	check(Sfx.engine_audio.spec_name == game.player_silhouette, "engine follows the selected car")
	# Force weather and traffic around us.
	game.rain_amount = 0.9
	game.storm_amount = 0.6
	game.wetness = 0.8
	game.fog_amount = 0.5
	game.lane = 0
	var assigned := 0
	for frame in range(240):
		if frame == 20:
			game.boosting = true
		if frame == 80:
			game.boosting = false
		if frame == 100:
			game.braking = true
		if frame == 160:
			game.braking = false
		if frame == 30:
			Sfx.thunder()
			Sfx.bump()
			Sfx.scrape(0.7, -0.5)
			Sfx.set_overhead(0.8)
		game.cars = [_traffic(game, -400.0 + frame * 3.0, 2, 1), _traffic(game, 300.0, 4, 2), _traffic(game, -700.0, 0, 3)]
		Sfx.update_engine(game.speed, game.boosting, game.braking, false, 0.3)
		Sfx.set_rain_intensity(game.rain_amount)
		Sfx.set_weather(game.wetness, game.wind, game.storm_amount)
		await get_tree().process_frame
		var n := 0
		for v in Sfx.traffic_audio._voices:
			if v.car != null:
				n += 1
		assigned = maxi(assigned, n)
	check(assigned >= 2, "traffic voices must follow nearby cars (got %d)" % assigned)
	Sfx.crash()
	Sfx.stop_engine()
	await get_tree().process_frame
	for v in Sfx.traffic_audio._voices:
		check(v.car == null, "voices released after the run")
	for p in Sfx.engine_audio._loops:
		check(not p.playing, "engine loops stop with the engine")
	# Every legacy one-shot still exists and plays without errors.
	for fn in ["click", "record", "pickup_coin", "pickup_nitro", "pickup", "boost_burst", "cut_in",
			"brake_overheat", "rewind_start", "rewind_stop", "slingshot_ready", "slingshot_snap",
			"ram_hit", "radar_ok", "shield_trigger", "duel_win", "whoosh"]:
		Sfx.call(fn)
	Sfx.pass_by(0.6, 0.8)
	Sfx.impact(0.9, 0.3)
	game.queue_free()
	await get_tree().process_frame


func check_volume_settings() -> void:
	var sfx := AudioServer.get_bus_index("SFX")
	Sfx.set_sfx_volume(0.5)
	check(absf(AudioServer.get_bus_volume_db(sfx) - linear_to_db(0.5)) < 0.01, "SFX slider drives the SFX bus")
	Sfx.set_sfx_enabled(false)
	check(AudioServer.is_bus_mute(sfx), "sound switch mutes SFX")
	Sfx.set_sfx_enabled(true)
	check(not AudioServer.is_bus_mute(sfx), "sound switch unmutes SFX")
	var mus := AudioServer.get_bus_index("Music")
	Sfx.set_music_volume(0.3)
	check(absf(AudioServer.get_bus_volume_db(mus) - linear_to_db(0.3)) < 0.01, "music slider drives the Music bus")
	Sfx.set_music_enabled(false)
	check(AudioServer.is_bus_mute(mus), "music switch mutes Music")
	Sfx.set_sfx_volume(0.9)
	Sfx.set_music_volume(0.75)


func _traffic(game: Game, y_off: float, kind: int, lane_i: int) -> Dictionary:
	return {
		"lane": lane_i, "x": game._lane_x(lane_i), "y": game.player_y + y_off,
		"w": game.car_w, "h": game.car_h, "kind": kind, "color": Color(0.5, 0.5, 0.5),
		"rel": 0.7, "cur_speed": game.speed * 0.7, "braking": false, "demo_speed": 0.0, "near": true,
	}
