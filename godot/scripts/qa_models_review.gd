extends "res://scripts/qa_model.gd"

# Contact sheets for all nine silhouettes, using the production geometry.
# Run with --script res://scripts/qa_models_review.gd (a graphical renderer).
func _run() -> void:
	_build()
	var title := Label.new()
	title.position = Vector2(22, 18)
	title.add_theme_font_size_override("font_size", 24)
	_vp.add_child(title)
	var views := [[32.0, 18.0, "front"], [90.0, 8.0, "side"], [150.0, 20.0, "rear"],
		[0.0, 8.0, "nose"], [180.0, 8.0, "tail"]]
	for view in views:
		var sheet := Image.create(W * 3, H * 3, false, Image.FORMAT_RGBA8)
		for i in range(Cars.LIST.size()):
			var car: Dictionary = Cars.get_car(i)
			_model.show_car(car)
			_bb = _model.bounds()
			if str(view[2]) == "front":
				_validate_geometry(car)
				_validate_arches(car)
				_validate_roof_and_bed(car)
				_validate_wipers(car)
			title.text = car.name
			_place(float(view[0]), float(view[1]))
			# Fit side elevations too; the original single-car QA cropped bumpers.
			var c := _bb.get_center()
			_cam.position = c + (_cam.position - c) * 1.26
			var img := await _capture()
			sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i((i % 3) * W, int(i / 3) * H))
		var path := ProjectSettings.globalize_path("res://shots/models_%s.png" % str(view[2]))
		sheet.save_png(path)
		print("[qa] wrote ", path)
	_validate_cache()
	await _detail_sheets(title)
	await _roof_and_pickup_sheets(title)
	await _wiper_sheets(title)
	await _garage_sheet()
	await _race_sheet()
	quit(0)


func _validate_wipers(car: Dictionary) -> void:
	var front: Array = []
	var rear := 0
	for node in _model._root.get_children():
		if str(node.name).begins_with("FrontWiper"):
			var a: Vector3 = node.get_meta("blade_start")
			var b: Vector3 = node.get_meta("blade_end")
			assert(a.is_finite() and b.is_finite())
			assert(a.distance_to(b) > 0.30 and a.distance_to(b) < 0.65)
			front.append((b-a).normalized())
		if str(node.name).begins_with("RearWiper"):
			rear += 1
	assert(front.size() == 2, "Two front wiper assemblies required")
	assert(front[0].dot(front[1]) > 0.98, "Parked blades point in opposite directions")
	assert(rear == (1 if str(car.silhouette) in ["hatch", "van", "offroad"] else 0))
	print("[qa] parked wipers OK: ", car.name)


func _wiper_sheets(title: Label) -> void:
	var sheet := Image.create(W * 3, H * 3, false, Image.FORMAT_RGBA8)
	for i in range(Cars.LIST.size()):
		var car: Dictionary = Cars.get_car(i)
		_model.show_car(car)
		title.text = car.name
		var target: Vector3 = _model._screen_surface(Vector2(0.915, 0), 0.0)
		_cam.position = target + Vector3(0.85, 1.40, 3.2)
		_cam.look_at(target)
		var img := await _capture()
		sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i((i % 3) * W, int(i / 3) * H))
	sheet.save_png(ProjectSettings.globalize_path("res://shots/wipers_front.png"))
	sheet = Image.create(W * 3, H, false, Image.FORMAT_RGBA8)
	for i in range(3):
		var car: Dictionary = Cars.get_car([0,1,3][i])
		_model.show_car(car)
		title.text = car.name
		var target: Vector3 = _model._screen_surface(Vector2(0.055, 0), 0.0)
		_cam.position = target + Vector3(0.7, 1.3, -3.0)
		_cam.look_at(target)
		var img := await _capture()
		sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(i * W, 0))
	sheet.save_png(ProjectSettings.globalize_path("res://shots/wipers_rear.png"))
	print("[qa] wrote front/rear wiper close-ups")


