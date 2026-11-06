extends Node

# All audio is synthesised at runtime into 16-bit PCM (no audio assets).
# Separate SFX / Music buses let the player mute them independently.
#
# The mix is built from a few continuous layers (engine, tyre roar, wind,
# nitro, brake squeal, overheated brakes) plus one-shot impacts and UI sounds.
# Everything is procedural, so it stays tiny in the export and can be tuned
# from code without hunting for samples.

const RATE := 22050
const TBL := 2048
const GEAR_SPEEDS := [0.0, 250.0, 445.0, 650.0, 875.0, 1110.0, 1460.0]

var engine: AudioStreamPlayer
var road: AudioStreamPlayer
var wind: AudioStreamPlayer
var nitro_snd: AudioStreamPlayer
var crash_snd: AudioStreamPlayer
var bump_snd: AudioStreamPlayer
var thunder_snd: AudioStreamPlayer
var whoosh_snd: AudioStreamPlayer
var click_snd: AudioStreamPlayer
var chime_snd: AudioStreamPlayer
var coin_snd: AudioStreamPlayer
var pickup_snd: AudioStreamPlayer
var boost_snd: AudioStreamPlayer
var brake_snd: AudioStreamPlayer
var overheat_snd: AudioStreamPlayer
var cutin_snd: AudioStreamPlayer
var rewind_snd: AudioStreamPlayer
var slip_snd: AudioStreamPlayer
var rain_snd: AudioStreamPlayer
var music_player: AudioStreamPlayer

var sfx_bus := 0
var music_bus := 0
var sfx_on := true
var music_on := true
var muted := false
var sfx_volume := 0.9
var music_volume := 0.75

var _engine_on := false
var _boost := false
var _braking := false
var _overheated := false
var _rewinding := false
var _paused := false
var _slip := 0.0
var _last_speed := 0.0
var _gear := 0
var _shift_t := 0.0
var _shift_dir := 0.0

var _music_buf := PackedFloat32Array()
var _music_task := -1
var _music_busy := false


func _ready() -> void:
	_setup_buses()
	set_process(true)
	engine = _player(_make_engine(), -18.0)
	road = _player(_make_road(), -60.0)
	wind = _player(_make_wind(), -28.0)
	nitro_snd = _player(_make_nitro(), -60.0)
	brake_snd = _player(_make_brake(), -60.0)
	overheat_snd = _player(_make_overheat(), -60.0)
	crash_snd = _player(_make_crash(), -4.0)
	bump_snd = _player(_make_bump(), -8.0)
	thunder_snd = _player(_make_thunder(), -8.0)
	whoosh_snd = _player(_make_whoosh(), -11.0)
	click_snd = _player(_make_click(), -18.0)
	chime_snd = _player(_make_chime(), -10.0)
	coin_snd = _player(_make_coin(), -13.0)
	pickup_snd = _player(_make_pickup(), -12.0)
	boost_snd = _player(_make_boost(), -9.0)
	cutin_snd = _player(_make_cutin(), -10.0)
	rewind_snd = _player(_make_rewind(), -9.0)
	slip_snd = _player(_make_slipstream(), -60.0)
	rain_snd = _player(_make_rain(), -60.0)

	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.volume_db = -19.0
	add_child(music_player)


func _setup_buses() -> void:
	for bus_name in ["SFX", "Music"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var idx := AudioServer.bus_count - 1
			AudioServer.set_bus_name(idx, bus_name)
			AudioServer.set_bus_send(idx, "Master")
	sfx_bus = AudioServer.get_bus_index("SFX")
	music_bus = AudioServer.get_bus_index("Music")


func _player(stream: AudioStream, vol: float, bus := "SFX") -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = vol
	p.bus = bus
	add_child(p)
	return p


# --- settings ---------------------------------------------------------------

func set_sfx_enabled(on: bool) -> void:
	sfx_on = on
	muted = not on
	if sfx_bus < 0 or sfx_bus >= AudioServer.bus_count:
		sfx_bus = AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0 and sfx_bus < AudioServer.bus_count:
		AudioServer.set_bus_mute(sfx_bus, not on)
		if on:
			AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(maxf(sfx_volume, 0.0001)))


func set_sfx_volume(v: float) -> void:
	sfx_volume = clampf(v, 0.0, 1.0)
	if sfx_bus < 0 or sfx_bus >= AudioServer.bus_count:
		sfx_bus = AudioServer.get_bus_index("SFX")
	if sfx_bus >= 0 and sfx_bus < AudioServer.bus_count:
		AudioServer.set_bus_volume_db(sfx_bus, linear_to_db(maxf(sfx_volume, 0.0001)))


func set_music_enabled(on: bool) -> void:
	music_on = on
	if music_bus < 0 or music_bus >= AudioServer.bus_count:
		music_bus = AudioServer.get_bus_index("Music")
	if music_bus >= 0 and music_bus < AudioServer.bus_count:
		AudioServer.set_bus_mute(music_bus, not on)
		if on:
			AudioServer.set_bus_volume_db(music_bus, linear_to_db(maxf(music_volume, 0.0001)))
	if on:
		play_music()
	elif music_player != null:
		music_player.stop()


