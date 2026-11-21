class_name Lighting
extends Node2D

# Real 2D light (0.8.0 Stage 2).
#
# Every light in the scene is first collected into one pooled list of sources
# (position, direction, colour, energy, kind). All light effects read that
# list: emissive lamp cores, the bloom buffer, the PointLight2D pool, wet
# reflections, light trails and the fog's in-scattering. One list means a lamp
# can never glow in one effect and be missing in another.
#
# The scene itself is darkened by a CanvasModulate driven by the time of day,
# so at night only what is lit is visible. A fixed pool of PointLight2D nodes
# is handed to the most important lights each frame (player's beams first,
# then by distance to the player); only the nearest N of them cast shadows
# (preset budget). Cars and lamp posts carry pooled LightOccluder2D shapes.

enum { HEAD, TAIL, BRAKE, STREET, SIGNAL, NITRO, SPARK, BEACON }

const TRAIL_STEP := 1.0 / 60.0
# Lamp arm length (art units): long enough that the head hangs over the outer
# lane, so the pool reads as light from above, not from the verge.
const STREET_ARM := 150.0
const TRAIL_POINTS := 14

var game  # Game
var stack  # RenderStack
var params: Dictionary = {}
var glow_tex: Texture2D

# Pooled sources: never reallocated during a race.
var sources: Array = []
var count := 0

# Light requests: one per car (twin-beam cone), per stop-light pair, per lamp.
var _requests: Array = []
var _req_count := 0
var _order: Array = []
var _had_light: Dictionary = {}
var _lp: Dictionary = {}  # scratch lamp points (CarLamps.points)

var canvas_mod: CanvasModulate
var _lights: Array = []        # PointLight2D pool
var _occluders: Array = []     # LightOccluder2D pool
var _occ_used := 0
var _car_poly: OccluderPolygon2D
var _pole_poly: OccluderPolygon2D

var flash := 0.0               # lightning: lights the whole scene for a moment
var ambient := Color.WHITE

# Light trails: road-space history per tracked lamp, keyed by a visual id.
var _trails: Dictionary = {}
var _trail_t := 0.0
var _next_tid := 1

static var _cone_tex: ImageTexture
static var _cone_texs: Array = []
static var _point_tex: ImageTexture
static var _pool_tex: ImageTexture
static var _overhead_tex: ImageTexture


func setup(p_game, p_stack) -> void:
	game = p_game
	stack = p_stack
	name = "Lighting"
	glow_tex = game.glow_tex
	_make_textures()
	canvas_mod = CanvasModulate.new()
	canvas_mod.name = "Ambient"
	# CanvasModulate is a canvas-wide setting; it only needs to live in the
	# game's canvas (layer 0), so the HUD and FX overlay stay unaffected.
	add_child(canvas_mod)
	_car_poly = OccluderPolygon2D.new()
	# Unit box wound TL-TR-BR-BL; counter-clockwise culling keeps the body
	# itself lit and starts the shadow at its far edge.
	_car_poly.polygon = PackedVector2Array([Vector2(-0.5, -0.5), Vector2(0.5, -0.5), Vector2(0.5, 0.5), Vector2(-0.5, 0.5)])
	_car_poly.cull_mode = OccluderPolygon2D.CULL_COUNTER_CLOCKWISE
	_pole_poly = OccluderPolygon2D.new()
	_pole_poly.polygon = PackedVector2Array([Vector2(-4, -4), Vector2(4, -4), Vector2(4, 4), Vector2(-4, 4)])
	_pole_poly.cull_mode = OccluderPolygon2D.CULL_DISABLED
	stack.emissive_painters.append(paint_emissive)
	stack.emissive_painters.append(paint_trails)
	stack.bloom_painters.append(paint_bloom)
	stack.road_glow_painters.append(paint_light_pools)


