class_name RoadsideArt
extends Node

# A single procedural atlas: detailed foliage costs one textured quad per plant
# during play. All random choices happen at bake time, never in the draw loop.
const CELL := 128
const PIXELS := 192
const COLS := 8
const VARIANTS := 4
const TYPES := 15
const OAK := 0
const BIRCH := 1
const SPRUCE := 2
const PINE := 3
const SHRUB := 4
const FLOWERS := 5
const ROCK := 6
const FERN := 7
const LOG := 8
const PICNIC := 9
const CABINET := 10
const FENCE := 11
const DRAIN := 12
const WORKS := 13
const MARKER := 14
const HOUSE := 15
const SHOP := 16
const BARN := 17
const GARAGE := 18
const APARTMENT := 19
const BUILDINGS := preload("res://art/roadside/buildings.gd")
var atlas: ImageTexture
var building_textures: Array[Texture2D] = []
var building_shadows: Array[Texture2D] = []
var building_entries: Array = []


class Sheet extends Node2D:
	func _draw() -> void:
		for kind in range(TYPES):
			for variant in range(VARIANTS):
				var index := kind * VARIANTS + variant
				draw_set_transform(Vector2((index % COLS) * CELL + CELL / 2,
					int(index / COLS) * CELL + CELL / 2))
				RoadsideArt.paint(self, kind, variant)


func _ready() -> void:
	var vp := SubViewport.new()
	vp.size = Vector2i(COLS * PIXELS, int(ceil(float(TYPES * VARIANTS) / COLS)) * PIXELS)
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.render_target_update_mode = SubViewport.UPDATE_ONCE
	vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
	var sheet := Sheet.new()
	sheet.scale = Vector2.ONE * float(PIXELS) / float(CELL)
	vp.add_child(sheet)
	add_child(vp)
	await RenderingServer.frame_post_draw
	if not is_inside_tree():
		return
	var img := vp.get_texture().get_image()
	if img != null and not img.is_empty():
		img.generate_mipmaps()
		atlas = ImageTexture.create_from_image(img)
	vp.queue_free()
	building_entries = BUILDINGS.ENTRIES
	for entry in building_entries:
		building_textures.append(load(entry.path))
		building_shadows.append(load(entry.shadow_path))


func draw_building(ci: CanvasItem, street_edge: Vector2, kind: int,
		variant: int, size: float, side: float, ambient: Color, canvas_offset := Vector2.ZERO, sun_strength := 1.0) -> void:
	if building_textures.is_empty():
		return
	var index := posmod(variant, 2) if kind == APARTMENT else 2 + kind - HOUSE
	var entry: Dictionary = building_entries[index]
	var texture: Texture2D = building_textures[index]
	# Match the car's ~1.8 m width. Both footprint and height come from the 3D
	# camera, and the anchor is a projected ground point, not a rotated facade.
	var scale_to_world := (86.0 / 1.8) * size / float(entry.pixels_per_metre)
	# Translate the same world-lit render to either verge. Mirroring it would
	# reverse the sun direction on the right-hand side of the road.
	var anchor: Vector2 = entry.anchor
	if side > 0:
		anchor.x = entry.solid_bounds.position.x
	ci.draw_set_transform(street_edge + canvas_offset, 0.0, Vector2.ONE * scale_to_world)
	if sun_strength > 0.01:
		ci.draw_texture_rect(building_shadows[index], Rect2(-anchor, texture.get_size()), false, Color(1, 1, 1, sun_strength))
	ci.draw_texture_rect(texture, Rect2(-anchor, texture.get_size()), false, ambient)
	ci.draw_set_transform(canvas_offset)


static func building_bounds(street_edge: Vector2, kind: int, variant: int,
		size: float, side: float) -> Rect2:
	var index := posmod(variant, 2) if kind == APARTMENT else 2 + kind - HOUSE
	var entry: Dictionary = BUILDINGS.ENTRIES[index]
	var scale_to_world := (86.0 / 1.8) * size / float(entry.pixels_per_metre)
	var bounds: Rect2 = entry.solid_bounds
	var anchor: Vector2 = entry.anchor
	if side > 0:
		anchor.x = bounds.position.x
	var a: Vector2 = (bounds.position - anchor) * scale_to_world
	var b: Vector2 = (bounds.end - anchor) * scale_to_world
	return Rect2(street_edge + a, b - a)


