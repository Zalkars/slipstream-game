class_name Art
extends RefCounted

# Procedural art helpers. Everything is drawn from primitives, no image assets.

static var _cache: Dictionary = {}


static func _sb(color: Color, radius: int, border_color: Color, border_w: int) -> StyleBoxFlat:
	var key := color.to_html(true) + "|" + str(radius) + "|" + border_color.to_html(true) + "|" + str(border_w)
	var hit: StyleBoxFlat = _cache.get(key)
	if hit != null:
		return hit
	var s := StyleBoxFlat.new()
	s.bg_color = color
	s.corner_radius_top_left = radius
	s.corner_radius_top_right = radius
	s.corner_radius_bottom_left = radius
	s.corner_radius_bottom_right = radius
	if border_w > 0:
		s.border_width_left = border_w
		s.border_width_right = border_w
		s.border_width_top = border_w
		s.border_width_bottom = border_w
		s.border_color = border_color
	s.anti_aliasing = true
	s.anti_aliasing_size = 0.7
	_cache[key] = s
	return s


static func rr(ci: CanvasItem, rect: Rect2, color: Color, radius := 0.0, border_color := Color(0, 0, 0, 0), border_w := 0) -> void:
	if rect.size.x <= 0.5 or rect.size.y <= 0.5:
		return
	ci.draw_style_box(_sb(color, int(max(0.0, radius)), border_color, border_w), rect)


static func soft_shadow(ci: CanvasItem, rect: Rect2, radius: float, strength := 0.22) -> void:
	var o := Vector2(rect.size.x * 0.05, rect.size.y * 0.035)
	rr(ci, Rect2(rect.position + o, rect.size), Color(0, 0, 0, strength * 0.45), radius)
	rr(ci, Rect2(rect.position + o * 0.6, rect.size * Vector2(0.98, 0.985)), Color(0, 0, 0, strength * 0.55), radius)


# --- cars -------------------------------------------------------------------

static func traffic(ci: CanvasItem, center: Vector2, w: float, h: float, kind: int, body: Color, opts := {}) -> void:
	match kind:
		2:
			truck(ci, center, w, h, body, opts.get("trailer", Color(0.78, 0.79, 0.79)), opts)
		3:
			van(ci, center, w, h, body, opts)
		4:
			bus(ci, center, w, h, body, opts)
		6:
			pickup(ci, center, w, h, body, opts)
		_:
			car(ci, center, w, h, body, opts)


# --- car silhouettes --------------------------------------------------------
#
# One procedural body, five genuinely different cars. Everything that used to
# be a magic number inside car() is now a per-car profile (Plan_0.5.0.md,
# stage 1): HATCH and HYPER differ in proportion and cabin shape, not in paint.
#
# Every point is a Vector2(t, hw): t runs from the nose (0, top of the rect) to
# the boot (1, bottom) and hw is the half-width as a share of w. A Vector3 is
# three half-widths sampled at t = 0, 0.5 and 1.
#
#   side       half-width down the flank     (mirrored, so the car stays symmetric)
#   nose       how rounded the nose is       (0 = square, 1 = pointed)
#   tail       how rounded the boot is
#   cabin      outline of the greenhouse: t0/hw0 at the windscreen base,
#              t1/hw1 at its top, t2/hw2 at the rear window base
#   track      wheel width as a share of the body width
#   stance     how far the wheels stick out past the body
#   wheelbase  front/rear axle positions as a share of h
#   mirrors    whether the mirrors stick out (they add width to the silhouette)
#
# Geometry contract: "nose" is the top of the rect (negative Y) and the boot
# the bottom, because the player car drives up the screen.
static var _silhouettes: Dictionary = {}


static func silhouette(name: String) -> Dictionary:
	if _silhouettes.is_empty():
		_silhouettes = {
			# City hatch: tall, narrow, boxy nose, cabin almost the whole length.
			# City hatch: one-box silhouette — tall cabin, glass to all four
			# corners, near-vertical tailgate, upright and narrow.
			"hatch": {
				"side": [Vector2(0.00, 0.90), Vector2(0.04, 0.95), Vector2(0.12, 0.96),
					Vector2(0.44, 0.97), Vector2(0.80, 0.96), Vector2(0.94, 0.93), Vector2(1.00, 0.90)],
				"nose": 0.0, "tail": 0.0,
				"cabin": Vector3(0.10, 0.44, 0.90), "glass_w0": 0.64, "roof_w": 0.52,
				"track": 0.150, "stance": 0.02, "wheelbase": Vector2(0.17, 0.63), "mirrors": false,
				"length": 0.94,
			},
			# Classic three-box GT: long bonnet, upright cabin set back, long boot.
			"sedan": {
				"side": [Vector2(0.00, 0.80), Vector2(0.05, 0.89), Vector2(0.14, 0.93),
					Vector2(0.40, 0.94), Vector2(0.70, 0.93), Vector2(0.90, 0.88), Vector2(1.00, 0.80)],
				"nose": 0.20, "tail": 0.20,
				"cabin": Vector3(0.28, 0.52, 0.66), "glass_w0": 0.46, "roof_w": 0.30,
				"track": 0.148, "stance": 0.02, "wheelbase": Vector2(0.15, 0.67), "mirrors": true,
				"length": 1.00,
			},
			# Muscle: short cabin far back, slab sides, wide square haunches.
			"muscle": {
				"side": [Vector2(0.00, 0.93), Vector2(0.03, 0.96), Vector2(0.10, 0.95),
					Vector2(0.36, 0.92), Vector2(0.60, 0.95), Vector2(0.84, 1.00), Vector2(1.00, 1.00)],
				"nose": 0.0, "tail": 0.0,
				"cabin": Vector3(0.38, 0.60, 0.84), "glass_w0": 0.58, "roof_w": 0.52,
				"track": 0.168, "stance": 0.05, "wheelbase": Vector2(0.16, 0.65), "mirrors": true,
				"length": 0.97,
			},
			# Mid-engine wedge: needle nose, cabin forward, pinched waist.
			"sport": {
				"side": [Vector2(0.00, 0.30), Vector2(0.04, 0.50), Vector2(0.12, 0.74),
					Vector2(0.30, 0.80), Vector2(0.52, 0.78), Vector2(0.78, 0.96), Vector2(1.00, 0.90)],
				"nose": 0.85, "tail": 0.30,
				"cabin": Vector3(0.22, 0.50, 0.73), "glass_w0": 0.40, "roof_w": 0.24,
				"track": 0.160, "stance": 0.04, "wheelbase": Vector2(0.17, 0.70), "mirrors": true,
				"length": 1.06,
			},
			# Hypercar: dagger nose, cockpit far forward, arrow tail.
			"hyper": {
				"side": [Vector2(0.00, 0.18), Vector2(0.03, 0.40), Vector2(0.10, 0.62),
					Vector2(0.28, 0.76), Vector2(0.48, 0.80), Vector2(0.70, 1.00), Vector2(1.00, 0.22)],
				"nose": 0.94, "tail": 0.90,
				"cabin": Vector3(0.26, 0.50, 0.68), "glass_w0": 0.40, "roof_w": 0.22,
				"track": 0.172, "stance": 0.06, "wheelbase": Vector2(0.18, 0.72), "mirrors": true,
				"length": 1.03,
			},
		}
	return _silhouettes.get(name, _silhouettes["sedan"])


