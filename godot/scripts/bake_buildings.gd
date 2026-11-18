extends SceneTree

const MODEL := preload("res://scripts/building_model.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var probe := root.get_node_or_null("QaFrames")
	if probe != null:
		probe.queue_free()
	var vp := SubViewport.new()
	vp.size = Vector2i(1536, 2304)
	vp.transparent_bg = true
	vp.own_world_3d = true
	vp.msaa_3d = Viewport.MSAA_4X
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	root.add_child(vp)
	var environment := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color("#adb7c3")
	env.ambient_light_energy = 0.43
	environment.environment = env
	vp.add_child(environment)
	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-52, -32, 0)
	key.light_energy = 0.95
	key.light_color = Color("#fff2d9")
	key.shadow_enabled = true
	key.shadow_opacity = 0.65
	key.shadow_bias = 0.12
	key.shadow_normal_bias = 1.0
	key.directional_shadow_max_distance = 100
	key.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	vp.add_child(key)
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-25, 130, 0)
	fill.light_energy = 0.18
	fill.light_color = Color("#b5c8df")
	vp.add_child(fill)
	var camera := Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.far = 300
	vp.add_child(camera)
	camera.current = true
	var ground := MeshInstance3D.new()
	var mesh := PlaneMesh.new()
	mesh.size = Vector2(240, 240)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.7, 0.7, 0.7)
	material.roughness = 1.0
	mesh.material = material
	ground.mesh = mesh
	ground.position.y = -0.02
	vp.add_child(ground)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://art/roadside"))
	var entries: Array = []
	var sheet := Image.create(1800, 1800, false, Image.FORMAT_RGBA8)
	sheet.fill(Color("#717c62"))
	for index in range(6):
		var model := MODEL.new()
		vp.add_child(model)
		model.build(index)
		var center := Vector3(0, model.dimensions.y * 0.4, 0)
		# Match the race camera's heading: highway and roof edges remain parallel.
		camera.position = center + Vector3(0, 44, -37)
		camera.look_at(center, Vector3.UP)
		camera.size = 63.0 if index < 2 else 40.5
		await process_frame
		ground.visible = false
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var body := vp.get_texture().get_image()
		body.convert(Image.FORMAT_RGBA8)
		var used := body.get_used_rect()
		assert(used.position.x > 8 and used.position.y > 8 and used.end.x < vp.size.x - 8 and used.end.y < vp.size.y - 8, "3D building was clipped")
		ground.visible = true
		# A separate shadow-only pass prevents a solid building silhouette from
		# contaminating the ground mask. Roof/facade shading stays in the body.
		for child in model.get_children():
			if child is GeometryInstance3D:
				child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_SHADOWS_ONLY
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await RenderingServer.frame_post_draw
		var shadow := vp.get_texture().get_image()
		var base := shadow.get_pixel(4, 4)
		var luminance := maxf(0.01, base.r + base.g + base.b)
		var shadow_data := shadow.get_data()
		var pixels := shadow_data.duplicate()
		for pixel in range(body.get_width() * body.get_height()):
			var offset := pixel * 4
			var darkness := clampf(1.0 - float(shadow_data[offset] + shadow_data[offset + 1] + shadow_data[offset + 2]) / (255.0 * luminance), 0, 0.65)
			pixels[offset] = 30
			pixels[offset + 1] = 39
			pixels[offset + 2] = 44
			pixels[offset + 3] = int(maxf(0.0, darkness - 0.015) * 0.48 * 255.0)
		var ground_shadow := Image.create_from_data(body.get_width(), body.get_height(), false, Image.FORMAT_RGBA8, pixels)
		ground_shadow = _soft_shadow(ground_shadow)
		var crop := used.merge(ground_shadow.get_used_rect()).grow(6).intersection(Rect2i(Vector2i.ZERO, vp.size))
		var origin := camera.unproject_position(Vector3.ZERO)
		var pixels_per_metre := camera.unproject_position(Vector3(1, 0, 0)).distance_to(origin)
		# Anchor the outermost solid geometry, including awnings and balconies.
		# Shadows may extend past this edge; the building itself must not.
		var edge := float(used.end.x)
		entries.append({"path": "res://art/roadside/building_%d.png" % index,
			"anchor": Vector2(edge - crop.position.x, origin.y - crop.position.y),
			"shadow_path": "res://art/roadside/building_shadow_%d.png" % index,
			"solid_bounds": Rect2(used.position - crop.position, used.size),
			"pixels_per_metre": pixels_per_metre, "floors": model.floors,
			"dimensions": model.dimensions, "size": crop.size})
		var result := body.get_region(crop)
		result.save_png(entries[-1].path)
		var soft := ground_shadow.get_region(crop)
		soft.save_png(entries[-1].shadow_path)
		var preview := soft.duplicate()
		preview.blend_rect(result, Rect2i(Vector2i.ZERO, result.get_size()), Vector2i.ZERO)
		var factor := minf(570.0 / preview.get_width(), 860.0 / preview.get_height())
		preview.resize(int(preview.get_width() * factor), int(preview.get_height() * factor), Image.INTERPOLATE_LANCZOS)
		sheet.blend_rect(preview, Rect2i(Vector2i.ZERO, preview.get_size()), Vector2i((index % 3) * 600 + (600 - preview.get_width()) / 2, int(index / 3) * 900 + (900 - preview.get_height()) / 2))
		print("[buildings] ", index, " floors=", model.floors, " metres=", model.dimensions, " sprite=", crop.size)
		model.queue_free()
		await process_frame
	var file := FileAccess.open("res://art/roadside/buildings.gd", FileAccess.WRITE)
	file.store_string("extends RefCounted\n\n# Generated by bake_buildings.gd from metre-scale 3D geometry.\nconst ENTRIES = " + var_to_str(entries) + "\n")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	sheet.save_png("res://shots/buildings_3d_review.png")
	vp.queue_free()
	await process_frame
	quit(0)