func _validate_roof_and_bed(car: Dictionary) -> void:
	var roof: float = _model._roof
	var width: float = _model._cab_sec(0.5).hwt
	for i in range(65):
		var u: float = lerpf(_model._roof0, _model._roof1, float(i) / 64.0)
		assert(absf(_model._cab_top_y(u, 0.0) - roof) < 0.00001, "Uneven roof height")
		assert(absf(float(_model._cab_sec(u).hwt) - width) < 0.00001, "Wavy roof width")
	for u: float in [_model._roof0, _model._roof1]:
		assert(_model._cab_ts.has(u), "Roof break missing from the actual mesh")
		assert(absf(_model._cab_height(u - 0.0001) - _model._cab_height(u + 0.0001)) < 0.0001)
	if str(car.silhouette) == "pickup":
		var t := 0.20
		assert(absf(_model._body_top(t) - _model._belt) < 0.01, "Bed rails above the body")
		assert(_model._body_top(t) - _model._bed_floor(t) > 0.23, "Bed is not recessed")
		var ring: Dictionary = _model._body_ring(t)
		var found_floor := false
		for point: Vector2 in ring.pts:
			if absf(point.x) < 0.01 and absf(point.y - _model._bed_floor(t)) < 0.0001:
				found_floor = true
		assert(found_floor, "Pickup tub is not part of BodyShell")
		var rail_width: float = _model._bed_inner_hw(0.20)
		for i in range(25):
			var rail_t := lerpf(0.05, 0.34, float(i) / 24.0)
			assert(absf(_model._bed_inner_hw(rail_t) - rail_width) < 0.0001, "Wavy pickup rail")
	print("[qa] flat roof / integrated body OK: ", car.name)


func _roof_and_pickup_sheets(title: Label) -> void:
	var sheet := Image.create(W * 3, H * 3, false, Image.FORMAT_RGBA8)
	for i in range(Cars.LIST.size()):
		var car: Dictionary = Cars.get_car(i)
		_model.show_car(car)
		title.text = car.name
		var target := Vector3(0, _model._roof - 0.10, _model._zw((_model._cab0 + _model._cab1) * 0.5))
		_cam.position = target + Vector3(2.5, 3.5, 3.0)
		_cam.look_at(target)
		var img := await _capture()
		sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i((i % 3) * W, int(i / 3) * H))
	sheet.save_png(ProjectSettings.globalize_path("res://shots/models_roofs.png"))
	_model.show_car(Cars.get_car(5))
	_bb = _model.bounds()
	title.text = "PICKUP"
	sheet = Image.create(W * 2, H * 2, false, Image.FORMAT_RGBA8)
	var views := [[35.0, 22.0], [145.0, 28.0], [90.0, 12.0], [180.0, 65.0]]
	for i in range(views.size()):
		_place(views[i][0], views[i][1])
		var centre := _bb.get_center()
		_cam.position = centre + (_cam.position - centre) * 1.18
		var img := await _capture()
		sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i((i % 2) * W, int(i / 2) * H))
	sheet.save_png(ProjectSettings.globalize_path("res://shots/pickup_integrated.png"))
	sheet = Image.create(W * 2, H, false, Image.FORMAT_RGBA8)
	var commercial := ["truck", "bus"]
	for i in range(commercial.size()):
		_model.show_car({"silhouette": commercial[i], "color": "#d8a43e"})
		title.text = str(commercial[i]).to_upper()
		var target := Vector3(_model._W * 0.43, _model._wr + 0.10, _model._wz_f)
		_cam.position = target + Vector3(4.0, 0.7, 0.8)
		_cam.look_at(target)
		var img := await _capture()
		sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(i * W, 0))
	sheet.save_png(ProjectSettings.globalize_path("res://shots/commercial_wheels.png"))
	print("[qa] wrote roofs, pickup and commercial wheel detail sheets")


