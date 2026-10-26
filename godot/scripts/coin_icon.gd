class_name CoinIcon
extends Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(28, 28)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.46
	draw_circle(c + Vector2(0.0, r * 0.16), r, Color(0, 0, 0, 0.28))
	draw_circle(c, r, Color(0.78, 0.55, 0.09))
	draw_circle(c, r * 0.86, Color(0.97, 0.78, 0.24))
	draw_circle(c - Vector2(r * 0.20, r * 0.24), r * 0.30, Color(1.0, 0.93, 0.66, 0.55))
	draw_arc(c, r * 0.60, 0.0, TAU, 24, Color(0.70, 0.48, 0.07, 0.75), maxf(1.0, r * 0.12), true)
	var s := r * 0.34
	draw_colored_polygon(
		PackedVector2Array([
			c + Vector2(0.0, -s), c + Vector2(s * 0.34, 0.0),
			c + Vector2(0.0, s), c + Vector2(-s * 0.34, 0.0),
		]),
		Color(0.62, 0.42, 0.05, 0.85)
	)
