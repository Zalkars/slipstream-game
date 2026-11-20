class_name ContactFx
extends RefCounted

# Contact with the road and between cars (0.8.0 Stage 6). Visual only: own
# RNG, reads Game state, never writes simulation state.
#
# Sparks: physical particles thrown along the tangent of an impact, sliding on
#   the asphalt with friction, bouncing off the guard rails, cooling from
#   white-yellow to orange to dark red; long continuous streams while a body
#   scrapes along another car; one or two pooled lights per burst (preset);
#   on a wet road they die faster. Each spark that comes to rest scorches the
#   road buffer.
# Tyre marks: per wheel, intensity from slip (braking against the grip, a
#   quick lane change swinging the rear axle, a nitro launch). Dry: dark rubber
#   with a tread pattern; wet: lighter tracks where the tyre squeezed the water
#   away; after a puddle, wet footprints on dry asphalt. All baked once into
#   the road buffer. Hard dry braking also smokes.

const WHEELS := [Vector2(-0.31, -0.30), Vector2(0.31, -0.30), Vector2(-0.31, 0.32), Vector2(0.31, 0.32)]

var game  # Game
var stack  # RenderStack
var params: Dictionary = {}
var rng := RandomNumberGenerator.new()

var sparks: Array = []   # {p, v, temp, life, wet}
var smoke: Array = []    # {p, v, life, max, size}
var _bursts: Array = []  # {p, life, energy}
var _prev_wheels: Array = []
var _prev_scroll := 0.0
var _prev_x := 0.0
var _have_prev := false
var _was_crashed := false
var _wet_feet := 0.0
var _scrape_t := 0.0
var _launch_t := 0.0
var _was_boosting := false

static var _tread_tex: ImageTexture


func setup(p_game, p_stack) -> void:
	game = p_game
	stack = p_stack
	rng.seed = 5150
	_make_tread()
	stack.emissive_painters.append(paint_sparks)
	stack.bloom_painters.append(paint_spark_bloom)
	stack.particle_painters.append(paint_smoke)


func apply_params(p: Dictionary) -> void:
	params = p


static func _make_tread() -> void:
	if _tread_tex != null:
		return
	# 16x32 tread strip: chevron blocks; repeats along the road.
	var img := Image.create(16, 32, false, Image.FORMAT_RGBA8)
	for y in range(32):
		for x in range(16):
			var cx := absf(float(x) - 7.5) / 7.5
			var groove := fposmod(float(y) + cx * 6.0, 8.0) < 2.0
			var edge := cx > 0.86
			var a := 0.25 if groove else (0.75 if edge else 1.0)
			img.set_pixel(x, y, Color(1, 1, 1, a))
	_tread_tex = ImageTexture.create_from_image(img)


# --- public hooks (called by Game at impacts) ---------------------------------

# pos: contact point, dir: main direction of the debris, strength 0..1+.
func spark_burst(pos: Vector2, dir: Vector2, strength: float) -> void:
	var cap := int(params.get("max_sparks", 120))
	var wet: float = game.wetness
	var n := int(lerpf(10.0, 46.0, clampf(strength, 0.0, 1.5) / 1.5))
	var d := dir.normalized() if dir.length_squared() > 0.001 else Vector2.UP
	for i in range(n):
		if sparks.size() >= cap:
			sparks.pop_front()
		var ang := rng.randf_range(-0.9, 0.9)
		var spd := rng.randf_range(220.0, 760.0) * (0.6 + strength * 0.5)
		sparks.append({"p": pos + Vector2(rng.randf_range(-6, 6), rng.randf_range(-6, 6)),
			"v": d.rotated(ang) * spd + Vector2(0.0, rng.randf_range(-80.0, 80.0)),
			"temp": rng.randf_range(0.85, 1.0), "life": rng.randf_range(0.35, 0.9), "wet": wet})
	if int(params.get("spark_lights", 1)) > 0:
		_bursts.append({"p": pos, "life": 0.28, "energy": clampf(0.6 + strength * 0.6, 0.4, 1.3)})
		while _bursts.size() > int(params.get("spark_lights", 1)):
			_bursts.pop_front()


# --- per frame --------------------------------------------------------------

