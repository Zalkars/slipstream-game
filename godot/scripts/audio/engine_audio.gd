extends Node

# The player's own car: engine, tyres, brakes and nitro on the Engine bus.
#
# Engine: three rpm points x {on load, off load} = six seamless loops per car
# class (rendered offline at known rpm). The two loops around the current rpm
# are crossfaded with equal power and pitch-shifted to the exact rpm; throttle
# load blends on/off. Gears come from the car's speed fraction with shift dips,
# rev-matched downshift blips and exhaust pops on lift-off for sporty classes.

const BANK := preload("res://scripts/audio/audio_bank.gd")
const POOL := preload("res://scripts/audio/audio_pool.gd")

# Gear upper limits as a fraction of the car's top speed. Cruising sits around
# 0.68..1.0 (gears 4-5); nitro pushes into 6th; braking drops to 2nd-3rd.
const GEAR_TOP := [0.22, 0.38, 0.55, 0.74, 0.98, 1.30, 99.0]
const SHIFT_TIME := 0.16
const SILHOUETTE_TO_SPEC := {
	"hatch": "hatch", "van": "van", "sedan": "sedan", "offroad": "offroad", "muscle": "muscle",
	"pickup": "pickup", "sport": "sport", "ev": "ev", "hyper": "hyper",
}

var spec: Dictionary = {}
var spec_name := ""
var running := false
var paused := false
var rewinding := false

var _eng: Array = []        # [ref][load] -> AudioStreamPlayer
var _refs: PackedFloat32Array = PackedFloat32Array()
var _nitro: AudioStreamPlayer
var _roll_dry: AudioStreamPlayer
var _roll_wet: AudioStreamPlayer
var _air: AudioStreamPlayer
var _draft: AudioStreamPlayer
var _scrub: AudioStreamPlayer
var _squeal: AudioStreamPlayer
var _skid_wet: AudioStreamPlayer
var _abs: AudioStreamPlayer
var _overheat: AudioStreamPlayer
var _loops: Array = []
var pool: Node

var rpm := 900.0
var load := 0.5
var gear := 1
var _shift_t := 0.0
var _blip_t := 0.0
var _prev_speed := -1.0
var _accel := 0.0
var _was_boost := false
var _was_brake := false
var _pop_cd := 0.0
var _rng := RandomNumberGenerator.new()
var _master_db := 0.0      # fade for start/stop/pause/rewind
var _nitro_gain := 0.0
var _squeal_amt := 0.0
var _lat_skid := 0.0
var _decel := 0.0           # fast-tracking deceleration (px/s^2) for the brakes
# Slingshot: a short, believable surge. Gear is held and rpm/loudness are
# capped relative to the moment it fired, then released smoothly.
const SLING_RPM_GAIN := 1.10
const SLING_DB_GAIN := 1.5
const SLING_RELEASE := 1.2
var _sling_lock := 0.0
var _sling_rpm0 := 0.0
var _sling_db0 := 0.0
var _was_sling := false
var last_base_db := 0.0     # engine loudness before per-loop weights (tests)
var squeal_level := 0.0     # 0..1 current brake squeal/hiss drive


func _ready() -> void:
	_rng.seed = 8086
	for i in range(3):
		var row: Array = []
		for j in range(2):
			row.append(_loop_player())
		_eng.append(row)
	_nitro = _loop_player()
	_roll_dry = _loop_player()
	_roll_wet = _loop_player()
	_air = _loop_player()
	_draft = _loop_player()
	_scrub = _loop_player()
	_squeal = _loop_player()
	_skid_wet = _loop_player()
	_abs = _loop_player()
	_overheat = _loop_player()
	_nitro.stream = BANK.stream("nitro/sustain", true)
	_roll_dry.stream = BANK.stream("tyre/roll_dry", true)
	_roll_wet.stream = BANK.stream("tyre/roll_wet", true)
	_air.stream = BANK.stream("air/rush", true)
	_draft.stream = BANK.stream("air/rush", true)
	_scrub.stream = BANK.stream("brake/scrub", true)
	_squeal.stream = BANK.stream("brake/squeal_dry", true)
	_skid_wet.stream = BANK.stream("brake/skid_wet", true)
	_abs.stream = BANK.stream("brake/abs", true)
	_overheat.stream = BANK.stream("brake/overheat", true)
	pool = POOL.new()
	pool.name = "EnginePool"
	add_child(pool)
	pool.setup(6, "Engine", false)