func _validate_arches(car: Dictionary) -> void:
	for axle: float in [_model._wz_f, _model._wz_r]:
		var rad: float = _model._wr + 0.040
		for i in range(1, 32):
			var a := PI * float(i) / 32.0
			var t: float = (axle + rad * cos(a)) / _model._L + 0.5
			var y: float = _model._body_bot(t)
			assert(absf(y - (_model._wr + rad * sin(a))) < 0.001, "Non-circular arch: " + str(car.name))
			var section: Dictionary = _model._body_sec(t)
			var trimmed: Dictionary = _model._body_ring(t)
			var reference: Dictionary = _model._sec(section.hwb, section.hwt,
				section.y0, section.y1, section.rb, section.rt, _model._zw(t))
			# The upper quarter-circle and the bonnet must not move when the
			# lower edge is trimmed above the tyre.
			for j in range(9, 14 if str(car.silhouette) == "pickup" else 16):
				assert(trimmed.pts[j].distance_to(reference.pts[j]) < 0.0001,
					"Arch deforms shoulder: " + str(car.name))
	for child in _model._root.get_children():
		if child is MeshInstance3D and str(child.name).begins_with("WheelWell"):
			var middle: float = child.get_aabb().get_center().z
			var axle: float = _model._wz_f if middle > 0 else _model._wz_r
			var vertices: PackedVector3Array = child.mesh.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
			for vertex in vertices:
				var radius := Vector2(vertex.y - _model._wr, vertex.z - axle).length()
				assert(radius < _model._wr + 0.030, "Liner touches body shell")
				assert(radius > _model._wr * 1.008 + 0.012, "Liner touches tyre")
	print("[qa] circular arches / stable shoulders / liner clearance OK: ", car.name)


func _detail_sheets(title: Label) -> void:
	for rear: bool in [false, true]:
		var sheet := Image.create(W * 3, H * 3, false, Image.FORMAT_RGBA8)
		for i in range(Cars.LIST.size()):
			var car: Dictionary = Cars.get_car(i)
			_model.show_car(car)
			title.text = car.name
			var axle: float = _model._wz_r if rear else _model._wz_f
			var target := Vector3(_model._W * 0.43, _model._wr + 0.10, axle)
			_cam.position = target + Vector3(3.5, 0.7, 0.85)
			_cam.look_at(target)
			var img := await _capture()
			sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i((i % 3) * W, int(i / 3) * H))
		var name := "arches_rear" if rear else "arches_front"
		sheet.save_png(ProjectSettings.globalize_path("res://shots/%s.png" % name))
	var sheet := Image.create(W * 3, H, false, Image.FORMAT_RGBA8)
	for i in range(3):
		var car: Dictionary = Cars.get_car([4, 6, 8][i])
		_model.show_car(car)
		title.text = car.name
		var target := Vector3(0, _model._deck + 0.12, _model._zw(0.09))
		_cam.position = target + Vector3(2.6, 1.6, -3.8)
		_cam.look_at(target)
		var img := await _capture()
		sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i(i * W, 0))
	sheet.save_png(ProjectSettings.globalize_path("res://shots/spoilers.png"))
	print("[qa] wrote arch and spoiler close-ups")


func _validate_geometry(car: Dictionary) -> void:
	assert(_bb.position.is_finite() and _bb.size.is_finite())
	assert(absf(_bb.get_center().x) < 0.10, "Off-centre car: " + str(car.name))
	assert(_bb.size.z > 3.5 and _bb.size.z < 5.2)
	assert(_bb.position.y > -0.08, "Geometry below the ground: " + str(car.name))
	var flap: Vector2 = _model._flap_location()
	for i in range(25):
		var a := TAU * float(i) / 24.0
		var t: float = flap.x + cos(a) * 0.061 / _model._L
		var y := flap.y + sin(a) * 0.061
		var section: Dictionary = _model._body_sec(t)
		assert(y > float(section.y0) + float(section.rb), "Flap intersects arch: " + str(car.name))
		assert(y < float(section.y1) - float(section.rt), "Flap crosses shoulder: " + str(car.name))
	var stack: Array = [_model._root]
	var triangles := 0
	while not stack.is_empty():
		var node: Node = stack.pop_back()
		stack.append_array(node.get_children())
		if node is MeshInstance3D:
			var mesh: Mesh = node.mesh
			for surface in range(mesh.get_surface_count()):
				var arrays := mesh.surface_get_arrays(surface)
				var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
				var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
				if str(node.name).begins_with("GlassPane"):
					assert(node.material_override is ShaderMaterial, "Glass shader missing")
					var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
					assert(uvs.size() == vertices.size(), "Missing glass UV coordinates")
					for uv in uvs:
						assert(uv.is_finite() and uv.x >= -0.001 and uv.x <= 1.001
							and uv.y >= -0.001 and uv.y <= 1.001, "Invalid frit mapping")
				for vertex in vertices:
					assert(vertex.is_finite(), "Invalid vertex: " + str(car.name))
				for normal in normals:
					assert(normal.is_finite() and normal.length_squared() > 0.9)
				var indices := PackedInt32Array()
				if arrays[Mesh.ARRAY_INDEX] != null:
					indices = arrays[Mesh.ARRAY_INDEX]
				triangles += int((indices.size() if not indices.is_empty() else vertices.size()) / 3)
	print("[qa] geometry OK: %s, %d triangles" % [car.name, triangles])