# Half-width of the flank at any point down the car, linearly interpolated.
static func _side_at(side: Array, t: float) -> float:
	if t <= 0.0:
		return (side[0] as Vector2).y
	for i in range(1, side.size()):
		var b: Vector2 = side[i]
		if t <= b.x:
			var a: Vector2 = side[i - 1]
			var k := (t - a.x) / maxf(b.x - a.x, 0.0001)
			return lerpf(a.y, b.y, k)
	return (side[side.size() - 1] as Vector2).y


# Body outline: flanks from the profile plus rounded nose and boot, mirrored.
static func _body_points(r: Rect2, pr: Dictionary) -> PackedVector2Array:
	var side: Array = pr.side
	var cx := r.get_center().x
	var hw := r.size.x * 0.5
	var pts := PackedVector2Array()
	var nose_round: float = float(pr.nose)
	var tail_round: float = float(pr.tail)
	# left flank, nose to boot
	for p in side:
		var v: Vector2 = p
		pts.append(Vector2(cx - hw * v.y, r.position.y + r.size.y * v.x))
	# boot: a shallow arc that rounds or squares the tail
	var tail_w := hw * (side[side.size() - 1] as Vector2).y
	var tail_c := Vector2(cx, r.end.y)
	for i in range(1, 5):
		var a := PI * (0.5 + 0.5 * float(i) / 5.0)
		pts.append(Vector2(tail_c.x + cos(a + PI) * -tail_w, tail_c.y - sin(a) * r.size.y * 0.03 * (1.0 - tail_round)))
	# right flank, boot to nose
	for i in range(side.size() - 1, -1, -1):
		var v: Vector2 = side[i]
		pts.append(Vector2(cx + hw * v.y, r.position.y + r.size.y * v.x))
	# nose: the pointed end, so HYPER reads as a dagger and MUSCLE as a slab
	var nose_w := hw * (side[0] as Vector2).y
	var nose_c := Vector2(cx, r.position.y)
	for i in range(1, 5):
		var a := PI * (0.5 * float(i) / 5.0)
		pts.append(Vector2(nose_c.x + cos(a) * nose_w, nose_c.y + sin(a) * r.size.y * 0.022 * (1.0 - nose_round)))
	return pts


# Glasshouse: windscreen base -> windscreen top -> rear window base, mirrored.
# The taper between those three points is the "greenhouse", and it is the
# cheapest strong cue from above: a hatch has an almost rectangular one, a
# hypercar a narrow teardrop, and that reads at a glance.
static func _draw_cabin(ci: CanvasItem, r: Rect2, pr: Dictionary, glass: Color) -> void:
	var cabin: Vector3 = pr.cabin
	var cx := r.get_center().x
	var hw := r.size.x * 0.5
	var gw0: float = hw * float(pr.glass_w0)
	var gw1: float = hw * float(pr.roof_w)
	var y0 := r.position.y + r.size.y * cabin.x
	var y1 := r.position.y + r.size.y * cabin.y
	var y2 := r.position.y + r.size.y * cabin.z
	# Two separate pieces of glass, not one outline: a windscreen surrounded by
	# glass on all four sides would just read as one huge windshield from above.
	# Windscreen: narrow at the cowl, wide where it meets the roof — the slope
	# is what makes a wedge look like a wedge from straight above.
	var glazing := PackedVector2Array([
		Vector2(cx - gw0, y0), Vector2(cx + gw0, y0),
		Vector2(cx + gw1, y1), Vector2(cx - gw1, y1),
	])
	ci.draw_colored_polygon(glazing, glass)
	glazing = PackedVector2Array([
		Vector2(cx - gw1, y1), Vector2(cx + gw1, y1),
		Vector2(cx + gw0 * 0.94, y2), Vector2(cx - gw0 * 0.94, y2),
	])
	ci.draw_colored_polygon(glazing, glass)
	# windscreen: darker at its inner edge, lighter where the sky hits it
	ci.draw_polygon(PackedVector2Array([
		Vector2(cx - gw0, y0), Vector2(cx + gw0, y0),
		Vector2(cx + gw1, y1), Vector2(cx - gw1, y1),
	]), PackedColorArray([
		Color(0.10, 0.14, 0.19, 0.0), Color(0.10, 0.14, 0.19, 0.0),
		Color(0.50, 0.60, 0.70, 0.22), Color(0.50, 0.60, 0.70, 0.22),
	]))
	# roof panel runs between the two creases; the crease lines are part of the
	# silhouette, so they are drawn in a colour that reads on any paint
	var roof_h := maxf(r.size.y * 0.02, 2.0)
	ci.draw_colored_polygon(PackedVector2Array([
		Vector2(cx - gw1, y1), Vector2(cx + gw1, y1),
		Vector2(cx + gw1, y1 + roof_h), Vector2(cx - gw1, y1 + roof_h),
	]), Color(1.0, 1.0, 1.0, 0.10))
	ci.draw_line(Vector2(cx - gw1, y1), Vector2(cx + gw1, y1), Color(0.55, 0.62, 0.70, 0.55), 1.5)
	ci.draw_line(Vector2(cx - gw1, y2), Vector2(cx + gw1, y2), Color(0.55, 0.62, 0.70, 0.55), 1.5)

