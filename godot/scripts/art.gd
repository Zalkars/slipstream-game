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

static func car(ci: CanvasItem, center: Vector2, w: float, h: float, body: Color, opts := {}) -> void:
	var is_player: bool = opts.get("player", false)
	var stripes: bool = opts.get("stripe", is_player)
	var wing: bool = opts.get("wing", is_player)
	var braking: bool = opts.get("brake", false)
	var r := Rect2(center.x - w * 0.5, center.y - h * 0.5, w, h)
	var dark := Color(0.075, 0.082, 0.09)
	var edge := body.lightened(0.22) if body.v < 0.3 else body.darkened(0.38)

	soft_shadow(ci, r, w * 0.22, 0.30)

	# wheels (behind the body)
	var ww := w * 0.155
	var wh := h * 0.145
	for wy in [r.position.y + h * 0.145, r.position.y + h * 0.665]:
		rr(ci, Rect2(r.position.x - ww * 0.30, wy, ww, wh), dark, ww * 0.34)
		rr(ci, Rect2(r.end.x - ww * 0.70, wy, ww, wh), dark, ww * 0.34)
		# small brake disc glint
		ci.draw_circle(Vector2(r.position.x - ww * 0.30 + ww * 0.5, wy + wh * 0.5), ww * 0.18, Color(0.42, 0.44, 0.47, 0.5))

	# body
	rr(ci, r, body, w * 0.21, edge, max(2, int(w * 0.018)))

	# left-side soft highlight
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

	# hood shading
	rr(ci, Rect2(r.position.x + w * 0.10, r.position.y + h * 0.055, w * 0.80, h * 0.17), body.lightened(0.06), w * 0.10)

	# windshield
	var glass := Color(0.105, 0.145, 0.185)
	rr(ci, Rect2(r.position.x + w * 0.13, r.position.y + h * 0.235, w * 0.74, h * 0.135), glass, w * 0.07, Color(0.3, 0.35, 0.4, 0.5), 1)
	rr(ci, Rect2(r.position.x + w * 0.16, r.position.y + h * 0.248, w * 0.68, h * 0.032), Color(0.55, 0.64, 0.72, 0.35), w * 0.02)

	# roof
	rr(ci, Rect2(r.position.x + w * 0.11, r.position.y + h * 0.385, w * 0.78, h * 0.245), body.darkened(0.10), w * 0.08)

	# side windows
	rr(ci, Rect2(r.position.x + w * 0.045, r.position.y + h * 0.40, w * 0.075, h * 0.21), glass, w * 0.03)
	rr(ci, Rect2(r.end.x - w * 0.12, r.position.y + h * 0.40, w * 0.075, h * 0.21), glass, w * 0.03)

	# mirrors
	rr(ci, Rect2(r.position.x - w * 0.045, r.position.y + h * 0.335, w * 0.075, h * 0.032), dark, w * 0.02)
	rr(ci, Rect2(r.end.x - w * 0.030, r.position.y + h * 0.335, w * 0.075, h * 0.032), dark, w * 0.02)

	# rear window
	rr(ci, Rect2(r.position.x + w * 0.145, r.position.y + h * 0.655, w * 0.71, h * 0.10), glass, w * 0.06)

	# boot lid shading
	rr(ci, Rect2(r.position.x + w * 0.11, r.position.y + h * 0.785, w * 0.78, h * 0.10), body.darkened(0.05), w * 0.06)

	if stripes:
		# racing stripes
		var st: Color = opts.get("stripe_color", Color(0.94, 0.93, 0.90, 0.92))
		rr(ci, Rect2(r.position.x + w * 0.30, r.position.y + h * 0.02, w * 0.055, h * 0.23), st, w * 0.02)
		rr(ci, Rect2(r.position.x + w * 0.645, r.position.y + h * 0.02, w * 0.055, h * 0.23), st, w * 0.02)
		rr(ci, Rect2(r.position.x + w * 0.30, r.position.y + h * 0.755, w * 0.055, h * 0.14), st, w * 0.02)
		rr(ci, Rect2(r.position.x + w * 0.645, r.position.y + h * 0.755, w * 0.055, h * 0.14), st, w * 0.02)
	if wing:
		# rear wing
		rr(ci, Rect2(r.position.x + w * 0.03, r.position.y + h * 0.885, w * 0.94, h * 0.055), body.darkened(0.45), w * 0.03, Color(0, 0, 0, 0.4), 1)
		rr(ci, Rect2(r.position.x + w * 0.06, r.position.y + h * 0.895, w * 0.88, h * 0.018), Color(1, 1, 1, 0.10), w * 0.01)
	else:
		rr(ci, Rect2(r.position.x + w * 0.09, r.position.y + h * 0.895, w * 0.82, h * 0.028), body.darkened(0.35), w * 0.02)

	# headlights
	var lamp := Color(0.97, 0.95, 0.86)
	rr(ci, Rect2(r.position.x + w * 0.095, r.position.y + h * 0.014, w * 0.235, h * 0.028), lamp, w * 0.02)
	rr(ci, Rect2(r.end.x - w * 0.330, r.position.y + h * 0.014, w * 0.235, h * 0.028), lamp, w * 0.02)

	# taillights
	var tail := Color(0.78, 0.11, 0.11) if not is_player else Color(0.86, 0.13, 0.12)
	rr(ci, Rect2(r.position.x + w * 0.085, r.position.y + h * 0.952, w * 0.245, h * 0.024), tail, w * 0.02)
	rr(ci, Rect2(r.end.x - w * 0.330, r.position.y + h * 0.952, w * 0.245, h * 0.024), tail, w * 0.02)

	if braking:
		ci.draw_circle(Vector2(r.position.x + w * 0.205, r.position.y + h * 0.960), w * 0.22, Color(1.0, 0.16, 0.10, 0.20))
		ci.draw_circle(Vector2(r.end.x - w * 0.205, r.position.y + h * 0.960), w * 0.22, Color(1.0, 0.16, 0.10, 0.20))
		rr(ci, Rect2(r.position.x + w * 0.085, r.position.y + h * 0.952, w * 0.245, h * 0.024), Color(1.0, 0.30, 0.18), w * 0.02)
		rr(ci, Rect2(r.end.x - w * 0.330, r.position.y + h * 0.952, w * 0.245, h * 0.024), Color(1.0, 0.30, 0.18), w * 0.02)

	# front grill / bumper line
	rr(ci, Rect2(r.position.x + w * 0.34, r.position.y + h * 0.012, w * 0.32, h * 0.018), dark, w * 0.01)


static func truck(ci: CanvasItem, center: Vector2, w: float, h: float, cab: Color, trailer: Color) -> void:
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
	rr(ci, Rect2(tr.position.x + w * 0.05, tr.end.y - h * 0.035, w * 0.18, h * 0.016), Color(0.78, 0.11, 0.11), 2)
	rr(ci, Rect2(tr.end.x - w * 0.23, tr.end.y - h * 0.035, w * 0.18, h * 0.016), Color(0.78, 0.11, 0.11), 2)


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
