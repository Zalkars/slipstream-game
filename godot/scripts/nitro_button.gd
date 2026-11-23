class_name NitroButton
extends Control

# Press-to-fire nitro. The game handles a second press and reports full boost.
# Three full charges also arm the Chrono-Shield crash rewind.

signal tapped

const SEGMENTS := 3

var segments := SEGMENTS
var charge := 0.0
var active := false
var full_boost := false
var shield_ready := false
var label_font: Font
var _down := false
var _touch_id := -1
var _flash := 0.0
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(148, 148)
	set_process(true)


func reset() -> void:
	_touch_id = -1
	_down = false
	active = false
	full_boost = false
	shield_ready = false
	_flash = 0.0
	queue_redraw()


func set_segments(s: int) -> void:
	s = clampi(s, 1, 6)
	if segments != s:
		segments = s
		queue_redraw()


func set_charge(v: float) -> void:
	var max_v := float(segments) / float(SEGMENTS)
	v = clampf(v, 0.0, max_v)
	if absf(v - charge) > 0.002:
		if v > charge + 0.05:
			_flash = 1.0
		charge = v
		queue_redraw()


func set_active(v: bool, full := false) -> void:
	if active != v or full_boost != full:
		active = v
		full_boost = full
		queue_redraw()


func set_shield_ready(v: bool) -> void:
	if shield_ready != v:
		shield_ready = v
		queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	var dirty := false
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.0)
		dirty = true
	if active or _flash > 0.0 or shield_ready or charge >= 1.0 - 0.001:
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.32))
	draw_circle(c, r, Color(0.04, 0.05, 0.06, 0.88))
	if shield_ready:
		var sp := 0.5 + 0.5 * sin(_pulse * 4.5)
		draw_arc(c, r + 1.0, 0.0, TAU, 48, Color(0.36, 0.88, 0.96, 0.35 + sp * 0.40), 2.8, true)
	draw_arc(c, r - 1.5, 0.0, TAU, 48, Color(0.42, 0.90, 0.98, 0.45) if shield_ready else Color(1, 1, 1, 0.13), 1.5, true)

	if active:
		var active_tint := Color("#c591ff") if full_boost else Color("#ff734d")
		draw_circle(c, r - 2.0, Color(active_tint, 0.15))
		draw_arc(c, r - 4.0, 0.0, TAU, 48, Color(active_tint, 0.64), 3.0, true)

	var ring_r := r - 10.0
	var span := TAU / float(segments)
	var gap := 0.12
	var start := -PI * 0.5 + gap * 0.5
	for i in range(segments):
		var a0 := start + span * float(i)
		var a1 := a0 + span - gap
		draw_arc(c, ring_r, a0, a1, 24, Color(1, 1, 1, 0.09), 7.0, true)
		var frac := clampf(charge * float(SEGMENTS) - float(i), 0.0, 1.0)
		if frac > 0.01:
			var col := Color("#ffd06b") if active else (Color("#5ce1e6") if (shield_ready and i < 3) else Color("#f2b134"))
			draw_arc(c, ring_r, a0, a0 + (a1 - a0) * frac, 24, col, 7.0, true)

	var inner := ring_r - 14.0
	var base := Color("#6735a8") if full_boost else (Color("#c22f27") if active else Color("#1b1f24"))
	draw_circle(c, inner, base)
	draw_arc(c, inner, 0.0, TAU, 40, Color(1, 1, 1, 0.07), 2.0, true)
	if _down:
		draw_circle(c, inner, Color(1, 1, 1, 0.06))

	var ready := charge >= 1.0 / float(SEGMENTS) - 0.001
	if ready and not active:
		var p := 0.5 + 0.5 * sin(_pulse * 3.4)
		draw_arc(c, inner + 2.0, 0.0, TAU, 40, Color(0.36, 0.88, 0.96, 0.16 + p * 0.16) if shield_ready else Color(1.0, 0.75, 0.25, 0.10 + p * 0.12), 2.0, true)

	var glyph := Color(1, 1, 1, 0.95) if (ready or active) else Color(1, 1, 1, 0.36)
	var s := inner * 0.52
	draw_colored_polygon(
		PackedVector2Array([
			c + Vector2(s * 0.10, -s * 0.82),
			c + Vector2(-s * 0.44, s * 0.10),
			c + Vector2(-s * 0.04, s * 0.10),
			c + Vector2(-s * 0.16, s * 0.86),
			c + Vector2(s * 0.46, -s * 0.14),
			c + Vector2(s * 0.06, -s * 0.14),
		]),
		glyph
	)

	if label_font:
		var txt := "ФОРСАЖ" if full_boost else ("ЩИТ" if shield_ready and not active else "НИТРО")
		var fs := 14
		var tw := label_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		var tcol := Color(0.50, 0.95, 1.0, 0.88) if (shield_ready and not active) else Color(1, 1, 1, 0.58)
		draw_string(label_font, c + Vector2(-tw * 0.5, inner * 0.82), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, tcol)

	if _flash > 0.0:
		draw_arc(c, r - 2.0, 0.0, TAU, 48, Color(1.0, 0.85, 0.40, _flash * 0.55), 2.5, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled and not _down:
			_touch_id = event.index
			_down = true
			queue_redraw()
			tapped.emit()
		elif (not event.pressed or event.canceled) and _down and event.index == _touch_id:
			_touch_id = -1
			_down = false
			queue_redraw()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		# With touch emulation the corresponding ScreenTouch owns the press.
		if Input.emulate_touch_from_mouse or event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if event.pressed and not _down:
			_touch_id = -1
			_down = true
			queue_redraw()
			tapped.emit()
		elif not event.pressed and _down and _touch_id == -1:
			_down = false
			queue_redraw()
		accept_event()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		reset()
