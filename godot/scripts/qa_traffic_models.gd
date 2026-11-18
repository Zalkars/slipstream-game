extends "res://scripts/qa_model.gd"

# Run with a graphical renderer: geometry, colour cache, camera fit and all
# seven spawn kinds through the production race bakery, plus inspection sheets.
func _run() -> void:
	_build()
	var sheet := Image.create(W * 2, H * 2, false, Image.FORMAT_RGBA8)
	var cell := 0
	for sil in ["truck", "bus"]:
		var car := {"silhouette": sil, "color": "#e0a52a", "trailer": "#e1e4e6", "accent": "#d64a3a"}
		_model.show_car(car)
		_bb = _model.bounds()
		assert(_bb.size.z > 7.0 and _bb.size.y > 2.8)
		assert(_bb.position.y > -0.04)
		var stack: Array = [_model._root]
		var triangles := 0
		while not stack.is_empty():
			var node: Node = stack.pop_back()
			stack.append_array(node.get_children())
			if node is MeshInstance3D:
				for surface in range(node.mesh.get_surface_count()):
					var arrays: Array = node.mesh.surface_get_arrays(surface)
					for vertex: Vector3 in arrays[Mesh.ARRAY_VERTEX]:
						assert(vertex.is_finite())
					for normal: Vector3 in arrays[Mesh.ARRAY_NORMAL]:
						assert(normal.is_finite() and normal.length_squared() > 0.9)
					var indices = arrays[Mesh.ARRAY_INDEX]
					triangles += int((indices.size() if indices != null and indices.size() > 0 else arrays[Mesh.ARRAY_VERTEX].size()) / 3)
		print("[qa] ", sil, " geometry OK, triangles=", triangles)
		var instance: int = _model._root.get_instance_id()
		car.trailer = "#72b8e6"
		car.accent = "#2e7fbe"
		_model.show_car(car)
		assert(_model._root.get_instance_id() == instance)
		var v: Dictionary = _model._variants[sil]
		assert(v.cargo_paint.albedo_color.is_equal_approx(Color(car.trailer)))
		assert(v.accent.albedo_color.is_equal_approx(Color(car.accent)))
		car.trailer = "#e1e4e6"
		car.accent = "#d64a3a"
		_model.show_car(car)
		for az: float in [30.0, 150.0]:
			_place(az, 24.0)
			var center := _bb.get_center()
			_cam.position = center + (_cam.position - center) * 1.35
			var img := await _capture()
			sheet.blit_rect(img, Rect2i(0, 0, W, H), Vector2i((cell % 2) * W, int(cell / 2) * H))
			cell += 1
	sheet.save_png(ProjectSettings.globalize_path("res://shots/traffic_commercial.png"))
	var art := RaceArt.new()
	root.add_child(art)
	art.set_process(false)
	var line := Image.create(960, 1000, false, Image.FORMAT_RGBA8)
	line.fill(Color("#373c43"))
	var kinds := [0, 1, 2, 3, 4, 5, 6, 0]
	for i in range(kinds.size()):
		var car := {"kind": kinds[i], "color": Color("#d8a43e"), "trailer": Color("#e1e4e6"), "accent": Color("#d64a3a")}
		if i == 7:
			car.silhouette = "hatch"
		assert(art._silhouette(car) != "", "Traffic kind missing a model")
		var img: Image = await art.render_preview(car)
		assert(img != null and img.get_width() > 40 and img.get_height() > 100)
		var bb: AABB = art._model.bounds()
		if kinds[i] in [2, 4]:
			for corner in range(8):
				var screen: Vector2 = art._cam.unproject_position(bb.get_endpoint(corner))
				assert(screen.x > 2 and screen.x < art._vp.size.x - 2, "Horizontal clipping")
				assert(screen.y > 2 and screen.y < art._vp.size.y - 2, "Vertical clipping")
		var ratio := minf(196.0 / img.get_width(), 450.0 / img.get_height())
		img.resize(int(img.get_width() * ratio), int(img.get_height() * ratio), Image.INTERPOLATE_LANCZOS)
		line.blend_rect(img, Rect2i(Vector2i.ZERO, img.get_size()), Vector2i((i % 4) * 240 + (240 - img.get_width()) / 2, int(i / 4) * 500 + (500 - img.get_height()) / 2))
		if kinds[i] in [2, 4]:
			var key: String = art._key(car)
			car.trailer = Color("#72b8e6")
			car.accent = Color("#2e7fbe")
			assert(art._key(car) != key, "Commercial livery missing from sprite key")
			# Custom showcase colours render on demand for QA only; gameplay
			# uses the finite palette baked into its committed atlases.
		print("[qa] traffic kind ", kinds[i], " render OK")
	line.save_png(ProjectSettings.globalize_path("res://shots/traffic_models.png"))
	var road_ok: bool = await _road_preview()
	assert(road_ok, "Production road preview failed")
	print("[qa] PASS: all traffic models, geometry, framing and colour caches")
	quit(0)


func _road_preview() -> bool:
	var vp := SubViewport.new()
	vp.size = Vector2i(720, 1560)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	# Resolve Game after the SceneTree autoloads (including Sfx) are ready.
	var game = load("res://scripts/game.gd").new()
	vp.add_child(game)
	game.start_run()
	game.set_process(false)
	game.use_3d_cars = true
	game.cars.clear()
	var kinds := [0, 1, 3, 5, 2, 4, 6, 0]
	for i in range(kinds.size()):
		var kind: int = kinds[i]
		var type: Dictionary = game.TRAFFIC_TYPES[kind]
		var car := {"kind": kind, "silhouette": game._traffic_silhouette(kind),
			"color": game.TRAFFIC_COLORS[i], "stripe": kind == 5,
			"stripe_color": game._traffic_stripe(game.TRAFFIC_COLORS[i]),
			"trailer": game.TRAILER_COLORS[0], "accent": game.BUS_ACCENTS[1],
			"x": game._lane_x(i % 4), "y": 340.0 if i < 4 else 860.0,
			"w": game.car_w * float(type.w), "h": game.car_h * float(type.h)}
		car.merge(game.PALETTE.variants(str(car.silhouette), i)[1], true)
		assert(not game.race_art.take(car).is_empty(), "Missing production traffic appearance")
		game.cars.append(car)
	for night in [false, true]:
		game.time_of_day = 0.70 if night else 0.15
		game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		vp.get_texture().get_image().save_png("res://shots/traffic_road_%s.png" % ("night" if night else "day"))
	print("[qa] production atlas: all traffic appearances; day/night road renders OK")
	vp.queue_free()
	return true
