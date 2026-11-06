class_name Fx
extends RefCounted

# Lighting, weather and atmosphere rendering. Everything here is either a
# precomputed light texture (generated once at start-up) or cheap per-frame
# compositing, so the GL-Compatibility mobile renderer keeps a stable frame time.
#
# Coordinate contract: top-down world, car-local +Y is "backwards". A traffic
# car's headlights therefore point UP the screen (negative Y) and the player's
# headlights point DOWN the screen (positive Y). Drawing with draw_set_transform
# lets the very same beam textures serve both directions.

# --- textures ---------------------------------------------------------------

# Additive radial falloff. 1.0 in the middle, smooth quartic tail, no fringes.
static func glow_tex(size := 128) -> ImageTexture:
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	var mid := float(size - 1) * 0.5
	var inv := 1.0 / mid
	for y in range(size):
		var dy := (float(y) - mid) * inv
		for x in range(size):
			var dx := (float(x) - mid) * inv
			var d := sqrt(dx * dx + dy * dy)
			var a := clampf(1.0 - d, 0.0, 1.0)
			a = a * a * (1.4 + 0.6 * a)
			a += 0.35 * clampf(1.0 - d * 2.4, 0.0, 1.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# A headlight spot as seen from above: origin at the lamp (top edge of the
# image), beam running to the bottom. The shape is built from a physical-looking
# model, not from a painted triangle:
#   * the beam fans out with a soft-ish edge and a gently widening low beam,
#   * light intensity falls with distance so the road not far ahead is not lit,
#   * a low-beam "asymmetric cutoff" puts the hotspot a little off-centre,
#     which is what makes a real headlight pool look lopsided on the tarmac,
#   * two U-shaped pools inside the cone reproduce the classic overlapping
#     low-beam pattern close to the bumper.
# The result is stored as intensity (white alpha) and tinted by the caller.
static func headlight_tex(w := 192, h := 512) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mid := float(w - 1) * 0.5
	for y in range(h):
		var v := float(y) / float(h - 1)  # 0 at the lamp, 1 at the far end
		# Low beam: stays bright for the first half, then dies out.
		var reach := pow(clampf(1.0 - v, 0.0, 1.0), 1.35)
		# Hotspot just beyond the cutoff shield, slightly off to one side.
		var hot := exp(-pow((v - 0.30) / 0.16, 2.0))
		# Half-width grows with distance; the very edge of the frame fades.
		var halfw := 0.30 + 0.62 * pow(v, 0.62)
		# Asymmetric cutoff: the right side of the beam is a touch taller.
		var skew := 0.05 * sin(v * PI)
		for x in range(w):
			var nx := (float(x) - mid) / mid
			var edge_pos := (nx - skew) / halfw
			var edge := 1.0 - absf(edge_pos)
			if edge <= 0.0:
				continue
			var profile := pow(edge, 0.85)
			# Brighter centre line, like a projector lens hotspot.
			var centre := exp(-pow(nx / (halfw * 0.36), 2.0))
			var zone := exp(-pow((v - 0.16) / 0.10, 2.0)) * exp(-pow(nx / (halfw * 0.62), 2.0))
			var a := profile * (0.42 * reach + 0.50 * hot + 0.16 * centre + 0.32 * zone)
			# Soften the lamp edge so the cone does not start with a hard line.
			a *= smoothstep(0.0, 0.035, v)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf(a, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# Vertical light streak used for reflections in wet tarmac and for the light
# smeared along a rain-soaked surface. Bright in the middle, fades at both ends.
static func streak_tex(w := 32, h := 128) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mid := float(w - 1) * 0.5
	for y in range(h):
		var v := float(y) / float(h - 1)
		# Reflections are strongest close to what they reflect.
		var along := pow(1.0 - v, 1.25)
		for x in range(w):
			var dx := absf((float(x) - mid) / mid)
			var across := pow(clampf(1.0 - dx, 0.0, 1.0), 1.6)
			var core := pow(clampf(1.0 - dx * 2.2, 0.0, 1.0), 2.0)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf((across * 0.62 + core * 0.5) * along, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# Tiled wet-asphalt microtexture: fine grain plus soft streaks along the
# driving axis and a sparse glitter of droplets. Used as an additive layer.
static func wet_tex(size := 256, seed_val := 6631) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	for y in range(size):
		for x in range(size):
			var n := rng.randf()
			img.set_pixel(x, y, Color(1, 1, 1, n * 0.10))
	# Vertical sheen streaks.
	for i in range(26):
		var cx := rng.randf() * float(size)
		var wdt := rng.randf_range(2.0, 9.0)
		var amt := rng.randf_range(0.05, 0.16)
		for y in range(size):
			for x in range(int(cx - wdt), int(cx + wdt) + 1):
				if x < 0 or x >= size:
					continue
				var d := absf(float(x) - cx) / wdt
				var a: float = img.get_pixel(x, y).a + amt * pow(clampf(1.0 - d, 0.0, 1.0), 1.5)
				img.set_pixel(x, y, Color(1, 1, 1, clampf(a, 0.0, 0.6)))
	# Droplet glitter.
	for i in range(size * 3):
		var px := rng.randi_range(0, size - 1)
		var py := rng.randi_range(0, size - 1)
		img.set_pixel(px, py, Color(1, 1, 1, minf(0.75, img.get_pixel(px, py).a + rng.randf_range(0.15, 0.45))))
	return ImageTexture.create_from_image(img)


# Rain streak: a thin, slightly tapered needle with a soft horizontal falloff
# that is a few pixels wide but still clearly visible by itself. Drawn under a
# rotation transform with its "head" at the bottom of the rect.
static func rain_tex(w := 16, h := 96) -> ImageTexture:
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var mid := float(w - 1) * 0.5
	for y in range(h):
		var v := float(y) / float(h - 1)  # 0 = tail, 1 = head
		var along := smoothstep(0.0, 0.55, v) * (0.55 + 0.45 * v)
		for x in range(w):
			var dx := absf((float(x) - mid) / mid)
			var body := pow(clampf(1.0 - dx, 0.0, 1.0), 1.55)
			var core := pow(clampf(1.0 - dx * 2.2, 0.0, 1.0), 1.6)
			img.set_pixel(x, y, Color(1.0, 1.0, 1.0, clampf((body * 0.62 + core * 0.58) * along, 0.0, 1.0)))
	return ImageTexture.create_from_image(img)


# --- drawing helpers --------------------------------------------------------

# Additive-or-not textured ellipse: a radial texture stretched into an oval.
static func pool(ci: CanvasItem, tex: Texture2D, center: Vector2, radius: float, col: Color, stretch := Vector2.ONE, rot := 0.0) -> void:
	if tex == null or col.a <= 0.002:
		return
	var r := Vector2(radius * stretch.x, radius * stretch.y)
	if rot != 0.0:
		ci.draw_set_transform(center, rot, Vector2.ONE)
		ci.draw_texture_rect(tex, Rect2(-r, r * 2.0), false, col)
		ci.draw_set_transform(Vector2.ZERO)
	else:
		ci.draw_texture_rect(tex, Rect2(center - r, r * 2.0), false, col)


# A headlight beam. origin = lamp, dir = unit-ish direction of travel,
# spread = half-angle-ish width scale, length = throw in pixels.
static func beam(ci: CanvasItem, tex: Texture2D, origin: Vector2, angle: float, width: float, length: float, col: Color) -> void:
	if tex == null or col.a <= 0.002:
		return
	ci.draw_set_transform(origin, angle, Vector2.ONE)
	ci.draw_texture_rect(tex, Rect2(-width * 0.5, 0.0, width, length), false, col)
	ci.draw_set_transform(Vector2.ZERO)


# Soft vertical gradient rectangle (4 colours, top to bottom) built once per
# call; cheap enough for the few full-screen washes the scene needs.
static func vgrad(ci: CanvasItem, rect: Rect2, top: Color, bottom: Color) -> void:
	ci.draw_polygon(
		PackedVector2Array([
			rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
		]),
		PackedColorArray([top, top, bottom, bottom])
	)


static func hgrad(ci: CanvasItem, rect: Rect2, left: Color, right: Color) -> void:
	ci.draw_polygon(
		PackedVector2Array([
			rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y),
		]),
		PackedColorArray([left, right, right, left])
	)
