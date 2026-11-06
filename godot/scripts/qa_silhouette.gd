extends SceneTree

# Pixel test for the car roster (Plan_0.5.0.md, stage 1).
#
# Every car is rendered on its own, in one flat colour, with stripes, spoiler,
# lamps and every body detail switched OFF. What is left is the top-down
# projection of the body: outline, proportions and glasshouse — the silhouette
# a player reads on the road.
#
# Two cars may overlap on at most 60 % of the pixels of their union, measured
# two ways, because the cars also have different overall sizes and a naive
# corner-anchored compare would punish a car for being longer:
#
#   BY SHAPE   both silhouettes scaled to the same bounding box. Iso-accuracy:
#              can two bodies be told apart at all?
#   AS DRAWN   pixels lined up on the car centre, world units preserved.
#              Iso-scale: can they be told apart at the size the game draws?
#
# The second number is the honest one for gameplay, the first one is the one
# that tells you whether a silhouette is lazy.
#
# Run (needs a renderer, i.e. no --headless):
#   godot --path godot --script res://scripts/qa_silhouette.gd
#   godot --path godot --script res://scripts/qa_silhouette.gd -- --png
#
# Exit 0 = every pair is distinct enough in both measures.

const CELL := 320
const PAD := 24
const NORM_W := 64
const NORM_H := 96
const MIN_DIFF := 15.0
const CUES := ["BODY+GLASS"]


class Raster extends SubViewport:
	# Draws one car inside a Viewport and reads the result back.
	var car: Dictionary = {}
	var colour := Color.BLACK
	var layer := 0

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
		Art.car(canvas, Vector2(size) * 0.5, float(size.x) * 0.50, float(size.y) * 0.80, colour, {
			"silhouette": str(car.get("silhouette", "")),
			"stripe": false,
			"wing": false,
			"player": false,
			"details": false,
			"body_only": layer == 0,
			"glass": layer == 1,
		})

	func shot(new_car: Dictionary, new_colour: Color, new_layer: int) -> Image:
		car = new_car
		colour = new_colour
		layer = new_layer
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
	for ci in range(CUES.size()):
		var masks: Array = []
		print("cue: %s" % CUES[ci])
		for i in range(count):
			var car: Dictionary = Cars.get_car(i)
			var img: Image = await rasters[i].shot(car, Color(0.62, 0.62, 0.62), ci)
			if img == null:
				printerr("QA_SILHOUETTE: read-back failed for %s" % car.name)
				quit(2)
				return
			masks.append(_mask_of(img))
			var m: Dictionary = masks[i]
			print("  %-9s filled=%5.1f%%  bbox=%s" % [car.name, m.filled * 100.0, str(m.bbox)])
			if m.filled < 0.05:
				printerr("QA_SILHOUETTE: %s rendered almost nothing" % car.name)
				ok = false

		for label in ["shape", "drawn"]:
			print("")
			print("  %s: pair                        diff   room" % label.to_upper())
			for i in range(count):
				for j in range(i + 1, count):
					var overlap: float = _overlap_shape(masks[i], masks[j]) if label == "shape" else _overlap_drawn(masks[i], masks[j])
					var bad: bool = overlap < MIN_DIFF
					if bad:
						ok = false
					print("    %-9s vs %-9s  %5.1f%%  %5.1f%%%s" % [
						Cars.get_car(i).name, Cars.get_car(j).name,
						overlap, overlap - MIN_DIFF,
						"   <-- TOO SIMILAR" if bad else "",
					])
		print("")

	if want_png:
		await _sheet(rasters, count)
	else:
		print("[qa] pass -- --png to also write the contact sheet")

	print("QA_SILHOUETTE: %s  [run %s]" % ["PASS" if ok else "FAIL", str(Time.get_ticks_msec())])
	quit(0 if ok else 1)


# Contact sheet: every car in its own paint, flat silhouette on the first row
# and fully detailed on the second, so the numbers can be checked with the eyes.
func _sheet(rasters: Array, count: int) -> void:
	var w := CELL * count + PAD * 2
	var h := CELL * 2 + PAD * 3
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.07, 0.08, 0.10, 1.0))
	for row in range(2):
		for i in range(count):
			var car: Dictionary = Cars.get_car(i)
			var shot: Image
			if row == 0:
				shot = await rasters[i].shot(car, Color(str(car.color)), 1)
			else:
				shot = await rasters[i].shot(car, Color(str(car.color)), 2)
			if shot != null:
				img.blend_rect(shot, Rect2i(Vector2i.ZERO, shot.get_size()),
					Vector2i(PAD + CELL * i, PAD + row * (CELL + PAD)))
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	var path := ProjectSettings.globalize_path("res://shots/qa_silhouette.png")
	img.save_png(path)
	print("[qa] wrote ", path, " ", img.get_size())