func _loop_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = "Engine"
	p.volume_db = -80.0
	add_child(p)
	_loops.append(p)
	return p


func set_car(silhouette: String) -> void:
	var specs := BANK.engines()
	var key: String = SILHOUETTE_TO_SPEC.get(silhouette, "sedan")
	if not specs.has(key):
		key = "sedan" if specs.has("sedan") else ""
	if key == spec_name or key == "":
		return
	spec_name = key
	spec = specs[key]
	_refs = PackedFloat32Array(spec.get("refs", [1500.0, 3500.0, 6000.0]))
	for i in range(3):
		for j in range(2):
			var p: AudioStreamPlayer = _eng[i][j]
			p.stop()
			p.stream = BANK.stream("engine/%s_%d_%s" % [key, i, "on" if j == 0 else "off"], true)
			if running and p.stream != null:
				p.volume_db = -80.0
				p.play(_rng.randf() * maxf(0.0, p.stream.get_length() - 0.05))
				p.stream_paused = true


func start() -> void:
	running = true
	paused = false
	rewinding = false
	_prev_speed = -1.0
	_shift_t = 0.0
	_blip_t = 0.0
	_was_boost = false
	_was_brake = false
	_nitro_gain = 0.0
	_master_db = -18.0
	rpm = float(spec.get("idle", 800.0)) * 1.6
	for p in _loops:
		p.volume_db = -80.0
		if p.stream != null:
			# Random start points so the loops never phase-lock audibly.
			p.play(_rng.randf() * maxf(0.0, p.stream.get_length() - 0.05))
			p.stream_paused = true


func stop() -> void:
	running = false
	for p in _loops:
		p.stop()


func _vol(p: AudioStreamPlayer, db: float, dt: float, rate := 18.0) -> void:
	# Smooth in dB and pause players that are effectively silent.
	var target := db + _master_db
	var k := minf(1.0, dt * rate)
	p.volume_db = lerpf(p.volume_db, target, k) if p.volume_db > -79.0 or target > -79.0 else -80.0
	var silent := p.volume_db < -62.0 and target < -62.0
	if p.stream_paused != silent and p.playing:
		p.stream_paused = silent


static func _gain_db(w: float) -> float:
	return 20.0 * log(maxf(w, 0.00001)) / log(10.0)


# s: speed, top, boost, brake, overheated, draft, wet, lateral, crashed
func update(dt: float, s: Dictionary) -> void:
	if not running or spec.is_empty():
		return
	var speed: float = s.speed
	var top := maxf(300.0, float(s.top))
	var boost: bool = s.boost
	var brake: bool = s.brake
	var wet: float = s.wet
	if _prev_speed < 0.0:
		_prev_speed = speed
	var raw_acc := (speed - _prev_speed) / maxf(dt, 0.001)
	_prev_speed = speed
	_accel = lerpf(_accel, raw_acc, minf(1.0, dt * 8.0))
	_decel = lerpf(_decel, maxf(0.0, -raw_acc), minf(1.0, dt * 25.0))
	var sling: bool = s.get("sling", false)
	if sling and not _was_sling:
		_sling_rpm0 = rpm
		_sling_db0 = last_base_db
	if sling:
		_sling_lock = SLING_RELEASE
	elif _sling_lock > 0.0:
		_sling_lock = maxf(0.0, _sling_lock - dt)
	_was_sling = sling

	var fade_target := 0.0
	if paused:
		fade_target = -26.0
	elif rewinding:
		fade_target = -12.0
	_master_db = lerpf(_master_db, fade_target, minf(1.0, dt * 4.0))

	_update_rpm(dt, speed / top, boost, brake)
	_engine_mix(dt)
	_nitro_mix(dt, boost, speed / top)
	_tyres_mix(dt, speed, top, brake, wet, float(s.lateral), bool(s.overheated), float(s.draft), boost,
		float(s.get("grip", 1.0)))
	if _pop_cd > 0.0:
		_pop_cd -= dt
	_was_boost = boost
	_was_brake = brake


