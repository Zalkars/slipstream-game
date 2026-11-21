extends Node

# Audio director (autoload "Sfx").
#
# 0.8.0 rework: sound effects are baked OGG Vorbis assets (godot/audio/, built
# by tools/audio/build_audio.py from synthesis plus CC0 recordings listed in
# docs/credits.md). Music is still synthesised here on a worker thread.
#
# Buses (see audio/audio_buses.gd): Master (compressor + limiter) <- Music, SFX;
# SFX <- Engine, World, Ambient, UI. The player's sound switch/slider drives SFX.
#
# Subsystems:
#   engine_audio   own car: per-class engine loops, gears, nitro, tyres, brakes
#   traffic_audio  continuous voices for nearby traffic + pass-bys
#   ambience_audio rain, thunder, wind, birds, city, fog muffling, echo
# plus pooled one-shots for impacts, road features and UI.
#
# The game binds itself with bind_game(); everything else is read from its
# public state, so game.gd only needs that one call. Every public function that
# existed before 0.8.0 is kept with the same signature.

const RATE := 22050
const TBL := 2048

const BANK := preload("res://scripts/audio/audio_bank.gd")
const BUSES := preload("res://scripts/audio/audio_buses.gd")
const POOL := preload("res://scripts/audio/audio_pool.gd")
const PAN := preload("res://scripts/audio/audio_pan.gd")
const ENGINE := preload("res://scripts/audio/engine_audio.gd")
const TRAFFIC := preload("res://scripts/audio/traffic_audio.gd")
const AMBIENCE := preload("res://scripts/audio/ambience_audio.gd")

const BUS_BASE_DB := {"World": -1.5, "Ambient": -3.0}
const JOINT_PERIOD := 760.0     # game.gd road seam spacing (px)
const RAIL_PERIOD := 190.0      # guard-rail post spacing (px)

var music_player: AudioStreamPlayer

var sfx_bus := 0
var music_bus := 0
var sfx_on := true
var music_on := true
var muted := false
var sfx_volume := 0.9
var music_volume := 0.75

var engine_audio: Node
var traffic_audio: Node
var ambience: Node
var world_pool: Node
var ui_pool: Node
var listener: AudioListener2D
var scrape_player: AudioStreamPlayer2D

var _game_ref: WeakRef = null
var _engine_on := false
var _paused := false
var _rewinding := false
var _boost := false
var _braking := false
var _overheated := false
var _slip := 0.0
var _last_speed := 0.0
var _wetness := 0.0
var _wind_amt := 0.15
var _storm_amt := 0.0
var _rain := 0.0
var _overhead_api := 0.0
var _scrape_amt := 0.0
var _scrape_pan := 0.0
var _scrape_hold := 0.0
var _duck := 0.0
var _duck_hold := 0.0
var _crash_cd := 0.0
var _prev_px := -1.0
var _lateral := 0.0
var _flash_t := -100.0
var _prev_lightning := 0.0
var _prev_puddle := 0.0
var _joint_ph := PackedFloat32Array([-1.0, -1.0])
var _rail_ph := -1.0
var _clock := 0.0
var _state := {"speed": 0.0, "top": 1100.0, "boost": false, "brake": false, "overheated": false,
	"draft": 0.0, "wet": 0.0, "lateral": 0.0, "sling": false, "grip": 1.0}
var _rng := RandomNumberGenerator.new()

var _music_buf := PackedFloat32Array()
var _music_task := -1
var _music_busy := false


