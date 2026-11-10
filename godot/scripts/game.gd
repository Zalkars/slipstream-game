class_name Game
extends Node2D

# Top-down highway racer: procedural road, traffic, pickups, braking and nitro.

signal hud_changed(score: int, kmh: int, nitro: float, combo: int, coins: int, boosting: bool)
signal run_ended(score: int, distance: int, near: int, coins: int)
signal near_miss(combo: int)
signal cut_in(combo: int)
signal pickup_taken(kind: int)
signal lane_changed(new_lane: int)
signal brake_state_changed(is_braking: bool)
signal status_changed(slip: float, brake_heat: float, overheated: bool)
signal rewind_started()
signal rewind_finished()
signal nitro_boosted()

const LANES := 4
const DEMO_SPEED := 620.0
const NITRO_SEG := 1.0 / 3.0
const BOOST_TIME := 1.6
const BRAKE_MULT := 0.42
const CRUISE_KMH := 100.0
const TOP_KMH_SCALE := 0.3
const BOOST_KMH_SCALE := 1.2
const BRAKE_HEAT_RATE := 0.46
const BRAKE_HEAT_LOAD := 0.24
const BRAKE_COOL_RATE := 0.34
const BRAKE_RESTART_HEAT := 0.28
const SLIP_BONUS := 0.15
const CUTIN_WINDOW := 0.72
const CUTIN_MAX_GAP := 230.0
const ROAD_CYCLE := 3600.0
const DAY_LENGTH := 360.0
const WEATHER_CLEAR := 0
const WEATHER_CLOUDY := 1
const WEATHER_RAIN := 2
const WEATHER_STORM := 3
const WEATHER_FOG := 4
# t, ambient r/g/b, night factor. One full day takes DAY_LENGTH seconds.
const SKY_KEYS := [
	[0.00, 1.00, 1.00, 1.00, 0.00],
	[0.24, 1.00, 1.00, 1.00, 0.00],
	[0.37, 1.05, 0.97, 0.88, 0.00],
	[0.44, 1.04, 0.90, 0.77, 0.08],
	[0.49, 0.94, 0.80, 0.77, 0.28],
	[0.55, 0.70, 0.65, 0.76, 0.60],
	[0.60, 0.46, 0.49, 0.62, 0.88],
	[0.64, 0.42, 0.46, 0.60, 1.00],
	[0.80, 0.42, 0.46, 0.60, 1.00],
	[0.86, 0.54, 0.52, 0.63, 0.66],
	[0.92, 0.80, 0.68, 0.62, 0.22],
	[0.97, 0.95, 0.90, 0.84, 0.03],
	[1.00, 1.00, 1.00, 1.00, 0.00],
]
const TRAFFIC_COLORS := [
	Color("#e8e7e3"), Color("#b9bdc1"), Color("#3d4147"), Color("#1b1e22"),
	Color("#5e2b2b"), Color("#2c4a6e"), Color("#3c5c48"), Color("#c9c3b4"),
	Color("#7a1f24"), Color("#1f6a78"), Color("#d1a12c"), Color("#e3ddd0"),
	Color("#4b3b66"), Color("#8a5a2b"), Color("#2f6b3f"), Color("#9aa4ae"),
]
const TRAILER_COLORS := [
	Color("#d9dad6"), Color("#c3c5c1"), Color("#8f969c"),
	Color("#b7b0a4"), Color("#6d7c86"), Color("#a4483f"),
]
const BUS_ACCENTS := [
	Color("#d64a3a"), Color("#2e7fbe"), Color("#3f9a5c"),
	Color("#e0a52a"), Color("#e8e4d8"),
]
# kind: 0 car, 1 SUV, 2 truck, 3 van, 4 bus, 5 sports car, 6 pickup.
const TRAFFIC_TYPES := [
	{"kind": 0, "weight": 0.26, "w": 1.00, "h": 1.00, "rel": [0.70, 0.80]},
	{"kind": 1, "weight": 0.14, "w": 1.06, "h": 1.08, "rel": [0.66, 0.76]},
	{"kind": 2, "weight": 0.12, "w": 1.14, "h": 1.72, "rel": [0.54, 0.64]},
	{"kind": 3, "weight": 0.13, "w": 1.04, "h": 1.38, "rel": [0.63, 0.73]},
	{"kind": 4, "weight": 0.07, "w": 1.12, "h": 2.05, "rel": [0.48, 0.58]},
	{"kind": 5, "weight": 0.14, "w": 1.05, "h": 0.96, "rel": [0.74, 0.86]},
	{"kind": 6, "weight": 0.14, "w": 1.05, "h": 1.16, "rel": [0.68, 0.78]},
]

var W := 720.0
var H := 1560.0
var road_w := 518.0
var road_x := 101.0
var lane_w := 129.5
var car_w := 86.0
var car_h := 163.0
var player_y := 1320.0

var scroll := 0.0
var speed := 760.0
var t := 0.0
var distance := 0.0
var score := 0.0
var bonus := 0.0
var near := 0
var combo := 0
var combo_t := 0.0
var nitro := NITRO_SEG
var boosting := false
var boost_t := 0.0
var braking := false
var lane := 1
var player_x := 300.0
var player_tilt := 0.0
var cars: Array = []
var items: Array = []
var spawn_t := 0.8
var item_t := 1.4
var demo := true
var running := false
var paused := false
var time_scale := 1.0
var crashed := false
var shake := 0.0
var flash := 0.0
var particles: Array = []
var decor: Array = []
var road_scars: Array = []
var skid_marks: Array = []
var _has_prev_skid := false
var _prev_skid_l := Vector2.ZERO
var _prev_skid_r := Vector2.ZERO
var _nitro_cooldown := 0.0

# Brake temperature, slipstream, weather, day/night and tutorial rewind.
var brake_heat := 0.0
var overheated := false
var slip := 0.0
var time_of_day := 0.15
var weather_state := 0
var weather_timer := 45.0
var rain_amount := 0.0
var fog_amount := 0.0
var cloud_amount := 0.05
var storm_amount := 0.0
var wetness := 0.0
var wind := 0.15
var lightning := 0.0
var lightning_next := 9.0
var thunder_delay := 0.0
var lightning_bolt := PackedVector2Array()
var lightning_branches: Array = []
var rain_drops: Array = []
var rain_splashes: Array = []
var puddles: Array = []
var rear_hazards: Array = []
var tutorial_mode := false
var rewinding := false
var rewind_frames: Array = []
var _rewind_step_t := 0.0
var _rewind_invuln := 0.0
var _snapshot_t := 0.0
var _cutin_window := 0.0
var _cutin_lane := -1
var _rear_spawn_t := 0.5

var car_index := 0
var base_speed := 740.0
var top_speed := 1100.0
var handling := 12.0

var player_color := Color("#b32b26")
var player_stripe := true
var player_wing := false
var player_stripe_col := Color("#f0ede4")
var player_silhouette := "sedan"

var control_mode := "buttons"
var free_lane := 3
var free_t := 7.0
var pickup_coins := 0

var swipe_start := Vector2.ZERO
var swipe_used := true

var asphalt_tex: ImageTexture
var grass_tex: ImageTexture
var beam_tex: ImageTexture
var glow_tex: ImageTexture
var rain_tex: ImageTexture
var wet_tex: ImageTexture
var streak_tex: ImageTexture
var _sx := 0.0
var _sy := 0.0

# Rain motion state, shared by the simulation and the renderer so a streak's
# angle always matches the velocity that actually moved it.
var rain_vx := -60.0
var rain_vy := 900.0
var rain_scale := 60.0  # screen px/s per 1000 px/s of simulated fall
var rain_gust := 1.0
var pending = null  # one-shot rendered probe used by the QA harness
var pending_rect := false
# QA harness switch: draw the rain field as flat colour-coded marks so the
# calibration scripts can measure exact streak geometry.
const QA_FIELD := false
# Set once in _draw(): the canvas transform is letterboxed, so widget-space
# pixels are not pixel-space pixels. Every measurement in the QA harness needs
# this factor to talk about real screen pixels.
var px_per_unit := 1.0
var rain_lens: Array = []


static func top_kmh(px_speed: float) -> int:
	return int(round(px_speed * TOP_KMH_SCALE))


# Arcade gauge: the car cruises around CRUISE_KMH and only its top speed matches
# the real px/s scale, so normal driving doesn't read like a hypercar.
static func gauge_kmh(px_speed: float, base_px: float, top_px: float) -> int:
	if px_speed <= 0.0:
		return 0
	if base_px <= 0.0 or top_px <= base_px:
		return top_kmh(maxf(px_speed, 0.0))
	var top_kmh_val := top_px * TOP_KMH_SCALE
	if px_speed <= base_px:
		return int(round(px_speed / base_px * CRUISE_KMH))
	if px_speed <= top_px:
		var k := (px_speed - base_px) / (top_px - base_px)
		return int(round(lerpf(CRUISE_KMH, top_kmh_val, k)))
	var over := clampf((px_speed - top_px) / (top_px * 0.5), 0.0, 1.0)
	return int(round(lerpf(top_kmh_val, top_kmh_val * BOOST_KMH_SCALE, over)))


func _ready() -> void:
	asphalt_tex = _noise_tex(256, Color(0.365, 0.375, 0.395), 0.034, 11)
	grass_tex = _noise_tex(128, Color(0.400, 0.500, 0.295), 0.042, 23)
	beam_tex = Fx.headlight_tex()
	glow_tex = Fx.glow_tex()
	rain_tex = Fx.rain_tex()
	wet_tex = Fx.wet_tex()
	streak_tex = Fx.streak_tex()
	_gen_decor()
	_gen_road_scars()
	_gen_puddles()
	_layout()
	_gen_rain()
	get_viewport().size_changed.connect(_layout)
	start_demo()


# Three parallax layers. "fall" is the simulated downward speed of the drop in
# front of the windscreen; the renderer converts it to screen px/s and the same
# number drives the motion, so streaks never look like painted decals.
func _gen_rain() -> void:
	rain_drops.clear()
	# Drops are distributed over the screen in proportion to how visible they
	# are: the far layer is thin and dim, the near layer is thick and bright,
	# but it is also sparser, so the sheet reads as depth instead of hatching.
	for i in range(420):
		var roll := randf()
		var layer := 0
		var fall := 900.0
		var alpha := 0.20
		var width := 1.6
		if roll < 0.56:
			layer = 0
			fall = randf_range(700.0, 940.0)
			alpha = randf_range(0.10, 0.17)
			width = randf_range(0.9, 1.4)
		elif roll < 0.86:
			layer = 1
			fall = randf_range(950.0, 1230.0)
			alpha = randf_range(0.17, 0.27)
			width = randf_range(1.4, 2.1)
		else:
			layer = 2
			fall = randf_range(1230.0, 1620.0)
			alpha = randf_range(0.26, 0.40)
			width = randf_range(2.0, 3.0)
		rain_drops.append({
			"x": randf_range(-60.0, W + 60.0),
			"y": randf_range(0.0, H),
			"fall": fall,
			"alpha": alpha,
			"width": width,
			"layer": layer,
		})


# --- setup ------------------------------------------------------------------

func _layout() -> void:
	var vs := get_viewport_rect().size
	W = vs.x
	H = vs.y
	road_w = minf(W * 0.72, 640.0)
	lane_w = road_w / float(LANES)
	road_x = (W - road_w) * 0.5
	car_w = lane_w * 0.665
	car_h = car_w * 1.9
	player_y = H - 330.0
	if demo:
		player_x = _lane_x(lane)


func _lane_x(l: int) -> float:
	return road_x + lane_w * (float(l) + 0.5)