func _update_rpm(dt: float, u: float, boost: bool, brake: bool) -> void:
	var idle: float = spec.get("idle", 800.0)
	var shift_rpm: float = spec.get("shift", 6000.0)
	var redline: float = spec.get("redline", 6500.0)
	var is_ev: bool = spec.get("ev", false)
	var want_load := 0.55
	if brake:
		want_load = 0.0
	elif boost:
		want_load = 1.0
	elif _accel > 40.0:
		want_load = 0.85
	elif _accel < -60.0:
		want_load = 0.15
	if is_ev:
		var target := redline * clampf(u / 1.55, 0.03, 1.0)
		if _sling_lock > 0.0 and not brake and not boost:
			target = minf(target, _sling_rpm0 * SLING_RPM_GAIN)
		rpm = lerpf(rpm, target, minf(1.0, dt * 10.0))
		load = lerpf(load, want_load, minf(1.0, dt * 6.0))
		return
	# Gear from speed with hysteresis so braking/boost don't hunt. The gear is
	# held through a slingshot so its brief speed spike cannot shift and rev.
	var g := gear
	if _sling_lock > 0.0 and not brake and not boost:
		g = gear
	else:
		g = _pick_gear(u)
	if g != gear:
		if g > gear:
			_shift_t = SHIFT_TIME
			if rpm > shift_rpm * 0.8:
				_maybe_pop(0.45)
		else:
			# Rev-matched downshift: a short throttle blip.
			_blip_t = 0.12
		gear = g
	var g_lo := 0.0 if gear == 1 else float(GEAR_TOP[gear - 2])
	var g_hi := float(GEAR_TOP[gear - 1])
	if gear >= GEAR_TOP.size():
		g_hi = g_lo * 1.25
	var frac := clampf((u - g_lo * 0.82) / maxf(0.01, g_hi - g_lo * 0.82), 0.0, 1.12)
	var target_rpm := lerpf(idle * 1.45, shift_rpm, frac)
	target_rpm = minf(target_rpm, redline)
	if _blip_t > 0.0:
		_blip_t -= dt
		target_rpm *= 1.12
		want_load = 0.6
	var slew := 6.0
	if _sling_lock > 0.0 and not brake and not boost:
		# Quick, modest rev rise; the release phase glides back down.
		target_rpm = minf(target_rpm, _sling_rpm0 * SLING_RPM_GAIN)
		want_load = minf(want_load, 0.8)
		slew = 5.0 if _was_sling else 3.0
	if _shift_t > 0.0:
		_shift_t -= dt
		want_load = 0.08
		slew = 22.0
	rpm = lerpf(rpm, target_rpm, minf(1.0, dt * slew))
	# Lift-off pops: off throttle after being on it hard.
	if (brake and not _was_brake) or (_was_boost and not boost):
		if rpm > shift_rpm * 0.5:
			_maybe_pop(1.0)
	load = lerpf(load, want_load, minf(1.0, dt * (14.0 if want_load < load else 7.0)))


func _pick_gear(u: float) -> int:
	var g := gear
	while g < GEAR_TOP.size() and u > float(GEAR_TOP[g - 1]):
		g += 1
	while g > 1 and u < float(GEAR_TOP[g - 2]) * 0.90:
		g -= 1
	return clampi(g, 1, GEAR_TOP.size())


