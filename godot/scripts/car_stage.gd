class_name CarStage
extends Control

# Interactive garage view. The room is drawn on the canvas and the car uses
# the same procedural model as the race atlas. An idle view costs no 3D frames.
const MODEL := preload("res://scripts/car_model.gd")
const VP_W := 760
const VP_H := 540
const FRONT := Vector2(32.0, 22.0)
const SIDE := Vector2(90.0, 14.0)
const REAR := Vector2(148.0, 22.0)
const NO_DRAG := -2

var car: Dictionary = {}:
	set(value):
		if car == value:
			return
		car = value
		if is_visible_in_tree():
			_sync_car()

var _vp: SubViewport
var _cam: Camera3D
var _model: Node3D
var _bounds: AABB
var _shown_car: Dictionary = {}
var _angles := FRONT
var _orbit: Tween
var _drag_id := NO_DRAG
var _last_drag := Vector2.ZERO
var _plate := StyleBoxFlat.new()
var _shadow := GradientTexture2D.new()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	clip_contents = true
	_plate.bg_color = Color("#101820")
	_plate.border_color = Color("#394450")
	_plate.set_border_width_all(1)
	_plate.set_corner_radius_all(20)
	var falloff := Gradient.new()
	falloff.set_color(0, Color(0.015, 0.02, 0.026, 0.82))
	falloff.set_color(1, Color(0.015, 0.02, 0.026, 0.0))
	falloff.add_point(0.5, Color(0.015, 0.02, 0.026, 0.44))
	falloff.add_point(0.8, Color(0.015, 0.02, 0.026, 0.10))
	_shadow.gradient = falloff
	_shadow.fill = GradientTexture2D.FILL_RADIAL
	_shadow.fill_from = Vector2(0.5, 0.5)
	_shadow.fill_to = Vector2(1.0, 0.5)
	_build_viewport()
	_sync_car()


func _build_viewport() -> void:
	_vp = SubViewport.new()
	_vp.name = "CarView"
	_vp.size = Vector2i(VP_W, VP_H)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)

	var world := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color.TRANSPARENT
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#bfcbdc")
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	world.environment = env
	_vp.add_child(world)

	_add_light(Vector3(-42.0, 32.0, 0.0), Color("#fff0db"), 0.82)
	_add_light(Vector3(-24.0, -81.0, 0.0), Color("#c0dfff"), 0.38)
	_add_light(Vector3(-35.0, 196.0, 0.0), Color("#f1f6ff"), 0.72)

	_cam = Camera3D.new()
	_cam.fov = 28.0
	_vp.add_child(_cam)
	_cam.current = true
	_model = MODEL.new()
	_vp.add_child(_model)


func _add_light(rotation_deg: Vector3, tint: Color, energy: float) -> void:
	var light := DirectionalLight3D.new()
	light.rotation_degrees = rotation_deg
	light.light_color = tint
	light.light_energy = energy
	_vp.add_child(light)


func _sync_car() -> void:
	if _model == null or car.is_empty() or car == _shown_car:
		return
	_shown_car = car
	_model.show_car(car)
	_bounds = _model.bounds()
	_frame_camera()


func set_view(angles: Vector2) -> void:
	if _orbit != null:
		_orbit.kill()
	var target := Vector2(_angles.x + wrapf(angles.x - _angles.x, -180.0, 180.0), angles.y)
	_orbit = create_tween()
	_orbit.tween_method(_set_angles, _angles, target, 0.26).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)


func _set_angles(angles: Vector2) -> void:
	_angles = angles
	_frame_camera()