func _noise_tex(size: int, base: Color, variation: float, seed_val: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	# Low-frequency value noise gives asphalt its uneven, worn patches; the
	# per-pixel grain on top reads as aggregate when tiled.
	var cells := 8
	var grid := PackedFloat32Array()
	grid.resize((cells + 1) * (cells + 1))
	for i in range(grid.size()):
		grid[i] = rng.randf_range(-1.0, 1.0)
	# Wrap the low-frequency grid so the tiled asphalt has no visible seams.
	for i in range(cells + 1):
		grid[i * (cells + 1) + cells] = grid[i * (cells + 1)]
		grid[cells * (cells + 1) + i] = grid[i]
	for y in range(size):
		for x in range(size):
			var gx := float(x) / float(size) * float(cells)
			var gy := float(y) / float(size) * float(cells)
			var ix := clampi(int(gx), 0, cells - 1)
			var iy := clampi(int(gy), 0, cells - 1)
			var fx := gx - float(ix)
			var fy := gy - float(iy)
			fx = fx * fx * (3.0 - 2.0 * fx)
			fy = fy * fy * (3.0 - 2.0 * fy)
			var g00 := grid[iy * (cells + 1) + ix]
			var g10 := grid[iy * (cells + 1) + ix + 1]
			var g01 := grid[(iy + 1) * (cells + 1) + ix]
			var g11 := grid[(iy + 1) * (cells + 1) + ix + 1]
			var coarse := lerpf(lerpf(g00, g10, fx), lerpf(g01, g11, fx), fy)
			var fine := rng.randf_range(-1.0, 1.0)
			var n := coarse * 0.72 + fine * 0.34
			img.set_pixel(x, y, Color(
				clampf(base.r + n * variation, 0.0, 1.0),
				clampf(base.g + n * variation, 0.0, 1.0),
				clampf(base.b + n * variation, 0.0, 1.0),
				1.0
			))
	for i in range(size * 4):
		var px := rng.randi_range(0, size - 1)
		var py := rng.randi_range(0, size - 1)
		img.set_pixel(px, py, base.lightened(rng.randf_range(0.10, 0.26)))
	for i in range(size * 2):
		var px := rng.randi_range(0, size - 1)
		var py := rng.randi_range(0, size - 1)
		img.set_pixel(px, py, base.darkened(rng.randf_range(0.08, 0.20)))
	# Small tar-filled cracks.
	for i in range(6):
		var px := float(rng.randi_range(0, size - 1))
		var py := float(rng.randi_range(0, size - 1))
		var ang := rng.randf_range(0.0, TAU)
		for step in range(rng.randi_range(10, 34)):
			var ix2 := int(posmod(px, float(size)))
			var iy2 := int(posmod(py, float(size)))
			img.set_pixel(ix2, iy2, base.darkened(rng.randf_range(0.14, 0.28)))
			ang += rng.randf_range(-0.45, 0.45)
			px += cos(ang) * 1.7
			py += sin(ang) * 1.7
	return ImageTexture.create_from_image(img)


# Soft headlight cone, radial glow, rain streak and wet sheen textures are
# generated by Fx (see fx.gd); keeping them there leaves this file about the game.


func _gen_puddles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 44127
	puddles.clear()
	for i in range(24):
		puddles.append({
			"x": rng.randf_range(0.05, 0.95),
			"y": rng.randf() * ROAD_CYCLE,
			"rx": rng.randf_range(24.0, 78.0),
			"ry": rng.randf_range(55.0, 165.0),
			"rot": rng.randf_range(-0.16, 0.16),
			"phase": rng.randf_range(0.0, TAU),
		})


func _gen_road_scars() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 71305
	road_scars.clear()
	for i in range(6):
		var kind := 0 if (i % 2 == 0) else 1
		var r := rng.randf_range(16.0, 30.0)
		var rot := rng.randf_range(0.0, TAU)
		var stretch := rng.randf_range(0.8, 1.4)
		var alpha := rng.randf_range(0.18, 0.28)
		var geom: Dictionary = {}

		if kind == 0:
			var main_pts := PackedVector2Array([Vector2.ZERO])
			var pos := Vector2.ZERO
			var ang := rot
			var segments := rng.randi_range(4, 6)
			for s in range(segments):
				ang += rng.randf_range(-0.45, 0.45)
				pos += Vector2(cos(ang), sin(ang)) * (r * rng.randf_range(0.35, 0.50))
				main_pts.append(pos)
			var branches: Array = []
			if rng.randf() < 0.65 and main_pts.size() >= 3:
				var b_start: Vector2 = main_pts[1]
				var b_ang := ang + rng.randf_range(0.6, 1.0)
				var b_pts := PackedVector2Array([b_start])
				var b_pos := b_start
				for bs in range(2):
					b_ang += rng.randf_range(-0.3, 0.3)
					b_pos += Vector2(cos(b_ang), sin(b_ang)) * (r * 0.30)
					b_pts.append(b_pos)
				branches.append(b_pts)
			geom["main"] = main_pts
			geom["branches"] = branches
		else:
			var tar_pts := PackedVector2Array()
			var t_pos := Vector2.ZERO
			var t_ang := rot
			tar_pts.append(t_pos)
			for t_step in range(rng.randi_range(5, 7)):
				t_ang += sin(float(t_step) * 1.6) * 0.5
				t_pos += Vector2(cos(t_ang), sin(t_ang)) * (r * 0.38)
				tar_pts.append(t_pos)
			geom["tar"] = tar_pts

		road_scars.append({
			"kind": kind,
			"x": rng.randf_range(0.12, 0.88),
			"y": rng.randf() * ROAD_CYCLE,
			"r": r,
			"rot": rot,
			"stretch": stretch,
			"alpha": alpha,
			"geom": geom,
		})


func _gen_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99017
	decor.clear()
	for side in [-1, 1]:
		for i in range(22):
			var roll := rng.randf()
			var kind := 0
			if roll < 0.50:
				kind = 0
			elif roll < 0.86:
				kind = 1
			elif roll < 0.94:
				kind = 2
			else:
				kind = 3
			decor.append({
				"side": side,
				"y": rng.randf() * 2600.0,
				"kind": kind,
				"size": rng.randf_range(0.85, 1.35),
				"off": rng.randf_range(0.0, 24.0),
				"tint": rng.randf_range(0.0, 1.0),
			})


func _apply_car() -> void:
	var car := Cars.get_car(car_index)
	base_speed = float(car.speed)
	top_speed = float(car.top)
	handling = float(car.handling)
	player_color = Color(str(car.color))
	player_stripe = bool(car.stripe)
	player_wing = bool(car.wing)
	player_stripe_col = Color(str(car.stripe_color))
	player_silhouette = str(car.get("silhouette", "sedan"))


func start_run() -> void:
	_layout()
	_apply_car()
	scroll = 0.0
	speed = base_speed
	t = 0.0
	distance = 0.0
	score = 0.0
	bonus = 0.0
	near = 0
	combo = 0
	combo_t = 0.0
	nitro = NITRO_SEG
	boosting = false
	boost_t = 0.0
	_nitro_cooldown = 0.0
	braking = false
	brake_heat = 0.0
	overheated = false
	slip = 0.0
	rear_hazards.clear()
	rewinding = false
	rewind_frames.clear()
	_rewind_step_t = 0.0
	_rewind_invuln = 0.0
	_snapshot_t = 0.0
	_cutin_window = 0.0
	_cutin_lane = -1
	_rear_spawn_t = 0.45
	tutorial_mode = false
	lane = 1
	player_x = _lane_x(lane)
	player_tilt = 0.0
	cars.clear()
	items.clear()
	particles.clear()
	skid_marks.clear()
	_has_prev_skid = false
	spawn_t = 1.0
	item_t = 1.2
	pickup_coins = 0
	free_lane = 3
	free_t = 7.0
	crashed = false
	demo = false
	running = true
	paused = false
	time_scale = 1.0
	shake = 0.0
	flash = 0.0
	hud_changed.emit(0, gauge_kmh(speed, base_speed, top_speed), nitro, 0, 0, false)
	status_changed.emit(slip, brake_heat, overheated)


func set_tutorial_mode(on: bool) -> void:
	if not on and rewinding:
		while not rewind_frames.is_empty():
			_apply_snapshot(rewind_frames.pop_back())
		_finish_rewind()
	tutorial_mode = on
	rewind_frames.clear()
	rewinding = false
	_rewind_invuln = 0.0
	_snapshot_t = 0.0
	if on:
		rewind_frames.append(_snapshot_state())


func start_demo() -> void:
	_apply_car()
	cars.clear()
	items.clear()
	particles.clear()
	skid_marks.clear()
	_has_prev_skid = false
	_nitro_cooldown = 0.0
	lane = 1
	player_x = _lane_x(lane)
	crashed = false
	running = false
	demo = true
	paused = false
	boosting = false
	braking = false
	boost_t = 0.0
	shake = 0.0
	flash = 0.0
	brake_heat = 0.0
	overheated = false
	slip = 0.0
	tutorial_mode = false
	rewinding = false
	rewind_frames.clear()
	_rewind_invuln = 0.0
	spawn_t = 0.5


func stop_run() -> void:
	running = false
	demo = false
	boosting = false
	braking = false


func move_lane(dir: int) -> void:
	if not running or paused or crashed:
		return
	var old_lane := lane
	lane = clampi(lane + dir, 0, LANES - 1)
	if lane != old_lane:
		_cutin_window = CUTIN_WINDOW
		_cutin_lane = lane
		lane_changed.emit(lane)


func set_braking(on: bool) -> void:
	if on and overheated:
		if braking:
			braking = false
			brake_state_changed.emit(false)
		Sfx.click()
		return
	if not running or paused or crashed:
		if braking:
			braking = false
			brake_state_changed.emit(false)
		return
	if braking != on:
		braking = on
		if on:
			_rear_spawn_t = minf(_rear_spawn_t, 0.25)
		brake_state_changed.emit(braking)


func tap_nitro() -> bool:
	if not running or paused or crashed:
		return false
	if boost_t > 0.0 or _nitro_cooldown > 0.0:
		return false
	if nitro < NITRO_SEG - 0.002:
		return false
	nitro = maxf(0.0, nitro - NITRO_SEG)
	boost_t = BOOST_TIME
	boosting = true
	_nitro_cooldown = 0.35
	nitro_boosted.emit()
	return true


func _unhandled_input(event: InputEvent) -> void:
	if not running or paused or crashed or control_mode != "swipe":
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			swipe_start = event.position
			swipe_used = false
		else:
			if braking:
				set_braking(false)
			if not swipe_used:
				_try_swipe(event.position)
	elif event is InputEventScreenDrag and not swipe_used:
		_try_swipe(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			swipe_start = event.position
			swipe_used = false
		else:
			if braking:
				set_braking(false)
			if not swipe_used:
				_try_swipe(event.position)
	elif event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT) and not swipe_used:
		_try_swipe(event.position)


func _try_swipe(pos: Vector2) -> void:
	var d := pos - swipe_start
	var abs_x := absf(d.x)
	var abs_y := absf(d.y)
	if abs_x < 44.0 and abs_y < 44.0:
		return
	if abs_x > abs_y * 1.1:
		swipe_used = true
		move_lane(1 if d.x > 0.0 else -1)
	elif abs_y > abs_x * 1.1:
		swipe_used = true
		if d.y > 0.0:
			set_braking(true)
		else:
			if tap_nitro():
				Sfx.boost_burst()


func spawn_tutorial_car(target_lane: int) -> void:
	for c in cars:
		if c.get("lane", -1) == target_lane and c.get("y", 0.0) < player_y and c.get("y", 0.0) > player_y - 700.0:
			return
	var c := {
		"lane": target_lane,
		"x": _lane_x(target_lane),
		"y": player_y - 500.0,
		"w": car_w,
		"h": car_h,
		"kind": 0,
		"color": TRAFFIC_COLORS[randi() % TRAFFIC_COLORS.size()],
		"rel": 0.70,
		"cur_speed": 0.70 * base_speed,
		"braking": false,
		"demo_speed": 0.0,
		"near": false,
	}
	cars.append(c)


# --- simulation -------------------------------------------------------------

func _process(delta: float) -> void:
	var raw := minf(delta, 0.05)
	if rewinding:
		if not paused:
			_tick_rewind(raw)
	elif not paused:
		_tick(raw * time_scale)
	queue_redraw()


func _coins_total() -> int:
	return int(distance / 10.0) + pickup_coins + near * 2


func _update_brake_heat(dt: float) -> void:
	if braking and not crashed:
		var load := clampf(speed / maxf(1.0, top_speed), 0.35, 1.25)
		brake_heat = clampf(brake_heat + dt * (BRAKE_HEAT_RATE + load * BRAKE_HEAT_LOAD), 0.0, 1.0)
		if brake_heat >= 1.0 and not overheated:
			overheated = true
			braking = false
			brake_state_changed.emit(false)
			shake = maxf(shake, 14.0)
			Sfx.brake_overheat()
	else:
		var cool := BRAKE_COOL_RATE + (0.12 if speed < 260.0 else 0.0)
		brake_heat = maxf(0.0, brake_heat - dt * cool)
		if overheated and brake_heat <= BRAKE_RESTART_HEAT:
			overheated = false
			Sfx.record()


func _update_slipstream(dt: float) -> void:
	var best := 0.0
	if not braking and not boosting and not crashed:
		for c in cars:
			var dy := player_y - float(c.y)
			if dy <= car_h * 0.35 or dy > car_h * 7.5:
				continue
			var dx := absf(float(c.x) - player_x)
			if dx > (car_w + float(c.w)) * 0.52:
				continue
			var along := 1.0 - clampf((dy - car_h * 1.0) / (car_h * 6.5), 0.0, 1.0)
			var lateral := 1.0 - clampf(dx / maxf(1.0, lane_w * 0.85), 0.0, 1.0)
			best = maxf(best, along * lateral)
	slip = lerpf(slip, best, minf(1.0, dt * (3.6 if best > slip else 2.4)))
	if slip > 0.32 and not braking:
		bonus += int(15.0 * slip * dt * 8.0)


func _update_cutin(dt: float) -> void:
	if _cutin_window <= 0.0:
		return
	_cutin_window = maxf(0.0, _cutin_window - dt)
	var target_x := _lane_x(lane)
	if absf(player_x - target_x) > lane_w * 0.38:
		return
	for c in cars:
		if int(c.get("lane", -1)) != lane or bool(c.get("cutin", false)):
			continue
		var gap := (float(c.y) - float(c.h) * 0.5) - (player_y + car_h * 0.5)
		if gap < 5.0 or gap > CUTIN_MAX_GAP:
			continue
		var traffic_speed := float(c.get("rel", 0.7)) * lerpf(base_speed, top_speed, clampf(t / 70.0, 0.0, 1.0))
		if speed < traffic_speed + 15.0:
			continue
		c["cutin"] = true
		c["near"] = true
		near += 1
		combo += 1
		combo_t = 3.2
		bonus += 45 * combo
		var seg_gain := NITRO_SEG if gap <= 130.0 else (NITRO_SEG * 0.5)
		if nitro >= 0.999:
			bonus += 250 * combo
			pickup_coins += 5
		else:
			nitro = minf(1.0, nitro + seg_gain)
		cut_in.emit(combo)
		for i in range(14):
			particles.append({
				"p": Vector2(player_x + randf_range(-car_w * 0.35, car_w * 0.35), player_y + car_h * 0.45),
				"v": Vector2(randf_range(-160.0, 160.0), randf_range(90.0, 260.0)),
				"life": randf_range(0.25, 0.55),
				"max": 0.55,
				"col": Color(1.0, 0.85, 0.35),
				"size": randf_range(2.5, 5.5),
			})
		_cutin_window = 0.0
		return


func _update_rear_spawning(dt: float, ref_speed: float) -> void:
	if braking and not overheated and speed > 40.0:
		_rear_spawn_t -= dt
		if _rear_spawn_t <= 0.0:
			if _spawn_rear(ref_speed):
				_rear_spawn_t = randf_range(0.55, 0.90)
			else:
				_rear_spawn_t = 0.20
	else:
		_rear_spawn_t = 0.40


func _spawn_rear(ref_speed: float) -> bool:
	if cars.size() > 16:
		return false
	var chosen := -1
	for attempt in range(20):
		var l := randi() % LANES
		if l == free_lane:
			continue
		var blocked := false
		for c in cars:
			if int(c.lane) == l and float(c.y) > H - 180.0 and float(c.y) < H + 260.0:
				blocked = true
				break
		if not blocked:
			chosen = l
			break
	if chosen < 0:
		return false

	var type := _pick_traffic_type()
	var kind := int(type.kind)
	var w := car_w * float(type.w)
	var h := car_h * float(type.h)
	var target_rel := randf_range(float(type.rel[0]), float(type.rel[1]))
	var col: Color = TRAFFIC_COLORS[randi() % TRAFFIC_COLORS.size()]
	var entry := {
		"lane": chosen,
		"x": _lane_x(chosen),
		"y": H + h * 0.5 + 40.0,
		"w": w,
		"h": h,
		"kind": kind,
		"color": col,
		"rel": target_rel,
		"cur_speed": target_rel * ref_speed,
		"braking": false,
		"demo_speed": randf_range(280.0, 460.0),
		"near": false,
		"cutin": false,
		"from_rear": true,
		"stripe": false,
		"wing": false,
		"rails": false,
		"roof_sign": false,
		"cargo": false,
		"stripe_color": _traffic_stripe(col),
		"silhouette": _traffic_silhouette(kind),
	}
	match kind:
		0:
			entry["stripe"] = randf() < 0.35
			if entry["stripe"] and randf() < 0.18:
				entry["wing"] = true
			entry["roof_sign"] = randf() < 0.06
		1:
			entry["rails"] = true
		2:
			entry["trailer"] = TRAILER_COLORS[randi() % TRAILER_COLORS.size()]
		4:
			entry["accent"] = BUS_ACCENTS[randi() % BUS_ACCENTS.size()]
		5:
			entry["stripe"] = true
			entry["wing"] = randf() < 0.75
		6:
			entry["cargo"] = randf() < 0.6
	cars.append(entry)
	return true


# --- tutorial rewind --------------------------------------------------------

func _snapshot_state() -> Dictionary:
	var car_copy: Array = []
	for c in cars:
		car_copy.append(c.duplicate())
	var item_copy: Array = []
	for it in items:
		item_copy.append(it.duplicate())
	return {
		"scroll": scroll,
		"t": t,
		"distance": distance,
		"score": score,
		"bonus": bonus,
		"near": near,
		"combo": combo,
		"combo_t": combo_t,
		"nitro": nitro,
		"speed": speed,
		"lane": lane,
		"player_x": player_x,
		"player_tilt": player_tilt,
		"braking": braking,
		"boost_t": boost_t,
		"boosting": boosting,
		"spawn_t": spawn_t,
		"item_t": item_t,
		"free_lane": free_lane,
		"free_t": free_t,
		"cars": car_copy,
		"items": item_copy,
		"brake_heat": brake_heat,
		"overheated": overheated,
		"slip": slip,
	}


func _record_rewind_snapshot(dt: float) -> void:
	_snapshot_t += dt
	if _snapshot_t < 0.08:
		return
	_snapshot_t = 0.0
	rewind_frames.append(_snapshot_state())
	while rewind_frames.size() > 42:
		rewind_frames.pop_front()


func _apply_snapshot(s: Dictionary) -> void:
	scroll = float(s.scroll)
	t = float(s.t)
	distance = float(s.distance)
	score = float(s.score)
	bonus = float(s.bonus)
	near = int(s.near)
	combo = int(s.combo)
	combo_t = float(s.combo_t)
	nitro = float(s.nitro)
	speed = float(s.speed)
	lane = int(s.lane)
	player_x = float(s.player_x)
	player_tilt = float(s.player_tilt)
	braking = bool(s.braking)
	boost_t = float(s.boost_t)
	boosting = bool(s.boosting)
	spawn_t = float(s.spawn_t)
	item_t = float(s.item_t)
	free_lane = int(s.free_lane)
	free_t = float(s.free_t)
	cars = s.cars
	items = s.items
	brake_heat = float(s.brake_heat)
	overheated = bool(s.overheated)
	slip = float(s.slip)


func _begin_rewind() -> void:
	if rewinding:
		return
	crashed = true
	running = false
	boosting = false
	braking = false
	boost_t = 0.0
	shake = 26.0
	flash = 0.6
	Sfx.crash()
	for i in range(18):
		particles.append({
			"p": Vector2(player_x + randf_range(-30.0, 30.0), player_y + randf_range(-40.0, 20.0)),
			"v": Vector2(randf_range(-280.0, 280.0), randf_range(-360.0, 100.0)),
			"life": randf_range(0.35, 0.8),
			"max": 0.8,
			"col": [Color(1.0, 0.72, 0.28), Color(0.92, 0.92, 0.9), Color(0.72, 0.22, 0.16)][randi() % 3],
			"size": randf_range(2.0, 5.0),
		})
	rewinding = true
	if rewind_frames.is_empty():
		rewind_frames.append(_snapshot_state())
	_rewind_step_t = 0.0
	rewind_started.emit()


func _tick_rewind(dt: float) -> void:
	if not rewinding:
		return
	shake = maxf(0.0, shake - dt * 38.0)
	flash = maxf(0.0, flash - dt * 2.0)
	_rewind_step_t += dt
	while _rewind_step_t >= 0.030 and not rewind_frames.is_empty():
		_apply_snapshot(rewind_frames.pop_back())
		_rewind_step_t -= 0.030
	if rewind_frames.is_empty():
		_finish_rewind()


func _finish_rewind() -> void:
	rewinding = false
	crashed = false
	running = true
	boosting = false
	braking = false
	boost_t = 0.0
	_nitro_cooldown = 0.0
	brake_heat = minf(brake_heat, 0.18)
	overheated = false
	slip = 0.0
	_rewind_invuln = 1.35
	particles.clear()
	skid_marks.clear()
	_has_prev_skid = false
	spawn_t = maxf(spawn_t, 0.8)
	for c in cars:
		if absf(float(c.x) - player_x) < lane_w * 0.85:
			if float(c.y) > player_y - 380.0 and float(c.y) < player_y + 160.0:
				c.y -= 480.0
	status_changed.emit(slip, brake_heat, overheated)
	hud_changed.emit(int(score), gauge_kmh(speed, base_speed, top_speed), nitro, combo, _coins_total(), boosting)
	rewind_finished.emit()


func _update_weather(dt: float) -> void:
	# One full day/night cycle lasts DAY_LENGTH seconds, independent of runs.
	time_of_day = fposmod(time_of_day + dt / DAY_LENGTH, 1.0)

	weather_timer -= dt
	if weather_timer <= 0.0:
		_next_weather()

	var goal := _weather_targets()
	var rise := 1.0 - exp(-dt * 0.115)
	var fall := 1.0 - exp(-dt * 0.170)
	rain_amount = lerpf(rain_amount, float(goal[0]), rise if float(goal[0]) > rain_amount else fall)
	fog_amount = lerpf(fog_amount, float(goal[1]), rise if float(goal[1]) > fog_amount else fall)
	cloud_amount = lerpf(cloud_amount, float(goal[2]), 1.0 - exp(-dt * 0.130))
	storm_amount = lerpf(storm_amount, float(goal[3]), rise if float(goal[3]) > storm_amount else fall)

	# Road stays wet for a while after the rain stops.
	var wet_goal := clampf(rain_amount * 1.12 + storm_amount * 0.15, 0.0, 1.0)
	var wet_k := 0.16 if wet_goal > wetness else 0.035
	wetness = lerpf(wetness, wet_goal, 1.0 - exp(-dt * wet_k))

	wind = clampf(0.12 + rain_amount * 0.42 + storm_amount * 0.72 + cloud_amount * 0.10, 0.0, 1.2)

	Sfx.set_rain_intensity((rain_amount * 0.85 + storm_amount * 0.35) * (1.0 if running else 0.35))
	if Sfx.has_method("set_weather"):
		Sfx.set_weather(wetness, wind, storm_amount)

	# --- rain -------------------------------------------------------------
	# The wind vector below is the single source of truth for the rain: the
	# simulation moves every drop along it and the renderer derives the streak
	# angle from the very same pair, so what you see is exactly what moved.
	# Gusts are a magnitude and never a sign, so the slant never "breathes"
	# in and out while the drops keep travelling one way.
	rain_gust = 0.80 + 0.14 * sin(t * 0.37) + 0.06 * sin(t * 1.31 + 1.7)
	var sim_speed := speed if running else DEMO_SPEED
	var fall_k := clampf(sim_speed / 900.0, 0.55, 1.45)
	var wind_k := clampf(wind * 0.85, 0.0, 1.1)
	rain_vx = -(150.0 + 320.0 * wind_k + storm_amount * 120.0) * rain_gust
	rain_vy = (380.0 + sim_speed * 0.30) * (1.0 + wind * 0.06)
	rain_scale = 34.0 + fall_k * 26.0
	var wrap_pad := 60.0 + 150.0 * clampf(wind, 0.0, 1.2)
	var fall_dt := dt
	if not running:
		fall_dt = dt * 0.82
	var drift := Vector2(rain_vx, rain_vy)
	for rd in rain_drops:
		var k_layer := 1.0 + float(rd.layer) * 0.16
		var kf: float = float(rd.fall) / 1000.0
		rd.y += drift.y * kf * k_layer * fall_dt
		rd.x += drift.x * kf * k_layer * fall_dt
		if rd.y > H + 150.0:
			rd.y = -150.0 - randf() * 60.0
			rd.x = randf_range(-wrap_pad, W + wrap_pad)
		elif rd.x < -wrap_pad:
			rd.x += W + wrap_pad * 2.0
		elif rd.x > W + wrap_pad:
			rd.x -= W + wrap_pad * 2.0

	# Rain splashes on the tarmac: small crowns that pop and fade fast.
	for i in range(rain_splashes.size() - 1, -1, -1):
		var sp: Dictionary = rain_splashes[i]
		sp.life -= dt
		if sp.life <= 0.0:
			rain_splashes.remove_at(i)
	if rain_amount > 0.04 and randf() < rain_amount * (170.0 + storm_amount * 90.0) * dt:
		for n in range(2):
			rain_splashes.append({
				"x": randf_range(road_x - 22.0, road_x + road_w + 22.0),
				"y": randf_range(-20.0, H),
				"life": randf_range(0.15, 0.28),
				"max": 0.28,
				"size": randf_range(1.8, 5.0),
			})
	while rain_splashes.size() > 120:
		rain_splashes.pop_front()

	# Windscreen drops: big, close, short-lived streaks over the whole frame.
	for i in range(rain_lens.size() - 1, -1, -1):
		var d: Dictionary = rain_lens[i]
		d.life -= dt
		if d.life <= 0.0:
			rain_lens.remove_at(i)
	if rain_amount > 0.05 and rain_lens.size() < 22 and randf() < rain_amount * (60.0 + storm_amount * 40.0) * dt:
		rain_lens.append({
			"x": randf_range(-20.0, W + 20.0),
			"y": randf_range(-40.0, H),
			"len": randf_range(30.0, 90.0),
			"w": randf_range(3.0, 6.5),
			"life": randf_range(0.10, 0.22),
			"max": 0.22,
		})

	if storm_amount > 0.28:
		lightning_next -= dt * (0.5 + storm_amount)
		if lightning_next <= 0.0:
			_strike_lightning()
			lightning_next = randf_range(4.0, 11.0)
	if thunder_delay > 0.0:
		thunder_delay -= dt
		if thunder_delay <= 0.0 and Sfx.has_method("thunder"):
			Sfx.thunder()
	lightning = maxf(0.0, lightning - dt * 3.6)


func _next_weather() -> void:
	var pool: Array = []
	match weather_state:
		WEATHER_CLEAR:
			pool = [WEATHER_CLOUDY, WEATHER_CLOUDY, WEATHER_RAIN, WEATHER_FOG]
		WEATHER_CLOUDY:
			pool = [WEATHER_CLEAR, WEATHER_RAIN, WEATHER_RAIN, WEATHER_FOG]
		WEATHER_RAIN:
			pool = [WEATHER_CLOUDY, WEATHER_STORM, WEATHER_STORM, WEATHER_FOG]
		WEATHER_STORM:
			pool = [WEATHER_RAIN, WEATHER_RAIN, WEATHER_CLOUDY]
		_:
			pool = [WEATHER_CLOUDY, WEATHER_CLEAR, WEATHER_RAIN]
	weather_state = int(pool[randi() % pool.size()])
	match weather_state:
		WEATHER_CLEAR:
			weather_timer = randf_range(80.0, 125.0)
		WEATHER_CLOUDY:
			weather_timer = randf_range(65.0, 105.0)
		WEATHER_RAIN:
			weather_timer = randf_range(55.0, 88.0)
		WEATHER_STORM:
			weather_timer = randf_range(38.0, 66.0)
		_:
			weather_timer = randf_range(50.0, 82.0)


func _weather_targets() -> Array:
	match weather_state:
		WEATHER_CLOUDY:
			return [0.06, 0.08, 0.58, 0.0]
		WEATHER_RAIN:
			return [0.58, 0.26, 0.84, 0.0]
		WEATHER_STORM:
			return [1.0, 0.38, 0.96, 1.0]
		WEATHER_FOG:
			return [0.0, 0.82, 0.32, 0.0]
		_:
			return [0.0, 0.0, 0.05, 0.0]


func _strike_lightning() -> void:
	var x := randf_range(W * 0.12, W * 0.88)
	var y := -40.0
	var pts := PackedVector2Array([Vector2(x, y)])
	var bottom := randf_range(360.0, 900.0)
	while y < bottom:
		x = clampf(x + randf_range(-46.0, 46.0), 10.0, W - 10.0)
		y += randf_range(54.0, 118.0)
		pts.append(Vector2(x, y))
	lightning_bolt = pts
	lightning_branches.clear()
	for i in range(randi_range(2, 4)):
		if pts.size() < 3:
			break
		var root: Vector2 = pts[randi_range(1, pts.size() - 1)]
		var b := PackedVector2Array([root])
		var bx := root.x
		var by := root.y
		var steps := randi_range(2, 4)
		for j in range(steps):
			bx += randf_range(-70.0, 70.0)
			by += randf_range(30.0, 72.0)
			b.append(Vector2(clampf(bx, 0.0, W), by))
		lightning_branches.append(b)
	lightning = 1.0
	thunder_delay = randf_range(0.55, 1.7)


func _tick(dt: float) -> void:
	if paused:
		return

	_update_weather(dt)
	t += dt

	if demo:
		scroll += DEMO_SPEED * dt
		spawn_t -= dt
		if spawn_t <= 0.0:
			_spawn(true)
			spawn_t = randf_range(0.7, 1.4)
		_move_traffic(dt, 0.0, 0.0, true)
		_update_fx(dt)
		return

	if not running:
		_update_fx(dt)
		return

	if _nitro_cooldown > 0.0:
		_nitro_cooldown = maxf(0.0, _nitro_cooldown - dt)

	if boost_t > 0.0:
		boost_t -= dt
		if boost_t <= 0.0:
			boost_t = 0.0
			boosting = false
			_nitro_cooldown = 0.35

	if _rewind_invuln > 0.0:
		_rewind_invuln = maxf(0.0, _rewind_invuln - dt)

	_update_brake_heat(dt)
	_update_slipstream(dt)

	var ramp := clampf(t / 70.0, 0.0, 1.0)
	var ref := lerpf(base_speed, top_speed, ramp)
	var want := ref
	if boosting:
		want *= 1.5
	if braking and not overheated:
		# Heat makes the pads fade before they lock out completely.
		want *= lerpf(BRAKE_MULT, BRAKE_MULT * 1.85, brake_heat)
	elif not braking:
		want *= 1.0 + SLIP_BONUS * slip
	var k := 2.4
	if braking and not overheated:
		k = 5.5
	elif boosting:
		k = 5.0
	speed = lerpf(speed, want, minf(1.0, dt * k))

	var travel := speed * dt
	scroll += travel
	distance += travel / 12.0

	# Update existing skid marks with road travel
	for i in range(skid_marks.size() - 1, -1, -1):
		var sk: Dictionary = skid_marks[i]
		sk.p1.y += travel
		sk.p2.y += travel
		sk.life -= dt
		if sk.life <= 0.0 or (sk.p1.y > H + 80.0 and sk.p2.y > H + 80.0):
			skid_marks.remove_at(i)

	var is_skidding := braking and not overheated and running and not crashed and speed > 130.0
	if is_skidding:
		var wheel_y := player_y + car_h * 0.34
		var curr_l := Vector2(player_x - car_w * 0.31, wheel_y)
		var curr_r := Vector2(player_x + car_w * 0.31, wheel_y)
		if _has_prev_skid:
			var max_life := 3.2
			skid_marks.append({
				"p1": _prev_skid_l + Vector2(0.0, travel),
				"p2": curr_l,
				"life": max_life,
				"max": max_life,
			})
			skid_marks.append({
				"p1": _prev_skid_r + Vector2(0.0, travel),
				"p2": curr_r,
				"life": max_life,
				"max": max_life,
			})
			if skid_marks.size() > 160:
				skid_marks.remove_at(0)
				skid_marks.remove_at(0)
		_prev_skid_l = curr_l
		_prev_skid_r = curr_r
		_has_prev_skid = true
	else:
		_has_prev_skid = false

	var target_x := _lane_x(lane)
	var handle_k := handling if time_scale >= 0.9 else handling * (1.0 / maxf(0.12, time_scale))
	player_x = lerpf(player_x, target_x, minf(1.0, dt * handle_k))
	player_tilt = lerpf(player_tilt, clampf((target_x - player_x) * 0.0022, -0.10, 0.10), minf(1.0, dt * 9.0 * (2.5 if time_scale < 0.5 else 1.0)))

	if combo_t > 0.0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 0
			combo_t = 0.0

	free_t -= dt
	if free_t <= 0.0:
		_rotate_free_lane()

	spawn_t -= dt
	if spawn_t <= 0.0:
		_spawn(false)
		spawn_t = maxf(0.52, 0.95 - t * 0.008)

	item_t -= dt
	if item_t <= 0.0:
		_spawn_item()
		item_t = randf_range(1.7, 3.1)

	_update_rear_spawning(dt, ref)
	_move_traffic(dt, speed, ref, false)
	if rewinding:
		return
	_update_cutin(dt)
	_move_items(dt)
	_update_fx(dt)

	if tutorial_mode and running and not crashed:
		_record_rewind_snapshot(dt)

	score = floor(distance) + float(bonus)
	hud_changed.emit(int(score), gauge_kmh(speed, base_speed, top_speed), nitro, combo, _coins_total(), boosting)
	status_changed.emit(slip, brake_heat, overheated)


func _rotate_free_lane() -> void:
	var nl := free_lane
	for attempt in range(10):
		var cand := randi() % LANES
		if cand != free_lane:
			nl = cand
			break
	free_lane = nl
	free_t = randf_range(6.0, 9.0)


func _move_traffic(dt: float, player_speed: float, ref_speed: float, is_demo: bool) -> void:
	if is_demo:
		for i in range(cars.size() - 1, -1, -1):
			var c: Dictionary = cars[i]
			c.y += float(c.demo_speed) * dt
			if c.y > H + 340.0:
				cars.remove_at(i)
		return

	var py := player_y
	for i in range(cars.size() - 1, -1, -1):
		var c: Dictionary = cars[i]
		var desired_speed: float = float(c.get("rel", 0.72)) * ref_speed
		var target_speed := desired_speed
		var wants_brake := false

		# 1. Check for lead traffic car directly ahead in same lane
		var lead_gap := 9999.0
		var lead_spd := desired_speed
		for c2 in cars:
			if c2 == c:
				continue
			if absf(float(c2.x) - float(c.x)) < lane_w * 0.65:
				if float(c2.y) < float(c.y):
					var g: float = (float(c.y) - float(c.h) * 0.5) - (float(c2.y) + float(c2.h) * 0.5)
					if g > -10.0 and g < lead_gap:
						lead_gap = g
						lead_spd = float(c2.get("cur_speed", float(c2.rel) * ref_speed))

		if lead_gap < 360.0:
			if float(c.get("cur_speed", desired_speed)) > lead_spd - 25.0 or lead_gap < 220.0:
				wants_brake = true
				if lead_gap > 90.0:
					var k_gap := (lead_gap - 90.0) / 270.0
					target_speed = minf(target_speed, lerpf(lead_spd * 0.88, lead_spd, k_gap))
				else:
					target_speed = minf(target_speed, minf(lead_spd * 0.82, lead_spd - 40.0))
			# Enforce traffic physical clearance so cars never pass through each other
			var min_lead_gap := 18.0
			if lead_gap < min_lead_gap:
				c.y = float(c.y) + (min_lead_gap - lead_gap)
				c["cur_speed"] = minf(float(c.get("cur_speed", desired_speed)), lead_spd)

		# 2. Check for player ahead in the same lane (traffic braking behind player)
		if float(c.y) > py and absf(float(c.x) - player_x) < lane_w * 0.72:
			var p_gap: float = (float(c.y) - float(c.h) * 0.5) - (py + car_h * 0.5)
			if p_gap > 0.0 and p_gap < 440.0:
				if player_speed < float(c.get("cur_speed", desired_speed)) + 25.0 or braking or p_gap < 240.0:
					wants_brake = true
					if p_gap > 110.0:
						var k_pgap := (p_gap - 110.0) / 330.0
						target_speed = minf(target_speed, lerpf(player_speed * 0.88, player_speed, k_pgap))
					else:
						target_speed = minf(target_speed, minf(player_speed * 0.82, player_speed - 40.0))
				var p_min_gap := 24.0
				if p_gap < p_min_gap:
					c.y = py + (car_h + float(c.h)) * 0.5 + p_min_gap
					c["cur_speed"] = minf(float(c.get("cur_speed", desired_speed)), player_speed)

		# Update speed and braking state
		c["braking"] = wants_brake
		var current_spd: float = float(c.get("cur_speed", desired_speed))
		if wants_brake:
			current_spd = lerpf(current_spd, target_speed, minf(1.0, dt * 6.5))
		else:
			current_spd = lerpf(current_spd, desired_speed, minf(1.0, dt * 2.5))
		c["cur_speed"] = current_spd

		# Move car relative to player
		var prev_y: float = float(c.y)
		c.y = float(c.y) + (player_speed - current_spd) * dt

		if float(c.y) > H + 340.0 or float(c.y) < -900.0:
			cars.remove_at(i)
			continue

		var pw := car_w * 0.78
		var ph := car_h * 0.80
		var cw: float = float(c.w) * 0.78
		var ch: float = float(c.h) * 0.80
		if _rewind_invuln <= 0.0 and absf(float(c.x) - player_x) < (pw + cw) * 0.5 and absf(float(c.y) - py) < (ph + ch) * 0.5:
			var dy := float(c.y) - py
			if dy > car_h * 0.18:
				# Bumper bump: arcade knock from trailing car without instant death
				Sfx.bump()
				shake = maxf(shake, 7.5)
				speed = maxf(speed, player_speed + 75.0)
				c.y = py + (ph + ch) * 0.5 + 4.0
				c["braking"] = true
				c["cur_speed"] = minf(float(c.get("cur_speed", desired_speed)), speed * 0.60)
				for k in range(5):
					particles.append({
						"p": Vector2(player_x + randf_range(-car_w * 0.25, car_w * 0.25), py + car_h * 0.46),
						"v": Vector2(randf_range(-60.0, 60.0), randf_range(40.0, 120.0)),
						"life": randf_range(0.20, 0.40),
						"max": 0.40,
						"col": Color(0.85, 0.85, 0.85, 0.6),
						"size": randf_range(2.0, 4.0),
					})
			else:
				_crash()
				return

		if not c.get("near", false) and prev_y < py and float(c.y) >= py:
			# Traffic passing us: pan the swish to the side it went by, and make
			# it louder the closer it clipped us. This is the main cue that tells
			# the player where the gaps actually are.
			var side := clampf((float(c.x) - player_x) / maxf(1.0, lane_w), -1.0, 1.0)
			var closeness := clampf(1.0 - absf(float(c.x) - player_x) / (lane_w * 2.2), 0.0, 1.0)
			if Sfx.has_method("pass_by"):
				Sfx.pass_by(side, closeness)
			elif Sfx.has_method("whoosh"):
				Sfx.whoosh(side)
			if absf(float(c.x) - player_x) < lane_w * 1.22:
				c["near"] = true
				near += 1
				combo += 1
				combo_t = 2.6
				bonus += 10 * combo
				near_miss.emit(combo)


func _move_items(dt: float) -> void:
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		it.y += speed * dt
		it.phase += dt
		if it.y > H + 110.0:
			items.remove_at(i)
			continue
		if absf(float(it.x) - player_x) < car_w * 0.60 and absf(float(it.y) - player_y) < car_h * 0.62:
			if int(it.kind) == 0:
				pickup_coins += 12
				pickup_taken.emit(0)
			else:
				nitro = minf(1.0, nitro + 0.20)
				pickup_taken.emit(1)
			items.remove_at(i)


func _spawn_item() -> void:
	if items.size() > 3:
		return
	var chosen := -1
	for attempt in range(14):
		var l := randi() % LANES
		var blocked := false
		for c in cars:
			if int(c.lane) == l and float(c.y) < 420.0:
				blocked = true
				break
		if blocked:
			continue
		for it in items:
			if int(it.lane) == l:
				blocked = true
				break
		if not blocked:
			chosen = l
			break
	if chosen < 0:
		return
	items.append({
		"lane": chosen,
		"x": _lane_x(chosen),
		"y": -50.0,
		"kind": 1 if randf() < 0.18 else 0,
		"phase": randf() * 4.0,
	})


func _pick_traffic_type() -> Dictionary:
	var roll := randf()
	var acc := 0.0
	for tp in TRAFFIC_TYPES:
		acc += float(tp.weight)
		if roll <= acc:
			return tp
	return TRAFFIC_TYPES[TRAFFIC_TYPES.size() - 1]


func _traffic_stripe(body: Color) -> Color:
	if body.v > 0.55:
		return Color(0.12, 0.13, 0.15)
	return Color(0.94, 0.93, 0.90)


# Traffic borrows the garage classes for the car-like kinds, so the road shows
# hatchbacks, off-roaders and coupes instead of one repainted sedan. The
# dedicated van/truck/bus/pickup drawings keep their own bodies.
func _traffic_silhouette(kind: int) -> String:
	match kind:
		0:
			return "hatch" if randf() < 0.45 else "sedan"
		1:
			return "offroad"
		5:
			return "sport"
	return ""


func _spawn(is_demo: bool) -> void:
	if cars.size() > 9:
		return
	var top_count := 0
	for c in cars:
		if c.y < 620.0:
			top_count += 1
	if top_count >= 3:
		return

	var chosen := -1
	for attempt in range(20):
		var l := randi() % LANES
		if not is_demo and l == free_lane:
			continue
		var blocked := false
		for c in cars:
			if int(c.lane) == l and float(c.y) < 660.0:
				blocked = true
				break
		if not blocked:
			chosen = l
			break
	if chosen < 0:
		return

	var type := _pick_traffic_type()
	var kind := int(type.kind)
	var w := car_w * float(type.w)
	var h := car_h * float(type.h)
	var rel := randf_range(float(type.rel[0]), float(type.rel[1]))
	var col: Color = TRAFFIC_COLORS[randi() % TRAFFIC_COLORS.size()]
	var entry := {
		"lane": chosen,
		"x": _lane_x(chosen),
		"y": -h * 0.75,
		"w": w,
		"h": h,
		"kind": kind,
		"color": col,
		"rel": rel,
		"cur_speed": rel * (lerpf(base_speed, top_speed, clampf(t / 70.0, 0.0, 1.0)) if running else DEMO_SPEED),
		"braking": false,
		"demo_speed": randf_range(250.0, 420.0),
		"near": false,
		"cutin": false,
		"stripe": false,
		"wing": false,
		"rails": false,
		"roof_sign": false,
		"cargo": false,
		"stripe_color": _traffic_stripe(col),
		"silhouette": _traffic_silhouette(kind),
	}
	match kind:
		0:
			entry["stripe"] = randf() < 0.35
			if entry["stripe"] and randf() < 0.18:
				entry["wing"] = true
			entry["roof_sign"] = randf() < 0.06
		1:
			entry["rails"] = true
		2:
			entry["trailer"] = TRAILER_COLORS[randi() % TRAILER_COLORS.size()]
		4:
			entry["accent"] = BUS_ACCENTS[randi() % BUS_ACCENTS.size()]
		5:
			entry["stripe"] = true
			entry["wing"] = randf() < 0.75
		6:
			entry["cargo"] = randf() < 0.6
	cars.append(entry)


func _crash() -> void:
	if crashed:
		return
	if tutorial_mode:
		_begin_rewind()
		return
	crashed = true
	running = false
	boosting = false
	braking = false
	boost_t = 0.0
	shake = 24.0
	flash = 0.7
	for i in range(30):
		particles.append({
			"p": Vector2(player_x + randf_range(-26.0, 26.0), player_y + randf_range(-40.0, 20.0)),
			"v": Vector2(randf_range(-330.0, 330.0), randf_range(-430.0, 120.0)),
			"life": randf_range(0.45, 1.1),
			"max": 1.1,
			"col": [Color(1.0, 0.72, 0.28), Color(0.92, 0.92, 0.9), Color(0.72, 0.22, 0.16)][randi() % 3],
			"size": randf_range(2.0, 6.0),
		})
	run_ended.emit(int(score), int(distance), near, _coins_total())


func _update_fx(dt: float) -> void:
	shake = maxf(0.0, shake - dt * 42.0)
	flash = maxf(0.0, flash - dt * 2.2)
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.life -= dt
		if p.life <= 0.0:
			particles.remove_at(i)
			continue
		p.p += p.v * dt
		p.v.y += 640.0 * dt
		p.v *= 0.985

	if braking and not overheated and running and not crashed and speed > 180.0 and randf() < 0.40:
		for side in [-1, 1]:
			particles.append({
				"p": Vector2(player_x + float(side) * car_w * 0.31, player_y + car_h * 0.36),
				"v": Vector2(randf_range(-16.0, 16.0), randf_range(30.0, 90.0)),
				"life": randf_range(0.24, 0.48),
				"max": 0.48,
				"col": Color(0.88, 0.90, 0.92, 0.42),
				"size": randf_range(3.5, 7.5),
			})
	if overheated and running and randf() < 0.55:
		for side in [-1, 1]:
			particles.append({
				"p": Vector2(player_x + float(side) * car_w * 0.30, player_y + car_h * 0.33),
				"v": Vector2(randf_range(-34.0, 34.0), randf_range(20.0, 95.0)),
				"life": randf_range(0.45, 0.95),
				"max": 0.95,
				"col": Color(0.86, 0.87, 0.87, 0.20),
				"size": randf_range(5.0, 11.0),
			})
	if slip > 0.35 and randf() < 0.35:
		particles.append({
			"p": Vector2(player_x + randf_range(-car_w * 0.45, car_w * 0.45), player_y - car_h * 0.55),
			"v": Vector2(randf_range(-20.0, 20.0), randf_range(-180.0, -80.0)),
			"life": randf_range(0.18, 0.36),
			"max": 0.36,
			"col": Color(0.78, 0.90, 1.0, 0.22),
			"size": randf_range(1.5, 3.5),
		})
	if rain_amount > 0.05 and running and not crashed and speed > 110.0 and randf() < (0.25 + rain_amount * 0.45):
		for side in [-1, 1]:
			var spray_spd := speed * 0.45
			particles.append({
				"p": Vector2(player_x + float(side) * car_w * 0.38 + randf_range(-4.0, 4.0), player_y + car_h * 0.44),
				"v": Vector2(float(side) * randf_range(15.0, 45.0), randf_range(spray_spd * 0.7, spray_spd * 1.3)),
				"life": randf_range(0.20, 0.42),
				"max": 0.42,
				"col": Color(0.82, 0.88, 0.94, 0.25 * rain_amount),
				"size": randf_range(2.5, 6.0),
			})


func finish_run() -> void:
	if running:
		tutorial_mode = false
		_crash()


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	var sx := 0.0
	var sy := 0.0
	if shake > 0.2:
		sx = randf_range(-shake, shake)
		sy = randf_range(-shake, shake)
	_sx = sx
	_sy = sy
	px_per_unit = get_global_transform_with_canvas().get_scale().y
	draw_set_transform(Vector2(sx, sy))

	_draw_grass()
	_draw_road()
	_draw_shoulders()
	_draw_markings()
	_draw_skid_marks()
	_draw_rails()
	_draw_road_beams()
	_draw_puddles()
	_draw_cloud_shadows()
	_draw_scenery()
	_draw_cars()
	_draw_night_atmosphere()
	_draw_streetlight_glows()
	_draw_air_beams()
	_draw_items()
	_draw_speed_streaks()
	_draw_car_light_glows()
	_draw_wet_reflections()
	_draw_rain_splashes()
	_draw_road_mist()
	_draw_particles()
	_draw_rain()
	_draw_fog()
	_draw_lightning()
	_draw_rear_hazards()
	_draw_rain_lens()

	draw_set_transform(Vector2.ZERO)
	_draw_haze()
	if pending:
		_draw_probe_streak()
	if pending_rect:
		draw_rect(Rect2(150.0, 150.0, 40.0, 40.0), Color(1.0, 1.0, 1.0, 1.0))
	if flash > 0.01:
		draw_rect(Rect2(0.0, 0.0, W, H), Color(1.0, 1.0, 1.0, flash * 0.5))
	if rewinding:
		_draw_rewind_fx()


func _sample_sky(t: float) -> Array:
	var tt := fposmod(t, 1.0)
	for i in range(SKY_KEYS.size() - 1):
		var a: Array = SKY_KEYS[i]
		var b: Array = SKY_KEYS[i + 1]
		if tt >= float(a[0]) and tt <= float(b[0]):
			var span := maxf(0.0001, float(b[0]) - float(a[0]))
			var k := (tt - float(a[0])) / span
			k = k * k * (3.0 - 2.0 * k)
			return [
				Color(
					lerpf(float(a[1]), float(b[1]), k),
					lerpf(float(a[2]), float(b[2]), k),
					lerpf(float(a[3]), float(b[3]), k)
				),
				lerpf(float(a[4]), float(b[4]), k),
			]
	return [Color.WHITE, 0.0]


func get_sky_ambient() -> Color:
	var sky := _sample_sky(time_of_day)
	var amb: Color = sky[0]
	# Overcast, rain and storm all flatten and cool the light.
	var dim := 1.0 - cloud_amount * 0.19 - rain_amount * 0.08 - storm_amount * 0.15 - fog_amount * 0.09
	dim = clampf(dim, 0.34, 1.12)
	var cool := rain_amount * 0.10 + storm_amount * 0.16
	return Color(
		clampf(amb.r * (dim - cool * 0.30), 0.0, 1.3),
		clampf(amb.g * (dim - cool * 0.08), 0.0, 1.3),
		clampf(amb.b * (dim + cool * 0.22), 0.0, 1.3)
	)


func get_night_factor() -> float:
	return float(_sample_sky(time_of_day)[1])


func get_light_factor() -> float:
	# Headlights come on at dusk, in rain, fog and storms.
	return clampf(maxf(get_night_factor(), maxf(fog_amount * 0.68, maxf(rain_amount * 0.42, storm_amount * 0.52))), 0.0, 1.0)


func get_weather_name() -> String:
	match weather_state:
		WEATHER_CLOUDY:
			return "ОБЛАЧНО"
		WEATHER_RAIN:
			return "ДОЖДЬ"
		WEATHER_STORM:
			return "ГРОЗА"
		WEATHER_FOG:
			return "ТУМАН"
		_:
			return "ЯСНО"


func get_clock_text() -> String:
	var total := fposmod(time_of_day * 24.0 + 6.0, 24.0)
	var hh := int(total)
	var mm := int((total - float(hh)) * 60.0)
	return "%02d:%02d" % [hh, mm]


func weather_status_text() -> String:
	return "%s · %s" % [get_weather_name(), get_clock_text()]


func _draw_skid_marks() -> void:
	if skid_marks.is_empty():
		return
	var base_col := Color(0.04, 0.05, 0.06)
	var w := car_w * 0.16
	for sk in skid_marks:
		var a: float = clampf(float(sk.life) / float(sk.max), 0.0, 1.0) * 0.44
		draw_line(sk.p1, sk.p2, Color(base_col.r, base_col.g, base_col.b, a), w)


func _draw_grass() -> void:
	var amb := get_sky_ambient()
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.40, 0.50, 0.30) * amb)
	if grass_tex:
		var off := fposmod(scroll, 128.0)
		draw_texture_rect(grass_tex, Rect2(0.0, off - 128.0, W, H + 128.0), true, Color(amb.r, amb.g, amb.b, 0.62))
	var period := 380.0
	var off2 := fposmod(scroll, period)
	var count := int(H / period) + 3
	for i in range(count):
		var y := off2 + i * period - period
		draw_circle(Vector2(W * 0.06, y + 40.0), 34.0, Color(0.26, 0.35, 0.19, 0.18) * amb)
		draw_circle(Vector2(W * 0.94, y + 170.0), 42.0, Color(0.26, 0.35, 0.19, 0.16) * amb)


