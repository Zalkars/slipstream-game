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


# --- car styles -------------------------------------------------------------
#
# The roster keeps the clean 0.4 body the garage was built around. Each class
# only nudges it: a little longer, a little wider, the cabin moved forward or
# back, plus the details that fit its character. No tapered "silhouette"
# experiments: the paint, glass and lights stay exactly where they belong.
static var _styles: Dictionary = {}


static func car_style(name: String) -> Dictionary:
	if _styles.is_empty():
		_styles = {
			# City hatch: compact, cabin forward, no spoiler drama.
			"hatch": {
				"len": 0.94, "wid": 0.99, "cabin": -0.020, "roof": 0.020,
				"scoop": false, "vents": false, "splitter": false, "diffuser": false,
				"exhaust": 1, "dark_roof": false, "stripe_w": 0.058,
			},
			# Three-box GT: the baseline every other car is measured against.
			"sedan": {
				"len": 1.00, "wid": 1.00, "cabin": 0.000, "roof": 0.000,
				"scoop": false, "vents": false, "splitter": false, "diffuser": false,
				"exhaust": 2, "dark_roof": false, "stripe_w": 0.055,
			},
			# Muscle: wider body, cabin set back, hood scoop and fat stripes.
			"muscle": {
				"len": 1.02, "wid": 1.05, "cabin": 0.025, "roof": -0.020,
				"scoop": true, "vents": false, "splitter": false, "diffuser": false,
				"exhaust": 2, "dark_roof": false, "stripe_w": 0.070,
			},
			# Track coupe: forward cabin, vents, splitter and diffuser.
			"sport": {
				"len": 1.035, "wid": 1.035, "cabin": -0.025, "roof": -0.015,
				"scoop": false, "vents": true, "splitter": true, "diffuser": true,
				"exhaust": 2, "dark_roof": false, "stripe_w": 0.058,
			},
			# Hypercar: widest, longest, dark roof, aero all round.
			"hyper": {
				"len": 1.05, "wid": 1.065, "cabin": -0.010, "roof": -0.030,
				"scoop": false, "vents": true, "splitter": true, "diffuser": true,
				"exhaust": 2, "dark_roof": true, "stripe_w": 0.050,
			},
		}
	return _styles.get(name, _styles["sedan"])


