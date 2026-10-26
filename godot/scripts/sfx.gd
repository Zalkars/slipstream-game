extends Node

# All audio is synthesised at runtime into 16-bit PCM (no audio assets).
# Separate SFX / Music buses let the player mute them independently.

const RATE := 22050
const TBL := 2048

var engine: AudioStreamPlayer
var wind: AudioStreamPlayer
var nitro_snd: AudioStreamPlayer
var crash_snd: AudioStreamPlayer
var whoosh_snd: AudioStreamPlayer
var click_snd: AudioStreamPlayer
var chime_snd: AudioStreamPlayer
var coin_snd: AudioStreamPlayer
var pickup_snd: AudioStreamPlayer
var boost_snd: AudioStreamPlayer
var music_player: AudioStreamPlayer

var sfx_bus := 0
var music_bus := 0
var sfx_on := true
var music_on := true
var muted := false

var _engine_on := false
var _boost := false
var _paused := false

var _music_buf := PackedFloat32Array()
var _music_task := -1
var _music_busy := false


func _ready() -> void:
	_setup_buses()
	set_process(true)
	engine = _player(_make_engine(), -16.0)
	wind = _player(_make_wind(), -26.0)
	nitro_snd = _player(_make_nitro(), -60.0)
	crash_snd = _player(_make_crash(), -4.0)
	whoosh_snd = _player(_make_whoosh(), -11.0)
	click_snd = _player(_make_click(), -17.0)
	chime_snd = _player(_make_chime(), -10.0)
	coin_snd = _player(_make_coin(), -13.0)
	pickup_snd = _player(_make_pickup(), -12.0)
	boost_snd = _player(_make_boost(), -9.0)

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
	AudioServer.set_bus_mute(sfx_bus, not on)


func set_music_enabled(on: bool) -> void:
	music_on = on
	AudioServer.set_bus_mute(music_bus, not on)
	if on:
		play_music()
	elif music_player != null:
		music_player.stop()


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
	_paused = false
	engine.volume_db = -18.0
	wind.volume_db = -28.0
	nitro_snd.volume_db = -60.0
	engine.play()
	wind.play()
	nitro_snd.play()


func stop_engine() -> void:
	_engine_on = false
	engine.stop()
	wind.stop()
	nitro_snd.stop()


func set_paused(p: bool) -> void:
	_paused = p
	if music_player != null and music_player.playing:
		music_player.volume_db = -30.0 if p else -19.0
	if not _engine_on:
		return
	engine.volume_db = -42.0 if p else (-16.0 + _speed_ratio() * 5.0)
	wind.volume_db = -46.0 if p else (-26.0 + _speed_ratio() * 8.0)
	nitro_snd.volume_db = -60.0 if p else (-15.0 if _boost else -60.0)


func _speed_ratio() -> float:
	var kmh := 0.0
	var game := _find_game()
	if game != null:
		kmh = game.speed * 0.3
	return clampf((kmh - 120.0) / 210.0, 0.0, 1.0)


func _find_game() -> Node:
	var root := get_tree().current_scene
	if root == null:
		return null
	return root.get_node_or_null("Game")


func update_engine(kmh: float, boost: bool) -> void:
	if not _engine_on:
		return
	_boost = boost
	if _paused:
		return
	var ratio := clampf((kmh - 120.0) / 210.0, 0.0, 1.0)
	engine.pitch_scale = 0.82 + ratio * 0.46 + (0.10 if boost else 0.0)
	engine.volume_db = -16.0 + ratio * 5.0
	wind.volume_db = -26.0 + ratio * 8.0
	nitro_snd.volume_db = -13.0 if boost else -60.0


# --- one-shots --------------------------------------------------------------

func crash() -> void:
	crash_snd.play()


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


func boost_burst() -> void:
	boost_snd.play()


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


func _loop_samples(f: PackedFloat32Array, loop_len: int, fade: int) -> PackedFloat32Array:
	for i in range(fade):
		var a := float(i) / float(fade)
		f[i] = f[i] * a + f[loop_len + i] * (1.0 - a)
	var out := PackedFloat32Array()
	out.resize(loop_len)
	for i in range(loop_len):
		out[i] = f[i]
	return out


func _make_engine() -> AudioStreamWAV:
	var loop_len := RATE
	var fade := 2048
	var n := loop_len + fade
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 4242
	for i in range(n):
		var tt := float(i) / float(RATE)
		var v := 0.0
		v += sin(TAU * 55.0 * tt) * 0.50
		v += sin(TAU * 110.0 * tt) * 0.32
		v += sin(TAU * 165.0 * tt) * 0.16
		v += sin(TAU * 220.0 * tt) * 0.10
		v += sin(TAU * 330.0 * tt) * 0.05
		v += sin(TAU * 440.0 * tt) * 0.03
		lp = lerpf(lp, rng.randf_range(-1.0, 1.0), 0.10)
		var mod := 0.80 + 0.20 * sin(TAU * 55.0 * tt)
		v = v * 0.55 * mod + lp * 0.30
		f[i] = clampf(v * 1.5, -1.0, 1.0) * 0.85
	return _loop_wav(f, loop_len, fade)