func _ready() -> void:
	_rng.seed = 2600
	BUSES.setup()
	sfx_bus = AudioServer.get_bus_index("SFX")
	music_bus = AudioServer.get_bus_index("Music")
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)

	listener = AudioListener2D.new()
	listener.name = "Listener"
	add_child(listener)
	listener.make_current()

	engine_audio = ENGINE.new()
	engine_audio.name = "EngineAudio"
	add_child(engine_audio)
	traffic_audio = TRAFFIC.new()
	traffic_audio.name = "TrafficAudio"
	add_child(traffic_audio)
	ambience = AMBIENCE.new()
	ambience.name = "Ambience"
	add_child(ambience)
	world_pool = POOL.new()
	world_pool.name = "WorldPool"
	add_child(world_pool)
	world_pool.setup(10, "World", true)
	ui_pool = POOL.new()
	ui_pool.name = "UIPool"
	add_child(ui_pool)
	ui_pool.setup(4, "UI", false)
	scrape_player = PAN.make_player("World")
	scrape_player.stream = BANK.stream("impact/scrape", true)
	scrape_player.volume_db = -80.0
	add_child(scrape_player)

	music_player = AudioStreamPlayer.new()
	music_player.bus = "Music"
	music_player.volume_db = -19.0
	add_child(music_player)
	ambience.start()


# --- binding ----------------------------------------------------------------

func bind_game(g: Node) -> void:
	_game_ref = weakref(g) if g != null else null
	_prev_px = -1.0
	_joint_ph[0] = -1.0
	_joint_ph[1] = -1.0
	_rail_ph = -1.0


func _game() -> Node:
	if _game_ref == null:
		return null
	var g = _game_ref.get_ref()
	if g == null or not is_instance_valid(g) or not g.is_inside_tree():
		return null
	return g


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
		music_player.volume_db = _music_db()
		music_player.play()


func _music_db() -> float:
	# Music sits a little lower while racing so engine and traffic read clearly.
	if _paused:
		return -30.0
	return -21.0 if _engine_on else -19.0


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
	# Release every playback before the engine shuts down, so the streams are
	# not reported as leaked at exit.
	engine_audio.stop()
	traffic_audio.stop()
	ambience.stop()
	world_pool.stop_all()
	ui_pool.stop_all()
	engine_audio.pool.stop_all()
	traffic_audio.pool.stop_all()
	scrape_player.stop()
	BANK.clear()


func stop_music() -> void:
	if music_player != null:
		music_player.stop()


# --- frame update -----------------------------------------------------------

func _process(delta: float) -> void:
	_poll_music()
	var dt := minf(delta, 0.05)
	_clock += dt
	if _crash_cd > 0.0:
		_crash_cd -= dt
	var g := _game()
	var running := false
	if g != null:
		running = bool(g.running) and not bool(g.demo)
		_read_world(g, dt)
	ambience.rain = lerpf(ambience.rain, _rain, minf(1.0, dt * 2.0))
	ambience.storm = _storm_amt
	ambience.wind = _wind_amt
	ambience.set_level(-26.0 if _paused else (0.0 if _engine_on else -12.0))
	ambience.update(dt)

	_state.speed = _last_speed
	_state.boost = _boost
	_state.brake = _braking
	_state.overheated = _overheated
	_state.draft = _slip
	_state.wet = _wetness
	_state.lateral = _lateral
	if g != null:
		_state.top = float(g.top_speed)
		var st = g.get("slingshot_t")
		_state.sling = st != null and float(st) > 0.0 and _engine_on
		var gm = g.get("grip_mu")
		_state.grip = float(gm) if gm != null else 1.0
	engine_audio.paused = _paused
	engine_audio.rewinding = _rewinding
	engine_audio.update(dt, _state)

	traffic_audio.active = _engine_on and running and not _paused and not _rewinding
	traffic_audio.update(dt, g, _last_speed, _wetness)
	if g != null and _engine_on and running and not _paused and not _rewinding:
		_road_features(g)
	_update_scrape(dt)
	# A hard stop pushes the world back a little so the tyres cut through.
	if engine_audio.squeal_level > 0.2:
		_duck_to(-6.0 * engine_audio.squeal_level)
	_update_duck(dt)


func _poll_music() -> void:
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
		music_player.volume_db = _music_db()
		music_player.play()


