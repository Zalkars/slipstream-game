extends Node2D

# Screen manager: menu, garage, settings, HUD, pause, result + persistence.

const VERSION := "0.2.0"
const SAVE_PATH := "user://slipstream.cfg"
const START_COINS := 300

var game: Game
var ui: CanvasLayer

var menu: Control
var hud: Control
var garage: Control
var settings: Control
var how: Control
var pause_panel: Control
var result_panel: Control
var confirm_panel: Control

var score_label: Label
var combo_label: Label
var coins_label: Label
var speed_label: Label
var swipe_hint: Label
var nitro_btn: NitroButton
var pad_left: PadButton
var pad_right: PadButton
var brake_btn: PadButton

var menu_best: Label
var menu_car: Label
var menu_coins: Label

var garage_coins: Label
var g_stage: CarStage
var g_name: Label
var g_sub: Label
var g_desc: Label
var g_price: Label
var g_hint: Label
var g_action: Button
var g_vals: Array = []
var g_bars: Array = []

var settings_coins: Label
var sfx_switch: ToggleSwitch
var music_switch: ToggleSwitch
var ctrl_buttons: Button
var ctrl_swipe: Button

var result_score: Label
var result_record: Label
var result_dist: Label
var result_near: Label
var result_best: Label
var result_coins: Label
var result_total: Label

var font_ui: Font
var font_bold: Font
var font_num: Font

var accent := Color("#e23b30")
var amber := Color("#f2b134")
var ink := Color("#f3f1ec")
var dim_col := Color("#9aa3ac")

var best := 0
var coins := START_COINS
var owned: Array = [0]
var selected := 0

var sfx_on := true
var music_on := true
var control_mode := "buttons"

var garage_index := 0
var settings_from_pause := false
var in_game := false
var paused := false
var result_open := false
var _shots := false
var _hint_t := 0.0


func _ready() -> void:
	_load()
	_setup_fonts()
	game = Game.new()
	game.name = "Game"
	add_child(game)
	game.hud_changed.connect(_on_hud)
	game.run_ended.connect(_on_crashed)
	game.near_miss.connect(_on_near)
	game.pickup_taken.connect(_on_pickup)

	ui = CanvasLayer.new()
	ui.layer = 5
	add_child(ui)

	_build_menu()
	_build_hud()
	_build_garage()
	_build_settings()
	_build_how()
	_build_pause()
	_build_result()
	_build_confirm()

	show_menu()
	Sfx.set_sfx_enabled(sfx_on)
	Sfx.set_music_enabled(music_on)

	get_tree().set_auto_accept_quit(false)
	if "--shots" in OS.get_cmdline_user_args():
		_shots = true
		_capture_seq()


func _process(delta: float) -> void:
	if _hint_t > 0.0:
		_hint_t = maxf(0.0, _hint_t - delta)
		if _hint_t <= 0.0 and swipe_hint != null:
			swipe_hint.visible = false


func _setup_fonts() -> void:
	var raj := load("res://fonts/Rajdhani-SemiBold.ttf") as Font
	var raj_bold := load("res://fonts/Rajdhani-Bold.ttf") as Font
	var orb := load("res://fonts/Orbitron.ttf") as Font
	font_ui = raj if raj != null else ThemeDB.fallback_font
	font_bold = raj_bold if raj_bold != null else font_ui
	if orb != null:
		var fv := FontVariation.new()
		fv.base_font = orb
		fv.variation_opentype = {"wght": 820.0}
		font_num = fv
	else:
		font_num = font_bold


# --- persistence ------------------------------------------------------------

func _load() -> void:
	var cf := ConfigFile.new()
	if cf.load(SAVE_PATH) == OK:
		best = int(cf.get_value("stats", "best", 0))
		coins = int(cf.get_value("stats", "coins", START_COINS))
		var arr: Array = cf.get_value("profile", "owned", [0])
		owned = []
		for v in arr:
			var idx := int(v)
			if idx >= 0 and idx < Cars.LIST.size() and not owned.has(idx):
				owned.append(idx)
		if owned.is_empty():
			owned = [0]
		selected = clampi(int(cf.get_value("profile", "car", 0)), 0, Cars.LIST.size() - 1)
		if not owned.has(selected):
			selected = int(owned[0])
		var legacy_muted := bool(cf.get_value("audio", "muted", false))
		sfx_on = bool(cf.get_value("audio", "sfx", not legacy_muted))
		music_on = bool(cf.get_value("audio", "music", true))
		var mode := str(cf.get_value("controls", "mode", "buttons"))
		control_mode = mode if mode in ["buttons", "swipe"] else "buttons"
	if "--mute" in OS.get_cmdline_user_args():
		sfx_on = false
		music_on = false
	garage_index = selected


func _save() -> void:
	var cf := ConfigFile.new()
	cf.set_value("stats", "best", best)
	cf.set_value("stats", "coins", coins)
	cf.set_value("profile", "owned", owned)
	cf.set_value("profile", "car", selected)
	cf.set_value("audio", "sfx", sfx_on)
	cf.set_value("audio", "music", music_on)
	cf.set_value("controls", "mode", control_mode)
	cf.save(SAVE_PATH)


# --- screens ----------------------------------------------------------------

func _hide_screens() -> void:
	for s in [menu, garage, settings, how]:
		if s != null:
			s.visible = false