static func car(ci: CanvasItem, center: Vector2, w: float, h: float, body: Color, opts := {}) -> void:
	var is_player: bool = opts.get("player", false)
	var stripes: bool = opts.get("stripe", is_player)
	var wing: bool = opts.get("wing", is_player)
	var braking: bool = opts.get("brake", false)
	var rails: bool = opts.get("rails", false)
	var roof_sign: bool = opts.get("roof_sign", false)
	var details: bool = opts.get("details", true)
	var body_only: bool = opts.get("body_only", false)
	var with_glass: bool = opts.get("glass", true)
	var pr: Dictionary = silhouette(str(opts.get("silhouette", "sedan")))
	# Each car gets its own overall length while the caller keeps the collision
	# box it already uses: the silhouette is what the eye reads, the hitbox is
	# what the game needs, and they do not have to be the same rectangle.
	h = h * float(pr.get("length", 1.0))
	var r := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)
	var dark := Color(0.075, 0.082, 0.09)
	var edge := body.lightened(0.22) if body.v < 0.3 else body.darkened(0.38)
	var glass := Color(0.055, 0.075, 0.100)
	var side: Array = pr.side
	var body_pts := _body_points(r, pr)
	var cabin: Vector3 = pr.cabin
	var cy: float = cabin.x
	var cr: float = cabin.z
	var cx := r.get_center().x
	var hw := w * 0.5

	# Wheels sit outside the flank: the stance sets the real overall width, so
	# a muscle car is wide at the tyres and a hypercar wider still.
	var heat: float = float(opts.get("heat", 0.0))
	var ww := w * float(pr.track)
	var wh := h * 0.145
	var axle: Vector2 = pr.wheelbase
	for wy in [r.position.y + h * axle.x, r.position.y + h * axle.y]:
		var t_mid: float = (wy + wh * 0.5 - r.position.y) / h
		var wheel_w: float = hw * _side_at(side, t_mid) + w * float(pr.stance)
		for s in [-1.0, 1.0]:
			var wx: float = cx + s * wheel_w - ww * 0.5
			var wc := Vector2(wx + ww * 0.5, wy + wh * 0.5)
			rr(ci, Rect2(wx, wy, ww, wh), dark, ww * 0.36)
			if not details:
				continue
			if heat > 0.35:
				# Glowing heated brake disc (cherry red to fiery incandescent orange)
				var ht := clampf((heat - 0.35) / 0.65, 0.0, 1.0)
				var glow_col := Color(1.0, 0.22 + ht * 0.45, 0.06, 0.55 + ht * 0.35)
				ci.draw_circle(wc, ww * 0.42, Color(1.0, 0.35, 0.05, 0.20 * ht))
				ci.draw_circle(wc, ww * 0.22, glow_col)
				if ht > 0.65:
					ci.draw_circle(wc, ww * 0.11, Color(1.0, 0.95, 0.75, 0.65 * (ht - 0.65) / 0.35))
			else:
				ci.draw_circle(wc, ww * 0.18, Color(0.42, 0.44, 0.47, 0.5))

	if body_only:
		ci.draw_colored_polygon(body_pts, body)
		return

	# body: a tapered polygon instead of a rectangle
	ci.draw_colored_polygon(body_pts, body)

	# everything below is paint: none of it belongs to the silhouette
	if not details and not with_glass:
		return

	if details:
		ci.draw_polyline(body_pts + PackedVector2Array([body_pts[0]]), edge, maxf(1.5, w * 0.012), true)
		soft_shadow(ci, r, w * 0.22, 0.30)

	# cylindrical shading across the width — what makes the roof read as a roof
	var shade := PackedVector2Array([
		Vector2(cx - hw * 0.96, r.position.y + h * 0.10),
		Vector2(cx + hw * 0.96, r.position.y + h * 0.10),
		Vector2(cx + hw * 0.96, r.end.y - h * 0.10),
		Vector2(cx - hw * 0.96, r.end.y - h * 0.10),
	])
	ci.draw_polygon(shade, PackedColorArray([
		Color(1, 1, 1, 0.11), Color(0, 0, 0, 0.10), Color(0, 0, 0, 0.10), Color(1, 1, 1, 0.11),
	]))

	if with_glass:
		# bonnet crease: follows the nose taper, so the bonnet reads as a plane
		var hood_w0 := hw * _side_at(side, 0.02) * 0.66
		var hood_w1 := hw * _side_at(side, cy) * 0.72
		ci.draw_polygon(PackedVector2Array([
			Vector2(cx - hood_w0, r.position.y + h * 0.02),
			Vector2(cx - hood_w0 * 0.52, r.position.y + h * 0.02),
			Vector2(cx - hood_w1 * 0.52, r.position.y + h * cy),
			Vector2(cx - hood_w1, r.position.y + h * cy),
		]), PackedColorArray([Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.05), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0)]))
		_draw_cabin(ci, r, pr, glass)
		if rails:
			# roof rails make an ordinary body read as a crossover / SUV
			var rr_y := r.position.y + h * (cy + 0.02)
			var rr_h := h * (cr - cy - 0.04)
			rr(ci, Rect2(cx - hw * 0.70, rr_y, w * 0.042, rr_h), dark, w * 0.018)
			rr(ci, Rect2(cx + hw * 0.70 - w * 0.042, rr_y, w * 0.042, rr_h), dark, w * 0.018)
		if roof_sign:
			rr(ci, Rect2(cx - w * 0.165, r.position.y + h * (cy + 0.06), w * 0.33, h * 0.088),
				Color(0.96, 0.84, 0.34), w * 0.03, Color(0.22, 0.19, 0.12, 0.65), 1)
			rr(ci, Rect2(cx - w * 0.145, r.position.y + h * (cy + 0.074), w * 0.29, h * 0.032), Color(0.20, 0.18, 0.13, 0.55), w * 0.01)

	if details and bool(pr.mirrors):
		var my := r.position.y + h * (cy - 0.045)
		var mx: float = hw * _side_at(side, cy - 0.045) + w * 0.012
		rr(ci, Rect2(cx - mx - w * 0.062, my, w * 0.075, h * 0.032), dark, w * 0.02)
		rr(ci, Rect2(cx + mx - w * 0.013, my, w * 0.075, h * 0.032), dark, w * 0.02)

	if details:
		# boot lid crease, so the rear reads as a rear
		var boot_y := r.position.y + h * (cr + 0.06)
		var boot_w: float = hw * _side_at(side, cr + 0.06) * 0.68
		ci.draw_line(Vector2(cx - boot_w, boot_y), Vector2(cx + boot_w, boot_y), Color(0, 0, 0, 0.13), maxf(1.0, h * 0.006))

	if stripes:
		# racing stripes, clipped visually to the bonnet and the boot
		var st: Color = opts.get("stripe_color", Color(0.94, 0.93, 0.90, 0.92))
		var stripe_h := h * (cy - 0.02)
		for sx in [-0.20, 0.145]:
			rr(ci, Rect2(cx + w * sx, r.position.y + h * 0.02, w * 0.055, stripe_h), st, w * 0.02)
			rr(ci, Rect2(cx + w * sx, r.position.y + h * (cr + 0.05), w * 0.055, h * (0.94 - cr)), st, w * 0.02)

	if details:
		if wing:
			# rear wing
			rr(ci, Rect2(r.position.x + w * 0.03, r.position.y + h * 0.885, w * 0.94, h * 0.055), body.darkened(0.45), w * 0.03, Color(0, 0, 0, 0.4), 1)
			rr(ci, Rect2(r.position.x + w * 0.06, r.position.y + h * 0.895, w * 0.88, h * 0.018), Color(1, 1, 1, 0.10), w * 0.01)
		else:
			rr(ci, Rect2(r.position.x + w * 0.09, r.position.y + h * 0.895, w * 0.82, h * 0.028), body.darkened(0.35), w * 0.02)

		# headlights follow the nose width
		var lamp := Color(0.97, 0.95, 0.86)
		var nose_w: float = hw * _side_at(side, 0.04)
		var hl_w := w * 0.235
		var hl_x := cx - nose_w + w * 0.06
		rr(ci, Rect2(hl_x, r.position.y + h * 0.014, hl_w, h * 0.028), lamp, w * 0.02)
		rr(ci, Rect2(cx + nose_w - w * 0.06 - hl_w, r.position.y + h * 0.014, hl_w, h * 0.028), lamp, w * 0.02)

		# taillights
		var tail := Color(0.78, 0.11, 0.11) if not is_player else Color(0.86, 0.13, 0.12)
		var rear_w: float = hw * _side_at(side, 0.96)
		var tl_w := w * 0.245
		var tl_x := cx - rear_w + w * 0.055
		rr(ci, Rect2(tl_x, r.position.y + h * 0.952, tl_w, h * 0.024), tail, w * 0.02)
		rr(ci, Rect2(cx + rear_w - w * 0.055 - tl_w, r.position.y + h * 0.952, tl_w, h * 0.024), tail, w * 0.02)

		if braking:
			ci.draw_circle(Vector2(tl_x + tl_w * 0.5, r.position.y + h * 0.960), w * 0.22, Color(1.0, 0.16, 0.10, 0.20))
			ci.draw_circle(Vector2(cx + rear_w - w * 0.055 - tl_w * 0.5, r.position.y + h * 0.960), w * 0.22, Color(1.0, 0.16, 0.10, 0.20))
			rr(ci, Rect2(tl_x, r.position.y + h * 0.952, tl_w, h * 0.024), Color(1.0, 0.30, 0.18), w * 0.02)
			rr(ci, Rect2(cx + rear_w - w * 0.055 - tl_w, r.position.y + h * 0.952, tl_w, h * 0.024), Color(1.0, 0.30, 0.18), w * 0.02)

	# front grill / bumper line, narrowed to the actual nose
	if details:
		var grill_w: float = hw * _side_at(side, 0.03) * 0.70
		rr(ci, Rect2(cx - grill_w * 0.5, r.position.y + h * 0.012, grill_w, h * 0.018), dark, w * 0.01)