func set_music_volume(v: float) -> void:
	music_volume = clampf(v, 0.0, 1.0)
	if music_bus < 0 or music_bus >= AudioServer.bus_count:
		music_bus = AudioServer.get_bus_index("Music")
	if music_bus >= 0 and music_bus < AudioServer.bus_count:
		AudioServer.set_bus_volume_db(music_bus, linear_to_db(maxf(music_volume, 0.0001)))


func set_muted(m: bool) -> void:
	set_sfx_enabled(not m)


func play_music() -> void:
	if not music_on:
		return
	if music_player.stream == null:
		_start_music_build()
		return
	if not music_player.playing:
		music_player.volume_db = -30.0 if _paused else -19.0
		music_player.play()


func _start_music_build() -> void:
	if _music_busy:
		return
	_music_busy = true
	_music_task = WorkerThreadPool.add_task(_music_worker, false, "SLIPSTREAM music")


func _music_worker() -> void:
	_music_buf = _render_music_loop()


func _exit_tree() -> void:
	if _music_task >= 0:
		WorkerThreadPool.wait_for_task_completion(_music_task)
		_music_task = -1
		_music_busy = false


func _process(_delta: float) -> void:
	if not _music_busy or _music_task < 0:
		return
	if not WorkerThreadPool.is_task_completed(_music_task):
		return
	WorkerThreadPool.wait_for_task_completion(_music_task)
	_music_task = -1
	_music_busy = false
	music_player.stream = _wav(_music_buf, true)
	_music_buf = PackedFloat32Array()
	if music_on and not music_player.playing:
		music_player.volume_db = -30.0 if _paused else -19.0
		music_player.play()


func stop_music() -> void:
	if music_player != null:
		music_player.stop()


# --- engine loop ------------------------------------------------------------

func play_engine() -> void:
	if _engine_on:
		return
	_engine_on = true
	_boost = false
	_braking = false
	_overheated = false
	_rewinding = false
	_paused = false
	_slip = 0.0
	_gear = 0
	_shift_t = 0.0
	engine.volume_db = -18.0
	engine.pitch_scale = 0.86
	road.volume_db = -60.0
	wind.volume_db = -30.0
	nitro_snd.volume_db = -60.0
	brake_snd.volume_db = -60.0
	overheat_snd.volume_db = -60.0
	slip_snd.volume_db = -60.0
	rain_snd.volume_db = -60.0
	engine.play()
	road.play()
	wind.play()
	nitro_snd.play()
	brake_snd.play()
	overheat_snd.play()
	slip_snd.play()
	rain_snd.play()


func stop_engine() -> void:
	_engine_on = false
	_braking = false
	_overheated = false
	_rewinding = false
	engine.stop()
	road.stop()
	wind.stop()
	nitro_snd.stop()
	brake_snd.stop()
	overheat_snd.stop()
	slip_snd.stop()
	rain_snd.stop()


func set_paused(p: bool) -> void:
	_paused = p
	if music_player != null and music_player.playing:
		music_player.volume_db = -30.0 if p else -19.0
	if not _engine_on:
		return
	if p:
		engine.volume_db = -42.0
		road.volume_db = -60.0
		wind.volume_db = -46.0
		nitro_snd.volume_db = -60.0
		brake_snd.volume_db = -60.0
		overheat_snd.volume_db = -60.0
	else:
		update_engine(_last_speed, _boost, _braking, _overheated, _slip)


func _speed_ratio(px_speed: float) -> float:
	return clampf((px_speed - 380.0) / 900.0, 0.0, 1.0)


func _gear_rpm(px_speed: float) -> Array:
	var g := 0
	for i in range(GEAR_SPEEDS.size() - 1):
		if px_speed >= float(GEAR_SPEEDS[i + 1]):
			g = i + 1
	var lo := float(GEAR_SPEEDS[clampi(g, 0, GEAR_SPEEDS.size() - 1)])
	var hi := float(GEAR_SPEEDS[clampi(g + 1, 0, GEAR_SPEEDS.size() - 1)])
	var rpm := clampf((px_speed - lo) / maxf(1.0, hi - lo), 0.0, 1.0)
	return [g, rpm]


