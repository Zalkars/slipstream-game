class_name NitroButton
extends Control

# Tap-to-fire nitro: three charge segments, tap spends one segment.

signal tapped

const SEGMENTS := 3

var charge := 0.0
var active := false
var label_font: Font
var _down := false
var _flash := 0.0
var _pulse := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(148, 148)
	set_process(true)


func reset() -> void:
	_down = false
	active = false
	_flash = 0.0
	queue_redraw()


func set_charge(v: float) -> void:
	v = clampf(v, 0.0, 1.0)
	if absf(v - charge) > 0.002:
		if v > charge + 0.05:
			_flash = 1.0
		charge = v
		queue_redraw()


func set_active(v: bool) -> void:
	if active != v:
		active = v
		queue_redraw()


func _process(delta: float) -> void:
	_pulse += delta
	var dirty := false
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 2.0)
		dirty = true
	if active or _flash > 0.0 or charge >= 1.0 - 0.001:
		dirty = true
	if dirty:
		queue_redraw()


func _draw() -> void:
	var c := size * 0.5
	var r := minf(size.x, size.y) * 0.5 - 4.0
	draw_circle(c + Vector2(0, 3), r, Color(0, 0, 0, 0.32))
	draw_circle(c, r, Color(0.04, 0.05, 0.06, 0.88))
	draw_arc(c, r - 1.5, 0.0, TAU, 48, Color(1, 1, 1, 0.13), 1.5, true)

	if active:
		draw_circle(c, r - 2.0, Color(0.95, 0.25, 0.16, 0.15))
		draw_arc(c, r - 4.0, 0.0, TAU, 48, Color(1.0, 0.45, 0.30, 0.50), 3.0, true)

	var ring_r := r - 10.0
	var span := TAU / float(SEGMENTS)
	var gap := 0.12
	var start := -PI * 0.5 + gap * 0.5
	for i in range(SEGMENTS):
		var a0 := start + span * float(i)
		var a1 := a0 + span - gap
		draw_arc(c, ring_r, a0, a1, 24, Color(1, 1, 1, 0.09), 7.0, true)
		var frac := clampf(charge * float(SEGMENTS) - float(i), 0.0, 1.0)
		if frac > 0.01:
			var col := Color("#ffd06b") if active else Color("#f2b134")
			draw_arc(c, ring_r, a0, a0 + (a1 - a0) * frac, 24, col, 7.0, true)

	var inner := ring_r - 14.0
	var base := Color("#c22f27") if active else Color("#1b1f24")
	draw_circle(c, inner, base)
	draw_arc(c, inner, 0.0, TAU, 40, Color(1, 1, 1, 0.07), 2.0, true)
	if _down:
		draw_circle(c, inner, Color(1, 1, 1, 0.06))

	var ready := charge >= 1.0 / float(SEGMENTS) - 0.001
	if ready and not active:
		var p := 0.5 + 0.5 * sin(_pulse * 3.4)
		draw_arc(c, inner + 2.0, 0.0, TAU, 40, Color(1.0, 0.75, 0.25, 0.10 + p * 0.12), 2.0, true)

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
		var txt := "НИТРО"
		var fs := 15
		var tw := label_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs).x
		draw_string(label_font, c + Vector2(-tw * 0.5, inner * 0.82), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, fs, Color(1, 1, 1, 0.58))

	if _flash > 0.0:
		draw_arc(c, r - 2.0, 0.0, TAU, 48, Color(1.0, 0.85, 0.40, _flash * 0.55), 2.5, true)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		if event.pressed:
			_down = true
			queue_redraw()
		elif _down:
			_down = false
			queue_redraw()
			tapped.emit()
		accept_event()
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_down = true
			queue_redraw()
		elif _down:
			_down = false
			queue_redraw()
			tapped.emit()
		accept_event()