func _maybe_pop(chance: float) -> void:
	var pops: float = spec.get("pops", 0.0)
	if pops <= 0.0 or _pop_cd > 0.0 or paused or rewinding:
		return
	if _rng.randf() > pops * chance:
		return
	_pop_cd = 0.35
	var count := 1 + (1 if _rng.randf() < pops * 0.6 else 0) + (1 if _rng.randf() < pops * 0.3 else 0)
	for i in range(count):
		var delay := float(i) * _rng.randf_range(0.05, 0.11)
		get_tree().create_timer(delay, false).timeout.connect(_pop_now)


func _pop_now() -> void:
	if not running:
		return
	var st := BANK.stream("engine/pop_%d" % _rng.randi_range(0, 4))
	pool.play(st, -9.0 + _rng.randf_range(-3.0, 1.5) + _master_db, _rng.randf_range(0.85, 1.15))


func _engine_mix(dt: float) -> void:
	# Position of rpm between the reference loops, in log space.
	var lr := log(maxf(rpm, 100.0))
	var w := [0.0, 0.0, 0.0]
	var l0 := log(_refs[0])
	var l1 := log(_refs[1])
	var l2 := log(_refs[2])
	if lr <= l1:
		var k := clampf((lr - l0) / (l1 - l0), 0.0, 1.0)
		w[0] = cos(k * PI * 0.5)
		w[1] = sin(k * PI * 0.5)
	else:
		var k := clampf((lr - l1) / (l2 - l1), 0.0, 1.0)
		w[1] = cos(k * PI * 0.5)
		w[2] = sin(k * PI * 0.5)
	var on_w := sqrt(clampf(load, 0.0, 1.0))
	var off_w := sqrt(1.0 - clampf(load, 0.0, 1.0))
	var redline: float = spec.get("redline", 6500.0)
	var rn := clampf(rpm / redline, 0.0, 1.2)
	# Louder with revs and load; a short dip while the clutch is in.
	var base_db: float = -7.0 + float(spec.get("vol", 0.0)) + rn * 5.0 + load * 3.0
	if _shift_t > 0.0:
		base_db -= 3.0
	if _sling_lock > 0.0:
		base_db = minf(base_db, _sling_db0 + SLING_DB_GAIN)
	last_base_db = base_db
	# Step back under a hard brake so the tyres read clearly.
	base_db -= squeal_level * 4.0
	for i in range(3):
		var pitch := clampf(rpm / _refs[i], 0.45, 2.2)
		for j in range(2):
			var p: AudioStreamPlayer = _eng[i][j]
			p.pitch_scale = pitch
			var lw: float = on_w if j == 0 else off_w
			var off_db := 0.0 if j == 0 else -4.5
			_vol(p, base_db + off_db + _gain_db(w[i] * lw), dt, 30.0)


func _nitro_mix(dt: float, boost: bool, u: float) -> void:
	if boost and not _was_boost:
		pool.play(BANK.stream("nitro/ignite"), -3.0 + _master_db, 1.0)
	elif _was_boost and not boost and running:
		pool.play(BANK.stream("nitro/blowoff"), -6.0 + _master_db, _rng.randf_range(0.95, 1.08))
	_nitro_gain = lerpf(_nitro_gain, 1.0 if boost else 0.0, minf(1.0, dt * (4.0 if boost else 3.0)))
	_nitro.pitch_scale = 0.9 + clampf(u, 0.0, 1.6) * 0.18
	_vol(_nitro, -8.0 + _gain_db(_nitro_gain), dt, 30.0)