func apply_params(p: Dictionary) -> void:
	params = p
	var want := int(p.get("lights", 8))
	while _lights.size() < want:
		var l := PointLight2D.new()
		l.blend_mode = Light2D.BLEND_MODE_ADD
		l.range_item_cull_mask = RenderStack.MASK_ROAD | RenderStack.MASK_OBJECTS | RenderStack.MASK_AIR
		l.shadow_item_cull_mask = 1
		l.height = 40.0
		l.enabled = false
		add_child(l)
		_lights.append(l)
	while _lights.size() > want:
		var l: PointLight2D = _lights.pop_back()
		l.queue_free()
	var filt := int(p.get("shadow_filter", 0))
	for l in _lights:
		l.shadow_filter = [Light2D.SHADOW_FILTER_NONE, Light2D.SHADOW_FILTER_PCF5, Light2D.SHADOW_FILTER_PCF13][clampi(filt, 0, 2)]
		l.shadow_filter_smooth = 1.5
	if game != null and game.race_art != null:
		game.race_art.normal_maps = bool(p.get("normal_maps", true))
	if not bool(p.get("trails", true)):
		_trails.clear()


# --- textures ---------------------------------------------------------------

# Lamp offsets (fraction of the texture half-width) of the twin-beam family.
# Each car picks the texture whose two beams start exactly on its own lamps:
# offset = lamp spacing / beam length * 2 (the texture is half as wide as long).
const CONE_SPREADS := [0.10, 0.14, 0.18, 0.22, 0.26, 0.30, 0.34]


static func cone_for(spread: float) -> ImageTexture:
	var best := 0
	for i in range(CONE_SPREADS.size()):
		if absf(float(CONE_SPREADS[i]) - spread) < absf(float(CONE_SPREADS[best]) - spread):
			best = i
	return _cone_texs[best]


# Twin low-beam pattern seen from above. The light node sits at the middle of
# the bumper (bottom centre of the image); the two lamps at +-lamp of the
# half-width throw overlapping cones up the image, with a hot zone just past
# the cutoff and a long soft throw. No hard edges anywhere.
static func _make_cone(lamp_nx: float) -> ImageTexture:
	var w := 128
	var h := 256
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	for y in range(h):
		var v := 1.0 - float(y) / float(h - 1)  # 0 at the bumper, 1 far ahead
		var reach := pow(clampf(1.0 - v, 0.0, 1.0), 1.15)
		var hot := exp(-pow((v - 0.22) / 0.14, 2.0))
		var halfw := 0.05 + 0.58 * pow(v, 0.80)
		for x in range(w):
			var nx := (float(x) / float(w - 1)) * 2.0 - 1.0
			var a := 0.0
			for lamp in [-lamp_nx, lamp_nx]:
				# Beams stay almost parallel: each lights its own side of the lane.
				var d := absf(nx - lamp * (1.0 - v * 0.25)) / halfw
				if d < 1.0:
					var prof := pow(1.0 - d, 0.9)
					a = maxf(a, prof * (0.55 * reach + 0.65 * hot))
			# Spill: a dim wide fan close to the bumper.
			a += 0.12 * exp(-pow(v / 0.18, 2.0)) * clampf(1.0 - absf(nx), 0.0, 1.0)
			# Fade in past the bumper, die out before the far end and never
			# touch the texture's sides, so the beam is never cut off.
			a *= smoothstep(0.0, 0.09, v)
			a *= 1.0 - smoothstep(0.72, 0.98, v)
			a *= 1.0 - smoothstep(0.66, 0.98, absf(nx))
			var c := clampf(a, 0.0, 1.0)
			img.set_pixel(x, y, Color(c, c, c, 1.0))
	return ImageTexture.create_from_image(img)