func _draw_road() -> void:
	var amb := get_sky_ambient()
	if rain_amount > 0.01:
		amb = amb.lerp(amb * Color(0.78, 0.78, 0.82), rain_amount * 0.42)

	draw_rect(Rect2(road_x, 0.0, road_w, H), Color(0.355, 0.365, 0.385) * amb)
	if asphalt_tex:
		# Downward road texture scrolling
		var tile := 256.0
		var off := fposmod(scroll, tile)
		draw_texture_rect(asphalt_tex, Rect2(road_x, off - tile, road_w, H + tile * 2.0), true, amb)

	# Broad tyre-polished tracks in every lane.
	for l in range(LANES):
		var cx := _lane_x(l)
		var sw := lane_w * 0.19
		draw_rect(Rect2(cx - lane_w * 0.35 - sw * 0.5, 0.0, sw, H), Color(0.06, 0.06, 0.07, 0.060))
		draw_rect(Rect2(cx + lane_w * 0.35 - sw * 0.5, 0.0, sw, H), Color(0.06, 0.06, 0.07, 0.060))
		draw_rect(Rect2(cx - lane_w * 0.35 - sw * 1.15, 0.0, sw * 2.3, H), Color(0.07, 0.07, 0.08, 0.026))
		draw_rect(Rect2(cx + lane_w * 0.35 - sw * 1.15, 0.0, sw * 2.3, H), Color(0.07, 0.07, 0.08, 0.026))
		draw_rect(Rect2(cx - lane_w * 0.09, 0.0, lane_w * 0.18, H), Color(1, 1, 1, 0.012) * amb)

	var ew := 34.0
	_grad_h(Rect2(road_x, 0.0, ew, H), Color(0, 0, 0, 0.22), Color(0, 0, 0, 0.0))
	_grad_h(Rect2(road_x + road_w - ew, 0.0, ew, H), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.22))

	for l in range(1, LANES):
		var x := road_x + lane_w * l
		draw_rect(Rect2(x - lane_w * 0.02, 0.0, lane_w * 0.04, H), Color(0.07, 0.07, 0.08, 0.055))

	# Transverse tar seams repair the tiled texture and add motion cues.
	var seam_period := 760.0
	var seam_y := fposmod(scroll, seam_period) - seam_period
	while seam_y < H + seam_period:
		draw_rect(Rect2(road_x + 5.0, seam_y, road_w - 10.0, 2.0), Color(0.05, 0.05, 0.06, 0.11))
		draw_rect(Rect2(road_x + 5.0, seam_y + 2.0, road_w - 10.0, 1.0), Color(0.55, 0.56, 0.55, 0.035) * amb)
		seam_y += seam_period

	# Seamless multi-period wrap: defects appear uniformly across entire screen
	for scar in road_scars:
		var base_y := fposmod(float(scar.y) + scroll, ROAD_CYCLE)
		for k in [-1, 0, 1]:
			var sy: float = base_y + float(k) * ROAD_CYCLE
			if sy < -160.0 or sy > H + 160.0:
				continue
			var sx: float = road_x + road_w * float(scar.x)
			_draw_road_scar(scar, Vector2(sx, sy), amb)

	# Wet asphalt: darker base, cool sky sheen and long specular bands.
	if wetness > 0.03:
		draw_rect(Rect2(road_x, 0.0, road_w, H), Color(0.08, 0.10, 0.14, wetness * 0.15))
		draw_rect(Rect2(road_x, 0.0, road_w, H), Color(0.62, 0.74, 0.90, wetness * 0.07))
		for l in range(LANES):
			var cx := _lane_x(l)
			draw_rect(Rect2(cx - lane_w * 0.44, 0.0, lane_w * 0.10, H), Color(0.74, 0.84, 0.97, wetness * 0.028))
			draw_rect(Rect2(cx + lane_w * 0.34, 0.0, lane_w * 0.08, H), Color(0.74, 0.84, 0.97, wetness * 0.020))