func _make_wind() -> AudioStreamWAV:
	var loop_len := RATE * 2
	var fade := 4096
	var n := loop_len + fade
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 777
	for i in range(n):
		var raw := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.06)
		lp2 = lerpf(lp2, lp, 0.09)
		f[i] = clampf(lp2 * 2.4, -1.0, 1.0) * 0.8
	return _loop_wav(f, loop_len, fade)


func _make_nitro() -> AudioStreamWAV:
	var loop_len := RATE
	var fade := 3072
	var n := loop_len + fade
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 91
	for i in range(n):
		var tt := float(i) / float(RATE)
		var raw := rng.randf_range(-1.0, 1.0)
		lp = lerpf(lp, raw, 0.22)
		lp2 = lerpf(lp2, lp, 0.02)
		var hiss := lp - lp2 * 0.85
		var rumble := sin(TAU * 70.0 * tt) * 0.10
		f[i] = clampf(hiss * 0.9 + rumble, -1.0, 1.0)
	return _loop_wav(f, loop_len, fade)


func _make_crash() -> AudioStreamWAV:
	var n := int(RATE * 0.85)
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 33
	for i in range(n):
		var tt := float(i) / float(RATE)
		var env := exp(-5.2 * tt)
		var noise := rng.randf_range(-1.0, 1.0) * env
		lp = lerpf(lp, noise, 0.32)
		var thump := sin(TAU * 52.0 * tt) * exp(-4.2 * tt) * 0.55
		var metal := sin(TAU * 1170.0 * tt) * exp(-9.0 * tt) * 0.16
		var crunch := sin(TAU * 240.0 * tt) * exp(-14.0 * tt) * 0.25
		f[i] = clampf(lp * 1.35 + thump + metal + crunch, -1.0, 1.0)
	return _wav(f, false)


func _make_whoosh() -> AudioStreamWAV:
	var n := int(RATE * 0.42)
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 808
	for i in range(n):
		var tt := float(i) / float(RATE)
		var env := sin(PI * clampf(tt / 0.42, 0.0, 1.0))
		env = env * env
		var raw := rng.randf_range(-1.0, 1.0)
		var k := lerpf(0.32, 0.10, tt / 0.42)
		lp = lerpf(lp, raw, k)
		lp2 = lerpf(lp2, lp, 0.03)
		f[i] = clampf((lp - lp2) * 2.0 * env, -1.0, 1.0) * 0.85
	return _wav(f, false)


func _make_click() -> AudioStreamWAV:
	var n := int(RATE * 0.07)
	var f := PackedFloat32Array()
	f.resize(n)
	for i in range(n):
		var tt := float(i) / float(RATE)
		var env := exp(-46.0 * tt)
		f[i] = (sin(TAU * 1350.0 * tt) * 0.45 + sin(TAU * 2100.0 * tt) * 0.18) * env
	return _wav(f, false)


func _make_chime() -> AudioStreamWAV:
	var n := int(RATE * 0.95)
	var f := PackedFloat32Array()
	f.resize(n)
	for i in range(n):
		var tt := float(i) / float(RATE)
		var a := 0.0
		if tt < 0.5:
			a += sin(TAU * 880.0 * tt) * exp(-7.0 * tt)
			a += sin(TAU * 1760.0 * tt) * exp(-10.0 * tt) * 0.3
		if tt > 0.16:
			var t2 := tt - 0.16
			a += sin(TAU * 1318.5 * t2) * exp(-6.0 * t2) * 0.8
			a += sin(TAU * 2637.0 * t2) * exp(-9.0 * t2) * 0.2
		f[i] = clampf(a * 0.4, -1.0, 1.0)
	return _wav(f, false)


func _make_coin() -> AudioStreamWAV:
	var n := int(RATE * 0.24)
	var f := PackedFloat32Array()
	f.resize(n)
	for i in range(n):
		var tt := float(i) / float(RATE)
		var a := 0.0
		a += sin(TAU * 1318.5 * tt) * exp(-15.0 * tt) * 0.5
		if tt > 0.055:
			var t2 := tt - 0.055
			a += sin(TAU * 1975.5 * t2) * exp(-13.0 * t2) * 0.45
		f[i] = clampf(a, -1.0, 1.0) * 0.8
	return _wav(f, false)


func _make_pickup() -> AudioStreamWAV:
	var n := int(RATE * 0.4)
	var f := PackedFloat32Array()
	f.resize(n)
	var ph := 0.0
	for i in range(n):
		var tt := float(i) / float(RATE)
		var k := clampf(tt / 0.4, 0.0, 1.0)
		var fr := lerpf(480.0, 1180.0, k * k)
		ph += TAU * fr / float(RATE)
		var env := sin(PI * k)
		f[i] = clampf((sin(ph) * 0.6 + sin(ph * 2.0) * 0.18) * env, -1.0, 1.0) * 0.8
	return _wav(f, false)