func frame(dt: float) -> void:
	var g = game
	if g.crashed and not _was_crashed:
		spark_burst(Vector2(g.player_x, g.player_y - g.car_h * 0.3), Vector2(rng.randf_range(-1, 1), -1), 1.4)
	_was_crashed = g.crashed
	_update_scrape(dt)
	_update_sparks(dt)
	_update_marks(dt)
	_update_smoke(dt)
	var lit = g.lighting_fx
	for i in range(_bursts.size() - 1, -1, -1):
		var b: Dictionary = _bursts[i]
		b.life -= dt
		if b.life <= 0.0:
			_bursts.remove_at(i)
			continue
		if lit != null:
			# Weak, flickering light on the asphalt and the bodywork; no flash.
			var e: float = float(b.energy) * (float(b.life) / 0.28) * (0.7 + 0.3 * rng.randf())
			lit.add_spark_light(b.p, Color(1.0, 0.72, 0.36), e, 150.0)


# Bodies brushing past: the sprites overlap although the (smaller) hitboxes do
# not. Visual only - a continuous stream of sparks along the contact line.
func _update_scrape(dt: float) -> void:
	var g = game
	if not g.running or g.crashed:
		return
	for c in g.cars:
		var dx := float(c.x) - float(g.player_x)
		var dy := float(c.y) - float(g.player_y)
		var reach_x := (float(c.w) + float(g.car_w)) * 0.5 * 0.94
		var reach_y := (float(c.h) + float(g.car_h)) * 0.5 * 0.85
		if absf(dx) < reach_x and absf(dx) > reach_x * 0.80 and absf(dy) < reach_y:
			_scrape_t += dt
			if _scrape_t > 1.0 / 45.0:
				_scrape_t = 0.0
				var side := signf(dx)
				var p := Vector2(g.player_x + side * g.car_w * 0.47, g.player_y + clampf(dy, -g.car_h * 0.4, g.car_h * 0.4))
				spark_burst(p, Vector2(-side * 0.3, 1.0), 0.25)
			return


func _update_sparks(dt: float) -> void:
	var g = game
	var rail_l: float = g.road_x - 39.0
	var rail_r: float = g.road_x + g.road_w + 33.0
	var travel: float = (g.speed if g.running else 0.0) * dt
	var scroll: float = g.scroll
	for i in range(sparks.size() - 1, -1, -1):
		var s: Dictionary = sparks[i]
		var wet := float(s.wet)
		s.life -= dt * (1.0 + wet * 1.4)
		# Cooling: radiates fast while white-hot, slower once dull red.
		s.temp = float(s.temp) - dt * (1.1 + wet * 2.2) * (0.5 + float(s.temp))
		if s.life <= 0.0 or s.temp <= 0.02:
			if rng.randf() < 0.35:
				stack.road_buffer.dot(s.p, rng.randf_range(0.8, 1.8), Color(0.10, 0.09, 0.08, 0.35), scroll)
			sparks.remove_at(i)
			continue
		var v: Vector2 = s.v
		# Sliding friction on the asphalt, plus the road carrying it away.
		v *= exp(-dt * 2.6)
		s.p += v * dt + Vector2(0.0, travel)
		if s.p.x < rail_l or s.p.x > rail_r:
			s.p.x = clampf(s.p.x, rail_l, rail_r)
			v.x = -v.x * 0.45
			v.y *= 0.7
		s.v = v


func _spark_color(temp: float) -> Color:
	# Black-body-ish ramp: white-yellow -> orange -> dark red.
	if temp > 0.7:
		return Color(1.0, 0.95, 0.70).lerp(Color(1.0, 1.0, 0.95), (temp - 0.7) / 0.3)
	if temp > 0.35:
		return Color(1.0, 0.55, 0.15).lerp(Color(1.0, 0.95, 0.70), (temp - 0.35) / 0.35)
	return Color(0.45, 0.06, 0.02).lerp(Color(1.0, 0.55, 0.15), temp / 0.35)


func paint_sparks(ci: CanvasItem) -> void:
	for s in sparks:
		var t := float(s.temp)
		var c := _spark_color(t)
		var e := clampf(t * 1.4, 0.0, 1.0)
		var v: Vector2 = s.v
		var tail: Vector2 = v * 0.022
		ci.draw_line(s.p - tail, s.p, Color(c.r * e, c.g * e, c.b * e, 1.0), 1.6 + t * 1.2, true)


func paint_spark_bloom(ci: CanvasItem) -> void:
	for s in sparks:
		var t := float(s.temp)
		if t < 0.45:
			continue
		var c := _spark_color(t)
		ci.draw_circle(s.p, 3.0 + t * 3.0, Color(c.r * t, c.g * t, c.b * t, 1.0))