func _ellipse_points(center: Vector2, rx: float, ry: float, rot: float, segments := 18) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(segments):
		var a := TAU * float(i) / float(segments)
		var p := Vector2(cos(a) * rx, sin(a) * ry)
		pts.append(center + p.rotated(rot))
	return pts


func _draw_road_scar(scar: Dictionary, p: Vector2, amb := Color.WHITE) -> void:
	var kind := int(scar.kind)
	var a := float(scar.alpha)
	var geom: Dictionary = scar.get("geom", {})

	if kind == 0:
		var main_pts: PackedVector2Array = geom.get("main", PackedVector2Array())
		if main_pts.size() >= 2:
			var shifted_main := PackedVector2Array()
			var lip_main := PackedVector2Array()
			for pt in main_pts:
				shifted_main.append(p + pt)
				lip_main.append(p + pt + Vector2(1.0, 1.0))
			draw_polyline(lip_main, Color(0.65, 0.66, 0.67, a * 0.22) * amb, 1.0, true)
			draw_polyline(shifted_main, Color(0.08, 0.08, 0.09, a * 0.75), 1.2, true)
		for branch in geom.get("branches", []):
			if branch.size() >= 2:
				var shifted_b := PackedVector2Array()
				for pt in branch:
					shifted_b.append(p + pt)
				draw_polyline(shifted_b, Color(0.08, 0.08, 0.09, a * 0.60), 1.0, true)
	else:
		var tar_pts: PackedVector2Array = geom.get("tar", PackedVector2Array())
		if tar_pts.size() >= 2:
			var shifted_tar := PackedVector2Array()
			for pt in tar_pts:
				shifted_tar.append(p + pt)
			draw_polyline(shifted_tar, Color(0.06, 0.06, 0.07, a * 0.70), 1.8, true)