func update_engine(px_speed: float, boost: bool, is_braking := false, overheated := false, slip := 0.0) -> void:
	if not _engine_on:
		return
	_last_speed = px_speed
	_boost = boost
	_braking = is_braking
	_overheated = overheated
	_slip = clampf(slip, 0.0, 1.0)
	if _paused:
		return
	if _rewinding:
		engine.volume_db = lerpf(engine.volume_db, -28.0, 0.20)
		road.volume_db = lerpf(road.volume_db, -38.0, 0.20)
		wind.volume_db = lerpf(wind.volume_db, -40.0, 0.20)
		nitro_snd.volume_db = lerpf(nitro_snd.volume_db, -60.0, 0.20)
		brake_snd.volume_db = lerpf(brake_snd.volume_db, -60.0, 0.20)
		overheat_snd.volume_db = lerpf(overheat_snd.volume_db, -60.0, 0.20)
		return

	var ratio := _speed_ratio(px_speed)
	var gear_data := _gear_rpm(px_speed)
	var gear := int(gear_data[0])
	var rpm := float(gear_data[1])
	if gear != _gear:
		_shift_dir = 1.0 if gear > _gear else -1.0
		_shift_t = 0.13
		_gear = gear
	if _shift_t > 0.0:
		_shift_t = maxf(0.0, _shift_t - get_process_delta_time())

	# Engine note follows rpm inside the gear, not just absolute speed.
	var pitch := 0.70 + rpm * 0.72 + ratio * 0.08
	if boost:
		pitch += 0.10
	if _shift_t > 0.0:
		pitch -= _shift_dir * 0.07 * (_shift_t / 0.13)
	engine.pitch_scale = clampf(pitch, 0.58, 1.92)
	var shift_dip := (0.30 * (_shift_t / 0.13)) if _shift_t > 0.0 else 0.0
	engine.volume_db = -17.0 + ratio * 5.0 + (2.0 if boost else 0.0) - shift_dip

	# Tyre roar and wind grow with speed cleanly.
	road.volume_db = -34.0 + ratio * 16.0 + (1.5 if boost else 0.0)
	road.pitch_scale = 0.92 + ratio * 0.30
	wind.volume_db = -29.0 + ratio * 11.0 + (2.0 if boost else 0.0)
	wind.pitch_scale = 0.88 + ratio * 0.20

	nitro_snd.volume_db = lerpf(nitro_snd.volume_db, -12.0 if boost else -60.0, 0.30)
	nitro_snd.pitch_scale = 0.96 + ratio * 0.16
	overheat_snd.volume_db = lerpf(overheat_snd.volume_db, -17.0 if _overheated else -60.0, 0.20)
	slip_snd.volume_db = -60.0

	if is_braking and px_speed > 100.0 and not _overheated:
		var k := clampf(px_speed / 1000.0, 0.30, 1.05)
		brake_snd.volume_db = lerpf(brake_snd.volume_db, -12.0 - (1.0 - k) * 3.0, 0.32)
		brake_snd.pitch_scale = 0.88 + k * 0.30
	else:
		brake_snd.volume_db = lerpf(brake_snd.volume_db, -60.0, 0.24)


func set_rain_intensity(amt: float) -> void:
	if rain_snd == null:
		return
	var a := clampf(amt, 0.0, 1.0)
	if a > 0.01:
		rain_snd.volume_db = -32.0 + a * 15.0
		rain_snd.pitch_scale = 0.95 + a * 0.15
	else:
		rain_snd.volume_db = -60.0


# --- one-shots --------------------------------------------------------------

func crash() -> void:
	crash_snd.play()


func thunder() -> void:
	if thunder_snd != null:
		thunder_snd.pitch_scale = randf_range(0.82, 1.05)
		thunder_snd.volume_db = -8.0 + randf_range(-2.0, 1.5)
		thunder_snd.play()


func bump() -> void:
	if bump_snd != null:
		bump_snd.play()


func whoosh(pan_side := 0.0) -> void:
	whoosh_snd.volume_db = -11.0 - absf(pan_side) * 3.0
	whoosh_snd.play()


func click() -> void:
	click_snd.play()


func record() -> void:
	chime_snd.play()


func pickup_coin() -> void:
	coin_snd.play()


func pickup_nitro() -> void:
	pickup_snd.play()


func pickup() -> void:
	pickup_snd.play()


func boost_burst() -> void:
	boost_snd.play()


func cut_in() -> void:
	whoosh_snd.play()
	cutin_snd.play()


func brake_overheat() -> void:
	overheat_snd.play()
	crash_snd.volume_db = -9.0
	crash_snd.play()
	crash_snd.volume_db = -4.0


func rewind_start() -> void:
	_rewinding = true
	rewind_snd.play()


func rewind_stop() -> void:
	_rewinding = false


# --- synthesis helpers ------------------------------------------------------

func _wav(f: PackedFloat32Array, looped: bool) -> AudioStreamWAV:
	var data := PackedByteArray()
	data.resize(f.size() * 2)
	for i in range(f.size()):
		data.encode_s16(i * 2, int(clampf(f[i], -1.0, 1.0) * 32000.0))
	var w := AudioStreamWAV.new()
	w.format = AudioStreamWAV.FORMAT_16_BITS
	w.mix_rate = RATE
	w.stereo = false
	w.data = data
	if looped:
		w.loop_mode = AudioStreamWAV.LOOP_FORWARD
		w.loop_begin = 0
		w.loop_end = f.size()
	return w


func _loop_wav(f: PackedFloat32Array, loop_len: int, fade: int) -> AudioStreamWAV:
	return _wav(_loop_samples(f, loop_len, fade), true)


static func _loop_samples(f: PackedFloat32Array, loop_len: int, fade: int) -> PackedFloat32Array:
	for i in range(fade):
		var a := float(i) / float(fade)
		f[i] = f[i] * a + f[loop_len + i] * (1.0 - a)
	var out := PackedFloat32Array()
	out.resize(loop_len)
	for i in range(loop_len):
		out[i] = f[i]
	return out