static func truck(ci: CanvasItem, center: Vector2, w: float, h: float, cab: Color, trailer: Color, opts := {}) -> void:
	var r := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)
	var dark := Color(0.075, 0.082, 0.09)
	soft_shadow(ci, r, w * 0.12, 0.32)

	var ww := w * 0.14
	var wh := h * 0.10
	for wy in [r.position.y + h * 0.12, r.position.y + h * 0.42, r.position.y + h * 0.80]:
		rr(ci, Rect2(r.position.x - ww * 0.28, wy, ww, wh), dark, ww * 0.3)
		rr(ci, Rect2(r.end.x - ww * 0.72, wy, ww, wh), dark, ww * 0.3)

	# trailer
	var tr := Rect2(r.position.x + w * 0.02, r.position.y + h * 0.24, w * 0.96, h * 0.72)
	rr(ci, tr, trailer, 7, trailer.darkened(0.42), 2)
	# ribs
	var ribs := 9
	for i in range(1, ribs):
		var y := tr.position.y + tr.size.y * float(i) / float(ribs)
		ci.draw_line(Vector2(tr.position.x + 4, y), Vector2(tr.end.x - 4, y), Color(1, 1, 1, 0.14), 1.0)
	# trailer top highlight
	rr(ci, Rect2(tr.position.x + 6, tr.position.y + 5, tr.size.x - 12, 6), Color(1, 1, 1, 0.16), 3)

	# cab
	var cr := Rect2(r.position.x, r.position.y, w, h * 0.235)
	rr(ci, cr, cab, 8, cab.darkened(0.4), 2)
	rr(ci, Rect2(cr.position.x + w * 0.10, cr.position.y + h * 0.045, w * 0.80, h * 0.095), Color(0.11, 0.15, 0.19), 6, Color(0.3, 0.35, 0.4, 0.5), 1)
	rr(ci, Rect2(cr.position.x + w * 0.13, cr.position.y + h * 0.052, w * 0.74, h * 0.022), Color(0.55, 0.64, 0.72, 0.32), 2)
	rr(ci, Rect2(cr.position.x + w * 0.12, cr.position.y + h * 0.005, w * 0.20, h * 0.018), Color(0.97, 0.95, 0.86), 2)
	rr(ci, Rect2(cr.end.x - w * 0.32, cr.position.y + h * 0.005, w * 0.20, h * 0.018), Color(0.97, 0.95, 0.86), 2)
	# trailer taillights
	var braking: bool = opts.get("brake", false)
	var tail := Color(0.78, 0.11, 0.11)
	if braking:
		tail = Color(1.0, 0.30, 0.18)
		ci.draw_circle(Vector2(tr.position.x + w * 0.14, tr.end.y - h * 0.027), w * 0.20, Color(1.0, 0.16, 0.10, 0.24))
		ci.draw_circle(Vector2(tr.end.x - w * 0.14, tr.end.y - h * 0.027), w * 0.20, Color(1.0, 0.16, 0.10, 0.24))
	rr(ci, Rect2(tr.position.x + w * 0.05, tr.end.y - h * 0.035, w * 0.18, h * 0.016), tail, 2)
	rr(ci, Rect2(tr.end.x - w * 0.23, tr.end.y - h * 0.035, w * 0.18, h * 0.016), tail, 2)