func _draw_puddles() -> void:
	# Surface water first: the wet sheen belongs to the asphalt itself.
	_draw_wet_sheen()
	if wetness <= 0.04:
		return
	var amb := get_sky_ambient()
	var night := get_night_factor()
	var light := get_light_factor()
	var water := Color(
		clampf(0.30 * amb.r + 0.16, 0.0, 1.0),
		clampf(0.38 * amb.g + 0.19, 0.0, 1.0),
		clampf(0.50 * amb.b + 0.25, 0.0, 1.0)
	)
	for p in puddles:
		var base_y := fposmod(float(p.y) + scroll, ROAD_CYCLE)
		for k in [-1, 0, 1]:
			var y: float = base_y + float(k) * ROAD_CYCLE
			if y < -260.0 or y > H + 260.0:
				continue
			var x := road_x + road_w * float(p.x)
			var rx := float(p.rx)
			var ry := float(p.ry)
			var wob := 1.0 + 0.05 * sin(t * 0.9 + float(p.phase))
			draw_set_transform(Vector2(x + _sx, y + _sy), float(p.rot), Vector2.ONE)
			# Dark water body, then the sky reflection and a thin bright rim.
			draw_texture_rect(glow_tex, Rect2(-rx, -ry * wob, rx * 2.0, ry * 2.0 * wob), false, Color(water.r, water.g, water.b, 0.36 * wetness))
			draw_texture_rect(glow_tex, Rect2(-rx * 0.70, -ry * 0.76 * wob, rx * 1.40, ry * 1.52 * wob), false, Color(0.66, 0.78, 0.94, 0.10 * wetness))
			draw_set_transform(Vector2(x + _sx, y + _sy), float(p.rot), Vector2(1.0, ry / maxf(1.0, rx)))
			if wetness > 0.20:
				draw_arc(Vector2.ZERO, rx * 0.92, 0.0, TAU, 26, Color(0.74, 0.84, 0.97, 0.070 * wetness), 1.2, true)
			# Rain rings on the water surface.
			if rain_amount > 0.08 and wetness > 0.14:
				draw_set_transform(Vector2(x + _sx, y + _sy), 0.0, Vector2.ONE)
				for r in range(2):
					var kk := fposmod(t * (0.90 + float(r) * 0.22) + float(p.phase) * 0.31 + float(r) * 0.47, 1.0)
					var rr := (0.08 + kk * 0.62) * rx
					var ra := (1.0 - kk) * (1.0 - kk) * 0.13 * rain_amount * wetness
					var ang_off := float(p.phase) + float(r) * 2.4
					var off := Vector2(cos(ang_off) * rx * 0.30, sin(ang_off) * ry * 0.24)
					draw_arc(off, rr, 0.0, TAU, 18, Color(0.80, 0.90, 1.0, ra), 1.0, true)
			draw_set_transform(Vector2(_sx, _sy))
	# Where a puddle sits in a beam the water throws the light back up: a soft
	# vertical glare on the water that reads as a real reflection.
	if light > 0.05 and wetness > 0.12:
		var glare := light * wetness * (1.0 - night * 0.45)
		for p in puddles:
			var base_y := fposmod(float(p.y) + scroll, ROAD_CYCLE)
			for k in [-1, 0, 1]:
				var y: float = base_y + float(k) * ROAD_CYCLE
				if y < -200.0 or y > H + 200.0:
					continue
				var flare := 0.55 + 0.45 * sin(t * 2.3 + float(p.phase))
				Fx.pool(self, glow_tex, Vector2(road_x + road_w * float(p.x), y + float(p.ry) * 0.35), float(p.rx) * 0.8,
					Color(1.0, 0.93, 0.78, 0.055 * glare * flare), Vector2(0.9, 2.2))


