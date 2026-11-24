extends Control

signal car_picked(index: int)

const NO_POINTER := -2
const DRAG_THRESHOLD := 14.0
const FRICTION := 6.5
const MAX_SPEED := 1850.0

var _scroll := ScrollContainer.new()
var _rail := HBoxContainer.new()
var _pointer := NO_POINTER
var _pressed_at := Vector2.ZERO
var _scroll_at_press := 0
var _pressed_index := -1
var _selected_index := 0
var _dragged := false
var _last_motion_us := 0
var _last_x := 0.0
var _offset := 0.0
var _velocity := 0.0
var _motion: Tween
var _trackpad_target := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	_scroll.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.add_theme_constant_override("separation", 9)
	add_child(_scroll)
	_scroll.add_child(_rail)
	_scroll.get_h_scroll_bar().changed.connect(_reveal_selected.call_deferred)
	set_process(false)


func add_tile(tile: Button) -> void:
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.add_child(tile)


func reveal_tile(index: int) -> void:
	_stop_motion()
	_selected_index = index
	if index >= _rail.get_child_count():
		return
	var tile := _rail.get_child(index) as Control
	var left := float(_scroll.scroll_horizontal)
	var right := left + _scroll.size.x
	if tile.position.x < left or tile.position.x + tile.size.x > right:
		_animate_scroll(tile.position.x - (_scroll.size.x - tile.size.x) * 0.5, 0.32)


func _reveal_selected() -> void:
	if _pointer == NO_POINTER and _selected_index < _rail.get_child_count():
		_scroll.ensure_control_visible(_rail.get_child(_selected_index) as Control)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_contact(event.index, event.position, event.pressed, event.canceled)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	elif event is InputEventPanGesture:
		var amount: Vector2 = event.delta
		var start := _trackpad_target if _motion != null and _motion.is_running() else float(_scroll.scroll_horizontal)
		_trackpad_target = clampf(start + (amount.x if not is_zero_approx(amount.x) else amount.y) * 42.0, 0, _scroll_limit())
		_animate_scroll(_trackpad_target, 0.14, true)
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if Input.emulate_touch_from_mouse or event.device == InputEvent.DEVICE_ID_EMULATION:
					return
				_contact(-1, event.position, event.pressed, event.canceled)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				if event.pressed:
					_scroll_wheel(-1)
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				if event.pressed:
					_scroll_wheel(1)
			_:
				return
	elif event is InputEventMouseMotion:
		_drag(-1, event.position)
	else:
		return
	accept_event()


func _contact(id: int, point: Vector2, pressed: bool, canceled: bool) -> void:
	if pressed and not canceled and _pointer == NO_POINTER:
		_stop_motion()
		_pointer = id
		_pressed_at = point
		_scroll_at_press = _scroll.scroll_horizontal
		_offset = float(_scroll_at_press)
		_last_x = point.x
		_last_motion_us = Time.get_ticks_usec()
		_pressed_index = _index_at(point)
		_dragged = false
	elif id == _pointer and (not pressed or canceled):
		_pointer = NO_POINTER
		if _dragged:
			if canceled or Time.get_ticks_usec() - _last_motion_us > 105000 or absf(_velocity) < 70.0:
				_snap_scroll()
			else:
				_offset = float(_scroll.scroll_horizontal)
				set_process(true)
		elif not canceled and _pressed_index >= 0 and _pressed_index == _index_at(point):
			car_picked.emit(_pressed_index)


func _drag(id: int, point: Vector2) -> void:
	if id != _pointer:
		return
	var movement := point - _pressed_at
	_dragged = _dragged or movement.length() >= DRAG_THRESHOLD
	if _dragged:
		_set_scroll(_scroll_at_press - movement.x)
	var now := Time.get_ticks_usec()
	var seconds := maxf(float(now - _last_motion_us) / 1000000.0, 0.004)
	var instantaneous := clampf((_last_x - point.x) / seconds, -MAX_SPEED, MAX_SPEED)
	_velocity = lerpf(_velocity, instantaneous, 1.0 - exp(-seconds * 29.0))
	_last_motion_us = now
	_last_x = point.x


func _process(delta: float) -> void:
	var next_velocity := _velocity * exp(-delta * FRICTION)
	var predicted := _offset + (_velocity - next_velocity) / FRICTION
	_offset = clampf(predicted, 0.0, _scroll_limit())
	_set_scroll(_offset)
	_velocity = next_velocity
	if not is_equal_approx(predicted, _offset) or absf(_velocity) < 55.0:
		_snap_scroll()


func _scroll_limit() -> float:
	var scroll_bar := _scroll.get_h_scroll_bar()
	return maxf(scroll_bar.max_value - scroll_bar.page, 0.0)


func _set_scroll(offset: float) -> void:
	_scroll.scroll_horizontal = roundi(clampf(offset, 0.0, _scroll_limit()))


func _nearest_snap(offset: float) -> float:
	var limit := _scroll_limit()
	var best := 0.0 if offset < limit * 0.5 else limit
	for child in _rail.get_children():
		var tile := child as Control
		var candidate := clampf(tile.position.x, 0.0, limit)
		if absf(candidate - offset) < absf(best - offset):
			best = candidate
	return best


func _snap_scroll() -> void:
	_animate_scroll(_nearest_snap(_scroll.scroll_horizontal), 0.19)


func _scroll_wheel(direction: int) -> void:
	if _rail.get_child_count() == 0:
		return
	var tile := _rail.get_child(0) as Control
	var stride := tile.size.x + _rail.get_theme_constant("separation")
	var start := _trackpad_target if _motion != null and _motion.is_running() else float(_scroll.scroll_horizontal)
	_trackpad_target = _nearest_snap(clampf(start + stride * direction, 0.0, _scroll_limit()))
	_animate_scroll(_trackpad_target, 0.24)


func _animate_scroll(offset: float, seconds: float, snap_when_done := false) -> void:
	_stop_motion()
	var target := clampf(offset, 0.0, _scroll_limit())
	_trackpad_target = target
	var start := float(_scroll.scroll_horizontal)
	if absf(start - target) < 1.0:
		return
	_motion = create_tween()
	_motion.tween_method(_set_scroll, start, target, seconds).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	if snap_when_done:
		_motion.finished.connect(_snap_scroll)


func _stop_motion() -> void:
	if _motion != null:
		_motion.kill()
		_motion = null
	_velocity = 0.0
	set_process(false)


func _index_at(point: Vector2) -> int:
	if not Rect2(Vector2.ZERO, size).has_point(point):
		return -1
	var global_point := get_global_transform() * point
	for tile in _rail.get_children():
		if (tile as Control).get_global_rect().has_point(global_point):
			return tile.get_index()
	return -1


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_FOCUS_OUT or (what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree()):
		_pointer = NO_POINTER
		_stop_motion()
