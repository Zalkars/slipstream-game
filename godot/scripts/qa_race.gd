extends SceneTree

# Temporary review sheet: every race sprite from the chase camera, twice the
# gameplay size, so the 3D cars can be checked for framing and lighting.

const COLS := 5
const CELL_W := 220
const CELL_H := 360
const RACE_ART := preload("res://scripts/race_art.gd")


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var art := RACE_ART.new()
	root.add_child(art)
	art.set_process(false)
	await process_frame

	var cars := []
	for i in range(Cars.LIST.size()):
		var c: Dictionary = Cars.get_car(i)
		cars.append({
			"silhouette": c.silhouette,
			"color": c.color,
			"stripe": bool(c.stripe),
			"stripe_color": c.stripe_color,
		})
	# Traffic-only classes that have a 3D model but no garage entry.
	cars.append({"silhouette": "van", "color": "#b9bdc1", "stripe": false})
	cars.append({"silhouette": "pickup", "color": "#8a5a2b", "stripe": false})

	var count := cars.size()
	var rows := int(ceil(float(count) / float(COLS)))
	var sheet := Image.create(CELL_W * COLS, CELL_H * rows, false, Image.FORMAT_RGBA8)
	sheet.fill(Color(0.38, 0.40, 0.39, 1.0))
	for i in range(count):
		var img: Image = await art.render_preview(cars[i])
		if img == null:
			continue
		var k := minf(float(CELL_W - 24) / float(img.get_width()),
			float(CELL_H - 24) / float(img.get_height()))
		var size := Vector2i(maxi(1, int(img.get_width() * k)), maxi(1, int(img.get_height() * k)))
		img.resize(size.x, size.y, Image.INTERPOLATE_BILINEAR)
		var x := (i % COLS) * CELL_W + (CELL_W - size.x) / 2
		var y := int(i / COLS) * CELL_H + (CELL_H - size.y) / 2
		sheet.blend_rect(img, Rect2i(0, 0, size.x, size.y), Vector2i(x, y))
	var path := ProjectSettings.globalize_path("res://shots/qa_race.png")
	sheet.save_png(path)
	print("[qa] wrote ", path, " ", sheet.get_size())
	quit(0)
