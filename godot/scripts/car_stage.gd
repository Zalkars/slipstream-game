class_name CarStage
extends Control

# Garage showcase: a large, clean car on a lit turntable.
#
# The car itself is a procedural 3D model (see car_model.gd) rendered into a
# transparent SubViewport and composited over the 2D room. The 2D pass still
# paints the room, the light cone, the podium and the contact shadow, so the
# stage keeps its painted look while the car gets real volume, wheels and
# shading. The viewport only re-renders while the model is fresh: the car does
# not animate in 3D, only the 2D bob, so a menu stays cheap.

const MODEL := preload("res://scripts/car_model.gd")

const VP_W := 760
const VP_H := 600

var car: Dictionary = {}
var _t := 0.0
var _ring := 0.0
# QA hook: freeze the animation / hide the contact shadow for a repeatable shot.
var shadow_off := false

var _vp: SubViewport
var _cam: Camera3D
var _model: Node3D
var _warm := 10
var _sig := ""


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_viewport()
	set_process(true)


func _build_viewport() -> void:
	_vp = SubViewport.new()
	_vp.name = "CarView"
	_vp.size = Vector2i(VP_W, VP_H)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(_vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.60, 0.68)
	env.ambient_light_energy = 0.16
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.08
	we.environment = env
	_vp.add_child(we)

	var key := DirectionalLight3D.new()
	_vp.add_child(key)
	key.rotation_degrees = Vector3(-46.0, 30.0, 0.0)
	key.light_energy = 0.50
	key.light_color = Color(1.0, 0.97, 0.92)

	var fill := DirectionalLight3D.new()
	_vp.add_child(fill)
	fill.rotation_degrees = Vector3(-22.0, -62.0, 0.0)
	fill.light_energy = 0.18
	fill.light_color = Color(0.72, 0.82, 1.0)

	var rim := DirectionalLight3D.new()
	_vp.add_child(rim)
	rim.rotation_degrees = Vector3(-26.0, 196.0, 0.0)
	rim.light_energy = 0.40
	rim.light_color = Color(0.95, 0.96, 1.0)

	# low bounce so the flanks and the nose are not pure black
	var bounce := DirectionalLight3D.new()
	_vp.add_child(bounce)
	bounce.rotation_degrees = Vector3(-9.0, 124.0, 0.0)
	bounce.light_energy = 0.07
	bounce.light_color = Color(1.0, 0.95, 0.88)

	_cam = Camera3D.new()
	_cam.fov = 28.0
	_vp.add_child(_cam)
	_cam.current = true

	_model = MODEL.new()
	_vp.add_child(_model)


func _process(delta: float) -> void:
	_t += delta
	_ring += delta * 0.42
	if _warm > 0:
		_warm -= 1
		if _warm == 0 and _vp != null:
			# the 3D car is static: render it once and keep the texture
			_vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	_sync_car()
	queue_redraw()


# Test hook: put the animation on an exact phase so renders are repeatable.
func set_time(t: float) -> void:
	_t = t
	_ring = t * 0.42
	_sync_car()
	queue_redraw()


func _sync_car() -> void:
	if _model == null or car.is_empty():
		return
	var sig := "%s|%s|%s|%s" % [
		str(car.get("silhouette", "sedan")),
		str(car.get("color", "#b32b26")),
		str(car.get("stripe", false)),
		str(car.get("stripe_color", "#f0ede4")),
	]
	if sig == _sig:
		return
	_sig = sig
	_model.show_car(car)
	_frame_camera()
	_warm = 10
	if _vp != null:
		_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS


func _frame_camera() -> void:
	var bb: AABB = _model.bounds()
	var c := bb.get_center()
	var radius := maxf(0.5, bb.size.length() * 0.5)
	var az := deg_to_rad(22.0)
	var el := deg_to_rad(25.0)
	var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	var half_v := deg_to_rad(_cam.fov * 0.5)
	var half_h := atan(tan(half_v) * float(VP_W) / float(VP_H))
	var half := minf(half_v, half_h)
	_cam.position = c + dir * (radius / sin(half) * 0.66)
	_cam.look_at(c, Vector3.UP)


# --- geometry, in one place ------------------------------------------------

func car_width() -> float:
	return size.x * 0.80


func car_height() -> float:
	return car_width() * 0.70


func podium_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.71)


func car_center() -> Vector2:
	return Vector2(size.x * 0.5, size.y * 0.47 + sin(_t * 1.25) * 2.0)


# Where the tyres touch the floor.
func ground_point() -> Vector2:
	return podium_center() + Vector2(0.0, size.y * 0.012)


func shadow_center() -> Vector2:
	return ground_point() + Vector2(0.0, -size.y * 0.004)


# --- drawing ---------------------------------------------------------------

func _draw() -> void:
	_sync_car()
	_draw_room()
	_draw_beam()
	_draw_podium()
	if not shadow_off:
		_draw_contact_shadow()
	_draw_car()


# Dark showroom with a gentle wall-to-floor gradient.
func _draw_room() -> void:
	Art.rr(self, Rect2(Vector2.ZERO, size), Color("#0b0e11"), 28)
	Fx.vgrad(self, Rect2(Vector2.ZERO, Vector2(size.x, size.y * 0.78)),
		Color(0.090, 0.100, 0.115), Color(0.025, 0.030, 0.035))
	# floor: a barely visible warm strip, so the podium has something to stand on
	Fx.vgrad(self, Rect2(0.0, size.y * 0.68, size.x, size.y * 0.32),
		Color(0.030, 0.032, 0.036, 0.0), Color(0.016, 0.018, 0.021))