func _tyres_mix(dt: float, speed: float, top: float, brake: bool, wet: float,
		lateral: float, overheated: bool, draft: float, boost: bool, grip := 1.0) -> void:
	var u := clampf(speed / top, 0.0, 1.8)
	var dry_k := 1.0 - wet * 0.65
	_roll_dry.pitch_scale = 0.75 + u * 0.35
	_vol(_roll_dry, -13.0 + _gain_db(clampf(u * 1.4, 0.0, 1.0)) + u * 3.0 + _gain_db(dry_k), dt)
	_roll_wet.pitch_scale = 0.85 + u * 0.22
	_vol(_roll_wet, -11.0 + _gain_db(clampf(wet * 1.3, 0.0, 1.0) * clampf(u * 1.5, 0.0, 1.0)) + u * 3.0, dt)
	_air.pitch_scale = 0.8 + u * 0.3
	_vol(_air, -22.0 + _gain_db(clampf((u - 0.25) * 1.3, 0.0, 1.0)) + u * 6.0 + (2.0 if boost else 0.0), dt)
	# Drafting: a low, hollow rush behind another car.
	_draft.pitch_scale = 0.55 + u * 0.12
	_vol(_draft, -16.0 + _gain_db(clampf((draft - 0.2) * 1.4, 0.0, 1.0)), dt, 8.0)

	# Braking: friction rumble always, squeal from brake force (deceleration)
	# and speed, a water hiss on the wet. A normal hard stop (~3000 px/s^2 at
	# first, decaying as speed drops) squeals clearly for most of a second.
	var bite := 0.0
	if brake and not overheated and speed > 120.0:
		var force := pow(clampf(_decel / 2400.0, 0.0, 1.0), 0.55)
		var spd := clampf((speed - 120.0) / 480.0, 0.0, 1.0)
		# Less grip (wet, puddles) means more slip for the same pedal.
		var slip_k := 1.0 + (1.0 - clampf(grip, 0.0, 1.0)) * 0.6
		bite = clampf(force * spd * slip_k, 0.0, 1.0)
	_squeal_amt = lerpf(_squeal_amt, bite, minf(1.0, dt * (18.0 if bite > _squeal_amt else 4.0)))
	squeal_level = _squeal_amt
	# Hard stops engage ABS: on the wet early, on the dry only at full bite.
	var abs_on := brake and not overheated and speed > 180.0 and (wet > 0.3 and _squeal_amt > 0.25 or _squeal_amt > 0.82)
	var squeal_w := _squeal_amt * (1.0 - wet * 0.75) * (0.7 if abs_on else 1.0)
	_squeal.pitch_scale = 0.88 + u * 0.22 + _squeal_amt * 0.06
	_vol(_squeal, -2.0 + _gain_db(squeal_w), dt, 24.0)
	_skid_wet.pitch_scale = 0.9 + u * 0.15
	_vol(_skid_wet, -3.0 + _gain_db(_squeal_amt * clampf(wet * 1.6, 0.0, 1.0)), dt, 24.0)
	_scrub.pitch_scale = 0.85 + u * 0.25
	_vol(_scrub, -15.0 + _gain_db((0.35 + _squeal_amt * 0.65) if brake and speed > 100.0 and not overheated else 0.0), dt, 16.0)
	_abs.pitch_scale = 1.0
	_vol(_abs, -14.0 if abs_on else -80.0, dt, 20.0)
	_vol(_overheat, -15.0 if overheated else -80.0, dt, 6.0)
	# Lane-change scrub: brief chirp on the dry, a slushy skid on the wet.
	var lat := clampf((absf(lateral) - 700.0) / 900.0, 0.0, 1.0) * clampf(u, 0.0, 1.0)
	_lat_skid = lerpf(_lat_skid, lat, minf(1.0, dt * 10.0))
	if _lat_skid > 0.02 and not brake:
		_squeal.volume_db = maxf(_squeal.volume_db, -22.0 + _gain_db(_lat_skid * (1.0 - wet)) + _master_db)
		_skid_wet.volume_db = maxf(_skid_wet.volume_db, -16.0 + _gain_db(_lat_skid * wet) + _master_db)
		if _squeal.stream_paused and _squeal.volume_db > -60.0:
			_squeal.stream_paused = false
		if _skid_wet.stream_paused and _skid_wet.volume_db > -60.0:
			_skid_wet.stream_paused = false


func one_shot(asset: String, volume_db: float, pitch := 1.0) -> void:
	pool.play(BANK.stream(asset), volume_db + _master_db, pitch)
