extends Control

# Each preview runs a staged race with the real renderer and perk rules.
# The viewport, traffic, score, and weather belong to the preview alone.
const VIEW := Vector2i(640, 600)
const ACCENT := Color("#ffbf89")
const GOOD := Color("#8aebc3")
const NITRO := Color("#89dfff")
const INK := Color("#f3f5fa")
const MUTED := Color("#b6c3d7")

var caption_font: Font
var body_font: Font
var _car: Dictionary = {}
var _road: Game
var _viewport: SubViewport
var _time := 0.0
var _duration := 5.6
var _title := ""
var _detail := ""
var _cue_color := ACCENT
var _cue_time := 0.0
var _completed := false
var _focus: Dictionary = {}
var _passed := false
var _launched := false
var _brake_peak := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	custom_minimum_size.y = 564
	set_process(false)


func play(car: Dictionary) -> void:
	if not is_visible_in_tree():
		return
	if _viewport == null:
		_build_viewport()
	_car = car
	_time = 0.0
	var perk := str(car.perk_id)
	_duration = 5.6
	if perk == "carbon_brakes":
		_duration = 7.0
	elif perk == "hyperdrive":
		_duration = 4.1
	_title = ""
	_completed = false
	_passed = false
	_launched = false
	_brake_peak = 0.0
	_focus = {}
	var rain := perk == "all_weather"
	var night := perk in ["ram_nitro", "hyperdrive"]
	var hour := 0.46 if rain else 0.52 if night else 0.32
	_road.challenge_config = {"car_index": car.id, "seed": 410 + int(car.id),
		"tod": hour, "weather": Game.WEATHER_RAIN if rain else Game.WEATHER_CLEAR}
	_road.start_run()
	_road.scroll = 810.0
	_road.player_y = VIEW.y * 0.61
	_road.spawn_t = _duration + 1.0
	_road.item_t = _duration + 1.0
	_road.puddles.clear()
	_road.contact_fx.reset()
	_road.render_stack.road_buffer.clear_all()
	_setup_scene()
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	set_process(true)
	queue_redraw()


func _build_viewport() -> void:
	_viewport = SubViewport.new()
	_viewport.size = VIEW
	_viewport.world_2d = World2D.new()
	_viewport.gui_disable_input = true
	add_child(_viewport)
	_road = Game.new()
	_road.gfx_level = GfxPresets.MEDIUM
	_road.use_session_audio = false
	_viewport.add_child(_road)
	_road.set_process(false)
	_road.set_process_unhandled_input(false)
	_road.cut_in.connect(_on_cut_in)
	_road.ram_used.connect(_on_ram)
	_road.slingshot_fired.connect(_on_slingshot)
	_road.pickup_taken.connect(_on_pickup)


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		set_process(false)
		if _viewport != null:
			_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _process(delta: float) -> void:
	var previous := _time
	var step := minf(delta, 0.05)
	_time = minf(_time + step, _duration)
	_direct_scene(previous)
	if _road.braking:
		_road._rear_spawn_t = _duration + 1.0
	_road._process(step)
	_read_scene()
	queue_redraw()
	if _time >= _duration:
		_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
		set_process(false)


func _setup_scene() -> void:
	var py := _road.player_y
	match str(_car.perk_id):
		"compact":
			_cue("Узкий просвет", "Хэтчбек проходит между машинами за счёт узкого хитбокса.")
			var space := _road.car_w * 0.39 * (1.0 + _road.hitbox_w_mult) + 0.8
			var left := _traffic(2, 0, py - 264.0, 0.71)
			var right := _traffic(7, 2, py - 264.0, 0.71)
			left.x = _road.player_x - space
			right.x = _road.player_x + space
			_focus = left
		"taxi_magnet":
			_cue("Монеты на соседней полосе", "Фургон держит свою полосу.")
			_traffic(5, 3, py - 350.0, 0.91)
		"wide_cutin":
			_cue("Обгон и возврат в полосу", "Седан проходит слева и перестраивается перед соперником.")
			_road.lane = 0
			_road.player_x = _road._lane_x(0)
			_traffic(4, 2, py - 160.0, 0.72)
		"all_weather":
			_cue("Мокрая дорога", "Водитель впереди видит дальнюю LED-люстру.")
			_focus = _traffic(2, 1, py - 251.0, 0.85)
			_road.nitro = 0.24
		"ram_nitro":
			_cue("Цель впереди", "Маскл подбирается к легковушке для тарана на нитро.")
			_focus = _traffic(2, 1, py - 330.0, 0.90)
			_road.nitro = Game.NITRO_SEG * 2.0
		"extra_tank":
			_cue("На старте два заряда", "У пикапа четыре ячейки вместо трёх.")
			_traffic(0, 0, py - 275.0, 0.88)
		"carbon_brakes":
			_cue("Торможение на скорости", "Карбоновые тормоза нагреваются на 45% медленнее.")
			_traffic(1, 3, py - 320.0, 0.74)
		"regen_brake":
			_cue("Нитро почти пустое", "Электрокар начинает торможение на скорости.")
			_road.nitro = 0.03
			_traffic(5, 2, py - 240.0, 0.82)
		"hyperdrive":
			_cue("Порог гипердрайва · 310 км/ч", "Гиперкар ускоряется до порога удвоения очков.")
			_road.nitro = Game.NITRO_SEG * 2.0
			_traffic(5, 2, py - 185.0, 0.83)
			_traffic(3, 0, py - 345.0, 0.87)


