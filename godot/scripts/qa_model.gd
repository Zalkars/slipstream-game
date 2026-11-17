extends SceneTree

# QA sheet: one car from several angles at high resolution, so panel shapes,
# shut lines and lighting can be judged without the garage backdrop.

const MODEL := preload("res://scripts/car_model.gd")
const W := 720
const H := 520
const COLS := 2

var _vp: SubViewport
var _cam: Camera3D
var _model: Node3D
var _bb := AABB()


func _initialize() -> void:
	call_deferred("_run")


func _build() -> void:
	_vp = SubViewport.new()
	_vp.size = Vector2i(W, H)
	_vp.transparent_bg = false
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(_vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.10, 0.11, 0.125)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.58, 0.63, 0.72)
	env.ambient_light_energy = 0.34
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.06
	we.environment = env
	_vp.add_child(we)

	var key := DirectionalLight3D.new()
	_vp.add_child(key)
	key.rotation_degrees = Vector3(-42.0, 34.0, 0.0)
	key.light_energy = 0.95
	key.light_color = Color(1.0, 0.97, 0.92)
	var fill := DirectionalLight3D.new()
	_vp.add_child(fill)
	fill.rotation_degrees = Vector3(-18.0, -68.0, 0.0)
	fill.light_energy = 0.30
	fill.light_color = Color(0.72, 0.82, 1.0)
	var rim := DirectionalLight3D.new()
	_vp.add_child(rim)
	rim.rotation_degrees = Vector3(-24.0, 198.0, 0.0)
	rim.light_energy = 0.55
	rim.light_color = Color(0.95, 0.96, 1.0)

	_cam = Camera3D.new()
	_cam.fov = 24.0
	_vp.add_child(_cam)
	_cam.current = true

	_model = MODEL.new()
	_vp.add_child(_model)

	# ground, so the car is not floating in a void
	var gm := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(24, 24)
	gm.mesh = pm
	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.075, 0.08, 0.09)
	gmat.roughness = 0.9
	gm.material_override = gmat
	_vp.add_child(gm)


func _place(az_deg: float, el_deg: float) -> void:
	var c := _bb.get_center()
	var radius := maxf(1.0, _bb.size.length() * 0.5)
	var az := deg_to_rad(az_deg)
	var el := deg_to_rad(el_deg)
	var dir := Vector3(sin(az) * cos(el), sin(el), cos(az) * cos(el))
	var half_v := deg_to_rad(_cam.fov * 0.5)
	var half_h := atan(tan(half_v) * float(W) / float(H))
	var half := minf(half_v, half_h)
	_cam.position = c + dir * (radius / sin(half) * 0.62)
	_cam.look_at(c, Vector3.UP)


func _capture() -> Image:
	await process_frame
	await process_frame
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	return _vp.get_texture().get_image()


func _run() -> void:
	_build()
	var idx := 0
	var out_name := "qa_model"
	var args := OS.get_cmdline_user_args()
	for a in args:
		if a.begins_with("--car="):
			idx = int(a.split("=")[1])
		if a.begins_with("--out="):
			out_name = a.split("=")[1]
	var car: Dictionary = Cars.get_car(idx)
	var model_car := {
		"silhouette": car.silhouette,
		"color": car.color,
		"stripe": bool(car.stripe),
		"stripe_color": car.stripe_color,
	}
	_model.show_car(model_car)
	await process_frame
	_bb = _model.bounds()

	var views := [
		[26.0, 14.0], [90.0, 9.0], [154.0, 15.0], [26.0, 46.0],
	]
	var rows := int(ceil(float(views.size()) / float(COLS)))
	var sheet := Image.create(W * COLS, H * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.08, 0.085, 0.095, 1.0))
	for i in range(views.size()):
		var v: Array = views[i]
		_place(float(v[0]), float(v[1]))
		var img := await _capture()
		var x := int(i % COLS) * W
		var y := int(i / COLS) * H
		sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(x, y))
	var path := ProjectSettings.globalize_path("res://shots/%s.png" % out_name)
	sheet.save_png(path)
	print("[qa] wrote ", path, " ", sheet.get_size())
	quit(0)