static func van(ci: CanvasItem, center: Vector2, w: float, h: float, body: Color, _opts := {}) -> void:
	var r := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)
	var dark := Color(0.075, 0.082, 0.09)
	var glass := Color(0.055, 0.075, 0.100)
	var edge := body.lightened(0.22) if body.v < 0.3 else body.darkened(0.38)
	soft_shadow(ci, r, w * 0.16, 0.30)

	var ww := w * 0.15
	var wh := h * 0.095
	for wy in [r.position.y + h * 0.24, r.position.y + h * 0.74]:
		rr(ci, Rect2(r.position.x - ww * 0.28, wy, ww, wh), dark, ww * 0.32)
		rr(ci, Rect2(r.end.x - ww * 0.72, wy, ww, wh), dark, ww * 0.32)

	# body
	rr(ci, r, body, w * 0.14, edge, max(2, int(w * 0.018)))
	# hood strip
	rr(ci, Rect2(r.position.x + w * 0.10, r.position.y + h * 0.012, w * 0.80, h * 0.040), body.lightened(0.06), w * 0.03)

	# windshield
	rr(ci, Rect2(r.position.x + w * 0.10, r.position.y + h * 0.055, w * 0.80, h * 0.075), glass, w * 0.04, Color(0.3, 0.35, 0.4, 0.5), 1)
	rr(ci, Rect2(r.position.x + w * 0.13, r.position.y + h * 0.064, w * 0.74, h * 0.022), Color(0.55, 0.64, 0.72, 0.30), w * 0.01)

	# long cargo roof
	rr(ci, Rect2(r.position.x + w * 0.085, r.position.y + h * 0.165, w * 0.83, h * 0.655), body.darkened(0.10), w * 0.06)
	for i in range(1, 4):
		var ry := r.position.y + h * (0.24 + 0.13 * float(i))
		ci.draw_line(Vector2(r.position.x + w * 0.135, ry), Vector2(r.end.x - w * 0.135, ry), Color(1, 1, 1, 0.08), maxf(1.0, h * 0.005))
	# roof rails
	rr(ci, Rect2(r.position.x + w * 0.125, r.position.y + h * 0.20, w * 0.042, h * 0.55), Color(0.20, 0.21, 0.22, 0.85), w * 0.02)
	rr(ci, Rect2(r.end.x - w * 0.167, r.position.y + h * 0.20, w * 0.042, h * 0.55), Color(0.20, 0.21, 0.22, 0.85), w * 0.02)

	# mirrors
	rr(ci, Rect2(r.position.x - w * 0.048, r.position.y + h * 0.125, w * 0.072, h * 0.026), dark, w * 0.02)
	rr(ci, Rect2(r.end.x - w * 0.024, r.position.y + h * 0.125, w * 0.072, h * 0.026), dark, w * 0.02)

	# rear doors
	var dr := Rect2(r.position.x + w * 0.10, r.position.y + h * 0.835, w * 0.80, h * 0.125)
	rr(ci, dr, body.darkened(0.06), w * 0.05, body.darkened(0.30), 1)
	ci.draw_line(
		Vector2(dr.position.x + dr.size.x * 0.5, dr.position.y + dr.size.y * 0.10),
		Vector2(dr.position.x + dr.size.x * 0.5, dr.end.y - dr.size.y * 0.10),
		Color(0, 0, 0, 0.30), maxf(1.0, w * 0.012)
	)
	rr(ci, Rect2(dr.position.x + w * 0.05, dr.position.y + h * 0.014, w * 0.33, h * 0.048), glass, w * 0.02)
	rr(ci, Rect2(dr.end.x - w * 0.38, dr.position.y + h * 0.014, w * 0.33, h * 0.048), glass, w * 0.02)

	# taillights
	var braking: bool = _opts.get("brake", false)
	var tail := Color(0.78, 0.11, 0.11)
	if braking:
		tail = Color(1.0, 0.30, 0.18)
		ci.draw_circle(Vector2(r.position.x + w * 0.13, r.position.y + h * 0.97), w * 0.20, Color(1.0, 0.16, 0.10, 0.24))
		ci.draw_circle(Vector2(r.end.x - w * 0.13, r.position.y + h * 0.97), w * 0.20, Color(1.0, 0.16, 0.10, 0.24))
	rr(ci, Rect2(r.position.x + w * 0.055, r.position.y + h * 0.962, w * 0.155, h * 0.018), tail, w * 0.015)
	rr(ci, Rect2(r.end.x - w * 0.21, r.position.y + h * 0.962, w * 0.155, h * 0.018), tail, w * 0.015)


