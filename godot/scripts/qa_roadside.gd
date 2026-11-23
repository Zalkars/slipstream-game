extends SceneTree


class ShadowProbe extends Node2D:
	var art: Node
	var strength := 1.0

	func _draw() -> void:
		art.draw_building(self, Vector2(610, 600), 19, 0, 0.45, -1.0,
			Color.WHITE, Vector2.ZERO, strength)
		art.draw_building(self, Vector2(880, 600), 19, 1, 0.45, 1.0,
			Color.WHITE, Vector2.ZERO, strength)

# Run with a graphical renderer, --script res://scripts/qa_roadside.gd.
# Checks the real atlas and production road, including night and cycle seams.
func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var probe := root.get_node_or_null("QaFrames")
	if probe != null:
		probe.queue_free()
	var main: Node = load("res://scenes/Main.tscn").instantiate()
	root.add_child(main)
	current_scene = main
	for i in range(12):
		await process_frame
	main.start_game(false)
	var game: Node2D = main.game
	game.set_process(false)
	game.use_3d_cars = true
	game.cars.clear()
	main.set_process(false)
	var art: Node = game.roadside_art
	assert(art.atlas != null, "Roadside atlas failed to bake")
	var image: Image = art.atlas.get_image()
	assert(image.get_size() == Vector2i(1536, 1536))
	# Every variant must have visible pixels and transparent padding to prevent
	# adjacent atlas cells bleeding into each other under linear filtering.
	for index in range(60):
		var cell := image.get_region(Rect2i((index % 8) * 192, int(index / 8) * 192, 192, 192))
		var used := cell.get_used_rect()
		assert(used.size.x > 15 and used.size.y > 15)
		assert(used.position.x >= 2 and used.position.y >= 2)
		assert(used.end.x < 190 and used.end.y < 190)
	assert(art.building_textures.size() == 6, "Baked 3D buildings must load")
	assert(art.building_shadows.size() == 6, "Ground shadows must load separately")
	for index in range(6):
		var entry: Dictionary = art.building_entries[index]
		var sprite: Image = art.building_textures[index].get_image()
		var used := sprite.get_used_rect()
		var shadow: Image = art.building_shadows[index].get_image()
		assert(shadow.get_size() == sprite.get_size())
		var values := {}
		var maximum := 0
		var data := shadow.get_data()
		for offset in range(3, data.size(), 16):
			var alpha := int(data[offset])
			values[alpha] = true
			maximum = maxi(maximum, alpha)
		assert(maximum > 5 and maximum < 80, "Ground shadows must be translucent")
		assert(values.size() >= 12, "A soft shadow must have a gradual alpha ramp")
		assert(used.position.x > 1 and used.position.y > 1)
		assert(used.end.x < sprite.get_width() - 1 and used.end.y < sprite.get_height() - 1)
		assert(entry.dimensions.x >= 9 and entry.dimensions.z >= 12)
		assert(entry.anchor.x > 0 and entry.anchor.y > 0)
		if index < 2:
			assert(entry.floors == 5 and entry.dimensions.y == 15)
			assert(entry.dimensions.z / 4.36 > 5)
	await _check_shadow_fade(art)
	var original: Array = game.decor.duplicate(true)
	game._gen_decor()
	assert(original == game.decor, "Decor generation must be deterministic")
	for d in game.decor:
		assert(d.y >= 0 and d.y < float(d.get("cycle", game.DECOR_CYCLE)))
		assert(d.prop >= 0 and d.prop < 20)
		if d.kind == 0 or d.kind == 1:
			for i in range(6):
				var center: float = i * 1300.0 + (530.0 if d.side < 0 else 910.0) + 40.0
				var gap: float = fposmod(d.y - center + 3900.0, 7800.0) - 3900.0
				assert(absf(gap) >= 130.0, "Keep furniture clear of trees and shrubs")
	var buildings: Array = game.decor.filter(func(d: Dictionary) -> bool: return int(d.kind) == 5)
	assert(buildings.size() == 10)
	for building in buildings:
		var bounds: Rect2 = game._building_plot_bounds(building)
		# The complete geometry, including balconies and awnings, stays on the
		# outer side of the guardrail. Test both sides, not just the origin.
		if building.side < 0:
			assert(bounds.end.x <= game.road_x - 52.0)
		else:
			assert(bounds.position.x >= game.road_x + game.road_w + 52.0)
		for d in game.decor:
			if d.side != building.side or d.kind == 5 or d.prop == 12 or d.prop == 14:
				continue
			var gap: float = fposmod(d.y - building.y + 3900.0, 7800.0) - 3900.0
			var margin := 45.0 if int(d.kind) == 2 else 70.0
			assert(gap <= bounds.position.y - building.y - margin or gap >= bounds.end.y - building.y + margin,
				"Building must not overlap lamps, signs or vegetation, including wraparound")
		for other in buildings:
			if other == building or other.side != building.side:
				continue
			for shift in [-7800.0, 0.0, 7800.0]:
				var other_bounds: Rect2 = game._building_plot_bounds(other)
				other_bounds.position.y += shift
				assert(not bounds.intersects(other_bounds), "Building silhouettes must not overlap")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	image.save_png("res://shots/roadside_atlas.png")
	for scene in ["day", "woodland", "night", "wrap", "building_edge", "sunset"]:
		game.time_of_day = 0.15 if scene != "night" else 0.70
		if scene == "sunset":
			game.time_of_day = 0.49
		game.scroll = {"day": 0.0, "woodland": 2600.0, "night": 1100.0, "wrap": 7799.0, "building_edge": 7480.0, "sunset": 1100.0}[scene]
		game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://shots/roadside_%s.png" % scene)
	# Move across the scenery loop in small steps. A newly visible, incorrectly
	# culled building would change a large portion of a verge in a single frame.
	game.time_of_day = 0.15
	var previous := PackedByteArray()
	for step in range(14):
		game.scroll = 7788.0 + step * 2.0
		game.queue_redraw()
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := root.get_texture().get_image()
		frame.convert(Image.FORMAT_RGBA8)
		var current := frame.get_data()
		if not previous.is_empty():
			var changed := 0
			for offset in range(0, current.size(), 64):
				var delta := absi(int(current[offset]) - int(previous[offset]))
				delta += absi(int(current[offset + 1]) - int(previous[offset + 1]))
				delta += absi(int(current[offset + 2]) - int(previous[offset + 2]))
				if delta > 70:
					changed += 1
			assert(float(changed) / (current.size() / 64.0) < 0.08, "Scenery must not pop at the loop seam")
		previous = current
	print("[qa] roadside: 60 scenery sprites + 6 full-size buildings; 10 clear building plots; ", game.decor.size(), " deterministic props; lamp/rail/building clearance OK; day/woodland/night/wrap rendered")
	print("[qa] shadows: day/dusk/night compositing and 14 moving seam frames OK")
	quit(0)


func _check_shadow_fade(art: Node) -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1500, 1200)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	var probe := ShadowProbe.new()
	probe.art = art
	vp.add_child(probe)
	root.add_child(vp)
	var masses: Array[int] = []
	for strength in [1.0, 0.5, 0.0]:
		probe.strength = strength
		probe.queue_redraw()
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		await process_frame
		await RenderingServer.frame_post_draw
		var frame := vp.get_texture().get_image()
		frame.convert(Image.FORMAT_RGBA8)
		var data := frame.get_data()
		var mass := 0
		for offset in range(3, data.size(), 4):
			mass += int(data[offset])
		masses.append(mass)
	var daylight := float(masses[0] - masses[2])
	var dusk := float(masses[1] - masses[2])
	assert(daylight > 10000, "Daytime shadows must remain visible")
	assert(dusk > daylight * 0.40 and dusk < daylight * 0.60, "Shadow fade must be smooth and vanish at night")
	vp.queue_free()
