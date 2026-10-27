class_name VolumeSlider
extends Control

signal value_changed(val: float)

var value: float = 0.8
var label_font: Font
var accent_color := Color("#f2b134")
var fill_color := Color("#e23b30")
var track_bg := Color(0.12, 0.14, 0.17, 0.90)
var track_border := Color(1.0, 1.0, 1.0, 0.10)
var text_color := Color(0.85, 0.88, 0.90)

var _dragging := false
var _hover := false
var _anim_drag := 0.0
var _pointer_id := -999


func _ready() -> void:
	custom_minimum_size = Vector2(0, 48)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_entered.connect(func(): _hover = true; queue_redraw())
	mouse_exited.connect(func(): _hover = false; queue_redraw())
	set_process(true)


func set_value(v: float) -> void:
	var clamped := clampf(v, 0.0, 1.0)
	if absf(clamped - value) > 0.001:
		value = clamped
		queue_redraw()
		value_changed.emit(value)


func set_value_no_signal(v: float) -> void:
	var clamped := clampf(v, 0.0, 1.0)
	if absf(clamped - value) > 0.001:
		value = clamped
		queue_redraw()


func _process(delta: float) -> void:
	var target := 1.0 if (_dragging or _hover) else 0.0
	if absf(_anim_drag - target) > 0.005:
		_anim_drag = lerpf(_anim_drag, target, minf(1.0, delta * 14.0))
		queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_pointer_id = event.index
			_dragging = true
			_update_from_pos(event.position.x)
			accept_event()
		elif event.index == _pointer_id:
			_dragging = false
			_pointer_id = -999
			accept_event()
	elif event is InputEventScreenDrag and _dragging and event.index == _pointer_id:
		_update_from_pos(event.position.x)
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pointer_id = -1
			_dragging = true
			_update_from_pos(event.position.x)
			accept_event()
		else:
			_dragging = false
			_pointer_id = -999
			accept_event()
	elif event is InputEventMouseMotion and _dragging and _pointer_id == -1:
		_update_from_pos(event.position.x)
		accept_event()


func _update_from_pos(px: float) -> void:
	var left_pad := 14.0
	var right_pad := 64.0
	var track_w := maxf(10.0, size.x - left_pad - right_pad)
	var new_val := clampf((px - left_pad) / track_w, 0.0, 1.0)
	# Snap to 5% increments for clean feeling
	new_val = roundf(new_val * 20.0) / 20.0
	if absf(new_val - value) > 0.001:
		value = new_val
		queue_redraw()
		value_changed.emit(value)


func _draw() -> void:
	var h := size.y
	var cy := h * 0.5
	var left_pad := 14.0
	var right_pad := 64.0
	var track_w := maxf(10.0, size.x - left_pad - right_pad)
	var track_h := 10.0
	var track_rect := Rect2(left_pad, cy - track_h * 0.5, track_w, track_h)
	var track_rad := 5.0

	# 1. Track trough & subtle border
	Art.rr(self, track_rect, track_bg, track_rad)
	Art.rr(self, Rect2(track_rect.position.x, track_rect.position.y + 1, track_rect.size.x, 2), Color(0, 0, 0, 0.45), 1.0)

	# 2. Filled track
	var fill_w := track_w * value
	if fill_w > 2.0:
		var fill_rect := Rect2(left_pad, cy - track_h * 0.5, fill_w, track_h)
		var col := fill_color.lerp(accent_color, 0.65)
		Art.rr(self, fill_rect, col, track_rad)
		# Highlight line on top of fill
		Art.rr(self, Rect2(left_pad + 2, cy - track_h * 0.5 + 1, maxf(1.0, fill_w - 4), 2), Color(1, 1, 1, 0.35), 1.0)

	# 3. Knob
	var knob_x := left_pad + fill_w
	var knob_pos := Vector2(knob_x, cy)
	var base_rad := 12.0
	var cur_rad := base_rad + _anim_drag * 2.5

	# Knob drop shadow
	draw_circle(knob_pos + Vector2(0, 2), cur_rad, Color(0, 0, 0, 0.35))

	# Knob outer glow when dragging
	if _anim_drag > 0.01:
		draw_circle(knob_pos, cur_rad + 4.0 * _anim_drag, Color(accent_color.r, accent_color.g, accent_color.b, 0.28 * _anim_drag))

	# Knob surface
	draw_circle(knob_pos, cur_rad, Color(0.96, 0.96, 0.98))
	draw_circle(knob_pos, cur_rad, Color(0.65, 0.70, 0.75, 0.20)) # bevel
	# Center pip
	var pip_col := accent_color.lerp(fill_color, 0.3)
	draw_circle(knob_pos, 4.2 + _anim_drag * 0.8, pip_col)

	# 4. Percentage label
	if label_font:
		var pct_str := "%d%%" % int(round(value * 100.0))
		var fs := 18
		var tw := label_font.get_string_size(pct_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		var tx := size.x - 12.0 - tw
		var ty := cy + fs * 0.35
		var col_txt := text_color if value > 0.01 else Color(0.48, 0.52, 0.55)
		draw_string(label_font, Vector2(tx, ty), pct_str, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, col_txt)