func _make_boost() -> AudioStreamWAV:
	var n := int(RATE * 0.7)
	var f := PackedFloat32Array()
	f.resize(n)
	var lp := 0.0
	var lp2 := 0.0
	var ph := 0.0
	var rng := RandomNumberGenerator.new()
	rng.seed = 5150
	for i in range(n):
		var tt := float(i) / float(RATE)
		var k := clampf(tt / 0.7, 0.0, 1.0)
		var env := sin(PI * k)
		var raw := rng.randf_range(-1.0, 1.0)
		var cut := lerpf(0.10, 0.42, k)
		lp = lerpf(lp, raw, cut)
		lp2 = lerpf(lp2, lp, 0.05)
		var hiss := lp - lp2
		ph += TAU * lerpf(90.0, 230.0, k) / float(RATE)
		var body := sin(ph) * 0.5
		f[i] = clampf((hiss * 2.2 + body) * env, -1.0, 1.0) * 0.9
	return _wav(f, false)


# --- music ------------------------------------------------------------------

func _render_music_loop() -> PackedFloat32Array:
	var beat := 60.0 / 118.0
	var bar := beat * 4.0
	var loop_len := int(round(bar * 4.0 * RATE))
	var fade := 4096
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
	]
	var roots := [110.00, 87.31, 130.81, 98.00]
	var arp := [0, 2, 1, 2, 0, 2, 1, 2]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5511

	for b in range(4):
		var t0 := float(b) * bar
		for nidx in range(3):
			var fr: float = chords[b][nidx]
			_tone(buf, t0, bar * 1.02, fr, 0.046, 0.50, 0.60, tbl, 0.26)
			_tone(buf, t0, bar * 1.02, fr * 1.004, 0.018, 0.55, 0.60, tbl, 0.12)
		_bass(buf, t0, beat * 1.7, roots[b], 0.15, tbl)
		_bass(buf, t0 + bar * 0.5, beat * 1.7, roots[b] * 2.0, 0.07, tbl)
		for k in range(8):
			var step: int = arp[k]
			var f2: float = chords[b][step] * 2.0
			_pluck(buf, t0 + float(k) * beat * 0.5, beat * 0.46, f2, 0.030 if k % 2 == 0 else 0.022, tbl)
		_kick(buf, t0, 0.10)
		_kick(buf, t0 + beat * 2.0, 0.075)
		for k in range(4):
			_hat(buf, t0 + beat * (float(k) + 0.5), 0.012, rng)

	var peak := 0.0001
	for v in buf:
		peak = maxf(peak, absf(v))
	var gain := 0.72 / peak
	for i in range(buf.size()):
		buf[i] *= gain

	return _loop_samples(buf, loop_len, fade)


func _tone(buf: PackedFloat32Array, start: float, dur: float, freq: float, amp: float, attack: float, release: float, tbl: PackedFloat32Array, harm: float) -> void:
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


func _bass(buf: PackedFloat32Array, start: float, dur: float, freq: float, amp: float, tbl: PackedFloat32Array) -> void:
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
		var env := exp(-2.3 * tt) * minf(1.0, tt / 0.010)
		var p0 := int(ph) & mask
		var v := tbl[p0] + tbl[(int(ph) * 2) & mask] * 0.34 + tbl[(int(ph) * 3) & mask] * 0.14
		buf[idx] += v * env * amp
		ph += inc


func _pluck(buf: PackedFloat32Array, start: float, dur: float, freq: float, amp: float, tbl: PackedFloat32Array) -> void:
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
		var v := tbl[p0] * 0.70 + tbl[(int(ph) * 2) & mask] * 0.20 + tbl[(int(ph) * 3) & mask] * 0.08
		buf[idx] += v * env * amp
		ph += inc


func _kick(buf: PackedFloat32Array, start: float, amp: float) -> void:
	var s0 := int(start * RATE)
	var n := int(0.26 * RATE)
	for i in range(n):
		var idx := s0 + i
		if idx >= buf.size():
			break
		var tt := float(i) / float(RATE)
		var ph := TAU * (44.0 * tt + (120.0 / 18.0) * (1.0 - exp(-18.0 * tt)))
		buf[idx] += sin(ph) * exp(-10.0 * tt) * amp


func _hat(buf: PackedFloat32Array, start: float, amp: float, rng: RandomNumberGenerator) -> void:
	var s0 := int(start * RATE)
	var n := int(0.055 * RATE)
	var prev := 0.0
	for i in range(n):
		var idx := s0 + i
		if idx >= buf.size():
			break
		var tt := float(i) / float(RATE)
		var raw := rng.randf_range(-1.0, 1.0)
		var hp := raw - prev * 0.7
		prev = raw
		buf[idx] += hp * exp(-48.0 * tt) * amp