static func bus(ci: CanvasItem, center: Vector2, w: float, h: float, body: Color, opts := {}) -> void:
	var r := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)
	var accent: Color = opts.get("accent", Color(0.86, 0.27, 0.22))
	var dark := Color(0.075, 0.082, 0.09)
	var glass := Color(0.055, 0.075, 0.100)
	var edge := body.lightened(0.22) if body.v < 0.3 else body.darkened(0.38)
	soft_shadow(ci, r, w * 0.12, 0.34)

	# three axles
	var ww := w * 0.13
	var wh := h * 0.072
	for wy in [r.position.y + h * 0.12, r.position.y + h * 0.70, r.position.y + h * 0.84]:
		rr(ci, Rect2(r.position.x - ww * 0.30, wy, ww, wh), dark, ww * 0.30)
		rr(ci, Rect2(r.end.x - ww * 0.70, wy, ww, wh), dark, ww * 0.30)

	# body
	rr(ci, r, body, w * 0.10, edge, max(2, int(w * 0.016)))
	# roof
	rr(ci, Rect2(r.position.x + w * 0.08, r.position.y + h * 0.095, w * 0.84, h * 0.745), body.darkened(0.09), w * 0.06)
	# livery stripes along the sides
	rr(ci, Rect2(r.position.x + w * 0.032, r.position.y + h * 0.115, w * 0.034, h * 0.72), accent, w * 0.016)
	rr(ci, Rect2(r.end.x - w * 0.066, r.position.y + h * 0.115, w * 0.034, h * 0.72), accent, w * 0.016)
	# roof hatches
	for i in range(3):
		var hy := r.position.y + h * (0.17 + 0.21 * float(i))
		rr(ci, Rect2(r.position.x + w * 0.30, hy, w * 0.40, h * 0.075), body.darkened(0.24), w * 0.02, Color(0, 0, 0, 0.25), 1)

	# destination sign + windshield
	rr(ci, Rect2(r.position.x + w * 0.33, r.position.y + h * 0.006, w * 0.34, h * 0.020), Color(0.97, 0.84, 0.36), w * 0.01)
	rr(ci, Rect2(r.position.x + w * 0.10, r.position.y + h * 0.034, w * 0.80, h * 0.052), glass, w * 0.03, Color(0.3, 0.35, 0.4, 0.5), 1)
	rr(ci, Rect2(r.position.x + w * 0.14, r.position.y + h * 0.042, w * 0.72, h * 0.016), Color(0.55, 0.64, 0.72, 0.28), w * 0.01)

	# rear engine grille
	var gr := Rect2(r.position.x + w * 0.16, r.position.y + h * 0.855, w * 0.68, h * 0.090)
	rr(ci, gr, Color(0.10, 0.11, 0.12), w * 0.03, Color(0, 0, 0, 0.35), 1)
	for i in range(4):
		var gy := gr.position.y + gr.size.y * (0.22 + 0.19 * float(i))
		ci.draw_line(Vector2(gr.position.x + w * 0.03, gy), Vector2(gr.end.x - w * 0.03, gy), Color(1, 1, 1, 0.07), maxf(1.0, h * 0.003))

	# taillights
	var bus_braking: bool = opts.get("brake", false)
	var b_tail := Color(0.78, 0.11, 0.11)
	if bus_braking:
		b_tail = Color(1.0, 0.30, 0.18)
		ci.draw_circle(Vector2(r.position.x + w * 0.13, r.position.y + h * 0.968), w * 0.20, Color(1.0, 0.16, 0.10, 0.24))
		ci.draw_circle(Vector2(r.end.x - w * 0.13, r.position.y + h * 0.968), w * 0.20, Color(1.0, 0.16, 0.10, 0.24))
	rr(ci, Rect2(r.position.x + w * 0.055, r.position.y + h * 0.958, w * 0.145, h * 0.020), b_tail, w * 0.015)
	rr(ci, Rect2(r.end.x - w * 0.20, r.position.y + h * 0.958, w * 0.145, h * 0.020), b_tail, w * 0.015)