func draw_prop(ci: CanvasItem, p: Vector2, kind: int, variant: int,
		size: float, ambient: Color) -> bool:
	if atlas == null:
		return false
	var index := kind * VARIANTS + posmod(variant, VARIANTS)
	var source := Rect2((index % COLS) * PIXELS, int(index / COLS) * PIXELS, PIXELS, PIXELS)
	ci.draw_texture_rect_region(atlas, Rect2(p - Vector2.ONE * CELL * size * 0.5,
		Vector2.ONE * CELL * size), source, ambient)
	return true


static func _blob(ci: CanvasItem, p: Vector2, radius: float, col: Color,
		rng: RandomNumberGenerator, stretch := Vector2.ONE) -> void:
	var points := PackedVector2Array()
	for i in range(20):
		var angle := TAU * float(i) / 20.0
		points.append(p + Vector2(cos(angle), sin(angle)) * radius * rng.randf_range(0.88, 1.10) * stretch)
	ci.draw_colored_polygon(points, col)
	points.append(points[0])
	ci.draw_polyline(points, col.lightened(0.06), 0.65, true)


static func _shadow(ci: CanvasItem, p: Vector2, radius: float,
		rng: RandomNumberGenerator, stretch := Vector2.ONE) -> void:
	for i in range(3):
		_blob(ci, p + Vector2(6, 8), radius + float(2 - i) * 2.0,
			Color(0.025, 0.045, 0.025, 0.055 + float(i) * 0.025), rng, stretch)


