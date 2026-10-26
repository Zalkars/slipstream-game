class_name PadButton
extends Control

# Semi-transparent driving pad: left/right chevrons or the brake pedal.
# Left/right auto-repeat while held; brake reports held state.

signal pressed
signal held_changed(on: bool)

var kind := "left"
var label_font: Font
var _down := false
var _repeat := 0.0
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(108, 108)
	set_process(true)


func reset() -> void:
	var was := _down
	_down = false
	if kind == "brake" and was:
		held_changed.emit(false)
	queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	if kind != "brake" and _down:
		_repeat -= delta
		if _repeat <= 0.0:
			pressed.emit()
			_repeat = 0.15
		queue_redraw()
	elif _down:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 2.0
	var base_alpha := 0.46 if _down else 0.34
	var bg := Color(0.03, 0.04, 0.05, base_alpha)
	if kind == "brake" and _down:
		bg = Color(0.42, 0.24, 0.06, 0.55)
	draw_circle(c, r + 2.0, Color(0, 0, 0, 0.20))
	draw_circle(c, r, bg)
	draw_arc(c, r - 1.0, 0.0, TAU, 48, Color(1, 1, 1, 0.16 if _down else 0.12), 1.6, true)
	draw_circle(c, r * 0.78, Color(1, 1, 1, 0.035 if not _down else 0.07))

	if kind == "left" or kind == "right":
		var dir := -1.0 if kind == "left" else 1.0
		var col := Color(1, 1, 1, 0.94 if _down else 0.84)
		var w := r * 0.22
		var h := r * 0.36
		var cx := c.x + dir * r * 0.04
		draw_polyline(
			PackedVector2Array([
				Vector2(cx - dir * w, c.y - h),
				Vector2(cx + dir * w * 0.7, c.y),
				Vector2(cx - dir * w, c.y + h),
			]),
			col, r * 0.13, true
		)
		if _down:
			draw_arc(c, r * 0.86, 0.0, TAU, 40, Color(1, 1, 1, 0.10), 2.0, true)
	else:
		var col := Color(1, 0.90, 0.62, 0.98) if _down else Color(0.95, 0.95, 0.94, 0.88)
		var pr := Rect2(c.x - r * 0.36, c.y - r * 0.52, r * 0.72, r * 0.50)
		Art.rr(self, pr, col, r * 0.13)
		for i in range(3):
			var ly := c.y - r * 0.38 + float(i) * r * 0.13
			draw_line(Vector2(c.x - r * 0.22, ly), Vector2(c.x + r * 0.22, ly), Color(0.10, 0.11, 0.12, 0.50), 2.0, true)
		if label_font:
			var txt := "ТОРМОЗ"
			var fs := 15
			var tw := label_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
			draw_string(label_font, c + Vector2(-tw * 0.5, r * 0.70), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col)
		if _down:
			var p := 0.5 + 0.5 * sin(_pulse * 8.0)
			draw_arc(c, r - 3.0, 0.0, TAU, 48, Color(1, 0.65, 0.25, 0.20 + p * 0.20), 2.5, true)


func _press() -> void:
	if _down:
		return
	_down = true
	_repeat = 0.28
	if kind == "brake":
		held_changed.emit(true)
	else:
		pressed.emit()
	queue_redraw()


func _release() -> void:
	if not _down:
		return
	_down = false
	if kind == "brake":
		held_changed.emit(false)
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_press()
		else:
			_release()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press()
		else:
			_release()
