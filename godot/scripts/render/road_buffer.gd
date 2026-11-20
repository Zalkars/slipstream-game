class_name RoadBuffer
extends Node

# Accumulation buffer for marks that live ON the road: tyre marks, wet tyre
# tracks, spark scorches. It is a ring of road rows in a SubViewport that is
# never cleared as a whole: a mark is drawn into it exactly once, the frame it
# appears, and from then on costs nothing but the single textured quad that
# shows the buffer. Rows are recycled as they scroll off the bottom; the strip
# that is about to appear at the top is wiped just before it becomes visible.
#
# Road coordinate: v = screen_y - scroll is constant for a point painted on the
# asphalt, so a mark stored at v slides down with the road for free.

const AHEAD := 260.0  # rows wiped ahead of the top edge of the screen

var vp: SubViewport
var scale := 0.5
var ring_h := 2048.0
var x0 := 0.0
var width := 600.0
var _clear_layer: DrawLayer
var _stroke_layer: DrawLayer
var _strokes: Array = []      # strokes queued this frame (road coordinates)
var _clears: Array = []       # [v_from, v_to] strips queued this frame
var _full_clear := true
var _last_scroll := 0.0
var _cleared_top := 0.0       # smallest v already wiped ahead of the screen
var _dirty := false


func setup(p_x0: float, p_width: float, screen_h: float, p_scale: float) -> void:
	x0 = p_x0
	width = p_width
	scale = clampf(p_scale, 0.25, 1.0)
	ring_h = ceilf((screen_h + AHEAD * 2.0 + 64.0) / 256.0) * 256.0
	var size := Vector2i(maxi(8, int(ceil(width * scale))), maxi(8, int(ceil(ring_h * scale))))
	if vp == null:
		vp = SubViewport.new()
		vp.name = "RoadBufferView"
		vp.transparent_bg = true
		vp.disable_3d = true
		vp.gui_disable_input = true
		vp.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_LINEAR
		add_child(vp)
		_clear_layer = DrawLayer.new("Clear", 0, _paint_clears)
		var sh := Shader.new()
		sh.code = "shader_type canvas_item;\nrender_mode blend_disabled, unshaded;\nvoid fragment() { COLOR = vec4(0.0); }\n"
		var mat := ShaderMaterial.new()
		mat.shader = sh
		_clear_layer.material = mat
		vp.add_child(_clear_layer)
		_stroke_layer = DrawLayer.new("Strokes", 1, _paint_strokes)
		_stroke_layer.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		vp.add_child(_stroke_layer)
	vp.size = size
	_full_clear = true
	_strokes.clear()
	_clears.clear()


# --- strokes (screen coordinates at the current scroll) ----------------------

func line(a: Vector2, b: Vector2, w: float, col: Color, scroll: float) -> void:
	if _strokes.size() > 900:
		return
	_strokes.append([0, Vector2(a.x, a.y - scroll), Vector2(b.x, b.y - scroll), w, col])


func dot(p: Vector2, r: float, col: Color, scroll: float) -> void:
	if _strokes.size() > 900:
		return
	_strokes.append([1, Vector2(p.x, p.y - scroll), r, col])


# A textured ribbon segment (tread pattern): quad from a to b, width w, the
# texture's V coordinate runs along the road so the pattern stays continuous.
func ribbon(a: Vector2, b: Vector2, w: float, col: Color, tex: Texture2D, scroll: float) -> void:
	if _strokes.size() > 900:
		return
	_strokes.append([2, Vector2(a.x, a.y - scroll), Vector2(b.x, b.y - scroll), w, col, tex])


# --- per frame --------------------------------------------------------------

func update(scroll: float) -> void:
	if vp == null:
		return
	if scroll < _last_scroll - 0.5 or scroll - _last_scroll > ring_h * 0.5:
		# Rewind, a new run or a huge jump: the stored marks no longer match
		# the road under them.
		_full_clear = true
	if _full_clear:
		_cleared_top = -scroll - AHEAD
		_clears.clear()
	else:
		var new_top := -scroll - AHEAD
		if new_top < _cleared_top:
			_clears.append([new_top, _cleared_top])
			_cleared_top = new_top
	_last_scroll = scroll
	var work := _full_clear or not _clears.is_empty() or not _strokes.is_empty()
	if work:
		vp.render_target_clear_mode = SubViewport.CLEAR_MODE_ONCE if _full_clear else SubViewport.CLEAR_MODE_NEVER
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		_full_clear = false
		_dirty = true
		_clear_layer.queue_redraw()
		_stroke_layer.queue_redraw()
	elif _dirty:
		# Re-record empty layers so a later update cannot replay old strokes.
		_dirty = false
		_clear_layer.queue_redraw()
		_stroke_layer.queue_redraw()