static func _make_textures() -> void:
	if _cone_tex != null:
		return
	_cone_texs.clear()
	for sp in CONE_SPREADS:
		_cone_texs.append(_make_cone(float(sp)))
	_cone_tex = cone_for(0.14)

	var s := 128
	var pimg := Image.create(s, s, false, Image.FORMAT_RGBA8)
	var pool := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in range(s):
		for x in range(s):
			var d := Vector2(float(x) - 63.5, float(y) - 63.5).length() / 63.5
			var a := clampf(1.0 - d, 0.0, 1.0)
			var p := a * a
			pimg.set_pixel(x, y, Color(p, p, p, 1.0))
			var q := a * a * (3.0 - 2.0 * a)
			pool.set_pixel(x, y, Color(1, 1, 1, q))
	_point_tex = ImageTexture.create_from_image(pimg)
	_pool_tex = ImageTexture.create_from_image(pool)
	# Street-lamp pool seen from above: a bright core under the lamp head, an
	# elliptical pool along the road (1 : 1.4) and a soft wide skirt.
	var oimg := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in range(s):
		for x in range(s):
			var q := Vector2((float(x) - 63.5) / 63.5, (float(y) - 63.5) / 63.5)
			var d := Vector2(q.x, q.y / 1.0).length()
			var e := Vector2(q.x * 1.4, q.y).length()
			var pool_v := pow(clampf(1.0 - e, 0.0, 1.0), 1.6) * 0.75
			var core := pow(clampf(1.0 - d * 2.6, 0.0, 1.0), 2.0) * 0.45
			var skirt := pow(clampf(1.0 - d, 0.0, 1.0), 3.0) * 0.18
			var v := clampf(pool_v + core + skirt, 0.0, 1.0)
			oimg.set_pixel(x, y, Color(v, v, v, 1.0))
	_overhead_tex = ImageTexture.create_from_image(oimg)


# --- source collection ------------------------------------------------------

func _add(kind: int, pos: Vector2, dir: float, col: Color, energy: float, radius: float, owner := -1) -> Dictionary:
	var s: Dictionary
	if count < sources.size():
		s = sources[count]
	else:
		s = {}
		sources.append(s)
	s["kind"] = kind
	s["pos"] = pos
	s["dir"] = dir
	s["col"] = col
	s["energy"] = energy
	s["radius"] = radius
	s["owner"] = owner
	count += 1
	return s


# kind: 0 cone, 1 point. prio higher = more important.
func _request(kind: int, pos: Vector2, rot: float, col: Color, energy: float, size: float, prio: float, shadow_ok: bool, key := -1, spread := 0.14) -> void:
	# Hysteresis: a light that had a PointLight2D last frame keeps it unless
	# something clearly more important needs it, so beams never flicker.
	if key != -1 and _had_light.has(key):
		prio += 120.0
	var r: Dictionary
	if _req_count < _requests.size():
		r = _requests[_req_count]
	else:
		r = {}
		_requests.append(r)
	r["kind"] = kind
	r["pos"] = pos
	r["rot"] = rot
	r["col"] = col
	r["energy"] = energy
	r["size"] = size
	r["prio"] = prio
	r["shadow"] = shadow_ok
	r["key"] = key
	r["spread"] = spread
	_req_count += 1


func headlight_level() -> float:
	return game.get_light_factor()


# Public: other systems (sparks) add short-lived lights through here.
func add_spark_light(pos: Vector2, col: Color, energy: float, radius: float) -> void:
	_add(SPARK, pos, 0.0, col, energy, radius)
	_request(1, pos, 0.0, col, energy, radius, 900.0 + energy, false)