static func pickup(ci: CanvasItem, center: Vector2, w: float, h: float, body: Color, opts := {}) -> void:
	var r := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)
	var dark := Color(0.075, 0.082, 0.09)
	var glass := Color(0.055, 0.075, 0.100)
	var edge := body.lightened(0.22) if body.v < 0.3 else body.darkened(0.38)
	soft_shadow(ci, r, w * 0.20, 0.30)

	var ww := w * 0.155
	var wh := h * 0.125
	for wy in [r.position.y + h * 0.18, r.position.y + h * 0.72]:
		rr(ci, Rect2(r.position.x - ww * 0.30, wy, ww, wh), dark, ww * 0.34)
		rr(ci, Rect2(r.end.x - ww * 0.70, wy, ww, wh), dark, ww * 0.34)

	# body
	rr(ci, r, body, w * 0.17, edge, max(2, int(w * 0.018)))
	# hood
	rr(ci, Rect2(r.position.x + w * 0.10, r.position.y + h * 0.045, w * 0.80, h * 0.115), body.lightened(0.06), w * 0.07)
	# windshield
	rr(ci, Rect2(r.position.x + w * 0.115, r.position.y + h * 0.175, w * 0.77, h * 0.090), glass, w * 0.05, Color(0.3, 0.35, 0.4, 0.5), 1)
	rr(ci, Rect2(r.position.x + w * 0.145, r.position.y + h * 0.186, w * 0.71, h * 0.026), Color(0.55, 0.64, 0.72, 0.32), w * 0.01)
	# cab roof
	rr(ci, Rect2(r.position.x + w * 0.105, r.position.y + h * 0.285, w * 0.79, h * 0.185), body.darkened(0.10), w * 0.06)
	# side windows
	rr(ci, Rect2(r.position.x + w * 0.045, r.position.y + h * 0.300, w * 0.062, h * 0.150), glass, w * 0.03)
	rr(ci, Rect2(r.end.x - w * 0.107, r.position.y + h * 0.300, w * 0.062, h * 0.150), glass, w * 0.03)
	# mirrors
	rr(ci, Rect2(r.position.x - w * 0.045, r.position.y + h * 0.220, w * 0.070, h * 0.028), dark, w * 0.02)
	rr(ci, Rect2(r.end.x - w * 0.025, r.position.y + h * 0.220, w * 0.070, h * 0.028), dark, w * 0.02)

	# cargo bed
	var bed := Rect2(r.position.x + w * 0.075, r.position.y + h * 0.545, w * 0.85, h * 0.390)
	rr(ci, bed, body.darkened(0.16), w * 0.05, edge, 2)
	rr(ci, Rect2(bed.position.x + w * 0.045, bed.position.y + h * 0.022, bed.size.x - w * 0.090, bed.size.y - h * 0.045), Color(0.10, 0.11, 0.12), w * 0.03)
	if opts.get("cargo", false):
		var crate := Rect2(bed.position.x + w * 0.11, bed.position.y + h * 0.040, w * 0.40, h * 0.240)
		rr(ci, crate, Color(0.56, 0.45, 0.30), w * 0.02, Color(0.32, 0.25, 0.16, 0.8), 1)
		ci.draw_line(
			Vector2(crate.position.x + crate.size.x * 0.5, crate.position.y + 2.0),
			Vector2(crate.position.x + crate.size.x * 0.5, crate.end.y - 2.0),
			Color(0.30, 0.24, 0.15, 0.55), maxf(1.0, w * 0.010)
		)
	# tailgate
	rr(ci, Rect2(bed.position.x + w * 0.020, bed.end.y - h * 0.030, bed.size.x - w * 0.040, h * 0.028), body.lightened(0.05), w * 0.02)
	# taillights
	var p_braking: bool = opts.get("brake", false)
	var p_tail := Color(0.78, 0.11, 0.11)
	if p_braking:
		p_tail = Color(1.0, 0.30, 0.18)
		ci.draw_circle(Vector2(r.position.x + w * 0.15, r.position.y + h * 0.968), w * 0.20, Color(1.0, 0.16, 0.10, 0.24))
		ci.draw_circle(Vector2(r.end.x - w * 0.15, r.position.y + h * 0.968), w * 0.20, Color(1.0, 0.16, 0.10, 0.24))
	rr(ci, Rect2(r.position.x + w * 0.065, r.position.y + h * 0.958, w * 0.165, h * 0.020), p_tail, w * 0.015)
	rr(ci, Rect2(r.end.x - w * 0.230, r.position.y + h * 0.958, w * 0.165, h * 0.020), p_tail, w * 0.015)


# --- pickups ----------------------------------------------------------------

static func coin(ci: CanvasItem, p: Vector2, rad: float, phase := 0.0) -> void:
	var glow := 0.5 + 0.5 * sin(phase * 4.0)
	ci.draw_circle(p + Vector2(rad * 0.14, rad * 0.34), rad * 1.02, Color(0, 0, 0, 0.22))
	ci.draw_circle(p, rad * 1.45, Color(0.96, 0.72, 0.20, 0.08 + glow * 0.05))
	ci.draw_circle(p, rad, Color(0.80, 0.57, 0.10))
	ci.draw_circle(p, rad * 0.84, Color(0.97, 0.78, 0.24))
	ci.draw_circle(p - Vector2(rad * 0.20, rad * 0.24), rad * 0.33, Color(1.0, 0.93, 0.66, 0.55))
	ci.draw_arc(p, rad * 0.62, 0.0, TAU, 26, Color(0.70, 0.48, 0.07, 0.75), maxf(1.0, rad * 0.10), true)
	var s := rad * 0.36
	ci.draw_colored_polygon(
		PackedVector2Array([
			p + Vector2(0.0, -s), p + Vector2(s * 0.34, 0.0),
			p + Vector2(0.0, s), p + Vector2(-s * 0.34, 0.0),
		]),
		Color(0.62, 0.42, 0.05, 0.85)
	)