func _read_world(g: Node, dt: float) -> void:
	ambience.fog = float(g.fog_amount)
	ambience.tod = float(g.time_of_day)
	if g.has_method("get_night_factor"):
		ambience.night = float(g.get_night_factor())
	# Optional state other systems may add (bridges, overpasses, tunnels).
	var oh = g.get("overhead_amount")
	ambience.overhead = clampf(float(oh) if oh != null else _overhead_api, 0.0, 1.0)
	_overhead_api = maxf(0.0, _overhead_api - dt * 0.5)
	# Lightning flash: remember when it struck to tell near from far thunder.
	var lt := float(g.lightning)
	if lt > _prev_lightning + 0.3:
		_flash_t = _clock
	_prev_lightning = lt
	var px := float(g.player_x)
	if _prev_px >= 0.0 and dt > 0.0:
		_lateral = lerpf(_lateral, (px - _prev_px) / dt, minf(1.0, dt * 12.0))
	_prev_px = px
	var sil = g.get("player_silhouette")
	if sil != null and _engine_on:
		engine_audio.set_car(str(sil))
	# Puddle splash (all-weather perk drives through standing water).
	var pc = g.get("_puddle_cd")
	if pc != null:
		if float(pc) > _prev_puddle + 0.5 and _engine_on:
			world_pool.play(BANK.stream("road/splash"), -5.0, _rng.randf_range(0.9, 1.1), 0.0)
		_prev_puddle = float(pc)


func _road_features(g: Node) -> void:
	var scroll := float(g.scroll)
	var py := float(g.player_y)
	var ch := float(g.car_h)
	var speed := _last_speed
	if speed < 120.0:
		return
	var sp = g.get("seam_period")
	var period := float(sp) if sp != null else JOINT_PERIOD
	# Concrete/tar joints under the front then the rear axle: "ta-dum".
	var axle := [py - ch * 0.30, py + ch * 0.30]
	var vol := -17.0 + clampf(speed / 1400.0, 0.0, 1.0) * 6.0 - _wetness * 3.0
	for i in range(2):
		var ph := fposmod(scroll - float(axle[i]), period)
		if _joint_ph[i] >= 0.0 and ph < _joint_ph[i] - period * 0.5:
			world_pool.play(BANK.stream("road/joint_%d" % i), vol, _rng.randf_range(0.92, 1.06), 0.0)
		_joint_ph[i] = ph
	# Guard-rail posts whoosh past when we drive in an edge lane.
	var lanes := int(g.get("LANES")) if g.get("LANES") != null else 4
	var lane := int(g.lane)
	var rph := fposmod(scroll - py, RAIL_PERIOD)
	if lane == 0 or lane == lanes - 1:
		if _rail_ph >= 0.0 and rph < _rail_ph - RAIL_PERIOD * 0.5:
			var side := -0.85 if lane == 0 else 0.85
			world_pool.play(BANK.stream("road/rail_puff"), -21.0 + clampf(speed / 1500.0, 0.0, 1.0) * 6.0,
				_rng.randf_range(0.85, 1.15) * (0.8 + speed / 3000.0), side)
	_rail_ph = rph


func _update_scrape(dt: float) -> void:
	if _scrape_hold > 0.0:
		_scrape_hold -= dt
	else:
		_scrape_amt = maxf(0.0, _scrape_amt - dt * 3.0)
	var on := _scrape_amt > 0.01 and not _paused
	if on and not scrape_player.playing and scrape_player.stream != null:
		scrape_player.play(_rng.randf() * 1.5)
	if scrape_player.playing:
		PAN.place(scrape_player, _scrape_pan, -10.0 + 20.0 * log(maxf(_scrape_amt, 0.0001)) / log(10.0))
		scrape_player.pitch_scale = 0.85 + _scrape_amt * 0.25 + clampf(_last_speed / 3000.0, 0.0, 0.3)
		if not on:
			scrape_player.stop()


func _duck_to(db: float, hold := 0.0) -> void:
	_duck = minf(_duck, db)
	_duck_hold = maxf(_duck_hold, hold)