static func _soft(v: float) -> float:
	return tanh(v * 1.45) * 0.82


func _make_engine() -> AudioStreamWAV:
	var loop_len := RATE
	var fade := 3000
	var n := loop_len + fade
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in range(n):
		var tt := float(i) / float(RATE)
		var p := TAU * tt
		# Rich combustion cylinder firing pulses (42 Hz base + strong harmonics)
		var v := 0.0
		v += sin(p * 42.0) * 0.44
		v += sin(p * 84.0 + 0.3) * 0.34
		v += sin(p * 126.0) * 0.22
		v += sin(p * 168.0 + 0.5) * 0.16
		v += sin(p * 252.0) * 0.09
		v += sin(p * 336.0) * 0.05
		# Sub-bass exhaust thud
		v += sin(p * 21.0) * 0.22
		# Subtle non-linear cylinder pressure wave shaping
		v += v * v * 0.14
		# Intake manifold acoustic rumble
		var raw := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.090)
		lp2 = lerpf(lp2, raw, 0.015)
		v += (lp - lp2 * 0.55) * 0.28
		# Turbocharger compressor spool whistle
		var turbo := sin(TAU * (1480.0 + 120.0 * sin(p * 7.0)) * tt) * 0.038
		v += turbo
		var throb := 0.80 + 0.20 * (0.5 + 0.5 * sin(p * 21.0))
		f[i] = _soft(v * throb * 1.35)
	return _loop_wav(f, loop_len, fade)


func _make_road() -> AudioStreamWAV:
	var loop_len := int(RATE * 1.5)
	var fade := 4000
	var n := loop_len + fade
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var lp3 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 2024
	for i in range(n):
		var tt := float(i) / float(RATE)
		var raw := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.14)
		lp2 = lerpf(lp2, raw, 0.020)
		lp3 = lerpf(lp3, raw, 0.045)
		var pavement := (lp - lp2 * 0.65) * 0.90 + lp3 * 0.35
		# Highway expansion joint cadence ("ba-dum ... ba-dum")
		var seam := 0.0
		var phase := fposmod(tt * 6.5, 1.0)
		if phase < 0.06:
			seam = sin(TAU * 52.0 * tt) * exp(-28.0 * phase) * 0.22
		var rumble := sin(TAU * 34.0 * tt) * 0.08
		f[i] = _soft(pavement * 1.10 + rumble + seam)
	return _loop_wav(f, loop_len, fade)


func _make_wind() -> AudioStreamWAV:
	var loop_len := RATE * 2
	var fade := 5000
	var n := loop_len + fade
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in range(n):
		var tt := float(i) / float(RATE)
		var raw := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.065)
		lp2 = lerpf(lp2, lp, 0.012)
		var air := lp - lp2 * 0.75
		var gust := 0.82 + 0.18 * sin(TAU * 0.35 * tt) + 0.08 * sin(TAU * 2.1 * tt)
		f[i] = _soft(air * 2.4 * gust)
	return _loop_wav(f, loop_len, fade)


func _make_nitro() -> AudioStreamWAV:
	var loop_len := RATE
	var fade := 3500
	var n := loop_len + fade
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var lp3 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 9191
	for i in range(n):
		var tt := float(i) / float(RATE)
		var raw := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.32)
		lp2 = lerpf(lp2, lp, 0.035)
		lp3 = lerpf(lp3, raw, 0.070)
		var plasma := lp - lp2 * 0.60
		var fiery_roar := sin(TAU * 54.0 * tt) * 0.18 + sin(TAU * 27.0 * tt) * 0.12
		var turbine := sin(TAU * (1950.0 + 80.0 * sin(TAU * 8.0 * tt)) * tt) * 0.065
		var flutter := 0.84 + 0.16 * sin(TAU * 36.0 * tt)
		f[i] = _soft(((plasma + lp3 * 0.28) * 1.30 + fiery_roar + turbine) * flutter)
	return _loop_wav(f, loop_len, fade)


func _make_brake() -> AudioStreamWAV:
	var loop_len := int(RATE * 1.2)
	var fade := 3000
	var n := loop_len + fade
	var f := PackedFloat32Array()
	f.resize(n)
	var low := 0.0
	var band := 0.0
	var low2 := 0.0
	var band2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 8841
	for i in range(n):
		var tt := float(i) / float(RATE)
		var raw := rng.randf_range(-1.0, 1.0)
		# ABS pulsating cadence (13.5 Hz)
		var abs_mod := 0.76 + 0.24 * sin(TAU * 13.5 * tt)
		# Tire scrub friction band (520 Hz)
		var fc := 520.0 + sin(TAU * 11.0 * tt) * 80.0
		var fcoef := 2.0 * sin(PI * fc / float(RATE))
		low += fcoef * band
		var high := raw - low - 1.1 * band
		band += fcoef * high
		# Brake pad friction bite (1450 Hz) - pleasant mechanical friction, not piercing squeak
		var fc2 := 1450.0 + sin(TAU * 17.0 * tt) * 140.0
		var fcoef2 := 2.0 * sin(PI * fc2 / float(RATE))
		low2 += fcoef2 * band2
		var high2 := raw - low2 - 1.4 * band2
		band2 += fcoef2 * high2
		# Low frequency tire tearing on tarmac (95 Hz)
		var tear := sin(TAU * 95.0 * tt) * 0.14 + sin(TAU * 48.0 * tt) * 0.08
		var scrub := (band * 0.52 + band2 * 0.26 + tear) * abs_mod
		f[i] = _soft(scrub * 1.25)
	return _loop_wav(f, loop_len, fade)


