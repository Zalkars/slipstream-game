class_name Lighting
extends Node2D

# Every light in the scene is first collected into one list of sources
# (position, direction, colour, energy, kind). All light effects read that
# list: the emissive lamps, the bloom buffer, and in later stages the
# PointLight2D pool, wet reflections, light trails and fog scattering. One
# list means a lamp can never glow in one effect and be missing in another.

enum { HEAD, TAIL, BRAKE, STREET, SIGNAL, NITRO, SPARK, BEACON }

var game  # Game
var stack  # RenderStack
var params: Dictionary = {}
var glow_tex: Texture2D

# Pooled sources: never reallocated during a race.
var sources: Array = []
var count := 0


func setup(p_game, p_stack) -> void:
	game = p_game
	stack = p_stack
	name = "Lighting"
	glow_tex = game.glow_tex
	stack.emissive_painters.append(paint_emissive)
	stack.bloom_painters.append(paint_bloom)


func apply_params(p: Dictionary) -> void:
	params = p


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


func headlight_level() -> float:
	return game.get_light_factor()


func collect() -> void:
	count = 0
	var g = game
	var light: float = headlight_level()
	var W: float = g.W
	var H: float = g.H
	# Player.
	if g.running and not g.demo:
		var px: float = g.player_x
		var py: float = g.player_y
		var cw: float = g.car_w
		var ch: float = g.car_h
		var tilt: float = g.player_tilt
		if light > 0.02:
			for side in [-1.0, 1.0]:
				var lp := Vector2(px + side * cw * 0.27, py - ch * 0.47).rotated(0.0)
				_add(HEAD, lp, -PI * 0.5 + tilt * 0.6 + side * 0.03, Color(1.0, 0.93, 0.80), light, 560.0, -2)
		var braking: bool = g.braking and not g.overheated
		for side in [-1.0, 1.0]:
			var tp := Vector2(px + side * cw * 0.29, py + ch * 0.465)
			if braking:
				_add(BRAKE, tp, PI * 0.5, Color(1.0, 0.10, 0.05), 1.0, 120.0, -2)
			elif light > 0.02:
				_add(TAIL, tp, PI * 0.5, Color(1.0, 0.12, 0.07), light * 0.6, 70.0, -2)
		if g.boosting:
			for side in [-1.0, 1.0]:
				_add(NITRO, Vector2(px + side * cw * 0.23, py + ch * 0.55), PI * 0.5, Color(1.0, 0.55, 0.20), 1.0, 90.0, -2)
	# Traffic.
	for i in range(g.cars.size()):
		var c: Dictionary = g.cars[i]
		var cy := float(c.y)
		if cy < -700.0 or cy > H + 260.0:
			continue
		var cx := float(c.x)
		var cw := float(c.w)
		var ch := float(c.h)
		if bool(c.get("rammed", false)):
			continue
		if light > 0.02:
			for side in [-1.0, 1.0]:
				_add(HEAD, Vector2(cx + side * cw * 0.27, cy - ch * 0.47), -PI * 0.5, Color(1.0, 0.92, 0.76), light * 0.85, 320.0 * cw / g.car_w, i)
		var braking := bool(c.get("braking", false))
		for side in [-1.0, 1.0]:
			var tp := Vector2(cx + side * cw * 0.29, cy + ch * 0.465)
			if braking:
				_add(BRAKE, tp, PI * 0.5, Color(1.0, 0.10, 0.05), 0.9, 110.0, i)
			elif light > 0.02:
				_add(TAIL, tp, PI * 0.5, Color(1.0, 0.12, 0.07), light * 0.55, 60.0, i)
		var sig := int(c.get("signal_dir", 0))
		if sig != 0 and sin(float(g.t) * 22.0) > 0.0:
			for end_y in [-ch * 0.42, ch * 0.42]:
				_add(SIGNAL, Vector2(cx + float(sig) * cw * 0.44, cy + end_y), 0.0, Color(1.0, 0.62, 0.12), 0.8, 50.0, i)
	# Street lamps.
	var street := light * clampf(1.0 - float(g.blackout_amount), 0.0, 1.0)
	if street > 0.04:
		var period: float = g.DECOR_CYCLE
		for di in range(g.decor.size()):
			var d: Dictionary = g.decor[di]
			if int(d.kind) != 2:
				continue
			var base_y := fposmod(float(d.y) + float(g.scroll), period)
			for k in range(-1, int(ceil(H / period)) + 1):
				var y: float = base_y + float(k) * period
				if y < -320.0 or y > H + 320.0:
					continue
				var side: float = d.side
				var x: float = (g.road_x - 52.0 - float(d.off)) if side < 0 else (g.road_x + g.road_w + 52.0 + float(d.off))
				var s: float = d.size
				var arm_dir: float = 1.0 if side < 0 else -1.0
				var lamp := Vector2(x + arm_dir * 92.0 * 0.9 * s, y)
				var flick := street_flicker(di, float(g.t))
				if flick <= 0.01:
					continue
				var led := (di % 3) == 0
				var col := Color(0.82, 0.90, 1.0) if led else Color(1.0, 0.72, 0.36)
				_add(STREET, lamp, 0.0, col, street * flick, 300.0 * s, di)


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


func frame(_dt: float) -> void:
	collect()


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
				_bulb(ci, p, float(s.radius) * 0.12, col, e)


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
				_bulb(ci, p, float(s.radius) * 0.3, col, 0.8 * e)