func _draw_cloud_shadows() -> void:
	if cloud_amount <= 0.05:
		return
	var a := cloud_amount * (0.085 + 0.030 * sin(t * 0.11))
	for i in range(5):
		var x := fposmod(float(i) * 263.0 + t * 7.0 + scroll * 0.018, W + 760.0) - 380.0
		var y := fposmod(float(i) * 447.0 + t * 11.0 + scroll * 0.030, H + 900.0) - 450.0
		var rx := 300.0 + float(i) * 46.0
		var ry := 175.0 + float(i) * 26.0
		draw_texture_rect(glow_tex, Rect2(x - rx, y - ry, rx * 2.0, ry * 2.0), false, Color(0.02, 0.03, 0.05, a))


func _glow(center: Vector2, radius: float, col: Color, stretch := Vector2.ONE) -> void:
	if glow_tex == null or col.a <= 0.001:
		return
	var r := Vector2(radius * stretch.x, radius * stretch.y)
	draw_texture_rect(glow_tex, Rect2(center - r, r * 2.0), false, col)


func _draw_shoulders() -> void:
	var sh := 27.0
	var col := Color(0.62, 0.62, 0.58)
	draw_rect(Rect2(road_x - sh, 0.0, sh, H), col)
	draw_rect(Rect2(road_x + road_w, 0.0, sh, H), col)
	draw_rect(Rect2(road_x - sh, 0.0, sh, H), Color(0.35, 0.36, 0.33, 0.10))
	draw_rect(Rect2(road_x + road_w, 0.0, sh, H), Color(0.35, 0.36, 0.33, 0.10))
	draw_rect(Rect2(road_x - sh - 2.0, 0.0, 2.0, H), Color(0.15, 0.16, 0.14, 0.55))
	draw_rect(Rect2(road_x + road_w, 0.0, 2.0, H), Color(0.15, 0.16, 0.14, 0.55))
	draw_rect(Rect2(road_x - sh, 0.0, 2.0, H), Color(0.16, 0.17, 0.16, 0.35))
	draw_rect(Rect2(road_x + road_w + sh - 2.0, 0.0, 2.0, H), Color(0.16, 0.17, 0.16, 0.35))
	var period := 170.0
	var off := fposmod(scroll, period)
	var y := off - period
	while y < H + period:
		draw_rect(Rect2(road_x - sh, y, sh, 1.5), Color(0.18, 0.18, 0.17, 0.35))
		draw_rect(Rect2(road_x + road_w, y, sh, 1.5), Color(0.18, 0.18, 0.17, 0.35))
		y += period


func _draw_markings() -> void:
	var paint := Color(0.95, 0.94, 0.89, 0.93)
	draw_rect(Rect2(road_x + 12.0, 0.0, 7.0, H), paint)
	draw_rect(Rect2(road_x + road_w - 19.0, 0.0, 7.0, H), paint)
	# Worn edge along the solid lines.
	draw_rect(Rect2(road_x + 17.5, 0.0, 1.5, H), Color(0.36, 0.38, 0.39, 0.22))
	draw_rect(Rect2(road_x + road_w - 14.0, 0.0, 1.5, H), Color(0.36, 0.38, 0.39, 0.22))
	var period := 250.0
	var dash := 96.0
	var off := fposmod(scroll, period)
	for l in range(1, LANES):
		var x := road_x + lane_w * l - 3.5
		var y := off - period
		while y < H + period:
			draw_rect(Rect2(x + 1.0, y + 2.0, 7.0, dash), Color(0.05, 0.05, 0.06, 0.12))
			draw_rect(Rect2(x, y, 7.0, dash), paint)
			draw_rect(Rect2(x + 5.0, y + 4.0, 2.0, dash - 8.0), Color(0.80, 0.80, 0.76, 0.28))
			y += period
	# Reflective studs on the edge lines.
	var stud_period := 190.0
	var stud_y := fposmod(scroll, stud_period) - stud_period
	while stud_y < H + stud_period:
		for side in [15.5, road_w - 15.5]:
			draw_circle(Vector2(road_x + side, stud_y), 2.4, Color(0.82, 0.84, 0.80, 0.55))
			draw_circle(Vector2(road_x + side, stud_y), 1.3, Color(1.0, 0.96, 0.78, 0.85))
		stud_y += stud_period


func _draw_rails() -> void:
	var sh := 27.0
	for side in [-1, 1]:
		var x := road_x - sh - 12.0 if side < 0 else road_x + road_w + sh + 6.0
		draw_rect(Rect2(x + 3.0, 0.0, 8.0, H), Color(0, 0, 0, 0.16))
		draw_rect(Rect2(x, 0.0, 12.0, H), Color(0.68, 0.70, 0.71))
		draw_rect(Rect2(x, 0.0, 4.0, H), Color(0.86, 0.88, 0.88))
		draw_rect(Rect2(x + 10.0, 0.0, 2.0, H), Color(0.46, 0.48, 0.49))
		var period := 190.0
		var off := fposmod(scroll, period)
		var y := off - period
		while y < H + period:
			draw_rect(Rect2(x - 3.0, y, 18.0, 8.0), Color(0.36, 0.38, 0.39))
			draw_rect(Rect2(x - 3.0, y, 18.0, 2.0), Color(0.60, 0.62, 0.63))
			y += period


func _draw_scenery() -> void:
	var period := 2600.0
	for d in decor:
		var base_y := fposmod(float(d.y) + scroll, period)
		for k in [-1, 0, 1]:
			var y: float = base_y + k * period
			if y < -170.0 or y > H + 170.0:
				continue
			var side: float = d.side
			var x: float = (road_x - 52.0 - float(d.off)) if side < 0 else (road_x + road_w + 52.0 + float(d.off))
			var kind: int = d.kind
			var s: float = d.size
			if kind == 0:
				Art.tree(self, Vector2(x, y), 41.0 * s, d.tint)
			elif kind == 1:
				Art.bush(self, Vector2(x, y), 34.0 * s)
			elif kind == 2:
				Art.streetlight(self, Vector2(x, y), 1.0 if side < 0 else -1.0, 0.9 * s)
			else:
				Art.road_sign(self, Vector2(x, y), side)


func _draw_streetlight_glows() -> void:
	var light := get_light_factor()
	if light <= 0.04:
		return
	var period := 2600.0
	for d in decor:
		if int(d.kind) != 2:
			continue
		var base_y := fposmod(float(d.y) + scroll, period)
		for k in [-1, 0, 1]:
			var y: float = base_y + float(k) * period
			if y < -200.0 or y > H + 200.0:
				continue
			var side: float = d.side
			var x: float = (road_x - 52.0 - float(d.off)) if side < 0 else (road_x + road_w + 52.0 + float(d.off))
			var s: float = d.size
			var arm_dir: float = 1.0 if side < 0 else -1.0
			var lamp_x: float = x + arm_dir * 92.0 * 0.9 * s
			var pool_x: float = road_x + 120.0 if side < 0 else road_x + road_w - 120.0
			_glow(Vector2(pool_x, y), 106.0 * s, Color(1.0, 0.80, 0.40, 0.16 * light), Vector2(1.75, 0.62))
			_glow(Vector2(pool_x, y), 66.0 * s, Color(1.0, 0.90, 0.62, 0.22 * light), Vector2(1.45, 0.60))
			_glow(Vector2(lamp_x, y), 62.0 * s, Color(1.0, 0.78, 0.38, 0.30 * light))
			_glow(Vector2(lamp_x, y), 24.0 * s, Color(1.0, 0.97, 0.84, 0.78 * light))
			if wetness > 0.08:
				_glow(Vector2(pool_x, y + 78.0 * s), 34.0 * s, Color(1.0, 0.82, 0.46, 0.16 * wetness * light), Vector2(0.55, 3.1))


func _draw_items() -> void:
	for it in items:
		var p := Vector2(float(it.x), float(it.y))
		if int(it.kind) == 0:
			Art.coin(self, p, 17.0, float(it.phase))
		else:
			Art.nitro_can(self, p, 30.0, float(it.phase))


func _draw_speed_streaks() -> void:
	if not (boosting and running):
		return
	for i in range(16):
		var x := fposmod(float(i) * 97.0 + 31.0, W)
		var y := fposmod(scroll * 1.35 + float(i) * 191.0, H + 200.0) - 100.0
		draw_line(Vector2(x, y), Vector2(x, y + 110.0), Color(1, 1, 1, 0.075), 2.0)




func _draw_rewind_fx() -> void:
	var tint := 0.08 + 0.04 * sin(t * 22.0)
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.36, 0.60, 0.92, tint))
	for i in range(14):
		var y := fposmod(float(i) * 127.0 + t * 620.0, H + 80.0) - 40.0
		draw_line(Vector2(0.0, y), Vector2(W, y), Color(0.80, 0.92, 1.0, 0.045), 2.0)
	for i in range(4):
		var y := fposmod(float(i) * 379.0 - t * 980.0, H + 160.0) - 80.0
		draw_rect(Rect2(0.0, y, W, 2.5), Color(0.88, 0.95, 1.0, 0.055))


# --- atmospheric water ------------------------------------------------------

# A thin veil of surface water on the asphalt. The texture tiles with the road,
# so it slides exactly as fast as the markings and never "swims".
func _draw_wet_sheen() -> void:
	if wetness <= 0.02 or wet_tex == null:
		return
	var amb := get_sky_ambient()
	var night := get_night_factor()
	var light := get_light_factor()
	var tile := 256.0
	var off := fposmod(scroll, tile)
	var tint := Color(
		clampf(0.55 + amb.r * 0.45, 0.0, 1.0),
		clampf(0.66 + amb.g * 0.40, 0.0, 1.0),
		clampf(0.82 + amb.b * 0.30, 0.0, 1.0)
	)
	draw_texture_rect(wet_tex, Rect2(road_x, off - tile, road_w, H + tile * 2.0), true,
		Color(tint.r, tint.g, tint.b, wetness * (0.30 + night * 0.10)))
	# A cool long sheen along the lane centres: the specular smear that wet
	# tarmac always shows when there is light above.
	for l in range(LANES):
		var cx := _lane_x(l)
		Fx.vgrad(self, Rect2(cx - lane_w * 0.30, 0.0, lane_w * 0.60, H),
			Color(0.70, 0.82, 0.98, wetness * (0.020 + light * 0.030)),
			Color(0.70, 0.82, 0.98, wetness * (0.050 + light * 0.060)))
	# Puddle glare near the camera, where the grazing angle is sharpest.
	Fx.vgrad(self, Rect2(road_x, H * 0.62, road_w, H * 0.38),
		Color(0.72, 0.84, 1.0, 0.0),
		Color(0.72, 0.84, 1.0, wetness * (0.045 + light * 0.075)))


# Water thrown off the road by every car. Distant cars lift a small plume; the
# player lifts a real rooster tail that trails back and glows in the beams.
func _draw_road_mist() -> void:
	if wetness <= 0.08 or glow_tex == null:
		return
	var night := get_night_factor()
	var light := get_light_factor()
	var speed_k := clampf(speed / maxf(1.0, top_speed), 0.0, 1.0)
	var base_a := wetness * (0.055 + 0.075 * speed_k) * (1.0 - night * 0.35)
	for c in cars:
		var cy := float(c.y)
		if cy < -140.0 or cy > H + 120.0:
			continue
		var s := float(c.w) / car_w
		var mist := 0.55 + 0.45 * clampf((cy - 120.0) / H, 0.0, 1.0)
		for i in range(3):
			var f := float(i) / 2.0
			var p := Vector2(float(c.x) + sin(t * 2.1 + cy * 0.01 + f * 3.0) * 6.0 * s,
				cy + float(c.h) * 0.50 + 18.0 + f * 26.0)
			Fx.pool(self, glow_tex, p, (30.0 + f * 26.0) * s,
				Color(0.80, 0.87, 0.96, base_a * mist * (1.0 - f * 0.30)), Vector2(1.9, 0.55))
	if running and not demo:
		var tail := clampf(speed / maxf(1.0, top_speed), 0.2, 1.2)
		for i in range(5):
			var f := float(i) / 4.0
			var yy := player_y + car_h * 0.50 + f * 150.0 * (0.6 + tail)
			var rr := (30.0 + f * 30.0) * (0.9 + tail * 0.25)
			var px := player_x + sin(t * 3.3 + f * 2.0) * 5.0
			Fx.pool(self, glow_tex, Vector2(px, yy), rr,
				Color(0.84, 0.90, 0.99, base_a * 1.35 * (1.0 - f * 0.22)), Vector2(2.0, 0.55))
			# The part of the spray the headlights pick up, so the tail glows.
			if light > 0.1:
				Fx.pool(self, glow_tex, Vector2(px, yy - 20.0), rr * 0.8,
					Color(1.0, 0.94, 0.82, base_a * light * 0.55 * (1.0 - f * 0.3)), Vector2(1.6, 0.5))


