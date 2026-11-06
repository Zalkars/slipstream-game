extends SceneTree

# Pixel test for the car roster (Plan_0.5.0.md, stage 1).
#
# Every car is drawn alone, in one colour, with stripes, spoiler, lamps and
# every paint detail switched OFF. What is left is the car as it is seen from
# straight above: outline, proportions, glazing, and only then paint.
#
# Two numbers per pair, both measured in pixels, never by eye:
#
#   DIFF   how much the two cars disagree in appearance. Each car is
#          normalised into a 64 x 96 grid and every cell keeps the tone of the
#          car there (body, glass, roof crease). 0 = identical from above.
#          With one colour and no paint details, the only tones left are the
#          shape and the greenhouse, so this is the silhouette test.
#   COVER  how much of the two solid bodies lies on top of each other, at the
#          size the game draws them (no normalising). A hatch and a hypercar
#          are both about 86 x 163 px on screen, so they will always cover a
#          good part of each other; this number documents how much.
#
# Gates: DIFF >= 12 % and COVER <= 85 % for every pair.
#
# Run (needs a renderer, i.e. no --headless):
#   godot --path godot --script res://scripts/qa_silhouette.gd
#   godot --path godot --script res://scripts/qa_silhouette.gd -- --png
#
# Exit 0 = every pair passes, 1 = at least one does not, 2 = harness failure.

const CELL := 320
const PAD := 24
const NORM_W := 64
const NORM_H := 96
const MIN_DIFF := 12.0
const MAX_COVER := 85.0


class Raster extends SubViewport:
	# Draws one car inside a Viewport and reads the result back.
	var car: Dictionary = {}
	var colour := Color.BLACK
	var detailed := false

	func _init(w: int, h: int) -> void:
		size = Vector2i(w, h)
		transparent_bg = true
		render_target_update_mode = SubViewport.UPDATE_ALWAYS
		gui_disable_input = true
		var canvas := Control.new()
		canvas.size = Vector2(w, h)
		canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
		canvas.draw.connect(_draw_car.bind(canvas))
		add_child(canvas)

	func _draw_car(canvas: Control) -> void:
		# Flat colour on purpose: paint must not be what tells the cars apart.
		Art.car(canvas, Vector2(size) * 0.5, float(size.x) * 0.50, float(size.y) * 0.80, colour, {
			"silhouette": str(car.get("silhouette", "")),
			"stripe": false,
			"wing": false,
			"player": false,
			"details": detailed,
			"glass": true,
		})

	func shot(new_car: Dictionary, new_colour: Color, new_detailed: bool) -> Image:
		car = new_car
		colour = new_colour
		detailed = new_detailed
		(get_child(0) as Control).queue_redraw()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := get_texture().get_image()
		if img != null:
			img.convert(Image.FORMAT_RGBA8)
		return img


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	if DisplayServer.get_name() == "headless":
		printerr("QA_SILHOUETTE: needs a renderer, run without --headless")
		quit(2)
		return
	var want_png := "--png" in OS.get_cmdline_user_args()
	var count := Cars.LIST.size()
	var rasters: Array = []
	for i in range(count):
		var r := Raster.new(CELL, CELL)
		root.add_child(r)
		rasters.append(r)
	await process_frame
	await process_frame

	var ok := true
	var shots: Array = []
	print("flat colour, no stripes, no wing, no paint details")
	for i in range(count):
		var car: Dictionary = Cars.get_car(i)
		var img: Image = await rasters[i].shot(car, Color(0.62, 0.62, 0.62), false)
		if img == null:
			printerr("QA_SILHOUETTE: read-back failed for %s" % car.name)
			quit(2)
			return
		var m := _mask_of(img)
		shots.append(img)
		print("  %-9s filled=%5.1f%%  bbox=%s" % [car.name, m.filled * 100.0, str(m.bbox)])
		if m.filled < 0.05:
			printerr("QA_SILHOUETTE: %s rendered almost nothing" % car.name)
			ok = false

	print("")
	print("  pair                      diff   cover")
	var worst_diff := 100.0
	var worst_cover := 0.0
	for i in range(count):
		for j in range(i + 1, count):
			var diff := _diff(shots[i], shots[j])
			var cover := _cover(shots[i], shots[j])
			worst_diff = minf(worst_diff, diff)
			worst_cover = maxf(worst_cover, cover)
			var bad := diff < MIN_DIFF or cover > MAX_COVER
			if bad:
				ok = false
			print("  %-9s vs %-9s  %5.1f%%  %5.1f%%%s" % [
				Cars.get_car(i).name, Cars.get_car(j).name, diff, cover,
				"   <-- too similar" if bad else "",
			])

	if want_png:
		await _sheet(rasters, count)

	print("")
	print("QA_SILHOUETTE: worst diff %.1f%% (min %.0f%%), worst cover %.1f%% (max %.0f%%) -> %s" % [
		worst_diff, MIN_DIFF, worst_cover, MAX_COVER, "PASS" if ok else "FAIL",
	])
	quit(0 if ok else 1)


