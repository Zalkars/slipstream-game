class_name Game
extends Node2D

# Top-down highway racer: procedural road, traffic, pickups, braking and nitro.

signal hud_changed(score: int, kmh: int, nitro: float, combo: int, coins: int, boosting: bool)
signal run_ended(score: int, distance: int, near: int, coins: int)
signal near_miss(combo: int)
signal pickup_taken(kind: int)
signal lane_changed(new_lane: int)
signal brake_state_changed(is_braking: bool)

const LANES := 4
const DEMO_SPEED := 620.0
const NITRO_SEG := 1.0 / 3.0
const BOOST_TIME := 1.6
const BRAKE_MULT := 0.42
const TRAFFIC_COLORS := [
	Color("#e8e7e3"), Color("#b9bdc1"), Color("#3d4147"), Color("#1b1e22"),
	Color("#5e2b2b"), Color("#2c4a6e"), Color("#3c5c48"), Color("#c9c3b4"),
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
var skid_marks: Array = []
var _has_prev_skid := false
var _prev_skid_l := Vector2.ZERO
var _prev_skid_r := Vector2.ZERO
var _nitro_cooldown := 0.0

var car_index := 0
var base_speed := 740.0
var top_speed := 1100.0
var handling := 12.0
var player_color := Color("#b32b26")
var player_stripe := true
var player_wing := false
var player_stripe_col := Color("#f0ede4")

var control_mode := "buttons"
var free_lane := 3
var free_t := 7.0
var pickup_coins := 0

var swipe_start := Vector2.ZERO
var swipe_used := true

var asphalt_tex: ImageTexture
var grass_tex: ImageTexture
var _sx := 0.0
var _sy := 0.0


func _ready() -> void:
	asphalt_tex = _noise_tex(128, Color(0.365, 0.375, 0.395), 0.030, 11)
	grass_tex = _noise_tex(128, Color(0.400, 0.500, 0.295), 0.042, 23)
	_gen_decor()
	_layout()
	get_viewport().size_changed.connect(_layout)
	start_demo()


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
	for y in range(size):
		for x in range(size):
			var n := rng.randf_range(-1.0, 1.0)
			img.set_pixel(x, y, Color(
				clampf(base.r + n * variation, 0.0, 1.0),
				clampf(base.g + n * variation, 0.0, 1.0),
				clampf(base.b + n * variation, 0.0, 1.0),
				1.0
			))
	for i in range(size * 2):
		var px := rng.randi_range(0, size - 1)
		var py := rng.randi_range(0, size - 1)
		img.set_pixel(px, py, base.lightened(rng.randf_range(0.10, 0.22)))
	for i in range(size):
		var px := rng.randi_range(0, size - 1)
		var py := rng.randi_range(0, size - 1)
		img.set_pixel(px, py, base.darkened(rng.randf_range(0.08, 0.18)))
	return ImageTexture.create_from_image(img)


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
	nitro = 0.0
	boosting = false
	boost_t = 0.0
	_nitro_cooldown = 0.0
	braking = false
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
	hud_changed.emit(0, int(speed * 0.3), nitro, 0, 0, false)


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
		lane_changed.emit(lane)


func set_braking(on: bool) -> void:
	if not running or paused or crashed:
		if braking:
			braking = false
			brake_state_changed.emit(false)
		return
	if braking != on:
		braking = on
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
		"demo_speed": 0.0,
		"near": false,
	}
	cars.append(c)


# --- simulation -------------------------------------------------------------

func _process(delta: float) -> void:
	var dt := minf(delta, 0.05) * time_scale
	_tick(dt)
	queue_redraw()


func _coins_total() -> int:
	return int(distance / 10.0) + pickup_coins + near * 2


