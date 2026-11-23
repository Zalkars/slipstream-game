class_name WeatherClock
extends Control

# HUD clock with the weather as an icon: the current sky, the time in large
# digits and, shortly before the weather turns, a small forecast icon.

const CLEAR := 0
const CLOUDY := 1
const RAIN := 2
const STORM := 3
const FOG := 4

var font: Font
var weather := CLEAR
var night := false
var clock := "12:00"
var forecast := -1
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func set_state(w: int, is_night: bool, clock_text: String, next_w: int) -> void:
	if w == weather and is_night == night and clock_text == clock and next_w == forecast:
		return
	weather = w
	night = is_night
	clock = clock_text
	forecast = next_w
	queue_redraw()


func _process(delta: float) -> void:
	if forecast >= 0 and is_visible_in_tree():
		_pulse += delta
		queue_redraw()


func _draw() -> void:
	var fs := 46
	var tw := font.get_string_size(clock, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x if font != null else 110.0
	var icon := 50.0
	var gap := 10.0
	var fc_w := 50.0 if forecast >= 0 else 0.0
	var total := icon + gap + tw + 24.0 + fc_w
	var left := size.x - total
	var cy := size.y * 0.5
	Art.rr(self, Rect2(left, 2.0, total, size.y - 4.0), Color(0.02, 0.03, 0.04, 0.42), (size.y - 4.0) * 0.5)
	var x := left + 12.0
	draw_icon(self, Vector2(x + icon * 0.5, cy), icon, weather, night)
	x += icon + gap
	if font != null:
		var base := cy + font.get_ascent(fs) * 0.5 - font.get_descent(fs) * 0.35
		draw_string_outline(font, Vector2(x, base), clock, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, 4, Color(0, 0, 0, 0.45))
		draw_string(font, Vector2(x, base), clock, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(0.98, 0.97, 0.94))
	x += tw + 12.0
	if forecast >= 0:
		var a := 0.65 + 0.35 * sin(_pulse * 4.0)
		var ax := x + 4.0
		draw_polyline(PackedVector2Array([Vector2(ax, cy - 7.0), Vector2(ax + 6.0, cy), Vector2(ax, cy + 7.0)]),
			Color(1, 1, 1, 0.70 * a), 2.5, true)
		var c := Vector2(x + 30.0, cy)
		var tint := Color(1, 1, 1, a)
		draw_icon(self, c, 30.0, forecast, night, tint)


static func draw_icon(ci: CanvasItem, c: Vector2, s: float, w: int, is_night: bool, tint := Color.WHITE) -> void:
	var r := s * 0.5
	match w:
		CLEAR:
			if is_night:
				_moon(ci, c, r * 0.72, tint)
			else:
				_sun(ci, c, r * 0.46, tint)
		CLOUDY:
			if is_night:
				_moon(ci, c + Vector2(r * 0.28, -r * 0.30), r * 0.48, tint)
			else:
				_sun(ci, c + Vector2(r * 0.30, -r * 0.30), r * 0.32, tint)
			_cloud(ci, c + Vector2(-r * 0.08, r * 0.16), r * 0.82, _mul(Color(0.92, 0.94, 0.96), tint))
		RAIN:
			_cloud(ci, c + Vector2(0, -r * 0.22), r * 0.86, _mul(Color(0.80, 0.84, 0.88), tint))
			for i in range(3):
				var x := c.x - r * 0.42 + float(i) * r * 0.42
				ci.draw_line(Vector2(x, c.y + r * 0.30), Vector2(x - r * 0.16, c.y + r * 0.78), _mul(Color(0.45, 0.75, 1.0), tint), maxf(2.0, s * 0.07), true)
		STORM:
			_cloud(ci, c + Vector2(0, -r * 0.24), r * 0.86, _mul(Color(0.58, 0.62, 0.68), tint))
			ci.draw_colored_polygon(PackedVector2Array([
				c + Vector2(r * 0.06, r * 0.02), c + Vector2(-r * 0.30, r * 0.52), c + Vector2(-r * 0.02, r * 0.50),
				c + Vector2(-r * 0.16, r * 0.98), c + Vector2(r * 0.32, r * 0.38), c + Vector2(r * 0.04, r * 0.40),
			]), _mul(Color(1.0, 0.84, 0.26), tint))
		_:
			for i in range(3):
				var y := c.y - r * 0.44 + float(i) * r * 0.44
				var inset := r * (0.16 if i == 1 else 0.0)
				ci.draw_line(Vector2(c.x - r * 0.80 + inset, y), Vector2(c.x + r * 0.80 - inset, y), _mul(Color(0.80, 0.84, 0.86), tint), maxf(3.0, s * 0.11), true)


static func _mul(a: Color, b: Color) -> Color:
	return Color(a.r * b.r, a.g * b.g, a.b * b.b, a.a * b.a)


static func _sun(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	var col := _mul(Color(1.0, 0.80, 0.26), tint)
	for i in range(8):
		var d := Vector2.from_angle(TAU * float(i) / 8.0)
		ci.draw_line(c + d * r * 1.35, c + d * r * 1.85, col, maxf(2.0, r * 0.22), true)
	ci.draw_circle(c, r, col)
	ci.draw_circle(c - Vector2(r, r) * 0.25, r * 0.45, _mul(Color(1.0, 0.92, 0.55), tint))


static func _moon(ci: CanvasItem, c: Vector2, r: float, tint: Color) -> void:
	# Crescent: the left half of a disc minus a half-ellipse inside it.
	var pts := PackedVector2Array()
	var n := 16
	for i in range(n + 1):
		pts.append(c + Vector2.from_angle(lerpf(PI * 0.5, PI * 1.5, float(i) / float(n))) * r)
	for i in range(1, n):
		var a := lerpf(PI * 1.5, PI * 0.5, float(i) / float(n))
		pts.append(c + Vector2(cos(a) * r * 0.42, sin(a) * r))
	ci.draw_colored_polygon(pts, _mul(Color(0.96, 0.92, 0.74), tint))


static func _cloud(ci: CanvasItem, c: Vector2, r: float, col: Color) -> void:
	ci.draw_circle(c + Vector2(-r * 0.42, r * 0.12), r * 0.40, col)
	ci.draw_circle(c + Vector2(0.0, -r * 0.12), r * 0.52, col)
	ci.draw_circle(c + Vector2(r * 0.46, r * 0.10), r * 0.40, col)
	Art.rr(ci, Rect2(c.x - r * 0.82, c.y + r * 0.02, r * 1.64, r * 0.48), col, r * 0.24)
