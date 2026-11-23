extends Node2D

# Screen manager: menu, garage, settings, HUD, pause, result + persistence.

# The menu uses the same version as the exported project.
var version := str(ProjectSettings.get_setting("application/config/version", "dev"))
const SAVE_PATH := "user://slipstream.cfg"
const START_COINS := 300
const VolumeSlider = preload("res://scripts/volume_slider.gd")

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
var confirm_text: Label
var exit_panel: Control
var challenges_panel: Control

var score_label: Label
var combo_label: Label
var coins_label: Label
var speed_label: Label
var slip_label: Label
var weather_clock: WeatherClock
var challenge_hud_panel: PanelContainer
var challenge_hud_label: Label
var event_banner: PanelContainer
var event_banner_title: Label
var event_banner_sub: Label
const EVENT_BANNER_TIME := 2.3
const EVENT_BANNER_ENTER := 0.22
const EVENT_BANNER_EXIT := 0.30
# Quiet time between two notifications, so they never chain back to back.
const EVENT_BANNER_GAP := 4.0
const EVENT_BANNER_LIMIT := 2
# Plain text under the weather line in the left HUD column; drops below the
# duel bar while that is shown.
const EVENT_BANNER_X := 46.0
const EVENT_BANNER_Y := 242.0
const EVENT_BANNER_Y_DUEL := 298.0
const EVENT_BANNER_W := 420.0
var _event_banner_t := 0.0
var _event_banner_gap := 0.0
var _event_banner_queue: Array[Dictionary] = []
var brake_heat_bar: ProgressBar
var brake_heat_fill: StyleBoxFlat
var brake_heat_mark: ColorRect
var overheat_label: Label
var swipe_hint: Label
var nitro_btn: NitroButton
var pad_left: PadButton
var pad_right: PadButton
var brake_btn: PadButton
var zones_pad: ZonesPad
var _chord_brake := false
var _pedal_brake := false
var _keyboard_brakes: Dictionary = {}

var menu_best: Label
var menu_car: Label
var menu_coins: Label

var garage_coins: Label
var g_stage: CarStage
var g_name: Label
var g_sub: Label
var g_price: Label
var g_action: Button
var g_race: Button
var g_slots: Array[Button] = []
var g_vals: Array = []
var g_bars: Array = []
var g_perk_title: Label
var g_perk_desc: Label

var settings_coins: Label
var sfx_switch: ToggleSwitch
var sfx_slider: VolumeSlider
var music_switch: ToggleSwitch
var music_slider: VolumeSlider
var ctrl_zones: Button
var ctrl_buttons: Button
var ctrl_swipe: Button
var ctrl_desc: Label
var ctrl_fps_30: Button
var ctrl_fps_60: Button
var ctrl_fps_120: Button
var fps_desc: Label
var ctrl_cars_2d: Button
var ctrl_cars_3d: Button

var tutorial_panel: Control
var tutorial_title: Label
var tutorial_text: Label
var tutorial_active := false
var tutorial_step := 0
var tutorial_timer := 0.0
var tutorial_done := false
var _step2_prompted := false
var _nitro_prompted := false
var _was_overheated := false
var _overheat_recovered_t := 0.0

var result_score: Label
var result_record: Label
var result_dist: Label
var result_near: Label
var result_best: Label
var result_coins: Label
var result_total: Label
var result_mode_banner: Label
var result_share_btn: Button
var result_return_btn: Button

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
var sfx_volume := 0.90
var music_volume := 0.75
var control_mode := "zones"
var fps_limit := 60
# Race car art: true = baked 3D sprites, false = the original painted cars.
var cars_3d := true
# --- 0.8.0 graphics quality (render pipeline presets) ---
# gfx_choice: GfxPresets.AUTO or a fixed level; gfx_auto_level is what the
# first-launch benchmark resolved Auto to (-1 = not measured yet).
var gfx_choice := GfxPresets.AUTO
var gfx_auto_level := -1
var gfx_buttons: Array = []
var gfx_desc: Label

var garage_index := 0
var settings_from_pause := false
var in_game := false
var paused := false
var result_open := false
var _run_id := 0
var _shots := false
var _hint_t := 0.0

var player_name := "ГОНЩИК"
var daily_date := ""
var daily_best := 0
var daily_tier := 0
var daily_history: Dictionary = {}
var beaten_duels: Array = []
var active_challenge: Dictionary = {}
var loaded_duel: Dictionary = {}
var last_challenge_code := ""
var incoming_challenge_code := ""
var last_share_is_rematch := false
var _last_run_shareable := false
var _pending_invite_code := ""
var _native_challenges: Object

var ch_name_input: LineEdit
var ch_code_input: LineEdit
var ch_tabs: Array[Button] = []
var ch_pages: Array[ScrollContainer] = []
var ch_daily_info: Label
var ch_daily_status: Label
var ch_daily_progress: ProgressBar
var ch_daily_medals: Array[Label] = []
var ch_daily_rewards: Array[Label] = []
var ch_duel_preview: Label
var ch_duel_name: Label
var ch_duel_target: Label
var ch_duel_details: VBoxContainer
var ch_accept_btn: Button
var ch_share_btn: Button
var ch_copy_invite_btn: Button
var ch_copy_full_btn: Button
var ch_copy_row: HBoxContainer
var ch_outgoing_label: Label

# Yandex Ads: top banner (menu, garage, finish) and the rewarded revive.
const REVIVE_SECONDS := 5.0
var revive_panel: Control
var revive_count_label: Label
var revive_btn: Button
var revive_open := false
var _revive_watching := false
var _revive_t := 0.0
var _revive_result: Array = []
var _banner_shown := false
# Race banner: decided when a race starts from a height already measured, and
# kept for the whole race so the HUD never jumps (late load / failure / no net).
var race_banner_on := false
var race_banner_top := 0.0
const TUTORIAL_PANEL_Y := 216.0


func _ready() -> void:
	_load()
	if Engine.has_singleton("SlipstreamChallenges"):
		_native_challenges = Engine.get_singleton("SlipstreamChallenges")
		_native_challenges.connect("replay_share_failed", _on_replay_share_failed, CONNECT_DEFERRED)
	Engine.max_fps = fps_limit
	_setup_fonts()
	game = Game.new()
	game.name = "Game"
	game.use_3d_cars = cars_3d
	game.gfx_level = _gfx_effective_level()
	game.gfx_target_fps = fps_limit
	add_child(game)
	_gfx_maybe_benchmark()
	game.hud_changed.connect(_on_hud)
	game.run_ended.connect(_on_crashed)
	game.near_miss.connect(_on_near)
	game.cut_in.connect(_on_cut_in)
	game.pickup_taken.connect(_on_pickup)
	game.lane_changed.connect(_on_game_lane_changed)
	game.brake_state_changed.connect(_on_game_brake_changed)
	game.status_changed.connect(_on_status_changed)
	game.rewind_started.connect(_on_rewind_started)
	game.rewind_finished.connect(_on_rewind_finished)
	game.nitro_boosted.connect(_on_game_nitro_boosted)
	game.chrono_shield_triggered.connect(_on_chrono_shield)
	game.road_event_banner.connect(_show_event_banner)
	game.duel_milestone.connect(_on_duel_milestone)
	game.challenge_hud_changed.connect(_on_challenge_hud)

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
	_build_challenges()
	_build_confirm()
	_build_exit_panel()
	_build_tutorial()
	_build_revive()

	AdsService.banner_layout_changed.connect(_apply_banner_layout)
	AdsService.availability_changed.connect(_on_ads_availability)
	AdsService.rewarded_finished.connect(_on_revive_ad_finished)
	get_viewport().size_changed.connect(_apply_banner_layout)

	show_menu()
	Sfx.set_sfx_volume(sfx_volume)
	Sfx.set_music_volume(music_volume)
	Sfx.set_sfx_enabled(sfx_on)
	Sfx.set_music_enabled(music_on)

	get_tree().set_quit_on_go_back(false)
	get_tree().set_auto_accept_quit(false)
	get_window().go_back_requested.connect(_on_back)
	get_window().close_requested.connect(_on_back)
	if "--shots" in OS.get_cmdline_user_args():
		_shots = true
		_capture_seq()
	if "--qa-traffic" in OS.get_cmdline_user_args():
		_shots = true
		_qa_traffic_seq(false)
	if "--qa-traffic-2d" in OS.get_cmdline_user_args():
		_shots = true
		_qa_traffic_seq(true)
	if "--qa-scene" in OS.get_cmdline_user_args():
		_shots = true
		_qa_scene_seq()


func _process(delta: float) -> void:
	_sync_ads_banner()
	if revive_open and not _revive_watching and not AdsService.fullscreen:
		_revive_t = maxf(0.0, _revive_t - delta)
		if revive_count_label != null:
			revive_count_label.text = str(int(ceil(_revive_t)))
		if _revive_t <= 0.0:
			_decline_revive()

	if (_event_banner_t > 0.0 or _event_banner_gap > 0.0) and in_game and not paused:
		_update_event_banner(delta)

	if _hint_t > 0.0 and in_game and not paused:
		_hint_t = maxf(0.0, _hint_t - delta)
		if _hint_t <= 0.0 and swipe_hint != null:
			swipe_hint.visible = false

	if _overheat_recovered_t > 0.0:
		_overheat_recovered_t = maxf(0.0, _overheat_recovered_t - delta)
		if _overheat_recovered_t <= 0.0 and overheat_label != null and not _was_overheated:
			overheat_label.visible = false

	if tutorial_active and in_game and not paused and not result_open and game.running and not game.paused and not game.crashed and not game.rewinding:
		tutorial_timer += delta
		match tutorial_step:
			1:
				if tutorial_timer >= 1.4:
					if tutorial_panel != null and not tutorial_panel.visible:
						tutorial_panel.visible = true
						tutorial_title.text = "ОБУЧЕНИЕ · ПЕРЕСТРОЕНИЕ"
						tutorial_title.add_theme_color_override("font_color", amber)
						match control_mode:
							"zones":
								tutorial_text.text = "Нажмите ПРАВУЮ или ЛЕВУЮ зону экрана для перестроения"
							"buttons":
								tutorial_text.text = "Нажмите КНОПКУ СО СТРЕЛКОЙ для перестроения"
							"swipe":
								tutorial_text.text = "СВАЙПНИТЕ вправо или влево для перестроения"
						if game != null:
							game.spawn_tutorial_car(game.lane)
							game.time_scale = 0.16
			2:
				if tutorial_timer >= 2.0 and not _step2_prompted:
					_step2_prompted = true
					if tutorial_panel != null:
						tutorial_panel.visible = true
						tutorial_title.text = "ОБУЧЕНИЕ · ТОРМОЖЕНИЕ"
						tutorial_title.add_theme_color_override("font_color", amber)
						match control_mode:
							"zones":
								tutorial_text.text = "Нажмите ОБЕ СТОРОНЫ экрана для тормоза.\n(Не держите долго — тормоза перегреваются!)"
							"buttons":
								tutorial_text.text = "Зажмите кнопку «ТОРМОЗ», чтобы сбросить скорость.\n(Не держите долго — тормоза перегреваются!)"
							"swipe":
								tutorial_text.text = "СВАЙПНИТЕ ВНИЗ для включения тормоза.\n(Не держите долго — тормоза перегреваются!)"
					if game != null:
						game.spawn_tutorial_car(game.lane)
						game.time_scale = 0.16
			3:
				if tutorial_timer >= 1.7 and not _nitro_prompted:
					_nitro_prompted = true
					if tutorial_panel != null:
						tutorial_panel.visible = true
						tutorial_title.text = "ОБУЧЕНИЕ · НИТРО"
						tutorial_title.add_theme_color_override("font_color", amber)
						match control_mode:
							"zones":
								tutorial_text.text = "Нитро копится за обгоны впритирку. Нажмите кнопку с молнией по центру внизу."
							"buttons":
								tutorial_text.text = "Нитро копится за обгоны впритирку. Нажмите кнопку с молнией справа внизу"
							"swipe":
								tutorial_text.text = "Нитро копится за обгоны впритирку. СВАЙПНИТЕ ВВЕРХ, чтобы ускориться"
					if game != null:
						game.nitro = 1.0
						game._nitro_cooldown = 0.0
						game.time_scale = 0.35
			4:
				if tutorial_timer >= 3.2:
					if tutorial_panel != null:
						tutorial_panel.visible = false
					tutorial_active = false
					tutorial_done = true
					if game != null:
						game.time_scale = 1.0
						game.set_tutorial_mode(false)
					_save()


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
		sfx_volume = float(cf.get_value("audio", "sfx_vol", 0.90))
		music_volume = float(cf.get_value("audio", "music_vol", 0.75))
		var mode := str(cf.get_value("controls", "mode", "zones"))
		control_mode = mode if mode in ["zones", "buttons", "swipe"] else "zones"
		var fl := int(cf.get_value("display", "fps", 60))
		fps_limit = fl if fl in [30, 60, 120] else 60
		cars_3d = bool(cf.get_value("display", "cars_3d", true))
		gfx_choice = GfxPresets.level_from_key(str(cf.get_value("display", "gfx", "auto")))
		gfx_auto_level = int(cf.get_value("display", "gfx_auto_level", -1))
		tutorial_done = bool(cf.get_value("game", "tutorial_done", false))
		player_name = ChallengeCodec.sanitize_name(str(cf.get_value("challenge", "player_name", "ГОНЩИК")))
		daily_date = str(cf.get_value("challenge", "daily_date", ""))
		daily_best = int(cf.get_value("challenge", "daily_best", 0))
		daily_tier = int(cf.get_value("challenge", "daily_tier", 0))
		var history = cf.get_value("challenge", "daily_history", {})
		daily_history = history if history is Dictionary else {}
		var bd = cf.get_value("challenge", "beaten_duels", [])
		beaten_duels = bd if bd is Array else []
		var incoming := ChallengeCodec.decode(str(cf.get_value("challenge", "incoming_code", "")))
		if bool(incoming.get("ok", false)):
			incoming_challenge_code = str(incoming.code)
			loaded_duel = incoming
		var outgoing := ChallengeCodec.decode(str(cf.get_value("challenge", "outgoing_code", "")))
		if bool(outgoing.get("ok", false)):
			last_challenge_code = str(outgoing.code)
			last_share_is_rematch = bool(cf.get_value("challenge", "outgoing_rematch", false))
	_sync_daily_date()
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
	cf.set_value("audio", "sfx_vol", sfx_volume)
	cf.set_value("audio", "music_vol", music_volume)
	cf.set_value("controls", "mode", control_mode)
	cf.set_value("display", "fps", fps_limit)
	cf.set_value("display", "cars_3d", cars_3d)
	cf.set_value("display", "gfx", GfxPresets.key_from_level(gfx_choice))
	cf.set_value("display", "gfx_auto_level", gfx_auto_level)
	cf.set_value("game", "tutorial_done", tutorial_done)
	cf.set_value("challenge", "player_name", player_name)
	cf.set_value("challenge", "daily_date", daily_date)
	cf.set_value("challenge", "daily_best", daily_best)
	cf.set_value("challenge", "daily_tier", daily_tier)
	cf.set_value("challenge", "daily_history", daily_history)
	cf.set_value("challenge", "beaten_duels", beaten_duels)
	cf.set_value("challenge", "incoming_code", incoming_challenge_code)
	cf.set_value("challenge", "outgoing_code", last_challenge_code)
	cf.set_value("challenge", "outgoing_rematch", last_share_is_rematch)
	cf.save(SAVE_PATH)


