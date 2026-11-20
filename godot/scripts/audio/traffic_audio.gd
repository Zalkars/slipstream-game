extends Node

# Traffic around the player: a few continuous voices follow the nearest cars.
# Each voice is an engine loop for the vehicle class plus dry and wet tyre
# loops, panned by lateral offset, attenuated by distance and pitched by a
# (gently exaggerated) doppler shift from the relative speed. Recorded pass-by
# one-shots, truck/bus wind buffets and air-brake hisses sit on top.

const BANK := preload("res://scripts/audio/audio_bank.gd")
const POOL := preload("res://scripts/audio/audio_pool.gd")
const PAN := preload("res://scripts/audio/audio_pan.gd")

const VOICES := 5
const RANGE := 1250.0
const SOUND_SPEED := 4200.0   # px/s; real air would give ~1% shifts, this gives ~6-9%
const PASS_LEAD := 0.75       # pass_dry/pass_wet peak this far into the clip
# kind: 0 car, 1 SUV, 2 truck, 3 van, 4 bus, 5 sports car, 6 pickup.
const KIND_ENGINE := ["car", "suv", "truck", "van", "bus", "sport", "suv"]
const KIND_DB := [-3.0, -2.0, 1.5, -2.0, 1.0, 0.0, -1.0]
const KIND_PITCH := [1.0, 0.95, 0.9, 1.0, 0.92, 1.05, 0.9]

var active := false
var pool: Node
var _voices: Array = []   # {car, eng, dry, wet, gain, pitch, passed, brake_cd, prev_dy}
var _rng := RandomNumberGenerator.new()
var _scratch: Array = []


func _ready() -> void:
	_rng.seed = 4711
	for i in range(VOICES):
		var v := {
			"car": null, "gain": 0.0, "doppler": 1.0, "passed": false,
			"brake_cd": 0.0, "was_braking": false, "kind": 0,
			"eng": _player(), "dry": _player(), "wet": _player(),
		}
		v.dry.stream = BANK.stream("tyre/roll_dry", true)
		v.wet.stream = BANK.stream("tyre/roll_wet", true)
		_voices.append(v)
	pool = POOL.new()
	pool.name = "TrafficPool"
	add_child(pool)
	pool.setup(6, "World", true)


func _player() -> AudioStreamPlayer2D:
	var p := PAN.make_player("World")
	add_child(p)
	return p


func stop() -> void:
	active = false
	for v in _voices:
		v.car = null
		v.gain = 0.0
		for key in ["eng", "dry", "wet"]:
			v[key].stop()


func _assigned(c: Dictionary) -> int:
	for i in range(_voices.size()):
		if _voices[i].car != null and is_same(_voices[i].car, c):
			return i
	return -1


# g: bound game node. player_speed in px/s. wet 0..1.
func update(dt: float, g: Node, player_speed: float, wet: float) -> void:
	if g == null:
		return
	var cars: Array = g.cars
	var px: float = g.player_x
	var py: float = g.player_y
	var lane_w: float = g.lane_w
	# Pick the nearest cars (insertion into a short list; no sorting allocations).
	_scratch.clear()
	if active:
		for c in cars:
			if bool(c.get("rammed", false)):
				continue
			var dx := float(c.x) - px
			var dy := float(c.y) - py
			var d := sqrt(dx * dx + dy * dy * 0.7)
			if d > RANGE:
				continue
			var pos := _scratch.size()
			for k in range(_scratch.size()):
				if d < float(_scratch[k][0]):
					pos = k
					break
			if pos < VOICES:
				_scratch.insert(pos, [d, c])
				if _scratch.size() > VOICES:
					_scratch.pop_back()
	# Release voices whose car left the set.
	for v in _voices:
		if v.car == null:
			continue
		var keep := false
		for e in _scratch:
			if is_same(e[1], v.car):
				keep = true
				break
		if not keep:
			v.car = null
	# Assign free voices.
	for e in _scratch:
		if _assigned(e[1]) >= 0:
			continue
		for v in _voices:
			if v.car == null and float(v.gain) < 0.02:
				_attach(v, e[1], py)
				break
	for v in _voices:
		_update_voice(v, dt, g, px, py, lane_w, player_speed, wet)


func _attach(v: Dictionary, c: Dictionary, py: float) -> void:
	var kind := clampi(int(c.get("kind", 0)), 0, KIND_ENGINE.size() - 1)
	v.car = c
	v.kind = kind
	v.passed = false
	v.was_braking = bool(c.get("braking", false))
	v.prev_dy = float(c.y) - py
	v.eng.stream = BANK.stream("traffic/eng_" + KIND_ENGINE[kind], true)
	for key in ["eng", "dry", "wet"]:
		var p: AudioStreamPlayer2D = v[key]
		p.volume_db = -80.0
		if p.stream != null:
			p.play(_rng.randf() * maxf(0.0, p.stream.get_length() - 0.05))