func show_menu() -> void:
	in_game = false
	paused = false
	result_open = false
	_hide_screens()
	menu.visible = true
	hud.visible = false
	pause_panel.visible = false
	result_panel.visible = false
	confirm_panel.visible = false
	game.start_demo()
	Sfx.stop_engine()
	Sfx.set_paused(false)
	Sfx.play_music()
	_update_all_labels()


func show_garage() -> void:
	Sfx.click()
	in_game = false
	paused = false
	result_open = false
	_hide_screens()
	garage.visible = true
	hud.visible = false
	pause_panel.visible = false
	result_panel.visible = false
	confirm_panel.visible = false
	garage_index = selected
	game.start_demo()
	Sfx.stop_engine()
	Sfx.set_paused(false)
	Sfx.play_music()
	_update_all_labels()


func _show_how() -> void:
	Sfx.click()
	_hide_screens()
	how.visible = true


func _hide_how() -> void:
	Sfx.click()
	how.visible = false
	show_menu()


func _show_settings(from_pause: bool) -> void:
	Sfx.click()
	settings_from_pause = from_pause
	pause_panel.visible = false
	if not from_pause:
		in_game = false
		result_open = false
		_hide_screens()
		game.start_demo()
		Sfx.stop_engine()
		Sfx.set_paused(false)
		Sfx.play_music()
	settings.visible = true
	_update_settings_ui()


func _hide_settings() -> void:
	Sfx.click()
	settings.visible = false
	if settings_from_pause:
		pause_panel.visible = true
	else:
		show_menu()


func start_game() -> void:
	Sfx.click()
	_hide_screens()
	pause_panel.visible = false
	result_panel.visible = false
	confirm_panel.visible = false
	hud.visible = true
	in_game = true
	paused = false
	result_open = false
	game.car_index = selected
	game.control_mode = control_mode
	nitro_btn.reset()
	_apply_control_ui()
	_hint_t = 5.0 if control_mode == "swipe" else 0.0
	swipe_hint.visible = control_mode == "swipe"
	game.start_run()
	Sfx.set_paused(false)
	Sfx.play_engine()
	Sfx.play_music()


func _apply_control_ui() -> void:
	var button_mode := control_mode == "buttons"
	pad_left.visible = button_mode
	pad_right.visible = button_mode
	if button_mode:
		_place_bottom(brake_btn, 276.0, 34.0, 108.0, 108.0)
	else:
		_place_bottom(brake_btn, 34.0, 34.0, 108.0, 108.0)
	if game != null:
		game.control_mode = control_mode
	if swipe_hint != null:
		swipe_hint.visible = (not button_mode) and _hint_t > 0.0


func _toggle_pause() -> void:
	if not in_game or result_open:
		return
	Sfx.click()
	paused = not paused
	game.paused = paused
	pause_panel.visible = paused
	Sfx.set_paused(paused)
	if paused:
		game.set_braking(false)
		brake_btn.reset()
	else:
		_apply_control_ui()


func _tap_nitro() -> void:
	if not in_game or paused or result_open:
		return
	if game.tap_nitro():
		Sfx.boost_burst()


func _on_near(_combo: int) -> void:
	Sfx.whoosh()


func _on_pickup(kind: int) -> void:
	if kind == 0:
		Sfx.pickup_coin()
	else:
		Sfx.pickup_nitro()


func _on_hud(score: int, kmh: int, nitro: float, combo: int, run_coins: int, boosting: bool) -> void:
	score_label.text = _fmt(score)
	speed_label.text = str(kmh)
	nitro_btn.set_charge(nitro)
	nitro_btn.set_active(boosting)
	coins_label.text = ("МОНЕТЫ  " + _fmt(run_coins)) if run_coins > 0 else ""
	if combo > 1:
		combo_label.text = "×%d СЕРИЯ" % combo
	else:
		combo_label.text = ""
	Sfx.update_engine(kmh, boosting)


func _on_crashed(score: int, dist: int, near: int, run_coins: int) -> void:
	Sfx.crash()
	Sfx.stop_engine()
	await get_tree().create_timer(1.05).timeout
	if not game.crashed:
		return
	in_game = false
	result_open = true
	paused = false
	hud.visible = false
	game.paused = true
	_show_result(score, dist, near, run_coins)


func _show_result(score: int, dist: int, near: int, run_coins: int) -> void:
	var is_record := score > best
	if is_record:
		best = score
		Sfx.record()
	var earned := run_coins + (25 if is_record else 0)
	coins += earned
	_save()
	result_score.text = _fmt(score)
	result_record.visible = is_record
	result_dist.text = "%d м" % dist
	result_near.text = str(near)
	result_best.text = _fmt(best)
	result_coins.text = "+%s МОНЕТ" % _fmt(earned)
	result_total.text = "БАЛАНС  %s" % _fmt(coins)
	result_panel.visible = true
	_update_all_labels()


func _on_back() -> void:
	if confirm_panel.visible:
		_hide_confirm()
		return
	if how.visible:
		_hide_how()
		return
	if settings.visible:
		_hide_settings()
		return
	if garage.visible:
		show_menu()
		return
	if result_open:
		show_menu()
		return
	if in_game:
		_toggle_pause()
		return
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		_on_back()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if in_game and not paused and not result_open and not _shots:
			_toggle_pause()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if event.echo:
		return
	if event.pressed:
		match event.keycode:
			KEY_ESCAPE:
				_on_back()
			KEY_LEFT, KEY_A:
				if in_game and not paused and not result_open:
					game.move_lane(-1)
			KEY_RIGHT, KEY_D:
				if in_game and not paused and not result_open:
					game.move_lane(1)
			KEY_SPACE:
				if in_game and not paused and not result_open:
					_tap_nitro()
			KEY_DOWN, KEY_S:
				if in_game and not paused and not result_open:
					game.set_braking(true)
	else:
		if event.keycode in [KEY_DOWN, KEY_S] and in_game:
			game.set_braking(false)