func _make_overheat() -> AudioStreamWAV:
	var loop_len := int(RATE * 1.1)
	var fade := 3000
	var n := loop_len + fade
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 613
	for i in range(n):
		var tt := float(i) / float(RATE)
		var raw := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.45)
		lp2 = lerpf(lp2, raw, 0.08)
		var steam := lp - lp2 * 0.85
		# Metal stress clicks
		var ping := 0.0
		var ph := fposmod(tt * 5.0, 1.0)
		if ph < 0.08:
			ping = sin(TAU * 2400.0 * tt) * exp(-30.0 * ph) * 0.15
		# Subtle heat alarm warning beep
		var beep := 0.0
		var b_ph := fposmod(tt * 3.5, 1.0)
		if b_ph < 0.35:
			beep = sin(TAU * 880.0 * tt) * 0.06
		f[i] = _soft(steam * 0.85 + ping + beep)
	return _loop_wav(f, loop_len, fade)


func _make_crash() -> AudioStreamWAV:
	var n := int(RATE * 1.30)
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var hp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for i in range(n):
		var tt := float(i) / float(RATE)
		var env := exp(-4.2 * tt)
		var noise := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.28)
		hp = noise - lp
		# Heavy sub-bass impact thud (40 Hz shockwave)
		var thump := sin(TAU * 40.0 * tt) * exp(-4.8 * tt) * 0.75
		var sub := sin(TAU * 24.0 * tt) * exp(-3.8 * tt) * 0.40
		# Buckling sheet metal & frame crunch
		var crunch := sin(TAU * 165.0 * tt + sin(TAU * 35.0 * tt) * 2.0) * exp(-9.0 * tt) * 0.42
		var metal := sin(TAU * 840.0 * tt) * exp(-13.0 * tt) * 0.16
		# Tempered safety glass shattering
		var glass := hp * exp(-8.0 * tt) * 0.36
		# Cascading secondary debris
		var debris := 0.0
		if tt > 0.12:
			var t2 := tt - 0.12
			debris = hp * exp(-4.5 * t2) * 0.18 * (0.5 + 0.5 * sin(TAU * 26.0 * t2))
		f[i] = _soft(thump + sub + crunch + metal + glass + debris + lp * 0.90 * env)
	return _wav(f, false)


func _make_thunder() -> AudioStreamWAV:
	var n := int(RATE * 3.8)
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var lp3 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 7719
	for i in range(n):
		var tt := float(i) / float(RATE)
		var raw := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.030)
		lp2 = lerpf(lp2, raw, 0.0035)
		lp3 = lerpf(lp3, raw, 0.16)
		var env := exp(-tt * 1.05) * (1.0 - exp(-tt * 26.0))
		var roll := 0.62 + 0.38 * (0.5 + 0.5 * sin(TAU * 1.35 * tt + sin(TAU * 0.47 * tt) * 2.4))
		var rumble := (lp - lp2 * 0.62) * 1.05 + lp3 * 0.12
		var crack := 0.0
		if tt < 0.14:
			crack = sin(TAU * (110.0 + 70.0 * tt) * tt) * exp(-tt * 19.0) * 0.42
		f[i] = _soft((rumble * roll + crack) * env * 2.05)
	return _wav(f, false)


func _make_bump() -> AudioStreamWAV:
	var n := int(RATE * 0.24)
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 412
	for i in range(n):
		var tt := float(i) / float(RATE)
		var noise := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, noise, 0.35)
		# Low punchy bumper thud (pitch drops from 72Hz to 38Hz)
		var freq := lerpf(72.0, 38.0, minf(tt * 15.0, 1.0))
		var thud := sin(TAU * freq * tt) * exp(-12.0 * tt) * 0.85
		# Snappy plastic bumper contact slap
		var slap := lp * exp(-28.0 * tt) * 0.45
		# Frame vibration
		var vibe := sin(TAU * 190.0 * tt) * exp(-22.0 * tt) * 0.20
		f[i] = _soft(thud + slap + vibe)
	return _wav(f, false)


func _make_whoosh() -> AudioStreamWAV:
	var n := int(RATE * 0.52)
	var f := PackedFloat32Array()
	f.resize(n)
	var low := 0.0
	var band := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	for i in range(n):
		var tt := float(i) / float(RATE)
		var k := clampf(tt / 0.52, 0.0, 1.0)
		var env := sin(PI * k)
		env = env * env * env
		var raw := rng.randf_range(-1.0, 1.0)
		# Doppler pitch sweep
		var fc := lerpf(240.0, 2900.0, sin(k * PI * 0.85))
		var fcoef := 2.0 * sin(PI * fc / float(RATE))
		low += fcoef * band
		var high := raw - low - 0.85 * band
		band += fcoef * high
		f[i] = _soft((band * 3.2 + high * 0.25) * env)
	return _wav(f, false)