func _tick(dt: float) -> void:
	if paused:
		return

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

	t += dt
	if _nitro_cooldown > 0.0:
		_nitro_cooldown = maxf(0.0, _nitro_cooldown - dt)

	if boost_t > 0.0:
		boost_t -= dt
		if boost_t <= 0.0:
			boost_t = 0.0
			boosting = false
			_nitro_cooldown = 0.35

	var ramp := clampf(t / 70.0, 0.0, 1.0)
	var ref := lerpf(base_speed, top_speed, ramp)
	var want := ref
	if boosting:
		want *= 1.5
	if braking:
		want *= BRAKE_MULT
	var k := 2.4
	if braking:
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

	var is_skidding := braking and running and not crashed and speed > 130.0
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

	_move_traffic(dt, speed, ref, false)
	_move_items(dt)
	_update_fx(dt)

	score = floor(distance) + float(bonus)
	hud_changed.emit(int(score), int(speed * 0.3), nitro, combo, _coins_total(), boosting)


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
	var py := player_y
	for i in range(cars.size() - 1, -1, -1):
		var c: Dictionary = cars[i]
		var prev_y: float = c.y
		if is_demo:
			c.y += float(c.demo_speed) * dt
		else:
			c.y += (player_speed - float(c.rel) * ref_speed) * dt

		if c.y > H + 340.0 or c.y < -900.0:
			cars.remove_at(i)
			continue

		if is_demo:
			continue

		var pw := car_w * 0.80
		var ph := car_h * 0.82
		var cw: float = float(c.w) * 0.80
		var ch: float = float(c.h) * 0.82
		if absf(c.x - player_x) < (pw + cw) * 0.5 and absf(c.y - py) < (ph + ch) * 0.5:
			_crash()
			return

		if not c.get("near", false) and prev_y < py and c.y >= py:
			if absf(float(c.x) - player_x) < lane_w * 1.22:
				c["near"] = true
				near += 1
				combo += 1
				combo_t = 2.6
				bonus += 10 * combo
				var gain := 0.045 if combo < 3 else 0.070
				nitro = minf(1.0, nitro + gain)
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

	var roll := randf()
	var kind := 0
	if roll > 0.82:
		kind = 2
	elif roll > 0.52:
		kind = 1

	var w := car_w
	var h := car_h
	var rel := randf_range(0.70, 0.79)
	var col: Color = TRAFFIC_COLORS[randi() % TRAFFIC_COLORS.size()]
	if kind == 1:
		w = car_w * 1.07
		h = car_h * 1.09
		rel = randf_range(0.66, 0.76)
	elif kind == 2:
		w = car_w * 1.14
		h = car_h * 1.72
		rel = randf_range(0.54, 0.64)

	cars.append({
		"lane": chosen,
		"x": _lane_x(chosen),
		"y": -h * 0.75,
		"w": w,
		"h": h,
		"kind": kind,
		"color": col,
		"rel": rel,
		"demo_speed": randf_range(250.0, 420.0),
		"near": false,
	})


func _crash() -> void:
	if crashed:
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

	if braking and running and not crashed and speed > 180.0 and randf() < 0.40:
		for side in [-1, 1]:
			particles.append({
				"p": Vector2(player_x + float(side) * car_w * 0.31, player_y + car_h * 0.36),
				"v": Vector2(randf_range(-16.0, 16.0), randf_range(30.0, 90.0)),
				"life": randf_range(0.24, 0.48),
				"max": 0.48,
				"col": Color(0.88, 0.90, 0.92, 0.42),
				"size": randf_range(3.5, 7.5),
			})


func finish_run() -> void:
	if running:
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
	draw_set_transform(Vector2(sx, sy))

	_draw_grass()
	_draw_road()
	_draw_shoulders()
	_draw_markings()
	_draw_skid_marks()
	_draw_rails()
	_draw_scenery()
	_draw_items()
	_draw_speed_streaks()
	_draw_cars()
	_draw_particles()

	draw_set_transform(Vector2.ZERO)
	_draw_haze()
	if flash > 0.01:
		draw_rect(Rect2(0.0, 0.0, W, H), Color(1.0, 1.0, 1.0, flash * 0.5))


func _draw_skid_marks() -> void:
	if skid_marks.is_empty():
		return
	var base_col := Color(0.04, 0.05, 0.06)
	var w := car_w * 0.16
	for sk in skid_marks:
		var a: float = clampf(float(sk.life) / float(sk.max), 0.0, 1.0) * 0.44
		draw_line(sk.p1, sk.p2, Color(base_col.r, base_col.g, base_col.b, a), w)


func _draw_grass() -> void:
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.40, 0.50, 0.30))
	if grass_tex:
		var off := fposmod(scroll * 0.92, 128.0)
		draw_texture_rect(grass_tex, Rect2(0.0, -off, W, H + 128.0), true, Color(1, 1, 1, 0.62))
	var period := 380.0
	var off2 := fposmod(scroll, period)
	var count := int(H / period) + 3
	for i in range(count):
		var y := off2 + i * period - period
		draw_circle(Vector2(W * 0.06, y + 40.0), 34.0, Color(0.26, 0.35, 0.19, 0.18))
		draw_circle(Vector2(W * 0.94, y + 170.0), 42.0, Color(0.26, 0.35, 0.19, 0.16))


