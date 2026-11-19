class_name IconButton
extends Control

signal pressed

var kind := "pause"
var _pointer_id := -2


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(76, 76)


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5
	var down := _pointer_id != -2
	draw_circle(c, r, Color(0.03, 0.04, 0.05, 0.62 if down else 0.42))
	draw_circle(c, r - 1.5, Color(1, 1, 1, 0.11 if down else 0.05))
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
		_update_press(event.index, event.pressed, event.position, event.canceled)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.emulate_touch_from_mouse or event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_update_press(-1, event.pressed, event.position, event.canceled)
		accept_event()


func _update_press(id: int, down: bool, pos: Vector2, canceled: bool) -> void:
	if down and not canceled:
		if _pointer_id == -2:
			_pointer_id = id
			queue_redraw()
	elif _pointer_id == id:
		_pointer_id = -2
		queue_redraw()
		if not canceled and Rect2(Vector2.ZERO, size).has_point(pos):
			pressed.emit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		_pointer_id = -2
		queue_redraw()