# Contact sheet: every car in its own paint, once flat and once fully detailed,
# so the numbers above can also be checked with the eyes.
func _sheet(rasters: Array, count: int) -> void:
	var w := CELL * count + PAD * 2
	var h := CELL * 2 + PAD * 3
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.07, 0.08, 0.10, 1.0))
	for row in range(2):
		for i in range(count):
			var car: Dictionary = Cars.get_car(i)
			var shot: Image = await rasters[i].shot(car, Color(str(car.color)), row == 1)
			if shot != null:
				img.blend_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()),
					Vector2i(PAD + CELL * i, PAD + row * (CELL + PAD)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var path := ProjectSettings.globalize_path("res://shots/qa_silhouette.png")
	img.save_png(path)
	print("[qa] wrote ", path, " ", img.get_size())


# Solid pixels of one car: where the body is opaque, and how bright it is there.
func _mask_of(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var tone := {}
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in range(h):
		for x in range(w):
			var col := img.get_pixel(x, y)
			# A>0.9 keeps the soft drop shadow out: it fades over a wide margin,
			# every car has it, and it would flatten the differences.
			if col.a > 0.9:
				tone[Vector2i(x, y)] = col
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	var px := {}
	for k in tone:
		px[k] = true
	return {
		"px": px,
		"tone": tone,
		"filled": float(px.size()) / float(w * h),
		"bbox": Rect2i(Vector2i(x0, y0), Vector2i(x1 - x0 + 1, y1 - y0 + 1)),
	}


# Appearance difference: both cars normalised into the same box, then every
# cell compared by tone. Empty space is "no car", not "black car".
func _diff(a: Image, b: Image) -> float:
	var ma := _mask_of(a)
	var mb := _mask_of(b)
	var ga := _grid(ma, NORM_W, NORM_H, true)
	var gb := _grid(mb, NORM_W, NORM_H, true)
	var total := 0.0
	for i in range(ga.size()):
		var av: float = ga[i]
		var bv: float = gb[i]
		var empty_a := av < 0.0
		var empty_b := bv < 0.0
		if empty_a and empty_b:
			continue
		if empty_a or empty_b:
			total += 1.0
			continue
		total += absf(av - bv)
	return 100.0 * total / float(ga.size())


# Coverage: share of solid pixels that coincide, at real size, centred.
func _cover(a: Image, b: Image) -> float:
	var ga := _grid(_mask_of(a), 0, 0, false)
	var gb := _grid(_mask_of(b), 0, 0, false)
	var inter := 0
	var total_a := 0
	var total_b := 0
	for i in range(ga.size()):
		if ga[i] >= 0.0:
			total_a += 1
			if gb[i] >= 0.0:
				inter += 1
	for i in range(gb.size()):
		if gb[i] >= 0.0:
			total_b += 1
	return 100.0 * float(inter) / float(maxi(mini(total_a, total_b), 1))


# Rasterise one car into a grid. Normalised grids use a fixed box; raw grids
# keep pixel units and line the two cars up on their common centre.
func _grid(m: Dictionary, w: int, h: int, normalise: bool) -> PackedFloat32Array:
	var bbox: Rect2i = m.bbox
	var ca := _centre(bbox)
	var gw := w
	var gh := h
	var sx := 1.0
	var sy := 1.0
	if normalise:
		sx = float(w) / float(bbox.size.x)
		sy = float(h) / float(bbox.size.y)
	else:
		gw = bbox.size.x + 2 * (CELL - bbox.size.x) + 8
		gh = bbox.size.y + 2 * (CELL - bbox.size.y) + 8
		gw = maxi(gw, CELL + 8)
		gh = maxi(gh, CELL + 8)
	var acc := PackedFloat32Array()
	acc.resize(gw * gh)
	acc.fill(-1.0)
	var cnt := PackedInt32Array()
	cnt.resize(gw * gh)
	var half := Vector2i(gw / 2, gh / 2)
	for k in m.tone:
		var v: Vector2i = k
		var col: Color = m.tone[v]
		var x := int(round(float(v.x - ca.x) * sx)) + half.x
		var y := int(round(float(v.y - ca.y) * sy)) + half.y
		if x < 0 or y < 0 or x >= gw or y >= gh:
			continue
		var i := y * gw + x
		var t: float = (col.get_luminance() + col.v) * 0.5
		if cnt[i] == 0:
			acc[i] = t
		else:
			acc[i] = (acc[i] * float(cnt[i]) + t) / float(cnt[i] + 1)
		cnt[i] += 1
	return acc


func _centre(b: Rect2i) -> Vector2i:
	return Vector2i(b.position.x + b.size.x / 2, b.position.y + b.size.y / 2)