func collect() -> void:
	count = 0
	_req_count = 0
	var g = game
	var light: float = headlight_level()
	var H: float = g.H
	var ref := Vector2(g.player_x, g.player_y)
	# Player. Lamp positions come from the measured anchors of the car's
	# own model (render/car_lamps.gd), rotated with the body yaw.
	if g.running and not g.demo:
		var tilt: float = g.player_tilt
		var sprite: Dictionary = g._race_sprite(g._player_art)
		var box := CarLamps.draw_box(sprite, g.car_w, g.car_h)
		CarLamps.points(CarLamps.anchors(g._player_art, sprite, true), Vector2(g.player_x, g.player_y), box, tilt, _lp)
		var hl: Vector2 = _lp.head[0]
		var hr: Vector2 = _lp.head[1]
		if light > 0.02:
			_add(HEAD, hl, -PI * 0.5 + tilt, Color(1.0, 0.93, 0.80), light, 560.0, -2)
			_add(HEAD, hr, -PI * 0.5 + tilt, Color(1.0, 0.93, 0.80), light, 560.0, -2)
			_request(0, (hl + hr) * 0.5 + Vector2(0.0, -4.0).rotated(tilt), tilt * 0.6, Color(1.0, 0.94, 0.82), 1.35 * light, 620.0, 1000.0, true, -2,
				hl.distance_to(hr) / 620.0 * 2.0)
		var braking: bool = g.braking and not g.overheated
		var tl: Vector2 = _lp.tail[0]
		var tr: Vector2 = _lp.tail[1]
		for tp in [tl, tr]:
			if braking:
				_add(BRAKE, tp, PI * 0.5, Color(1.0, 0.10, 0.05), 1.0, 120.0, -2)
			elif light > 0.02:
				_add(TAIL, tp, PI * 0.5, Color(1.0, 0.12, 0.07), light * 0.6, 70.0, -2)
		if braking:
			_request(1, (tl + tr) * 0.5 + Vector2(0.0, g.car_h * 0.08), 0.0, Color(1.0, 0.12, 0.06), 0.85, 150.0, 800.0, false, -3)
		if g.boosting:
			for tp in [tl, tr]:
				_add(NITRO, tp.lerp((tl + tr) * 0.5, 0.25) + Vector2(0.0, g.car_h * 0.07), PI * 0.5, Color(1.0, 0.55, 0.20), 1.0, 90.0, -2)
			_request(1, (tl + tr) * 0.5 + Vector2(0.0, g.car_h * 0.14), 0.0, Color(1.0, 0.55, 0.22), 0.9, 130.0, 790.0, false, -4)
	# Traffic. Headlights are on from before a car enters the screen; the
	# light pool is shared, and cars without a PointLight2D get an identical
	# looking additive beam (paint_light_pools), so there is no pop-in.
	for i in range(g.cars.size()):
		var c: Dictionary = g.cars[i]
		var cy := float(c.y)
		if cy < -900.0 or cy > H + 260.0:
			continue
		if bool(c.get("rammed", false)):
			continue
		var cx := float(c.x)
		var cw := float(c.w)
		var ch := float(c.h)
		var k := cw / float(g.car_w)
		var dist := Vector2(cx, cy).distance_to(ref)
		var onscreen := cy > -ch and cy < H + ch
		var tid := _tid(c)
		var sprite: Dictionary = g._race_sprite(c)
		CarLamps.points(CarLamps.anchors(c, sprite, false), Vector2(cx, cy), CarLamps.draw_box(sprite, cw, ch), 0.0, _lp)
		var hl: Vector2 = _lp.head[0]
		var hr: Vector2 = _lp.head[1]
		if light > 0.02:
			_add(HEAD, hl, -PI * 0.5, Color(1.0, 0.92, 0.76), light * 0.85, 320.0 * k, i)
			_add(HEAD, hr, -PI * 0.5, Color(1.0, 0.92, 0.76), light * 0.85, 320.0 * k, i)
			_request(0, (hl + hr) * 0.5 + Vector2(0.0, -4.0), 0.0, Color(1.0, 0.92, 0.78), 1.1 * light, 420.0 * k,
				520.0 - dist * 0.18 + (60.0 if onscreen else -120.0), true, tid * 4, hl.distance_to(hr) / (420.0 * k) * 2.0)
		var braking := bool(c.get("braking", false))
		var tl: Vector2 = _lp.tail[0]
		var tr: Vector2 = _lp.tail[1]
		for tp in [tl, tr]:
			if braking:
				_add(BRAKE, tp, PI * 0.5, Color(1.0, 0.10, 0.05), 0.9, 110.0, i)
			elif light > 0.02:
				_add(TAIL, tp, PI * 0.5, Color(1.0, 0.12, 0.07), light * 0.55, 60.0, i)
		if braking and onscreen:
			_request(1, (tl + tr) * 0.5 + Vector2(0.0, ch * 0.07), 0.0, Color(1.0, 0.12, 0.06), 0.7, 120.0 * k, 300.0 - dist * 0.25, false, tid * 4 + 1)
		var sig := int(c.get("signal_dir", 0))
		if sig != 0 and sin(float(g.t) * 22.0) > 0.0:
			var si := 1 if sig > 0 else 0
			_add(SIGNAL, _lp.ind_f[si], 0.0, Color(1.0, 0.62, 0.12), 0.8, 50.0, i)
			_add(SIGNAL, _lp.ind_r[si], 0.0, Color(1.0, 0.62, 0.12), 0.8, 50.0, i)
	# Street lamps.
	var street := light * clampf(1.0 - float(g.blackout_amount), 0.0, 1.0)
	if street > 0.04:
		var period: float = g.DECOR_CYCLE
		for di in g.decor_lamps:
			var d: Dictionary = g.decor[di]
			var base_y := fposmod(float(d.y) + float(g.scroll), period)
			for kk in range(-1, int(ceil(H / period)) + 1):
				var y: float = base_y + float(kk) * period
				if y < -320.0 or y > H + 320.0:
					continue
				var side: float = d.side
				var x: float = (g.road_x - 52.0 - float(d.off)) if side < 0 else (g.road_x + g.road_w + 52.0 + float(d.off))
				var s: float = d.size
				var arm_dir: float = 1.0 if side < 0 else -1.0
				var lamp := Vector2(x + arm_dir * STREET_ARM * 0.9 * s, y)
				var flick := street_flicker(di, float(g.t))
				if flick <= 0.01:
					continue
				var led: bool = (int(di) % 3) == 0
				var col := Color(0.80, 0.88, 1.0) if led else Color(1.0, 0.70, 0.34)
				_add(STREET, lamp, 0.0, col, street * flick, 300.0 * s, di)
				# Overhead lamp: the pool lies right under the head, stretched
				# along the road; no shadows - a lamp above the carriageway does
				# not throw its post or a passing car across the lanes.
				_request(2, lamp, 0.0, col, 1.45 * street * flick, 320.0 * s,
					450.0 - lamp.distance_to(ref) * 0.25, false, 100000 + di * 8 + kk + 1)
	# Road-event beacons (roadworks blinkers, radar posts) as small sources.
	if g.road_event_type == g.EVENT_ROADWORKS and g.closed_lane >= 0:
		var head_y := float(g.road_event.get("head_y", -2000.0))
		var barrier_head := head_y - float(g.road_event.get("taper_len", 440.0))
		var tail_y := barrier_head - float(g.road_event.get("zone_len", 2600.0))
		var inner_x: float = (g.road_x + g.lane_w) if g.closed_lane == 0 else (g.road_x + g.road_w - g.lane_w)
		var blink := 0.4 + 0.6 * (0.5 + 0.5 * sin(float(g.t) * 14.0))
		var by := floorf(maxf(-60.0, tail_y) / 110.0) * 110.0
		while by < minf(H + 60.0, barrier_head):
			if by >= tail_y:
				_add(BEACON, Vector2(inner_x, by + 31.0), 0.0, Color(1.0, 0.62, 0.12), 0.7 * blink, 120.0)
			by += 110.0