# --- screens ----------------------------------------------------------------

func _hide_screens() -> void:
	for s in [menu, garage, settings, how, challenges_panel]:
		if s != null:
			s.visible = false
	if exit_panel != null:
		exit_panel.visible = false


func show_menu() -> void:
	_reset_driving_input()
	_close_revive()
	_clear_event_banners()
	tutorial_active = false
	if tutorial_panel != null:
		tutorial_panel.visible = false
	in_game = false
	paused = false
	result_open = false
	_hide_screens()
	active_challenge = {}
	if game != null:
		game.challenge_config = {}
	menu.visible = true
	hud.visible = false
	pause_panel.visible = false
	result_panel.visible = false
	confirm_panel.visible = false
	game.car_index = selected
	game.start_demo()
	Sfx.stop_engine()
	Sfx.set_paused(false)
	Sfx.play_music()
	_update_all_labels()


func show_garage() -> void:
	_reset_driving_input()
	_close_revive()
	tutorial_active = false
	if tutorial_panel != null:
		tutorial_panel.visible = false
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
	active_challenge = {}
	if game != null:
		game.challenge_config = {}
	garage_index = selected
	game.car_index = selected
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


func _start_solo_game() -> void:
	active_challenge = {}
	start_game(false)


func start_game(force_tutorial := false) -> void:
	_run_id += 1
	_close_revive()
	var bench := get_node_or_null("GfxBenchmark")
	if bench != null:
		bench.cancel()
		gfx_benchmarking = false
	var known_banner := AdsService.known_banner_height()
	race_banner_on = known_banner > 0
	race_banner_top = AdsService.px_to_design(get_viewport(), known_banner) if race_banner_on else 0.0
	if not race_banner_on:
		AdsService.prefetch_banner()
	_apply_banner_layout()
	Sfx.click()
	_hide_screens()
	pause_panel.visible = false
	result_panel.visible = false
	confirm_panel.visible = false
	if exit_panel != null:
		exit_panel.visible = false
	_clear_event_banners()
	if challenge_hud_panel != null:
		challenge_hud_panel.visible = not active_challenge.is_empty() and not force_tutorial
	hud.visible = true
	in_game = true
	paused = false
	result_open = false
	if force_tutorial:
		active_challenge = {}
	if str(active_challenge.get("type", "")) == "daily" and active_challenge.has("date_key"):
		_sync_daily_date(str(active_challenge.date_key))
	game.challenge_config = active_challenge.duplicate() if not active_challenge.is_empty() else {}
	game.car_index = int(active_challenge.get("car_index", selected)) if not active_challenge.is_empty() else selected
	game.control_mode = control_mode
	_reset_driving_input()
	_apply_control_ui()
	_hint_t = 6.0 if control_mode == "swipe" else 0.0
	if swipe_hint != null:
		swipe_hint.visible = control_mode == "swipe"

	if force_tutorial or (not tutorial_done and active_challenge.is_empty()):
		tutorial_active = true
		tutorial_step = 1
		tutorial_timer = 0.0
		_step2_prompted = false
		_nitro_prompted = false
		if tutorial_panel != null:
			tutorial_panel.visible = false
	else:
		tutorial_active = false
		_step2_prompted = false
		_nitro_prompted = false
		if tutorial_panel != null:
			tutorial_panel.visible = false

	game.start_run(tutorial_active)
	game.set_tutorial_mode(tutorial_active)
	game.record_target = best + 1 if best > 0 and not tutorial_active and active_challenge.is_empty() else 0
	_was_overheated = false
	Sfx.set_paused(false)
	Sfx.play_engine()
	Sfx.play_music()


func _apply_control_ui() -> void:
	_reset_driving_input()
	if zones_pad != null:
		zones_pad.visible = (control_mode == "zones")
		if not zones_pad.visible:
			zones_pad.reset()

	var button_mode := control_mode == "buttons"
	pad_left.visible = button_mode
	pad_right.visible = button_mode
	brake_btn.visible = button_mode

	if control_mode == "zones":
		_place_bottom(nitro_btn, 286.0, 26.0, 148.0, 148.0)
	elif button_mode:
		_place_bottom(pad_left, 20.0, 28.0, 136.0, 136.0)
		_place_bottom(pad_right, 170.0, 28.0, 136.0, 136.0)
		_place_bottom(brake_btn, 330.0, 28.0, 128.0, 128.0)
		_place_bottom(nitro_btn, 544.0, 24.0, 152.0, 152.0)
	else: # swipe
		_place_bottom(nitro_btn, 544.0, 24.0, 152.0, 152.0)

	if game != null:
		game.control_mode = control_mode
	if swipe_hint != null:
		swipe_hint.visible = (control_mode == "swipe") and _hint_t > 0.0
		swipe_hint.text = "← → ПОЛОСЫ   |   ↓ ТОРМОЗ   |   ↑ НИТРО"


func _reset_driving_input() -> void:
	_chord_brake = false
	_pedal_brake = false
	_keyboard_brakes.clear()
	for control in [zones_pad, pad_left, pad_right, brake_btn, nitro_btn]:
		if control != null:
			control.reset()
	if game != null:
		game.reset_swipe()
		game.set_braking(false)
		game.clear_nitro_tap()


func _apply_brake_input() -> void:
	game.set_braking(_chord_brake or _pedal_brake or not _keyboard_brakes.is_empty())


func _toggle_pause() -> void:
	if not in_game or result_open:
		return
	Sfx.click()
	paused = not paused
	game.paused = paused
	pause_panel.visible = paused
	Sfx.set_paused(paused)
	if paused:
		_reset_driving_input()
	else:
		_apply_control_ui()


func _on_game_lane_changed(_new_lane: int) -> void:
	if tutorial_active and tutorial_step == 1:
		tutorial_step = 2
		tutorial_timer = 0.0
		_step2_prompted = false
		if game != null:
			game.time_scale = 1.0
		if tutorial_panel != null:
			tutorial_title.text = "ОТЛИЧНО!"
			tutorial_title.add_theme_color_override("font_color", Color("#5ddb75"))
			tutorial_text.text = "Полоса свободна! Набираем скорость."
		Sfx.pickup()


func _on_game_brake_changed(is_braking: bool) -> void:
	if is_braking and tutorial_active and tutorial_step == 2:
		tutorial_step = 3
		tutorial_timer = 0.0
		_nitro_prompted = false
		if game != null:
			game.time_scale = 1.0
			game.nitro = 1.0
			game._nitro_cooldown = 0.0
		if tutorial_panel != null:
			tutorial_title.text = "ПРЕВОСХОДНО!"
			tutorial_title.add_theme_color_override("font_color", Color("#5ddb75"))
			tutorial_text.text = "Тормоз спасает от аварий в плотном потоке!"
		Sfx.record()


func _skip_tutorial() -> void:
	tutorial_active = false
	tutorial_done = true
	if tutorial_panel != null:
		tutorial_panel.visible = false
	if game != null:
		game.time_scale = 1.0
		game.set_tutorial_mode(false)
	Sfx.rewind_stop()
	_save()


func _tap_nitro() -> void:
	if not in_game or paused or result_open:
		return
	if game.tap_nitro():
		Sfx.boost_burst()


func _on_game_nitro_boosted() -> void:
	if game.full_nitro:
		_show_event_banner("ПОЛНОЕ НИТРО", "ВЕСЬ БАК УШЁЛ В УСКОРЕНИЕ", Color("#d4a5ff"))
	if tutorial_active and tutorial_step == 3:
		tutorial_step = 4
		tutorial_timer = 0.0
		if game != null:
			game.time_scale = 1.0
		if tutorial_panel != null:
			tutorial_panel.visible = true
			tutorial_title.text = "СЛИПСТРИМ И ОБГОН"
			tutorial_title.add_theme_color_override("font_color", Color("#7fc4ff"))
			tutorial_text.text = "Держитесь сзади для слипстрима. Обгон перед носом машины восстанавливает нитро!"
		Sfx.record()


func _on_near(_combo: int) -> void:
	Sfx.whoosh()


func _on_cut_in(_combo: int) -> void:
	Sfx.cut_in()


func _on_status_changed(slip: float, heat: float, over: bool) -> void:
	if slip_label != null:
		var show_slip := in_game and not result_open
		if show_slip and game != null and game.slingshot_charge >= 0.99 and not tutorial_active:
			slip_label.visible = true
			slip_label.text = "РОГАТКА ГОТОВА! ПЕРЕСТРОЙСЯ →"
			slip_label.add_theme_color_override("font_color", Color("#ffd447"))
		elif show_slip and slip > 0.18:
			slip_label.visible = true
			if not tutorial_active and game != null and game.slingshot_charge > 0.08:
				slip_label.text = "СЛИПСТРИМ +%d%% · РОГАТКА %d%%" % [int(round(slip * Game.SLIP_BONUS * 100.0)), int(round(game.slingshot_charge * 100.0))]
			else:
				slip_label.text = "СЛИПСТРИМ  +%d%%" % int(round(slip * Game.SLIP_BONUS * 100.0))
			slip_label.add_theme_color_override("font_color", Color("#9bd6ff"))
		elif show_slip and game != null and game.hyperdrive_active:
			slip_label.visible = true
			slip_label.text = "ГИПЕРДРАЙВ · ОЧКИ ×%d" % game._effective_score_mult()
			slip_label.add_theme_color_override("font_color", Color("#ff6b7a"))
		elif show_slip and game != null and game.score_mult > 1:
			slip_label.visible = true
			slip_label.text = "БОНУС-ЗОНА · ОЧКИ ×%d" % game._effective_score_mult()
			slip_label.add_theme_color_override("font_color", amber)
		else:
			slip_label.visible = false
	if brake_heat_bar != null:
		brake_heat_bar.value = heat
		var show_bar := in_game and not result_open and (heat > 0.02 or over)
		brake_heat_bar.visible = show_bar
		if brake_heat_mark != null:
			brake_heat_mark.visible = show_bar
	if brake_heat_fill != null:
		if over:
			brake_heat_fill.bg_color = Color("#ff3b2f")
		else:
			brake_heat_fill.bg_color = Color("#f2b134").lerp(Color("#e23b30"), clampf((heat - 0.55) / 0.45, 0.0, 1.0))
	if overheat_label != null:
		if over:
			overheat_label.visible = in_game and not result_open
			overheat_label.text = "ОСТЫВАНИЕ... %d%% (ЖДИТЕ 28%%)" % int(round(heat * 100.0))
			overheat_label.add_theme_color_override("font_color", Color("#ff4438"))
		elif _was_overheated and not over:
			_overheat_recovered_t = 1.6
			overheat_label.visible = in_game and not result_open
			overheat_label.text = "ТОРМОЗА ГОТОВЫ!"
			overheat_label.add_theme_color_override("font_color", Color("#5ddb75"))
		elif _overheat_recovered_t > 0.0:
			overheat_label.visible = in_game and not result_open
		else:
			overheat_label.visible = false
	if over and not _was_overheated:
		brake_btn.reset()
		if zones_pad != null:
			zones_pad.reset()
	_was_overheated = over


func _on_rewind_started() -> void:
	Sfx.rewind_start()
	if tutorial_panel != null:
		tutorial_panel.visible = true
		tutorial_title.text = "ОТМАТКА ВРЕМЕНИ"
		tutorial_title.add_theme_color_override("font_color", Color("#7fc4ff"))
		tutorial_text.text = "Без Game Over: возвращаемся на пару секунд назад."


func _on_rewind_finished() -> void:
	Sfx.rewind_stop()
	if tutorial_panel != null and tutorial_active:
		_refresh_tutorial_prompt()
	elif tutorial_panel != null:
		# Chrono-Shield / ad revive in a normal run: drop the rewind notice.
		tutorial_panel.visible = false