func _soft_shadow(mask: Image) -> Image:
	# Three separable box passes approximate a Gaussian penumbra. Work at 1/4
	# resolution so baking stays quick; the final bilinear upsample removes
	# shadow-map stair steps without changing the sharp building geometry.
	var original := mask.get_size()
	var width := int(ceil(original.x / 4.0))
	var height := int(ceil(original.y / 4.0))
	mask.resize(width, height, Image.INTERPOLATE_BILINEAR)
	var data := mask.get_data()
	var scratch := data.duplicate()
	const RADIUS := 3
	const TAPS := RADIUS * 2 + 1
	for pass_index in range(3):
		for y in range(height):
			var total := 0
			for k in range(-RADIUS, RADIUS + 1):
				total += int(data[(y * width + clampi(k, 0, width - 1)) * 4 + 3])
			for x in range(width):
				scratch[(y * width + x) * 4 + 3] = int(round(float(total) / TAPS))
				total -= int(data[(y * width + clampi(x - RADIUS, 0, width - 1)) * 4 + 3])
				total += int(data[(y * width + clampi(x + RADIUS + 1, 0, width - 1)) * 4 + 3])
		for x in range(width):
			var total := 0
			for k in range(-RADIUS, RADIUS + 1):
				total += int(scratch[(clampi(k, 0, height - 1) * width + x) * 4 + 3])
			for y in range(height):
				data[(y * width + x) * 4 + 3] = int(round(float(total) / TAPS))
				total -= int(scratch[(clampi(y - RADIUS, 0, height - 1) * width + x) * 4 + 3])
				total += int(scratch[(clampi(y + RADIUS + 1, 0, height - 1) * width + x) * 4 + 3])
	var result := Image.create_from_data(width, height, false, Image.FORMAT_RGBA8, data)
	result.resize(original.x, original.y, Image.INTERPOLATE_BILINEAR)
	return result