# Some lamps flicker and a few are dead. Deterministic per lamp, visual only.
static func street_flicker(index: int, t: float) -> float:
	var h := (index * 2654435761) & 0xFFFF
	var r := float(h) / 65535.0
	if r < 0.08:
		return 0.0  # dead lamp
	if r < 0.18:
		var f := sin(t * 23.0 + r * 50.0) * sin(t * 7.3 + r * 13.0)
		return 0.35 + 0.65 * clampf(f * 3.0 + 0.6, 0.0, 1.0)
	return 1.0


# --- per frame --------------------------------------------------------------

func frame(dt: float) -> void:
	flash = float(game.lightning) * 0.85
	collect()
	_update_ambient()
	_assign_lights()
	_update_occluders()
	_update_trails(dt)


# Ambient = sky colour, pushed much darker at night: the headlights do the rest.
func _update_ambient() -> void:
	var g = game
	var amb: Color = g.get_sky_ambient()
	var night: float = g.get_night_factor()
	var dark := lerpf(1.0, 0.34, night)
	dark *= 1.0 - float(g.blackout_amount) * 0.45
	dark *= 1.0 - float(g.storm_amount) * 0.10
	amb = Color(amb.r * dark, amb.g * dark, amb.b * (dark + night * 0.04), 1.0)
	if flash > 0.0:
		amb = amb.lerp(Color(0.85, 0.90, 1.05), clampf(flash, 0.0, 1.0))
	ambient = amb
	canvas_mod.color = amb