func _refresh_tutorial_prompt() -> void:
	if tutorial_panel == null or not tutorial_active:
		return
	tutorial_panel.visible = true
	tutorial_title.add_theme_color_override("font_color", amber)
	match tutorial_step:
		1:
			tutorial_title.text = "ОБУЧЕНИЕ · ПЕРЕСТРОЕНИЕ"
			match control_mode:
				"zones":
					tutorial_text.text = "Нажмите ПРАВУЮ или ЛЕВУЮ зону экрана для перестроения"
				"buttons":
					tutorial_text.text = "Нажмите КНОПКУ СО СТРЕЛКОЙ для перестроения"
				"swipe":
					tutorial_text.text = "СВАЙПНИТЕ вправо или влево для перестроения"
		2:
			tutorial_title.text = "ОБУЧЕНИЕ · ТОРМОЖЕНИЕ"
			match control_mode:
				"zones":
					tutorial_text.text = "Нажмите ОБЕ СТОРОНЫ экрана для тормоза.\n(Не держите долго — тормоза перегреваются!)"
				"buttons":
					tutorial_text.text = "Зажмите кнопку «ТОРМОЗ», чтобы сбросить скорость.\n(Не держите долго — тормоза перегреваются!)"
				"swipe":
					tutorial_text.text = "СВАЙПНИТЕ ВНИЗ для включения тормоза.\n(Не держите долго — тормоза перегреваются!)"
		3:
			tutorial_title.text = "ОБУЧЕНИЕ · НИТРО"
			match control_mode:
				"zones":
					tutorial_text.text = "Нитро копится за обгоны впритирку. Нажмите кнопку с молнией по центру внизу."
				"buttons":
					tutorial_text.text = "Нитро копится за обгоны впритирку. Нажмите кнопку с молнией справа внизу"
				"swipe":
					tutorial_text.text = "Нитро копится за обгоны впритирку. СВАЙПНИТЕ ВВЕРХ, чтобы ускориться"
		4:
			tutorial_title.text = "СЛИПСТРИМ И ОБГОН"
			tutorial_title.add_theme_color_override("font_color", Color("#7fc4ff"))
			tutorial_text.text = "Держитесь сзади для слипстрима. Обгон перед носом машины восстанавливает нитро!"
		_:
			tutorial_title.text = "ГОТОВО!"
			tutorial_text.text = "Обучение пройдено. Теперь — в плотный поток!"


func _on_pickup(kind: int) -> void:
	if kind == 0:
		Sfx.pickup_coin()
	else:
		Sfx.pickup_nitro()


func _on_hud(score: int, kmh: int, nitro: float, combo: int, run_coins: int, boosting: bool) -> void:
	score_label.text = _fmt(score)
	speed_label.text = str(kmh)
	nitro_btn.set_segments(4 if (game != null and game.car_perk == "extra_tank") else 3)
	nitro_btn.set_charge(nitro)
	nitro_btn.set_active(boosting, boosting and game.full_nitro)
	nitro_btn.set_shield_ready(not tutorial_active and nitro >= 1.0 - 0.002)
	if weather_clock != null:
		weather_clock.set_state(game.weather_state, game.get_night_factor() > 0.5, game.get_clock_text(), game.forecast_weather())
	coins_label.text = ("МОНЕТЫ  " + _fmt(run_coins)) if run_coins > 0 else ""
	if combo > 1:
		combo_label.text = "×%d СЕРИЯ" % combo
	else:
		combo_label.text = ""
	Sfx.update_engine(game.speed, boosting, game.braking, game.overheated, game.slip)


func _show_event_banner(title: String, sub: String, col: Color) -> void:
	if event_banner == null or not in_game or tutorial_active:
		return
	if _event_banner_t > 0.0 and event_banner_title.text == title and event_banner_sub.text == sub:
		return
	if _event_banner_queue.any(func(entry: Dictionary) -> bool: return entry.title == title and entry.sub == sub):
		return
	if _event_banner_queue.size() >= EVENT_BANNER_LIMIT:
		_event_banner_queue.pop_front()
	_event_banner_queue.append({"title": title, "sub": sub, "color": col})
	if _event_banner_t <= 0.0 and _event_banner_gap <= 0.0:
		_next_event_banner()


func _next_event_banner() -> void:
	if _event_banner_queue.is_empty():
		event_banner.visible = false
		return
	var entry: Dictionary = _event_banner_queue.pop_front()
	event_banner_title.text = entry.title
	event_banner_sub.text = entry.sub
	event_banner_title.add_theme_color_override("font_color", entry.color)
	var duel_bar := challenge_hud_panel != null and challenge_hud_panel.visible
	_place(event_banner, EVENT_BANNER_X - 12.0, EVENT_BANNER_Y_DUEL if duel_bar else EVENT_BANNER_Y, EVENT_BANNER_W, 44.0)
	event_banner.modulate.a = 0.0
	event_banner.visible = true
	_event_banner_t = EVENT_BANNER_TIME


func _update_event_banner(delta: float) -> void:
	if _event_banner_t <= 0.0:
		_event_banner_gap = maxf(0.0, _event_banner_gap - delta)
		if _event_banner_gap <= 0.0:
			_next_event_banner()
		return
	_event_banner_t = maxf(0.0, _event_banner_t - delta)
	if _event_banner_t <= 0.0:
		event_banner.visible = false
		_event_banner_gap = EVENT_BANNER_GAP
		return
	var appear := smoothstep(0.0, EVENT_BANNER_ENTER, EVENT_BANNER_TIME - _event_banner_t)
	var disappear := smoothstep(0.0, EVENT_BANNER_EXIT, _event_banner_t)
	var weight := appear * disappear
	event_banner.position.x = EVENT_BANNER_X - (1.0 - weight) * 12.0
	event_banner.modulate.a = weight


func _clear_event_banners() -> void:
	_event_banner_queue.clear()
	_event_banner_t = 0.0
	_event_banner_gap = 0.0
	if event_banner != null:
		event_banner.visible = false


# Routine manoeuvres (slingshot, nitro ram, cones, puddles) get sound and
# effects only; notifications are for road events and rare saves.
func _on_chrono_shield() -> void:
	_show_event_banner("ХРОНО-ЩИТ АКТИВИРОВАН!", "3 ЗАРЯДА НИТРО СПАСЛИ ОТ АВАРИИ", Color("#5ce1e6"))


func _on_duel_milestone(kind: String) -> void:
	if kind == "crash_passed":
		_show_event_banner("МЕСТО АВАРИИ ПРОЙДЕНО!", "ТЫ ПРОЕХАЛ ДАЛЬШЕ СОПЕРНИКА", Color("#5ce1e6"))
	elif kind == "score_beaten":
		_show_event_banner("СЧЁТ СОПЕРНИКА ПОБИТ!", "УДЕРЖИ ПРЕИМУЩЕСТВО", Color("#5ddb75"))


func _on_challenge_hud(info: Dictionary) -> void:
	if challenge_hud_panel == null or challenge_hud_label == null:
		return
	if info.is_empty() or not in_game or tutorial_active:
		challenge_hud_panel.visible = false
		return
	challenge_hud_panel.visible = true
	var ctype := str(info.get("type", ""))
	if ctype == "duel":
		var gap_m := int(info.get("gap_m", 0))
		var need := int(info.get("rival_score", 0)) + 1 - int(game.score)
		var position_text := "%+d М" % gap_m if gap_m != 0 else "РЯДОМ"
		if bool(info.get("ghost_finished", false)):
			position_text = "ПРИЗРАК ФИНИШИРОВАЛ"
		var score_text := "ЦЕЛЬ ВЗЯТА" if need <= 0 else "ДО ПОБЕДЫ %s ОЧК." % _fmt(need)
		challenge_hud_label.text = "%s · %s · %s" % [str(info.get("name", "ДРУГ")), position_text, score_text]
		challenge_hud_label.add_theme_color_override("font_color", Color("#5ddb75") if need <= 0 else DUEL_CYAN)
	elif ctype == "daily":
		var b := int(info.get("bronze", 6500))
		var s := int(info.get("silver", 14500))
		var g := int(info.get("gold", 26000))
		var cur := int(game.score) if game != null else 0
		var next_lbl := "ЗОЛОТО %s" % _fmt(g)
		if cur < b:
			next_lbl = "БРОНЗА %s" % _fmt(b)
		elif cur < s:
			next_lbl = "СЕРЕБРО %s" % _fmt(s)
		elif cur >= g:
			next_lbl = "ВСЕ ЦЕЛИ ВЗЯТЫ!"
		challenge_hud_label.text = "ВЫЗОВ ДНЯ · ЦЕЛЬ: %s" % next_lbl
		challenge_hud_label.add_theme_color_override("font_color", amber)


func _on_crashed(score: int, dist: int, near: int, run_coins: int) -> void:
	_reset_driving_input()
	var was_tutorial := tutorial_active
	if tutorial_active:
		tutorial_active = false
		if tutorial_panel != null:
			tutorial_panel.visible = false
		if game != null:
			game.time_scale = 1.0
			game.set_tutorial_mode(false)
		Sfx.rewind_stop()
	Sfx.crash()
	Sfx.stop_engine()
	if not was_tutorial and _revive_offerable():
		_offer_revive([score, dist, near, run_coins])
		return
	_settle_run(score, dist, near, run_coins, was_tutorial)


# Scores, pays and saves a finished run, then shows the finish screen.
func _settle_run(score: int, dist: int, near: int, run_coins: int, was_tutorial := false, delay := 1.05) -> void:
	var finished_run := _run_id
	var is_record := score > best
	if is_record:
		best = score

	var mode_bonus := 0
	var mode_banner_txt := ""
	var mode_banner_col := amber
	var ctype := str(active_challenge.get("type", ""))
	if ctype == "duel" and not was_tutorial:
		var rscore := int(active_challenge.get("score", 0))
		var rname := str(active_challenge.get("name", "ДРУГ"))
		var won := score > rscore
		if won:
			var cid := str(active_challenge.get("id", ""))
			if cid != "" and not beaten_duels.has(cid):
				beaten_duels.append(cid)
				mode_bonus = ChallengeCodec.DUEL_WIN_REWARD
				mode_banner_txt = "ПОБЕДА НАД %s! +%d МОНЕТ" % [rname, mode_bonus]
			else:
				mode_banner_txt = "ПОБЕДА НАД %s! (+%s ОЧК.)" % [rname, _fmt(score - rscore)]
			mode_banner_col = Color("#5ddb75")
		else:
			mode_banner_txt = "ВЫЗОВ %s: НЕ ХВАТИЛО %s ОЧКОВ" % [rname, _fmt(maxi(1, rscore - score + 1))]
			mode_banner_col = Color("#ff8a6b")
	elif ctype == "daily" and not was_tutorial:
		if score > daily_best:
			daily_best = score
		var rewards := ChallengeCodec.DAILY_REWARDS
		var targets := [int(active_challenge.get("bronze", 6500)), int(active_challenge.get("silver", 14500)), int(active_challenge.get("gold", 26000))]
		var tier_names := ["БРОНЗА", "СЕРЕБРО", "ЗОЛОТО"]
		var hit_tier := 0
		for idx in range(3):
			if score >= targets[idx]:
				hit_tier = idx + 1
				if daily_tier < idx + 1:
					mode_bonus += rewards[idx]
					daily_tier = idx + 1
		if mode_bonus > 0:
			mode_banner_txt = "ВЫЗОВ ДНЯ · %s! +%d МОНЕТ" % [tier_names[hit_tier - 1], mode_bonus]
			mode_banner_col = Color("#5ddb75")
		elif hit_tier > 0:
			mode_banner_txt = "ВЫЗОВ ДНЯ · %s (РЕКОРД ДНЯ %s)" % [tier_names[hit_tier - 1], _fmt(daily_best)]
			mode_banner_col = amber
		else:
			mode_banner_txt = "ВЫЗОВ ДНЯ · ДО БРОНЗЫ %s ОЧК." % _fmt(maxi(0, targets[0] - score))
			mode_banner_col = dim_col

	_last_run_shareable = not was_tutorial and game != null and game.ghost_rec.size() > 1 and score > 0
	if _last_run_shareable:
		var payload := game.build_challenge_payload(player_name)
		payload.score = score
		last_challenge_code = ChallengeCodec.encode(payload)
		last_share_is_rematch = ctype == "duel"

	var earned := run_coins + (25 if is_record else 0) + mode_bonus
	coins += earned
	_save()
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if not in_game or finished_run != _run_id or not game.crashed:
		return
	in_game = false
	result_open = true
	paused = false
	hud.visible = false
	pause_panel.visible = false
	confirm_panel.visible = false
	_hide_screens()
	game.paused = true
	Sfx.set_paused(false)
	_show_result(score, dist, near, earned, is_record, mode_banner_txt, mode_banner_col)


func _show_result(score: int, dist: int, near: int, earned: int, is_record: bool, mode_txt := "", mode_col := Color.WHITE) -> void:
	if is_record:
		Sfx.record()
	result_score.text = _fmt(score)
	result_record.visible = is_record
	if result_mode_banner != null:
		result_mode_banner.visible = mode_txt != ""
		if result_mode_banner.visible:
			result_mode_banner.text = mode_txt
			result_mode_banner.add_theme_color_override("font_color", mode_col)
	if result_share_btn != null:
		var can_share := _last_run_shareable and last_challenge_code != ""
		result_share_btn.visible = can_share
		result_share_btn.disabled = false
		if can_share:
			var is_duel := str(active_challenge.get("type", "")) == "duel"
			result_share_btn.text = "ПОДЕЛИТЬСЯ РЕВАНШЕМ" if is_duel else "ПОДЕЛИТЬСЯ ВЫЗОВОМ"
			result_share_btn.add_theme_color_override("font_color", Color("#eaf6f8"))
	result_return_btn.text = "К ВЫЗОВАМ" if not active_challenge.is_empty() else "ГАРАЖ"
	result_dist.text = "%d м" % dist
	result_near.text = str(near)
	result_best.text = _fmt(best)
	result_coins.text = "+%s МОНЕТ" % _fmt(earned)
	result_total.text = "БАЛАНС  %s" % _fmt(coins)
	result_panel.visible = true
	_update_all_labels()


func _on_back() -> void:
	if revive_open:
		if not _revive_watching:
			_decline_revive()
		return
	if exit_panel != null and exit_panel.visible:
		_hide_exit_panel()
		return
	if confirm_panel != null and confirm_panel.visible:
		_hide_confirm()
		return
	if how != null and how.visible:
		_hide_how()
		return
	if settings != null and settings.visible:
		_hide_settings()
		return
	if challenges_panel != null and challenges_panel.visible:
		show_menu()
		return
	if garage != null and garage.visible:
		show_menu()
		return
	if result_open:
		show_menu()
		return
	# Dismiss settings and pause before interpreting Back as skipping a lesson.
	if in_game and paused:
		_toggle_pause()
		return
	if tutorial_active:
		_skip_tutorial()
		return
	if in_game:
		_toggle_pause()
		return
	_show_exit_panel()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST or what == NOTIFICATION_WM_CLOSE_REQUEST:
		_on_back()
	elif what == NOTIFICATION_APPLICATION_FOCUS_OUT:
		if in_game and not paused and not result_open and not revive_open and not _shots:
			_toggle_pause()


