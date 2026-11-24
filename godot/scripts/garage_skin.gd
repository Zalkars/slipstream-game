extends RefCounted

const INK := Color("#f3f4f7")
const MUTED := Color("#b3bbc9")
const ACCENT := Color("#ffac68")
const WARM_TEXT := Color("#ffcf9f")

var body: Font = ThemeDB.fallback_font
var bold := FontVariation.new()
var display := FontVariation.new()
var _surfaces: Dictionary = {}


func _init() -> void:
	bold.base_font = body
	bold.variation_embolden = 0.65
	display.base_font = preload("res://fonts/Orbitron.ttf")
	display.variation_opentype = {0x77676874: 760.0} # OpenType wght.


func flat(fill: Color, stroke: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = stroke
	style.set_border_width_all(2)
	style.set_corner_radius_all(radius)
	return style


# Nine-slice textures keep the rounded edges at the same radius across screen sizes.
func gradient(top: Color, bottom: Color, stroke: Color, radius: int) -> StyleBoxTexture:
	var key := [top, bottom, stroke, radius]
	var texture: ImageTexture = _surfaces.get(key)
	if texture == null:
		const SIDE := 72
		const CENTER := Vector2(36, 36)
		var image := Image.create_empty(SIDE, SIDE, false, Image.FORMAT_RGBA8)
		for y in range(SIDE):
			for x in range(SIDE):
				var delta := (Vector2(x + 0.5, y + 0.5) - CENTER).abs() - (CENTER - Vector2.ONE * radius)
				var distance := delta.max(Vector2.ZERO).length() + minf(maxf(delta.x, delta.y), 0.0) - radius
				var fill := top.lerp(bottom, float(x + y) / (2.0 * (SIDE - 1)))
				var color := fill.lerp(stroke, clampf(distance + 2.0, 0.0, 1.0)) if stroke.a > 0.0 else fill
				color.a *= clampf(0.5 - distance, 0.0, 1.0)
				image.set_pixel(x, y, color)
		texture = ImageTexture.create_from_image(image)
		_surfaces[key] = texture
	var style := StyleBoxTexture.new()
	style.texture = texture
	for side in [SIDE_LEFT, SIDE_TOP, SIDE_RIGHT, SIDE_BOTTOM]:
		style.set_texture_margin(side, radius + 1)
		style.set_content_margin(side, 0)
	return style


class Icon extends Control:
	var kind: String
	var tint: Color

	func _init(icon_kind: String, color: Color, dimension: float) -> void:
		kind = icon_kind
		tint = color
		custom_minimum_size = Vector2.ONE * dimension
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var center := size * 0.5
		var points := PackedVector2Array()
		match kind:
			"previous", "next", "back":
				var side := 1.0 if kind == "next" else -1.0
				points = PackedVector2Array([center + Vector2(-side * 5, -10),
					center + Vector2(side * 5, 0), center + Vector2(-side * 5, 10)])
				draw_polyline(points, tint, 3.5, true)
				if kind == "back":
					draw_line(center - Vector2(5, 0), center + Vector2(11, 0), tint, 3.5, true)
			"catalog":
				for x in [-10, 2]:
					for y in [-10, 2]:
						Art.rr(self, Rect2(center + Vector2(x, y), Vector2(8, 8)), tint, 2.0)
			"play":
				draw_arc(center, minf(size.x, size.y) * 0.48, 0, TAU, 40, Color(tint, 0.56), 2.0, true)
				draw_colored_polygon(PackedVector2Array([center + Vector2(-5, -9),
					center + Vector2(10, 0), center + Vector2(-5, 9)]), tint)