func _validate_cache() -> void:
	var count: int = _model.get_child_count()
	for car in Cars.LIST:
		_model.show_car(car)
		var instance: int = _model._root.get_instance_id()
		var recoloured: Dictionary = car.duplicate()
		recoloured.color = "#72b8e6"
		recoloured.stripe = not bool(car.stripe)
		_model.show_car(recoloured)
		assert(_model._root.get_instance_id() == instance, "Colour rebuilt the geometry")
		assert(_model._stripe_root.visible == bool(recoloured.stripe))
		var variant: Dictionary = _model._variants[str(car.silhouette)]
		assert(variant.paint.albedo_color.is_equal_approx(Color("#72b8e6")))
		_model.show_car(car)
	assert(_model.get_child_count() == count, "Colour variants duplicated meshes")
	print("[qa] colour/stripe cache OK: all nine silhouettes reused")


func _garage_sheet() -> void:
	var sheet := Image.create(616 * 3, 600 * 3, false, Image.FORMAT_RGBA8)
	for i in range(Cars.LIST.size()):
		var vp := SubViewport.new()
		vp.size = Vector2i(616, 600)
		vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		root.add_child(vp)
		var stage := CarStage.new()
		stage.car = Cars.get_car(i)
		stage.size = Vector2(616, 600)
		vp.add_child(stage)
		var box: AABB = stage._model.bounds()
		for corner in range(8):
			var screen: Vector2 = stage._cam.unproject_position(box.get_endpoint(corner))
			assert(screen.x > 0 and screen.x < CarStage.VP_W)
			assert(screen.y > 0 and screen.y < CarStage.VP_H)
		await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		sheet.blit_rect(img, Rect2i(0, 0, 616, 600), Vector2i((i % 3) * 616, int(i / 3) * 600))
		vp.queue_free()
	var path := ProjectSettings.globalize_path("res://shots/models_garage.png")
	sheet.save_png(path)
	print("[qa] wrote ", path)


func _race_sheet() -> void:
	var art := RaceArt.new()
	root.add_child(art)
	art.set_process(false)
	art.set_enabled(true)
	var sheet := Image.create(220 * 3, 360 * 3, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.24, 0.26, 0.28))
	for i in range(Cars.LIST.size()):
		var sprite: Dictionary = art.take(Cars.get_car(i))
		assert(not sprite.is_empty(), "Missing production atlas sprite")
		var atlas: Image = art._pages[int(sprite.page)].get_image()
		var img := atlas.get_region(Rect2i(sprite.region))
		assert(img.get_used_rect().has_area(), "Blank atlas region")
		var scale := minf(196.0 / img.get_width(), 336.0 / img.get_height())
		img.resize(int(img.get_width() * scale), int(img.get_height() * scale), Image.INTERPOLATE_LANCZOS)
		var pos := Vector2i((i % 3) * 220 + (220 - img.get_width()) / 2,
			int(i / 3) * 360 + (360 - img.get_height()) / 2)
		sheet.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), pos)
	var path := ProjectSettings.globalize_path("res://shots/models_race.png")
	sheet.save_png(path)
	print("[qa] wrote ", path)