func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	if event.echo:
		return
	if event.pressed and event.keycode in [KEY_BACK, KEY_ESCAPE]:
		_on_back()
		get_viewport().set_input_as_handled()
		return
	if not in_game or paused or result_open:
		return
	match event.keycode:
		KEY_LEFT, KEY_A, KEY_RIGHT, KEY_D:
			var side := -1 if event.keycode in [KEY_LEFT, KEY_A] else 1
			zones_pad.set_contact(int(event.keycode) + 1000, side, event.pressed)
		KEY_SPACE:
			if event.pressed:
				_tap_nitro()
		KEY_DOWN, KEY_S:
			if event.pressed:
				_keyboard_brakes[event.keycode] = true
			else:
				_keyboard_brakes.erase(event.keycode)
			_apply_brake_input()


# --- ads: top banner and rewarded revive -------------------------------------

# The banner shows on the main menu, garage and finish screen and, when its
# height was known at the start, during the race (HUD moved below it).
# Change-detected every frame.
func _sync_ads_banner() -> void:
	var want := (in_game and race_banner_on) or (not in_game and not revive_open and (
		(menu != null and menu.visible) or (garage != null and garage.visible)
		or (result_panel != null and result_panel.visible) or (settings != null and settings.visible)
		or (how != null and how.visible) or (challenges_panel != null and challenges_panel.visible)))
	if want == _banner_shown:
		return
	_banner_shown = want
	AdsService.set_banner_visible(want)
	_apply_banner_layout()


# Screens that share the banner start below its real, measured height.
func _apply_banner_layout() -> void:
	var top := AdsService.banner_height_in(get_viewport()) if _banner_shown else 0.0
	for c in [menu, garage, result_panel, settings, how, challenges_panel]:
		if c != null:
			c.offset_top = top
	# The race HUD uses the height reserved at race start, never the live one.
	var race_top := race_banner_top if race_banner_on else 0.0
	if hud != null:
		hud.offset_top = race_top
	if tutorial_panel != null:
		tutorial_panel.position.y = TUTORIAL_PANEL_Y + race_top


func _revive_offerable() -> bool:
	if _shots or not active_challenge.is_empty() or game == null:
		return false
	return game.can_revive() and AdsService.can_show_rewarded()


func _offer_revive(result: Array) -> void:
	_revive_result = result
	revive_open = true
	_revive_watching = false
	_revive_t = REVIVE_SECONDS
	revive_count_label.text = str(int(ceil(_revive_t)))
	revive_btn.disabled = false
	pause_panel.visible = false
	revive_panel.visible = true


func _accept_revive() -> void:
	if not revive_open or _revive_watching:
		return
	# Set first: showing the ad emits availability_changed synchronously.
	_revive_watching = true
	revive_btn.disabled = true
	if not AdsService.request_rewarded():
		_revive_watching = false
		_decline_revive()


func _on_revive_ad_finished(earned: bool) -> void:
	if not revive_open or not _revive_watching:
		return
	if earned and game.revive():
		_close_revive()
		Sfx.play_engine()
		return
	_decline_revive()


# An offer is withdrawn as soon as the ad stops being available.
func _on_ads_availability() -> void:
	if revive_open and not _revive_watching and not AdsService.can_show_rewarded():
		_decline_revive()


func _decline_revive() -> void:
	if not revive_open:
		return
	var r := _revive_result
	_close_revive()
	if r.size() == 4:
		_settle_run(int(r[0]), int(r[1]), int(r[2]), int(r[3]), false, 0.0)


func _close_revive() -> void:
	revive_open = false
	_revive_watching = false
	_revive_result = []
	if revive_panel != null:
		revive_panel.visible = false