func _direct_scene(previous: float) -> void:
	var py := _road.player_y
	match str(_car.perk_id):
		"taxi_magnet":
			for i in range(4):
				if _crossed(previous, 0.45 + i * 0.46):
					_pickup(0, 2, py - 290.0)
		"wide_cutin":
			if _crossed(previous, 0.92) or _crossed(previous, 1.65):
				_road.move_lane(1)
		"all_weather":
			if _crossed(previous, 1.10):
				_road.puddles.append({"x": 0.375, "y": fposmod(py - 300.0 - _road.scroll, Game.ROAD_CYCLE),
					"rx": 57.0, "ry": 100.0, "rot": -0.08, "phase": 0.0})
		"ram_nitro":
			if _crossed(previous, 1.14):
				_boost()
				_cue("Нитро активно", "На этом заряде можно протаранить одну легковушку.", NITRO)
		"hyperdrive":
			if _crossed(previous, 2.55):
				_boost()
		"extra_tank":
			for i in range(4):
				if _crossed(previous, 0.48 + i * 0.47):
					_pickup(1, 1, py - 275.0)
			if _crossed(previous, 3.60):
				_boost()
				_cue("Один заряд потрачен", "В баке остаются ещё три заряда.", NITRO)
		"carbon_brakes":
			if _crossed(previous, 0.62):
				_road.set_braking(true)
			if _crossed(previous, 1.84):
				_road.set_braking(false)
				_cue("В воздушный мешок", "Держись за машиной впереди, чтобы зарядить Рогатку.")
				_traffic(2, 1, py - 230.0, 0.85)
			if not _launched and _road.slingshot_charge >= 0.99:
				_launched = true
				_road.move_lane(1)
		"regen_brake":
			if _crossed(previous, 0.83):
				_road.set_braking(true)
				_cue("Идёт рекуперация", "Пока горят стоп-сигналы, торможение пополняет нитро.", NITRO)
			if _crossed(previous, 2.30):
				_road.set_braking(false)
				_completed = _road.nitro >= Game.NITRO_SEG
				_cue("Дополнительный заряд", "Нитро накопилось за счёт торможения.", GOOD)


func _read_scene() -> void:
	match str(_car.perk_id):
		"compact":
			if not _completed and not _road.crashed and float(_focus.y) > _road.player_y + _road.car_h * 0.78:
				_completed = true
				_cue("Просвет пройден", "Хитбокс на 12% уже, поэтому кузов избежал контакта.", GOOD)
		"taxi_magnet":
			if not _completed and _road.pickup_coins >= 12:
				_completed = true
				_cue("Монета притянулась к фургону", "Смена полосы не нужна. К заработку добавляется 35%.", GOOD)
		"all_weather":
			if not _passed and int(_focus.lane) != _road.lane:
				_passed = true
				_cue("Трафик освобождает полосу", "Люстра помогает пройти вперёд.")
			if not _completed and _road.nitro > 0.25:
				_completed = true
				_cue("Лужа пополнила нитро", "Полоса свободна, шкала нитро подросла.", GOOD)
		"extra_tank":
			if not _completed and _road.nitro >= _road.max_nitro - 0.001:
				_completed = true
				_cue("Четвёртая ячейка заполнена", "Четыре полных заряда готовы к использованию.", GOOD)
		"carbon_brakes":
			_brake_peak = maxf(_brake_peak, _road.brake_heat)
		"hyperdrive":
			if not _completed and _road.hyperdrive_active:
				_completed = true
				_cue("Гипердрайв включён", "За дистанцию и обгоны начисляется вдвое больше очков.", GOOD)


func _traffic(car_index: int, lane: int, y: float, relative_speed: float) -> Dictionary:
	var model := Cars.get_car(car_index)
	var vehicle := {"lane": lane, "x": _road._lane_x(lane), "y": y, "w": _road.car_w, "h": _road.car_h,
		"kind": 0, "color": Color(str(model.color)), "rel": relative_speed, "near": false, "cutin": false,
		"stripe": model.stripe, "wing": model.wing, "stripe_color": Color(str(model.stripe_color)),
		"silhouette": model.silhouette}
	_road.cars.append(vehicle)
	return vehicle


func _pickup(kind: int, lane: int, y: float) -> void:
	_road.items.append({"kind": kind, "lane": lane, "x": _road._lane_x(lane), "y": y, "phase": 0.0})


func _boost() -> void:
	if _road.tap_nitro(false):
		Sfx.boost_burst()


func _on_cut_in(_combo: int) -> void:
	if _car.perk_id == "wide_cutin":
		_completed = true
		_cue("Подрез засчитан", "Окно шире на 45%, а подрез даёт на 25% больше нитро.", GOOD)