# Alpha mask cropped to the covered pixels.
func _mask_of(img: Image) -> Dictionary:
	var w := img.get_width()
	var h := img.get_height()
	var x0 := w
	var y0 := h
	var x1 := -1
	var y1 := -1
	for y in range(h):
		for x in range(w):
			if img.get_pixel(x, y).a > 0.9:
				x0 = mini(x0, x)
				y0 = mini(y0, y)
				x1 = maxi(x1, x)
				y1 = maxi(y1, y)
	if x1 < 0:
		return {"px": {}, "tone": {}, "filled": 0.0, "bbox": Rect2i()}
	var px := {}
	var tone := {}
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var col := img.get_pixel(x, y)
			# Only solid body pixels count. A soft drop shadow fades out over
			# a wide margin and every car would then share it, which hides
			# exactly the differences we are trying to measure.
			if col.a > 0.9:
				var at := Vector2i(x - x0, y - y0)
				px[at] = true
				tone[at] = col
	return {
		"px": px,
		"tone": tone,
		"filled": float(px.size()) / float(w * h),
		"bbox": Rect2i(Vector2i(x0, y0), Vector2i(x1 - x0 + 1, y1 - y0 + 1)),
	}


# Similarity of two cars as seen from above.
#
# An alpha mask only sees the outer boundary, and five road cars that share
# wheels, mirrors and pillars always share 75-90 % of their outline, so a
# coverage test alone cannot express "these are different cars". The cabin,
# the glazing and the roof creases are inside the outline and carry most of
# the identity, so the comparison works on appearance: each car is normalised
# into a 64 x 96 grid and each cell stores how bright that part of the car is.
# Two cars then differ where their glass, roofs and flanks are in different
# places, which is exactly what a player reads at a glance.
#
#   0 %  = identical from above, 100 % = nothing in common
func _overlap_shape(a: Dictionary, b: Dictionary) -> float:
	var ra := _normalise(a, NORM_W, NORM_H)
	var rb := _normalise(b, NORM_W, NORM_H)
	return _mean_abs_diff(ra, rb)


# Iso-scale: the same measure without normalising, so world size is preserved —
# what the player sees on the road, at the size the game draws the car.
func _overlap_drawn(a: Dictionary, b: Dictionary) -> float:
	var ba: Rect2i = a.bbox
	var bb: Rect2i = b.bbox
	var ca := _centre(ba)
	var cb := _centre(bb)
	var w := maxi(ba.size.x, bb.size.x) + 2 * absi(ca.x - cb.x) + 4
	var h := maxi(ba.size.y, bb.size.y) + 2 * absi(ca.y - cb.y) + 4
	return _mean_abs_diff(_paint(a, ca, w, h), _paint(b, cb, w, h))


func _normalise(m: Dictionary, w: int, h: int) -> PackedFloat32Array:
	var bbox: Rect2i = m.bbox
	return _paint(m, _centre(bbox), w, h, Vector2(float(w) / float(bbox.size.x), float(h) / float(bbox.size.y)))


# Rasterise a mask into a w x h grid of brightness values: 0.0 where the car is
# not there, otherwise the luminance the car was drawn with. Centred on
# `origin`, optionally scaled to a normalised box.
func _paint(m: Dictionary, origin: Vector2i, w: int, h: int, scale := Vector2.ONE) -> PackedFloat32Array:
	var acc := PackedFloat32Array()
	acc.resize(w * h)
	var cnt := PackedInt32Array()
	cnt.resize(w * h)
	var half := Vector2i(w / 2, h / 2)
	for k in m.px:
		var v: Vector2i = k
		var col: Color = m.tone[v]
		var p := Vector2(float(v.x - origin.x) * scale.x, float(v.y - origin.y) * scale.y)
		var x := int(round(p.x)) + half.x
		var y := int(round(p.y)) + half.y
		if x < 0 or y < 0 or x >= w or y >= h:
			continue
		var i := y * w + x
		acc[i] += col.get_luminance()
		cnt[i] += 1
	for i in range(acc.size()):
		if cnt[i] > 0:
			acc[i] = acc[i] / float(cnt[i])
		else:
			# empty space is treated as "background", not as "black car"
			acc[i] = -1.0
	return acc


# 0 % when the two appearance grids carry the same light, 100 % when one half
# of the car holds glass where the other holds paint or empty road.
func _mean_abs_diff(a: PackedFloat32Array, b: PackedFloat32Array) -> float:
	if a.size() != b.size() or a.is_empty():
		return 100.0
	var total := 0.0
	for i in range(a.size()):
		var av: float = a[i]
		var bv: float = b[i]
		var empty_a: bool = av < 0.0
		var empty_b: bool = bv < 0.0
		if empty_a and empty_b:
			continue
		if empty_a or empty_b:
			# a pixel where only one car exists: the full contrast of the body
			total += 1.0
			continue
		total += absf(av - bv)
	return 100.0 * total / float(a.size())

func _jaccard(a: PackedByteArray, b: PackedByteArray) -> float:
	if a.size() != b.size() or a.is_empty():
		return 0.0
	var inter := 0
	var either := 0
	for i in range(a.size()):
		var av := a[i]
		var bv := b[i]
		# Integer-typed locals: comparing untyped Variants here silently
		# reports a false negative in this engine build.
		var ai := int(av)
		var bi := int(bv)
		if ai > 0 and ai == bi:
			inter += 1
		if ai > 0 or bi > 0:
			either += 1
	return float(inter) / float(maxi(either, 1))

func _centre(b: Rect2i) -> Vector2i:
	return Vector2i(b.position.x + b.size.x / 2, b.position.y + b.size.y / 2)