func _assign_lights() -> void:
	_order.resize(_req_count)
	for i in range(_req_count):
		_order[i] = i
	var reqs := _requests
	_order.sort_custom(func(a: int, b: int) -> bool: return float(reqs[a].prio) > float(reqs[b].prio))
	var shadows_left := int(params.get("shadow_lights", 0))
	var n := _lights.size()
	_had_light.clear()
	for li in range(n):
		var l: PointLight2D = _lights[li]
		if li >= _req_count:
			l.enabled = false
			continue
		var r: Dictionary = reqs[_order[li]]
		if int(r.get("key", -1)) != -1:
			_had_light[int(r.key)] = true
		l.enabled = true
		l.position = r.pos
		l.color = r.col
		l.energy = float(r.energy)
		if int(r.kind) == 0:
			var ct := cone_for(float(r.get("spread", 0.14)))
			if l.texture != ct:
				l.texture = ct
			var sc := float(r.size) / 256.0
			l.texture_scale = sc
			l.offset = Vector2(0.0, -128.0 * sc)
			l.rotation = float(r.rot)
			l.height = 240.0
		elif int(r.kind) == 2:
			if l.texture != _overhead_tex:
				l.texture = _overhead_tex
			l.texture_scale = float(r.size) * 2.0 / 128.0
			l.offset = Vector2.ZERO
			l.rotation = 0.0
			l.height = 320.0  # above the road: even diffuse, a tight wet reflection
		else:
			if l.texture != _point_tex:
				l.texture = _point_tex
			l.texture_scale = float(r.size) * 2.0 / 128.0
			l.offset = Vector2.ZERO
			l.rotation = 0.0
			l.height = 170.0
		var sh := bool(r.shadow) and shadows_left > 0
		if sh:
			shadows_left -= 1
		l.shadow_enabled = sh


func _occluder() -> LightOccluder2D:
	var o: LightOccluder2D
	if _occ_used < _occluders.size():
		o = _occluders[_occ_used]
	else:
		o = LightOccluder2D.new()
		o.occluder_light_mask = 1
		add_child(o)
		_occluders.append(o)
	_occ_used += 1
	o.visible = true
	return o


func _update_occluders() -> void:
	_occ_used = 0
	if int(params.get("shadow_lights", 0)) > 0:
		var g = game
		var H: float = g.H
		for c in g.cars:
			var cy := float(c.y)
			if cy < -500.0 or cy > H + 200.0:
				continue
			var o := _occluder()
			o.occluder = _car_poly
			o.position = Vector2(float(c.x), cy)
			o.rotation = float(c.get("ram_rot", 0.0))
			o.scale = Vector2(float(c.w) * 0.84, float(c.h) * 0.90)
		if g.running and not g.demo:
			var o := _occluder()
			o.occluder = _car_poly
			o.position = Vector2(g.player_x, g.player_y)
			o.rotation = g.player_tilt
			o.scale = Vector2(g.car_w * 0.84, g.car_h * 0.90)
		# Lamp posts: their shadows fall across the lanes from the next lamp.
		var period: float = g.DECOR_CYCLE
		for di in g.decor_poles:
			var d: Dictionary = g.decor[di]
			var base_y := fposmod(float(d.y) + float(g.scroll), period)
			for kk in range(-1, int(ceil(H / period)) + 1):
				var y: float = base_y + float(kk) * period
				if y < -200.0 or y > H + 200.0:
					continue
				var side: float = d.side
				var x: float = (g.road_x - 52.0 - float(d.off)) if side < 0 else (g.road_x + g.road_w + 52.0 + float(d.off))
				var o := _occluder()
				o.occluder = _pole_poly
				o.position = Vector2(x, y)
				o.rotation = 0.0
				o.scale = Vector2.ONE
	for i in range(_occ_used, _occluders.size()):
		_occluders[i].visible = false


# --- light trails ------------------------------------------------------------

