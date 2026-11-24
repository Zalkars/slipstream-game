class_name CarStage
extends Control

# Interactive garage view. The room is drawn on the canvas and the car uses
# the same procedural model as the race atlas. An idle view costs no 3D frames.
const MODEL := preload("res://scripts/car_model.gd")
const VP_W := 760
const VP_H := 540
const FRONT := Vector2(32.0, 22.0)
const SIDE := Vector2(90.0, 22.0)
const REAR := Vector2(148.0, 22.0)
const NO_DRAG := -2
const ROOM_SIZE := Vector2(656.0, 500.0)
const WARM_LIGHT := Color("#ff966a")
const COOL_LIGHT := Color("#a4a3ff")

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
var _camera_distance := 1.0
var _shown_car: Dictionary = {}
var _angles := FRONT
var _orbit: Tween
var _drag_id := NO_DRAG
var _last_drag := Vector2.ZERO
var _plate := StyleBoxFlat.new()
var _shadow: GradientTexture2D
var _warm_glow: GradientTexture2D
var _cool_glow: GradientTexture2D
var _room_grain: ImageTexture


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	mouse_default_cursor_shape = Control.CURSOR_DRAG
	clip_contents = true
	_plate.bg_color = Color("#181c29")
	_plate.border_color = Color("#596475")
	_plate.set_border_width_all(2)
	_plate.set_corner_radius_all(28)
	_shadow = _falloff_texture(Color("#08080ed2"))
	_warm_glow = _falloff_texture(Color(WARM_LIGHT, 0.51))
	_cool_glow = _falloff_texture(Color(COOL_LIGHT, 0.50))
	_room_grain = _make_room_grain()
	_build_viewport()
	_sync_car()


func _falloff_texture(tint: Color) -> GradientTexture2D:
	var falloff := Gradient.new()
	falloff.set_color(0, tint)
	falloff.set_color(1, Color(tint, 0.0))
	falloff.add_point(0.5, Color(tint, tint.a * 0.45))
	falloff.add_point(0.8, Color(tint, tint.a * 0.12))
	var texture := GradientTexture2D.new()
	texture.gradient = falloff
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	return texture


func _make_room_grain() -> ImageTexture:
	var random := RandomNumberGenerator.new()
	random.seed = 723
	var image := Image.create_empty(172, 132, false, Image.FORMAT_RGBA8)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			var brightness := random.randf()
			var tint := Color(0.77, 0.73, 0.83) if brightness >= 0.5 else Color(0.02, 0.02, 0.03)
			tint.a = absf(brightness - 0.5) * 0.055
			image.set_pixel(x, y, tint)
	return ImageTexture.create_from_image(image)


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
	# Fit the turntable once from the horizontal footprint. Both the projection
	# and the canvas scale stay fixed throughout the orbit.
	var footprint := Vector2(_bounds.size.x, _bounds.size.z)
	_camera_distance = maxf(5.0, footprint.length() * 1.675)
	if _orbit != null:
		_orbit.kill()
	_angles = FRONT
	_frame_camera()


func set_view(angles: Vector2) -> void:
	if _orbit != null:
		_orbit.kill()
	var target := Vector2(_angles.x + wrapf(angles.x - _angles.x, -180.0, 180.0), FRONT.y)
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
	_cam.position = center + dir * _camera_distance
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
	var movement := pos.x - _last_drag.x
	_last_drag = pos
	if not is_zero_approx(movement):
		_set_angles(Vector2(fposmod(_angles.x - movement * 0.65, 360.0), _angles.y))


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
	_draw_room()
	if _shown_car.is_empty():
		return
	var contact := size * Vector2(0.5, 0.69)
	var projected_ground := _cam.unproject_position(Vector3(_bounds.get_center().x, 0.02, _bounds.get_center().z))
	var scale2d := minf(size.x * 1.02, size.y * 1.43) / float(VP_W)
	var texture_size := Vector2(VP_W, VP_H) * scale2d
	var width := minf(texture_size.x, size.x)
	var shadow_size := Vector2(width * 0.87, width * 0.25)
	draw_texture_rect(_shadow, Rect2(contact - shadow_size * 0.5, shadow_size), false)
	draw_texture_rect(_vp.get_texture(), Rect2(contact - projected_ground * scale2d, texture_size), false)