# --- widgets ----------------------------------------------------------------

func _full(c: Control) -> void:
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	c.offset_left = 0
	c.offset_top = 0
	c.offset_right = 0
	c.offset_bottom = 0


func _place(c: Control, x: float, y: float, w: float, h: float) -> void:
	c.set_anchors_preset(Control.PRESET_TOP_LEFT)
	c.position = Vector2(x, y)
	c.size = Vector2(w, h)


func _place_bottom(c: Control, x: float, bottom: float, w: float, h: float) -> void:
	c.anchor_left = 0.0
	c.anchor_right = 0.0
	c.anchor_top = 1.0
	c.anchor_bottom = 1.0
	c.offset_left = x
	c.offset_right = x + w
	c.offset_bottom = -bottom
	c.offset_top = -bottom - h


func _label(txt: String, fs: int, col: Color, f: Font = null, align := HORIZONTAL_ALIGNMENT_LEFT) -> Label:
	var l := Label.new()
	l.text = txt
	l.horizontal_alignment = align
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_override("font", f if f != null else font_ui)
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", col)
	return l


func _vgrad(top: Color, mid: Color, bottom: Color) -> TextureRect:
	var g := Gradient.new()
	g.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	g.colors = PackedColorArray([top, mid, bottom])
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 8
	t.height = 256
	t.fill_from = Vector2(0.0, 0.0)
	t.fill_to = Vector2(0.0, 1.0)
	var tr := TextureRect.new()
	tr.texture = t
	tr.stretch_mode = TextureRect.STRETCH_SCALE
	tr.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(tr)
	return tr


func _btn_sb(col: Color, primary: bool) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = col
	sb.set_corner_radius_all(15)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1.0, 1.0, 1.0, 0.16) if primary else Color(0.30, 0.34, 0.38, 1.0)
	sb.content_margin_left = 24
	sb.content_margin_right = 24
	sb.content_margin_top = 8
	sb.content_margin_bottom = 10
	sb.shadow_color = Color(0.45, 0.10, 0.07, 0.28) if primary else Color(0.0, 0.0, 0.0, 0.28)
	sb.shadow_size = 9
	sb.shadow_offset = Vector2(0, 4)
	return sb


func _button(txt: String, primary := false) -> Button:
	var b := Button.new()
	b.text = txt
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	b.custom_minimum_size = Vector2(0, 102)
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 34)
	b.add_theme_color_override("font_color", Color("#fff7f1") if primary else Color("#e9edf0"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", Color(1, 1, 1, 0.78))
	b.add_theme_color_override("font_disabled_color", Color(0.66, 0.69, 0.71))
	var bg := accent if primary else Color(0.14, 0.16, 0.18)
	b.add_theme_stylebox_override("normal", _btn_sb(bg, primary))
	b.add_theme_stylebox_override("hover", _btn_sb(bg.lightened(0.09), primary))
	b.add_theme_stylebox_override("pressed", _btn_sb(bg.darkened(0.15), primary))
	b.add_theme_stylebox_override("disabled", _btn_sb(bg.darkened(0.42), primary))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func(): Sfx.click())
	return b


func _text_button(txt: String) -> Button:
	var b := Button.new()
	b.text = txt
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.custom_minimum_size = Vector2(0, 54)
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", 24)
	b.add_theme_color_override("font_color", Color(0.72, 0.76, 0.78))
	b.add_theme_color_override("font_hover_color", Color(0.95, 0.96, 0.96))
	b.add_theme_color_override("font_pressed_color", Color(0.8, 0.82, 0.84))
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func(): Sfx.click())
	return b


func _card(width: float) -> PanelContainer:
	var p := PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#13161a")
	sb.set_corner_radius_all(26)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1.0, 1.0, 1.0, 0.09)
	sb.content_margin_left = 34
	sb.content_margin_right = 34
	sb.content_margin_top = 30
	sb.content_margin_bottom = 30
	sb.shadow_color = Color(0, 0, 0, 0.55)
	sb.shadow_size = 28
	sb.shadow_offset = Vector2(0, 12)
	p.add_theme_stylebox_override("panel", sb)
	p.custom_minimum_size = Vector2(width, 0)
	return p


func _screen_bg() -> TextureRect:
	return _vgrad(
		Color(0.065, 0.075, 0.085, 1.0),
		Color(0.045, 0.052, 0.060, 1.0),
		Color(0.028, 0.033, 0.038, 1.0)
	)


