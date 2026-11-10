class_name CarStage
extends Control

# Garage showcase: a large, clean car on a lit turntable.
#
# The 0.5.0 experiment squashed the car into a perspective that made it look
# broken and tiny. This is the 0.4.0 composition the garage was designed
# around, polished in the places that actually show:
#   * a soft floor wash instead of a black void,
#   * a layered contact shadow under the tyres,
#   * a polished turntable with a warm rotating band,
#   * the readable top-down body the roster has always used.

var car: Dictionary = {}
var _t := 0.0
var _ring := 0.0
# QA hook: freeze the animation / hide the contact shadow for a repeatable shot.
var shadow_off := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	_ring += delta * 0.42
	queue_redraw()


# Test hook: put the animation on an exact phase so renders are repeatable.
func set_time(t: float) -> void:
	_t = t
	_ring = t * 0.42
	queue_redraw()


# --- geometry, in one place ------------------------------------------------

func car_width() -> float:
	return size.x * 0.33


func car_height() -> float:
	return car_width() * 1.9


func podium_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.71)


func car_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.47 + sin(_t * 1.25) * 2.0)


func shadow_center() -> Vector2:
	return Vector2(size.x * 0.5, car_center().y + car_height() * 0.42)


# --- drawing ---------------------------------------------------------------

func _draw() -> void:
	_draw_room()
	_draw_beam()
	_draw_podium()
	if not shadow_off:
		_draw_contact_shadow()
	_draw_car()


# Dark showroom with a gentle wall-to-floor gradient.
func _draw_room() -> void:
	Art.rr(self, Rect2(Vector2.ZERO, size), Color("#0b0e11"), 28)
	Fx.vgrad(self, Rect2(Vector2.ZERO, Vector2(size.x, size.y * 0.78)),
		Color(0.090, 0.100, 0.115), Color(0.025, 0.030, 0.035))
	# floor: a barely visible warm strip, so the podium has something to stand on
	Fx.vgrad(self, Rect2(0.0, size.y * 0.68, size.x, size.y * 0.32),
		Color(0.030, 0.032, 0.036, 0.0), Color(0.016, 0.018, 0.021))


# Cone of light from a fixture above the frame.
func _draw_beam() -> void:
	var c := size * 0.5
	var bw0 := size.x * 0.075
	var bw1 := size.x * 0.345
	var by0 := -size.y * 0.04
	var by1 := size.y * 0.68
	var bands := 14
	for i in range(bands):
		var k0 := float(i) / float(bands)
		var k1 := float(i + 1) / float(bands)
		var w0 := lerpf(bw0, bw1, k0)
		var w1 := lerpf(bw0, bw1, k1)
		var y0 := lerpf(by0, by1, k0)
		var y1 := lerpf(by0, by1, k1)
		var a := 0.16 * lerpf(1.35, 0.30, (k0 + k1) * 0.5) / float(bands)
		draw_colored_polygon(PackedVector2Array([
			Vector2(c.x - w0, y0), Vector2(c.x + w0, y0),
			Vector2(c.x + w1, y1), Vector2(c.x - w1, y1),
		]), Color(0.86, 0.89, 0.93, a))


# Points along a perspective ellipse: cx,cy centre, rx horizontal, ry vertical.
func _ellipse_pts(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(steps + 1):
		var a := lerpf(a0, a1, float(i) / float(steps))
		out.push_back(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return out


# Polished turntable in perspective. The fill uses a squashed transform (cheap),
# but the ring details are drawn as real screen-space ellipse polylines: a
# squashed draw_arc stroke collapses to ~1px and simply disappears, while these
# stay a readable 2-3px whatever the aspect ratio.
func _draw_podium() -> void:
	var p := podium_center()
	var rx := size.x * 0.44
	var ry := rx * 0.33
	draw_set_transform(p, 0.0, Vector2(1.0, 0.33))
	draw_circle(Vector2.ZERO, rx, Color(0.032, 0.038, 0.048))
	# soft inner wash so the table reads as a lit surface, not a dark disc
	for i in range(5):
		var k := float(i) / 4.0
		draw_circle(Vector2.ZERO, rx * lerpf(0.96, 0.60, k),
			Color(0.10, 0.11, 0.13, 0.12))
	draw_set_transform(Vector2.ZERO)
	# bright rim and an inner seam
	draw_polyline(_ellipse_pts(p.x, p.y, rx * 0.985, ry * 0.985, 0.0, TAU, 96),
		Color(1, 1, 1, 0.14), 3.0, true)
	draw_polyline(_ellipse_pts(p.x, p.y, rx * 0.760, ry * 0.760, 0.0, TAU, 80),
		Color(1, 1, 1, 0.06), 2.0, true)
	# rotating warm dashes as short chords, drawn in screen space so they keep
	# their thickness on the flattened (top/bottom) parts of the ellipse
	var band := rx * 0.875
	var band_ry := band * 0.33
	for i in range(28):
		var a0 := _ring + TAU * float(i) / 28.0 - 0.040
		var a1 := a0 + 0.080
		var p0 := Vector2(p.x + cos(a0) * band, p.y + sin(a0) * band_ry)
		var p1 := Vector2(p.x + cos(a1) * band, p.y + sin(a1) * band_ry)
		draw_line(p0, p1, Color(0.95, 0.72, 0.28, 0.34), 3.0, true)
	# sheen along the front edge, away from the light
	draw_polyline(_ellipse_pts(p.x, p.y, rx * 0.93, ry * 0.93, PI * 0.18, PI * 0.82, 48),
		Color(1, 1, 1, 0.10), 3.0, true)


# Soft contact shadow under the tyres: widest and faintest first, narrowing to
# a dark core. Painted before the car, so the car hides the hard centre.
func _draw_contact_shadow() -> void:
	var c := shadow_center()
	var w := car_width()
	var layers := 8
	for i in range(layers):
		var k := 1.0 - float(i) / float(layers - 1)  # 1 = outermost
		var spread := lerpf(0.46, 0.78, k)
		var alpha := lerpf(0.24, 0.0, pow(k, 0.9))
		draw_set_transform(c, 0.0, Vector2(1.0, 0.30))
		draw_circle(Vector2.ZERO, w * spread, Color(0.010, 0.010, 0.016, alpha))
	draw_set_transform(Vector2.ZERO)


func _draw_car() -> void:
	var car_c := car_center()
	var body := Color(str(car.get("color", "#b32b26")))
	Art.car(self, car_c, car_width(), car_height(), body, {
		"silhouette": str(car.get("silhouette", "sedan")),
		"stripe": bool(car.get("stripe", true)),
		"wing": bool(car.get("wing", false)),
		"stripe_color": Color(str(car.get("stripe_color", "#f0ede4"))),
		"player": true,
		"fine": true,
	})
