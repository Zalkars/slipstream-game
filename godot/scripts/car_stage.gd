class_name CarStage
extends Control

# Garage showcase: spotlight, rotating turntable and a large car preview.

var car: Dictionary = {}
var _t := 0.0
var _ring := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_process(true)


func _process(delta: float) -> void:
	_t += delta
	_ring += delta * 0.42
	queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	Art.rr(self, Rect2(Vector2.ZERO, size), Color("#0b0e11"), 28)
	# light beam from above: soft vertical gradient cone
	var bw0 := size.x * 0.10
	var bw1 := size.x * 0.44
	var by0 := 0.0
	var by1 := size.y * 0.72
	var bands := 12
	for i in range(bands):
		var k0 := float(i) / float(bands)
		var k1 := float(i + 1) / float(bands)
		var w0 := lerpf(bw0, bw1, k0)
		var w1 := lerpf(bw0, bw1, k1)
		var y0 := lerpf(by0, by1, k0)
		var y1 := lerpf(by0, by1, k1)
		var a := 0.18 * lerpf(1.30, 0.35, (k0 + k1) * 0.5) / float(bands)
		draw_colored_polygon(PackedVector2Array([
			Vector2(c.x - w0, y0), Vector2(c.x + w0, y0),
			Vector2(c.x + w1, y1), Vector2(c.x - w1, y1),
		]), Color(0.86, 0.89, 0.93, a))
	# soft spotlight floor glow with gentle edge falloff
	for i in range(9):
		var r := size.x * (0.10 + float(i) * 0.065) * (0.55 + 0.30 * sin(float(i) * 1.3))
		var inv := 1.0 - float(i) / 9.0
		draw_circle(c + Vector2(0, size.y * 0.16), r, Color(0.98, 0.90, 0.74, 0.012 * (1.0 + inv * 2.2)))

	# turntable
	var plat := c + Vector2(0, size.y * 0.22)
	draw_set_transform(plat, 0.0, Vector2(1.0, 0.34))
	draw_circle(Vector2.ZERO, size.x * 0.42, Color(0.05, 0.06, 0.07))
	draw_circle(Vector2.ZERO, size.x * 0.40, Color(0.09, 0.10, 0.11))
	draw_arc(Vector2.ZERO, size.x * 0.40, 0.0, TAU, 64, Color(1, 1, 1, 0.07), 3.0, true)
	draw_arc(Vector2.ZERO, size.x * 0.30, 0.0, TAU, 64, Color(1, 1, 1, 0.035), 2.0, true)
	# rotating dashes
	for i in range(24):
		var a0 := _ring + TAU * float(i) / 24.0
		draw_arc(Vector2.ZERO, size.x * 0.355, a0, a0 + 0.10, 4, Color(0.95, 0.72, 0.28, 0.30), 3.5, true)
	draw_set_transform(Vector2.ZERO)

	# car shadow + car
	var car_c := c + Vector2(0, -size.y * 0.02 + sin(_t * 1.25) * 3.0)
	var body := Color(str(car.get("color", "#b32b26")))
	var stripes := bool(car.get("stripe", true))
	var wing := bool(car.get("wing", false))
	var stripe_col := Color(str(car.get("stripe_color", "#f0ede4")))
	draw_circle(car_c + Vector2(0, 150), 118.0, Color(0, 0, 0, 0.30))
	Art.car(self, car_c, 86.0 * 2.5, 163.0 * 2.5, body, {
		"stripe": stripes,
		"wing": wing,
		"stripe_color": stripe_col,
	})