func _coin_chip(parent: Control, x: float, y: float, w: float) -> Label:
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 8)
	_place(row, x, y, w, 44)
	var ic := CoinIcon.new()
	ic.custom_minimum_size = Vector2(30, 30)
	ic.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(ic)
	var val := _label("0", 28, amber, font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
	val.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(val)
	parent.add_child(row)
	return val


func _stat_bar(parent: Control, x: float, y: float, w: float) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.max_value = 1.0
	pb.value = 0.5
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(pb, x, y, w, 12.0)
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(1, 1, 1, 0.08)
	bg.set_corner_radius_all(6)
	var fg := StyleBoxFlat.new()
	fg.bg_color = amber
	fg.set_corner_radius_all(6)
	pb.add_theme_stylebox_override("background", bg)
	pb.add_theme_stylebox_override("fill", fg)
	parent.add_child(pb)
	return pb


# --- menu -------------------------------------------------------------------

func _build_menu() -> void:
	menu = Control.new()
	_full(menu)
	menu.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(menu)

	menu.add_child(_vgrad(
		Color(0.03, 0.035, 0.04, 0.74),
		Color(0.03, 0.035, 0.04, 0.20),
		Color(0.03, 0.035, 0.04, 0.92)
	))

	menu_coins = _coin_chip(menu, 430.0, 46.0, 246.0)

	var tag := _label("А Р К А Д Н Ы Й   Р Е Й С", 21, accent, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	_place(tag, 60, 230, 600, 30)
	menu.add_child(tag)

	var title := _label("SLIPSTREAM", 74, Color("#f5f2ea"), font_num, HORIZONTAL_ALIGNMENT_CENTER)
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.45))
	title.add_theme_constant_override("shadow_offset_x", 0)
	title.add_theme_constant_override("shadow_offset_y", 3)
	title.add_theme_constant_override("shadow_outline_size", 6)
	_place(title, 20, 266, 680, 108)
	menu.add_child(title)

	var bar := ColorRect.new()
	bar.color = accent
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(bar, 310, 388, 100, 5)
	menu.add_child(bar)

	var sub := _label("РЕАЛИСТИЧНЫЙ РЕЙС · v" + VERSION, 22, Color(0.76, 0.79, 0.79), font_ui, HORIZONTAL_ALIGNMENT_CENTER)
	_place(sub, 60, 406, 600, 30)
	menu.add_child(sub)

	menu_car = _label("", 20, amber, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	_place(menu_car, 60, 442, 600, 28)
	menu.add_child(menu_car)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	vb.anchor_left = 0.0
	vb.anchor_right = 0.0
	vb.anchor_top = 1.0
	vb.anchor_bottom = 1.0
	vb.offset_left = 70
	vb.offset_right = 650
	vb.offset_top = -540
	vb.offset_bottom = -60
	menu.add_child(vb)

	var play := _button("ПОЕХАЛИ", true)
	play.custom_minimum_size = Vector2(0, 88)
	play.pressed.connect(start_game)
	vb.add_child(play)

	var garage_btn := _button("ГАРАЖ", false)
	garage_btn.custom_minimum_size = Vector2(0, 88)
	garage_btn.pressed.connect(show_garage)
	vb.add_child(garage_btn)

	var settings_btn := _button("НАСТРОЙКИ", false)
	settings_btn.custom_minimum_size = Vector2(0, 88)
	settings_btn.pressed.connect(func(): _show_settings(false))
	vb.add_child(settings_btn)

	var how_btn := _button("КАК ИГРАТЬ", false)
	how_btn.custom_minimum_size = Vector2(0, 88)
	how_btn.pressed.connect(_show_how)
	vb.add_child(how_btn)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	vb.add_child(spacer)

	menu_best = _label("РЕКОРД  0", 28, Color(0.78, 0.81, 0.81), font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(menu_best)

	var ver := _label("v" + VERSION + " · GODOT EDITION", 16, Color(0.44, 0.48, 0.50), font_ui, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(ver)


# --- HUD --------------------------------------------------------------------

func _build_hud() -> void:
	hud = Control.new()
	_full(hud)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(hud)

	var top := _vgrad(Color(0.02, 0.025, 0.03, 0.58), Color(0.02, 0.025, 0.03, 0.0), Color(0.02, 0.025, 0.03, 0.0))
	_place(top, 0, 0, 720, 260)
	hud.add_child(top)

	var cap := _label("СЧЁТ", 20, Color(0.70, 0.74, 0.76), font_bold)
	_place(cap, 46, 38, 260, 24)
	hud.add_child(cap)

	score_label = _label("0", 54, Color(0.97, 0.96, 0.93), font_num)
	_place(score_label, 42, 58, 420, 68)
	hud.add_child(score_label)

	combo_label = _label("", 22, amber, font_bold)
	_place(combo_label, 46, 126, 420, 30)
	hud.add_child(combo_label)

	coins_label = _label("", 20, amber, font_bold)
	_place(coins_label, 46, 158, 340, 28)
	hud.add_child(coins_label)

	var pause := IconButton.new()
	pause.kind = "pause"
	pause.pressed.connect(_toggle_pause)
	_place(pause, 600, 36, 76, 76)
	hud.add_child(pause)

	speed_label = _label("0", 52, Color(0.97, 0.96, 0.93), font_num, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(speed_label, 392, 110, 282, 62)
	hud.add_child(speed_label)

	var unit := _label("КМ/Ч", 19, Color(0.70, 0.74, 0.76), font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(unit, 392, 176, 282, 24)
	hud.add_child(unit)

	var bot := _vgrad(Color(0.02, 0.025, 0.03, 0.0), Color(0.02, 0.025, 0.03, 0.14), Color(0.02, 0.025, 0.03, 0.46))
	_place_bottom(bot, 0, 0, 720, 330)
	hud.add_child(bot)

	pad_left = PadButton.new()
	pad_left.kind = "left"
	pad_left.label_font = font_bold
	pad_left.pressed.connect(func(): game.move_lane(-1))
	_place_bottom(pad_left, 34, 34, 108, 108)
	hud.add_child(pad_left)

	pad_right = PadButton.new()
	pad_right.kind = "right"
	pad_right.label_font = font_bold
	pad_right.pressed.connect(func(): game.move_lane(1))
	_place_bottom(pad_right, 150, 34, 108, 108)
	hud.add_child(pad_right)

	brake_btn = PadButton.new()
	brake_btn.kind = "brake"
	brake_btn.label_font = font_bold
	brake_btn.held_changed.connect(func(on: bool): game.set_braking(on))
	_place_bottom(brake_btn, 276, 34, 108, 108)
	hud.add_child(brake_btn)

	nitro_btn = NitroButton.new()
	nitro_btn.label_font = font_bold
	nitro_btn.tapped.connect(_tap_nitro)
	_place_bottom(nitro_btn, 548, 30, 148, 148)
	hud.add_child(nitro_btn)

	swipe_hint = _label("СВАЙП  ←  →", 21, Color(1, 1, 1, 0.42), font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	_place_bottom(swipe_hint, 160, 74, 380, 30)
	swipe_hint.visible = false
	hud.add_child(swipe_hint)


# --- garage -----------------------------------------------------------------

func _build_garage() -> void:
	garage = Control.new()
	_full(garage)
	garage.visible = false
	garage.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(garage)
	garage.add_child(_screen_bg())

	var back := IconButton.new()
	back.kind = "back"
	back.pressed.connect(show_menu)
	_place(back, 36, 38, 76, 76)
	garage.add_child(back)

	var title := _label("ГАРАЖ", 44, ink, font_num, HORIZONTAL_ALIGNMENT_CENTER)
	_place(title, 0, 44, 720, 68)
	garage.add_child(title)

	garage_coins = _coin_chip(garage, 440.0, 50.0, 246.0)

	g_stage = CarStage.new()
	_place(g_stage, 52, 132, 616, 600)
	garage.add_child(g_stage)

	var left := PadButton.new()
	left.kind = "left"
	left.label_font = font_bold
	left.pressed.connect(func(): _garage_step(-1))
	_place(left, 18, 384, 76, 76)
	garage.add_child(left)

	var right := PadButton.new()
	right.kind = "right"
	right.label_font = font_bold
	right.pressed.connect(func(): _garage_step(1))
	_place(right, 626, 384, 76, 76)
	garage.add_child(right)

	g_name = _label("", 42, ink, font_num, HORIZONTAL_ALIGNMENT_CENTER)
	_place(g_name, 52, 744, 616, 54)
	garage.add_child(g_name)

	g_sub = _label("", 19, dim_col, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	_place(g_sub, 52, 798, 616, 28)
	garage.add_child(g_sub)

	var card := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0f1317")
	sb.set_corner_radius_all(22)
	sb.border_width_left = 1
	sb.border_width_right = 1
	sb.border_width_top = 1
	sb.border_width_bottom = 1
	sb.border_color = Color(1, 1, 1, 0.07)
	card.add_theme_stylebox_override("panel", sb)
	_place(card, 52, 848, 616, 216)
	garage.add_child(card)

	var titles := ["СКОРОСТЬ", "РАЗГОН", "МАНЁВРЕННОСТЬ"]
	for i in range(3):
		var ry := 868.0 + float(i) * 62.0
		var lab := _label(titles[i], 20, Color(0.66, 0.71, 0.74), font_bold)
		_place(lab, 78, ry, 300, 28)
		garage.add_child(lab)
		var val := _label("", 22, ink, font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
		_place(val, 360, ry, 254, 28)
		garage.add_child(val)
		g_vals.append(val)
		g_bars.append(_stat_bar(garage, 78, ry + 30.0, 564))

	g_desc = _label("", 19, Color(0.62, 0.67, 0.70), font_ui, HORIZONTAL_ALIGNMENT_CENTER)
	g_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	g_desc.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	_place(g_desc, 76, 1080, 568, 64)
	garage.add_child(g_desc)

	g_price = _label("", 24, amber, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	_place_bottom(g_price, 52, 250, 616, 34)
	garage.add_child(g_price)

	g_action = _button("", true)
	g_action.custom_minimum_size = Vector2(0, 92)
	g_action.add_theme_font_size_override("font_size", 32)
	g_action.pressed.connect(_garage_action)
	_place_bottom(g_action, 52, 148, 616, 92)
	garage.add_child(g_action)

	g_hint = _label("", 16, Color(0.52, 0.57, 0.60), font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	_place_bottom(g_hint, 52, 100, 616, 26)
	garage.add_child(g_hint)


func _garage_step(dir: int) -> void:
	Sfx.click()
	garage_index = (garage_index + dir + Cars.LIST.size()) % Cars.LIST.size()
	_update_garage()


func _garage_action() -> void:
	var car := Cars.get_car(garage_index)
	var price := int(car.price)
	if owned.has(garage_index):
		if selected != garage_index:
			selected = garage_index
			_save()
			Sfx.record()
			_update_all_labels()
	else:
		if coins < price:
			return
		coins -= price
		owned.append(garage_index)
		selected = garage_index
		_save()
		Sfx.record()
		_update_all_labels()


func _update_garage() -> void:
	if g_stage == null:
		return
	var car := Cars.get_car(garage_index)
	g_stage.car = car
	g_stage.queue_redraw()
	g_name.text = str(car.name)
	g_sub.text = str(car.sub)
	g_desc.text = str(car.desc)
	var top_kmh := int(float(car.top) * 0.3)
	var sr := Cars.speed_rating(car)
	var ar := Cars.accel_rating(car)
	var gr := Cars.grip_rating(car)
	g_vals[0].text = "%d КМ/Ч" % top_kmh
	g_vals[1].text = "%d / 10" % ar
	g_vals[2].text = "%d / 10" % gr
	g_bars[0].value = float(sr) / 10.0
	g_bars[1].value = float(ar) / 10.0
	g_bars[2].value = float(gr) / 10.0

	var is_owned := owned.has(garage_index)
	var price := int(car.price)
	if is_owned and selected == garage_index:
		g_action.text = "ВЫБРАНО"
		g_action.disabled = true
		g_price.text = "ВАША МАШИНА"
		g_price.add_theme_color_override("font_color", amber)
	elif is_owned:
		g_action.text = "ВЫБРАТЬ"
		g_action.disabled = false
		g_price.text = "УЖЕ В ГАРАЖЕ"
		g_price.add_theme_color_override("font_color", Color(0.70, 0.75, 0.78))
	else:
		g_price.text = "ЦЕНА  %s МОНЕТ" % _fmt(price)
		g_price.add_theme_color_override("font_color", amber)
		if coins >= price:
			g_action.text = "КУПИТЬ ЗА %s" % _fmt(price)
			g_action.disabled = false
		else:
			g_action.text = "НЕ ХВАТАЕТ %s" % _fmt(price - coins)
			g_action.disabled = true
	g_hint.text = "%d / %d МАШИН · МОНЕТЫ ДАЮТ ЗАЕЗДЫ, ОБГОНЫ И ПОДБОРЫ" % [garage_index + 1, Cars.LIST.size()]


# --- settings ---------------------------------------------------------------

func _build_settings() -> void:
	settings = Control.new()
	_full(settings)
	settings.visible = false
	settings.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(settings)
	settings.add_child(_screen_bg())

	var back := IconButton.new()
	back.kind = "back"
	back.pressed.connect(_hide_settings)
	_place(back, 36, 38, 76, 76)
	settings.add_child(back)

	var title := _label("НАСТРОЙКИ", 42, ink, font_num, HORIZONTAL_ALIGNMENT_CENTER)
	_place(title, 0, 46, 720, 64)
	settings.add_child(title)

	settings_coins = _coin_chip(settings, 440.0, 50.0, 246.0)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(center)
	settings.add_child(center)

	var card := _card(620)
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	card.add_child(vb)

	vb.add_child(_label("ЗВУК И МУЗЫКА", 17, accent, font_bold))

	sfx_switch = ToggleSwitch.new()
	sfx_switch.label_font = font_bold
	sfx_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	sfx_switch.toggled.connect(_on_sfx_toggled)
	vb.add_child(_setting_row("ЗВУКИ", "Двигатель, удары, интерфейс", sfx_switch))

	music_switch = ToggleSwitch.new()
	music_switch.label_font = font_bold
	music_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	music_switch.toggled.connect(_on_music_toggled)
	vb.add_child(_setting_row("МУЗЫКА", "Спокойный фон без слов", music_switch))

	vb.add_child(_divider())
	vb.add_child(_label("УПРАВЛЕНИЕ", 17, accent, font_bold))

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 10)
	ctrl_buttons = _mode_button("КНОПКИ")
	ctrl_buttons.pressed.connect(func(): _set_control_mode("buttons"))
	modes.add_child(ctrl_buttons)
	ctrl_swipe = _mode_button("СВАЙПЫ")
	ctrl_swipe.pressed.connect(func(): _set_control_mode("swipe"))
	modes.add_child(ctrl_swipe)
	vb.add_child(modes)

	var hint := _label("КНОПКИ — стрелки внизу экрана. СВАЙПЫ — веди пальцем влево или вправо. Тормоз и нитро работают в обоих режимах.", 17, Color(0.55, 0.60, 0.63), font_ui)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.custom_minimum_size = Vector2(0, 54)
	vb.add_child(hint)

	vb.add_child(_divider())

	var reset := _text_button("СБРОСИТЬ ПРОГРЕСС")
	reset.add_theme_color_override("font_color", Color(0.86, 0.38, 0.32))
	reset.add_theme_color_override("font_hover_color", Color(1.0, 0.55, 0.46))
	reset.pressed.connect(_show_confirm)
	vb.add_child(reset)


func _setting_row(title: String, sub: String, ctrl: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 0)
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(_label(title, 26, ink, font_bold))
	if sub != "":
		box.add_child(_label(sub, 16, Color(0.52, 0.57, 0.60), font_ui))
	row.add_child(box)
	row.add_child(ctrl)
	return row


func _divider() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.08)
	c.custom_minimum_size = Vector2(0, 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _mode_button(txt: String) -> Button:
	var b := _button(txt, false)
	b.custom_minimum_size = Vector2(0, 66)
	b.add_theme_font_size_override("font_size", 24)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return b


func _style_mode_btn(b: Button, on: bool) -> void:
	if b == null:
		return
	var bg := accent if on else Color(0.14, 0.16, 0.18)
	var sb := _btn_sb(bg, on)
	sb.content_margin_top = 4
	sb.content_margin_bottom = 5
	b.add_theme_stylebox_override("normal", sb)
	b.add_theme_stylebox_override("hover", _btn_sb(bg.lightened(0.08), on))
	b.add_theme_stylebox_override("pressed", _btn_sb(bg.darkened(0.12), on))
	b.add_theme_color_override("font_color", Color(1, 1, 1, 0.96) if on else Color(0.70, 0.75, 0.78))


func _update_settings_ui() -> void:
	if sfx_switch != null:
		sfx_switch.set_on(sfx_on)
	if music_switch != null:
		music_switch.set_on(music_on)
	_style_mode_btn(ctrl_buttons, control_mode == "buttons")
	_style_mode_btn(ctrl_swipe, control_mode == "swipe")


func _on_sfx_toggled(v: bool) -> void:
	sfx_on = v
	Sfx.set_sfx_enabled(v)
	_save()


func _on_music_toggled(v: bool) -> void:
	music_on = v
	Sfx.set_music_enabled(v)
	_save()


func _set_control_mode(mode: String) -> void:
	if control_mode == mode:
		return
	control_mode = mode
	_apply_control_ui()
	_save()
	_update_settings_ui()


# --- how to play ------------------------------------------------------------

func _build_how() -> void:
	how = Control.new()
	_full(how)
	how.visible = false
	how.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(how)

	var dim := ColorRect.new()
	dim.color = Color(0.02, 0.025, 0.03, 0.95)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(dim)
	how.add_child(dim)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(center)
	how.add_child(center)

	var card := _card(640)
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 10)
	card.add_child(vb)

	vb.add_child(_label("КАК ИГРАТЬ", 40, ink, font_num, HORIZONTAL_ALIGNMENT_CENTER))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 4)
	vb.add_child(gap)

	var items := [
		["УПРАВЛЕНИЕ", "Стрелки внизу экрана или свайпы — режим выбирается в настройках."],
		["ТОРМОЗ", "Держи ТОРМОЗ, чтобы сбросить скорость и разорвать плотный поток."],
		["НИТРО", "Копится за близкие обгоны и синие баллоны. Нажми, чтобы потратить заряд."],
		["МОНЕТЫ", "Золото на дороге и дистанция пополняют кошелёк. Машины покупаются в гараже."],
		["ФИНИШ", "Столкновение завершает заезд. Рекорд, монеты и гараж сохраняются."],
	]
	for it in items:
		vb.add_child(_label(it[0], 19, accent, font_bold))
		var body := _label(it[1], 23, Color(0.86, 0.88, 0.89), font_ui)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(0, 54)
		vb.add_child(body)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 4)
	vb.add_child(gap2)

	var ok := _button("ПОНЯТНО", true)
	ok.custom_minimum_size = Vector2(0, 90)
	ok.pressed.connect(_hide_how)
	vb.add_child(ok)


# --- pause ------------------------------------------------------------------

func _build_pause() -> void:
	pause_panel = Control.new()
	_full(pause_panel)
	pause_panel.visible = false
	pause_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(pause_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.02, 0.76)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(dim)
	pause_panel.add_child(dim)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(center)
	pause_panel.add_child(center)

	var card := _card(540)
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 12)
	card.add_child(vb)

	vb.add_child(_label("ПАУЗА", 44, ink, font_num, HORIZONTAL_ALIGNMENT_CENTER))
	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 6)
	vb.add_child(gap)

	var resume := _button("ПРОДОЛЖИТЬ", true)
	resume.pressed.connect(_toggle_pause)
	vb.add_child(resume)

	var to_settings := _button("НАСТРОЙКИ", false)
	to_settings.custom_minimum_size = Vector2(0, 90)
	to_settings.pressed.connect(func(): _show_settings(true))
	vb.add_child(to_settings)

	var again := _button("ЗАНОВО", false)
	again.custom_minimum_size = Vector2(0, 90)
	again.pressed.connect(start_game)
	vb.add_child(again)

	var to_menu := _button("В МЕНЮ", false)
	to_menu.custom_minimum_size = Vector2(0, 90)
	to_menu.pressed.connect(show_menu)
	vb.add_child(to_menu)


# --- result -----------------------------------------------------------------

func _build_result() -> void:
	result_panel = Control.new()
	_full(result_panel)
	result_panel.visible = false
	result_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(result_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.02, 0.82)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(dim)
	result_panel.add_child(dim)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(center)
	result_panel.add_child(center)

	var card := _card(580)
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 6)
	card.add_child(vb)

	vb.add_child(_label("ЗАЕЗД ОКОНЧЕН", 22, dim_col, font_bold, HORIZONTAL_ALIGNMENT_CENTER))
	vb.add_child(_label("ОЧКИ", 16, Color(0.55, 0.60, 0.63), font_bold, HORIZONTAL_ALIGNMENT_CENTER))

	result_score = _label("0", 88, ink, font_num, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(result_score)

	result_record = _label("НОВЫЙ РЕКОРД", 22, amber, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	result_record.visible = false
	vb.add_child(result_record)

	result_coins = _label("+0 МОНЕТ", 27, amber, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(result_coins)

	result_total = _label("БАЛАНС  0", 17, Color(0.60, 0.65, 0.68), font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(result_total)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	vb.add_child(gap)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	vb.add_child(row)

	var vals: Array[Label] = []
	var titles := ["ДИСТАНЦИЯ", "ВПРИТИРКУ", "РЕКОРД"]
	for i in range(3):
		var cell := VBoxContainer.new()
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cell.add_theme_constant_override("separation", 0)
		var cap := _label(titles[i], 15, Color(0.55, 0.60, 0.63), font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		cell.add_child(cap)
		var val := _label("0", 32, Color(0.92, 0.93, 0.93), font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		cell.add_child(val)
		row.add_child(cell)
		vals.append(val)
	result_dist = vals[0]
	result_near = vals[1]
	result_best = vals[2]

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 12)
	vb.add_child(gap2)

	var again := _button("ЕЩЁ РАЗ", true)
	again.pressed.connect(start_game)
	vb.add_child(again)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	vb.add_child(row2)

	var to_garage := _button("ГАРАЖ", false)
	to_garage.custom_minimum_size = Vector2(0, 88)
	to_garage.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to_garage.add_theme_font_size_override("font_size", 28)
	to_garage.pressed.connect(show_garage)
	row2.add_child(to_garage)

	var to_menu := _button("В МЕНЮ", false)
	to_menu.custom_minimum_size = Vector2(0, 88)
	to_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to_menu.add_theme_font_size_override("font_size", 28)
	to_menu.pressed.connect(show_menu)
	row2.add_child(to_menu)


# --- reset confirmation -----------------------------------------------------

func _build_confirm() -> void:
	confirm_panel = Control.new()
	_full(confirm_panel)
	confirm_panel.visible = false
	confirm_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(confirm_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.02, 0.86)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(dim)
	confirm_panel.add_child(dim)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(center)
	confirm_panel.add_child(center)

	var card := _card(560)
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	card.add_child(vb)

	vb.add_child(_label("СБРОСИТЬ ПРОГРЕСС?", 34, ink, font_num, HORIZONTAL_ALIGNMENT_CENTER))
	var body := _label("Монеты, купленные машины и рекорд будут удалены. Настройки останутся.", 21, Color(0.70, 0.74, 0.76), font_ui, HORIZONTAL_ALIGNMENT_CENTER)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size = Vector2(0, 64)
	vb.add_child(body)

	var yes := _button("СБРОСИТЬ", true)
	yes.pressed.connect(_do_reset)
	vb.add_child(yes)

	var no := _button("ОТМЕНА", false)
	no.custom_minimum_size = Vector2(0, 90)
	no.pressed.connect(_hide_confirm)
	vb.add_child(no)


func _show_confirm() -> void:
	Sfx.click()
	confirm_panel.visible = true


func _hide_confirm() -> void:
	Sfx.click()
	confirm_panel.visible = false


func _do_reset() -> void:
	coins = START_COINS
	owned = [0]
	selected = 0
	best = 0
	garage_index = 0
	_save()
	confirm_panel.visible = false
	Sfx.click()
	_update_all_labels()


# --- misc -------------------------------------------------------------------

func _update_all_labels() -> void:
	if menu_coins != null:
		menu_coins.text = _fmt(coins)
	if menu_best != null:
		menu_best.text = "РЕКОРД  " + _fmt(best)
	if menu_car != null:
		var car := Cars.get_car(selected)
		menu_car.text = "ВАША МАШИНА · %s · %d КМ/Ч" % [str(car.name), int(float(car.top) * 0.3)]
	if garage_coins != null:
		garage_coins.text = _fmt(coins)
	if settings_coins != null:
		settings_coins.text = _fmt(coins)
	_update_garage()
	_update_settings_ui()


func _fmt(n: int) -> String:
	var s := str(absi(n))
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i > 0:
			out = " " + out
	return out


# --- dev screenshots --------------------------------------------------------

func _capture_seq() -> void:
	await get_tree().create_timer(1.4).timeout
	await _shot("menu")

	# garage: show a purchasable car, then buy it to verify the flow
	owned = [0]
	selected = 0
	garage_index = 0
	coins = 900
	_save()
	_update_all_labels()
	show_garage()
	_garage_step(1)
	await get_tree().create_timer(0.6).timeout
	await _shot("garage")
	_garage_action()

	_show_settings(false)
	await get_tree().create_timer(0.5).timeout
	await _shot("settings")
	show_menu()
	_show_how()
	await get_tree().create_timer(0.5).timeout
	await _shot("how")
	_hide_how()

	start_game()
	await get_tree().create_timer(1.5).timeout
	game.move_lane(1)
	await get_tree().create_timer(0.30).timeout
	_tap_nitro()
	await get_tree().create_timer(0.75).timeout
	await _shot("game")
	game.set_braking(true)
	await get_tree().create_timer(0.5).timeout
	game.set_braking(false)
	await get_tree().create_timer(0.3).timeout
	game.finish_run()
	await get_tree().create_timer(1.8).timeout
	await _shot("result")

	control_mode = "swipe"
	start_game()
	await get_tree().create_timer(1.4).timeout
	await _shot("game_swipe")
	var touch := InputEventScreenTouch.new()
	touch.position = Vector2(320.0, 760.0)
	touch.pressed = true
	Input.parse_input_event(touch)
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(420.0, 762.0)
	Input.parse_input_event(drag)
	var lift := InputEventScreenTouch.new()
	lift.position = Vector2(420.0, 762.0)
	lift.pressed = false
	Input.parse_input_event(lift)
	await get_tree().create_timer(0.25).timeout
	get_tree().quit()


func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png("res://shots/%s.png" % shot_name)
	print("[shot] ", shot_name, " ", img.get_size())