func clear_all() -> void:
	_full_clear = true
	_strokes.clear()


# Shows the buffer: the visible screen rows map to at most two ring segments.
func draw_to(ci: CanvasItem, scroll: float, screen_h: float, modulate := Color.WHITE) -> void:
	if vp == null:
		return
	var tex := vp.get_texture()
	var r0 := fposmod(-scroll, ring_h)
	var first := minf(ring_h - r0, screen_h)
	ci.draw_texture_rect_region(tex, Rect2(x0, 0.0, width, first),
		Rect2(0.0, r0 * scale, width * scale, first * scale), modulate)
	if first < screen_h:
		var rest := screen_h - first
		ci.draw_texture_rect_region(tex, Rect2(x0, first, width, rest),
			Rect2(0.0, 0.0, width * scale, rest * scale), modulate)


# --- painters (inside the SubViewport, buffer pixels) ------------------------

func _row(v: float) -> float:
	return fposmod(v, ring_h) * scale


func _paint_clears(ci: CanvasItem) -> void:
	for c in _clears:
		var a := float(c[0])
		var b := float(c[1])
		var len := b - a
		if len >= ring_h:
			ci.draw_rect(Rect2(0, 0, width * scale + 2.0, ring_h * scale + 2.0), Color(0, 0, 0, 0))
			continue
		var y := _row(a)
		var h := len * scale
		ci.draw_rect(Rect2(0.0, y - 1.0, width * scale + 2.0, h + 2.0), Color(0, 0, 0, 0))
		if y + h > ring_h * scale:
			ci.draw_rect(Rect2(0.0, y - ring_h * scale - 1.0, width * scale + 2.0, h + 2.0), Color(0, 0, 0, 0))
	_clears.clear()


func _paint_strokes(ci: CanvasItem) -> void:
	var span := ring_h * scale
	for s in _strokes:
		var kind := int(s[0])
		var p: Vector2 = s[1]
		var base := Vector2((p.x - x0) * scale, _row(p.y))
		var shift := base.y - p.y * scale
		for k in [0.0, -span, span]:
			var off := Vector2(-x0 * scale, shift + k)
			match kind:
				0:
					var a: Vector2 = p * scale + off
					var b: Vector2 = Vector2(s[2]) * scale + off
					if maxf(a.y, b.y) < -8.0 or minf(a.y, b.y) > span + 8.0:
						continue
					ci.draw_line(a, b, s[4], maxf(1.0, float(s[3]) * scale), true)
				1:
					var c: Vector2 = p * scale + off
					if c.y < -16.0 or c.y > span + 16.0:
						continue
					ci.draw_circle(c, maxf(0.6, float(s[2]) * scale), s[3])
				2:
					var a2: Vector2 = p * scale + off
					var b2: Vector2 = Vector2(s[2]) * scale + off
					if maxf(a2.y, b2.y) < -8.0 or minf(a2.y, b2.y) > span + 8.0:
						continue
					var d := b2 - a2
					if d.length_squared() < 0.0001:
						continue
					var n := Vector2(-d.y, d.x).normalized() * float(s[3]) * scale * 0.5
					var tex: Texture2D = s[5]
					# V runs with the road coordinate, so the tread repeats.
					var v0 := float(p.y) / 24.0
					var v1 := float(Vector2(s[2]).y) / 24.0
					ci.draw_polygon(PackedVector2Array([a2 - n, a2 + n, b2 + n, b2 - n]),
						PackedColorArray([s[4], s[4], s[4], s[4]]),
						PackedVector2Array([Vector2(0, v0), Vector2(1, v0), Vector2(1, v1), Vector2(0, v1)]), tex)
	_strokes.clear()