func _make_click() -> AudioStreamWAV:
	var n := int(RATE * 0.06)
	var f := PackedFloat32Array()
	f.resize(n)
	for i in range(n):
		var tt := float(i) / float(RATE)
		# Tactile mechanical click: soft wooden transient + gentle snap
		var env := exp(-65.0 * tt)
		var body := sin(TAU * 120.0 * tt) * 0.35
		var snap := sin(TAU * 1420.0 * tt) * 0.25 + sin(TAU * 2240.0 * tt) * 0.10
		f[i] = (body + snap) * env
	return _wav(f, false)


func _make_chime() -> AudioStreamWAV:
	var n := int(RATE * 1.25)
	var f := PackedFloat32Array()
	f.resize(n)
	var notes := [1046.50, 1318.51, 1567.98, 2093.00]
	for i in range(n):
		var tt := float(i) / float(RATE)
		var a := 0.0
		for j in range(notes.size()):
			var start := float(j) * 0.09
			if tt < start:
				continue
			var t2 := tt - start
			var fr: float = notes[j]
			a += sin(TAU * fr * t2) * exp(-4.2 * t2) * 0.28
			a += sin(TAU * fr * 2.0 * t2) * exp(-6.5 * t2) * 0.10
			a += sin(TAU * fr * 3.0 * t2) * exp(-9.5 * t2) * 0.04
		f[i] = _soft(a * 1.20)
	return _wav(f, false)


func _make_coin() -> AudioStreamWAV:
	var n := int(RATE * 0.28)
	var f := PackedFloat32Array()
	f.resize(n)
	for i in range(n):
		var tt := float(i) / float(RATE)
		# Classic arcade crystalline double-ping (A6 1760 Hz -> E7 2637 Hz)
		var a := sin(TAU * 1760.0 * tt) * exp(-15.0 * tt) * 0.40
		a += sin(TAU * 3520.0 * tt) * exp(-24.0 * tt) * 0.12
		if tt > 0.045:
			var t2 := tt - 0.045
			a += sin(TAU * 2637.0 * t2) * exp(-12.0 * t2) * 0.48
			a += sin(TAU * 5274.0 * t2) * exp(-20.0 * t2) * 0.14
		f[i] = _soft(a * 1.15)
	return _wav(f, false)


func _make_pickup() -> AudioStreamWAV:
	var n := int(RATE * 0.45)
	var f := PackedFloat32Array()
	f.resize(n)
	var ph := 0.0
	for i in range(n):
		var tt := float(i) / float(RATE)
		var k := clampf(tt / 0.45, 0.0, 1.0)
		var fr := lerpf(380.0, 1480.0, k * k)
		ph += TAU * fr / float(RATE)
		var env := sin(PI * k)
		env = env * env
		var trem := 0.85 + 0.15 * sin(TAU * 28.0 * tt)
		var harm := sin(ph) * 0.48 + sin(ph * 2.0) * 0.18 + sin(ph * 4.0) * 0.06
		f[i] = _soft(harm * env * trem * 1.25)
	return _wav(f, false)


func _make_boost() -> AudioStreamWAV:
	var n := int(RATE * 0.90)
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for i in range(n):
		var tt := float(i) / float(RATE)
		var k := clampf(tt / 0.90, 0.0, 1.0)
		var env := sin(PI * k)
		env = env * env
		# Concussive explosive sub-bass slam
		var sub := sin(TAU * lerpf(68.0, 32.0, k) * tt) * exp(-4.5 * tt) * 0.65
		# Ignition crackle & jet rush
		var raw := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, lerpf(0.12, 0.52, k))
		lp2 = lerpf(lp2, lp, 0.040)
		var hiss := (lp - lp2) * 2.6
		ph += TAU * lerpf(650.0, 2100.0, k * k) / float(RATE)
		var turbine := sin(ph) * 0.14
		f[i] = _soft((sub + (hiss + turbine) * env) * 1.30)
	return _wav(f, false)


func _make_cutin() -> AudioStreamWAV:
	var n := int(RATE * 0.38)
	var f := PackedFloat32Array()
	f.resize(n)
	var low := 0.0
	var band := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 9091
	for i in range(n):
		var tt := float(i) / float(RATE)
		var k := clampf(tt / 0.38, 0.0, 1.0)
		var env := sin(PI * k) * (1.0 - k * 0.25)
		var raw := rng.randf_range(-1.0, 1.0)
		# Crisp metallic blade slice ("SHING!")
		var fc := lerpf(3400.0, 950.0, k)
		var fcoef := 2.0 * sin(PI * fc / float(RATE))
		low += fcoef * band
		var high := raw - low - 0.75 * band
		band += fcoef * high
		# Harmonic reward ping
		var ping := sin(TAU * 1318.5 * tt) * exp(-12.0 * tt) * 0.26 + sin(TAU * 2637.0 * tt) * exp(-18.0 * tt) * 0.14
		f[i] = _soft((band * 2.8 + high * 0.30) * env + ping)
	return _wav(f, false)