func _draw_road() -> void:
	draw_rect(Rect2(road_x, 0.0, road_w, H), Color(0.355, 0.365, 0.385))
	if asphalt_tex:
		var off := fposmod(scroll, 128.0)
		draw_texture_rect(asphalt_tex, Rect2(road_x, -off, road_w, H + 128.0), true)

	for l in range(LANES):
		var cx := _lane_x(l)
		var sw := lane_w * 0.20
		draw_rect(Rect2(cx - lane_w * 0.35 - sw * 0.5, 0.0, sw, H), Color(0.06, 0.06, 0.07, 0.055))
		draw_rect(Rect2(cx + lane_w * 0.35 - sw * 0.5, 0.0, sw, H), Color(0.06, 0.06, 0.07, 0.055))
		draw_rect(Rect2(cx - lane_w * 0.35 - sw * 0.9, 0.0, sw * 1.8, H), Color(0.06, 0.06, 0.07, 0.025))
		draw_rect(Rect2(cx + lane_w * 0.35 - sw * 0.9, 0.0, sw * 1.8, H), Color(0.06, 0.06, 0.07, 0.025))

	var ew := 34.0
	_grad_h(Rect2(road_x, 0.0, ew, H), Color(0, 0, 0, 0.20), Color(0, 0, 0, 0.0))
	_grad_h(Rect2(road_x + road_w - ew, 0.0, ew, H), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.20))

	for l in range(1, LANES):
		var x := road_x + lane_w * l
		draw_rect(Rect2(x - lane_w * 0.02, 0.0, lane_w * 0.04, H), Color(0.07, 0.07, 0.08, 0.05))

	var patches := [
		[0.20, 0.10, 70.0, 0.045],
		[0.72, 0.34, 95.0, 0.040],
		[0.34, 0.62, 60.0, 0.050],
		[0.80, 0.82, 80.0, 0.042],
	]
	for spec in patches:
		var py := fposmod(float(spec[1]) * 1400.0 + scroll, 1400.0) - 180.0
		var px := road_x + road_w * float(spec[0])
		var pr := float(spec[2])
		var pa := float(spec[3])
		draw_circle(Vector2(px, py), pr, Color(0.05, 0.05, 0.06, pa))
		draw_circle(Vector2(px + pr * 0.7, py + pr * 0.25), pr * 0.68, Color(0.05, 0.05, 0.06, pa))
		draw_circle(Vector2(px - pr * 0.6, py + pr * 0.4), pr * 0.55, Color(0.05, 0.05, 0.06, pa))

	var crack_x := [0.31, 0.58, 0.79]
	for i in range(3):
		var cy := fposmod(float(i) * 430.0 + 150.0 + scroll, 1290.0) - 120.0
		var cx := road_x + road_w * float(crack_x[i])
		draw_line(Vector2(cx, cy), Vector2(cx + 13.0, cy + 42.0), Color(0.08, 0.08, 0.09, 0.22), 1.5)
		draw_line(Vector2(cx + 13.0, cy + 42.0), Vector2(cx - 5.0, cy + 88.0), Color(0.08, 0.08, 0.09, 0.20), 1.5)

	for l in range(LANES):
		var oy := fposmod(scroll + float(l) * 511.0, 1740.0) - 300.0
		draw_circle(Vector2(_lane_x(l) + lane_w * 0.08, oy), lane_w * 0.13, Color(0.05, 0.05, 0.06, 0.045))


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
	var paint := Color(0.95, 0.94, 0.89, 0.95)
	draw_rect(Rect2(road_x + 12.0, 0.0, 7.0, H), paint)
	draw_rect(Rect2(road_x + road_w - 19.0, 0.0, 7.0, H), paint)
	var period := 250.0
	var dash := 96.0
	var off := fposmod(scroll, period)
	for l in range(1, LANES):
		var x := road_x + lane_w * l - 3.5
		var y := off - period
		while y < H + period:
			draw_rect(Rect2(x, y, 7.0, dash), paint)
			y += period


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


func _draw_cars() -> void:
	var list := cars.duplicate()
	list.sort_custom(func(a, b): return float(a.y) < float(b.y))
	var player_drawn := false
	for c in list:
		if running and not demo and not player_drawn and float(c.y) > player_y:
			_draw_player()
			player_drawn = true
		var center := Vector2(float(c.x), float(c.y))
		if int(c.get("kind", 0)) == 2:
			Art.truck(self, center, float(c.w), float(c.h), c.color, Color(0.78, 0.79, 0.79))
		else:
			Art.car(self, center, float(c.w), float(c.h), c.color, {})
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
		"brake": braking and running,
	})
	draw_set_transform(Vector2(_sx, _sy))


func _draw_particles() -> void:
	for p in particles:
		var a: float = clampf(float(p.life) / float(p.max), 0.0, 1.0)
		var col: Color = p.col
		col.a = p.col.a * a
		draw_circle(p.p, float(p.size) * (0.5 + a * 0.5), col)


func _draw_haze() -> void:
	_grad_v(Rect2(0.0, 0.0, W, 190.0), Color(0.78, 0.80, 0.80, 0.16), Color(0.78, 0.80, 0.80, 0.0))
	_grad_v(Rect2(0.0, H - 150.0, W, 150.0), Color(0.10, 0.11, 0.12, 0.0), Color(0.10, 0.11, 0.12, 0.10))


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
