extends Control

signal car_picked(index: int)

const NO_POINTER := -2
const DRAG_THRESHOLD := 14.0

var _scroll := ScrollContainer.new()
var _rail := HBoxContainer.new()
var _pointer := NO_POINTER
var _pressed_at := Vector2.ZERO
var _scroll_at_press := 0
var _pressed_index := -1
var _selected_index := 0
var _dragged := false


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


func add_tile(tile: Button) -> void:
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rail.add_child(tile)


func reveal_tile(index: int) -> void:
	_selected_index = index
	_reveal_selected()


func _reveal_selected() -> void:
	if _selected_index < _rail.get_child_count():
		_scroll.ensure_control_visible(_rail.get_child(_selected_index) as Control)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_contact(event.index, event.position, event.pressed, event.canceled)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	elif event is InputEventPanGesture:
		var amount: Vector2 = event.delta
		_scroll.scroll_horizontal += roundi((amount.x if not is_zero_approx(amount.x) else amount.y) * 42.0)
	elif event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				if Input.emulate_touch_from_mouse or event.device == InputEvent.DEVICE_ID_EMULATION:
					return
				_contact(-1, event.position, event.pressed, event.canceled)
			MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_LEFT:
				_scroll.scroll_horizontal -= roundi(event.factor * 130.0)
			MOUSE_BUTTON_WHEEL_DOWN, MOUSE_BUTTON_WHEEL_RIGHT:
				_scroll.scroll_horizontal += roundi(event.factor * 130.0)
			_:
				return
	elif event is InputEventMouseMotion:
		_drag(-1, event.position)
	else:
		return
	accept_event()


func _contact(id: int, point: Vector2, pressed: bool, canceled: bool) -> void:
	if pressed and not canceled and _pointer == NO_POINTER:
		_pointer = id
		_pressed_at = point
		_scroll_at_press = _scroll.scroll_horizontal
		_pressed_index = _index_at(point)
		_dragged = false
	elif id == _pointer and (not pressed or canceled):
		_pointer = NO_POINTER
		if not canceled and not _dragged and _pressed_index >= 0 and _pressed_index == _index_at(point):
			car_picked.emit(_pressed_index)


func _drag(id: int, point: Vector2) -> void:
	if id != _pointer:
		return
	var movement := point - _pressed_at
	_dragged = _dragged or movement.length() >= DRAG_THRESHOLD
	if _dragged:
		_scroll.scroll_horizontal = _scroll_at_press - roundi(movement.x)


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