static func nitro_can(ci: CanvasItem, p: Vector2, s: float, phase := 0.0) -> void:
	var glow := 0.5 + 0.5 * sin(phase * 4.0)
	ci.draw_circle(p + Vector2(s * 0.12, s * 0.30), s * 0.62, Color(0, 0, 0, 0.22))
	ci.draw_circle(p, s * 0.95, Color(0.30, 0.72, 1.0, 0.08 + glow * 0.07))
	var w := s * 0.66
	var h := s * 1.30
	var r := Rect2(p.x - w * 0.5, p.y - h * 0.5, w, h)
	rr(ci, r, Color(0.08, 0.38, 0.60), w * 0.30, Color(0.52, 0.84, 0.98, 0.80), 2)
	rr(ci, Rect2(r.position.x + w * 0.16, r.position.y + h * 0.09, w * 0.17, h * 0.82), Color(1, 1, 1, 0.16), w * 0.08)
	rr(ci, Rect2(r.position.x + w * 0.08, r.position.y - h * 0.04, w * 0.84, h * 0.13), Color(0.76, 0.81, 0.85), 3)
	rr(ci, Rect2(r.position.x + w * 0.08, r.end.y - h * 0.09, w * 0.84, h * 0.13), Color(0.76, 0.81, 0.85), 3)
	var g := s * 0.40
	ci.draw_colored_polygon(
		PackedVector2Array([
			p + Vector2(g * 0.10, -g * 0.82), p + Vector2(-g * 0.44, g * 0.10),
			p + Vector2(-g * 0.04, g * 0.10), p + Vector2(-g * 0.16, g * 0.86),
			p + Vector2(g * 0.46, -g * 0.14), p + Vector2(g * 0.06, -g * 0.14),
		]),
		Color(0.94, 0.98, 1.0, 0.95)
	)


# --- scenery ----------------------------------------------------------------

static func tree(ci: CanvasItem, p: Vector2, s: float, tint := 0.0) -> void:
	ci.draw_circle(p + Vector2(s * 0.22, s * 0.26), s * 0.72, Color(0, 0, 0, 0.16))
	ci.draw_circle(p, s * 0.22, Color(0.30, 0.23, 0.16))
	var c1 := Color(0.24, 0.35, 0.18).lerp(Color(0.29, 0.40, 0.21), tint)
	var c2 := Color(0.31, 0.44, 0.23).lerp(Color(0.36, 0.49, 0.27), tint)
	var c3 := Color(0.38, 0.52, 0.28).lerp(Color(0.43, 0.56, 0.32), tint)
	ci.draw_circle(p + Vector2(-s * 0.06, -s * 0.02), s * 0.62, c1)
	ci.draw_circle(p + Vector2(-s * 0.28, -s * 0.22), s * 0.44, c2)
	ci.draw_circle(p + Vector2(s * 0.24, -s * 0.16), s * 0.40, c2)
	ci.draw_circle(p + Vector2(s * 0.06, s * 0.22), s * 0.40, c1)
	ci.draw_circle(p + Vector2(-s * 0.18, -s * 0.30), s * 0.24, c3)


static func bush(ci: CanvasItem, p: Vector2, s: float) -> void:
	ci.draw_circle(p + Vector2(s * 0.15, s * 0.18), s * 0.62, Color(0, 0, 0, 0.14))
	ci.draw_circle(p, s * 0.46, Color(0.24, 0.35, 0.19))
	ci.draw_circle(p + Vector2(-s * 0.26, s * 0.06), s * 0.32, Color(0.28, 0.40, 0.22))
	ci.draw_circle(p + Vector2(s * 0.24, s * 0.02), s * 0.30, Color(0.30, 0.44, 0.24))
	ci.draw_circle(p + Vector2(-s * 0.08, -s * 0.12), s * 0.24, Color(0.36, 0.50, 0.28))


static func streetlight(ci: CanvasItem, base: Vector2, dir: float, s: float) -> void:
	# top-down street lamp: base, arm reaching over the road, lamp head
	var arm_len := 92.0 * s
	var lamp_x := base.x + arm_len * dir
	ci.draw_polygon(
		PackedVector2Array([
			Vector2(base.x, base.y + 6.0 * s),
			Vector2(lamp_x, base.y + 10.0 * s),
			Vector2(lamp_x + dir * 30.0 * s, base.y + 46.0 * s),
			Vector2(base.x + dir * 24.0 * s, base.y + 38.0 * s),
		]),
		PackedColorArray([Color(0, 0, 0, 0.13), Color(0, 0, 0, 0.10), Color(0, 0, 0, 0.0), Color(0, 0, 0, 0.0)])
	)
	ci.draw_circle(base + Vector2(2, 6), 9.0 * s, Color(0, 0, 0, 0.16))
	ci.draw_circle(base, 8.0 * s, Color(0.44, 0.45, 0.43))
	ci.draw_circle(base - Vector2(1.5, 1.5), 4.0 * s, Color(0.60, 0.61, 0.58))
	var x0 := minf(base.x, lamp_x)
	var x1 := maxf(base.x, lamp_x)
	ci.draw_rect(Rect2(x0, base.y - 3.0 * s, x1 - x0, 6.0 * s), Color(0.40, 0.41, 0.40))
	ci.draw_rect(Rect2(x0, base.y - 3.0 * s, x1 - x0, 2.0 * s), Color(0.60, 0.61, 0.59))
	rr(ci, Rect2(lamp_x - 14.0 * s, base.y - 6.0 * s, 28.0 * s, 12.0 * s), Color(0.28, 0.29, 0.28), 4)
	rr(ci, Rect2(lamp_x - 10.0 * s, base.y - 3.0 * s, 20.0 * s, 5.0 * s), Color(0.88, 0.86, 0.76), 2)


static func road_sign(ci: CanvasItem, p: Vector2, side: float) -> void:
	# small blue plate beside the road
	ci.draw_rect(Rect2(p.x - 2, p.y, 4, 26), Color(0.35, 0.36, 0.36))
	rr(ci, Rect2(p.x - 15, p.y - 22, 30, 24), Color(0.12, 0.28, 0.48), 4, Color(0.88, 0.90, 0.92), 2)
	var dir := 1.0 if side > 0 else -1.0
	var cx := p.x
	var cy := p.y - 10
	ci.draw_polyline(
		PackedVector2Array([Vector2(cx - 6 * dir, cy - 4), Vector2(cx + 2 * dir, cy), Vector2(cx - 6 * dir, cy + 4)]),
		Color(0.92, 0.94, 0.96), 2.0, true
	)