func _draw_cars() -> void:
	var list := cars.duplicate()
	list.sort_custom(func(a, b): return float(a.y) < float(b.y))
	var player_drawn := false
	var light := get_light_factor()
	for c in list:
		if running and not demo and not player_drawn and float(c.y) > player_y:
			_draw_player()
			player_drawn = true
		var center := Vector2(float(c.x), float(c.y))
		Art.traffic(self, center, float(c.w), float(c.h), int(c.get("kind", 0)), c.color, {
			"stripe": bool(c.get("stripe", false)),
			"wing": bool(c.get("wing", false)),
			"rails": bool(c.get("rails", false)),
			"roof_sign": bool(c.get("roof_sign", false)),
			"cargo": bool(c.get("cargo", false)),
			"brake": bool(c.get("braking", false)),
			"light": light,
			"silhouette": str(c.get("silhouette", "sedan")),
			"exact": true,
			"stripe_color": c.get("stripe_color", Color(0.94, 0.93, 0.90)),
			"trailer": c.get("trailer", Color(0.78, 0.79, 0.79)),
			"accent": c.get("accent", Color(0.86, 0.27, 0.22)),
		})
	if running and not demo and not player_drawn:
		_draw_player()


func _draw_player() -> void:
	draw_set_transform(Vector2(player_x + _sx, player_y + _sy), player_tilt)
	if boosting:
		for side in [-1, 1]:
			var fx: float = float(side) * car_w * 0.23
			draw_circle(Vector2(fx, car_h * 0.50), car_w * 0.11, Color(1.0, 0.55, 0.18, 0.35))
			draw_circle(Vector2(fx, car_h * 0.54), car_w * 0.07, Color(1.0, 0.85, 0.45, 0.45))
	Art.car(self, Vector2.ZERO, car_w, car_h, player_color, {
		"player": true,
		"stripe": player_stripe,
		"wing": player_wing,
		"stripe_color": player_stripe_col,
		"silhouette": player_silhouette,
		"brake": braking and running,
		"heat": brake_heat,
		"light": get_light_factor(),
	})
	draw_set_transform(Vector2(_sx, _sy))


func _draw_particles() -> void:
	for p in particles:
		var a: float = clampf(float(p.life) / float(p.max), 0.0, 1.0)
		var col: Color = p.col
		col.a = p.col.a * a
		draw_circle(p.p, float(p.size) * (0.5 + a * 0.5), col)


func _draw_haze() -> void:
	var night := get_night_factor()
	var amb := get_sky_ambient()
	var light := get_light_factor()
	var top := Color(0.78, 0.80, 0.80, 0.12 + fog_amount * 0.20)
	top = top.lerp(Color(0.10, 0.13, 0.21, 0.22 + fog_amount * 0.14), night)
	_grad_v(Rect2(0.0, 0.0, W, 230.0), top, Color(top.r, top.g, top.b, 0.0))
	_grad_v(Rect2(0.0, H - 170.0, W, 170.0), Color(0.10, 0.11, 0.12, 0.0), Color(0.10, 0.11, 0.12, 0.10 + night * 0.10))

	# Warm sunset wash only while the sky is actually warm.
	var warmth := clampf((amb.r - amb.b) * 0.55, 0.0, 1.0) * (1.0 - night)
	if warmth > 0.02:
		_grad_v(Rect2(0.0, 0.0, W, 520.0), Color(1.0, 0.54, 0.24, warmth * 0.14), Color(1.0, 0.54, 0.24, 0.0))
		draw_rect(Rect2(0.0, 0.0, W, H), Color(1.0, 0.58, 0.30, warmth * 0.045))

	var vig := 0.13 + night * 0.12 + storm_amount * 0.08
	_grad_h(Rect2(0.0, 0.0, 120.0, H), Color(0.0, 0.0, 0.0, vig), Color(0.0, 0.0, 0.0, 0.0))
	_grad_h(Rect2(W - 120.0, 0.0, 120.0, H), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, vig))
	# At night everything outside the headlights sinks into darkness. The heavy
	# falloff towards the top of the screen is what plants the feeling that
	# only the road ahead is lit.
	if night > 0.05:
		_grad_v(Rect2(0.0, 0.0, W, H * 0.38), Color(0.0, 0.0, 0.0, night * 0.20 * (1.0 - light * 0.5)), Color(0.0, 0.0, 0.0, 0.0))
		_grad_v(Rect2(0.0, H * 0.70, W, H * 0.30), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, night * 0.16))


func _grad_h(rect: Rect2, left: Color, right: Color) -> void:
	draw_polygon(
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([left, right, right, left])
	)


func _grad_v(rect: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, bottom, bottom])
	)


# All headlight illumination that lands ON the road. Drawn before the cars and
# the scenery, so the bodywork always stays on top: what we see is light on
# asphalt, not a translucent decal over the whole scene. Each lamp gets a long
# throw plus a hot near-field wedge, the way a real low beam reads from above.
func _draw_road_beams() -> void:
	var light := get_light_factor()
	if light <= 0.015 or beam_tex == null:
		return
	# Rain and fog scatter light away from the surface, so the pool under the
	# car loses some punch while the glow around the lamp grows.
	var gain := light * (1.0 + fog_amount * 0.25) * (1.0 - wetness * 0.25)
	for c in cars:
		var cy := float(c.y)
		if cy < -480.0 or cy > H + 260.0:
			continue
		var cx := float(c.x)
		var cw := float(c.w)
		var ch := float(c.h)
		var s := cw / car_w
		# Traffic drives up the screen, so its beams point to -Y.
		var nose := Vector2(cx, cy - ch * 0.44)
		var sway := sin(t * 0.9 + cy * 0.011 + cx * 0.02) * 0.010 * (0.4 + wind)
		for side in [-1.0, 1.0]:
			var lamp := nose + Vector2(float(side) * cw * 0.26, 0.0)
			var ang := PI + sway
			var throw_len := 300.0 * s * (1.0 + fog_amount * 0.22)
			Fx.beam(self, beam_tex, lamp, ang, cw * 1.55, throw_len, Color(1.0, 0.90, 0.70, 0.26 * gain))
			Fx.beam(self, beam_tex, lamp, ang, cw * 0.92, throw_len * 0.62, Color(1.0, 0.96, 0.86, 0.30 * gain))
		Fx.pool(self, glow_tex, Vector2(cx, cy - ch * 0.75), 96.0 * s * (1.0 + fog_amount * 0.3),
			Color(1.0, 0.86, 0.62, 0.09 * gain), Vector2(1.7, 1.0))
	if running and not demo:
		var nose := Vector2(player_x, player_y - car_h * 0.44)
		var sway_p := sin(t * 0.7) * 0.006 * (0.5 + wind)
		for side in [-1.0, 1.0]:
			var lamp := nose + Vector2(float(side) * car_w * 0.26, 0.0)
			var ang := sway_p + float(side) * 0.035 + player_tilt * 0.6
			# Long throw: the point of real headlights is seeing far ahead.
			Fx.beam(self, beam_tex, lamp, ang, car_w * 1.75, 560.0 * (1.0 + fog_amount * 0.18), Color(1.0, 0.91, 0.72, 0.28 * gain))
			# Hot patch just in front of the bumper, where the cutoff bites.
			Fx.beam(self, beam_tex, lamp, ang, car_w * 1.05, 330.0, Color(1.0, 0.96, 0.85, 0.34 * gain))
			# Very wide, very faint spill that reveals the lane edges.
			Fx.beam(self, beam_tex, lamp, ang, car_w * 2.60, 200.0, Color(1.0, 0.90, 0.70, 0.11 * gain))
		# The bright pool right at the nose: a low beam is brightest here and
		# the cutoff makes it almost flat and very wide.
		Fx.pool(self, glow_tex, Vector2(player_x, player_y - car_h * 0.56 - 210.0), 200.0 * (1.0 + fog_amount * 0.25),
			Color(1.0, 0.93, 0.76, 0.09 * gain), Vector2(1.9, 0.85))


# Beams seen in the AIR: drawn over the cars and under the rain. The cone is
# deliberately thin here: the bright part lives on the road, this is the halo
# that makes light feel volumetric, especially in fog and rain. The lamp bloom
# ("brows") is drawn last so it sits on the bodywork like real glare.
func _draw_air_beams() -> void:
	var light := get_light_factor()
	if light <= 0.015 or beam_tex == null:
		return
	var haze := 0.30 * rain_amount + 1.05 * fog_amount + 0.42 * storm_amount
	var gain := light * maxf(haze, 0.10)
	var scatter := 1.0 + fog_amount * 0.9 + rain_amount * 0.25
	var brows: Array = []
	for c in cars:
		var cy := float(c.y)
		if cy < -420.0 or cy > H + 200.0:
			continue
		var cx := float(c.x)
		var cw := float(c.w)
		var ch := float(c.h)
		var s := cw / car_w
		var nose := Vector2(cx, cy - ch * 0.44)
		var sway := sin(t * 0.9 + cy * 0.011 + cx * 0.02) * 0.010 * (0.4 + wind)
		for side in [-1.0, 1.0]:
			var lamp := nose + Vector2(float(side) * cw * 0.26, 0.0)
			Fx.beam(self, beam_tex, lamp, PI + sway, cw * 0.95 * scatter, 300.0 * s * scatter,
				Color(1.0, 0.88, 0.66, 0.13 * gain))
			var r := 44.0 * s * scatter
			brows.append({"rect": Rect2(lamp + Vector2(-r, -r * 0.62), Vector2(r * 2.0, r * 1.24)), "a": 0.09 * gain})
	if running and not demo:
		var nose := Vector2(player_x, player_y - car_h * 0.44)
		var sway_p := sin(t * 0.7) * 0.006 * (0.5 + wind)
		for side in [-1.0, 1.0]:
			var lamp := nose + Vector2(float(side) * car_w * 0.26, 0.0)
			var ang := sway_p + float(side) * 0.035 + player_tilt * 0.6
			Fx.beam(self, beam_tex, lamp, ang, car_w * 1.00 * scatter, 500.0 * scatter,
				Color(1.0, 0.90, 0.70, 0.17 * gain))
			var r := 64.0 * scatter
			brows.append({"rect": Rect2(lamp + Vector2(-r, -r * 1.10), Vector2(r * 2.0, r * 1.60)), "a": 0.11 * gain})
	draw_set_transform(Vector2(_sx, _sy))
	for b in brows:
		draw_texture_rect(glow_tex, b.rect, false, Color(1.0, 0.91, 0.74, b.a))


func _draw_car_light_glows() -> void:
	var light := get_light_factor()
	if light <= 0.035:
		return

	for c in cars:
		var cy := float(c.y)
		var cx := float(c.x)
		var cw := float(c.w)
		var ch := float(c.h)
		if cy < -200.0 or cy > H + 200.0:
			continue
		var braking := bool(c.get("braking", false))
		var head_a := 0.30 * light
		for side in [-1, 1]:
			var hp := Vector2(cx + float(side) * cw * 0.28, cy - ch * 0.452)
			_glow(hp, 54.0, Color(1.0, 0.90, 0.64, head_a * 0.30))
			_glow(hp, 20.0, Color(1.0, 0.95, 0.80, head_a))
			_glow(hp, 7.0, Color(1.0, 0.99, 0.94, 0.80 * light))

		var tail_a := (0.62 if braking else 0.30) * light
		for side in [-1, 1]:
			var tp := Vector2(cx + float(side) * cw * 0.285, cy + ch * 0.462)
			_glow(tp, 46.0, Color(1.0, 0.16, 0.10, tail_a * 0.32))
			_glow(tp, 18.0, Color(1.0, 0.22, 0.14, tail_a))
			_glow(tp, 7.0, Color(1.0, 0.46, 0.32, tail_a * 1.10))
		if braking:
			_glow(Vector2(cx, cy + ch * 0.475), 64.0, Color(1.0, 0.10, 0.06, 0.22 * light), Vector2(2.2, 0.8))

	if running and not demo:
		for side in [-1, 1]:
			var hp := Vector2(player_x + float(side) * car_w * 0.28, player_y - car_h * 0.452)
			_glow(hp, 62.0, Color(1.0, 0.90, 0.62, 0.22 * light))
			_glow(hp, 23.0, Color(1.0, 0.96, 0.82, 0.38 * light))
			_glow(hp, 8.0, Color(1.0, 1.0, 0.96, 0.82 * light))
			var tp := Vector2(player_x + float(side) * car_w * 0.285, player_y + car_h * 0.462)
			_glow(tp, 24.0, Color(1.0, 0.16, 0.10, 0.35 * light))
			_glow(tp, 8.0, Color(1.0, 0.34, 0.22, 0.60 * light))