# Cone of light from a fixture above the frame.
func _draw_beam() -> void:
	var c := size * 0.5
	var bw0 := size.x * 0.075
	var bw1 := size.x * 0.345
	var by0 := -size.y * 0.04
	var by1 := size.y * 0.68
	var bands := 14
	for i in range(bands):
		var k0 := float(i) / float(bands)
		var k1 := float(i + 1) / float(bands)
		var w0 := lerpf(bw0, bw1, k0)
		var w1 := lerpf(bw0, bw1, k1)
		var y0 := lerpf(by0, by1, k0)
		var y1 := lerpf(by0, by1, k1)
		var a := 0.16 * lerpf(1.35, 0.30, (k0 + k1) * 0.5) / float(bands)
		draw_colored_polygon(PackedVector2Array([
			Vector2(c.x - w0, y0), Vector2(c.x + w0, y0),
			Vector2(c.x + w1, y1), Vector2(c.x - w1, y1),
		]), Color(0.86, 0.89, 0.93, a))


# Points along a perspective ellipse: cx,cy centre, rx horizontal, ry vertical.
func _ellipse_pts(cx: float, cy: float, rx: float, ry: float, a0: float, a1: float, steps: int) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in range(steps + 1):
		var a := lerpf(a0, a1, float(i) / float(steps))
		out.push_back(Vector2(cx + cos(a) * rx, cy + sin(a) * ry))
	return out


# Polished turntable in perspective. The fill uses a squashed transform (cheap),
# but the ring details are drawn as real screen-space ellipse polylines: a
# squashed draw_arc stroke collapses to ~1px and simply disappears, while these
# stay a readable 2-3px whatever the aspect ratio.
func _draw_podium() -> void:
	var p := podium_center()
	var rx := size.x * 0.465
	var ry := rx * 0.33
	draw_set_transform(p, 0.0, Vector2(1.0, 0.33))
	draw_circle(Vector2.ZERO, rx, Color(0.032, 0.038, 0.048))
	# soft inner wash so the table reads as a lit surface, not a dark disc
	for i in range(5):
		var k := float(i) / 4.0
		draw_circle(Vector2.ZERO, rx * lerpf(0.96, 0.60, k),
			Color(0.10, 0.11, 0.13, 0.12))
	# pool of light from the beam landing on the table
	for i in range(7):
		var k := float(i) / 6.0
		draw_circle(Vector2.ZERO, rx * lerpf(0.80, 0.16, k),
			Color(0.40, 0.45, 0.52, 0.032))
	draw_set_transform(Vector2.ZERO)
	# bright rim and an inner seam
	draw_polyline(_ellipse_pts(p.x, p.y, rx * 0.985, ry * 0.985, 0.0, TAU, 96),
		Color(1, 1, 1, 0.14), 3.0, true)
	draw_polyline(_ellipse_pts(p.x, p.y, rx * 0.760, ry * 0.760, 0.0, TAU, 80),
		Color(1, 1, 1, 0.06), 2.0, true)
	# rotating warm dashes as short chords, drawn in screen space so they keep
	# their thickness on the flattened (top/bottom) parts of the ellipse
	var band := rx * 0.875
	var band_ry := band * 0.33
	for i in range(28):
		var a0 := _ring + TAU * float(i) / 28.0 - 0.040
		var a1 := a0 + 0.080
		var p0 := Vector2(p.x + cos(a0) * band, p.y + sin(a0) * band_ry)
		var p1 := Vector2(p.x + cos(a1) * band, p.y + sin(a1) * band_ry)
		draw_line(p0, p1, Color(0.95, 0.72, 0.28, 0.34), 3.0, true)
	# sheen along the front edge, away from the light
	draw_polyline(_ellipse_pts(p.x, p.y, rx * 0.93, ry * 0.93, PI * 0.18, PI * 0.82, 48),
		Color(1, 1, 1, 0.10), 3.0, true)


# Soft contact shadow under the tyres: widest and faintest first, narrowing to
# a dark core. Painted before the car, so the car hides the hard centre.
func _draw_contact_shadow() -> void:
	var c := shadow_center()
	var w := car_width()
	var layers := 9
	for i in range(layers):
		var k := 1.0 - float(i) / float(layers - 1)  # 1 = outermost
		var spread := lerpf(0.44, 0.70, k)
		var alpha := lerpf(0.42, 0.0, pow(k, 0.9))
		draw_set_transform(c, 0.0, Vector2(1.0, 0.27))
		draw_circle(Vector2.ZERO, w * spread, Color(0.010, 0.010, 0.016, alpha))
	draw_set_transform(Vector2.ZERO)


func _draw_car() -> void:
	if _vp == null or _cam == null or _model == null:
		return
	var w := size.x * 0.86
	var h := w * float(VP_H) / float(VP_W)
	# pin the tyre contact patch to the podium, wherever the camera put it
	var gp := _cam.unproject_position(Vector3.ZERO)
	var k := Vector2(w, h) / Vector2(VP_W, VP_H)
	var pos := ground_point() - gp * k
	draw_texture_rect(_vp.get_texture(), Rect2(pos, Vector2(w, h)), false)