func _draw_room() -> void:
	draw_set_transform(Vector2.ZERO, 0, size / ROOM_SIZE)
	Fx.vgrad(self, Rect2(2, 20, 652, 263), Color("#151928"), Color("#2c2b40"))
	Fx.vgrad(self, Rect2(2, 283, 652, 196), Color("#302938"), Color("#181b28"))
	draw_texture_rect(_warm_glow, Rect2(2, 42, 326, 416), false)
	draw_texture_rect(_cool_glow, Rect2(328, 42, 326, 416), false)

	draw_colored_polygon(PackedVector2Array([Vector2(103, 101), Vector2(553, 101),
		Vector2(485, 144), Vector2(171, 144)]), Color("#141823"))
	Fx.vgrad(self, Rect2(173, 144, 310, 138), Color("#242937"), Color("#191d2a"))
	for x in [193, 260, 328, 396, 463]:
		draw_line(Vector2(x, 145), Vector2(x, 282), Color("#ffffff18"), 1.0, true)
	draw_line(Vector2(174, 146), Vector2(482, 146), Color("#ffffff28"), 2.0, true)
	draw_line(Vector2(173, 220), Vector2(483, 220), Color("#101522"), 2.0, true)

	for x in [3, 128, 252, 404, 528, 653]:
		draw_line(Vector2(lerpf(328, float(x), 0.43), 283), Vector2(x, 477),
			Color("#abb2cf27"), 1.0, true)
	for y in [300, 319, 351, 400, 466]:
		draw_line(Vector2(2, y), Vector2(654, y), Color("#a1aec526"), 1.0, true)
	draw_line(Vector2(2, 283), Vector2(654, 283), Color("#111623"), 7.0, true)
	draw_line(Vector2(2, 287), Vector2(654, 287), Color("#84839e64"), 1.0, true)

	for side in [-1.0, 1.0]:
		var tint := WARM_LIGHT if side < 0 else COOL_LIGHT
		_room_side(side, tint)
	draw_set_transform(Vector2.ZERO, 0, size / ROOM_SIZE)
	draw_texture_rect(_room_grain, Rect2(4, 25, 648, 450), false)
	Fx.vgrad(self, Rect2(3, 22, 650, 105), Color("#11131d78"), Color("#11131d00"))
	Fx.vgrad(self, Rect2(3, 442, 650, 35), Color("#181b2800"), Color("#181b28"))
	draw_set_transform(Vector2.ZERO)


func _room_side(side: float, tint: Color) -> void:
	draw_set_transform(Vector2(328, 0) * size / ROOM_SIZE, 0, size / ROOM_SIZE * Vector2(side, 1))
	draw_colored_polygon(PackedVector2Array([Vector2(233, 97), Vector2(267, 97),
		Vector2(217, 282), Vector2(188, 282)]), Color("#282c39"))
	draw_line(Vector2(233, 97), Vector2(188, 282), Color("#c6c7e447"), 1.5, true)
	draw_colored_polygon(PackedVector2Array([Vector2(148, 129), Vector2(164, 129),
		Vector2(143, 282), Vector2(126, 282)]), Color("#1b1e2c"))
	for y in [125, 245]:
		var points := PackedVector2Array([Vector2(154, y + 17), Vector2(223, y), Vector2(321, y)])
		draw_polyline(points, Color(tint, 0.14), 11.0, true)
		draw_polyline(points, Color(tint, 0.43), 5.0, true)
		draw_polyline(points, tint, 2.0, true)
	Fx.vgrad(self, Rect2(177, 290, 136, 39), Color(tint, 0.2), Color(tint, 0))
	draw_line(Vector2(190, 294), Vector2(308, 294), Color(tint, 0.18), 2.0, true)
	draw_polyline(PackedVector2Array([Vector2(134, 310), Vector2(226, 425), Vector2(175, 425)]),
		Color(tint, 0.53), 2.0, true)
