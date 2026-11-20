extends Node

# Weather and time-of-day beds on the Ambient bus, crossfaded continuously:
# light/heavy rain, drops on the roof, storm rumble, wind, morning birds, the
# far city at night and a daytime hum. Fog muffles Ambient + World through the
# buses' low-pass and adds a little reverb; overhead structures add echo.

const BANK := preload("res://scripts/audio/audio_bank.gd")
const BUSES := preload("res://scripts/audio/audio_buses.gd")
const POOL := preload("res://scripts/audio/audio_pool.gd")

var beds: Dictionary = {}
var pool: Node
var running := false
var level_db := 0.0         # menu vs race, pause
var _level_target := -12.0
var _rng := RandomNumberGenerator.new()
var _space_cut := 20000.0
var _space_wet := 0.0

# Inputs (set by the director each frame).
var rain := 0.0
var storm := 0.0
var wind := 0.15
var fog := 0.0
var night := 0.0
var tod := 0.15
var overhead := 0.0
var speed_n := 0.0

const BEDS := {
	"rain_light": "amb/rain_light", "rain_heavy": "amb/rain_heavy", "rain_roof": "amb/rain_roof",
	"storm": "amb/storm_low", "wind": "amb/wind", "birds": "amb/birds",
	"city_night": "amb/city_night", "city_hum": "amb/city_hum", "underpass": "amb/underpass",
}


func _ready() -> void:
	_rng.seed = 1999
	for key in BEDS:
		var p := AudioStreamPlayer.new()
		p.bus = "Ambient"
		p.volume_db = -80.0
		p.stream = BANK.stream(BEDS[key], true)
		add_child(p)
		beds[key] = p
	pool = POOL.new()
	pool.name = "AmbientPool"
	add_child(pool)
	pool.setup(3, "Ambient", true)


func start() -> void:
	if running:
		return
	running = true


func stop() -> void:
	running = false
	for key in beds:
		beds[key].stop()
		beds[key].stream = null
	pool.stop_all()


func set_level(db: float) -> void:
	_level_target = db


static func _db(w: float) -> float:
	return 20.0 * log(maxf(w, 0.00001)) / log(10.0)


static func _smooth(a: float, b: float, x: float) -> float:
	return smoothstep(a, b, x)


func _bed(key: String, db: float, dt: float, pitch := 1.0) -> void:
	var p: AudioStreamPlayer = beds[key]
	var target := db + level_db
	p.volume_db = lerpf(p.volume_db, target, minf(1.0, dt * 1.6))
	p.pitch_scale = pitch
	# Beds only hold a playback while audible: a silent bed is stopped and
	# restarts at a random point when it fades back in.
	var silent := p.volume_db < -60.0 and target < -60.0
	if silent and p.playing:
		p.stop()
	elif not silent and not p.playing and p.stream != null and running:
		p.play(_rng.randf() * maxf(0.0, p.stream.get_length() - 0.1))


func update(dt: float) -> void:
	if not running:
		return
	level_db = lerpf(level_db, _level_target, minf(1.0, dt * 2.5))
	var heavy := _smooth(0.35, 0.9, rain)
	var light := clampf(rain * 2.4, 0.0, 1.0) * (1.0 - heavy * 0.55)
	_bed("rain_light", -6.0 + _db(light), dt)
	_bed("rain_heavy", -5.0 + _db(heavy), dt)
	_bed("rain_roof", -9.0 + _db(clampf(rain * 1.5, 0.0, 1.0)), dt)
	_bed("storm", -6.0 + _db(storm), dt)
	var w := _smooth(0.12, 1.05, wind)
	_bed("wind", -10.0 + _db(clampf(w + storm * 0.3, 0.0, 1.0)), dt, 0.92 + w * 0.12)
	# Birds: strongest around dawn (tod ~0.86..0.15), present by day, gone at
	# night and in rain or storms.
	var dawn_d := absf(fposmod(tod - 0.97 + 0.5, 1.0) - 0.5)
	var morning := clampf(1.0 - dawn_d / 0.16, 0.0, 1.0)
	var birds := maxf(morning, (1.0 - night) * 0.35) * (1.0 - night) * (1.0 - clampf(rain * 2.0, 0.0, 1.0)) * (1.0 - storm) * (1.0 - fog * 0.4)
	_bed("birds", -11.0 + _db(birds), dt)
	_bed("city_night", -12.0 + _db(night * (1.0 - rain * 0.4)), dt)
	_bed("city_hum", -19.0 + _db((1.0 - night) * 0.8 + 0.2), dt)
	_bed("underpass", -9.0 + _db(overhead), dt)
	# Fog muffles the world and the ambience; overhead structures echo.
	var cut := lerpf(20000.0, 1300.0, pow(clampf(fog, 0.0, 1.0), 0.7))
	var wet := 0.22 * fog + 0.38 * overhead
	_space_cut = lerpf(_space_cut, cut, minf(1.0, dt * 2.0))
	_space_wet = lerpf(_space_wet, wet, minf(1.0, dt * 4.0))
	BUSES.set_space("Ambient", _space_cut, _space_wet * 0.6, 0.6 + fog * 0.3)
	BUSES.set_space("World", lerpf(20000.0, _space_cut, 0.8), _space_wet, 0.45 + overhead * 0.35)


# Thunder from flash-to-bang delay: short delay = close crack, long = far roll.
func thunder(delay: float) -> void:
	var k := clampf((delay - 0.5) / 1.3, 0.0, 1.0)
	var pan := _rng.randf_range(-0.7, 0.7)
	if k < 0.35:
		pool.play(BANK.stream("amb/thunder_close"), -1.0 - k * 6.0 + _rng.randf_range(-1.5, 1.0) + level_db,
			_rng.randf_range(0.92, 1.04), pan)
	else:
		var asset := "amb/thunder_far_%d" % _rng.randi_range(0, 1)
		pool.play(BANK.stream(asset), -4.0 - k * 7.0 + _rng.randf_range(-1.5, 1.0) + level_db,
			_rng.randf_range(0.82, 0.98), pan)