func _update_voice(v: Dictionary, dt: float, g: Node, px: float, py: float, lane_w: float,
		player_speed: float, wet: float) -> void:
	var c = v.car
	var target_gain := 0.0
	if c != null and active:
		target_gain = 1.0
	v.gain = lerpf(float(v.gain), target_gain, minf(1.0, dt * (3.0 if target_gain > v.gain else 5.0)))
	if c == null:
		if float(v.gain) < 0.02:
			for key in ["eng", "dry", "wet"]:
				if v[key].playing:
					v[key].stop()
			return
		# Keep fading out at the last position.
		for key in ["eng", "dry", "wet"]:
			v[key].volume_db = lerpf(v[key].volume_db, -80.0, minf(1.0, dt * 5.0))
		return
	var dx := float(c.x) - px
	var dy := float(c.y) - py
	var cur := float(c.get("cur_speed", player_speed * 0.7))
	# Screen-space velocity of the car relative to us (road scrolls down).
	var vy := player_speed - cur
	var dist := sqrt(dx * dx + dy * dy * 0.7)
	var radial := 0.0
	if dist > 1.0:
		radial = (dy * vy) / maxf(dist, 1.0)
	var dop := clampf(SOUND_SPEED / maxf(800.0, SOUND_SPEED + radial), 0.8, 1.25)
	v.doppler = lerpf(float(v.doppler), dop, minf(1.0, dt * 6.0))
	var att := -20.0 * log(1.0 + pow(dist / 240.0, 1.5)) / log(10.0)
	var kind := int(v.kind)
	var gain_db := att + float(KIND_DB[kind]) + 20.0 * log(maxf(0.0001, float(v.gain))) / log(10.0)
	var pan := clampf(dx / (lane_w * 2.4), -1.0, 1.0)
	var speed_n := clampf(cur / 1100.0, 0.2, 1.6)
	var eng: AudioStreamPlayer2D = v.eng
	var dry: AudioStreamPlayer2D = v.dry
	var wetp: AudioStreamPlayer2D = v.wet
	eng.pitch_scale = clampf(float(KIND_PITCH[kind]) * (0.82 + 0.25 * speed_n) * float(v.doppler), 0.4, 2.5)
	dry.pitch_scale = clampf((0.72 + 0.3 * speed_n) * float(v.doppler), 0.4, 2.5)
	wetp.pitch_scale = dry.pitch_scale
	PAN.place(eng, pan, gain_db - 5.0)
	PAN.place(dry, pan, gain_db - 12.0 + 20.0 * log(maxf(0.0001, 1.0 - wet * 0.7)) / log(10.0))
	PAN.place(wetp, pan, gain_db - 10.0 + 20.0 * log(maxf(0.0001, wet)) / log(10.0))

	# Pass-by: start the recorded whoosh so its peak lands as the car draws level.
	if not bool(v.passed) and absf(dx) < lane_w * 2.3 and absf(vy) > 40.0:
		var ttc := -dy / vy  # seconds until dy == 0
		if ttc > 0.0 and ttc <= PASS_LEAD:
			v.passed = true
			_pass_by(kind, pan, absf(dx) / lane_w, absf(vy), wet, PASS_LEAD - ttc)
	if absf(dy) > 600.0:
		v.passed = false
	# Air brakes on trucks and buses when they start braking.
	v.brake_cd = maxf(0.0, float(v.brake_cd) - dt)
	var braking := bool(c.get("braking", false))
	if braking and not bool(v.was_braking) and (kind == 2 or kind == 4) and float(v.brake_cd) <= 0.0 and dist < 900.0:
		v.brake_cd = 7.0
		if _rng.randf() < 0.6:
			pool.play(BANK.stream("traffic/air_brake"), gain_db - 8.0, _rng.randf_range(0.92, 1.08), pan)
	v.was_braking = braking
	v.prev_dy = dy


func _pass_by(kind: int, pan: float, lanes_away: float, rel_speed: float, wet: float, skip: float) -> void:
	var near_db := -2.0 - clampf(lanes_away - 1.0, 0.0, 1.3) * 10.0
	var speed_db := clampf((rel_speed - 150.0) / 500.0, 0.0, 1.0) * 4.0 - 3.0
	var heavy := kind == 2 or kind == 4
	var asset := "traffic/pass_dry"
	if wet > 0.4:
		asset = "traffic/pass_wet_heavy" if heavy else "traffic/pass_wet"
	var pitch := clampf(0.86 + rel_speed / 2400.0, 0.8, 1.25) * (0.82 if heavy else 1.0)
	var vol := near_db + speed_db + (2.0 if heavy else 0.0)
	if asset == "traffic/pass_wet_heavy":
		skip += 0.6
	pool.play(BANK.stream(asset), vol - 4.0, pitch, pan, maxf(0.0, skip))
	if heavy and lanes_away < 1.6:
		pool.play(BANK.stream("traffic/buffet"), vol - 6.0, _rng.randf_range(0.9, 1.1), pan * 0.7)


# Used when no game is bound (old pass_by hook).
func fallback_pass(side: float, closeness: float, wet: float) -> void:
	var asset := "traffic/pass_wet" if wet > 0.4 else "traffic/pass_dry"
	pool.play(BANK.stream(asset), -6.0 - (1.0 - closeness) * 12.0, _rng.randf_range(0.94, 1.1), side, PASS_LEAD - 0.2)
