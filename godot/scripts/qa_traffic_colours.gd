extends SceneTree

const PALETTE := preload("res://scripts/traffic_palette.gd")

class Sheet extends Control:
	var art: RaceArt
	var cars: Array = []

	func _draw() -> void:
		draw_rect(Rect2(0, 0, 1320, 1440), Color("#161c25"))
		var font := ThemeDB.fallback_font
		for i in range(cars.size()):
			var car: Dictionary = cars[i]
			var origin := Vector2((i % 6) * 220, int(i / 6) * 360)
			draw_style_box(_tile(), Rect2(origin + Vector2(5, 5), Vector2(210, 350)))
			var sprite := art.take(car)
			assert(not sprite.is_empty(), "Showcase appearance missing")
			art.draw(self, origin + Vector2(110, 165), 154, 272, sprite)
			draw_string(font, origin + Vector2(17, 325), str(car.silhouette).to_upper(), HORIZONTAL_ALIGNMENT_LEFT, 190, 17, Color("#d9e5f3"))
			draw_circle(origin + Vector2(189, 320), 8, car.color)

	func _tile() -> StyleBoxFlat:
		var style := StyleBoxFlat.new()
		style.bg_color = Color("#29313d")
		style.set_corner_radius_all(12)
		return style


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(1320, 1440)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(vp)
	var sheet := Sheet.new()
	sheet.art = RaceArt.new()
	root.add_child(sheet.art)
	sheet.art.set_enabled(true)
	var silhouettes := ["hatch", "sedan", "ev", "muscle", "sport", "hyper",
		"offroad", "van", "pickup", "truck", "bus", "sedan"]
	for i in range(silhouettes.size()):
		for option in range(2):
			var variants: Array = PALETTE.variants(silhouettes[i], (16 + i + option * 3) % PALETTE.TRAFFIC_COLORS.size())
			sheet.cars.append(variants[variants.size() - 1 if option == 1 else 0])
	vp.add_child(sheet)
	await process_frame
	await RenderingServer.frame_post_draw
	vp.get_texture().get_image().save_png("res://shots/traffic_colours.png")
	print("[qa] 24 production appearances rendered; all 11 traffic silhouettes")
	quit(0)