func _make_rewind() -> AudioStreamWAV:
	var n := int(RATE * 1.5)
	var f := PackedFloat32Array()
	f.resize(n)
	var low := 0.0
	var band := 0.0
	var ph := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 1717
	for i in range(n):
		var tt := float(i) / float(RATE)
		var k := clampf(tt / 1.5, 0.0, 1.0)
		var env := sin(PI * k)
		env = env * env * 0.90
		var raw := rng.randf_range(-1.0, 1.0)
		var fc := lerpf(380.0, 3200.0, k * k)
		var fcoef := 2.0 * sin(PI * fc / float(RATE))
		low += fcoef * band
		var high := raw - low - 0.95 * band
		band += fcoef * high
		ph += TAU * lerpf(160.0, 740.0, k) / float(RATE)
		var warble := sin(ph + sin(TAU * 8.0 * tt) * 0.9) * 0.16
		f[i] = _soft(band * 2.4 * env + high * 0.24 * env + warble * env)
	return _wav(f, false)


func _make_slipstream() -> AudioStreamWAV:
	var loop_len := RATE
	var fade := 3000
	var n := loop_len + fade
	var f := PackedFloat32Array()
	f.resize(n)
	var low := 0.0
	var band := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 505
	for i in range(n):
		var tt := float(i) / float(RATE)
		var raw := rng.randf_range(-1.0, 1.0)
		# Suction vacuum & vortex air sweep
		var fc := 680.0 + sin(TAU * 5.0 * tt) * 180.0
		var fcoef := 2.0 * sin(PI * fc / float(RATE))
		low += fcoef * band
		var high := raw - low - 0.85 * band
		band += fcoef * high
		var suction := sin(TAU * 58.0 * tt) * 0.14 + sin(TAU * 116.0 * tt) * 0.08
		var whistle := sin(TAU * (920.0 + 80.0 * sin(TAU * 4.0 * tt)) * tt) * 0.035
		f[i] = _soft((band * 2.2 + suction + whistle) * 0.90)
	return _loop_wav(f, loop_len, fade)


func _make_rain() -> AudioStreamWAV:
	var loop_len := int(RATE * 1.8)
	var fade := 4000
	var n := loop_len + fade
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 31415
	for i in range(n):
		var tt := float(i) / float(RATE)
		var raw := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.35)
		lp2 = lerpf(lp2, lp, 0.030)
		var rain_hiss := (lp - lp2 * 0.80) * 0.75
		# Droplet taps on glass
		var tap := 0.0
		if rng.randf() < 0.012:
			tap = rng.randf_range(0.2, 0.5) * sin(TAU * rng.randf_range(1600.0, 3200.0) * tt)
		f[i] = _soft(rain_hiss + tap)
	return _loop_wav(f, loop_len, fade)


# --- music ------------------------------------------------------------------

static func _render_music_loop() -> PackedFloat32Array:
	var beat := 60.0 / 118.0
	var bar := beat * 4.0
	var bars := 8
	var loop_len := int(round(bar * float(bars) * RATE))
	var fade := 5000
	var buf := PackedFloat32Array()
	buf.resize(loop_len + fade)

	var tbl := PackedFloat32Array()
	tbl.resize(TBL)
	for i in range(TBL):
		tbl[i] = sin(TAU * float(i) / float(TBL))

	var chords := [
		[220.00, 261.63, 329.63],  # Am
		[174.61, 220.00, 261.63],  # F
		[261.63, 329.63, 392.00],  # C
		[196.00, 246.94, 293.66],  # G
		[220.00, 261.63, 329.63],  # Am
		[174.61, 220.00, 261.63],  # F
		[146.83, 174.61, 220.00],  # Dm
		[164.81, 207.65, 246.94],  # E
	]
	var roots := [110.00, 87.31, 130.81, 98.00, 110.00, 87.31, 73.42, 82.41]
	var arp := [0, 2, 1, 2, 0, 2, 1, 2]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5511

	for b in range(bars):
		var t0 := float(b) * bar
		var chord: Array = chords[b]
		for nidx in range(3):
			var fr: float = chord[nidx]
			# Wide pad: two detuned layers plus an upper octave shimmer.
			_tone(buf, t0, bar * 1.04, fr, 0.038, 0.42, 0.55, tbl, 0.30)
			_tone(buf, t0, bar * 1.04, fr * 1.0035, 0.020, 0.50, 0.55, tbl, 0.16)
			_tone(buf, t0, bar * 1.04, fr * 2.0, 0.009, 0.55, 0.55, tbl, 0.08)
		_bass(buf, t0, beat * 1.9, roots[b], 0.16, tbl)
		_bass(buf, t0 + bar * 0.5, beat * 1.7, roots[b] * 2.0, 0.072, tbl)
		_bass(buf, t0 + bar * 0.75, beat * 0.5, roots[b], 0.055, tbl)
		for k in range(8):
			var step: int = arp[k]
			var f2: float = chord[step] * 2.0
			var amp := 0.030 if k % 2 == 0 else 0.022
			_pluck(buf, t0 + float(k) * beat * 0.5, beat * 0.46, f2, amp, tbl)
			# simple echo one eighth later
			if k % 2 == 1:
				_pluck(buf, t0 + float(k) * beat * 0.5 + beat * 0.25, beat * 0.30, f2, amp * 0.32, tbl)
		_kick(buf, t0, 0.105)
		_kick(buf, t0 + beat * 1.0, 0.082)
		_kick(buf, t0 + beat * 2.0, 0.098)
		_kick(buf, t0 + beat * 3.0, 0.082)
		_snare(buf, t0 + beat * 1.0, 0.055, rng)
		_snare(buf, t0 + beat * 3.0, 0.058, rng)
		for k in range(8):
			_hat(buf, t0 + beat * (float(k) + 0.5), 0.010 if k % 2 == 0 else 0.014, rng)
		if b % 2 == 1:
			_hat(buf, t0 + beat * 3.5, 0.016, rng)

	var peak := 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var gain := 0.74 / peak
	for i in range(buf.size()):
		buf[i] *= gain

	return _loop_samples(buf, loop_len, fade)


