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
	check_brake_squeal()
	check_slingshot_envelope()
	await check_driven_race()
	check_volume_settings()
	print("[audio] buses, assets, 9 engines, rpm model, brake squeal, slingshot envelope, driven race, volume settings: ",
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


func _st(speed: float, brake := false, wet := 0.0, sling := false) -> Dictionary:
	return {"speed": speed, "top": 1100.0, "boost": false, "brake": brake, "overheated": false,
		"draft": 0.0, "wet": wet, "lateral": 0.0, "sling": sling, "grip": 1.0 - wet * 0.3}


# Runs a brake press shaped like game.gd (exponential approach to 0.42x at
# rate k) and returns [peak squeal level, peak squeal dB, peak wet hiss dB,
# seconds the squeal stayed above 0.3].
func _brake_run(ea, k: float, wet: float) -> Array:
	ea.set_car("sedan")
	ea.start()
	var dt := 1.0 / 60.0
	var speed := 1000.0
	for i in range(90):
		ea.update(dt, _st(speed, false, wet))
	var peak := 0.0
	var peak_db := -80.0
	var wet_db := -80.0
	var held := 0.0
	for i in range(90):
		speed = lerpf(speed, 420.0, 1.0 - exp(-dt * k))
		ea.update(dt, _st(speed, k > 0.0, wet))
		peak = maxf(peak, ea.squeal_level)
		peak_db = maxf(peak_db, ea._squeal.volume_db)
		wet_db = maxf(wet_db, ea._skid_wet.volume_db)
		if ea.squeal_level > 0.3:
			held += dt
	ea.stop()
	return [peak, peak_db, wet_db, held]


func check_brake_squeal() -> void:
	var ea = Sfx.engine_audio
	var hard: Array = _brake_run(ea, 5.5, 0.0)
	check(hard[0] > 0.75, "a normal hard stop must squeal strongly (level %.2f)" % hard[0])
	check(hard[1] > -9.0, "dry squeal must be clearly audible (peak %.1f dB)" % hard[1])
	check(hard[3] >= 0.35, "squeal must last through the stop (%.2fs)" % hard[3])
	var light: Array = _brake_run(ea, 1.2, 0.0)
	check(light[0] < hard[0] - 0.2, "lighter braking must squeal less (%.2f vs %.2f)" % [light[0], hard[0]])
	var none: Array = _brake_run(ea, 0.0, 0.0)
	check(none[0] < 0.01, "no brake, no squeal")
	var wet: Array = _brake_run(ea, 5.5, 0.9)
	check(wet[2] > -9.0, "wet braking must hiss audibly (peak %.1f dB)" % wet[2])
	check(wet[1] < hard[1] - 3.0, "on the wet the squeal gives way to hiss")
	print("[audio] squeal hard %.2f/%.1fdB/%.2fs light %.2f wet hiss %.1fdB squeal %.1fdB" % [hard[0], hard[1], hard[3], light[0], wet[2], wet[1]])


func check_slingshot_envelope() -> void:
	var ea = Sfx.engine_audio
	for car in ["sedan", "muscle", "ev"]:
		ea.set_car(car)
		ea.start()
		var dt := 1.0 / 60.0
		var speed := 1000.0
		for i in range(120):
			ea.update(dt, _st(speed))
		var rpm0: float = ea.rpm
		var gear0: int = ea.gear
		var db0: float = ea.last_base_db
		var max_rpm := 0.0
		var max_db := -80.0
		var max_step := 0.0
		var gear_changed := false
		for i in range(51):  # SLINGSHOT_TIME 0.85 s, speed x1.32 at k 5.2
			speed = lerpf(speed, 1320.0, 1.0 - exp(-dt * 5.2))
			var prev: float = ea.rpm
			ea.update(dt, _st(speed, false, 0.0, true))
			max_rpm = maxf(max_rpm, ea.rpm)
			max_db = maxf(max_db, ea.last_base_db)
			max_step = maxf(max_step, absf(ea.rpm - prev) / prev)
			gear_changed = gear_changed or ea.gear != gear0
		for i in range(150):  # back to cruise
			speed = lerpf(speed, 1000.0, 1.0 - exp(-dt * 2.4))
			var prev: float = ea.rpm
			ea.update(dt, _st(speed))
			max_rpm = maxf(max_rpm, ea.rpm)
			max_step = maxf(max_step, absf(ea.rpm - prev) / prev)
		check(max_rpm <= rpm0 * 1.11 + 1.0, "%s slingshot revs must stay modest (%.0f -> %.0f)" % [car, rpm0, max_rpm])
		check(max_rpm >= rpm0 * 1.03, "%s slingshot must still lift the revs" % car)
		check(max_db <= db0 + 1.6, "%s slingshot must not swell the engine (%.1f -> %.1f dB)" % [car, db0, max_db])
		check(not gear_changed, "%s gear holds through the slingshot" % car)
		check(max_step < 0.05, "%s rpm moves smoothly (max step %.3f)" % [car, max_step])
		print("[audio] slingshot %s rpm %.0f->%.0f base %.1f->%.1f dB step %.3f end %.0f" % [car, rpm0, max_rpm, db0, max_db, max_step, ea.rpm])
		check(absf(ea.rpm - rpm0) / rpm0 < 0.06, "%s engine settles back after the slingshot (%.0f vs %.0f)" % [car, ea.rpm, rpm0])
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