func _on_ram(points: int) -> void:
	_completed = true
	_cue("Таран · +%d очков" % points, "Маскл сбивает легковушку и продолжает заезд.", GOOD)


func _on_slingshot(_combo: int, _points: int) -> void:
	_completed = true
	_cue("Рогатка сработала", "В воздушном мешке заряд набирается на 35% быстрее.", GOOD)


func _on_pickup(kind: int) -> void:
	if kind == 0:
		Sfx.pickup_coin()
	else:
		Sfx.pickup_nitro()


func _crossed(previous: float, at: float) -> bool:
	return previous < at and _time >= at


func _cue(title: String, detail: String, color := ACCENT) -> void:
	if title == _title:
		return
	_title = title
	_detail = detail
	_cue_color = color
	_cue_time = _time


func _draw() -> void:
	if _viewport == null or _road == null:
		return
	draw_set_transform(Vector2.ZERO, 0.0, size / Vector2(VIEW))
	draw_texture_rect(_viewport.get_texture(), Rect2(Vector2.ZERO, Vector2(VIEW)), false)
	Fx.vgrad(self, Rect2(0, 0, VIEW.x, 100), Color("#101724d9"), Color("#10172400"))
	_draw_hud()
	if _car.perk_id == "compact" and not _completed:
		_draw_clearance()
	var bottom := float(VIEW.y)
	Fx.vgrad(self, Rect2(0, bottom - 150, VIEW.x, 67), Color("#10152100"), Color("#101521ef"))
	draw_rect(Rect2(0, bottom - 83, VIEW.x, 83), Color("#101521ef"))
	var pulse := 1.0 - clampf((_time - _cue_time) / 0.45, 0.0, 1.0)
	draw_rect(Rect2(0, bottom - 83, 5, 79), Color(_cue_color, 0.65 + pulse * 0.35))
	_text(_title, Vector2(19, bottom - 48), 26, _cue_color)
	_text(_detail, Vector2(19, bottom - 20), 18, MUTED, false)
	draw_rect(Rect2(0, bottom - 4, VIEW.x, 4), Color("#3b4758"))
	draw_rect(Rect2(0, bottom - 4, VIEW.x * _time / _duration, 4), ACCENT)
	draw_set_transform(Vector2.ZERO)


func _draw_hud() -> void:
	Art.rr(self, Rect2(13, 13, 126, 68), Color("#111825e9"), 12)
	var kmh := Game.gauge_kmh(_road.speed, _road.base_speed, _road.top_speed)
	_text("КМ/Ч", Vector2(24, 37), 16, MUTED, false)
	_text(str(kmh), Vector2(24, 67), 31, INK)
	match str(_car.perk_id):
		"compact":
			_badge("ХИТБОКС", "−12%", ACCENT)
		"taxi_magnet":
			_badge("МОНЕТЫ · ТАРИФ", "%d  ·  +35%%" % _road.pickup_coins, ACCENT)
		"carbon_brakes":
			_badge("НАГРЕВ / РОГАТКА", "%d%%  /  %d%%" % [roundi(_brake_peak * 100.0),
				roundi(_road.slingshot_charge * 100.0)], NITRO)
		"hyperdrive":
			_badge("МНОЖИТЕЛЬ ОЧКОВ", "×%d" % _road._effective_score_mult(), GOOD if _road.hyperdrive_active else INK)
		_:
			_draw_nitro()


func _badge(label: String, value: String, color: Color) -> void:
	Art.rr(self, Rect2(429, 13, 198, 68), Color("#111825e9"), 12)
	_text(label, Vector2(442, 37), 16, MUTED, false)
	_text(value, Vector2(442, 67), 25, color)


func _draw_nitro() -> void:
	Art.rr(self, Rect2(429, 13, 198, 68), Color("#111825e9"), 12)
	var slots := roundi(_road.max_nitro / Game.NITRO_SEG)
	_text("НИТРО", Vector2(442, 37), 16, MUTED, false)
	var segment := 172.0 / slots
	for i in slots:
		var rect := Rect2(442 + segment * i, 50, segment - 4, 15)
		Art.rr(self, rect, Color("#48566d"), 4)
		var fill := clampf(_road.nitro / Game.NITRO_SEG - i, 0.0, 1.0)
		if fill >= 0.04:
			Art.rr(self, Rect2(rect.position, Vector2(rect.size.x * fill, rect.size.y)), NITRO, 4)


func _draw_clearance() -> void:
	var center := Vector2(_road.player_x, _road.player_y)
	var collider := Vector2(_road.car_w * 0.78 * _road.hitbox_w_mult, _road.car_h * 0.80)
	var edge := Rect2(center - collider * 0.5, collider)
	draw_rect(edge, Color("#ffcb8b"), false, 2.0)


func _text(text: String, baseline: Vector2, font_size: int, tint: Color, heavy := true) -> void:
	var font := caption_font if heavy else body_font
	if font != null:
		draw_string(font, baseline, text, HORIZONTAL_ALIGNMENT_LEFT, VIEW.x - baseline.x - 12, font_size, tint)