func _build_revive() -> void:
	revive_panel = Control.new()
	_full(revive_panel)
	revive_panel.visible = false
	revive_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(revive_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.02, 0.66)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(dim)
	revive_panel.add_child(dim)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(center)
	revive_panel.add_child(center)

	var card := _card(580)
	center.add_child(card)
	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 14)
	card.add_child(vb)

	vb.add_child(_label("АВАРИЯ!", 26, accent, font_bold, HORIZONTAL_ALIGNMENT_CENTER))
	var sub := _label("Отмотать пару секунд назад и ехать дальше?", 24, dim_col, font_ui, HORIZONTAL_ALIGNMENT_CENTER)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)
	revive_count_label = _label("5", 96, amber, font_num, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(revive_count_label)

	revive_btn = _button("ПРОДОЛЖИТЬ ЗА РЕКЛАМУ", true)
	revive_btn.add_theme_font_size_override("font_size", 30)
	revive_btn.pressed.connect(_accept_revive)
	vb.add_child(revive_btn)

	var skip := _text_button("НЕТ, ЗАВЕРШИТЬ ЗАЕЗД")
	skip.pressed.connect(_decline_revive)
	vb.add_child(skip)


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


func _accent_card(tint: Color) -> PanelContainer:
	var panel := _card(0)
	var style := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	style.bg_color = Color("#131d25")
	style.border_color = Color(tint, 0.22)
	style.border_width_left = 3
	style.content_margin_left = 22
	style.content_margin_right = 22
	style.content_margin_top = 16
	style.content_margin_bottom = 16
	style.shadow_size = 0
	panel.add_theme_stylebox_override("panel", style)
	return panel


func _compact_button(caption: String, height: float, font_size: int, primary := false) -> Button:
	var button := _button(caption, primary)
	button.custom_minimum_size.y = height
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _screen_scroll(parent: Control, top: float, bottom: float) -> ScrollContainer:
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.anchor_right = 1.0
	scroll.anchor_bottom = 1.0
	scroll.offset_left = 36.0
	scroll.offset_top = top
	scroll.offset_right = -36.0
	scroll.offset_bottom = -bottom
	parent.add_child(scroll)
	return scroll


func _portrait_column(parent: Control) -> Control:
	var column := Control.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.anchor_left = 0.5
	column.anchor_right = 0.5
	column.anchor_bottom = 1.0
	column.offset_left = -360.0
	column.offset_right = 360.0
	parent.add_child(column)
	return column


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


func _stat_bar(parent: Control) -> ProgressBar:
	var pb := ProgressBar.new()
	pb.show_percentage = false
	pb.max_value = 1.0
	pb.value = 0.5
	pb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	pb.custom_minimum_size.y = 8.0
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

	var tag := _label("А Р К А Д Н Ы Е   Г О Н К И", 21, accent, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
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

	var sub := _label("РЕАЛИСТИЧНЫЙ ТРАФИК · v" + version, 22, Color(0.76, 0.79, 0.79), font_ui, HORIZONTAL_ALIGNMENT_CENTER)
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
	vb.offset_top = -530
	vb.offset_bottom = -52
	menu.add_child(vb)

	var play := _button("ПОЕХАЛИ", true)
	play.custom_minimum_size = Vector2(0, 86)
	play.pressed.connect(_start_solo_game)
	vb.add_child(play)

	var chall_btn := _button("ВЫЗОВЫ · ДУЭЛЬ И ДЕНЬ", false)
	chall_btn.custom_minimum_size = Vector2(0, 78)
	chall_btn.add_theme_font_size_override("font_size", 28)
	chall_btn.add_theme_color_override("font_color", Color("#7fe9ff"))
	chall_btn.pressed.connect(show_challenges)
	vb.add_child(chall_btn)

	var row_mid := HBoxContainer.new()
	row_mid.add_theme_constant_override("separation", 12)
	vb.add_child(row_mid)

	var garage_btn := _button("ГАРАЖ", false)
	garage_btn.custom_minimum_size = Vector2(0, 78)
	garage_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	garage_btn.add_theme_font_size_override("font_size", 30)
	garage_btn.pressed.connect(show_garage)
	row_mid.add_child(garage_btn)

	var settings_btn := _button("НАСТРОЙКИ", false)
	settings_btn.custom_minimum_size = Vector2(0, 78)
	settings_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	settings_btn.add_theme_font_size_override("font_size", 28)
	settings_btn.pressed.connect(func(): _show_settings(false))
	row_mid.add_child(settings_btn)

	var how_btn := _button("КАК ИГРАТЬ", false)
	how_btn.custom_minimum_size = Vector2(0, 66)
	how_btn.add_theme_font_size_override("font_size", 28)
	how_btn.pressed.connect(_show_how)
	vb.add_child(how_btn)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 4)
	vb.add_child(spacer)

	menu_best = _label("РЕКОРД  0", 28, Color(0.78, 0.81, 0.81), font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	vb.add_child(menu_best)

	var ver := _label("v" + version + " · GODOT EDITION", 16, Color(0.44, 0.48, 0.50), font_ui, HORIZONTAL_ALIGNMENT_CENTER)
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

	slip_label = _label("", 18, Color("#9bd6ff"), font_bold)
	_place(slip_label, 46, 188, 380, 26)
	slip_label.visible = false
	hud.add_child(slip_label)

	weather_clock = WeatherClock.new()
	weather_clock.font = font_num
	_place(weather_clock, 300, 38, 290, 66)
	hud.add_child(weather_clock)

	var heat_cap := _label("ТОРМОЗА", 14, Color(0.68, 0.72, 0.74), font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(heat_cap, 430, 202, 244, 16)
	hud.add_child(heat_cap)

	brake_heat_bar = ProgressBar.new()
	brake_heat_bar.show_percentage = false
	brake_heat_bar.max_value = 1.0
	brake_heat_bar.value = 0.0
	brake_heat_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(brake_heat_bar, 430, 220, 244, 9)
	var hbg := StyleBoxFlat.new()
	hbg.bg_color = Color(1, 1, 1, 0.08)
	hbg.set_corner_radius_all(5)
	brake_heat_fill = StyleBoxFlat.new()
	brake_heat_fill.bg_color = amber
	brake_heat_fill.set_corner_radius_all(5)
	brake_heat_bar.add_theme_stylebox_override("background", hbg)
	brake_heat_bar.add_theme_stylebox_override("fill", brake_heat_fill)
	brake_heat_bar.visible = false
	hud.add_child(brake_heat_bar)

	brake_heat_mark = ColorRect.new()
	brake_heat_mark.color = Color(1.0, 1.0, 1.0, 0.45)
	brake_heat_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_place(brake_heat_mark, 430.0 + 244.0 * 0.28, 219.0, 2.0, 11.0)
	brake_heat_mark.visible = false
	hud.add_child(brake_heat_mark)

	overheat_label = _label("ПЕРЕГРЕВ ТОРМОЗОВ", 14, Color("#ff5a48"), font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
	_place(overheat_label, 396, 232, 278, 18)
	overheat_label.visible = false
	hud.add_child(overheat_label)

	challenge_hud_panel = PanelContainer.new()
	challenge_hud_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var ch_sb := StyleBoxFlat.new()
	ch_sb.bg_color = Color(0.04, 0.06, 0.09, 0.78)
	ch_sb.set_corner_radius_all(12)
	ch_sb.border_width_left = 1
	ch_sb.border_width_right = 1
	ch_sb.border_width_top = 1
	ch_sb.border_width_bottom = 1
	ch_sb.border_color = Color(0.36, 0.88, 0.96, 0.35)
	ch_sb.content_margin_left = 14
	ch_sb.content_margin_right = 14
	ch_sb.content_margin_top = 4
	ch_sb.content_margin_bottom = 4
	challenge_hud_panel.add_theme_stylebox_override("panel", ch_sb)
	_place(challenge_hud_panel, 46, 254, 628, 36)
	challenge_hud_panel.visible = false
	hud.add_child(challenge_hud_panel)

	challenge_hud_label = _label("", 19, Color("#7fe9ff"), font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	challenge_hud_panel.add_child(challenge_hud_label)

	event_banner = PanelContainer.new()
	event_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	event_banner.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_place(event_banner, EVENT_BANNER_X, EVENT_BANNER_Y, EVENT_BANNER_W, 44)
	event_banner.clip_contents = true
	event_banner.visible = false
	hud.add_child(event_banner)

	var eb_vb := VBoxContainer.new()
	eb_vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	eb_vb.add_theme_constant_override("separation", 0)
	event_banner.add_child(eb_vb)
	# Single lines, no wrapping: a wrapping label in a container can measure
	# itself one word per line and stretch over the whole screen.
	event_banner_title = _label("", 18, amber, font_bold)
	event_banner_sub = _label("", 14, Color(0.86, 0.90, 0.94), font_ui)
	for l: Label in [event_banner_title, event_banner_sub]:
		l.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		l.clip_text = true
		# No backing card, so an outline keeps the text readable on the road.
		l.add_theme_color_override("font_outline_color", Color(0.0, 0.0, 0.0, 0.75))
		l.add_theme_constant_override("outline_size", 5)
		eb_vb.add_child(l)

	var bot := _vgrad(Color(0.02, 0.025, 0.03, 0.0), Color(0.02, 0.025, 0.03, 0.14), Color(0.02, 0.025, 0.03, 0.46))
	_place_bottom(bot, 0, 0, 720, 330)
	hud.add_child(bot)

	zones_pad = ZonesPad.new()
	zones_pad.font_bold = font_bold
	zones_pad.font_ui = font_ui
	zones_pad.lane_left.connect(func(): game.move_lane(-1))
	zones_pad.lane_right.connect(func(): game.move_lane(1))
	zones_pad.brake_changed.connect(func(on: bool):
		_chord_brake = on
		_apply_brake_input())
	_place_bottom(zones_pad, 0, 0, 720, 260)
	hud.add_child(zones_pad)

	pad_left = PadButton.new()
	pad_left.kind = "left"
	pad_left.label_font = font_bold
	pad_left.chord_steering = true
	pad_left.steering_contact.connect(func(down: bool, canceled: bool): zones_pad.set_contact(-2, -1, down, canceled))
	_place_bottom(pad_left, 20, 44, 136, 136)
	hud.add_child(pad_left)

	pad_right = PadButton.new()
	pad_right.kind = "right"
	pad_right.label_font = font_bold
	pad_right.chord_steering = true
	pad_right.steering_contact.connect(func(down: bool, canceled: bool): zones_pad.set_contact(-3, 1, down, canceled))
	_place_bottom(pad_right, 170, 44, 136, 136)
	hud.add_child(pad_right)

	brake_btn = PadButton.new()
	brake_btn.kind = "brake"
	brake_btn.label_font = font_bold
	brake_btn.held_changed.connect(func(on: bool):
		_pedal_brake = on
		_apply_brake_input())
	_place_bottom(brake_btn, 330, 44, 128, 128)
	hud.add_child(brake_btn)

	nitro_btn = NitroButton.new()
	nitro_btn.label_font = font_bold
	nitro_btn.tapped.connect(_tap_nitro)
	_place_bottom(nitro_btn, 544, 40, 152, 152)
	hud.add_child(nitro_btn)

	swipe_hint = _label("← → ПОЛОСЫ   |   ↓ ТОРМОЗ   |   ↑ НИТРО", 19, Color(0.92, 0.94, 0.96, 0.92), font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	var hint_sb := StyleBoxFlat.new()
	hint_sb.bg_color = Color(0.04, 0.05, 0.06, 0.78)
	hint_sb.set_corner_radius_all(14)
	hint_sb.border_width_left = 1
	hint_sb.border_width_right = 1
	hint_sb.border_width_top = 1
	hint_sb.border_width_bottom = 1
	hint_sb.border_color = Color(1.0, 1.0, 1.0, 0.12)
	hint_sb.content_margin_left = 14
	hint_sb.content_margin_right = 14
	hint_sb.content_margin_top = 4
	hint_sb.content_margin_bottom = 4
	swipe_hint.add_theme_stylebox_override("normal", hint_sb)
	_place_bottom(swipe_hint, 60, 200, 600, 36)
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
	var column := _portrait_column(garage)

	var back := IconButton.new()
	back.kind = "back"
	back.pressed.connect(show_menu)
	_place(back, 34, 32, 76, 76)
	column.add_child(back)
	var title := _label("ГАРАЖ", 40, ink, font_bold)
	_place(title, 126, 32, 290, 76)
	column.add_child(title)
	garage_coins = _coin_chip(column, 438.0, 43.0, 246.0)

	var scroll := _screen_scroll(column, 118.0, 172.0)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 12)
	scroll.add_child(content)

	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 0)
	content.add_child(heading)
	g_name = _label("", 42, ink, font_num, HORIZONTAL_ALIGNMENT_CENTER)
	heading.add_child(g_name)
	g_sub = _label("", 20, dim_col, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	heading.add_child(g_sub)

	g_stage = CarStage.new()
	g_stage.custom_minimum_size.y = 500
	content.add_child(g_stage)
	var angles := HBoxContainer.new()
	angles.add_theme_constant_override("separation", 8)
	content.add_child(angles)
	for view in [["СПЕРЕДИ", CarStage.FRONT], ["СБОКУ", CarStage.SIDE], ["СЗАДИ", CarStage.REAR]]:
		var angle := _compact_button(str(view[0]), 50, 21)
		angle.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		angle.pressed.connect(g_stage.set_view.bind(view[1]))
		angles.add_child(angle)
	var drag_hint := _label("Проведи по машине, чтобы повернуть её", 19, dim_col, font_ui, HORIZONTAL_ALIGNMENT_CENTER)
	content.add_child(drag_hint)

	var picker := GridContainer.new()
	picker.columns = 3
	picker.add_theme_constant_override("h_separation", 8)
	picker.add_theme_constant_override("v_separation", 6)
	content.add_child(picker)
	for i in range(Cars.LIST.size()):
		var slot := _compact_button(str(Cars.get_car(i).name), 43, 19)
		slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slot.pressed.connect(_select_garage_slot.bind(i))
		picker.add_child(slot)
		g_slots.append(slot)

	var stat_card := _card(0)
	var stat_style := stat_card.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	stat_style.content_margin_top = 13
	stat_style.content_margin_bottom = 15
	stat_style.content_margin_left = 24
	stat_style.content_margin_right = 24
	stat_style.shadow_size = 0
	stat_card.add_theme_stylebox_override("panel", stat_style)
	content.add_child(stat_card)
	var stat_rows := VBoxContainer.new()
	stat_rows.add_theme_constant_override("separation", 8)
	stat_card.add_child(stat_rows)
	for caption in ["СКОРОСТЬ", "РАЗГОН", "МАНЁВРЕННОСТЬ"]:
		var metric := VBoxContainer.new()
		metric.add_theme_constant_override("separation", 2)
		stat_rows.add_child(metric)
		var row := HBoxContainer.new()
		metric.add_child(row)
		var lab := _label(caption, 19, dim_col, font_bold)
		lab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(lab)
		var val := _label("", 21, ink, font_bold, HORIZONTAL_ALIGNMENT_RIGHT)
		row.add_child(val)
		g_vals.append(val)
		g_bars.append(_stat_bar(metric))

	var perk_card := _accent_card(amber)
	content.add_child(perk_card)
	var perk := VBoxContainer.new()
	perk.add_theme_constant_override("separation", 2)
	perk_card.add_child(perk)
	g_perk_title = _label("", 22, amber, font_bold)
	perk.add_child(g_perk_title)
	g_perk_desc = _label("", 20, ink, font_ui)
	g_perk_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	perk.add_child(g_perk_desc)

	g_price = _label("", 22, amber, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	_place_bottom(g_price, 36, 124, 648, 34)
	column.add_child(g_price)
	g_action = _compact_button("", 86, 27)
	g_action.pressed.connect(_garage_action)
	_place_bottom(g_action, 36, 29, 308, 86)
	column.add_child(g_action)
	g_race = _compact_button("ПОЕХАЛИ", 86, 30, true)
	g_race.pressed.connect(_garage_race)
	_place_bottom(g_race, 360, 29, 324, 86)
	column.add_child(g_race)


func _select_garage_slot(index: int) -> void:
	garage_index = index
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


func _garage_race() -> void:
	if not owned.has(garage_index):
		return
	if selected != garage_index:
		selected = garage_index
		_save()
	_start_solo_game()


func _update_garage() -> void:
	if g_stage == null:
		return
	var car := Cars.get_car(garage_index)
	g_stage.car = car
	g_name.text = str(car.name)
	g_sub.text = str(car.sub)
	g_perk_title.text = str(car.perk_name)
	g_perk_desc.text = str(car.perk_desc)
	var top_kmh := Game.top_kmh(float(car.top))
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
	g_race.disabled = not is_owned
	for i in range(g_slots.size()):
		var tint := Color("#273441") if i == garage_index else Color("#141b21")
		var style := _btn_sb(tint, false)
		style.set_border_width_all(1)
		style.border_color = Color(str(Cars.get_car(i).color)).lightened(0.22) if i == garage_index else Color("#2d3840")
		g_slots[i].add_theme_stylebox_override("normal", style)
		g_slots[i].add_theme_color_override("font_color", ink if owned.has(i) or i == garage_index else dim_col)
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
		if coins >= price:
			g_action.text = "КУПИТЬ"
			g_action.disabled = false
		else:
			g_action.text = "НЕ ХВАТАЕТ %s" % _fmt(price - coins)
			g_action.disabled = true


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

	sfx_slider = VolumeSlider.new()
	sfx_slider.label_font = font_bold
	sfx_slider.value = sfx_volume
	sfx_slider.visible = sfx_on
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	vb.add_child(sfx_slider)

	music_switch = ToggleSwitch.new()
	music_switch.label_font = font_bold
	music_switch.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	music_switch.toggled.connect(_on_music_toggled)
	vb.add_child(_setting_row("МУЗЫКА", "Спокойный фон без слов", music_switch))

	music_slider = VolumeSlider.new()
	music_slider.label_font = font_bold
	music_slider.value = music_volume
	music_slider.visible = music_on
	music_slider.value_changed.connect(_on_music_volume_changed)
	vb.add_child(music_slider)

	vb.add_child(_divider())
	vb.add_child(_label("УПРАВЛЕНИЕ", 17, accent, font_bold))

	var modes := HBoxContainer.new()
	modes.add_theme_constant_override("separation", 8)
	ctrl_zones = _mode_button("ДВЕ ЗОНЫ")
	ctrl_zones.pressed.connect(func(): _set_control_mode("zones"))
	modes.add_child(ctrl_zones)

	ctrl_buttons = _mode_button("КНОПКИ")
	ctrl_buttons.pressed.connect(func(): _set_control_mode("buttons"))
	modes.add_child(ctrl_buttons)

	ctrl_swipe = _mode_button("СВАЙПЫ")
	ctrl_swipe.pressed.connect(func(): _set_control_mode("swipe"))
	modes.add_child(ctrl_swipe)
	vb.add_child(modes)

	ctrl_desc = _label("", 16, Color(0.68, 0.72, 0.75), font_ui)
	ctrl_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ctrl_desc.custom_minimum_size = Vector2(0, 48)
	vb.add_child(ctrl_desc)

	vb.add_child(_divider())
	vb.add_child(_label("ГРАФИКА", 17, accent, font_bold))

	var fps := HBoxContainer.new()
	fps.add_theme_constant_override("separation", 8)
	ctrl_fps_30 = _mode_button("30")
	ctrl_fps_30.pressed.connect(func(): _set_fps(30))
	fps.add_child(ctrl_fps_30)
	ctrl_fps_60 = _mode_button("60")
	ctrl_fps_60.pressed.connect(func(): _set_fps(60))
	fps.add_child(ctrl_fps_60)
	ctrl_fps_120 = _mode_button("120")
	ctrl_fps_120.pressed.connect(func(): _set_fps(120))
	fps.add_child(ctrl_fps_120)
	vb.add_child(fps)

	fps_desc = _label("", 16, Color(0.68, 0.72, 0.75), font_ui)
	fps_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	fps_desc.custom_minimum_size = Vector2(0, 48)
	vb.add_child(fps_desc)

	var cars_row := HBoxContainer.new()
	cars_row.add_theme_constant_override("separation", 8)
	cars_row.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	ctrl_cars_2d = _mode_button("2D")
	ctrl_cars_2d.size_flags_horizontal = Control.SIZE_SHRINK_END
	ctrl_cars_2d.custom_minimum_size = Vector2(92, 58)
	ctrl_cars_2d.add_theme_font_size_override("font_size", 21)
	ctrl_cars_2d.pressed.connect(func(): _set_cars_3d(false))
	cars_row.add_child(ctrl_cars_2d)
	ctrl_cars_3d = _mode_button("3D")
	ctrl_cars_3d.size_flags_horizontal = Control.SIZE_SHRINK_END
	ctrl_cars_3d.custom_minimum_size = Vector2(92, 58)
	ctrl_cars_3d.add_theme_font_size_override("font_size", 21)
	ctrl_cars_3d.pressed.connect(func(): _set_cars_3d(true))
	cars_row.add_child(ctrl_cars_3d)
	vb.add_child(_setting_row("МАШИНЫ", "В дуэлях с друзьями всегда используется 3D", cars_row))
	_build_gfx_settings(vb)

	vb.add_child(_divider())

	var replay_tut := _text_button("ПОВТОРИТЬ ОБУЧЕНИЕ")
	replay_tut.add_theme_color_override("font_color", amber)
	replay_tut.add_theme_color_override("font_hover_color", Color(1.0, 0.85, 0.40))
	replay_tut.pressed.connect(func():
		tutorial_done = false
		_save()
		_hide_settings()
		start_game(true)
	)
	vb.add_child(replay_tut)

	var reset := _text_button("СБРОСИТЬ ПРОГРЕСС")
	reset.add_theme_color_override("font_color", Color(0.86, 0.38, 0.32))
	reset.add_theme_color_override("font_hover_color", Color(1.0, 0.55, 0.46))
	reset.pressed.connect(_show_confirm)
	vb.add_child(reset)


func _setting_row(title: String, sub: String, ctrl: Control) -> Control:
	var root := Control.new()
	root.custom_minimum_size = Vector2(0, 68)
	root.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var row := HBoxContainer.new()
	row.set_anchors_preset(Control.PRESET_FULL_RECT)
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
	root.add_child(row)

	if ctrl is ToggleSwitch:
		var btn := Button.new()
		btn.flat = true
		btn.set_anchors_preset(Control.PRESET_FULL_RECT)
		btn.offset_right = -124
		btn.focus_mode = Control.FOCUS_NONE
		btn.pressed.connect(func():
			ctrl._toggle()
		)
		root.add_child(btn)

	return root


func _divider() -> ColorRect:
	var c := ColorRect.new()
	c.color = Color(1, 1, 1, 0.08)
	c.custom_minimum_size = Vector2(0, 2)
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return c


func _mode_button(txt: String) -> Button:
	var b := _button(txt, false)
	b.custom_minimum_size = Vector2(0, 66)
	b.add_theme_font_size_override("font_size", 22)
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
	if sfx_slider != null:
		sfx_slider.visible = sfx_on
		sfx_slider.set_value_no_signal(sfx_volume)
	if music_switch != null:
		music_switch.set_on(music_on)
	if music_slider != null:
		music_slider.visible = music_on
		music_slider.set_value_no_signal(music_volume)
	_style_mode_btn(ctrl_zones, control_mode == "zones")
	_style_mode_btn(ctrl_buttons, control_mode == "buttons")
	_style_mode_btn(ctrl_swipe, control_mode == "swipe")
	if ctrl_fps_30 != null:
		_style_mode_btn(ctrl_fps_30, fps_limit == 30)
		_style_mode_btn(ctrl_fps_60, fps_limit == 60)
		_style_mode_btn(ctrl_fps_120, fps_limit == 120)
	if ctrl_cars_2d != null:
		_style_mode_btn(ctrl_cars_2d, not cars_3d)
		_style_mode_btn(ctrl_cars_3d, cars_3d)
	_update_gfx_settings_ui()
	if fps_desc != null:
		match fps_limit:
			30:
				fps_desc.text = "Экономит батарею, картинка менее плавная."
			60:
				fps_desc.text = "Баланс плавности и заряда батареи."
			120:
				fps_desc.text = "Максимальная плавность на экранах 120 Гц."
	if ctrl_desc != null:
		match control_mode:
			"zones":
				ctrl_desc.text = "Левая/правая половина — руль. Обе вместе — тормоз. Отдельная кнопка — нитро."
			"buttons":
				ctrl_desc.text = "Крупные кнопки: стрелки для поворотов, педаль тормоза и кнопка нитро."
			"swipe":
				ctrl_desc.text = "Свайп влево/вправо — руль, свайп вниз — тормоз, свайп вверх — нитро."


func _on_sfx_toggled(v: bool) -> void:
	sfx_on = v
	if sfx_slider != null:
		sfx_slider.visible = v
	Sfx.set_sfx_enabled(v)
	_save()
	if v:
		Sfx.click()


func _on_music_toggled(v: bool) -> void:
	music_on = v
	if music_slider != null:
		music_slider.visible = v
	Sfx.set_music_enabled(v)
	_save()


func _on_sfx_volume_changed(val: float) -> void:
	sfx_volume = val
	Sfx.set_sfx_volume(val)
	_save()


func _on_music_volume_changed(val: float) -> void:
	music_volume = val
	Sfx.set_music_volume(val)
	_save()


func _set_control_mode(mode: String) -> void:
	if control_mode == mode:
		return
	Sfx.click()
	control_mode = mode
	_apply_control_ui()
	_save()
	_update_settings_ui()


func _set_fps(limit: int) -> void:
	if fps_limit == limit:
		return
	Sfx.click()
	fps_limit = limit
	Engine.max_fps = limit
	if game != null:
		game.set_graphics(_gfx_effective_level(), fps_limit)
	_save()
	_update_settings_ui()


func _set_cars_3d(on: bool) -> void:
	if cars_3d == on:
		return
	Sfx.click()
	cars_3d = on
	if game != null:
		game.use_3d_cars = on
		game.queue_redraw()
	_save()
	_update_settings_ui()


# --- graphics quality (0.8.0) -----------------------------------------------

func _gfx_effective_level() -> int:
	if gfx_choice != GfxPresets.AUTO:
		return gfx_choice
	return gfx_auto_level if gfx_auto_level >= 0 else GfxPresets.MEDIUM


var gfx_benchmarking := false


func _gfx_maybe_benchmark() -> void:
	if gfx_choice != GfxPresets.AUTO or gfx_auto_level >= 0:
		return
	_gfx_run_benchmark(1.5)


# Runs the Auto test on the demo behind the menu/settings. The start is
# delayed past the launch/loading spike; re-run any time by tapping Авто.
func _gfx_run_benchmark(delay := 0.0) -> void:
	if gfx_benchmarking or DisplayServer.get_name() == "headless":
		return
	gfx_benchmarking = true
	_update_gfx_settings_ui()
	if delay > 0.0:
		await get_tree().create_timer(delay).timeout
	if in_game or game == null:
		# A race started meanwhile: test again on the next menu visit.
		gfx_benchmarking = false
		return
	var bench := GfxBenchmark.new()
	bench.name = "GfxBenchmark"
	add_child(bench)
	bench.finished.connect(func(level: int, _ms: float) -> void:
		gfx_benchmarking = false
		gfx_auto_level = level
		if gfx_choice == GfxPresets.AUTO and game != null:
			game.set_graphics(level, fps_limit)
		_save()
		_update_gfx_settings_ui())
	bench.start(game)


func _build_gfx_settings(vb: VBoxContainer) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	gfx_buttons.clear()
	for lv in [GfxPresets.AUTO, GfxPresets.LOW, GfxPresets.MEDIUM, GfxPresets.HIGH, GfxPresets.ULTRA]:
		var b := _mode_button(GfxPresets.level_name(lv))
		b.add_theme_font_size_override("font_size", 17)
		b.pressed.connect(_set_gfx.bind(lv))
		row.add_child(b)
		gfx_buttons.append(b)
	vb.add_child(row)
	gfx_desc = _label("", 16, Color(0.68, 0.72, 0.75), font_ui)
	gfx_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	gfx_desc.custom_minimum_size = Vector2(0, 48)
	vb.add_child(gfx_desc)


func _set_gfx(level: int) -> void:
	if level == GfxPresets.AUTO:
		# Tapping Авто (again) re-runs the device test.
		Sfx.click()
		gfx_choice = GfxPresets.AUTO
		_save()
		_update_settings_ui()
		_gfx_run_benchmark(0.3)
		return
	if gfx_choice == level:
		return
	Sfx.click()
	gfx_choice = level
	if game != null:
		game.set_graphics(_gfx_effective_level(), fps_limit)
	_save()
	_update_settings_ui()


func _update_gfx_settings_ui() -> void:
	var levels := [GfxPresets.AUTO, GfxPresets.LOW, GfxPresets.MEDIUM, GfxPresets.HIGH, GfxPresets.ULTRA]
	for i in range(gfx_buttons.size()):
		_style_mode_btn(gfx_buttons[i], gfx_choice == levels[i])
	if gfx_desc == null:
		return
	match gfx_choice:
		GfxPresets.AUTO:
			if gfx_benchmarking:
				gfx_desc.text = "Идёт тест устройства…"
			else:
				gfx_desc.text = "Подобрано по тесту устройства: %s. Нажмите «Авто», чтобы проверить снова." % GfxPresets.level_name(_gfx_effective_level()).capitalize()
		GfxPresets.LOW:
			gfx_desc.text = "Без теней и пост-эффектов. Для слабых телефонов."
		GfxPresets.MEDIUM:
			gfx_desc.text = "Свет фар с тенями, свечение, капли на экране."
		GfxPresets.HIGH:
			gfx_desc.text = "Больше теней и частиц, преломление капель."
		GfxPresets.ULTRA:
			gfx_desc.text = "Всё на максимум. Для флагманов."


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
		["РОГАТКА (СЛИПСТРИМ)", "Держись за машиной впереди — шкала зарядится вокруг авто. Резко перестройся, чтобы выстрелить вперёд, получить очки и нитро!"],
		["НИТРО И ХРОНО-ЩИТ", "Одно нажатие тратит заряд. Двойное тратит весь запас и продлевает ускорение. При аварии 3 заряда позволяют перемотать время."],
		["УПРАВЛЕНИЕ И ТОРМОЗ", "Две зоны, кнопки или свайпы (выбор в настройках). Тормоз сбрасывает скорость, но колодки греются. На мокрой дороге и в лужах тормозной путь длиннее, а глубокая лужа на скорости ненадолго уводит машину в аквапланирование."],
		["ДОРОЖНЫЕ РАБОТЫ", "Знак у обочины предупреждает заранее: перестройся. Стрелки и конусы можно сбить — это очки, но машина чуть теряет скорость. Ограждение со знаком STOP — авария."],
		["9 СПОСОБНОСТЕЙ МАШИН", "У каждой машины в гараже своя фишка: таран на нитро, магнит монет, 4-й баллон, рекуперация тормоза и гипердрайв."],
		["ВЫЗОВ ДРУГА И ВЫЗОВ ДНЯ", "Скопируй код после финиша и отправь другу в мессенджер — он сможет проехать с твоим живым призраком по той же трассе!"],
	]
	for it in items:
		vb.add_child(_label(it[0], 19, accent, font_bold))
		var body := _label(it[1], 22, Color(0.86, 0.88, 0.89), font_ui)
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.custom_minimum_size = Vector2(0, 52)
		vb.add_child(body)

	var gap2 := Control.new()
	gap2.custom_minimum_size = Vector2(0, 4)
	vb.add_child(gap2)

	var tut_btn := _button("ПРОЙТИ ОБУЧЕНИЕ", false)
	tut_btn.custom_minimum_size = Vector2(0, 76)
	tut_btn.pressed.connect(func():
		_hide_how()
		start_game(true)
	)
	vb.add_child(tut_btn)

	var ok := _button("ПОНЯТНО", true)
	ok.custom_minimum_size = Vector2(0, 84)
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

	result_mode_banner = _label("", 20, Color("#5ddb75"), font_bold, HORIZONTAL_ALIGNMENT_CENTER)
	result_mode_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	result_mode_banner.visible = false
	vb.add_child(result_mode_banner)

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

	result_share_btn = _button("ПОДЕЛИТЬСЯ ВЫЗОВОМ", false)
	result_share_btn.custom_minimum_size = Vector2(0, 78)
	result_share_btn.add_theme_font_size_override("font_size", 26)
	result_share_btn.add_theme_color_override("font_color", Color("#7fe9ff"))
	result_share_btn.pressed.connect(_share_challenge.bind(result_share_btn))
	result_share_btn.visible = false
	vb.add_child(result_share_btn)

	var row2 := HBoxContainer.new()
	row2.add_theme_constant_override("separation", 10)
	vb.add_child(row2)

	result_return_btn = _compact_button("ГАРАЖ", 88, 28)
	result_return_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_return_btn.pressed.connect(_return_from_result)
	row2.add_child(result_return_btn)

	var to_menu := _button("В МЕНЮ", false)
	to_menu.custom_minimum_size = Vector2(0, 88)
	to_menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	to_menu.add_theme_font_size_override("font_size", 28)
	to_menu.pressed.connect(show_menu)
	row2.add_child(to_menu)


# --- challenges (daily & friend ghost duel) ---------------------------------

const DUEL_CYAN := Color("#8cdef2")
const MEDAL_NAMES := ["БРОНЗА", "СЕРЕБРО", "ЗОЛОТО"]
const MEDAL_COLORS := [Color("#e2a372"), Color("#c1d1e1"), Color("#fac761")]


func _return_from_result() -> void:
	var mode := str(active_challenge.get("type", ""))
	if mode.is_empty():
		show_garage()
	else:
		show_challenges()
		_select_challenge_tab(1 if mode == "duel" else 0)


func _sync_daily_date(date_key := "") -> void:
	if date_key.is_empty():
		date_key = str(ChallengeCodec.daily_challenge().date_key)
	if daily_date == date_key:
		return
	if not daily_date.is_empty():
		daily_history[daily_date] = [daily_best, daily_tier]
	daily_date = date_key
	var saved = daily_history.get(date_key, [])
	daily_best = int(saved[0]) if saved is Array and saved.size() == 2 else 0
	daily_tier = clampi(int(saved[1]), 0, 3) if saved is Array and saved.size() == 2 else 0
	# Retain recent days so retries and time-zone changes cannot pay twice.
	var dates := daily_history.keys()
	dates.sort()
	while dates.size() > 14:
		daily_history.erase(dates.pop_front())


func _line_edit_style(focused := false) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color("#0d151d")
	sb.set_corner_radius_all(12)
	sb.set_border_width_all(1)
	sb.border_color = DUEL_CYAN if focused else Color("#3a4b58")
	sb.content_margin_left = 16
	sb.content_margin_right = 16
	sb.content_margin_top = 8
	sb.content_margin_bottom = 8
	return sb


func _challenge_input(placeholder: String, maximum: int) -> LineEdit:
	var field := LineEdit.new()
	field.placeholder_text = placeholder
	field.max_length = maximum
	field.custom_minimum_size.y = 60
	field.add_theme_font_override("font", font_ui)
	field.add_theme_font_size_override("font_size", 23)
	field.add_theme_stylebox_override("normal", _line_edit_style())
	field.add_theme_stylebox_override("focus", _line_edit_style(true))
	return field


func _build_challenges() -> void:
	challenges_panel = Control.new()
	_full(challenges_panel)
	challenges_panel.visible = false
	challenges_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	ui.add_child(challenges_panel)
	challenges_panel.add_child(_screen_bg())
	var column := _portrait_column(challenges_panel)

	var back := IconButton.new()
	back.kind = "back"
	back.pressed.connect(show_menu)
	_place(back, 34, 32, 76, 76)
	column.add_child(back)
	var title := _label("ВЫЗОВЫ", 40, ink, font_bold)
	_place(title, 126, 32, 380, 76)
	column.add_child(title)

	var tab_bar := HBoxContainer.new()
	tab_bar.add_theme_constant_override("separation", 10)
	_place(tab_bar, 36, 122, 648, 68)
	column.add_child(tab_bar)
	var tab_group := ButtonGroup.new()
	for index in range(2):
		var tab := _compact_button(["ВЫЗОВ ДНЯ", "ДУЭЛИ С ДРУЗЬЯМИ"][index], 68, 24)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.toggle_mode = true
		tab.button_group = tab_group
		var tab_selected := _btn_sb(Color("#294052"), false)
		tab_selected.border_color = Color("#638297")
		tab.add_theme_stylebox_override("pressed", tab_selected)
		tab.pressed.connect(_select_challenge_tab.bind(index))
		tab_bar.add_child(tab)
		ch_tabs.append(tab)

		var page := _screen_scroll(column, 210.0, 30.0)
		page.follow_focus = true
		page.visible = false
		ch_pages.append(page)
		var content := VBoxContainer.new()
		content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_theme_constant_override("separation", 16)
		page.add_child(content)
		if index == 0:
			_build_daily_page(content)
		else:
			_build_duel_page(content)
	_select_challenge_tab(0)


func _select_challenge_tab(index: int) -> void:
	for i in range(ch_pages.size()):
		ch_tabs[i].set_pressed_no_signal(i == index)
		ch_pages[i].visible = i == index
	if index == 0:
		_refresh_daily_ui()


func _challenge_section(parent: VBoxContainer, tint: Color) -> VBoxContainer:
	var card := _accent_card(tint)
	parent.add_child(card)
	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 12)
	card.add_child(content)
	return content


func _build_daily_page(content: VBoxContainer) -> void:
	var daily := _challenge_section(content, amber)
	daily.add_child(_label("ТРАССА ДНЯ", 25, amber, font_bold))
	ch_daily_info = _label("", 28, ink, font_bold)
	ch_daily_info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	daily.add_child(ch_daily_info)
	ch_daily_status = _label("", 22, dim_col, font_bold)
	daily.add_child(ch_daily_status)
	ch_daily_progress = _stat_bar(daily)
	var play := _compact_button("НА СТАРТ", 78, 31, true)
	play.pressed.connect(_start_daily_challenge)
	daily.add_child(play)

	var reward_card := _challenge_section(content, amber)
	reward_card.add_child(_label("МЕДАЛИ И НАГРАДЫ", 25, ink, font_bold))
	var medals := HBoxContainer.new()
	medals.add_theme_constant_override("separation", 8)
	reward_card.add_child(medals)
	for i in range(3):
		var cell := _accent_card(MEDAL_COLORS[i])
		var style := cell.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
		style.content_margin_left = 8
		style.content_margin_right = 8
		cell.add_theme_stylebox_override("panel", style)
		cell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		medals.add_child(cell)
		var stack := VBoxContainer.new()
		stack.add_theme_constant_override("separation", 4)
		cell.add_child(stack)
		stack.add_child(_label(MEDAL_NAMES[i], 21, MEDAL_COLORS[i], font_bold, HORIZONTAL_ALIGNMENT_CENTER))
		var target := _label("", 25, ink, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		stack.add_child(target)
		ch_daily_medals.append(target)
		var reward := _label("", 18, dim_col, font_bold, HORIZONTAL_ALIGNMENT_CENTER)
		stack.add_child(reward)
		ch_daily_rewards.append(reward)


func _build_duel_page(content: VBoxContainer) -> void:
	var incoming := _challenge_section(content, DUEL_CYAN)
	incoming.add_child(_label("ВЫЗОВ ОТ ДРУГА", 25, DUEL_CYAN, font_bold))
	var open_file := _compact_button("ОТКРЫТЬ ФАЙЛ ЗАЕЗДА", 64, 23)
	open_file.pressed.connect(_open_challenge_file)
	incoming.add_child(open_file)
	ch_code_input = _challenge_input("Код или сообщение от друга", ChallengeCodec.MAX_INPUT_LENGTH)
	if not incoming_challenge_code.is_empty():
		ch_code_input.text = ChallengeFiles.short_code(incoming_challenge_code)
	ch_code_input.text_changed.connect(_on_challenge_code_edited)
	ch_code_input.text_submitted.connect(func(_value: String): ch_code_input.release_focus())
	incoming.add_child(ch_code_input)

	var code_actions := HBoxContainer.new()
	code_actions.add_theme_constant_override("separation", 8)
	incoming.add_child(code_actions)
	var paste := _compact_button("ВСТАВИТЬ ИЗ БУФЕРА", 60, 22)
	paste.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paste.pressed.connect(_paste_challenge_from_clipboard)
	code_actions.add_child(paste)
	var clear := _compact_button("ОЧИСТИТЬ", 60, 22)
	clear.custom_minimum_size.x = 160
	clear.pressed.connect(func():
		ch_code_input.clear()
		_on_challenge_code_edited(""))
	code_actions.add_child(clear)

	ch_duel_details = VBoxContainer.new()
	ch_duel_details.add_theme_constant_override("separation", 2)
	incoming.add_child(ch_duel_details)
	ch_duel_name = _label("", 28, ink, font_bold)
	ch_duel_name.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ch_duel_details.add_child(ch_duel_name)
	ch_duel_target = _label("", 22, DUEL_CYAN, font_bold)
	ch_duel_details.add_child(ch_duel_target)
	ch_duel_preview = _label("", 21, dim_col, font_ui)
	ch_duel_preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	incoming.add_child(ch_duel_preview)

	ch_accept_btn = _compact_button("ПРИНЯТЬ ВЫЗОВ", 78, 27, true)
	ch_accept_btn.pressed.connect(_start_duel_challenge)
	incoming.add_child(ch_accept_btn)

	var outgoing := _challenge_section(content, amber)
	outgoing.add_child(_label("МОЙ ВЫЗОВ", 25, amber, font_bold))
	ch_outgoing_label = _label("", 22, ink, font_ui)
	ch_outgoing_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	outgoing.add_child(ch_outgoing_label)
	ch_share_btn = _compact_button("ПОДЕЛИТЬСЯ ВЫЗОВОМ", 68, 23)
	ch_share_btn.pressed.connect(_share_challenge.bind(ch_share_btn))
	outgoing.add_child(ch_share_btn)
	ch_copy_row = HBoxContainer.new()
	ch_copy_row.add_theme_constant_override("separation", 8)
	outgoing.add_child(ch_copy_row)
	ch_copy_invite_btn = _compact_button("ТЕКСТ ПРИГЛАШЕНИЯ", 52, 20)
	ch_copy_invite_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch_copy_invite_btn.pressed.connect(_copy_challenge_text.bind(ch_copy_invite_btn, true))
	ch_copy_row.add_child(ch_copy_invite_btn)
	ch_copy_full_btn = _compact_button("ПОЛНЫЙ КОД", 52, 20)
	ch_copy_full_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch_copy_full_btn.pressed.connect(_copy_challenge_text.bind(ch_copy_full_btn, false))
	ch_copy_row.add_child(ch_copy_full_btn)

	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 16)
	outgoing.add_child(name_row)
	name_row.add_child(_label("ИМЯ В ВЫЗОВЕ", 21, dim_col, font_bold))
	ch_name_input = _challenge_input("ГОНЩИК", 12)
	ch_name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ch_name_input.text = player_name
	ch_name_input.focus_exited.connect(_commit_challenge_name)
	ch_name_input.text_submitted.connect(func(_value: String): ch_name_input.release_focus())
	name_row.add_child(ch_name_input)

	var make := _compact_button("НОВЫЙ ЗАЕЗД", 68, 23)
	make.pressed.connect(_start_solo_game)
	outgoing.add_child(make)


func show_challenges() -> void:
	show_menu()
	_hide_screens()
	Sfx.click()
	challenges_panel.visible = true
	_refresh_challenges_ui()


func _refresh_daily_ui() -> void:
	var d := ChallengeCodec.daily_challenge()
	_sync_daily_date(str(d.date_key))
	var car := Cars.get_car(int(d.car_index))
	ch_daily_info.text = "%s · %s, %s\n%s · Машина выдана на заезд" % [
		str(car.name), str(d.time_label).to_lower(), str(d.weather_label).to_lower(), str(d.date_key),
	]
	var targets := [int(d.bronze), int(d.silver), int(d.gold)]
	var next := targets.find_custom(func(target: int) -> bool: return daily_best < target)
	var progress_text := "ВСЕ МЕДАЛИ ВЗЯТЫ"
	ch_daily_progress.value = 1.0
	if next >= 0:
		var previous := int(targets[next - 1]) if next > 0 else 0
		ch_daily_progress.value = inverse_lerp(float(previous), float(targets[next]), float(daily_best))
		progress_text = "ДО МЕДАЛИ %s" % _fmt(int(targets[next]) - daily_best)
	ch_daily_status.text = "РЕКОРД %s  ·  %s" % [_fmt(daily_best), progress_text]
	for i in range(targets.size()):
		ch_daily_medals[i].text = _fmt(targets[i])
		var claimed := daily_tier > i
		ch_daily_rewards[i].text = "ПОЛУЧЕНО" if claimed else "+%d МОНЕТ" % ChallengeCodec.DAILY_REWARDS[i]
		ch_daily_rewards[i].add_theme_color_override("font_color", MEDAL_COLORS[i] if claimed else dim_col)


func _refresh_challenges_ui() -> void:
	_refresh_daily_ui()
	if loaded_duel.is_empty():
		_on_challenge_code_edited(ch_code_input.text)
	else:
		_update_duel_preview(loaded_duel)
	var outgoing := ChallengeCodec.decode(last_challenge_code)
	ch_share_btn.visible = bool(outgoing.get("ok", false))
	ch_copy_row.visible = ch_share_btn.visible
	ch_share_btn.text = "ПОДЕЛИТЬСЯ ВЫЗОВОМ" if _native_challenges != null else "СОХРАНИТЬ ФАЙЛ ВЫЗОВА"
	ch_copy_invite_btn.text = "ТЕКСТ ПРИГЛАШЕНИЯ"
	ch_copy_full_btn.text = "ПОЛНЫЙ КОД"
	if ch_share_btn.visible:
		var car := Cars.get_car(int(outgoing.car_index))
		ch_outgoing_label.text = "%s · %s ОЧК. · %s М" % [str(car.name), _fmt(int(outgoing.score)), _fmt(int(outgoing.distance))]
	else:
		ch_outgoing_label.text = "Заверши заезд, чтобы поделиться своим результатом с другом."


func _commit_challenge_name() -> void:
	var updated := ChallengeCodec.sanitize_name(ch_name_input.text)
	ch_name_input.text = updated
	if player_name != updated:
		player_name = updated
		_save()


func _paste_challenge_from_clipboard() -> void:
	var clip := DisplayServer.clipboard_get()
	if clip.strip_edges().is_empty():
		ch_duel_preview.text = "Буфер обмена пуст."
		return
	var code := ChallengeCodec.extract_code(clip)
	if code.is_empty():
		code = ChallengeFiles.extract_code(clip.left(ChallengeCodec.MAX_INPUT_LENGTH))
	ch_code_input.text = code if not code.is_empty() else clip.strip_edges().left(ChallengeCodec.MAX_INPUT_LENGTH)
	_on_challenge_code_edited(ch_code_input.text)
	ch_code_input.release_focus()


func _on_challenge_code_edited(txt: String) -> void:
	_pending_invite_code = ""
	if txt.strip_edges().is_empty():
		_store_incoming({})
		return
	var code := ChallengeFiles.extract_code(txt)
	if not code.is_empty() and ChallengeCodec.extract_code(txt).is_empty():
		if not incoming_challenge_code.is_empty() and code == ChallengeFiles.short_code(incoming_challenge_code):
			_store_incoming(ChallengeCodec.decode(incoming_challenge_code))
			return
		_pending_invite_code = code
		loaded_duel = {}
		_update_duel_preview({}, "Открой вложение %s, чтобы загрузить призрака." % ChallengeFiles.filename(code))
		return
	var parsed := ChallengeCodec.decode(txt)
	if bool(parsed.get("ok", false)):
		_store_incoming(parsed)
	else:
		loaded_duel = {}
		_update_duel_preview(parsed)


func _store_incoming(parsed: Dictionary) -> void:
	loaded_duel = parsed
	_pending_invite_code = ""
	var replay := str(parsed.get("code", ""))
	if incoming_challenge_code != replay:
		incoming_challenge_code = replay
		_save()
	ch_code_input.text = ChallengeFiles.short_code(replay) if not replay.is_empty() else ""
	_update_duel_preview(parsed)


func _import_challenge_file(path: String) -> void:
	var parsed := ChallengeFiles.read(path)
	if not bool(parsed.get("ok", false)):
		ch_duel_preview.text = str(parsed.error)
		ch_duel_preview.add_theme_color_override("font_color", Color("#ff9985"))
		return
	var actual := ChallengeFiles.short_code(str(parsed.code))
	if not _pending_invite_code.is_empty() and actual != _pending_invite_code:
		_update_duel_preview({"error": "В файле вызов %s, а в поле указан %s." % [actual, _pending_invite_code]})
		return
	_store_incoming(parsed)


func _challenge_file_dialog(mode: FileDialog.FileMode, filename: String, on_selected: Callable) -> void:
	var dialog := FileDialog.new()
	dialog.access = FileDialog.ACCESS_FILESYSTEM
	dialog.use_native_dialog = true
	dialog.file_mode = mode
	dialog.title = "Открыть заезд" if mode == FileDialog.FILE_MODE_OPEN_FILE else "Сохранить заезд"
	dialog.filters = ["*.slipstream;Заезд SLIPSTREAM;application/octet-stream"]
	if not filename.is_empty():
		dialog.current_file = filename
	dialog.file_selected.connect(func(path: String):
		dialog.queue_free()
		on_selected.call(path))
	dialog.canceled.connect(dialog.queue_free)
	add_child(dialog)
	dialog.popup_centered_ratio(0.85)


func _open_challenge_file() -> void:
	_challenge_file_dialog(FileDialog.FILE_MODE_OPEN_FILE, "", _import_challenge_file)


func _update_duel_preview(parsed: Dictionary, notice := "") -> void:
	var valid := bool(parsed.get("ok", false))
	ch_duel_details.visible = valid
	ch_accept_btn.disabled = not valid
	if not valid:
		ch_accept_btn.text = "ПРИНЯТЬ ВЫЗОВ"
		ch_duel_preview.text = notice if not notice.is_empty() else str(parsed.get("error", "Открой файл из сообщения друга или вставь полный код SLIP…"))
		ch_duel_preview.add_theme_color_override("font_color", dim_col if parsed.is_empty() else Color("#ff9985"))
		return
	var car := Cars.get_car(int(parsed.car_index))
	var beaten := beaten_duels.has(str(parsed.id))
	ch_duel_name.text = "%s   /   %s" % [str(parsed.name), str(car.name)]
	ch_duel_target.text = "Цель · %s очк.   /   Заезд · %s м" % [_fmt(int(parsed.score) + 1), _fmt(int(parsed.distance))]
	ch_duel_preview.text = "%s, %s · %s" % [
		ChallengeCodec.time_label(float(parsed.tod)).capitalize(),
		ChallengeCodec.weather_label(int(parsed.weather)).to_lower(),
		"Реванш доступен" if beaten else "%d монет за первую победу" % ChallengeCodec.DUEL_WIN_REWARD,
	]
	ch_duel_preview.add_theme_color_override("font_color", dim_col)
	ch_accept_btn.text = "НА РЕВАНШ" if beaten else "ПРИНЯТЬ ВЫЗОВ"


func _start_daily_challenge() -> void:
	active_challenge = ChallengeCodec.daily_challenge()
	start_game(false)


func _start_duel_challenge() -> void:
	if loaded_duel.is_empty():
		return
	_commit_challenge_name()
	active_challenge = loaded_duel.duplicate(true)
	start_game(false)


func _share_challenge(button: Button, allow_native := true) -> void:
	var replay := last_challenge_code
	var payload := ChallengeCodec.decode(replay)
	if not bool(payload.get("ok", false)):
		return
	var code := ChallengeFiles.short_code(replay)
	var filename := ChallengeFiles.filename(code)
	var invitation := ChallengeCodec.format_share_message(payload, code, last_share_is_rematch)
	if allow_native and _native_challenges != null:
		if bool(_native_challenges.call("shareReplay", filename, ChallengeFiles.contents(replay), invitation)):
			return
	_challenge_file_dialog(FileDialog.FILE_MODE_SAVE_FILE, filename, func(path: String):
		if ChallengeFiles.write(path, replay) != OK:
			button.text = "ФАЙЛ НЕ СОХРАНЁН · ПОВТОРИТЬ"
			return
		DisplayServer.clipboard_set(invitation)
		button.text = "ФАЙЛ СОХРАНЁН · " + code
		Sfx.record())


func _on_replay_share_failed() -> void:
	_share_challenge(result_share_btn if result_open else ch_share_btn, false)


func _copy_challenge_text(button: Button, short := false) -> void:
	var payload := ChallengeCodec.decode(last_challenge_code)
	if not bool(payload.get("ok", false)):
		return
	var code := ChallengeFiles.short_code(last_challenge_code) if short else last_challenge_code
	DisplayServer.clipboard_set(ChallengeCodec.format_share_message(payload, code, last_share_is_rematch))
	button.text = "ТЕКСТ СКОПИРОВАН" if short else "КОД СКОПИРОВАН"
	Sfx.record()


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
	confirm_text = _label("", 21, Color(0.70, 0.74, 0.76), font_ui, HORIZONTAL_ALIGNMENT_CENTER)
	confirm_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	confirm_text.custom_minimum_size = Vector2(0, 64)
	vb.add_child(confirm_text)

	var yes := _button("СБРОСИТЬ", true)
	yes.pressed.connect(_do_reset)
	vb.add_child(yes)

	var no := _button("ОТМЕНА", false)
	no.custom_minimum_size = Vector2(0, 90)
	no.pressed.connect(_hide_confirm)
	vb.add_child(no)


func _show_confirm() -> void:
	Sfx.click()
	confirm_text.text = "Монеты, купленные машины и рекорд будут удалены. Настройки останутся."
	if in_game:
		confirm_text.text += " Текущий заезд завершится, и игра вернётся в меню."
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
	tutorial_done = false
	daily_best = 0
	daily_tier = 0
	daily_history.clear()
	beaten_duels.clear()
	incoming_challenge_code = ""
	last_challenge_code = ""
	last_share_is_rematch = false
	_last_run_shareable = false
	_pending_invite_code = ""
	loaded_duel = {}
	if ch_code_input != null:
		ch_code_input.clear()
	active_challenge = {}
	_save()
	confirm_panel.visible = false
	Sfx.click()
	game.car_index = selected
	if in_game:
		settings_from_pause = false
		show_menu()
		return
	game.start_demo()
	_update_all_labels()


# --- exit confirmation ------------------------------------------------------

func _build_exit_panel() -> void:
	exit_panel = Control.new()
	_full(exit_panel)
	exit_panel.visible = false
	exit_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	exit_panel.z_index = 100
	ui.add_child(exit_panel)

	var dim := ColorRect.new()
	dim.color = Color(0.01, 0.015, 0.02, 0.88)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(dim)
	exit_panel.add_child(dim)

	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_full(center)
	exit_panel.add_child(center)

	var card := _card(560)
	center.add_child(card)

	var vb := VBoxContainer.new()
	vb.add_theme_constant_override("separation", 16)
	card.add_child(vb)

	vb.add_child(_label("ВЫХОД", 38, ink, font_num, HORIZONTAL_ALIGNMENT_CENTER))

	var sub := _label(
		"Вы действительно хотите выйти из игры?",
		22, Color(0.82, 0.85, 0.87), font_ui, HORIZONTAL_ALIGNMENT_CENTER
	)
	sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vb.add_child(sub)

	var gap := Control.new()
	gap.custom_minimum_size = Vector2(0, 8)
	vb.add_child(gap)

	var quit_btn := _button("ВЫЙТИ", true)
	quit_btn.custom_minimum_size = Vector2(0, 88)
	quit_btn.pressed.connect(func():
		get_tree().quit()
	)
	vb.add_child(quit_btn)

	var cancel_btn := _button("ОТМЕНА", false)
	cancel_btn.custom_minimum_size = Vector2(0, 88)
	cancel_btn.pressed.connect(_hide_exit_panel)
	vb.add_child(cancel_btn)


func _show_exit_panel() -> void:
	Sfx.click()
	if exit_panel != null:
		exit_panel.visible = true
		if exit_panel.get_parent() != null:
			exit_panel.get_parent().move_child(exit_panel, -1)


func _hide_exit_panel() -> void:
	Sfx.click()
	if exit_panel != null:
		exit_panel.visible = false


# --- tutorial ---------------------------------------------------------------

func _build_tutorial() -> void:
	tutorial_panel = Control.new()
	_place(tutorial_panel, 36, 216, 648, 170)
	tutorial_panel.visible = false
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(tutorial_panel)

	var card := _card(648)
	card.set_anchors_preset(Control.PRESET_FULL_RECT)
	card.offset_left = 0
	card.offset_top = 0
	card.offset_right = 0
	card.offset_bottom = 0
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_panel.add_child(card)

	var vb := VBoxContainer.new()
	vb.set_anchors_preset(Control.PRESET_FULL_RECT)
	vb.offset_left = 22
	vb.offset_top = 16
	vb.offset_right = -22
	vb.offset_bottom = -16
	vb.add_theme_constant_override("separation", 6)
	vb.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(vb)

	var top_row := HBoxContainer.new()
	top_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tutorial_title = _label("ОБУЧЕНИЕ", 24, amber, font_bold)
	tutorial_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top_row.add_child(tutorial_title)

	var skip_btn := _text_button("ПРОПУСТИТЬ")
	skip_btn.add_theme_font_size_override("font_size", 18)
	skip_btn.pressed.connect(_skip_tutorial)
	top_row.add_child(skip_btn)
	vb.add_child(top_row)

	tutorial_text = _label("", 21, ink, font_ui)
	tutorial_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tutorial_text.custom_minimum_size = Vector2(0, 56)
	vb.add_child(tutorial_text)


# --- misc -------------------------------------------------------------------

func _update_all_labels() -> void:
	if menu_coins != null:
		menu_coins.text = _fmt(coins)
	if menu_best != null:
		menu_best.text = "РЕКОРД  " + _fmt(best)
	if menu_car != null:
		var car := Cars.get_car(selected)
		menu_car.text = "ВАША МАШИНА · %s · %d КМ/Ч" % [str(car.name), Game.top_kmh(float(car.top))]
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
	if n < 0:
		out = "-" + out
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
	_select_garage_slot(1)
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

	tutorial_done = true
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

	control_mode = "buttons"
	start_game()
	await get_tree().create_timer(1.2).timeout
	await _shot("game_buttons")
	await get_tree().create_timer(0.25).timeout

	# The original painted cars, kept as the 2D option in Settings.
	_set_cars_3d(false)
	start_game()
	await get_tree().create_timer(1.2).timeout
	await _shot("game_2d")
	_set_cars_3d(true)
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


# Traffic contact sheet: one of every silhouette on the real road, day and
# night, so a change to the car art can be checked at gameplay scale.
func _qa_traffic_car(lane: int, y: float, sil: String, kind: int, col: Color, extra := {}) -> Dictionary:
	var type: Dictionary = Game.TRAFFIC_TYPES[0]
	for tp in Game.TRAFFIC_TYPES:
		if int(tp.kind) == kind:
			type = tp
	var e := {
		"lane": lane,
		"x": game._lane_x(lane),
		"y": y,
		"w": game.car_w * float(type.w),
		"h": game.car_h * float(type.h),
		"kind": kind,
		"color": col,
		"rel": 0.7,
		"cur_speed": 420.0,
		"braking": false,
		"demo_speed": 420.0,
		"near": false,
		"cutin": false,
		"stripe": false,
		"wing": false,
		"rails": false,
		"roof_sign": false,
		"cargo": false,
		"stripe_color": Color(0.94, 0.93, 0.90),
		"silhouette": sil,
	}
	e.merge(extra, true)
	return e


func _qa_traffic_seq(use2d := false) -> void:
	await get_tree().create_timer(1.0).timeout
	in_game = true
	_hide_screens()
	hud.visible = false
	game.start_demo()
	game.use_3d_cars = not use2d
	game.set_process(false)
	game.cars.clear()
	game.cars.append(_qa_traffic_car(0, 300.0, "hatch", 0, Color("#e8e7e3")))
	game.cars.append(_qa_traffic_car(1, 300.0, "sedan", 0, Color("#5e2b2b"), {"stripe": true}))
	game.cars.append(_qa_traffic_car(2, 300.0, "offroad", 1, Color("#3c5c48")))
	game.cars.append(_qa_traffic_car(3, 300.0, "sport", 5, Color("#d1a12c"), {"stripe": true, "wing": true}))
	game.cars.append(_qa_traffic_car(0, 830.0, "", 3, Color("#b9bdc1")))
	game.cars.append(_qa_traffic_car(1, 830.0, "", 6, Color("#8a5a2b"), {"cargo": true}))
	game.cars.append(_qa_traffic_car(2, 830.0, "", 2, Color("#3d4147"), {"trailer": Color("#c3c5c1")}))
	game.cars.append(_qa_traffic_car(3, 830.0, "", 4, Color("#1f6a78"), {"accent": Color("#e0a52a")}))
	game.time_of_day = 0.15
	game.cloud_amount = 0.0
	game.rain_amount = 0.0
	game.storm_amount = 0.0
	game.fog_amount = 0.0
	game.wetness = 0.0
	game.queue_redraw()
	# Let the lazy 3D sprites bake before the shot; without this the sheet
	# catches a half-2D, half-3D frame.
	await get_tree().create_timer(2.4).timeout
	await _shot("qa_traffic_day")

	game.time_of_day = 0.68
	game.cloud_amount = 0.65
	game.rain_amount = 0.85
	game.wetness = 0.95
	game.scroll = 40.0
	game.queue_redraw()
	await _shot("qa_traffic_night")
	await get_tree().create_timer(0.2).timeout
	get_tree().quit()


# Scene QA: sun and shadows over a day, road-works pits, the footbridge,
# a lane-changing car, pickups, score pops and the HUD weather clock.
func _qa_scene_seq() -> void:
	await get_tree().create_timer(1.0).timeout
	tutorial_done = true
	show_garage()
	await get_tree().create_timer(0.6).timeout
	await _shot("qa_garage")
	start_game()
	await get_tree().create_timer(1.2).timeout
	var spacing := game.overhead_spacing
	var section := 3
	while (hash(Vector2i(section, game.active_run_seed % 2147483647)) & 0xFFFF) % 3 != 1:
		section += 1
	var roll := hash(Vector2i(section, game.active_run_seed % 2147483647)) & 0xFFFF
	var offset := lerpf(0.20, 0.80, float(roll) / 65535.0)
	for scene in [["dawn", 0.02, 0], ["noon", 0.26, 0], ["dusk", 0.50, 0], ["night", 0.70, 0], ["rain", 0.26, 2]]:
		game.paused = false
		game._rewind_invuln = 9999.0
		game._snap_challenge_weather(float(scene[1]), int(scene[2]))
		game.weather_next = Game.WEATHER_RAIN if int(scene[2]) != Game.WEATHER_RAIN else Game.WEATHER_CLEAR
		game.weather_timer = 12.0
		game.scroll = 380.0 + (float(section) + offset) * spacing
		game.cars.clear()
		game.items.clear()
		game.closed_lane = 0
		game.road_event_type = Game.EVENT_ROADWORKS
		game.road_event = Game.roadworks_layout(0, game.speed)
		game.road_event["warned"] = true
		game.road_event["y"] = 820.0 + float(game.road_event.lead) + Game.RW_ZONE_LEN * 0.5
		var c := _qa_traffic_car(2, 520.0, "sedan", 0, Color("#5e2b2b"))
		c["lane"] = 3
		c["x"] = lerpf(game._lane_x(2), game._lane_x(3), 0.45)
		c["yaw"] = Game.LC_YAW_MAX * 0.9
		game.cars.append(c)
		game.items.append({"lane": 2, "kind": 0, "x": game._lane_x(2), "y": 1000.0, "phase": 0.0})
		game.items.append({"lane": 3, "kind": 1, "x": game._lane_x(3), "y": 980.0, "phase": 0.0})
		game.score_pops.clear()
		game._add_score_pop(Vector2(game._lane_x(1), 1180.0), "+90  ×1,5", Color("#ffb347"))
		game.lane = 2
		game.player_x = game._lane_x(2)
		await get_tree().process_frame
		game.paused = true
		await get_tree().create_timer(0.5).timeout
		await _shot("qa_scene_" + str(scene[0]))
	game.paused = false
	game.road_event["y"] = 1200.0 + float(game.road_event.lead) - float(game.road_event.taper_len) * 0.5
	game._snap_challenge_weather(0.30, 0)
	await get_tree().process_frame
	game.paused = true
	await get_tree().create_timer(0.4).timeout
	await _shot("qa_scene_cones")
	game.paused = false
	get_tree().quit()

func _shot(shot_name: String) -> void:
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://shots"))
	img.save_png("res://shots/%s.png" % shot_name)
	print("[shot] ", shot_name, " ", img.get_size())