func _tid(c: Dictionary) -> int:
	if not c.has("_tid"):
		c["_tid"] = _next_tid
		_next_tid += 1
	return int(c["_tid"])


# Each trail stores road coordinates (y - scroll), so the light smears along
# the road behind the car exactly as fast as the car moves relative to it: a
# long-exposure photo of the motorway.
func _update_trails(dt: float) -> void:
	var g = game
	var light: float = headlight_level()
	if not bool(params.get("trails", true)) or light < 0.15:
		if not _trails.is_empty():
			_trails.clear()
		return
	_trail_t += dt
	if _trail_t < TRAIL_STEP:
		return
	_trail_t = fmod(_trail_t, TRAIL_STEP)
	var scroll: float = g.scroll
	var seen := {}
	var maxp := TRAIL_POINTS * (2 if g.boosting else 1)
	if g.running and not g.demo:
		for side in [-1.0, 1.0]:
			_push_trail(-10 - int(side), Vector2(g.player_x + side * g.car_w * 0.29, g.player_y + g.car_h * 0.47), scroll, seen, maxp, 1)
			_push_trail(-20 - int(side), Vector2(g.player_x + side * g.car_w * 0.27, g.player_y - g.car_h * 0.46), scroll, seen, maxp, 0, g.car_h)
	for c in g.cars:
		var cy := float(c.y)
		if cy < -200.0 or cy > g.H + 200.0 or bool(c.get("rammed", false)):
			continue
		var id := _tid(c)
		for side in [-1.0, 1.0]:
			var x: float = float(c.x) + side * float(c.w) * 0.29
			_push_trail(id * 4 + (0 if side < 0.0 else 1), Vector2(x, cy + float(c.h) * 0.47), scroll, seen, TRAIL_POINTS, 1)
			_push_trail(id * 4 + (2 if side < 0.0 else 3), Vector2(x, cy - float(c.h) * 0.46), scroll, seen, TRAIL_POINTS, 0, float(c.h))
	for key in _trails.keys():
		if not seen.has(key):
			_trails.erase(key)


# clear: a headlight trail would smear back across its own car, so the
# white streak only shows where it has left the body (clear = body length).
func _push_trail(key: int, p: Vector2, scroll: float, seen: Dictionary, maxp: int, kind: int, clear := 0.0) -> void:
	seen[key] = true
	var tr: Dictionary = _trails.get(key, {})
	if tr.is_empty():
		tr = {"pts": PackedVector2Array(), "kind": kind, "clear": clear}
		_trails[key] = tr
	var pts: PackedVector2Array = tr.pts
	pts.append(Vector2(p.x, p.y - scroll))
	while pts.size() > maxp:
		pts.remove_at(0)
	tr["pts"] = pts


func paint_trails(ci: CanvasItem) -> void:
	if _trails.is_empty():
		return
	var g = game
	var scroll: float = g.scroll
	var light: float = headlight_level()
	var boost := 1.6 if g.boosting else 1.0
	for key in _trails:
		var tr: Dictionary = _trails[key]
		var pts: PackedVector2Array = tr.pts
		var n := pts.size()
		if n < 3:
			continue
		var line := PackedVector2Array()
		var cols := PackedColorArray()
		line.resize(n)
		cols.resize(n)
		var red := int(tr.kind) == 1
		var clear := float(tr.get("clear", 0.0))
		var head_y := pts[n - 1].y + scroll
		for i in range(n):
			var k := float(i) / float(n - 1)  # 0 oldest, 1 at the lamp
			line[i] = Vector2(pts[i].x, pts[i].y + scroll)
			var a := k * k * 0.55 * light * boost
			if clear > 0.0:
				a = 0.4 * light * boost * (1.0 - k) * clampf((line[i].y - head_y - clear) / 40.0, 0.0, 1.0)
			cols[i] = Color(a, a * 0.10, a * 0.06, 1.0) if red else Color(a * 0.85, a * 0.80, a * 0.68, 1.0)
		var length := line[0].distance_to(line[n - 1])
		if length < 12.0:
			continue
		ci.draw_polyline_colors(line, cols, 5.0 if red else 3.5, true)


# --- painters ---------------------------------------------------------------

