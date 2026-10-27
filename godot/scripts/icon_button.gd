class_name IconButton
extends Control

signal pressed

var kind := "pause"
var _down := false


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(76, 76)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	draw_circle(c, r, Color(0.03, 0.04, 0.05, 0.42 if not _down else 0.62))
	draw_circle(c, r - 1.5, Color(1, 1, 1, 0.05 if not _down else 0.11))
	draw_arc(c, r - 1.5, 0.0, TAU, 40, Color(1, 1, 1, 0.10), 1.5, true)
	var col := Color(0.94, 0.94, 0.93, 0.92)
	if kind == "pause":
		var bw := r * 0.23
		var bh := r * 0.80
		Art.rr(self, Rect2(c.x - r * 0.36, c.y - bh * 0.5, bw, bh), col, bw * 0.35)
		Art.rr(self, Rect2(c.x + r * 0.13, c.y - bh * 0.5, bw, bh), col, bw * 0.35)
	elif kind == "back":
		draw_line(c + Vector2(-r * 0.28, 0.0), c + Vector2(r * 0.28, 0.0), col, 4.0, true)
		draw_line(c + Vector2(-r * 0.28, 0.0), c + Vector2(r * 0.02, -r * 0.3), col, 4.0, true)
		draw_line(c + Vector2(-r * 0.28, 0.0), c + Vector2(r * 0.02, r * 0.3), col, 4.0, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_down = true
			queue_redraw()
		elif _down:
			_down = false
			queue_redraw()
			pressed.emit()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
			queue_redraw()
		elif _down:
			_down = false
			queue_redraw()
			pressed.emit()
		accept_event()