static func _tone(buf: PackedFloat32Array, start: float, dur: float, freq: float, amp: float, attack: float, release: float, tbl: PackedFloat32Array, harm: float) -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var inc := freq * float(TBL) / float(RATE)
	var mask := TBL - 1
	var ph := 0.0
	for i in range(n):
		var idx := s0 + i
		if idx < 0:
			continue
		if idx >= buf.size():
			break
		var tt := float(i) / float(RATE)
		var env := 1.0
		if tt < attack:
			env = tt / attack
		elif tt > dur - release:
			env = maxf(0.0, (dur - tt) / release)
		env = env * env * (3.0 - 2.0 * env)
		var p0 := int(ph) & mask
		var v := tbl[p0]
		if harm > 0.0:
			v += tbl[int(ph * 2.0) & mask] * harm
		buf[idx] += v * env * amp
		ph += inc


static func _bass(buf: PackedFloat32Array, start: float, dur: float, freq: float, amp: float, tbl: PackedFloat32Array) -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var inc := freq * float(TBL) / float(RATE)
	var mask := TBL - 1
	var ph := 0.0
	for i in range(n):
		var idx := s0 + i
		if idx >= buf.size():
			break
		var tt := float(i) / float(RATE)
		var env := exp(-2.1 * tt) * minf(1.0, tt / 0.010)
		var p0 := int(ph) & mask
		var v := tbl[p0] + tbl[(int(ph) * 2) & mask] * 0.36 + tbl[(int(ph) * 3) & mask] * 0.15
		buf[idx] += v * env * amp
		ph += inc


static func _pluck(buf: PackedFloat32Array, start: float, dur: float, freq: float, amp: float, tbl: PackedFloat32Array) -> void:
	var s0 := int(start * RATE)
	var n := int(dur * RATE)
	var inc := freq * float(TBL) / float(RATE)
	var mask := TBL - 1
	var ph := 0.0
	for i in range(n):
		var idx := s0 + i
		if idx >= buf.size():
			break
		var tt := float(i) / float(RATE)
		var env := exp(-7.0 * tt) * minf(1.0, tt / 0.006)
		var p0 := int(ph) & mask
		var v := tbl[p0] * 0.68 + tbl[(int(ph) * 2) & mask] * 0.22 + tbl[(int(ph) * 3) & mask] * 0.09
		buf[idx] += v * env * amp
		ph += inc


static func _kick(buf: PackedFloat32Array, start: float, amp: float) -> void:
	var s0 := int(start * RATE)
	var n := int(0.28 * RATE)
	for i in range(n):
		var idx := s0 + i
		if idx >= buf.size():
			break
		var tt := float(i) / float(RATE)
		var ph := TAU * (42.0 * tt + (125.0 / 18.0) * (1.0 - exp(-18.0 * tt)))
		buf[idx] += sin(ph) * exp(-9.0 * tt) * amp


static func _snare(buf: PackedFloat32Array, start: float, amp: float, rng: RandomNumberGenerator) -> void:
	var s0 := int(start * RATE)
	var n := int(0.22 * RATE)
	var lp := 0.0
	for i in range(n):
		var idx := s0 + i
		if idx >= buf.size():
			break
		var tt := float(i) / float(RATE)
		var raw := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.35)
		var noise := raw - lp * 0.65
		var body := sin(TAU * 180.0 * tt) * 0.18
		buf[idx] += (noise * 0.70 + body) * exp(-14.0 * tt) * amp


static func _hat(buf: PackedFloat32Array, start: float, amp: float, rng: RandomNumberGenerator) -> void:
	var s0 := int(start * RATE)
	var n := int(0.060 * RATE)
	var prev := 0.0
	for i in range(n):
		var idx := s0 + i
		if idx >= buf.size():
			break
		var tt := float(i) / float(RATE)
		var raw := rng.randf_range(-1.0, 1.0)
		var hp := raw - prev * 0.72
		prev = raw
		buf[idx] += hp * exp(-46.0 * tt) * amp