func _bulb(ci: CanvasItem, pos: Vector2, r: float, col: Color, a: float) -> void:
	if a <= 0.004:
		return
	ci.draw_texture_rect(glow_tex, Rect2(pos - Vector2(r, r), Vector2(r, r) * 2.0), false,
		Color(col.r * a, col.g * a, col.b * a, 1.0))


# Lamp cores over the cars. Small and hot; the halo comes from bloom.
func paint_emissive(ci: CanvasItem) -> void:
	for i in range(count):
		var s: Dictionary = sources[i]
		var e := float(s.energy)
		var col: Color = s.col
		var p: Vector2 = s.pos
		match int(s.kind):
			HEAD:
				_bulb(ci, p, 16.0, col, 0.55 * e)
				_bulb(ci, p, 6.0, Color(1, 1, 1), 0.9 * e)
			TAIL:
				_bulb(ci, p, 12.0, col, 0.55 * e)
			BRAKE:
				_bulb(ci, p, 16.0, col, 0.75 * e)
				_bulb(ci, p, 6.0, Color(1.0, 0.45, 0.35), 0.9 * e)
			STREET:
				_bulb(ci, p, 22.0, col, 0.55 * e)
				_bulb(ci, p, 8.0, Color(1, 1, 1), 0.85 * e)
			SIGNAL:
				_bulb(ci, p, 12.0, col, 0.9 * e)
			NITRO:
				_bulb(ci, p, 18.0, col, 0.7 * e)
			SPARK, BEACON:
				_bulb(ci, p, maxf(4.0, float(s.radius) * 0.12), col, e)


func paint_bloom(ci: CanvasItem) -> void:
	for i in range(count):
		var s: Dictionary = sources[i]
		var e := float(s.energy)
		var col: Color = s.col
		var p: Vector2 = s.pos
		match int(s.kind):
			HEAD:
				_bulb(ci, p, 34.0, col, 0.7 * e)
			TAIL:
				_bulb(ci, p, 24.0, col, 0.5 * e)
			BRAKE:
				_bulb(ci, p, 34.0, col, 0.8 * e)
			STREET:
				_bulb(ci, p, 40.0, col, 0.6 * e)
			SIGNAL:
				_bulb(ci, p, 26.0, col, 0.7 * e)
			NITRO:
				_bulb(ci, p, 40.0, col, 0.8 * e)
			SPARK, BEACON:
				_bulb(ci, p, maxf(10.0, float(s.radius) * 0.3), col, 0.8 * e)


# Low preset fallback: lights that did not get a PointLight2D still leave a
# faint pool on the road (additive), so a distant car is never unlit.
func paint_light_pools(ci: CanvasItem) -> void:
	var assigned := mini(_lights.size(), _req_count)
	if _req_count <= assigned:
		return
	# Same texture, size and placement as the PointLight2D it stands in for,
	# scaled to what that light would add to asphalt of ~0.28 albedo, so a
	# light moving between the pool and this fallback does not visibly change.
	var albedo := 0.28 * (1.0 - float(game.wetness) * 0.25)
	for oi in range(assigned, _req_count):
		var r: Dictionary = _requests[_order[oi]]
		var e := float(r.energy) * albedo
		var col: Color = r.col
		var tint := Color(col.r * e, col.g * e, col.b * e, 1.0)
		var sz := float(r.size)
		var p: Vector2 = r.pos
		match int(r.kind):
			0:
				var sc := sz / 256.0
				ci.draw_set_transform(p, float(r.rot), Vector2.ONE)
				ci.draw_texture_rect(cone_for(float(r.get("spread", 0.14))), Rect2(-64.0 * sc, -256.0 * sc, 128.0 * sc, 256.0 * sc), false, tint)
				ci.draw_set_transform(Vector2.ZERO)
			2:
				ci.draw_texture_rect(_overhead_tex, Rect2(p - Vector2(sz, sz), Vector2(sz, sz) * 2.0), false, tint)
			_:
				ci.draw_texture_rect(_point_tex, Rect2(p - Vector2(sz, sz), Vector2(sz, sz) * 2.0), false, tint)