func _frame_camera() -> void:
	if _bounds.size == Vector3.ZERO:
		return
	var center := _bounds.get_center()
	var az := deg_to_rad(_angles.x)
	var el := deg_to_rad(_angles.y)
	var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	var tan_v := tan(deg_to_rad(_cam.fov * 0.5))
	var tan_h := tan_v * float(VP_W) / float(VP_H)
	var right := Vector3.UP.cross(dir).normalized()
	var up := dir.cross(right).normalized()
	var distance := 1.0
	for i in range(8):
		var p := _bounds.get_endpoint(i) - center
		var extent := maxf(absf(p.dot(right)) / tan_h, absf(p.dot(up)) / tan_v)
		distance = maxf(distance, p.dot(dir) + extent / 0.89)
	_cam.position = center + dir * distance
	_cam.look_at(center, Vector3.UP)
	if is_visible_in_tree():
		_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	queue_redraw()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_drag_contact(event.index, event.position, event.pressed and not event.canceled)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.emulate_touch_from_mouse or event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		_drag_contact(-1, event.position, event.pressed)
	elif event is InputEventMouseMotion:
		_drag(-1, event.position)
	else:
		return
	accept_event()


func _drag_contact(id: int, pos: Vector2, down: bool) -> void:
	if down and _drag_id == NO_DRAG:
		if _orbit != null:
			_orbit.kill()
		_drag_id = id
		_last_drag = pos
	elif not down and _drag_id == id:
		_drag_id = NO_DRAG


func _drag(id: int, pos: Vector2) -> void:
	if id != _drag_id:
		return
	var movement := pos - _last_drag
	_last_drag = pos
	_set_angles(Vector2(fposmod(_angles.x - movement.x * 0.65, 360.0),
		clampf(_angles.y + movement.y * 0.20, 7.0, 49.0)))


func _notification(what: int) -> void:
	if what != NOTIFICATION_VISIBILITY_CHANGED or _vp == null:
		return
	if is_visible_in_tree():
		_sync_car()
		_frame_camera()
	else:
		_drag_id = NO_DRAG
		if _orbit != null:
			_orbit.kill()
		_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _draw() -> void:
	draw_style_box(_plate, Rect2(Vector2.ZERO, size))
	var horizon := size.y * 0.57
	Fx.vgrad(self, Rect2(2, 20, size.x - 4, horizon - 20),
		Color("#111922"), Color("#24303a"))
	Fx.vgrad(self, Rect2(2, horizon, size.x - 4, size.y - horizon - 18),
		Color("#28323b"), Color("#111820"))
	draw_line(Vector2(2, horizon), Vector2(size.x - 2, horizon), Color("#53616a"), 1.0, true)
	for f in [0.13, 0.32, 0.68, 0.87]:
		var x := size.x * float(f)
		draw_line(Vector2(x, 45.0), Vector2(x, horizon), Color("#303b47"), 2.0, true)
	for side in [-1.0, 1.0]:
		var p := Vector2(size.x * (0.5 + float(side) * 0.34), 61.0)
		var q := p + Vector2(float(side) * 47.0, -20.0)
		draw_line(p, q, Color(0.54, 0.79, 1.0, 0.13), 15.0, true)
		draw_line(p, q, Color("#b7d8ee"), 3.0, true)
		var start := Vector2(size.x * (0.5 + float(side) * 0.20), horizon)
		var end := Vector2(size.x * (0.5 + float(side) * 0.46), size.y - 17.0)
		draw_line(start, end, Color(0.66, 0.75, 0.82, 0.13), 2.0, true)
		var marker := start.lerp(end, 0.83)
		draw_line(marker, marker - Vector2(24.0 * float(side), 0.0), Color("#d08f40"), 3.0, true)
	if _shown_car.is_empty():
		return
	var contact := Vector2(size.x * 0.5, size.y * 0.73)
	var width := minf(size.x * 1.01, size.y * 1.44)
	var scale2d := width / float(VP_W)
	var texture_size := Vector2(VP_W, VP_H) * scale2d
	var projected_ground := _cam.unproject_position(Vector3(_bounds.get_center().x, 0.02, _bounds.get_center().z))
	var shadow_size := Vector2(width * 0.87, width * 0.25)
	draw_texture_rect(_shadow, Rect2(contact - shadow_size * 0.5, shadow_size), false)
	draw_texture_rect(_vp.get_texture(), Rect2(contact - projected_ground * scale2d, texture_size), false)