func _update_duck(dt: float) -> void:
	if _duck_hold > 0.0:
		_duck_hold -= dt
	else:
		_duck = lerpf(_duck, 0.0, minf(1.0, dt * 1.8))
	var hold_nitro := -3.5 if _boost and _engine_on else 0.0
	var d := minf(_duck, hold_nitro)
	for bus in BUS_BASE_DB:
		var idx := AudioServer.get_bus_index(bus)
		if idx >= 0:
			var k := 1.0 if bus == "Ambient" else 0.5
			AudioServer.set_bus_volume_db(idx, float(BUS_BASE_DB[bus]) + d * k)


# --- engine loop ------------------------------------------------------------

func play_engine() -> void:
	_engine_on = true
	_boost = false
	_braking = false
	_overheated = false
	_rewinding = false
	_paused = false
	_slip = 0.0
	var g := _game()
	if g != null and g.get("player_silhouette") != null:
		engine_audio.set_car(str(g.player_silhouette))
	elif engine_audio.spec.is_empty():
		engine_audio.set_car("sedan")
	engine_audio.start()
	if music_player != null and music_player.playing:
		music_player.volume_db = _music_db()


func stop_engine() -> void:
	_engine_on = false
	_braking = false
	_overheated = false
	_rewinding = false
	_boost = false
	engine_audio.stop()
	traffic_audio.stop()
	if music_player != null and music_player.playing:
		music_player.volume_db = _music_db()


func set_paused(p: bool) -> void:
	_paused = p
	if music_player != null and music_player.playing:
		music_player.volume_db = _music_db()


func update_engine(px_speed: float, boost: bool, is_braking := false, overheated := false, slip := 0.0) -> void:
	_last_speed = px_speed
	_boost = boost
	_braking = is_braking
	_overheated = overheated
	_slip = clampf(slip, 0.0, 1.0)


func set_rain_intensity(amt: float) -> void:
	_rain = clampf(amt, 0.0, 1.0)


func set_weather(wetness: float, wind_amt: float, storm_amt: float) -> void:
	_wetness = clampf(wetness, 0.0, 1.0)
	_wind_amt = clampf(wind_amt, 0.0, 1.2)
	_storm_amt = clampf(storm_amt, 0.0, 1.0)


# --- optional hooks for other systems (all safe to never call) ---------------

# Generic impact. force 0..1 picks the layers, side -1..1 pans.
func impact(force: float, side := 0.0) -> void:
	var f := clampf(force, 0.0, 1.0)
	var vol := -8.0 + f * 7.0
	if f < 0.35:
		world_pool.play(BANK.stream("impact/knock"), vol, _rng.randf_range(0.9, 1.1), side)
		world_pool.play(BANK.stream("impact/clank"), vol - 6.0, _rng.randf_range(0.9, 1.15), side)
		_duck_to(-3.0)
	elif f < 0.7:
		world_pool.play(BANK.stream("impact/door_hit"), vol, _rng.randf_range(0.9, 1.05), side)
		world_pool.play(BANK.stream("impact/metal_hit"), vol - 3.0, _rng.randf_range(0.9, 1.1), side)
		world_pool.play(BANK.stream("impact/sub"), vol - 4.0, 1.0, 0.0)
		_duck_to(-6.0)
	else:
		_crash_layers(side, f)


# Side contact (rail or another car), call every frame while it lasts.
func scrape(amount: float, side := 0.0) -> void:
	_scrape_amt = maxf(_scrape_amt, clampf(amount, 0.0, 1.0))
	_scrape_pan = clampf(side, -1.0, 1.0)
	_scrape_hold = 0.08


# Bridge / overpass / tunnel overhead, 0..1; call every frame while under it.
func set_overhead(amount: float) -> void:
	_overhead_api = clampf(amount, 0.0, 1.0)


# --- one-shots --------------------------------------------------------------