static func paint(ci: CanvasItem, kind: int, variant: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 18793 + kind * 911 + variant * 137
	if kind <= PINE:
		_tree(ci, kind, variant, rng)
	elif kind == SHRUB:
		for i in range(7):
			var p := Vector2(rng.randf_range(-22, 22), rng.randf_range(-15, 15))
			_crown(ci, p, rng.randf_range(9, 16), Color("#436b39").lerp(Color("#78804b"), variant * 0.18), rng, 16)
		if variant == 2:
			for i in range(19):
				ci.draw_circle(Vector2(rng.randf_range(-26, 26), rng.randf_range(-20, 20)), 1.4, Color("#ba6553"))
	elif kind == FLOWERS:
		_meadow(ci, variant, rng)
	elif kind == ROCK:
		for i in range(3):
			var p := Vector2(rng.randf_range(-15, 15), rng.randf_range(-12, 12))
			var r := rng.randf_range(7, 17)
			_shadow(ci, p, r, rng, Vector2(1.2, 0.8))
			_blob(ci, p, r, Color("#686d60"), rng, Vector2(1.2, 0.8))
			ci.draw_colored_polygon(PackedVector2Array([p + Vector2(-r, -r * 0.3), p + Vector2(-r * 0.3, -r * 0.7), p + Vector2(r * 0.65, -r * 0.3), p + Vector2(r * 0.1, r * 0.35)]), Color("#9b9d86"))
			ci.draw_line(p + Vector2(-r * 0.25, -r * 0.55), p + Vector2(r * 0.1, r * 0.35), Color("#b4b39a"), 1, true)
			_blob(ci, p + Vector2(-r * 0.5, r * 0.35), r * 0.3, Color("#647343"), rng)
	elif kind == FERN:
		for i in range(9):
			var angle := TAU * i / 9.0 + variant * 0.3
			var tip := Vector2(cos(angle), sin(angle)) * rng.randf_range(19, 32)
			ci.draw_line(Vector2.ZERO, tip, Color("#8b9c51"), 1.2, true)
			for j in range(2, 8):
				var t := j / 9.0
				var base := tip * t
				var wing := tip.orthogonal().normalized() * (1.0 - t) * 9.0
				for side in [-1, 1]:
					ci.draw_colored_polygon(PackedVector2Array([base - tip * 0.09, base + wing * side + tip * 0.1, base + tip * 0.13]), Color("#4f7d40").lightened(t * 0.18))
	elif kind == LOG:
		ci.draw_line(Vector2(-28, 12), Vector2(27, -7), Color(0, 0, 0, 0.2), 17, true)
		ci.draw_line(Vector2(-28, 6), Vector2(25, -13), Color("#4b3d2a"), 14, true)
		ci.draw_line(Vector2(-28, 2), Vector2(25, -17), Color("#8b7850"), 3, true)
		ci.draw_line(Vector2(-2, -4), Vector2(-8, -20), Color("#5d4e32"), 5, true)
		ci.draw_circle(Vector2(25, -13), 7, Color("#b79d6b"))
		ci.draw_arc(Vector2(25, -13), 4, 0, TAU, 16, Color("#75613f"), 1, true)
		for i in range(12):
			ci.draw_circle(Vector2(rng.randf_range(-25, 15), rng.randf_range(-5, 3)), rng.randf_range(1, 3), Color("#6d8244"))
	else:
		_furniture(ci, kind, variant, rng)


static func _furniture(ci: CanvasItem, kind: int, variant: int, rng: RandomNumberGenerator) -> void:
	if kind == PICNIC:
		# A gravel turnout, timber table and two benches, seen from above.
		_blob(ci, Vector2.ZERO, 43, Color("#8b886c"), rng, Vector2(0.85, 1.1))
		for i in range(65):
			var p := Vector2(rng.randf_range(-29, 29), rng.randf_range(-35, 35))
			ci.draw_circle(p, rng.randf_range(0.4, 1.1), Color("#aeab8e"))
		ci.draw_rect(Rect2(-19, -21, 44, 51), Color(0, 0, 0, 0.18))
		for x in [-24, 18]:
			ci.draw_rect(Rect2(x, -24, 7, 48), Color("#504330"))
			ci.draw_rect(Rect2(x, -24, 5, 47), Color("#b09a65"))
			ci.draw_line(Vector2(x + 2, -22), Vector2(x + 2, 22), Color("#d1b57a"), 1, true)
		for x in range(-12, 14, 6):
			ci.draw_rect(Rect2(x, -22, 5, 44), Color("#9b794c").lightened(variant * 0.025))
			ci.draw_line(Vector2(x + 1, -20), Vector2(x + 1, 20), Color("#c3a36b"), 0.8, true)
			for y in [-17, 17]:
				ci.draw_circle(Vector2(x + 2, y), 0.8, Color("#514733"))
	elif kind == CABINET:
		ci.draw_rect(Rect2(-24, -30, 48, 60), Color("#8c8e80"))
		ci.draw_rect(Rect2(-13, -19, 35, 47), Color(0, 0, 0, 0.2))
		ci.draw_rect(Rect2(-17, -24, 32, 44), Color("#535e5c"))
		ci.draw_rect(Rect2(-17, -24, 29, 39), Color("#a1aaa0").darkened(variant * 0.04))
		ci.draw_rect(Rect2(-16, -24, 28, 3), Color("#c4cabc"))
		ci.draw_line(Vector2(-2, -18), Vector2(-2, 13), Color("#626e68"), 1, true)
		ci.draw_rect(Rect2(6, -5, 2, 6), Color("#3b4543"))
		for y in range(3, 13, 3):
			ci.draw_line(Vector2(-12, y), Vector2(-6, y), Color("#5b6861"), 1, true)
		ci.draw_colored_polygon(PackedVector2Array([Vector2(4, -15), Vector2(9, -7), Vector2(-1, -7)]), Color("#ddbf57"))
		ci.draw_line(Vector2(4, -12), Vector2(3, -9), Color("#51452a"), 1, true)
	elif kind == FENCE:
		ci.draw_line(Vector2(5, -47), Vector2(5, 47), Color(0, 0, 0, 0.18), 11, true)
		for x in [-7, 4]:
			ci.draw_line(Vector2(x, -46), Vector2(x, 46), Color("#685639"), 5, true)
			ci.draw_line(Vector2(x - 1, -46), Vector2(x - 1, 46), Color("#a18a5c"), 1.5, true)
		for y in [-42, 0, 42]:
			ci.draw_rect(Rect2(-11, y - 5, 22, 10), Color("#5a4a33"))
			ci.draw_rect(Rect2(-11, y - 5, 20, 3), Color("#b8a077"))
			ci.draw_circle(Vector2(-4, y), 1.3, Color("#403b2f"))
	elif kind == DRAIN:
		ci.draw_rect(Rect2(-18, -33, 36, 66), Color("#8a8b7c"))
		ci.draw_rect(Rect2(-13, -28, 26, 56), Color("#363e39"))
		for y in range(-26, 28, 6):
			ci.draw_rect(Rect2(-11, y, 22, 3), Color("#737b6d"))
			ci.draw_line(Vector2(-11, y), Vector2(11, y), Color("#abb09a"), 0.8, true)
		for x in [-14, 14]:
			ci.draw_line(Vector2(x, -29), Vector2(x, 29), Color("#b3b3a0"), 1, true)
	elif kind == WORKS:
		# Maintenance supplies: cones, a cable reel and a closed tool case.
		ci.draw_circle(Vector2(5, 3), 16, Color(0, 0, 0, 0.2))
		ci.draw_circle(Vector2(0, -3), 15, Color("#92764e"))
		ci.draw_arc(Vector2(0, -3), 11, 0, TAU, 24, Color("#c0a474"), 2, true)
		ci.draw_circle(Vector2(0, -3), 4, Color("#514b38"))
		for p in [Vector2(-25, -24), Vector2(25, 22), Vector2(-20, 25)]:
			ci.draw_rect(Rect2(p - Vector2(7, 7), Vector2(16, 16)), Color(0, 0, 0, 0.16))
			ci.draw_rect(Rect2(p - Vector2(7, 7), Vector2(14, 14)), Color("#4b4939"))
			ci.draw_circle(p, 6, Color("#d8773d"))
			ci.draw_circle(p - Vector2(1, 1), 3.8, Color("#e4d4b0"))
			ci.draw_circle(p - Vector2(1.5, 2), 2, Color("#ef9c54"))
		ci.draw_rect(Rect2(17, -27, 16, 11), Color("#576760"))
		ci.draw_rect(Rect2(18, -27, 14, 2), Color("#96a39a"))
	elif kind == MARKER:
		ci.draw_line(Vector2(3, -7), Vector2(7, 12), Color(0, 0, 0, 0.2), 7, true)
		ci.draw_style_box(Art._sb(Color("#dadbca"), 2, Color("#949c8c"), 1), Rect2(-5, -13, 10, 25))
		ci.draw_rect(Rect2(-4, -8, 8, 8), Color("#3b443f"))
		ci.draw_rect(Rect2(-2, -6, 4, 4), Color("#dd9453") if variant % 2 == 0 else Color("#dbdec4"))


static func _crown(ci: CanvasItem, p: Vector2, r: float, col: Color,
		rng: RandomNumberGenerator, leaves: int) -> void:
	_shadow(ci, p, r, rng)
	_blob(ci, p, r, col.darkened(0.28), rng)
	_blob(ci, p + Vector2(-r * 0.12, -r * 0.17), r * 0.86, col, rng)
	_blob(ci, p + Vector2(-r * 0.25, -r * 0.29), r * 0.53, col.lightened(0.14), rng)
	for i in range(leaves):
		var angle := rng.randf() * TAU
		var q := p + Vector2(cos(angle), sin(angle)) * sqrt(rng.randf()) * r * 0.85
		var light := clampf(0.14 - (q.x - p.x + q.y - p.y) / r * 0.17, -0.16, 0.32)
		var leaf_col := col.lightened(light) if light > 0 else col.darkened(-light)
		var d := rng.randf_range(1.5, 3.5)
		ci.draw_line(q, q + Vector2(d, -d * 0.5), leaf_col, d * 0.7, true)


static func _tree(ci: CanvasItem, kind: int, variant: int, rng: RandomNumberGenerator) -> void:
	_shadow(ci, Vector2.ZERO, 42, rng, Vector2(0.95, 0.90))
	ci.draw_line(Vector2(7, 23), Vector2(-3, -18), Color("#584932"), 7, true)
	if kind == BIRCH:
		ci.draw_line(Vector2(6, 22), Vector2(-3, -18), Color("#d4d0ad"), 4, true)
		for i in range(5):
			ci.draw_line(Vector2(2, i * 6 - 9), Vector2(6, i * 6 - 9), Color("#514f41"), 1.5, true)
	if kind == SPRUCE or kind == PINE:
		var base := Color("#305f4a") if kind == SPRUCE else Color("#4e7446")
		base = base.lightened(variant * 0.025)
		for ring in range(4):
			var r := 43.0 - ring * 9.0
			var center := Vector2(-ring * 1.4, -ring * 2.0)
			var pts := PackedVector2Array()
			for j in range(24):
				var a := j * TAU / 24.0 + variant * 0.7 + ring * 0.24
				var length := r * (rng.randf_range(0.86, 1.08) if j % 2 == 0 else rng.randf_range(0.48, 0.63))
				pts.append(center + Vector2(cos(a), sin(a)) * length)
			ci.draw_colored_polygon(pts, base.darkened(0.20 - ring * 0.10))
			for j in range(0, 24, 2):
				var tip := pts[j]
				ci.draw_line(center, tip, base.lightened(0.06 + ring * 0.025), 1.1, true)
				for k in range(2, 6):
					var q := center.lerp(tip, k / 7.0)
					var wing := (tip - center).orthogonal().normalized() * (7 - k) * 1.6
					for side in [-1, 1]:
						var needle: Vector2 = q + wing * side - (tip - center) * 0.07
						ci.draw_colored_polygon(PackedVector2Array([q - (tip - center) * 0.12, needle, q + (tip - center) * 0.16]), base.lightened(rng.randf_range(0.02, 0.14)))
		_crown(ci, Vector2(-5, -8), 7, base.lightened(0.1), rng, 12)
		if kind == PINE:
			for i in range(5):
				_crown(ci, Vector2.from_angle(i * TAU / 5.0) * 22.0, 16, base, rng, 15)
	else:
		var col := Color("#46713d") if kind == OAK else Color("#719351")
		if variant == 3:
			col = Color("#8c8644") if kind == OAK else Color("#a3a15c")
		for i in range(9):
			var a := i * TAU / 9.0 + variant * 0.7
			var p := Vector2(cos(a), sin(a)) * rng.randf_range(20, 29)
			if kind == BIRCH:
				p.x *= 0.77
			ci.draw_line(Vector2.ZERO, p, Color("#72664a"), 2.5, true)
			_crown(ci, p, rng.randf_range(13, 20), col.darkened(rng.randf_range(0, 0.12)), rng, 30)
		_crown(ci, Vector2(-4, -8), 23, col.lightened(0.07), rng, 45)


static func _meadow(ci: CanvasItem, variant: int, rng: RandomNumberGenerator) -> void:
	var flower := [Color("#e3cf78"), Color("#dfddd0"), Color("#a99ac5"), Color("#d2ad75")]
	# Low-contrast soil and moss tie the stems into the terrain.
	_blob(ci, Vector2.ZERO, 34, Color(0.22, 0.29, 0.12, 0.15), rng, Vector2(1.1, 0.8))
	_blob(ci, Vector2(-8, 3), 24, Color(0.45, 0.40, 0.23, 0.12), rng)
	for i in range(65):
		var p := Vector2(rng.randf_range(-37, 37), rng.randf_range(-26, 26))
		if p.length() > 37:
			continue
		var h := rng.randf_range(3, 10)
		ci.draw_line(p + Vector2(2, 2), p + Vector2(4, -h), Color(0.1, 0.17, 0.08, 0.18), 1, true)
		ci.draw_line(p, p + Vector2(-2, -h), Color("#85924f").darkened(rng.randf_range(0, 0.3)), 1.2, true)
		ci.draw_line(p, p + Vector2(3, -h * 0.6), Color("#a0a063"), 1, true)
		if i % 3 == 0:
			var tip := p + Vector2(-2, -h)
			for petal in range(4):
				ci.draw_circle(tip + Vector2.from_angle(petal * TAU / 4.0) * 1.5, 1.3, flower[variant])
			ci.draw_circle(tip, 0.8, Color("#c3a64b"))