# --- tyre marks -------------------------------------------------------------

func _wheel_pos(i: int) -> Vector2:
	var g = game
	var w: Vector2 = WHEELS[i]
	var local := Vector2(w.x * g.car_w, w.y * g.car_h).rotated(g.player_tilt)
	return Vector2(g.player_x, g.player_y) + local


func _update_marks(dt: float) -> void:
	var g = game
	if not g.running or g.crashed or g.demo:
		_have_prev = false
		return
	var scroll: float = g.scroll
	var travel := scroll - _prev_scroll
	var lat_v: float = (g.player_x - _prev_x) / maxf(dt, 0.0001) if _have_prev else 0.0
	if g.boosting and not _was_boosting:
		_launch_t = 0.35
	_was_boosting = g.boosting
	_launch_t = maxf(0.0, _launch_t - dt)
	var mu: float = g.grip_mu
	var wet: float = g.wetness
	if g.puddle_depth > 0.2:
		_wet_feet = 1.6
	_wet_feet = maxf(0.0, _wet_feet - dt)
	var braking: bool = g.braking and not g.overheated and g.speed > 130.0
	# Slip per wheel: braking loads the front; a quick lane change swings the
	# rear axle out (more on a slippery road); a nitro launch spins the rears.
	var brake_slip := 0.0
	if braking:
		brake_slip = clampf(g.speed / maxf(1.0, g.top_speed), 0.3, 1.0) * (1.25 - mu * 0.4)
	var swing := clampf(absf(lat_v) / 900.0, 0.0, 1.0) * (1.6 - mu)
	if swing < 0.18:
		swing = 0.0
	var launch := _launch_t / 0.35
	if _have_prev and travel > 0.5:
		for i in range(4):
			var rear := i >= 2
			var slip_amt := brake_slip * (1.0 if not rear else 0.8)
			if rear:
				slip_amt = maxf(slip_amt, maxf(swing, launch))
			var a: Vector2 = _prev_wheels[i] + Vector2(0.0, travel)
			var b := _wheel_pos(i)
			if slip_amt > 0.05:
				if wet > 0.35:
					# The tyre squeezes the water film away: a lighter track.
					stack.road_buffer.line(a, b, g.car_w * 0.13, Color(0.62, 0.66, 0.70, 0.16 * slip_amt * wet), scroll)
				else:
					stack.road_buffer.ribbon(a, b, g.car_w * 0.15, Color(0.035, 0.035, 0.04, 0.42 * slip_amt), _tread_tex, scroll)
			elif _wet_feet > 0.0 and wet < 0.6:
				# Wet footprints after a puddle, fading as the tyres dry.
				stack.road_buffer.line(a, b, g.car_w * 0.12, Color(0.05, 0.07, 0.09, 0.22 * (_wet_feet / 1.6)), scroll)
		if braking and wet < 0.3 and brake_slip > 0.55 and int(params.get("level", 1)) >= 1:
			for i in range(2):
				if rng.randf() < dt * 22.0:
					var wp := _wheel_pos(2 + i)
					smoke.append({"p": wp, "v": Vector2(rng.randf_range(-20, 20), rng.randf_range(40, 120)),
						"life": 0.9, "max": 0.9, "size": rng.randf_range(10.0, 18.0)})
	for i in range(4):
		if _prev_wheels.size() < 4:
			_prev_wheels.append(Vector2.ZERO)
		_prev_wheels[i] = _wheel_pos(i)
	_prev_scroll = scroll
	_prev_x = g.player_x
	_have_prev = true


func _update_smoke(dt: float) -> void:
	var travel: float = (game.speed if game.running else 0.0) * dt
	for i in range(smoke.size() - 1, -1, -1):
		var m: Dictionary = smoke[i]
		m.life -= dt
		if m.life <= 0.0:
			smoke.remove_at(i)
			continue
		m.p += m.v * dt + Vector2(0.0, travel * 0.35)
		m.v *= exp(-dt * 1.5)
	while smoke.size() > 60:
		smoke.pop_front()


func paint_smoke(ci: CanvasItem) -> void:
	var tex: Texture2D = game.glow_tex
	for m in smoke:
		var k: float = float(m.life) / float(m.max)
		var r: float = float(m.size) * (2.4 - k * 1.4)
		ci.draw_texture_rect(tex, Rect2(m.p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(0.82, 0.83, 0.84, 0.22 * k))