# Reflections on a wet road. A wet surface is a poor mirror but a very long
# one: every bright lamp smears into a vertical streak towards the viewer. The
# streaks use a dedicated texture (bright at the source, fading with distance)
# and sit under the mist, so a car never looks pasted onto the tarmac.
func _draw_wet_reflections() -> void:
	if wetness <= 0.05 or streak_tex == null:
		return
	var light := get_light_factor()
	var night := get_night_factor()
	var wet := wetness * (0.30 + light * 0.70)
	var sheen := Color(0.80, 0.88, 1.0)

	if light > 0.03:
		for c in cars:
			var cy := float(c.y)
			var cx := float(c.x)
			var cw := float(c.w)
			var ch := float(c.h)
			if cy < -240.0 or cy > H + 60.0:
				continue
			var braking := bool(c.get("braking", false))
			var tail_a := (0.55 if braking else 0.30) * wet
			for side in [-1, 1]:
				var tx := cx + float(side) * cw * 0.285
				draw_texture_rect(streak_tex, Rect2(tx - 11.0, cy + ch * 0.47, 22.0, 190.0), false, Color(1.0, 0.20, 0.14, tail_a * 0.55))
				if light > 0.3:
					# Headlights of every car are mirrored far ahead of it.
					var hx := cx + float(side) * cw * 0.26
					draw_texture_rect(streak_tex, Rect2(hx - 16.0, cy - ch * 0.48 - 210.0, 32.0, 210.0), false, Color(1.0, 0.92, 0.74, 0.11 * wet * light))

	if running and not demo:
		for side in [-1, 1]:
			var hx := player_x + float(side) * car_w * 0.28
			# The player's beams reflect as two long warm streaks up the road.
			draw_texture_rect(streak_tex, Rect2(hx - 26.0, player_y - car_h * 0.45 - 340.0, 52.0, 340.0), false, Color(1.0, 0.95, 0.80, 0.15 * wet))
			# Tail lights bleed onto the tarmac right behind the car.
			draw_texture_rect(streak_tex, Rect2(player_x - 82.0, player_y + car_h * 0.46, 164.0, 80.0), false, Color(1.0, 0.18, 0.12, 0.16 * wet))

	# Sky-coloured smears along the edges: what tells the eye the road is
	# SOAKED and not merely darker.
	if wetness > 0.25:
		draw_texture_rect(streak_tex, Rect2(road_x + 40.0, 0.0, 46.0, H), false, Color(sheen.r, sheen.g, sheen.b, 0.030 * wetness * (1.0 - night * 0.4)))
		draw_texture_rect(streak_tex, Rect2(road_x + road_w - 86.0, 0.0, 46.0, H), false, Color(sheen.r, sheen.g, sheen.b, 0.030 * wetness * (1.0 - night * 0.4)))


func _draw_rain_splashes() -> void:
	if rain_splashes.is_empty():
		return
	var night := get_night_factor()
	var light := get_light_factor()
	var wash := Color(0.78, 0.87, 1.0).lerp(Color(1.0, 0.95, 0.86), light * 0.55 * (1.0 - night))
	for sp in rain_splashes:
		var k: float = clampf(1.0 - float(sp.life) / float(sp.max), 0.0, 1.0)
		var r: float = float(sp.size) * (0.20 + k * 0.95)
		var a: float = (1.0 - k) * (1.0 - k) * 0.46 * rain_amount
		if a <= 0.008:
			continue
		var c := Vector2(float(sp.x) + _sx, float(sp.y) + _sy)
		draw_set_transform(c, 0.0, Vector2(1.0, 0.42))
		# A crown, not a cartoon ring: a thin bright crest plus a faint inner one.
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 14, Color(wash.r, wash.g, wash.b, a), 1.1, true)
		draw_arc(Vector2.ZERO, r * 0.52, 0.0, TAU, 9, Color(wash.r, wash.g, wash.b, a * 0.45), 0.8, true)
		draw_set_transform(Vector2(_sx, _sy))
		if k < 0.35:
			# Tiny sprite of water kicked straight up at the moment of impact.
			draw_circle(c + Vector2(0.0, -float(sp.size) * 0.35 * (1.0 - k)), 0.9,
				Color(wash.r, wash.g, wash.b, a * 0.9 * (1.0 - k / 0.35)))


func _draw_lightning() -> void:
	var flash_a := lightning * (0.72 + 0.28 * sin(t * 83.0))
	if flash_a <= 0.02:
		return
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.72, 0.80, 1.0, 0.20 * flash_a))
	for b in lightning_branches:
		draw_polyline(b, Color(0.74, 0.84, 1.0, 0.30 * flash_a), 4.0, true)
		draw_polyline(b, Color(0.96, 0.99, 1.0, 0.72 * flash_a), 1.4, true)
	if lightning_bolt.size() >= 2:
		draw_polyline(lightning_bolt, Color(0.60, 0.76, 1.0, 0.24 * flash_a), 12.0, true)
		draw_polyline(lightning_bolt, Color(0.86, 0.93, 1.0, 0.66 * flash_a), 5.0, true)
		draw_polyline(lightning_bolt, Color(1.0, 1.0, 1.0, 0.95 * flash_a), 1.8, true)


# Rain. Every drop is drawn as a streak along the exact direction it travels:
# the simulation moves it with (rain_vx, rain_vy), the renderer takes the same
# vector, so the slant is always right and a gust bends the whole field at
# once. Streaks are clipped to the screen and drops that leave an edge reappear
# on the opposite one, so nothing flashes at the borders.
#
# Cost: one draw_set_transform + one textured quad per drop. The per-layer pass
# keeps drops of similar width together, which lets the renderer batch them.
func _draw_rain() -> void:
	if rain_amount <= 0.02 or rain_tex == null:
		return
	var dir := Vector2(rain_vx, rain_vy)
	if dir.length_squared() < 1.0:
		dir = Vector2(0.0, 1.0)
	dir = dir.normalized()
	# draw_set_transform rotates CLOCKWISE for positive angles, so the angle is
	# atan2(dx, -dy): a drop blown to the left (-dx) must lean to the left.
	var ang := atan2(dir.x, -dir.y)
	var night := get_night_factor()
	var light := get_light_factor()
	var tint := Color(0.70, 0.79, 0.93).lerp(Color(0.88, 0.93, 1.0), 1.0 - night)
	var head_tint := Color(1.0, 0.95, 0.86)
	var spd_k := clampf((rain_vy - 340.0) / 440.0, 0.0, 1.0)
	var wind_k := clampf(-rain_vx / 480.0, -0.4, 1.2)
	# One shutter time for the whole sheet: a streak is exactly as long as the
	# path its own drop covers in that slice of time. Drops in the near layer
	# sweep more pixels per second, so they smear longer - that is motion blur,
	# and it is why the sheet reads as depth instead of as hatching.
	var shutter := 0.0168
	var show_head := light > 0.15 and running and not demo
	var nose_y := player_y - car_h * 0.44
	var travel_len := Vector2(rain_vx, rain_vy).length() * rain_scale
	for layer_i in range(3):
		var k_layer := 1.0 + float(layer_i) * 0.16
		var layer_a := 0.85 + float(layer_i) * 0.18
		var depth_a := lerpf(0.72, 1.0, float(layer_i) / 2.0)
		for rd in rain_drops:
			if int(rd.layer) != layer_i:
				continue
			var color := Color(0.0, 0.0, 0.0)
			if QA_FIELD:
				# Encode the drop index in the red channel and the layer in green.
				var idx := rain_drops.find(rd)
				color = Color(float(idx % 250 + 5) / 255.0, float(64 + layer_i * 60) / 255.0, 1.0)
			var kf: float = float(rd.fall) / 1000.0
			var length: float = clampf(travel_len * kf * shutter, 10.0, 64.0)
			var width: float = maxf(float(rd.width) * (0.85 + spd_k * 0.35), 1.5)
			var a: float = float(rd.alpha) * rain_amount * layer_a * depth_a
			if a <= 0.008:
				continue
			var px: float = float(rd.x) + _sx
			var py: float = float(rd.y) + _sy
			if QA_FIELD:
				# QA harness: paint drop ids into the frame instead of streaks, so
				# blob-to-drop mapping is exact and the tilt is measurable.
				draw_set_transform(Vector2(px, py), ang, Vector2.ONE)
				draw_rect(Rect2(-width * 0.5, -length, maxf(width, 1.0), length),
					Color(color.r, color.g, color.b, 1.0))
				continue
			# Cheap screen clip: skip drops whose whole streak is outside.
			if py - length > H + 40.0 or py < -40.0 or px < -70.0 or px > W + 70.0:
				continue
			draw_set_transform(Vector2(px, py), ang, Vector2.ONE)
			_rain_streak(width, length, Color(tint.r, tint.g, tint.b, a))
			# Headlight catch: streaks inside the beams pick up a warm glint,
			# which is what makes rain read as three-dimensional at night.
			if show_head:
				var d_nose := py - nose_y
				if d_nose < 0.0 and d_nose > -640.0:
					var spread_q := 64.0 + (-d_nose) * 0.62
					var off_x := absf(px - player_x)
					if off_x < spread_q:
						var k2 := (1.0 + d_nose / 640.0) * (1.0 - off_x / spread_q)
						_rain_streak(width, length, Color(head_tint.r, head_tint.g, head_tint.b, a * light * k2 * 0.9))
	draw_set_transform(Vector2(_sx, _sy))
	# The air itself gets heavier and cooler in a downpour.
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.12, 0.18, 0.26, rain_amount * 0.075 + storm_amount * 0.06))
	# Driving rain: the far edge of the screen gets a thin wind-driven sheet.
	if wind_k > 0.12:
		Fx.hgrad(self, Rect2(0.0, 0.0, W, H * 0.55),
			Color(tint.r, tint.g, tint.b, rain_amount * 0.035 * wind_k),
			Color(tint.r, tint.g, tint.b, 0.0))


# One rain streak, drawn in a frame that is already rotated to the fall
# direction (the caller sets the transform). Drawing through a single helper
# keeps the physical model in one place, and it lets the QA harness render this
# exact code path in isolation.
func _rain_streak(width: float, length: float, col: Color) -> void:
	if pending_rect:
		draw_rect(Rect2(-width * 0.5, -length, maxf(width, 1.5), length), col)
		return
	if rain_tex == null:
		return
	draw_texture_rect(rain_tex, Rect2(-width * 0.5, -length, maxf(width, 1.5), length), false, col)


# The QA harness asks for a single, isolated streak so it can measure the real
# rasterised geometry instead of guessing it. Never used during normal play.
func _draw_probe_streak() -> void:
	if pending == null:
		return
	var d: Dictionary = pending
	var ang := float(d.get("ang", 0.0))
	var p := Vector2(float(d.x), float(d.y))
	var w := float(d.w) * 0.5
	var ln := minf(float(d.len), 12.0)
	var c := cos(ang)
	var s := sin(ang)
	var corners := PackedVector2Array()
	for off in [Vector2(-w, -ln), Vector2(w, -ln), Vector2(w, 0.0), Vector2(-w, 0.0)]:
		corners.append(p + Vector2(off.x * c - off.y * s, off.x * s + off.y * c))
	draw_colored_polygon(corners, Color(1.0, 1.0, 1.0, float(d.a)))
	# A green tick above the origin: a fixed, unmoving marker the harness can
	# always find, independent of how the coordinate frames are scaled.
	draw_rect(Rect2(0.0, 0.0, 6.0, 3.0), Color(0.0, 1.0, 0.0))


# Drops landing on the windscreen: big, short-lived motion streaks over the
# whole frame. This is what sells speed in the rain.
func _draw_rain_lens() -> void:
	if rain_lens.is_empty() or rain_tex == null:
		return
	var dir := Vector2(rain_vx, rain_vy)
	if dir.length_squared() < 1.0:
		dir = Vector2(0.0, 1.0)
	var ang := atan2(dir.x, dir.y)
	draw_set_transform(Vector2(_sx, _sy), ang, Vector2.ONE)
	for d in rain_lens:
		var k: float = clampf(float(d.life) / float(d.max), 0.0, 1.0)
		var stretch: float = 1.0 + (1.0 - k) * 1.5
		var p := Vector2(float(d.x) + _sx, float(d.y) + _sy)
		draw_texture_rect(rain_tex, Rect2(p.x - float(d.w) * 0.5, p.y - float(d.len) * stretch,
			float(d.w), float(d.len) * stretch), false, Color(0.84, 0.91, 1.0, 0.20 * k * k * rain_amount))
	draw_set_transform(Vector2(_sx, _sy))


func _draw_fog() -> void:
	if fog_amount <= 0.02:
		return
	var night := get_night_factor()
	var pale := Color(0.70, 0.75, 0.80).lerp(Color(0.19, 0.23, 0.30), night * 0.70)
	var f_a := fog_amount
	_grad_v(Rect2(0.0, 0.0, W, 780.0), Color(pale.r, pale.g, pale.b, f_a * 0.78), Color(pale.r, pale.g, pale.b, 0.0))
	_grad_v(Rect2(0.0, H - 560.0, W, 560.0), Color(pale.r, pale.g, pale.b, 0.0), Color(pale.r, pale.g, pale.b, f_a * 0.46))
	draw_rect(Rect2(0.0, 0.0, W, H), Color(pale.r, pale.g, pale.b, f_a * 0.16))
	for i in range(9):
		var x := fposmod(float(i) * 239.0 + t * (4.0 + float(i) * 1.7) + scroll * 0.045, W + 820.0) - 410.0
		var y := fposmod(scroll * (0.16 + float(i) * 0.055) + float(i) * 277.0 + t * 3.0, H + 680.0) - 340.0
		var rx := 270.0 + float(i) * 42.0
		var ry := 132.0 + float(i) * 23.0
		var a := f_a * (0.125 + 0.042 * sin(t * 0.55 + float(i) * 1.73))
		draw_texture_rect(glow_tex, Rect2(x - rx, y - ry, rx * 2.0, ry * 2.0), false, Color(pale.r, pale.g, pale.b, a))


func _draw_rear_hazards() -> void:
	if not running or crashed:
		return
	var pulse := 0.65 + 0.35 * sin(t * 14.0)
	for c in cars:
		var cy: float = float(c.y)
		if cy > H - 160.0:
			var cx: float = float(c.x)
			var alert_y := H - 38.0
			var col := Color(1.0, 0.22, 0.18, pulse * 0.90)
			var pts := PackedVector2Array([
				Vector2(cx, alert_y - 18.0),
				Vector2(cx - 16.0, alert_y + 4.0),
				Vector2(cx - 10.0, alert_y + 4.0),
				Vector2(cx, alert_y - 8.0),
				Vector2(cx + 10.0, alert_y + 4.0),
				Vector2(cx + 16.0, alert_y + 4.0),
			])
			draw_colored_polygon(pts, col)
			draw_circle(Vector2(cx, alert_y + 12.0), 3.0, col)


func _draw_night_atmosphere() -> void:
	var night := get_night_factor()
	if night > 0.02:
		draw_rect(Rect2(0.0, 0.0, W, H), Color(0.03, 0.04, 0.10, night * 0.52))
		draw_rect(Rect2(0.0, 0.0, W, H), Color(0.02, 0.03, 0.07, night * 0.12))
	if storm_amount > 0.02:
		draw_rect(Rect2(0.0, 0.0, W, H), Color(0.04, 0.05, 0.09, storm_amount * 0.08))
	if rain_amount > 0.02:
		draw_rect(Rect2(0.0, 0.0, W, H), Color(0.14, 0.20, 0.28, rain_amount * 0.05))