func _crash_layers(side: float, force := 1.0) -> void:
	var v := -1.0 - (1.0 - force) * 6.0
	world_pool.play(BANK.stream("impact/crash_heavy"), v, _rng.randf_range(0.94, 1.04), side)
	world_pool.play(BANK.stream("impact/crash_metal"), v - 5.0, _rng.randf_range(0.9, 1.05), side * 0.6)
	world_pool.play(BANK.stream("impact/glass_%d" % _rng.randi_range(0, 1)), v - 7.0, _rng.randf_range(0.95, 1.1), -side * 0.4)
	world_pool.play(BANK.stream("impact/sub"), v - 1.0, 1.0, 0.0)
	_scrape_amt = 0.8
	_scrape_pan = side
	_scrape_hold = 0.5
	_duck_to(-10.0, 0.4)


func crash() -> void:
	if _crash_cd > 0.0:
		return
	_crash_cd = 0.3
	_crash_layers(_rng.randf_range(-0.3, 0.3))


func thunder() -> void:
	ambience.thunder(_clock - _flash_t if _clock - _flash_t < 5.0 else 1.2)


func bump() -> void:
	impact(0.25, 0.0)


func whoosh(pan_side := 0.0) -> void:
	world_pool.play(BANK.stream("traffic/pass_dry"), -12.0 - absf(pan_side) * 3.0, _rng.randf_range(1.0, 1.15), pan_side, 0.45)


func pass_by(side: float, closeness := 1.0) -> void:
	# With a bound game, traffic_audio already tracks and voices every pass.
	if _game() != null and _engine_on:
		return
	traffic_audio.fallback_pass(side, clampf(closeness, 0.0, 1.0), _wetness)


func click() -> void:
	ui_pool.play(BANK.stream("ui/click"), -6.0, _rng.randf_range(0.97, 1.03))


func record() -> void:
	ui_pool.play(BANK.stream("ui/record"), -5.0)


func pickup_coin() -> void:
	ui_pool.play(BANK.stream("ui/coin"), -8.0, _rng.randf_range(0.98, 1.03))


func pickup_nitro() -> void:
	ui_pool.play(BANK.stream("ui/pickup"), -7.0)


func pickup() -> void:
	ui_pool.play(BANK.stream("ui/pickup"), -7.0)


func boost_burst() -> void:
	# The ignition itself plays from engine_audio on the boost edge; this adds
	# the ducking so the world steps back as the nitro lights.
	_duck_to(-5.0, 0.3)
	if not _engine_on:
		ui_pool.play(BANK.stream("nitro/ignite"), -6.0)


func cut_in() -> void:
	ui_pool.play(BANK.stream("ui/cutin"), -6.0)
	world_pool.play(BANK.stream("traffic/pass_dry"), -13.0, 1.12, 0.0, 0.5)


func brake_overheat() -> void:
	engine_audio.one_shot("nitro/blowoff", -6.0, 0.62)
	world_pool.play(BANK.stream("impact/metal_hit"), -10.0, 0.8, 0.0)


func rewind_start() -> void:
	_rewinding = true
	ui_pool.play(BANK.stream("ui/rewind"), -5.0)


func rewind_stop() -> void:
	_rewinding = false


func slingshot_ready() -> void:
	engine_audio.one_shot("nitro/sling_ready", -7.0)


func slingshot_snap() -> void:
	engine_audio.one_shot("nitro/sling_snap", -7.0)
	_duck_to(-2.0)


func ram_hit() -> void:
	impact(0.6, 0.0)
	world_pool.play(BANK.stream("impact/crash_metal"), -9.0, 1.1, 0.0)


func radar_ok() -> void:
	ui_pool.play(BANK.stream("ui/radar"), -7.0)


func shield_trigger() -> void:
	engine_audio.one_shot("nitro/shield", -3.0)
	_duck_to(-6.0, 0.3)


func duel_win() -> void:
	ui_pool.play(BANK.stream("ui/record"), -4.0, 1.12)


# --- music helpers ----------------------------------------------------------

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


static func _loop_samples(f: PackedFloat32Array, loop_len: int, fade: int) -> PackedFloat32Array:
	for i in range(fade):
		var a := float(i) / float(fade)
		f[i] = f[i] * a + f[loop_len + i] * (1.0 - a)
	var out := PackedFloat32Array()
	out.resize(loop_len)
	for i in range(loop_len):
		out[i] = f[i]
	return out


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