static func car(ci: CanvasItem, center: Vector2, w: float, h: float, body: Color, opts := {}) -> void:
	var is_player: bool = opts.get("player", false)
	var stripes: bool = opts.get("stripe", is_player)
	var wing: bool = opts.get("wing", is_player)
	var braking: bool = opts.get("brake", false)
	var rails: bool = opts.get("rails", false)
	var roof_sign: bool = opts.get("roof_sign", false)
	var details: bool = opts.get("details", true)
	var with_glass: bool = opts.get("glass", true)
	var st: Dictionary = car_style(str(opts.get("silhouette", "sedan")))
	w *= float(st.wid)
	h *= float(st.len)
	var r := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)
	var dark := Color(0.075, 0.082, 0.09)
	# Dark paints need a stronger rim light, otherwise a black car turns into a
	# featureless blob against the garage backdrop.
	var edge := body.lightened(0.34) if body.v < 0.3 else body.darkened(0.38)
	var glass := Color(0.105, 0.145, 0.185)
	var cx := r.get_center().x
	# One place for every vertical landmark, so a moved cabin cannot tear the
	# bonnet, roof, side windows and boot apart.
	var cs := float(st.cabin)
	var wind_y := 0.235 + cs
	var wind_h := 0.135
	var roof_y := 0.385 + cs
	var roof_h := 0.245 + float(st.roof)
	var rear_y := roof_y + roof_h + 0.025
	var boot_y := rear_y + 0.130

	if details:
		soft_shadow(ci, r, w * 0.22, 0.30)

	# wheels (behind the body), each with a fender socket and a readable rim
	var heat: float = float(opts.get("heat", 0.0))
	var ww := w * 0.158
	var wh := h * 0.148
	for wy in [r.position.y + h * 0.145, r.position.y + h * 0.665]:
		for side in [-1.0, 1.0]:
			var left: bool = side < 0.0
			var wx: float = (r.position.x - ww * 0.34) if left else (r.end.x - ww * 0.66)
			var wc := Vector2(wx + ww * 0.5, wy + wh * 0.5)
			ci.draw_circle(wc, ww * 0.46, Color(0.02, 0.025, 0.03, 0.10))
			rr(ci, Rect2(wx, wy, ww, wh), Color(0.055, 0.060, 0.070), ww * 0.36)
			if details:
				for k in [0.22, 0.50, 0.78]:
					var ty: float = wy + wh * float(k)
					ci.draw_line(Vector2(wx + ww * 0.16, ty), Vector2(wx + ww * 0.84, ty),
						Color(1, 1, 1, 0.055), maxf(1.0, wh * 0.03))
				# rim sits on the visible outer half of the tyre
				var rim_x: float = (wx + ww * 0.06) if left else (wx + ww * 0.66)
				rr(ci, Rect2(rim_x, wy + wh * 0.27, ww * 0.28, wh * 0.46),
					Color(0.50, 0.53, 0.57, 0.9), ww * 0.10)
				ci.draw_circle(Vector2(rim_x + ww * 0.14, wy + wh * 0.5),
					ww * 0.055, Color(0.15, 0.16, 0.18))
			if heat > 0.35:
				# Glowing heated brake disc (cherry red to fiery incandescent orange)
				var ht := clampf((heat - 0.35) / 0.65, 0.0, 1.0)
				var glow_col := Color(1.0, 0.22 + ht * 0.45, 0.06, 0.55 + ht * 0.35)
				ci.draw_circle(wc, ww * 0.42, Color(1.0, 0.35, 0.05, 0.20 * ht))
				ci.draw_circle(wc, ww * 0.22, glow_col)
				if ht > 0.65:
					ci.draw_circle(wc, ww * 0.11, Color(1.0, 0.95, 0.75, 0.65 * (ht - 0.65) / 0.35))
			elif details:
				ci.draw_circle(wc, ww * 0.18, Color(0.42, 0.44, 0.47, 0.5))

	# body
	rr(ci, r, body, w * 0.21, edge, max(2, int(w * 0.018)))

	# soft cylinder: a lighter centre band and the familiar left-hand light
	rr(ci, Rect2(r.position.x + w * 0.10, r.position.y + h * 0.025,
		w * 0.80, h * 0.950), body.lightened(0.045), w * 0.14)
	var hx := r.position.x + w * 0.06
	ci.draw_polygon(
		PackedVector2Array([
			Vector2(hx, r.position.y + h * 0.10),
			Vector2(hx + w * 0.11, r.position.y + h * 0.12),
			Vector2(hx + w * 0.11, r.end.y - h * 0.12),
			Vector2(hx, r.end.y - h * 0.10),
		]),
		PackedColorArray([Color(1, 1, 1, 0.10), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.0), Color(1, 1, 1, 0.06)])
	)

	# bonnet, centre crease and cowl line
	rr(ci, Rect2(r.position.x + w * 0.10, r.position.y + h * 0.045,
		w * 0.80, h * (wind_y - 0.075)), body.lightened(0.05), w * 0.12)
	ci.draw_line(Vector2(cx - w * 0.020, r.position.y + h * 0.060),
		Vector2(cx - w * 0.020, r.position.y + h * (wind_y - 0.020)),
		Color(1, 1, 1, 0.065), maxf(1.0, w * 0.006))
	ci.draw_line(Vector2(r.position.x + w * 0.070, r.position.y + h * wind_y),
		Vector2(r.end.x - w * 0.070, r.position.y + h * wind_y),
		Color(0, 0, 0, 0.18), maxf(1.0, h * 0.004))

	if bool(st.scoop):
		rr(ci, Rect2(cx - w * 0.10, r.position.y + h * (wind_y - 0.105),
			w * 0.20, h * 0.045), dark, w * 0.03, Color(0, 0, 0, 0.4), 1)
	if bool(st.vents):
		for side in [-1.0, 1.0]:
			for i in range(2):
				rr(ci, Rect2(cx + float(side) * w * 0.115 - w * 0.045,
					r.position.y + h * (wind_y - 0.088 + float(i) * 0.024),
					w * 0.090, h * 0.011), dark, w * 0.005)

	if with_glass:
		# windshield: glass gradient, dark at the cowl, sky at the roof
		rr(ci, Rect2(r.position.x + w * 0.13, r.position.y + h * wind_y,
			w * 0.74, h * wind_h), glass, w * 0.07, Color(0.3, 0.35, 0.4, 0.5), 1)
		rr(ci, Rect2(r.position.x + w * 0.16, r.position.y + h * (wind_y + 0.014),
			w * 0.68, h * 0.030), Color(0.55, 0.64, 0.72, 0.38), w * 0.02)
		rr(ci, Rect2(r.position.x + w * 0.16, r.position.y + h * (wind_y + wind_h - 0.034),
			w * 0.68, h * 0.022), Color(0.02, 0.03, 0.04, 0.22), w * 0.02)

	# roof panel
	var roof_col := body.darkened(0.18) if bool(st.dark_roof) else body.darkened(0.10)
	rr(ci, Rect2(r.position.x + w * 0.11, r.position.y + h * roof_y,
		w * 0.78, h * roof_h), roof_col, w * 0.08)
	rr(ci, Rect2(r.position.x + w * 0.20, r.position.y + h * (roof_y + 0.020),
		w * 0.60, h * 0.018), Color(1, 1, 1, 0.07), w * 0.01)

	if rails:
		# roof rails make an ordinary body read as a crossover / SUV
		rr(ci, Rect2(r.position.x + w * 0.155, r.position.y + h * (roof_y + 0.020),
			w * 0.042, h * (roof_h - 0.040)), dark, w * 0.02)
		rr(ci, Rect2(r.end.x - w * 0.197, r.position.y + h * (roof_y + 0.020),
			w * 0.042, h * (roof_h - 0.040)), dark, w * 0.02)
	if roof_sign:
		# taxi-style roof sign
		rr(ci, Rect2(r.position.x + w * 0.335, r.position.y + h * (roof_y + 0.067),
			w * 0.33, h * 0.088), Color(0.96, 0.84, 0.34), w * 0.03, Color(0.22, 0.19, 0.12, 0.65), 1)
		rr(ci, Rect2(r.position.x + w * 0.355, r.position.y + h * (roof_y + 0.083),
			w * 0.29, h * 0.032), Color(0.20, 0.18, 0.13, 0.55), w * 0.01)

	# side windows (with a thin chrome edge, so they read as glass, not holes)
	var sw_y := r.position.y + h * (roof_y + 0.015)
	var sw_h := h * (roof_h - 0.050)
	rr(ci, Rect2(r.position.x + w * 0.045, sw_y, w * 0.075, sw_h),
		glass, w * 0.03, Color(0.55, 0.62, 0.70, 0.45), 1)
	rr(ci, Rect2(r.end.x - w * 0.120, sw_y, w * 0.075, sw_h),
		glass, w * 0.03, Color(0.55, 0.62, 0.70, 0.45), 1)

	# mirrors
	var my := r.position.y + h * (wind_y + 0.100)
	rr(ci, Rect2(r.position.x - w * 0.045, my, w * 0.075, h * 0.032), dark, w * 0.02)
	rr(ci, Rect2(r.end.x - w * 0.030, my, w * 0.075, h * 0.032), dark, w * 0.02)

	if with_glass:
		# rear window
		rr(ci, Rect2(r.position.x + w * 0.145, r.position.y + h * rear_y,
			w * 0.71, h * 0.100), glass, w * 0.06, Color(0.3, 0.35, 0.4, 0.5), 1)
		rr(ci, Rect2(r.position.x + w * 0.170, r.position.y + h * (rear_y + 0.012),
			w * 0.66, h * 0.022), Color(0.48, 0.57, 0.66, 0.26), w * 0.01)

	# boot lid shading
	rr(ci, Rect2(r.position.x + w * 0.11, r.position.y + h * boot_y,
		w * 0.78, h * 0.100), body.darkened(0.05), w * 0.06)

	# side skirts on the aero cars
	if bool(st.diffuser):
		rr(ci, Rect2(r.position.x + w * 0.012, r.position.y + h * (roof_y + 0.020),
			w * 0.020, h * (boot_y - roof_y)), Color(0, 0, 0, 0.18), w * 0.008)
		rr(ci, Rect2(r.end.x - w * 0.032, r.position.y + h * (roof_y + 0.020),
			w * 0.020, h * (boot_y - roof_y)), Color(0, 0, 0, 0.18), w * 0.008)

	if stripes:
		# racing stripes run bonnet -> roof -> boot
		var stc: Color = opts.get("stripe_color", Color(0.94, 0.93, 0.90, 0.92))
		var sw := w * float(st.stripe_w)
		for sx in [cx - w * 0.200, cx + w * 0.145]:
			rr(ci, Rect2(sx, r.position.y + h * 0.020, sw, h * (wind_y - 0.035)),
				stc, sw * 0.35)
			if roof_h > 0.12:
				rr(ci, Rect2(sx, r.position.y + h * (roof_y + 0.025), sw, h * (roof_h - 0.050)),
					stc, sw * 0.35)
			rr(ci, Rect2(sx, r.position.y + h * (boot_y + 0.012), sw, h * (0.940 - boot_y - 0.012)),
				stc, sw * 0.35)

	if wing:
		# rear wing
		rr(ci, Rect2(r.position.x + w * 0.03, r.position.y + h * 0.885, w * 0.94, h * 0.055),
			body.darkened(0.45), w * 0.03, Color(0, 0, 0, 0.4), 1)
		rr(ci, Rect2(r.position.x + w * 0.06, r.position.y + h * 0.895, w * 0.88, h * 0.018),
			Color(1, 1, 1, 0.10), w * 0.01)
	else:
		rr(ci, Rect2(r.position.x + w * 0.09, r.position.y + h * 0.895, w * 0.82, h * 0.028),
			body.darkened(0.35), w * 0.02)

	# headlights
	var lamp := Color(0.97, 0.95, 0.86)
	rr(ci, Rect2(r.position.x + w * 0.095, r.position.y + h * 0.014, w * 0.235, h * 0.028),
		lamp, w * 0.02)
	rr(ci, Rect2(r.end.x - w * 0.330, r.position.y + h * 0.014, w * 0.235, h * 0.028),
		lamp, w * 0.02)

	# aero lips
	if bool(st.splitter):
		rr(ci, Rect2(r.position.x + w * 0.10, r.position.y + h * 0.003, w * 0.80, h * 0.011),
			dark, w * 0.005)
	if bool(st.diffuser):
		rr(ci, Rect2(cx - w * 0.30, r.end.y - h * 0.026, w * 0.60, h * 0.018),
			dark, w * 0.005)
		for i in range(5):
			var fx := cx - w * 0.24 + w * 0.12 * float(i)
			ci.draw_line(Vector2(fx, r.end.y - h * 0.026), Vector2(fx, r.end.y - h * 0.008),
				Color(1, 1, 1, 0.08), maxf(1.0, w * 0.004))

	# exhaust tips
	var ex := int(st.exhaust)
	var tip := Color(0.62, 0.64, 0.67)
	if ex <= 1:
		rr(ci, Rect2(cx - w * 0.045, r.end.y - h * 0.024, w * 0.090, h * 0.013),
			tip, w * 0.006)
	else:
		for side in [-1.0, 1.0]:
			rr(ci, Rect2(cx + float(side) * w * 0.105 - w * 0.045, r.end.y - h * 0.024,
				w * 0.090, h * 0.013), tip, w * 0.006)

	# taillights
	var tail := Color(0.78, 0.11, 0.11) if not is_player else Color(0.86, 0.13, 0.12)
	rr(ci, Rect2(r.position.x + w * 0.085, r.position.y + h * 0.952, w * 0.245, h * 0.024),
		tail, w * 0.02)
	rr(ci, Rect2(r.end.x - w * 0.330, r.position.y + h * 0.952, w * 0.245, h * 0.024),
		tail, w * 0.02)

	if braking:
		ci.draw_circle(Vector2(r.position.x + w * 0.205, r.position.y + h * 0.960), w * 0.22,
			Color(1.0, 0.16, 0.10, 0.20))
		ci.draw_circle(Vector2(r.end.x - w * 0.205, r.position.y + h * 0.960), w * 0.22,
			Color(1.0, 0.16, 0.10, 0.20))
		rr(ci, Rect2(r.position.x + w * 0.085, r.position.y + h * 0.952, w * 0.245, h * 0.024),
			Color(1.0, 0.30, 0.18), w * 0.02)
		rr(ci, Rect2(r.end.x - w * 0.330, r.position.y + h * 0.952, w * 0.245, h * 0.024),
			Color(1.0, 0.30, 0.18), w * 0.02)

	# front grill / bumper line
	rr(ci, Rect2(r.position.x + w * 0.34, r.position.y + h * 0.012, w * 0.32, h * 0.018),
		dark, w * 0.01)


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
	var glass := Color(0.105, 0.145, 0.185)
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
	var glass := Color(0.105, 0.145, 0.185)
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
	var glass := Color(0.105, 0.145, 0.185)
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
