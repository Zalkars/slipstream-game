class_name Game
extends Node2D

# Top-down highway racer: procedural road, traffic, pickups, braking and nitro.

signal hud_changed(score: int, kmh: int, nitro: float, combo: int, coins: int, boosting: bool)
signal run_ended(score: int, distance: int, near: int, coins: int)
signal near_miss(combo: int)
signal cut_in(combo: int)
signal pickup_taken(kind: int)
signal lane_changed(new_lane: int)
signal brake_state_changed(is_braking: bool)
signal status_changed(slip: float, brake_heat: float, overheated: bool)
signal rewind_started()
signal rewind_finished()
signal nitro_boosted()
signal slingshot_ready()
signal slingshot_fired(combo: int, bonus_pts: int)
signal chrono_shield_triggered()
signal ram_used(bonus_pts: int)
signal road_event_banner(title: String, sub: String, col: Color)
signal duel_milestone(kind: String)
signal challenge_hud_changed(info: Dictionary)

const LANES := 4
const DEMO_SPEED := 620.0
const NITRO_SEG := 1.0 / 3.0
const RACE_ART := preload("res://scripts/race_art.gd")
const BOOST_TIME := 1.6
const SLINGSHOT_TIME := 0.85
const SLINGSHOT_MULT := 1.32
const FX_EMISSION_STEP := 1.0 / 60.0
const EVENT_NONE := 0
const EVENT_RADAR := 1
const EVENT_ROADWORKS := 2
const EVENT_BLACKOUT := 3
const BRAKE_MULT := 0.42
# 0.8.0 weather braking physics. Version 1 = 0.7.0 behaviour (dry grip
# everywhere); SLIP1 challenge codes replay with it, SLIP2 and new runs use 2.
const PHYSICS_VERSION := 2
const MU_DRY := 1.0
const MU_WET := 0.70
const MU_PUDDLE := 0.50
const MU_AQUAPLANE := 0.35
# How much of the grip loss reaches the brakes and the steering: the goal is
# a sense of weight, not a harder game.
const BRAKE_GRIP_WEIGHT := 0.75
const STEER_GRIP_WEIGHT := 0.40
const AQUAPLANE_TIME := 0.45
const CRUISE_KMH := 100.0
const TOP_KMH_SCALE := 0.3
const BOOST_KMH_SCALE := 1.2
const BRAKE_HEAT_RATE := 0.46
const BRAKE_HEAT_LOAD := 0.24
const BRAKE_COOL_RATE := 0.34
const BRAKE_RESTART_HEAT := 0.28
const SLIP_BONUS := 0.15
const CUTIN_WINDOW := 0.72
const CUTIN_MAX_GAP := 230.0
const ROAD_CYCLE := 3600.0
const DECOR_CYCLE := 7800.0
const ROADSIDE_ART := preload("res://scripts/roadside_art.gd")
const DAY_LENGTH := 360.0
const WEATHER_CLEAR := 0
const WEATHER_CLOUDY := 1
const WEATHER_RAIN := 2
const WEATHER_STORM := 3
const WEATHER_FOG := 4
# t, ambient r/g/b, night factor. One full day takes DAY_LENGTH seconds.
const SKY_KEYS := [
	[0.00, 1.00, 1.00, 1.00, 0.00],
	[0.24, 1.00, 1.00, 1.00, 0.00],
	[0.37, 1.05, 0.97, 0.88, 0.00],
	[0.44, 1.04, 0.90, 0.77, 0.08],
	[0.49, 0.94, 0.80, 0.77, 0.28],
	[0.55, 0.70, 0.65, 0.76, 0.60],
	[0.60, 0.46, 0.49, 0.62, 0.88],
	[0.64, 0.42, 0.46, 0.60, 1.00],
	[0.80, 0.42, 0.46, 0.60, 1.00],
	[0.86, 0.54, 0.52, 0.63, 0.66],
	[0.92, 0.80, 0.68, 0.62, 0.22],
	[0.97, 0.95, 0.90, 0.84, 0.03],
	[1.00, 1.00, 1.00, 1.00, 0.00],
]
const PALETTE := preload("res://scripts/traffic_palette.gd")
const TRAFFIC_COLORS = PALETTE.TRAFFIC_COLORS
const TRAILER_COLORS = PALETTE.TRAILER_COLORS
const BUS_ACCENTS = PALETTE.BUS_ACCENTS
# kind: 0 car, 1 SUV, 2 truck, 3 van, 4 bus, 5 sports car, 6 pickup.
const TRAFFIC_TYPES := [
	{"kind": 0, "weight": 0.26, "w": 1.00, "h": 1.00, "rel": [0.70, 0.80]},
	{"kind": 1, "weight": 0.14, "w": 1.06, "h": 1.08, "rel": [0.66, 0.76]},
	{"kind": 2, "weight": 0.12, "w": 1.14, "h": 1.72, "rel": [0.54, 0.64]},
	{"kind": 3, "weight": 0.13, "w": 1.04, "h": 1.38, "rel": [0.63, 0.73]},
	{"kind": 4, "weight": 0.07, "w": 1.12, "h": 2.05, "rel": [0.48, 0.58]},
	{"kind": 5, "weight": 0.14, "w": 1.05, "h": 0.96, "rel": [0.74, 0.86]},
	{"kind": 6, "weight": 0.14, "w": 1.05, "h": 1.16, "rel": [0.68, 0.78]},
]

var W := 720.0
var H := 1560.0
var road_w := 518.0
var road_x := 101.0
var lane_w := 129.5
var car_w := 86.0
var car_h := 163.0
var player_y := 1320.0

var scroll := 0.0
var speed := 760.0
var t := 0.0
var distance := 0.0
var score := 0.0
var bonus := 0.0
var near := 0
var combo := 0
var combo_t := 0.0
var nitro := NITRO_SEG
var boosting := false
var boost_t := 0.0
var braking := false
var lane := 1
var player_x := 300.0
var player_tilt := 0.0
var cars: Array = []
var items: Array = []
var spawn_t := 0.8
var item_t := 1.4
var demo := true
var running := false
var paused := false
var time_scale := 1.0
var crashed := false
var shake := 0.0
var flash := 0.0
var particles: Array = []
var _fx_emission_t := 0.0
var decor: Array = []
var roadside_art: Node
var _nitro_cooldown := 0.0

# Brake temperature, slipstream, weather, day/night and tutorial rewind.
var brake_heat := 0.0
var physics_version := PHYSICS_VERSION
var grip_mu := 1.0          # tyre grip under the player this tick
var puddle_depth := 0.0     # 0..1 water depth under the player
var aquaplane_t := 0.0      # seconds of aquaplaning left
var overheated := false
var slip := 0.0
var time_of_day := 0.15
var weather_state := 0
var weather_timer := 45.0
var rain_amount := 0.0
var fog_amount := 0.0
var cloud_amount := 0.05
var storm_amount := 0.0
var wetness := 0.0
var wind := 0.15
var lightning := 0.0
var lightning_next := 9.0
var thunder_delay := 0.0
var lightning_bolt := PackedVector2Array()
var lightning_branches: Array = []
var puddles: Array = []
var rear_hazards: Array = []
var tutorial_mode := false
var rewinding := false
var rewind_frames: Array = []
var _rewind_step_t := 0.0
var _rewind_invuln := 0.0
var _snapshot_t := 0.0
var _cutin_window := 0.0
var _cutin_lane := -1
var _rear_spawn_t := 0.5
var _hud_font: Font

# Deterministic simulation RNG & async challenge / ghost duel state.
var run_rng := RandomNumberGenerator.new()
var active_run_seed := 1
var start_tod := 0.15
var start_weather := 0
var challenge_config: Dictionary = {}
var duel_clock := 0.0
var ghost_rec: Array = []
var _ghost_rec_t := 0.0
var _duel_passed_crash := false
var _duel_beaten_score := false
var _ghost_art: Dictionary = {}
var _ghost_sprite: Dictionary = {}
var _ghost_state: Dictionary = {}

# Per-car unique perks, Slingshot Draft, Chrono-Shield, Road Events, Traffic Signals.
var car_perk := "compact"
var max_nitro := 1.0
var ram_charges := 0
var hyperdrive_active := false
var coin_mult := 1.0
var hitbox_w_mult := 1.0
var cutin_window_mult := 1.0
var cutin_gap_mult := 1.0
var cutin_nitro_mult := 1.0
var brake_heat_mult := 1.0
var brake_cool_mult := 1.0
var slingshot_rate_mult := 1.0
var _puddle_cd := 0.0

var slingshot_charge := 0.0
var slingshot_t := 0.0
var slingshot_grace := 0.0
var _slingshot_notified := false
var _shield_post_nitro := -1.0
var _shield_active := false
# Rewarded-ad revive: once per run, only after a fatal collision.
var _revive_used := false
var _revive_eligible := false

var _traffic_lc_t := 2.4
var road_event_type := EVENT_NONE
var road_event: Dictionary = {}
var road_event_t := 18.0
var _last_event_type := EVENT_NONE
var blackout_amount := 0.0
var score_mult := 1
var closed_lane := -1

var car_index := 0
var base_speed := 740.0
var top_speed := 1100.0
var handling := 12.0

var player_color := Color("#b32b26")
var player_stripe := true
var player_wing := false
var player_stripe_col := Color("#f0ede4")
var player_silhouette := "sedan"
# Settings toggle: 3D sprites for the race, or the original painted art.
var use_3d_cars := true:
	set(value):
		use_3d_cars = value
		if race_art != null:
			race_art.set_enabled(value)
var race_art: Node
var _player_art: Dictionary = {}

var control_mode := "buttons"
var free_lane := 3
var free_t := 7.0
var pickup_coins := 0

var swipe_start := Vector2.ZERO
var swipe_used := true
var _swipe_touch_id := -1
var _swipe_mouse_down := false

var grass_tex: ImageTexture
var glow_tex: ImageTexture
var _sx := 0.0
var _sy := 0.0

# Rain motion state, shared by the simulation and the renderer so a streak's
# angle always matches the velocity that actually moved it.
var rain_vx := -60.0
var rain_vy := 900.0
var rain_gust := 1.0

# 0.8.0 render pipeline: every visual system lives under render_stack and only
# reads this node's state. gfx_level is a GfxPresets level (LOW..ULTRA).
var render_stack: RenderStack
var lighting_fx: Lighting
var contact_fx: ContactFx
var weather_fx: WeatherFx
var fog_fx: FogFx
var gfx_level := GfxPresets.MEDIUM
var gfx_target_fps := 60
var draw_cpu_ms := 0.0  # CPU time of the last _draw (QA perf mode)


static func top_kmh(px_speed: float) -> int:
	return int(round(px_speed * TOP_KMH_SCALE))


# Arcade gauge: the car cruises around CRUISE_KMH and only its top speed matches
# the real px/s scale, so normal driving doesn't read like a hypercar.
static func gauge_kmh(px_speed: float, base_px: float, top_px: float) -> int:
	if px_speed <= 0.0:
		return 0
	if base_px <= 0.0 or top_px <= base_px:
		return top_kmh(maxf(px_speed, 0.0))
	var top_kmh_val := top_px * TOP_KMH_SCALE
	if px_speed <= base_px:
		return int(round(px_speed / base_px * CRUISE_KMH))
	if px_speed <= top_px:
		var k := (px_speed - base_px) / (top_px - base_px)
		return int(round(lerpf(CRUISE_KMH, top_kmh_val, k)))
	var over := clampf((px_speed - top_px) / (top_px * 0.5), 0.0, 1.0)
	return int(round(lerpf(top_kmh_val, top_kmh_val * BOOST_KMH_SCALE, over)))


func _ready() -> void:
	texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	var rf := load("res://fonts/Rajdhani-Bold.ttf") as Font
	_hud_font = rf if rf != null else ThemeDB.fallback_font
	run_rng.seed = 1729
	grass_tex = _noise_tex(128, Color(0.400, 0.500, 0.295), 0.042, 23)
	glow_tex = Fx.glow_tex()
	roadside_art = ROADSIDE_ART.new()
	roadside_art.name = "RoadsideArt"
	add_child(roadside_art)
	race_art = RACE_ART.new()
	race_art.name = "RaceArt"
	add_child(race_art)
	race_art.set_enabled(use_3d_cars)
	_layout()
	_gen_decor()
	_gen_puddles()
	_setup_render()
	get_viewport().size_changed.connect(_layout)
	# Audio reads speed, traffic, weather and road state from here (0.8.0).
	if Sfx.has_method("bind_game"):
		Sfx.bind_game(self)
	start_demo()

func _setup_render() -> void:
	# Cars, scenery and items in this node's own _draw are lit objects.
	light_mask = RenderStack.MASK_OBJECTS
	render_stack = RenderStack.new()
	add_child(render_stack)
	render_stack.setup(self)
	lighting_fx = Lighting.new()
	render_stack.add_child(lighting_fx)
	lighting_fx.setup(self, render_stack)
	render_stack.add_system(lighting_fx)
	fog_fx = FogFx.new()
	fog_fx.setup(self, render_stack)
	render_stack.add_system(fog_fx)
	weather_fx = WeatherFx.new()
	render_stack.add_child(weather_fx)
	weather_fx.setup(self, render_stack)
	render_stack.add_system(weather_fx)
	contact_fx = ContactFx.new()
	contact_fx.setup(self, render_stack)
	render_stack.add_system(contact_fx)
	render_stack.overlay_painters.insert(0, paint_haze)
	render_stack.finish_setup()
	render_stack.apply_preset(gfx_level, gfx_target_fps)


# Applied from the settings screen; takes effect on the next frame.
func set_graphics(level: int, target_fps := 60) -> void:
	gfx_level = clampi(level, GfxPresets.LOW, GfxPresets.ULTRA)
	gfx_target_fps = target_fps
	if render_stack != null:
		render_stack.apply_preset(gfx_level, gfx_target_fps)


# --- setup ------------------------------------------------------------------

func _layout(size: Vector2 = Vector2.ZERO) -> void:
	var previous_car_w := car_w
	var old_road_x := road_x
	var old_lane_w := lane_w
	var old_car_w := car_w
	var old_car_h := car_h
	var old_player_y := player_y
	var vs := size if size != Vector2.ZERO else get_viewport_rect().size
	W = vs.x
	H = vs.y
	road_w = minf(W * 0.72, 640.0)
	lane_w = road_w / float(LANES)
	road_x = (W - road_w) * 0.5
	car_w = lane_w * 0.665
	car_h = car_w * 1.9
	player_y = H - 330.0
	if demo:
		player_x = _lane_x(lane)
	# A window resize moves the road and the player; already-spawned traffic and
	# pickups must follow their lanes instead of staying in the old coordinates.
	if old_lane_w > 0.0 and (
		not is_equal_approx(road_x, old_road_x)
		or not is_equal_approx(lane_w, old_lane_w)
		or not is_equal_approx(player_y, old_player_y)
	):
		var kx := car_w / maxf(1.0, old_car_w)
		var ky := car_h / maxf(1.0, old_car_h)
		var dy := player_y - old_player_y
		for c in cars:
			c.x = road_x + lane_w * clampf((float(c.x) - old_road_x) / old_lane_w, 0.0, float(LANES))
			c.w = float(c.w) * kx
			c.h = float(c.h) * ky
			c.y = float(c.y) + dy
		for it in items:
			it.x = road_x + lane_w * clampf((float(it.x) - old_road_x) / old_lane_w, 0.0, float(LANES))
			it.y = float(it.y) + dy
	if not decor.is_empty() and not is_equal_approx(car_w, previous_car_w):
		_gen_decor()


func _lane_x(l: int) -> float:
	return road_x + lane_w * (float(l) + 0.5)


func _noise_tex(size: int, base: Color, variation: float, seed_val: int) -> ImageTexture:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val
	var img := Image.create(size, size, false, Image.FORMAT_RGBA8)
	# Low-frequency value noise gives asphalt its uneven, worn patches; the
	# per-pixel grain on top reads as aggregate when tiled.
	var cells := 8
	var grid := PackedFloat32Array()
	grid.resize((cells + 1) * (cells + 1))
	for i in range(grid.size()):
		grid[i] = rng.randf_range(-1.0, 1.0)
	# Wrap the low-frequency grid so the tiled asphalt has no visible seams.
	for i in range(cells + 1):
		grid[i * (cells + 1) + cells] = grid[i * (cells + 1)]
		grid[cells * (cells + 1) + i] = grid[i]
	for y in range(size):
		for x in range(size):
			var gx := float(x) / float(size) * float(cells)
			var gy := float(y) / float(size) * float(cells)
			var ix := clampi(int(gx), 0, cells - 1)
			var iy := clampi(int(gy), 0, cells - 1)
			var fx := gx - float(ix)
			var fy := gy - float(iy)
			fx = fx * fx * (3.0 - 2.0 * fx)
			fy = fy * fy * (3.0 - 2.0 * fy)
			var g00 := grid[iy * (cells + 1) + ix]
			var g10 := grid[iy * (cells + 1) + ix + 1]
			var g01 := grid[(iy + 1) * (cells + 1) + ix]
			var g11 := grid[(iy + 1) * (cells + 1) + ix + 1]
			var coarse := lerpf(lerpf(g00, g10, fx), lerpf(g01, g11, fx), fy)
			var fine := rng.randf_range(-1.0, 1.0)
			var n := coarse * 0.72 + fine * 0.34
			img.set_pixel(x, y, Color(
				clampf(base.r + n * variation, 0.0, 1.0),
				clampf(base.g + n * variation, 0.0, 1.0),
				clampf(base.b + n * variation, 0.0, 1.0),
				1.0
			))
	for i in range(size * 4):
		var px := rng.randi_range(0, size - 1)
		var py := rng.randi_range(0, size - 1)
		img.set_pixel(px, py, base.lightened(rng.randf_range(0.10, 0.26)))
	for i in range(size * 2):
		var px := rng.randi_range(0, size - 1)
		var py := rng.randi_range(0, size - 1)
		img.set_pixel(px, py, base.darkened(rng.randf_range(0.08, 0.20)))
	# Small tar-filled cracks.
	for i in range(6):
		var px := float(rng.randi_range(0, size - 1))
		var py := float(rng.randi_range(0, size - 1))
		var ang := rng.randf_range(0.0, TAU)
		for step in range(rng.randi_range(10, 34)):
			var ix2 := int(posmod(px, float(size)))
			var iy2 := int(posmod(py, float(size)))
			img.set_pixel(ix2, iy2, base.darkened(rng.randf_range(0.14, 0.28)))
			ang += rng.randf_range(-0.45, 0.45)
			px += cos(ang) * 1.7
			py += sin(ang) * 1.7
	return ImageTexture.create_from_image(img)


# Soft headlight cone, radial glow, rain streak and wet sheen textures are
# generated by Fx (see fx.gd); keeping them there leaves this file about the game.


func _gen_puddles() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 44127
	puddles.clear()
	for i in range(24):
		puddles.append({
			"x": rng.randf_range(0.05, 0.95),
			"y": rng.randf() * ROAD_CYCLE,
			"rx": rng.randf_range(24.0, 78.0),
			"ry": rng.randf_range(55.0, 165.0),
			"rot": rng.randf_range(-0.16, 0.16),
			"phase": rng.randf_range(0.0, TAU),
		})

func _gen_decor() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 99017
	decor.clear()
	for side in [-1, 1]:
		# Meadows and woodland alternate; the two verges have independent gaps.
		for i in range(56):
			var y := (float(i) + rng.randf_range(0.1, 0.9)) * DECOR_CYCLE / 56.0
			var woodland := sin(y * TAU / DECOR_CYCLE * 3.0 + side * 1.7)
			if woodland < -0.45 and rng.randf() < 0.8:
				continue
			var species := rng.randi_range(0, 3)
			if woodland > 0.5:
				species = 2 if rng.randf() < 0.65 else 3
			_add_decor(rng, side, y, 0, species, rng.randf_range(0.78, 1.13), rng.randf_range(23, 64), 2)
			# A smaller companion makes a grove rather than a line of trees.
			if i % 4 == 0:
				_add_decor(rng, side, y + 54, 0, species, 0.63, 56, 2)
		for i in range(40):
			var y := rng.randf() * DECOR_CYCLE
			_add_decor(rng, side, y, 1, ROADSIDE_ART.SHRUB, rng.randf_range(0.6, 0.95), rng.randf_range(8, 35), 1)
			if i % 3 == 0:
				_add_decor(rng, side, y + 34, 4, ROADSIDE_ART.FERN, 0.7, rng.randf_range(12, 30), 1)
		for i in range(95):
			var prop := ROADSIDE_ART.FLOWERS
			if i % 9 == 0:
				prop = ROADSIDE_ART.ROCK
			elif i % 23 == 0:
				prop = ROADSIDE_ART.LOG
			_add_decor(rng, side, rng.randf() * DECOR_CYCLE, 4, prop,
				rng.randf_range(0.45, 0.85), rng.randf_range(-3, 48), 0)
		# Small roadside destinations and maintenance details, spaced in groups.
		for i in range(6):
			var y := i * 1300.0 + (530.0 if side < 0 else 910.0)
			var prop := ROADSIDE_ART.PICNIC if i % 2 == 0 else ROADSIDE_ART.WORKS
			_add_decor(rng, side, y, 4, prop, 0.85, 19, 1)
			_add_decor(rng, side, y + 80, 4, ROADSIDE_ART.CABINET, 0.8, 11, 1)
			for j in range(3):
				_add_decor(rng, side, y - 160 - j * 82, 4, ROADSIDE_ART.FENCE, 0.85, 35, 1)
		for i in range(39):
			_add_decor(rng, side, i * 200.0 + 70, 4, ROADSIDE_ART.MARKER, 0.85, -12, 1)
		for i in range(12):
			_add_decor(rng, side, i * 650.0 + 120, 4, ROADSIDE_ART.DRAIN, 0.65, -9, 0)
		# Infrastructure has deliberate spacing and stays clear of the trees.
		for i in range(12):
			_add_decor(rng, side, i * 650.0 + (210.0 if side > 0 else 0.0), 2, 0, 1.0, 0.0, 3)
		for i in range(5):
			_add_decor(rng, side, i * 1560.0 + 330.0, 3, 0, 1.0, 0.0, 3)
	# Buildings sit on cleared plots, away from the shoulder and guardrail.
	# Filter the existing plants/furniture first so neither can hide a roof.
	var plots: Array = []
	for side in [-1, 1]:
		for i in range(5):
			plots.append({"side": side, "y": i * 1560.0 + (280.0 if side < 0 else 1040.0),
				"prop": [ROADSIDE_ART.APARTMENT, ROADSIDE_ART.HOUSE, ROADSIDE_ART.SHOP, ROADSIDE_ART.BARN, ROADSIDE_ART.GARAGE][posmod(i + (2 if side > 0 else 0), 5)]})
	decor = decor.filter(func(d: Dictionary) -> bool:
		if int(d.prop) == ROADSIDE_ART.MARKER or int(d.prop) == ROADSIDE_ART.DRAIN:
			return true
		for plot in plots:
			if int(plot.side) != int(d.side):
				continue
			var gap := fposmod(float(d.y) - float(plot.y) + DECOR_CYCLE * 0.5, DECOR_CYCLE) - DECOR_CYCLE * 0.5
			var bounds := _building_plot_bounds(plot)
			var margin := 45.0 if int(d.kind) == 2 else 70.0
			if gap > bounds.position.y - float(plot.y) - margin and gap < bounds.end.y - float(plot.y) + margin:
				return false
		return true)
	for plot in plots:
		_add_decor(rng, int(plot.side), float(plot.y), 5, int(plot.prop), 1.0, 4.0, 2)
	decor.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return int(a.layer) < int(b.layer))
	_index_decor()


# Spatial index of the decor (render cost, 0.8.0): y buckets along the cycle
# so drawing only touches props near the screen, plus the lamp-post and
# sign indices the lighting needs every frame. Buildings are tall and few,
# so they are always checked.
const DECOR_BUCKETS := 32
var _decor_buckets: Array = []
var _decor_tall: PackedInt32Array = PackedInt32Array()
var decor_lamps: PackedInt32Array = PackedInt32Array()
var decor_poles: PackedInt32Array = PackedInt32Array()
var _decor_visible: PackedInt32Array = PackedInt32Array()


func _index_decor() -> void:
	_decor_buckets.clear()
	for b in range(DECOR_BUCKETS):
		_decor_buckets.append(PackedInt32Array())
	_decor_tall = PackedInt32Array()
	decor_lamps = PackedInt32Array()
	decor_poles = PackedInt32Array()
	var bw := DECOR_CYCLE / float(DECOR_BUCKETS)
	for i in range(decor.size()):
		var d: Dictionary = decor[i]
		var kind := int(d.kind)
		if kind == 5:
			_decor_tall.append(i)
		else:
			var b := clampi(int(float(d.y) / bw), 0, DECOR_BUCKETS - 1)
			_decor_buckets[b].append(i)
		if kind == 2:
			decor_lamps.append(i)
		if kind == 2 or kind == 3:
			decor_poles.append(i)


# Indices (in draw order) of decor that can be on screen this frame.
func _visible_decor() -> PackedInt32Array:
	_decor_visible.clear()
	if _decor_buckets.size() != DECOR_BUCKETS:
		_index_decor()
	var bw := DECOR_CYCLE / float(DECOR_BUCKETS)
	# Decor y that lands on [-100, H + 100] on screen, one bucket of slack.
	var lo := -100.0 - scroll - bw
	var count := int(ceil((H + 200.0 + bw * 2.0) / bw)) + 1
	var first := int(floor(lo / bw))
	if count >= DECOR_BUCKETS:
		for i in range(decor.size()):
			_decor_visible.append(i)
		return _decor_visible
	for k in range(count):
		var b := posmod(first + k, DECOR_BUCKETS)
		_decor_visible.append_array(_decor_buckets[b])
	_decor_visible.append_array(_decor_tall)
	_decor_visible.sort()
	return _decor_visible


func _building_plot_bounds(plot: Dictionary) -> Rect2:
	var side := float(plot.side)
	var offset := float(plot.get("off", 4.0))
	var x := road_x - 52.0 - offset if side < 0 else road_x + road_w + 52.0 + offset
	return ROADSIDE_ART.building_bounds(Vector2(x, float(plot.y)), int(plot.prop),
		int(plot.get("variant", 0)), float(plot.get("size", 1.0)) * car_w / 86.0, side)


func _add_decor(rng: RandomNumberGenerator, side: int, y: float, kind: int,
		prop: int, size: float, offset: float, layer: int) -> void:
	# Keep rest areas and utility access readable, including across the loop seam.
	if kind == 0 or kind == 1:
		for i in range(6):
			var center := i * 1300.0 + (530.0 if side < 0 else 910.0) + 40.0
			var gap := fposmod(y - center + DECOR_CYCLE * 0.5, DECOR_CYCLE) - DECOR_CYCLE * 0.5
			if absf(gap) < 130.0:
				return
	decor.append({"side": side, "y": fposmod(y, DECOR_CYCLE), "kind": kind,
		"prop": prop, "variant": rng.randi_range(0, 3), "size": size,
		"off": offset, "tint": rng.randf(), "layer": layer})


func _rf() -> float:
	return randf() if demo else run_rng.randf()


func _rfr(a: float, b: float) -> float:
	return randf_range(a, b) if demo else run_rng.randf_range(a, b)


func _ri() -> int:
	return randi() if demo else run_rng.randi()


func _rir(a: int, b: int) -> int:
	return randi_range(a, b) if demo else run_rng.randi_range(a, b)


func _effective_score_mult() -> int:
	var m := score_mult
	if hyperdrive_active:
		m = maxi(m + 1, 2) if m > 1 else 2
	return m


func _apply_car() -> void:
	var car := Cars.get_car(car_index)
	base_speed = float(car.speed)
	top_speed = float(car.top)
	handling = float(car.handling)
	player_color = Color(str(car.color))
	player_stripe = bool(car.stripe)
	player_wing = bool(car.wing)
	player_stripe_col = Color(str(car.stripe_color))
	player_silhouette = str(car.get("silhouette", "sedan"))
	car_perk = str(car.get("perk_id", "compact"))
	max_nitro = (4.0 / 3.0) if car_perk == "extra_tank" else 1.0
	coin_mult = 1.35 if car_perk == "taxi_magnet" else 1.0
	hitbox_w_mult = 0.88 if car_perk == "compact" else 1.0
	cutin_window_mult = 1.45 if car_perk == "wide_cutin" else 1.0
	cutin_gap_mult = 1.25 if car_perk == "wide_cutin" else 1.0
	cutin_nitro_mult = 1.25 if car_perk == "wide_cutin" else 1.0
	brake_heat_mult = 0.55 if car_perk == "carbon_brakes" else 1.0
	brake_cool_mult = 1.35 if car_perk == "carbon_brakes" else 1.0
	slingshot_rate_mult = 1.35 if car_perk == "carbon_brakes" else 1.0
	_player_art = {
		"kind": 0,
		"silhouette": player_silhouette,
		"color": player_color,
		"stripe": player_stripe,
		"stripe_color": player_stripe_col,
	}
	if use_3d_cars and race_art != null:
		race_art.take(_player_art)


func _snap_challenge_weather(tod: float, w_state: int) -> void:
	time_of_day = fposmod(tod, 1.0)
	weather_state = clampi(w_state, 0, 4)
	var goal := _weather_targets()
	rain_amount = float(goal[0])
	fog_amount = float(goal[1])
	cloud_amount = float(goal[2])
	storm_amount = float(goal[3])
	wetness = clampf(rain_amount * 1.12 + storm_amount * 0.15, 0.0, 1.0)
	wind = clampf(0.12 + rain_amount * 0.42 + storm_amount * 0.72 + cloud_amount * 0.10, 0.0, 1.2)
	weather_timer = 55.0
	lightning = 0.0
	thunder_delay = 0.0
	lightning_next = 7.0


func start_run() -> void:
	_fx_emission_t = 0.0
	reset_swipe()
	_layout()
	if not challenge_config.is_empty():
		car_index = clampi(int(challenge_config.get("car_index", car_index)), 0, Cars.LIST.size() - 1)
		active_run_seed = int(challenge_config.get("seed", 1))
		if active_run_seed == 0:
			active_run_seed = 1
		_snap_challenge_weather(float(challenge_config.get("tod", 0.15)), int(challenge_config.get("weather", WEATHER_CLEAR)))
	else:
		active_run_seed = (randi() & 0x7FFFFFFF) | 1
	run_rng.seed = active_run_seed
	start_tod = time_of_day
	start_weather = weather_state

	_apply_car()
	scroll = 0.0
	speed = base_speed
	t = 0.0
	duel_clock = 0.0
	distance = 0.0
	score = 0.0
	bonus = 0.0
	near = 0
	combo = 0
	combo_t = 0.0
	nitro = (NITRO_SEG * 2.0) if car_perk == "extra_tank" else NITRO_SEG
	boosting = false
	boost_t = 0.0
	_nitro_cooldown = 0.0
	ram_charges = 0
	hyperdrive_active = false
	_puddle_cd = 0.0
	braking = false
	brake_heat = 0.0
	overheated = false
	slip = 0.0
	physics_version = clampi(int(challenge_config.get("physics", PHYSICS_VERSION)), 1, PHYSICS_VERSION)
	grip_mu = 1.0
	puddle_depth = 0.0
	aquaplane_t = 0.0
	slingshot_charge = 0.0
	slingshot_t = 0.0
	slingshot_grace = 0.0
	_slingshot_notified = false
	_shield_post_nitro = -1.0
	_shield_active = false
	_revive_used = false
	_revive_eligible = false
	rear_hazards.clear()
	rewinding = false
	rewind_frames.clear()
	_rewind_step_t = 0.0
	_rewind_invuln = 0.0
	_snapshot_t = 0.0
	_cutin_window = 0.0
	_cutin_lane = -1
	_rear_spawn_t = 0.45
	_traffic_lc_t = 2.4
	road_event_type = EVENT_NONE
	road_event.clear()
	road_event_t = 18.0
	_last_event_type = EVENT_NONE
	blackout_amount = 0.0
	score_mult = 1
	closed_lane = -1
	tutorial_mode = false
	lane = 1
	player_x = _lane_x(lane)
	player_tilt = 0.0
	cars.clear()
	items.clear()
	particles.clear()
	spawn_t = 1.0
	item_t = 1.2
	pickup_coins = 0
	free_lane = 3
	free_t = 7.0
	crashed = false
	demo = false
	running = true
	paused = false
	time_scale = 1.0
	shake = 0.0
	flash = 0.0

	ghost_rec.clear()
	_ghost_rec_t = 0.0
	_duel_passed_crash = false
	_duel_beaten_score = false
	_ghost_state.clear()
	_ghost_art.clear()
	_ghost_sprite.clear()
	if str(challenge_config.get("type", "")) == "duel":
		var rcar := Cars.get_car(int(challenge_config.get("car_index", 0)))
		_ghost_art = {
			"kind": 0,
			"silhouette": str(rcar.get("silhouette", "sedan")),
			"color": Color(str(rcar.color)),
			"stripe": bool(rcar.stripe),
			"stripe_color": Color(str(rcar.stripe_color)),
		}
		if use_3d_cars and race_art != null:
			_ghost_sprite = race_art.take(_ghost_art)
	_record_ghost_sample(true)

	hud_changed.emit(0, gauge_kmh(speed, base_speed, top_speed), nitro, 0, 0, false)
	status_changed.emit(slip, brake_heat, overheated)
	_emit_challenge_hud()


func set_tutorial_mode(on: bool) -> void:
	if not on and rewinding:
		while not rewind_frames.is_empty():
			_apply_snapshot(rewind_frames.pop_back())
		_finish_rewind()
	tutorial_mode = on
	rewind_frames.clear()
	rewinding = false
	_rewind_invuln = 0.0
	_snapshot_t = 0.0
	if on:
		rewind_frames.append(_snapshot_state())


func start_demo() -> void:
	_fx_emission_t = 0.0
	reset_swipe()
	_apply_car()
	cars.clear()
	items.clear()
	particles.clear()
	_nitro_cooldown = 0.0
	lane = 1
	player_x = _lane_x(lane)
	crashed = false
	running = false
	demo = true
	paused = false
	boosting = false
	braking = false
	boost_t = 0.0
	shake = 0.0
	flash = 0.0
	brake_heat = 0.0
	overheated = false
	slip = 0.0
	tutorial_mode = false
	rewinding = false
	rewind_frames.clear()
	_rewind_invuln = 0.0
	slingshot_charge = 0.0
	slingshot_t = 0.0
	slingshot_grace = 0.0
	hyperdrive_active = false
	road_event_type = EVENT_NONE
	road_event.clear()
	blackout_amount = 0.0
	score_mult = 1
	closed_lane = -1
	_ghost_state.clear()
	spawn_t = 0.5


func stop_run() -> void:
	_fx_emission_t = 0.0
	reset_swipe()
	running = false
	demo = false
	boosting = false
	braking = false


func move_lane(dir: int) -> void:
	if not running or paused or crashed:
		return
	var old_lane := lane
	lane = clampi(lane + dir, 0, LANES - 1)
	if lane != old_lane:
		_cutin_window = CUTIN_WINDOW * cutin_window_mult
		_cutin_lane = lane
		if slingshot_charge >= 0.99 and not tutorial_mode:
			_fire_slingshot(lane - old_lane)
		lane_changed.emit(lane)


func _fire_slingshot(dir: int) -> void:
	slingshot_charge = 0.0
	slingshot_grace = 0.0
	_slingshot_notified = false
	slingshot_t = SLINGSHOT_TIME
	nitro = minf(max_nitro, nitro + NITRO_SEG * 0.75)
	combo += 1
	combo_t = 3.2
	var pts := 80 * combo * _effective_score_mult()
	bonus += pts
	shake = maxf(shake, 4.5)
	Sfx.slingshot_snap()
	for i in range(16):
		particles.append({
			"p": Vector2(player_x + randf_range(-car_w * 0.3, car_w * 0.3), player_y + randf_range(-car_h * 0.2, car_h * 0.45)),
			"v": Vector2(-float(dir) * randf_range(90.0, 240.0), randf_range(120.0, 320.0)),
			"life": randf_range(0.25, 0.52),
			"max": 0.52,
			"col": Color(0.36, 0.90, 0.98) if i % 2 == 0 else Color(1.0, 0.86, 0.32),
			"size": randf_range(2.5, 5.5),
		})
	slingshot_fired.emit(combo, pts)


func set_braking(on: bool) -> void:
	if on and overheated:
		if braking:
			braking = false
			brake_state_changed.emit(false)
		Sfx.click()
		return
	if not running or paused or crashed:
		if braking:
			braking = false
			brake_state_changed.emit(false)
		return
	if braking != on:
		braking = on
		if on:
			_rear_spawn_t = minf(_rear_spawn_t, 0.25)
		brake_state_changed.emit(braking)


func tap_nitro() -> bool:
	if not running or paused or crashed:
		return false
	if boost_t > 0.0 or _nitro_cooldown > 0.0:
		return false
	if nitro < NITRO_SEG - 0.002:
		return false
	nitro = maxf(0.0, nitro - NITRO_SEG)
	boost_t = BOOST_TIME
	boosting = true
	_nitro_cooldown = 0.35
	if car_perk == "ram_nitro":
		ram_charges = 1
	nitro_boosted.emit()
	return true


func reset_swipe() -> void:
	var held_swipe := _swipe_touch_id != -1 or _swipe_mouse_down
	_swipe_touch_id = -1
	_swipe_mouse_down = false
	swipe_used = true
	swipe_start = Vector2.ZERO
	if held_swipe:
		set_braking(false)


func _unhandled_input(event: InputEvent) -> void:
	if not running or paused or crashed or control_mode != "swipe":
		reset_swipe()
		return
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			if _swipe_touch_id == -1 and not _swipe_mouse_down:
				_swipe_touch_id = event.index
				swipe_start = event.position
				swipe_used = false
		elif event.index == _swipe_touch_id:
			if not event.canceled and not swipe_used:
				_try_swipe(event.position)
			reset_swipe()
	elif event is InputEventScreenDrag:
		if event.index == _swipe_touch_id and not swipe_used:
			_try_swipe(event.position)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if Input.emulate_touch_from_mouse or event.device == InputEvent.DEVICE_ID_EMULATION:
			return
		if event.pressed:
			if _swipe_touch_id == -1 and not _swipe_mouse_down:
				_swipe_mouse_down = true
				swipe_start = event.position
				swipe_used = false
		elif _swipe_mouse_down:
			if not swipe_used:
				_try_swipe(event.position)
			reset_swipe()
	elif event is InputEventMouseMotion and _swipe_mouse_down and not swipe_used:
		_try_swipe(event.position)


func _try_swipe(pos: Vector2) -> void:
	var d := pos - swipe_start
	var abs_x := absf(d.x)
	var abs_y := absf(d.y)
	if abs_x < 44.0 and abs_y < 44.0:
		return
	if abs_x > abs_y * 1.1:
		swipe_used = true
		move_lane(1 if d.x > 0.0 else -1)
	elif abs_y > abs_x * 1.1:
		swipe_used = true
		if d.y > 0.0:
			set_braking(true)
		else:
			if tap_nitro():
				Sfx.boost_burst()


func spawn_tutorial_car(target_lane: int) -> void:
	for c in cars:
		if c.get("lane", -1) == target_lane and c.get("y", 0.0) < player_y and c.get("y", 0.0) > player_y - 700.0:
			return
	var c := {
		"lane": target_lane,
		"x": _lane_x(target_lane),
		"y": player_y - 500.0,
		"w": car_w,
		"h": car_h,
		"kind": 0,
		"color": TRAFFIC_COLORS[randi() % TRAFFIC_COLORS.size()],
		"rel": 0.70,
		"cur_speed": 0.70 * base_speed,
		"braking": false,
		"demo_speed": 0.0,
		"near": false,
	}
	cars.append(c)


# --- simulation -------------------------------------------------------------

func _process(delta: float) -> void:
	var raw := minf(delta, 0.05)
	if rewinding:
		if not paused:
			_tick_rewind(raw)
	elif not paused:
		_tick(raw * time_scale)
	_sx = 0.0
	_sy = 0.0
	if shake > 0.2:
		_sx = randf_range(-shake, shake)
		_sy = randf_range(-shake, shake)
	if render_stack != null:
		render_stack.frame(delta)
	queue_redraw()


func _coins_total() -> int:
	var raw := int(distance / 10.0) + pickup_coins + near * 2
	if coin_mult > 1.01:
		return int(round(float(raw) * coin_mult))
	return raw


func _update_brake_heat(dt: float) -> void:
	if braking and not crashed:
		var load := clampf(speed / maxf(1.0, top_speed), 0.35, 1.25)
		brake_heat = clampf(brake_heat + dt * (BRAKE_HEAT_RATE + load * BRAKE_HEAT_LOAD) * brake_heat_mult, 0.0, 1.0)
		if brake_heat >= 1.0 and not overheated:
			overheated = true
			braking = false
			brake_state_changed.emit(false)
			shake = maxf(shake, 14.0)
			Sfx.brake_overheat()
	else:
		var cool := (BRAKE_COOL_RATE + (0.12 if speed < 260.0 else 0.0)) * brake_cool_mult
		if physics_version >= 2:
			cool *= 1.0 + wetness * 0.35  # spray cools the discs
		brake_heat = maxf(0.0, brake_heat - dt * cool)
		if overheated and brake_heat <= BRAKE_RESTART_HEAT:
			overheated = false
			Sfx.record()


func _update_slipstream(dt: float) -> void:
	var best := 0.0
	if not braking and not boosting and not crashed:
		for c in cars:
			if bool(c.get("rammed", false)):
				continue
			var dy := player_y - float(c.y)
			if dy <= car_h * 0.35 or dy > car_h * 7.5:
				continue
			var dx := absf(float(c.x) - player_x)
			if dx > (car_w + float(c.w)) * 0.52:
				continue
			var along := 1.0 - clampf((dy - car_h * 1.0) / (car_h * 6.5), 0.0, 1.0)
			var lateral := 1.0 - clampf(dx / maxf(1.0, lane_w * 0.85), 0.0, 1.0)
			best = maxf(best, along * lateral)
	slip = lerpf(slip, best, minf(1.0, dt * (3.6 if best > slip else 2.4)))
	if slip > 0.32 and not braking:
		# Accumulate fractions; round only when presenting the total score.
		bonus += 120.0 * slip * dt
	if not tutorial_mode and not crashed:
		if slip >= 0.30 and not braking and not boosting:
			var rate := (0.68 + 0.52 * slip) * slingshot_rate_mult
			var was_ready := slingshot_charge >= 0.99
			slingshot_charge = minf(1.0, slingshot_charge + dt * rate)
			slingshot_grace = 0.45
			if not was_ready and slingshot_charge >= 0.99:
				_slingshot_notified = true
				Sfx.slingshot_ready()
				slingshot_ready.emit()
		else:
			if slingshot_grace > 0.0:
				slingshot_grace = maxf(0.0, slingshot_grace - dt)
			else:
				slingshot_charge = maxf(0.0, slingshot_charge - dt * 0.95)
				if slingshot_charge < 0.90:
					_slingshot_notified = false


func _update_cutin(dt: float) -> void:
	if _cutin_window <= 0.0:
		return
	_cutin_window = maxf(0.0, _cutin_window - dt)
	var target_x := _lane_x(lane)
	if absf(player_x - target_x) > lane_w * 0.38:
		return
	for c in cars:
		if int(c.get("lane", -1)) != lane or bool(c.get("cutin", false)) or bool(c.get("near", false)):
			continue
		var gap := (float(c.y) - float(c.h) * 0.5) - (player_y + car_h * 0.5)
		if gap < 5.0 or gap > CUTIN_MAX_GAP * cutin_gap_mult:
			continue
		# Compare against the car's actual speed, not its theoretical target:
		# a chasing car that is still closing the gap has not been overtaken.
		var traffic_speed := float(c.get("cur_speed", float(c.get("rel", 0.7)) * lerpf(base_speed, top_speed, clampf(t / 70.0, 0.0, 1.0))))
		if speed < traffic_speed + 15.0:
			continue
		c["cutin"] = true
		c["near"] = true
		near += 1
		combo += 1
		combo_t = 3.2
		var mult := _effective_score_mult()
		bonus += 45 * combo * mult
		var seg_gain := (NITRO_SEG if gap <= 130.0 * cutin_gap_mult else (NITRO_SEG * 0.5)) * cutin_nitro_mult
		if nitro >= max_nitro - 0.001:
			bonus += 250 * combo * mult
			pickup_coins += 5
		else:
			nitro = minf(max_nitro, nitro + seg_gain)
		cut_in.emit(combo)
		for i in range(14):
			particles.append({
				"p": Vector2(player_x + randf_range(-car_w * 0.35, car_w * 0.35), player_y + car_h * 0.45),
				"v": Vector2(randf_range(-160.0, 160.0), randf_range(90.0, 260.0)),
				"life": randf_range(0.25, 0.55),
				"max": 0.55,
				"col": Color(1.0, 0.85, 0.35),
				"size": randf_range(2.5, 5.5),
			})
		_cutin_window = 0.0
		return


func _update_rear_spawning(dt: float, ref_speed: float) -> void:
	if braking and not overheated and speed > 40.0:
		_rear_spawn_t -= dt
		if _rear_spawn_t <= 0.0:
			if _spawn_rear(ref_speed):
				_rear_spawn_t = _rfr(0.55, 0.90)
			else:
				_rear_spawn_t = 0.20
	else:
		_rear_spawn_t = 0.40


func _spawn_rear(ref_speed: float) -> bool:
	if cars.size() > 16:
		return false
	var chosen := -1
	for attempt in range(20):
		var l := _ri() % LANES
		if l == free_lane or l == closed_lane:
			continue
		var blocked := false
		for c in cars:
			if int(c.lane) == l and float(c.y) > H - 180.0 and float(c.y) < H + 260.0:
				blocked = true
				break
		if not blocked:
			chosen = l
			break
	if chosen < 0:
		return false

	var type := _pick_traffic_type()
	var kind := int(type.kind)
	var w := car_w * float(type.w)
	var h := car_h * float(type.h)
	var target_rel := _rfr(float(type.rel[0]), float(type.rel[1]))
	var col: Color = TRAFFIC_COLORS[_ri() % TRAFFIC_COLORS.size()]
	var entry := {
		"lane": chosen,
		"x": _lane_x(chosen),
		"y": H + h * 0.5 + 40.0,
		"w": w,
		"h": h,
		"kind": kind,
		"color": col,
		"rel": target_rel,
		"cur_speed": target_rel * ref_speed,
		"braking": false,
		"demo_speed": _rfr(280.0, 460.0),
		"near": false,
		"cutin": false,
		"from_rear": true,
		"stripe": false,
		"wing": false,
		"rails": false,
		"roof_sign": false,
		"cargo": false,
		"stripe_color": _traffic_stripe(col),
		"silhouette": _traffic_silhouette(kind),
	}
	match kind:
		0:
			entry["stripe"] = _rf() < 0.35
			if entry["stripe"] and _rf() < 0.18:
				entry["wing"] = true
			entry["roof_sign"] = _rf() < 0.06
		1:
			entry["rails"] = true
		2:
			entry["trailer"] = TRAILER_COLORS[_ri() % TRAILER_COLORS.size()]
		4:
			entry["accent"] = BUS_ACCENTS[_ri() % BUS_ACCENTS.size()]
		5:
			entry["stripe"] = true
			entry["wing"] = _rf() < 0.75
		6:
			entry["cargo"] = _rf() < 0.6
	entry.merge(PALETTE.pick(str(entry.silhouette), col), true)
	if use_3d_cars and race_art != null:
		race_art.take(entry)
	cars.append(entry)
	return true


# --- tutorial rewind --------------------------------------------------------

func _snapshot_state() -> Dictionary:
	var car_copy: Array = []
	for c in cars:
		car_copy.append(c.duplicate())
	var item_copy: Array = []
	for it in items:
		item_copy.append(it.duplicate())
	return {
		"scroll": scroll,
		"t": t,
		"distance": distance,
		"score": score,
		"bonus": bonus,
		"near": near,
		"pickup_coins": pickup_coins,
		"combo": combo,
		"combo_t": combo_t,
		"nitro": nitro,
		"speed": speed,
		"lane": lane,
		"player_x": player_x,
		"player_tilt": player_tilt,
		"cutin_window": _cutin_window,
		"cutin_lane": _cutin_lane,
		"braking": braking,
		"boost_t": boost_t,
		"boosting": boosting,
		"spawn_t": spawn_t,
		"item_t": item_t,
		"free_lane": free_lane,
		"free_t": free_t,
		"cars": car_copy,
		"items": item_copy,
		"brake_heat": brake_heat,
		"overheated": overheated,
		"slip": slip,
		"aquaplane_t": aquaplane_t,
	}


func _record_rewind_snapshot(dt: float) -> void:
	_snapshot_t += dt
	if _snapshot_t < 0.08:
		return
	_snapshot_t = 0.0
	rewind_frames.append(_snapshot_state())
	while rewind_frames.size() > 36:
		rewind_frames.pop_front()


func _apply_snapshot(s: Dictionary) -> void:
	scroll = float(s.scroll)
	t = float(s.t)
	distance = float(s.distance)
	score = float(s.score)
	bonus = float(s.bonus)
	near = int(s.near)
	pickup_coins = int(s.pickup_coins)
	combo = int(s.combo)
	combo_t = float(s.combo_t)
	nitro = float(s.nitro)
	speed = float(s.speed)
	lane = int(s.lane)
	player_x = float(s.player_x)
	player_tilt = float(s.player_tilt)
	_cutin_window = float(s.get("cutin_window", 0.0))
	_cutin_lane = int(s.get("cutin_lane", -1))
	braking = bool(s.braking)
	boost_t = float(s.boost_t)
	boosting = bool(s.boosting)
	spawn_t = float(s.spawn_t)
	item_t = float(s.item_t)
	free_lane = int(s.free_lane)
	free_t = float(s.free_t)
	cars = s.cars
	items = s.items
	brake_heat = float(s.brake_heat)
	overheated = bool(s.overheated)
	slip = float(s.slip)
	aquaplane_t = float(s.get("aquaplane_t", 0.0))


func _begin_rewind() -> void:
	if rewinding:
		return
	crashed = true
	running = false
	boosting = false
	braking = false
	boost_t = 0.0
	shake = 26.0
	flash = 0.6
	Sfx.crash()
	for i in range(18):
		particles.append({
			"p": Vector2(player_x + randf_range(-30.0, 30.0), player_y + randf_range(-40.0, 20.0)),
			"v": Vector2(randf_range(-280.0, 280.0), randf_range(-360.0, 100.0)),
			"life": randf_range(0.35, 0.8),
			"max": 0.8,
			"col": [Color(1.0, 0.72, 0.28), Color(0.92, 0.92, 0.9), Color(0.72, 0.22, 0.16)][randi() % 3],
			"size": randf_range(2.0, 5.0),
		})
	rewinding = true
	if rewind_frames.is_empty():
		rewind_frames.append(_snapshot_state())
	_rewind_step_t = 0.0
	rewind_started.emit()


func _tick_rewind(dt: float) -> void:
	if not rewinding:
		return
	if not tutorial_mode and not demo:
		duel_clock += dt
		_ghost_rec_t += dt
		if _ghost_rec_t >= 0.20:
			_ghost_rec_t -= 0.20
			_record_ghost_sample(false)
		_update_ghost_duel()
	shake = maxf(0.0, shake - dt * 38.0)
	flash = maxf(0.0, flash - dt * 2.0)
	_rewind_step_t += dt
	while _rewind_step_t >= 0.030 and not rewind_frames.is_empty():
		_apply_snapshot(rewind_frames.pop_back())
		_rewind_step_t -= 0.030
	if rewind_frames.is_empty():
		_finish_rewind()


func _finish_rewind() -> void:
	_fx_emission_t = 0.0
	rewinding = false
	crashed = false
	running = true
	boosting = false
	braking = false
	boost_t = 0.0
	slingshot_t = 0.0
	slingshot_charge = 0.0
	slingshot_grace = 0.0
	_slingshot_notified = false
	ram_charges = 0
	_nitro_cooldown = 0.0
	if _shield_active and _shield_post_nitro >= 0.0:
		nitro = _shield_post_nitro
	_shield_active = false
	_shield_post_nitro = -1.0
	brake_heat = minf(brake_heat, 0.18)
	overheated = false
	slip = 0.0
	_rewind_invuln = 1.60 if not tutorial_mode else 1.35
	particles.clear()
	spawn_t = maxf(spawn_t, 0.8)
	if closed_lane >= 0 and lane == closed_lane:
		lane = 1 if closed_lane == 0 else LANES - 2
		player_x = _lane_x(lane)
	for c in cars:
		if absf(float(c.x) - player_x) < lane_w * 0.85:
			if float(c.y) > player_y - 380.0 and float(c.y) < player_y + 160.0:
				c.y -= 480.0
	status_changed.emit(slip, brake_heat, overheated)
	hud_changed.emit(int(score), gauge_kmh(speed, base_speed, top_speed), nitro, combo, _coins_total(), boosting)
	_emit_challenge_hud()
	rewind_finished.emit()


func _update_weather(dt: float) -> void:
	# One full day/night cycle lasts DAY_LENGTH seconds, independent of runs.
	time_of_day = fposmod(time_of_day + dt / DAY_LENGTH, 1.0)

	weather_timer -= dt
	if weather_timer <= 0.0:
		_next_weather()

	var goal := _weather_targets()
	var rise := 1.0 - exp(-dt * 0.115)
	var fall := 1.0 - exp(-dt * 0.170)
	rain_amount = lerpf(rain_amount, float(goal[0]), rise if float(goal[0]) > rain_amount else fall)
	fog_amount = lerpf(fog_amount, float(goal[1]), rise if float(goal[1]) > fog_amount else fall)
	cloud_amount = lerpf(cloud_amount, float(goal[2]), 1.0 - exp(-dt * 0.130))
	storm_amount = lerpf(storm_amount, float(goal[3]), rise if float(goal[3]) > storm_amount else fall)

	# Road stays wet for a while after the rain stops.
	var wet_goal := clampf(rain_amount * 1.12 + storm_amount * 0.15, 0.0, 1.0)
	var wet_k := 0.16 if wet_goal > wetness else 0.035
	wetness = lerpf(wetness, wet_goal, 1.0 - exp(-dt * wet_k))

	wind = clampf(0.12 + rain_amount * 0.42 + storm_amount * 0.72 + cloud_amount * 0.10, 0.0, 1.2)

	Sfx.set_rain_intensity((rain_amount * 0.85 + storm_amount * 0.35) * (1.0 if running else 0.35))
	if Sfx.has_method("set_weather"):
		Sfx.set_weather(wetness, wind, storm_amount)

	# --- rain -------------------------------------------------------------
	# The wind vector below is the single source of truth for the rain:
	# render/weather_fx.gd moves every drop layer along it and derives the
	# streak angle from the very same pair, so what you see is what moved.
	# Gusts are a magnitude and never a sign, so the slant never "breathes"
	# in and out while the drops keep travelling one way.
	rain_gust = 0.80 + 0.14 * sin(t * 0.37) + 0.06 * sin(t * 1.31 + 1.7)
	var sim_speed := speed if running else DEMO_SPEED
	var wind_k := clampf(wind * 0.85, 0.0, 1.1)
	rain_vx = -(150.0 + 320.0 * wind_k + storm_amount * 120.0) * rain_gust
	rain_vy = (380.0 + sim_speed * 0.30) * (1.0 + wind * 0.06)
	if storm_amount > 0.28:
		lightning_next -= dt * (0.5 + storm_amount)
		if lightning_next <= 0.0:
			_strike_lightning()
			lightning_next = randf_range(4.0, 11.0)
	if thunder_delay > 0.0:
		thunder_delay -= dt
		if thunder_delay <= 0.0 and Sfx.has_method("thunder"):
			Sfx.thunder()
	lightning = maxf(0.0, lightning - dt * 3.6)


func _next_weather() -> void:
	var pool: Array = []
	match weather_state:
		WEATHER_CLEAR:
			pool = [WEATHER_CLOUDY, WEATHER_CLOUDY, WEATHER_RAIN, WEATHER_FOG]
		WEATHER_CLOUDY:
			pool = [WEATHER_CLEAR, WEATHER_RAIN, WEATHER_RAIN, WEATHER_FOG]
		WEATHER_RAIN:
			pool = [WEATHER_CLOUDY, WEATHER_STORM, WEATHER_STORM, WEATHER_FOG]
		WEATHER_STORM:
			pool = [WEATHER_RAIN, WEATHER_RAIN, WEATHER_CLOUDY]
		_:
			pool = [WEATHER_CLOUDY, WEATHER_CLEAR, WEATHER_RAIN]
	weather_state = int(pool[_ri() % pool.size()])
	match weather_state:
		WEATHER_CLEAR:
			weather_timer = _rfr(80.0, 125.0)
		WEATHER_CLOUDY:
			weather_timer = _rfr(65.0, 105.0)
		WEATHER_RAIN:
			weather_timer = _rfr(55.0, 88.0)
		WEATHER_STORM:
			weather_timer = _rfr(38.0, 66.0)
		_:
			weather_timer = _rfr(50.0, 82.0)


func _weather_targets() -> Array:
	match weather_state:
		WEATHER_CLOUDY:
			return [0.06, 0.08, 0.58, 0.0]
		WEATHER_RAIN:
			return [0.58, 0.26, 0.84, 0.0]
		WEATHER_STORM:
			return [1.0, 0.38, 0.96, 1.0]
		WEATHER_FOG:
			return [0.0, 0.82, 0.32, 0.0]
		_:
			return [0.0, 0.0, 0.05, 0.0]


func _strike_lightning() -> void:
	var x := randf_range(W * 0.12, W * 0.88)
	var y := -40.0
	var pts := PackedVector2Array([Vector2(x, y)])
	var bottom := randf_range(360.0, 900.0)
	while y < bottom:
		x = clampf(x + randf_range(-46.0, 46.0), 10.0, W - 10.0)
		y += randf_range(54.0, 118.0)
		pts.append(Vector2(x, y))
	lightning_bolt = pts
	lightning_branches.clear()
	for i in range(randi_range(2, 4)):
		if pts.size() < 3:
			break
		var root: Vector2 = pts[randi_range(1, pts.size() - 1)]
		var b := PackedVector2Array([root])
		var bx := root.x
		var by := root.y
		var steps := randi_range(2, 4)
		for j in range(steps):
			bx += randf_range(-70.0, 70.0)
			by += randf_range(30.0, 72.0)
			b.append(Vector2(clampf(bx, 0.0, W), by))
		lightning_branches.append(b)
	lightning = 1.0
	thunder_delay = randf_range(0.55, 1.7)


func _tick(dt: float) -> void:
	if paused:
		return

	_update_weather(dt)
	t += dt

	if demo:
		scroll += DEMO_SPEED * dt
		spawn_t -= dt
		if spawn_t <= 0.0:
			_spawn(true)
			spawn_t = randf_range(0.7, 1.4)
		_move_traffic(dt, 0.0, 0.0, true)
		_update_fx(dt)
		return

	if not running:
		_update_fx(dt)
		return

	if _nitro_cooldown > 0.0:
		_nitro_cooldown = maxf(0.0, _nitro_cooldown - dt)

	if boost_t > 0.0:
		boost_t -= dt
		if boost_t <= 0.0:
			boost_t = 0.0
			boosting = false
			_nitro_cooldown = 0.35

	if boost_t <= 0.0:
		ram_charges = 0

	if slingshot_t > 0.0:
		slingshot_t = maxf(0.0, slingshot_t - dt)

	if _rewind_invuln > 0.0:
		_rewind_invuln = maxf(0.0, _rewind_invuln - dt)

	if _puddle_cd > 0.0:
		_puddle_cd = maxf(0.0, _puddle_cd - dt)

	_update_brake_heat(dt)
	_update_slipstream(dt)

	if car_perk == "regen_brake" and braking and not overheated and not tutorial_mode and speed > 160.0:
		nitro = minf(max_nitro, nitro + dt * 0.28)

	var ramp := clampf(t / 70.0, 0.0, 1.0)
	var ref := lerpf(base_speed, top_speed, ramp)
	var want := ref
	if boosting:
		want *= 1.5
	if slingshot_t > 0.0:
		want *= SLINGSHOT_MULT
	if braking and not overheated:
		# Heat makes the pads fade before they lock out completely.
		want *= lerpf(BRAKE_MULT, BRAKE_MULT * 1.85, brake_heat)
	elif not braking:
		want *= 1.0 + SLIP_BONUS * slip
	var k := 2.4
	if braking and not overheated:
		k = 5.5
	elif boosting or slingshot_t > 0.0:
		k = 5.2
	if physics_version >= 2:
		_update_grip(dt)
		if braking and not overheated:
			k *= lerpf(1.0, grip_mu, BRAKE_GRIP_WEIGHT)
		# Exact exponential approach: the same speed curve at any frame rate.
		speed = lerpf(speed, want, 1.0 - exp(-dt * k))
	else:
		speed = lerpf(speed, want, minf(1.0, dt * k))

	var cur_kmh := gauge_kmh(speed, base_speed, top_speed)
	hyperdrive_active = (car_perk == "hyperdrive") and (cur_kmh >= 310) and not braking and not crashed and not tutorial_mode

	var travel := speed * dt
	scroll += travel
	var dist_delta := travel / 12.0
	distance += dist_delta

	var target_x := _lane_x(lane)
	var handle_k := handling if time_scale >= 0.9 else handling * (1.0 / maxf(0.12, time_scale))
	if physics_version >= 2:
		# Lane changes on a wet road are a touch slower, and the tail steps out
		# (a larger body yaw); aquaplaning briefly takes most of the steering.
		handle_k *= lerpf(1.0, grip_mu, STEER_GRIP_WEIGHT)
		if aquaplane_t > 0.0:
			handle_k *= 0.5
		player_x = lerpf(player_x, target_x, 1.0 - exp(-dt * handle_k))
		var yaw := 0.0022 * (1.0 + (1.0 - grip_mu) * 1.6)
		var yaw_max := 0.10 + (1.0 - grip_mu) * 0.08
		player_tilt = lerpf(player_tilt, clampf((target_x - player_x) * yaw, -yaw_max, yaw_max), 1.0 - exp(-dt * 9.0 * (2.5 if time_scale < 0.5 else 1.0)))
	else:
		player_x = lerpf(player_x, target_x, minf(1.0, dt * handle_k))
		player_tilt = lerpf(player_tilt, clampf((target_x - player_x) * 0.0022, -0.10, 0.10), minf(1.0, dt * 9.0 * (2.5 if time_scale < 0.5 else 1.0)))

	if combo_t > 0.0:
		combo_t -= dt
		if combo_t <= 0.0:
			combo = 0
			combo_t = 0.0

	free_t -= dt
	if free_t <= 0.0:
		_rotate_free_lane()

	spawn_t -= dt
	if spawn_t <= 0.0:
		_spawn(false)
		spawn_t = maxf(0.52, 0.95 - t * 0.008)

	item_t -= dt
	if item_t <= 0.0:
		_spawn_item()
		item_t = _rfr(1.7, 3.1)

	if not tutorial_mode:
		duel_clock += dt
		_ghost_rec_t += dt
		if _ghost_rec_t >= 0.20:
			_ghost_rec_t -= 0.20
			_record_ghost_sample(false)
		_update_road_events(dt, travel)
		_update_traffic_signals(dt)
		_check_offroad_puddles()
		_update_ghost_duel()

	_update_rear_spawning(dt, ref)
	_move_traffic(dt, speed, ref, false)
	if rewinding or crashed:
		return
	_update_cutin(dt)
	_move_items(dt)
	_update_fx(dt)

	if running and not crashed:
		_record_rewind_snapshot(dt)

	var mult := _effective_score_mult()
	if mult > 1 and not tutorial_mode:
		bonus += dist_delta * float(mult - 1)
	score = floor(distance) + float(bonus)
	hud_changed.emit(int(score), gauge_kmh(speed, base_speed, top_speed), nitro, combo, _coins_total(), boosting)
	status_changed.emit(slip, brake_heat, overheated)
	_emit_challenge_hud()


# --- tyre grip (physics version 2) ---------------------------------------------

# Grip coefficient for a surface state. Pure function: depends only on the
# weather state (driven by run_rng) and on where the car is on the road.
static func surface_mu(wet: float, depth: float, aquaplaning: bool) -> float:
	var mu := lerpf(MU_DRY, MU_WET, clampf(wet, 0.0, 1.0))
	if depth > 0.0:
		mu = minf(mu, lerpf(MU_WET, MU_PUDDLE, clampf(depth, 0.0, 1.0)))
	if aquaplaning:
		mu = minf(mu, MU_AQUAPLANE)
	return mu


# Water depth (0..1) at a screen point: puddles are fixed on the road, so the
# answer only depends on the scroll, the position and how much it has rained.
func puddle_depth_at(x: float, y: float) -> float:
	var fill := clampf((wetness - 0.25) / 0.5, 0.0, 1.0)
	if fill <= 0.0:
		return 0.0
	var best := 0.0
	for p in puddles:
		var base_y := fposmod(float(p.y) + scroll, ROAD_CYCLE)
		for k in [-1.0, 0.0, 1.0]:
			var dy: float = (base_y + k * ROAD_CYCLE - y) / maxf(1.0, float(p.ry) * 0.85)
			if absf(dy) >= 1.0:
				continue
			var dx := (road_x + road_w * float(p.x) - x) / maxf(1.0, float(p.rx) * 0.9 + car_w * 0.25)
			var q := dx * dx + dy * dy
			if q < 1.0:
				best = maxf(best, (1.0 - q) * fill)
	return best


func _update_grip(dt: float) -> void:
	puddle_depth = puddle_depth_at(player_x, player_y)
	if aquaplane_t > 0.0:
		aquaplane_t = maxf(0.0, aquaplane_t - dt)
	# Deep water at speed lifts the tyres for a moment.
	if puddle_depth > 0.45 and speed > top_speed * 0.8 and aquaplane_t <= 0.0:
		aquaplane_t = AQUAPLANE_TIME
	grip_mu = surface_mu(wetness, puddle_depth, aquaplane_t > 0.0)


func _rotate_free_lane() -> void:
	var nl := free_lane
	for attempt in range(12):
		var cand := _ri() % LANES
		if cand != free_lane and cand != closed_lane:
			nl = cand
			break
	if nl == closed_lane:
		nl = 1 if closed_lane == 0 else LANES - 2
	free_lane = nl
	free_t = _rfr(6.0, 9.0)


func _move_traffic(dt: float, player_speed: float, ref_speed: float, is_demo: bool) -> void:
	if is_demo:
		for i in range(cars.size() - 1, -1, -1):
			var c: Dictionary = cars[i]
			c.y += float(c.demo_speed) * dt
			if c.y > H + 340.0:
				cars.remove_at(i)
		return

	var py := player_y
	for i in range(cars.size() - 1, -1, -1):
		var c: Dictionary = cars[i]
		if bool(c.get("rammed", false)):
			c.x = float(c.x) + float(c.get("ram_vx", 360.0)) * dt
			c.y = float(c.y) + float(c.get("ram_vy", -240.0)) * dt
			c["ram_rot"] = float(c.get("ram_rot", 0.0)) + float(c.get("ram_spin", 7.0)) * dt
			if float(c.x) < -240.0 or float(c.x) > W + 240.0 or float(c.y) < -400.0 or float(c.y) > H + 340.0:
				cars.remove_at(i)
			continue
		if float(c.get("lane_move_t", 0.0)) > 0.0:
			c["lane_move_t"] = maxf(0.0, float(c.lane_move_t) - dt)
			c.x = lerpf(float(c.x), _lane_x(int(c.lane)), minf(1.0, dt * 6.5))
			if float(c.lane_move_t) <= 0.0:
				c["signal_dir"] = 0
		var desired_speed: float = float(c.get("rel", 0.72)) * ref_speed
		var target_speed := desired_speed
		var wants_brake := false

		# 1. Check for lead traffic car directly ahead in same lane
		var lead_gap := 9999.0
		var lead_spd := desired_speed
		for c2 in cars:
			if c2 == c:
				continue
			if absf(float(c2.x) - float(c.x)) < lane_w * 0.65:
				if float(c2.y) < float(c.y):
					var g: float = (float(c.y) - float(c.h) * 0.5) - (float(c2.y) + float(c2.h) * 0.5)
					if g > -10.0 and g < lead_gap:
						lead_gap = g
						lead_spd = float(c2.get("cur_speed", float(c2.rel) * ref_speed))

		if lead_gap < 360.0:
			if float(c.get("cur_speed", desired_speed)) > lead_spd - 25.0 or lead_gap < 220.0:
				wants_brake = true
				if lead_gap > 90.0:
					var k_gap := (lead_gap - 90.0) / 270.0
					target_speed = minf(target_speed, lerpf(lead_spd * 0.88, lead_spd, k_gap))
				else:
					target_speed = minf(target_speed, minf(lead_spd * 0.82, lead_spd - 40.0))
			# Enforce traffic physical clearance so cars never pass through each other
			var min_lead_gap := 18.0
			if lead_gap < min_lead_gap:
				c.y = float(c.y) + (min_lead_gap - lead_gap)
				c["cur_speed"] = minf(float(c.get("cur_speed", desired_speed)), lead_spd)

		# 2. Check for player ahead in the same lane (traffic braking behind player)
		if float(c.y) > py and absf(float(c.x) - player_x) < lane_w * 0.72:
			var p_gap: float = (float(c.y) - float(c.h) * 0.5) - (py + car_h * 0.5)
			if p_gap > 0.0 and p_gap < 440.0:
				if player_speed < float(c.get("cur_speed", desired_speed)) + 25.0 or braking or p_gap < 240.0:
					wants_brake = true
					if p_gap > 110.0:
						var k_pgap := (p_gap - 110.0) / 330.0
						target_speed = minf(target_speed, lerpf(player_speed * 0.88, player_speed, k_pgap))
					else:
						target_speed = minf(target_speed, minf(player_speed * 0.82, player_speed - 40.0))
				var p_min_gap := 24.0
				if p_gap < p_min_gap:
					c.y = py + (car_h + float(c.h)) * 0.5 + p_min_gap
					c["cur_speed"] = minf(float(c.get("cur_speed", desired_speed)), player_speed)

		# Update speed and braking state
		c["braking"] = wants_brake
		var current_spd: float = float(c.get("cur_speed", desired_speed))
		if wants_brake:
			current_spd = lerpf(current_spd, target_speed, minf(1.0, dt * 6.5))
		else:
			current_spd = lerpf(current_spd, desired_speed, minf(1.0, dt * 2.5))
		c["cur_speed"] = current_spd

		# Move car relative to player
		var prev_y: float = float(c.y)
		c.y = float(c.y) + (player_speed - current_spd) * dt

		if float(c.y) > H + 340.0 or float(c.y) < -900.0:
			cars.remove_at(i)
			continue

		var pw := car_w * 0.78 * hitbox_w_mult
		var ph := car_h * 0.80
		var cw: float = float(c.w) * 0.78
		var ch: float = float(c.h) * 0.80
		if _rewind_invuln <= 0.0 and absf(float(c.x) - player_x) < (pw + cw) * 0.5 and absf(float(c.y) - py) < (ph + ch) * 0.5:
			var dy := float(c.y) - py
			if not tutorial_mode and boosting and car_perk == "ram_nitro" and ram_charges > 0 and not (int(c.get("kind", 0)) in [2, 4]):
				ram_charges -= 1
				var side_dir := 1.0 if float(c.x) >= player_x else -1.0
				c["rammed"] = true
				c["ram_vx"] = side_dir * 720.0
				c["ram_vy"] = -380.0
				c["ram_spin"] = side_dir * 8.5
				c["ram_rot"] = 0.0
				var ram_pts := 250 * _effective_score_mult()
				bonus += ram_pts
				shake = maxf(shake, 16.0)
				flash = maxf(flash, 0.25)
				Sfx.ram_hit()
				if contact_fx != null:
					contact_fx.spark_burst(Vector2((player_x + float(c.x)) * 0.5, (py + float(c.y)) * 0.5), Vector2(side_dir, -0.4), 1.1)
				for k in range(22):
					particles.append({
						"p": Vector2((player_x + float(c.x)) * 0.5, (py + float(c.y)) * 0.5),
						"v": Vector2(side_dir * randf_range(120.0, 440.0), randf_range(-340.0, 120.0)),
						"life": randf_range(0.28, 0.62),
						"max": 0.62,
						"col": Color(1.0, 0.78, 0.26) if k % 2 == 0 else Color(0.95, 0.96, 1.0),
						"size": randf_range(2.5, 5.5),
					})
				ram_used.emit(ram_pts)
				continue
			if dy > car_h * 0.18:
				# Bumper bump: arcade knock from trailing car without instant death
				Sfx.bump()
				shake = maxf(shake, 7.5)
				if contact_fx != null:
					contact_fx.spark_burst(Vector2(player_x, py + car_h * 0.46), Vector2(0.0, 1.0), 0.45)
				speed = maxf(speed, player_speed + 75.0)
				c.y = py + (ph + ch) * 0.5 + 4.0
				c["braking"] = true
				c["cur_speed"] = minf(float(c.get("cur_speed", desired_speed)), speed * 0.60)
				for k in range(5):
					particles.append({
						"p": Vector2(player_x + randf_range(-car_w * 0.25, car_w * 0.25), py + car_h * 0.46),
						"v": Vector2(randf_range(-60.0, 60.0), randf_range(40.0, 120.0)),
						"life": randf_range(0.20, 0.40),
						"max": 0.40,
						"col": Color(0.85, 0.85, 0.85, 0.6),
						"size": randf_range(2.0, 4.0),
					})
			else:
				_crash()
				return

		if not c.get("near", false) and prev_y < py and float(c.y) >= py:
			# Traffic passing us: pan the swish to the side it went by, and make
			# it louder the closer it clipped us. This is the main cue that tells
			# the player where the gaps actually are.
			var side := clampf((float(c.x) - player_x) / maxf(1.0, lane_w), -1.0, 1.0)
			var closeness := clampf(1.0 - absf(float(c.x) - player_x) / (lane_w * 2.2), 0.0, 1.0)
			if Sfx.has_method("pass_by"):
				Sfx.pass_by(side, closeness)
			elif Sfx.has_method("whoosh"):
				Sfx.whoosh(side)
			if absf(float(c.x) - player_x) < lane_w * 1.22:
				c["near"] = true
				near += 1
				combo += 1
				combo_t = 2.6
				bonus += 10 * combo * _effective_score_mult()
				near_miss.emit(combo)


func _move_items(dt: float) -> void:
	var pull_mult := 1.25 if car_perk == "taxi_magnet" else 1.0
	for i in range(items.size() - 1, -1, -1):
		var it: Dictionary = items[i]
		it.y += speed * dt
		it.phase += dt
		if car_perk == "taxi_magnet" and int(it.kind) == 0 and dt > 0.0:
			var dx := player_x - float(it.x)
			var dy := player_y - float(it.y)
			if absf(dx) < lane_w * 1.65 and absf(dy) < car_h * 1.85:
				var pull := Vector2(dx, dy).normalized()
				it.x = float(it.x) + pull.x * 920.0 * dt
				it.y = float(it.y) + pull.y * 540.0 * dt
		if it.y > H + 110.0:
			items.remove_at(i)
			continue
		if absf(float(it.x) - player_x) < car_w * 0.60 * pull_mult and absf(float(it.y) - player_y) < car_h * 0.62 * pull_mult:
			if int(it.kind) == 0:
				pickup_coins += 12
				pickup_taken.emit(0)
			else:
				nitro = minf(max_nitro, nitro + 0.20)
				pickup_taken.emit(1)
			items.remove_at(i)


func _spawn_item() -> void:
	if items.size() > 3:
		return
	var chosen := -1
	for attempt in range(14):
		var l := _ri() % LANES
		if l == closed_lane:
			continue
		var blocked := false
		for c in cars:
			if int(c.lane) == l and float(c.y) < 420.0:
				blocked = true
				break
		if blocked:
			continue
		for it in items:
			if int(it.lane) == l:
				blocked = true
				break
		if not blocked:
			chosen = l
			break
	if chosen < 0:
		return
	items.append({
		"lane": chosen,
		"x": _lane_x(chosen),
		"y": -50.0,
		"kind": 1 if _rf() < 0.18 else 0,
		"phase": _rf() * 4.0,
	})


func _pick_traffic_type() -> Dictionary:
	var roll := _rf()
	var acc := 0.0
	for tp in TRAFFIC_TYPES:
		acc += float(tp.weight)
		if roll <= acc:
			return tp
	return TRAFFIC_TYPES[TRAFFIC_TYPES.size() - 1]


func _traffic_stripe(body: Color) -> Color:
	if body.v > 0.55:
		return Color(0.12, 0.13, 0.15)
	return Color(0.94, 0.93, 0.90)


# Every traffic kind resolves to a dedicated model; passenger cars also vary
# between hatchback and sedan. The same descriptors feed the 2D fallback.
func _traffic_silhouette(kind: int) -> String:
	match kind:
		0:
			return ["hatch", "hatch", "sedan", "sedan", "ev"][_ri() % 5]
		1:
			return "offroad"
		2:
			return "truck"
		3:
			return "van"
		4:
			return "bus"
		5:
			return ["sport", "sport", "sport", "muscle", "muscle", "hyper"][_ri() % 6]
		6:
			return "pickup"
	return ""


func _spawn(is_demo: bool) -> void:
	if cars.size() > 9:
		return
	var top_count := 0
	for c in cars:
		if c.y < 620.0:
			top_count += 1
	if top_count >= 3:
		return

	var chosen := -1
	for attempt in range(20):
		var l := _ri() % LANES
		if not is_demo and (l == free_lane or l == closed_lane):
			continue
		var blocked := false
		for c in cars:
			if int(c.lane) == l and float(c.y) < 660.0:
				blocked = true
				break
		if not blocked:
			chosen = l
			break
	if chosen < 0:
		return

	var type := _pick_traffic_type()
	var kind := int(type.kind)
	var w := car_w * float(type.w)
	var h := car_h * float(type.h)
	var rel := _rfr(float(type.rel[0]), float(type.rel[1]))
	var col: Color = TRAFFIC_COLORS[_ri() % TRAFFIC_COLORS.size()]
	var entry := {
		"lane": chosen,
		"x": _lane_x(chosen),
		"y": -h * 0.75,
		"w": w,
		"h": h,
		"kind": kind,
		"color": col,
		"rel": rel,
		"cur_speed": rel * (lerpf(base_speed, top_speed, clampf(t / 70.0, 0.0, 1.0)) if running else DEMO_SPEED),
		"braking": false,
		"demo_speed": _rfr(250.0, 420.0),
		"near": false,
		"cutin": false,
		"stripe": false,
		"wing": false,
		"rails": false,
		"roof_sign": false,
		"cargo": false,
		"stripe_color": _traffic_stripe(col),
		"silhouette": _traffic_silhouette(kind),
	}
	match kind:
		0:
			entry["stripe"] = _rf() < 0.35
			if entry["stripe"] and _rf() < 0.18:
				entry["wing"] = true
			entry["roof_sign"] = _rf() < 0.06
		1:
			entry["rails"] = true
		2:
			entry["trailer"] = TRAILER_COLORS[_ri() % TRAILER_COLORS.size()]
		4:
			entry["accent"] = BUS_ACCENTS[_ri() % BUS_ACCENTS.size()]
		5:
			entry["stripe"] = true
			entry["wing"] = _rf() < 0.75
		6:
			entry["cargo"] = _rf() < 0.6
	entry.merge(PALETTE.pick(str(entry.silhouette), col), true)
	if use_3d_cars and race_art != null:
		race_art.take(entry)
	cars.append(entry)


func _crash(allow_shield := true) -> void:
	if crashed:
		return
	if tutorial_mode:
		_begin_rewind()
		return
	if allow_shield and not rewinding and _rewind_invuln <= 0.0 and nitro >= 1.0 - 0.002 and not rewind_frames.is_empty():
		_shield_post_nitro = maxf(0.0, nitro - 1.0)
		_shield_active = true
		nitro = _shield_post_nitro
		Sfx.shield_trigger()
		chrono_shield_triggered.emit()
		_begin_rewind()
		return
	_record_ghost_sample(true)
	_revive_eligible = allow_shield
	crashed = true
	running = false
	boosting = false
	braking = false
	boost_t = 0.0
	slingshot_t = 0.0
	ram_charges = 0
	hyperdrive_active = false
	shake = 24.0
	flash = 0.7
	for i in range(30):
		particles.append({
			"p": Vector2(player_x + randf_range(-26.0, 26.0), player_y + randf_range(-40.0, 20.0)),
			"v": Vector2(randf_range(-330.0, 330.0), randf_range(-430.0, 120.0)),
			"life": randf_range(0.45, 1.1),
			"max": 1.1,
			"col": [Color(1.0, 0.72, 0.28), Color(0.92, 0.92, 0.9), Color(0.72, 0.22, 0.16)][randi() % 3],
			"size": randf_range(2.0, 6.0),
		})
	run_ended.emit(int(score), int(distance), near, _coins_total())


func _update_fx(dt: float) -> void:
	shake = maxf(0.0, shake - dt * 42.0)
	flash = maxf(0.0, flash - dt * 2.2)
	var damping := pow(0.985, dt * 60.0)
	for i in range(particles.size() - 1, -1, -1):
		var p: Dictionary = particles[i]
		p.life -= dt
		if p.life <= 0.0:
			particles.remove_at(i)
			continue
		p.p += p.v * dt
		p.v.y += 640.0 * dt
		p.v *= damping

	# Preserve the original 60 Hz effect density at every display frame rate.
	_fx_emission_t += dt
	while _fx_emission_t + 0.000000001 >= FX_EMISSION_STEP:
		_fx_emission_t = maxf(0.0, _fx_emission_t - FX_EMISSION_STEP)
		_emit_driving_particles()


func _emit_driving_particles() -> void:
	if braking and not overheated and running and not crashed and speed > 180.0 and randf() < 0.40:
		for side in [-1, 1]:
			particles.append({
				"p": Vector2(player_x + float(side) * car_w * 0.31, player_y + car_h * 0.36),
				"v": Vector2(randf_range(-16.0, 16.0), randf_range(30.0, 90.0)),
				"life": randf_range(0.24, 0.48),
				"max": 0.48,
				"col": Color(0.88, 0.90, 0.92, 0.42),
				"size": randf_range(3.5, 7.5),
			})
	if overheated and running and randf() < 0.55:
		for side in [-1, 1]:
			particles.append({
				"p": Vector2(player_x + float(side) * car_w * 0.30, player_y + car_h * 0.33),
				"v": Vector2(randf_range(-34.0, 34.0), randf_range(20.0, 95.0)),
				"life": randf_range(0.45, 0.95),
				"max": 0.95,
				"col": Color(0.86, 0.87, 0.87, 0.20),
				"size": randf_range(5.0, 11.0),
			})
	if slip > 0.35 and randf() < 0.35:
		particles.append({
			"p": Vector2(player_x + randf_range(-car_w * 0.45, car_w * 0.45), player_y - car_h * 0.55),
			"v": Vector2(randf_range(-20.0, 20.0), randf_range(-180.0, -80.0)),
			"life": randf_range(0.18, 0.36),
			"max": 0.36,
			"col": Color(0.78, 0.90, 1.0, 0.22),
			"size": randf_range(1.5, 3.5),
		})
	if rain_amount > 0.05 and running and not crashed and speed > 110.0 and randf() < (0.25 + rain_amount * 0.45):
		for side in [-1, 1]:
			var spray_spd := speed * 0.45
			particles.append({
				"p": Vector2(player_x + float(side) * car_w * 0.38 + randf_range(-4.0, 4.0), player_y + car_h * 0.44),
				"v": Vector2(float(side) * randf_range(15.0, 45.0), randf_range(spray_spd * 0.7, spray_spd * 1.3)),
				"life": randf_range(0.20, 0.42),
				"max": 0.42,
				"col": Color(0.82, 0.88, 0.94, 0.25 * rain_amount),
				"size": randf_range(2.5, 6.0),
			})


# A revive (rewarded ad) is possible after a fatal collision in a solo run:
# not in the tutorial, demo, duels or the Daily Challenge, and once per run.
func can_revive() -> bool:
	if not crashed or running or rewinding or demo or tutorial_mode:
		return false
	return _revive_eligible and not _revive_used and challenge_config.is_empty() and not rewind_frames.is_empty()


# Same rewind and invulnerability as the Chrono-Shield, from the crash state.
func revive() -> bool:
	if not can_revive():
		return false
	_revive_used = true
	_revive_eligible = false
	rewinding = true
	_rewind_step_t = 0.0
	rewind_started.emit()
	return true


func finish_run() -> void:
	if running:
		tutorial_mode = false
		_crash(false)


# --- traffic signals, road events, perks & ghost duel -----------------------

func _lane_wall_safe(y_center: float, adding_lane: int) -> bool:
	var occupied := {}
	occupied[adding_lane] = true
	if closed_lane >= 0:
		occupied[closed_lane] = true
	for c in cars:
		if bool(c.get("rammed", false)):
			continue
		if absf(float(c.y) - y_center) < 260.0:
			occupied[int(c.lane)] = true
	return occupied.size() < LANES


func _try_start_lane_change(c: Dictionary, force_fast := false) -> bool:
	if bool(c.get("rammed", false)) or int(c.get("signal_dir", 0)) != 0 or float(c.get("lane_move_t", 0.0)) > 0.0:
		return false
	var clane := int(c.get("lane", 0))
	var dirs := [-1, 1]
	if _rf() < 0.5:
		dirs = [1, -1]
	for d in dirs:
		var cand := clane + int(d)
		if cand < 0 or cand >= LANES or cand == closed_lane:
			continue
		var safe := true
		for c2 in cars:
			if c2 == c or bool(c2.get("rammed", false)):
				continue
			if int(c2.lane) == cand and absf(float(c2.y) - float(c.y)) < float(c.h) * 1.45 + float(c2.h) * 0.75:
				safe = false
				break
		if not safe:
			continue
		if not _lane_wall_safe(float(c.y), cand):
			continue
		c["signal_dir"] = int(d)
		c["signal_target"] = cand
		c["signal_t"] = 0.55 if force_fast else 1.25
		return true
	return false


func _update_traffic_signals(dt: float) -> void:
	for c in cars:
		if bool(c.get("rammed", false)):
			continue
		var st := float(c.get("signal_t", 0.0))
		if st > 0.0:
			st -= dt
			c["signal_t"] = st
			if st <= 0.0:
				var cand := int(c.get("signal_target", c.lane))
				var clear := cand >= 0 and cand < LANES and cand != closed_lane
				if clear:
					for c2 in cars:
						if c2 == c or bool(c2.get("rammed", false)):
							continue
						if int(c2.lane) == cand and absf(float(c2.y) - float(c.y)) < float(c.h) * 1.1 + float(c2.h) * 0.6:
							clear = false
							break
				if clear and _lane_wall_safe(float(c.y), cand):
					c["lane"] = cand
					c["lane_move_t"] = 0.72
				else:
					c["signal_dir"] = 0
					c["signal_t"] = 0.0

	# OFF-ROAD LED lightbar makes traffic ahead politely move aside if safe.
	if car_perk == "all_weather" and not crashed:
		for c in cars:
			if int(c.get("lane", -1)) == lane:
				var dy := player_y - float(c.y)
				if dy > car_h * 1.1 and dy < 420.0:
					_try_start_lane_change(c, true)

	_traffic_lc_t -= dt
	if _traffic_lc_t <= 0.0:
		_traffic_lc_t = _rfr(1.5, 2.7)
		var candidates: Array = []
		for c in cars:
			if bool(c.get("rammed", false)) or int(c.get("signal_dir", 0)) != 0 or float(c.get("lane_move_t", 0.0)) > 0.0:
				continue
			if int(c.get("kind", 0)) in [2, 4]:
				continue
			var cy := float(c.y)
			if cy > -60.0 and cy < player_y - car_h * 2.4:
				candidates.append(c)
		if not candidates.is_empty():
			var pick: Dictionary = candidates[_ri() % candidates.size()]
			_try_start_lane_change(pick, false)


func _check_offroad_puddles() -> void:
	if car_perk != "all_weather" or wetness <= 0.12 or _puddle_cd > 0.0 or crashed:
		return
	for p in puddles:
		var base_y := fposmod(float(p.y) + scroll, ROAD_CYCLE)
		for k in [-1, 0, 1]:
			var py: float = base_y + float(k) * ROAD_CYCLE
			if absf(py - player_y) < float(p.ry) * 0.85:
				var px := road_x + road_w * float(p.x)
				if absf(px - player_x) < float(p.rx) * 0.90 + car_w * 0.35:
					_puddle_cd = 1.25
					var pts := 85 * _effective_score_mult()
					bonus += pts
					nitro = minf(max_nitro, nitro + 0.08)
					Sfx.pickup_nitro()
					for s_i in range(10):
						particles.append({
							"p": Vector2(player_x + randf_range(-car_w * 0.35, car_w * 0.35), player_y + car_h * 0.3),
							"v": Vector2(randf_range(-160.0, 160.0), randf_range(60.0, 220.0)),
							"life": randf_range(0.22, 0.44),
							"max": 0.44,
							"col": Color(0.70, 0.88, 1.0, 0.65),
							"size": randf_range(2.5, 5.5),
						})
					road_event_banner.emit("СПЛЕШ В ЛУЖЕ!", "+%d ОЧКОВ · +НИТРО" % pts, Color("#5ce1e6"))
					return


func _update_road_events(dt: float, travel: float) -> void:
	if road_event_type == EVENT_NONE:
		blackout_amount = maxf(0.0, blackout_amount - dt * 1.4)
		score_mult = 1
		closed_lane = -1
		road_event_t -= dt
		if road_event_t <= 0.0:
			_start_next_road_event()
		return

	match road_event_type:
		EVENT_RADAR:
			blackout_amount = maxf(0.0, blackout_amount - dt * 1.4)
			score_mult = 1
			closed_lane = -1
			road_event.y = float(road_event.y) + travel
			var ry := float(road_event.y)
			if not bool(road_event.get("warned", false)) and ry > -980.0:
				road_event["warned"] = true
				var tgt := int(road_event.target_kmh)
				if str(road_event.mode) == "fast":
					road_event_banner.emit("РАДАР СКОРОСТИ!", "ПРОБЕЙ %d+ КМ/Ч" % tgt, Color("#5ce1e6"))
				else:
					road_event_banner.emit("КАМЕРА ТИХОГО ХОДА!", "СБРОСЬ ДО %d КМ/Ч" % tgt, Color("#f2b134"))
			if not bool(road_event.get("resolved", false)) and ry >= player_y:
				road_event["resolved"] = true
				var kmh := gauge_kmh(speed, base_speed, top_speed)
				var tgt := int(road_event.target_kmh)
				var ok := (kmh >= tgt) if str(road_event.mode) == "fast" else (kmh <= tgt)
				if ok:
					flash = maxf(flash, 0.30)
					pickup_coins += 25
					var pts := 300 * _effective_score_mult()
					bonus += pts
					Sfx.radar_ok()
					road_event_banner.emit("РАДАР ПРОЙДЕН!", "+25 МОНЕТ · +%d ОЧКОВ" % pts, Color("#5ddb75"))
				else:
					road_event_banner.emit("РАДАР НЕ ЗАСЧИТАН", "БЫЛО %d · ЦЕЛЬ %d КМ/Ч" % [kmh, tgt], Color("#9aa3ac"))
			if ry > H + 240.0:
				_end_road_event()
		EVENT_ROADWORKS:
			blackout_amount = maxf(0.0, blackout_amount - dt * 1.4)
			road_event.head_y = float(road_event.head_y) + travel
			var head_y := float(road_event.head_y)
			var taper_len := float(road_event.taper_len)
			var zone_len := float(road_event.zone_len)
			var tail_y := head_y - taper_len - zone_len
			var barrier_head := head_y - taper_len
			if not bool(road_event.get("warned", false)) and head_y > -950.0:
				road_event["warned"] = true
				road_event_banner.emit("ДОРОЖНЫЕ РАБОТЫ!", "СУЖЕНИЕ ПОЛОСЫ · ОЧКИ ×2", Color("#f2b134"))
			# Nudge traffic out of closed lane ahead of barrier
			for c in cars:
				if int(c.get("lane", -1)) == closed_lane and float(c.y) < barrier_head + 160.0 and float(c.y) > tail_y - 220.0:
					_try_start_lane_change(c, true)
			if head_y >= player_y - car_h * 0.5 and tail_y <= player_y + car_h * 0.5:
				score_mult = 2
			else:
				score_mult = 1
			# Taper cone warning bump
			if not bool(road_event.get("cone_hit", false)) and player_y <= head_y and player_y >= barrier_head:
				var frac := clampf((head_y - player_y) / maxf(1.0, taper_len), 0.0, 1.0)
				var edge_x := (road_x + 12.0) if closed_lane == 0 else (road_x + road_w - 12.0)
				var inner_x := (road_x + lane_w) if closed_lane == 0 else (road_x + road_w - lane_w)
				var cone_x := lerpf(edge_x, inner_x, frac)
				var hit_taper := (player_x - car_w * 0.36 < cone_x) if closed_lane == 0 else (player_x + car_w * 0.36 > cone_x)
				if hit_taper:
					road_event["cone_hit"] = true
					shake = maxf(shake, 8.5)
					speed *= 0.88
					Sfx.bump()
					if contact_fx != null:
						contact_fx.spark_burst(Vector2(cone_x, player_y - car_h * 0.35), Vector2(0.0, 1.0), 0.35)
					for k in range(10):
						particles.append({
							"p": Vector2(cone_x, player_y - car_h * 0.35),
							"v": Vector2(randf_range(-180.0, 180.0), randf_range(-140.0, 140.0)),
							"life": randf_range(0.22, 0.45),
							"max": 0.45,
							"col": Color(1.0, 0.52, 0.14),
							"size": randf_range(3.0, 6.0),
						})
			# Solid barrier collision
			if _rewind_invuln <= 0.0 and player_y + car_h * 0.36 >= tail_y and player_y - car_h * 0.36 <= barrier_head:
				if absf(player_x - _lane_x(closed_lane)) < lane_w * 0.42 + car_w * 0.34:
					_crash()
					return
			if tail_y > H + 200.0:
				_end_road_event()
		EVENT_BLACKOUT:
			road_event.time_left = float(road_event.time_left) - dt
			blackout_amount = lerpf(blackout_amount, 1.0, minf(1.0, dt * 2.2))
			score_mult = 2
			closed_lane = -1
			if float(road_event.time_left) <= 0.0:
				_end_road_event()


func _start_next_road_event() -> void:
	var pool := [EVENT_RADAR, EVENT_ROADWORKS, EVENT_BLACKOUT]
	if _last_event_type in pool:
		pool.erase(_last_event_type)
	var chosen := int(pool[_ri() % pool.size()])
	_last_event_type = chosen
	road_event_type = chosen
	match chosen:
		EVENT_RADAR:
			var is_fast := _rf() < 0.65
			var tgt := int(round(float(top_kmh(top_speed)) * 0.78 / 10.0) * 10.0) if is_fast else 175
			road_event = {
				"type": EVENT_RADAR,
				"mode": "fast" if is_fast else "slow",
				"target_kmh": tgt,
				"y": -1150.0,
				"warned": false,
				"resolved": false,
			}
		EVENT_ROADWORKS:
			closed_lane = 0 if _rf() < 0.5 else LANES - 1
			if free_lane == closed_lane:
				_rotate_free_lane()
			road_event = {
				"type": EVENT_ROADWORKS,
				"head_y": -1200.0,
				"taper_len": 440.0,
				"zone_len": 2600.0,
				"warned": false,
				"cone_hit": false,
			}
		EVENT_BLACKOUT:
			road_event = {
				"type": EVENT_BLACKOUT,
				"time_left": 10.5,
			}
			road_event_banner.emit("БЛЭКАУТ НА ТРАССЕ!", "ФАРЫ ВКЛЮЧЕНЫ · ОЧКИ ×2", Color("#7fc4ff"))


func _end_road_event() -> void:
	road_event_type = EVENT_NONE
	road_event.clear()
	score_mult = 1
	closed_lane = -1
	road_event_t = _rfr(20.0, 29.0)


func _record_ghost_sample(force := false) -> void:
	if tutorial_mode or demo:
		return
	if not force and ghost_rec.size() >= 3600:
		return
	var flags := 0
	if braking and not overheated:
		flags |= 1
	if boosting:
		flags |= 2
	if slingshot_t > 0.0:
		flags |= 4
	if rewinding:
		flags |= 8
	var x_norm := clampf((player_x - road_x) / maxf(1.0, road_w), 0.0, 1.0)
	ghost_rec.append({
		"scroll": scroll,
		"x_norm": x_norm,
		"flags": flags,
	})


func _update_ghost_duel() -> void:
	if str(challenge_config.get("type", "")) != "duel":
		return
	_ghost_state = ChallengeCodec.sample_ghost(challenge_config, duel_clock)
	var end_scroll := float(challenge_config.get("end_scroll", 0.0))
	if not _duel_passed_crash and end_scroll > 50.0 and scroll > end_scroll:
		_duel_passed_crash = true
		Sfx.record()
		duel_milestone.emit("crash_passed")
	var rival_score := int(challenge_config.get("score", 0))
	if not _duel_beaten_score and rival_score > 0 and int(floor(distance) + float(bonus)) > rival_score:
		_duel_beaten_score = true
		Sfx.duel_win()
		duel_milestone.emit("score_beaten")


func _emit_challenge_hud() -> void:
	if challenge_config.is_empty():
		challenge_hud_changed.emit({})
		return
	var ctype := str(challenge_config.get("type", ""))
	if ctype == "duel":
		var g_scroll := float(_ghost_state.get("scroll", 0.0))
		var gap_m := int(round((scroll - g_scroll) / 12.0))
		challenge_hud_changed.emit({
			"type": "duel",
			"name": str(challenge_config.get("name", "ДРУГ")),
			"rival_score": int(challenge_config.get("score", 0)),
			"gap_m": gap_m,
			"ghost_finished": bool(_ghost_state.get("finished", false)),
		})
	elif ctype == "daily":
		challenge_hud_changed.emit({
			"type": "daily",
			"bronze": int(challenge_config.get("bronze", 6500)),
			"silver": int(challenge_config.get("silver", 14500)),
			"gold": int(challenge_config.get("gold", 26000)),
		})


func build_challenge_payload(player_name: String) -> Dictionary:
	return {
		"seed": active_run_seed,
		"physics": physics_version,
		"car_index": car_index,
		"score": int(score),
		"distance": int(distance),
		"near": near,
		"tod": start_tod,
		"weather": start_weather,
		"step_ms": ChallengeCodec.BASE_STEP_MS,
		"end_time": duel_clock,
		"name": player_name,
		"samples": ghost_rec,
	}


# --- drawing ----------------------------------------------------------------

func _draw() -> void:
	var t_draw := Time.get_ticks_usec()
	draw_set_transform(Vector2(_sx, _sy))

	_draw_rails()
	_draw_cloud_shadows()
	_draw_scenery()
	_draw_road_event_under()
	_draw_cars()
	_draw_items()
	_draw_speed_streaks()
	_draw_road_event_over()
	_draw_rear_hazards()

	draw_set_transform(Vector2.ZERO)
	if flash > 0.01:
		draw_rect(Rect2(0.0, 0.0, W, H), Color(1.0, 1.0, 1.0, flash * 0.5))
	if rewinding:
		_draw_rewind_fx()
	draw_cpu_ms = float(Time.get_ticks_usec() - t_draw) / 1000.0


func _sample_sky(t: float) -> Array:
	var tt := fposmod(t, 1.0)
	for i in range(SKY_KEYS.size() - 1):
		var a: Array = SKY_KEYS[i]
		var b: Array = SKY_KEYS[i + 1]
		if tt >= float(a[0]) and tt <= float(b[0]):
			var span := maxf(0.0001, float(b[0]) - float(a[0]))
			var k := (tt - float(a[0])) / span
			k = k * k * (3.0 - 2.0 * k)
			return [
				Color(
					lerpf(float(a[1]), float(b[1]), k),
					lerpf(float(a[2]), float(b[2]), k),
					lerpf(float(a[3]), float(b[3]), k)
				),
				lerpf(float(a[4]), float(b[4]), k),
			]
	return [Color.WHITE, 0.0]


func get_sky_ambient() -> Color:
	var sky := _sample_sky(time_of_day)
	var amb: Color = sky[0]
	# Overcast, rain and storm all flatten and cool the light.
	var dim := 1.0 - cloud_amount * 0.19 - rain_amount * 0.08 - storm_amount * 0.15 - fog_amount * 0.09
	dim = clampf(dim, 0.34, 1.12)
	var cool := rain_amount * 0.10 + storm_amount * 0.16
	return Color(
		clampf(amb.r * (dim - cool * 0.30), 0.0, 1.3),
		clampf(amb.g * (dim - cool * 0.08), 0.0, 1.3),
		clampf(amb.b * (dim + cool * 0.22), 0.0, 1.3)
	)


func get_night_factor() -> float:
	return float(_sample_sky(time_of_day)[1])


func get_light_factor() -> float:
	# Headlights come on at dusk, in rain, fog, storms and blackouts.
	return clampf(maxf(get_night_factor(), maxf(blackout_amount * 0.90, maxf(fog_amount * 0.68, maxf(rain_amount * 0.42, storm_amount * 0.52)))), 0.0, 1.0)


func get_weather_name() -> String:
	match weather_state:
		WEATHER_CLOUDY:
			return "ОБЛАЧНО"
		WEATHER_RAIN:
			return "ДОЖДЬ"
		WEATHER_STORM:
			return "ГРОЗА"
		WEATHER_FOG:
			return "ТУМАН"
		_:
			return "ЯСНО"


func get_clock_text() -> String:
	var total := fposmod(time_of_day * 24.0 + 6.0, 24.0)
	var hh := int(total)
	var mm := int((total - float(hh)) * 60.0)
	return "%02d:%02d" % [hh, mm]


func weather_status_text() -> String:
	return "%s · %s" % [get_weather_name(), get_clock_text()]

func _draw_cloud_shadows() -> void:
	if cloud_amount <= 0.05:
		return
	var a := cloud_amount * (0.085 + 0.030 * sin(t * 0.11))
	for i in range(5):
		var x := fposmod(float(i) * 263.0 + t * 7.0 + scroll * 0.018, W + 760.0) - 380.0
		var y := fposmod(float(i) * 447.0 + t * 11.0 + scroll * 0.030, H + 900.0) - 450.0
		var rx := 300.0 + float(i) * 46.0
		var ry := 175.0 + float(i) * 26.0
		draw_texture_rect(glow_tex, Rect2(x - rx, y - ry, rx * 2.0, ry * 2.0), false, Color(0.02, 0.03, 0.05, a))


func _glow(center: Vector2, radius: float, col: Color, stretch := Vector2.ONE) -> void:
	if glow_tex == null or col.a <= 0.001:
		return
	var r := Vector2(radius * stretch.x, radius * stretch.y)
	draw_texture_rect(glow_tex, Rect2(center - r, r * 2.0), false, col)

func _draw_rails() -> void:
	var sh := 27.0
	for side in [-1, 1]:
		var x := road_x - sh - 12.0 if side < 0 else road_x + road_w + sh + 6.0
		draw_rect(Rect2(x + 3.0, 0.0, 8.0, H), Color(0, 0, 0, 0.16))
		draw_rect(Rect2(x, 0.0, 12.0, H), Color(0.68, 0.70, 0.71))
		draw_rect(Rect2(x, 0.0, 4.0, H), Color(0.86, 0.88, 0.88))
		draw_rect(Rect2(x + 10.0, 0.0, 2.0, H), Color(0.46, 0.48, 0.49))
		var period := 190.0
		var off := fposmod(scroll, period)
		var y := off - period
		while y < H + period:
			draw_rect(Rect2(x - 3.0, y, 18.0, 8.0), Color(0.36, 0.38, 0.39))
			draw_rect(Rect2(x - 3.0, y, 18.0, 2.0), Color(0.60, 0.62, 0.63))
			y += period


func _draw_scenery() -> void:
	# Ambient light is applied by the CanvasModulate (render/lighting.gd).
	var ambient := Color.WHITE
	for di in _visible_decor():
		var d: Dictionary = decor[di]
		var base_y := fposmod(float(d.y) + scroll, DECOR_CYCLE)
		# Include every repeated copy for tall viewports as well as wraparound.
		for k in range(-1, int(ceil(H / DECOR_CYCLE)) + 1):
			var y: float = base_y + k * DECOR_CYCLE
			var margin := 1400.0 if int(d.kind) == 5 else 100.0
			if y < -margin or y > H + margin:
				continue
			var side: float = d.side
			var x: float = (road_x - 52.0 - float(d.off)) if side < 0 else (road_x + road_w + 52.0 + float(d.off))
			var p := Vector2(x, y)
			var kind: int = d.kind
			var size: float = d.size
			if kind == 5:
				roadside_art.draw_building(self, p, int(d.prop), int(d.variant), size * car_w / 86.0, side, ambient, Vector2(_sx, _sy), (1.0 - get_light_factor()) * (1.0 - cloud_amount * 0.7))
			elif kind == 2:
				Art.streetlight(self, p, -side, 0.9 * size, Lighting.STREET_ARM)
			elif kind == 3:
				Art.road_sign(self, p, side)
			elif not roadside_art.draw_prop(self, p, int(d.prop), int(d.variant), size, ambient):
				# The atlas becomes ready after the first rendered frame.
				if kind == 0:
					Art.tree(self, p, 41.0 * size, d.tint)
				elif kind == 1:
					Art.bush(self, p, 34.0 * size)

func _draw_items() -> void:
	for it in items:
		var p := Vector2(float(it.x), float(it.y))
		if int(it.kind) == 0:
			Art.coin(self, p, 17.0, float(it.phase))
		else:
			Art.nitro_can(self, p, 30.0, float(it.phase))


func _draw_speed_streaks() -> void:
	if not (boosting and running):
		return
	for i in range(16):
		var x := fposmod(float(i) * 97.0 + 31.0, W)
		var y := fposmod(scroll * 1.35 + float(i) * 191.0, H + 200.0) - 100.0
		draw_line(Vector2(x, y), Vector2(x, y + 110.0), Color(1, 1, 1, 0.075), 2.0)




func _draw_rewind_fx() -> void:
	var tint := 0.08 + 0.04 * sin(t * 22.0)
	draw_rect(Rect2(0.0, 0.0, W, H), Color(0.36, 0.60, 0.92, tint))
	for i in range(14):
		var y := fposmod(float(i) * 127.0 + t * 620.0, H + 80.0) - 40.0
		draw_line(Vector2(0.0, y), Vector2(W, y), Color(0.80, 0.92, 1.0, 0.045), 2.0)
	for i in range(4):
		var y := fposmod(float(i) * 379.0 - t * 980.0, H + 160.0) - 80.0
		draw_rect(Rect2(0.0, y, W, 2.5), Color(0.88, 0.95, 1.0, 0.055))


# --- atmospheric water ------------------------------------------------------

func _draw_cars() -> void:
	if running and not demo and str(challenge_config.get("type", "")) == "duel" and not _ghost_state.is_empty():
		_draw_ghost_car()
	var list := cars.duplicate()
	list.sort_custom(func(a, b): return float(a.y) < float(b.y))
	var player_drawn := false
	var light := get_light_factor()
	for c in list:
		if running and not demo and not player_drawn and float(c.y) > player_y:
			_draw_player()
			player_drawn = true
		var center := Vector2(float(c.x), float(c.y))
		var ram_rot := float(c.get("ram_rot", 0.0))
		if ram_rot != 0.0:
			draw_set_transform(center + Vector2(_sx, _sy), ram_rot)
			center = Vector2.ZERO
		var sprite := _race_sprite(c)
		if sprite.is_empty():
			Art.traffic(self, center, float(c.w), float(c.h), int(c.get("kind", 0)), c.color, {
				"stripe": bool(c.get("stripe", false)),
				"wing": bool(c.get("wing", false)),
				"rails": bool(c.get("rails", false)),
				"roof_sign": bool(c.get("roof_sign", false)),
				"cargo": bool(c.get("cargo", false)),
				"brake": bool(c.get("braking", false)),
				"light": light,
				"silhouette": str(c.get("silhouette", "sedan")),
				"exact": true,
				"stripe_color": c.get("stripe_color", Color(0.94, 0.93, 0.90)),
				"trailer": c.get("trailer", Color(0.78, 0.79, 0.79)),
				"accent": c.get("accent", Color(0.86, 0.27, 0.22)),
			})
		else:
			_draw_vehicle_shadow(center, float(c.w), float(c.h))
			race_art.draw(self, center, float(c.w), float(c.h), sprite)
		# Stop lights and indicators are light sources: see render/lighting.gd.
		if ram_rot != 0.0:
			draw_set_transform(Vector2(_sx, _sy))
	if running and not demo and not player_drawn:
		_draw_player()


func _draw_player() -> void:
	draw_set_transform(Vector2(player_x + _sx, player_y + _sy), player_tilt)
	if _rewind_invuln > 0.0 and fposmod(t * 14.0, 1.0) < 0.35:
		draw_arc(Vector2.ZERO, car_h * 0.56, 0.0, TAU, 36, Color(0.45, 0.90, 1.0, 0.55), 3.0, true)
	if hyperdrive_active:
		var hp := 0.5 + 0.5 * sin(t * 12.0)
		_glow(Vector2.ZERO, car_h * 0.65, Color(0.88, 0.24, 0.34, 0.18 + hp * 0.12), Vector2(0.65, 1.12))
		draw_arc(Vector2.ZERO, car_h * 0.52, -PI * 0.85, -PI * 0.15, 22, Color(1.0, 0.35, 0.42, 0.55), 3.0, true)
	if not tutorial_mode and nitro >= 1.0 - 0.002:
		var cp := 0.5 + 0.5 * sin(t * 5.0)
		draw_arc(Vector2.ZERO, car_h * 0.54, PI * 0.18, PI * 0.82, 24, Color(0.36, 0.88, 0.96, 0.32 + cp * 0.28), 3.0, true)
	if slingshot_charge > 0.04 and not tutorial_mode:
		var ready := slingshot_charge >= 0.99
		var col := Color(1.0, 0.86, 0.28, 0.88) if ready else Color(0.36, 0.90, 0.98, 0.72)
		var ang_span := (PI * 0.38) * slingshot_charge
		var rad := car_h * 0.58
		draw_arc(Vector2.ZERO, rad, -PI * 0.5 - ang_span, -PI * 0.5, 18, col, 4.5 if ready else 3.2, true)
		draw_arc(Vector2.ZERO, rad, -PI * 0.5, -PI * 0.5 + ang_span, 18, col, 4.5 if ready else 3.2, true)
	if slingshot_t > 0.0:
		_glow(Vector2(0.0, car_h * 0.36), car_w * 0.72, Color(0.36, 0.92, 1.0, 0.30 * (slingshot_t / SLINGSHOT_TIME)), Vector2(0.8, 1.4))
	if boosting:
		for side in [-1, 1]:
			var fx: float = float(side) * car_w * 0.23
			draw_circle(Vector2(fx, car_h * 0.50), car_w * 0.11, Color(1.0, 0.55, 0.18, 0.35))
			draw_circle(Vector2(fx, car_h * 0.54), car_w * 0.07, Color(1.0, 0.85, 0.45, 0.45))
	var sprite := _race_sprite(_player_art)
	if sprite.is_empty():
		Art.car(self, Vector2.ZERO, car_w, car_h, player_color, {
			"player": true,
			"stripe": player_stripe,
			"wing": player_wing,
			"stripe_color": player_stripe_col,
			"silhouette": player_silhouette,
			"brake": braking and running,
			"heat": brake_heat,
			"light": get_light_factor(),
		})
	else:
		_draw_vehicle_shadow(Vector2.ZERO, car_w, car_h)
		race_art.draw(self, Vector2.ZERO, car_w, car_h, sprite)
		# Stop lights come from render/lighting.gd; brake-disc heat stays here.
		if brake_heat > 0.35:
			var ht := clampf((brake_heat - 0.35) / 0.65, 0.0, 1.0)
			for side in [-1, 1]:
				var wp := Vector2(float(side) * car_w * 0.36, car_h * 0.34)
				_glow(wp, car_w * 0.16, Color(1.0, 0.35, 0.05, 0.20 * ht))
				_glow(wp, car_w * 0.07, Color(1.0, 0.30 + ht * 0.40, 0.06, 0.55 + ht * 0.35))
	draw_set_transform(Vector2(_sx, _sy))


func _race_sprite(car: Dictionary) -> Dictionary:
	if not use_3d_cars or race_art == null or car.is_empty():
		return {}
	# Appearance is fixed for each spawned car (including rewind snapshots).
	if not car.has("_race_sprite"):
		car["_race_sprite"] = race_art.take(car)
	return car["_race_sprite"]


func _draw_vehicle_shadow(center: Vector2, w: float, h: float) -> void:
	_glow(center + Vector2(0.0, h * 0.02), w * 0.82,
		Color(0.0, 0.0, 0.0, 0.30), Vector2(0.62, 1.02))

# Distance haze, sunset wash and vignette. Drawn on the unshaded FX overlay
# (render/render_stack.gd), pre-tinted by the ambient light, so these large
# translucent gradients do not run the 2D-light loop for every pixel.
func paint_haze(ci: CanvasItem) -> void:
	var night := get_night_factor()
	var amb := get_sky_ambient()
	var lit: Color = lighting_fx.ambient if lighting_fx != null else Color.WHITE
	# Fog itself is render/fog_fx.gd; this is only the distance haze.
	var top := Color(0.78, 0.80, 0.80, 0.12)
	top = top.lerp(Color(0.10, 0.13, 0.21, 0.22), night)
	top = Color(top.r * lit.r, top.g * lit.g, top.b * lit.b, top.a)
	Fx.vgrad(ci, Rect2(0.0, 0.0, W, 230.0), top, Color(top.r, top.g, top.b, 0.0))
	var low := Color(0.10 * lit.r, 0.11 * lit.g, 0.12 * lit.b, 0.0)
	Fx.vgrad(ci, Rect2(0.0, H - 170.0, W, 170.0), low, Color(low.r, low.g, low.b, 0.10 + night * 0.10))

	# Warm sunset wash only while the sky is actually warm.
	var warmth := clampf((amb.r - amb.b) * 0.55, 0.0, 1.0) * (1.0 - night)
	if warmth > 0.02:
		var wc := Color(1.0 * lit.r, 0.54 * lit.g, 0.24 * lit.b, warmth * 0.14)
		Fx.vgrad(ci, Rect2(0.0, 0.0, W, 520.0), wc, Color(wc.r, wc.g, wc.b, 0.0))
		ci.draw_rect(Rect2(0.0, 0.0, W, H), Color(1.0 * lit.r, 0.58 * lit.g, 0.30 * lit.b, warmth * 0.045))

	var vig := 0.13 + night * 0.12 + storm_amount * 0.08
	Fx.hgrad(ci, Rect2(0.0, 0.0, 120.0, H), Color(0.0, 0.0, 0.0, vig), Color(0.0, 0.0, 0.0, 0.0))
	Fx.hgrad(ci, Rect2(W - 120.0, 0.0, 120.0, H), Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, vig))


func _grad_h(rect: Rect2, left: Color, right: Color) -> void:
	draw_polygon(
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([left, right, right, left])
	)


func _grad_v(rect: Rect2, top: Color, bottom: Color) -> void:
	draw_polygon(
		PackedVector2Array([rect.position, Vector2(rect.end.x, rect.position.y), rect.end, Vector2(rect.position.x, rect.end.y)]),
		PackedColorArray([top, top, bottom, bottom])
	)

func _draw_rear_hazards() -> void:
	if not running or crashed:
		return
	var pulse := 0.65 + 0.35 * sin(t * 14.0)
	for c in cars:
		var cy: float = float(c.y)
		if cy > H - 160.0:
			var cx: float = float(c.x)
			var alert_y := H - 38.0
			var col := Color(1.0, 0.22, 0.18, pulse * 0.90)
			var pts := PackedVector2Array([
				Vector2(cx, alert_y - 18.0),
				Vector2(cx - 16.0, alert_y + 4.0),
				Vector2(cx - 10.0, alert_y + 4.0),
				Vector2(cx, alert_y - 8.0),
				Vector2(cx + 10.0, alert_y + 4.0),
				Vector2(cx + 16.0, alert_y + 4.0),
			])
			draw_colored_polygon(pts, col)
			draw_circle(Vector2(cx, alert_y + 12.0), 3.0, col)

func _draw_ghost_car() -> void:
	var gx := road_x + float(_ghost_state.get("x_norm", 0.5)) * road_w
	var g_scroll := float(_ghost_state.get("scroll", 0.0))
	var gy := player_y - (g_scroll - scroll)
	if gy < -260.0 or gy > H + 260.0:
		return
	var ghost_col := Color(0.32, 0.88, 0.98, 0.55)
	_glow(Vector2(gx, gy), car_h * 0.60, Color(0.30, 0.86, 0.96, 0.16), Vector2(0.65, 1.08))
	if not _ghost_sprite.is_empty() and race_art != null:
		race_art.draw(self, Vector2(gx, gy), car_w, car_h, _ghost_sprite, Color(0.75, 0.96, 1.0, 0.50))
	else:
		Art.car(self, Vector2(gx, gy), car_w, car_h, Color(0.28, 0.78, 0.92, 0.55), {
			"player": false,
			"stripe": bool(_ghost_art.get("stripe", false)),
			"wing": false,
			"stripe_color": Color(0.85, 0.98, 1.0, 0.55),
			"silhouette": str(_ghost_art.get("silhouette", "sedan")),
			"details": false,
		})
	draw_rect(Rect2(gx - car_w * 0.46, gy - car_h * 0.48, car_w * 0.92, car_h * 0.96), ghost_col, false, 2.0)
	if bool(_ghost_state.get("boosting", false)):
		_glow(Vector2(gx, gy + car_h * 0.52), car_w * 0.34, Color(0.36, 0.90, 1.0, 0.50))
	var tag := str(challenge_config.get("name", "ДРУГ"))
	if _hud_font != null:
		var tw := _hud_font.get_string_size(tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17).x
		draw_rect(Rect2(gx - tw * 0.5 - 8.0, gy - car_h * 0.62 - 20.0, tw + 16.0, 24.0), Color(0.04, 0.08, 0.12, 0.80))
		draw_string(_hud_font, Vector2(gx - tw * 0.5, gy - car_h * 0.62 - 2.0), tag, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color(0.45, 0.94, 1.0, 0.95))


func _draw_road_event_under() -> void:
	# Ghost crash/finish line across highway
	if running and not demo and str(challenge_config.get("type", "")) == "duel":
		var end_sc := float(challenge_config.get("end_scroll", 0.0))
		if end_sc > 40.0:
			var fy := player_y - (end_sc - scroll)
			if fy > -80.0 and fy < H + 80.0:
				var sq := road_w / 16.0
				for i in range(16):
					var col := Color(0.36, 0.92, 1.0, 0.55) if i % 2 == 0 else Color(1.0, 0.85, 0.25, 0.45)
					draw_rect(Rect2(road_x + float(i) * sq, fy - 7.0, sq, 14.0), col)
				if _hud_font != null:
					var lbl := "ФИНИШ СОПЕРНИКА"
					var tw := _hud_font.get_string_size(lbl, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18).x
					draw_string(_hud_font, Vector2(road_x + road_w * 0.5 - tw * 0.5, fy - 14.0), lbl, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 18, Color(0.45, 0.95, 1.0, 0.90))

	if road_event_type == EVENT_RADAR:
		var ry := float(road_event.get("y", -2000.0))
		if ry > -60.0 and ry < H + 60.0:
			var lcol := Color(0.34, 0.90, 1.0, 0.65) if str(road_event.get("mode", "fast")) == "fast" else Color(0.98, 0.70, 0.18, 0.70)
			draw_rect(Rect2(road_x, ry - 4.0, road_w, 8.0), Color(lcol.r, lcol.g, lcol.b, 0.22))
			draw_line(Vector2(road_x, ry), Vector2(road_x + road_w, ry), lcol, 3.0)
	elif road_event_type == EVENT_ROADWORKS and closed_lane >= 0:
		var head_y := float(road_event.get("head_y", -2000.0))
		var taper_len := float(road_event.get("taper_len", 440.0))
		var zone_len := float(road_event.get("zone_len", 2600.0))
		var barrier_head := head_y - taper_len
		var tail_y := barrier_head - zone_len
		var y0 := maxf(-40.0, tail_y)
		var y1 := minf(H + 40.0, barrier_head)
		if y1 > y0:
			var lx := road_x + float(closed_lane) * lane_w
			draw_rect(Rect2(lx + 4.0, y0, lane_w - 8.0, y1 - y0), Color(0.95, 0.48, 0.12, 0.18))
			var step := 140.0
			var sy: float = floor(y0 / step) * step
			while sy < y1:
				if sy >= tail_y and sy <= barrier_head - 40.0:
					draw_line(Vector2(lx + 14.0, sy), Vector2(lx + lane_w - 14.0, sy + 52.0), Color(1.0, 0.62, 0.18, 0.35), 4.0)
					draw_line(Vector2(lx + lane_w - 14.0, sy), Vector2(lx + 14.0, sy + 52.0), Color(1.0, 0.62, 0.18, 0.35), 4.0)
				sy += step


func _draw_road_event_over() -> void:
	# Traffic lane-change chevron indicator
	for c in cars:
		var sig := int(c.get("signal_dir", 0))
		if sig != 0 and float(c.get("signal_t", 0.0)) > 0.0 and not bool(c.get("rammed", false)):
			var alpha := 0.35 + 0.35 * sin(t * 16.0)
			var cx := float(c.x) + float(sig) * lane_w * 0.52
			var cy := float(c.y)
			var pts := PackedVector2Array([
				Vector2(cx - float(sig) * 10.0, cy - 12.0),
				Vector2(cx + float(sig) * 8.0, cy),
				Vector2(cx - float(sig) * 10.0, cy + 12.0),
			])
			draw_polyline(pts, Color(1.0, 0.70, 0.16, alpha), 3.0, true)

	# Off-screen Ghost indicator
	if running and not demo and str(challenge_config.get("type", "")) == "duel" and not _ghost_state.is_empty():
		var gx := road_x + float(_ghost_state.get("x_norm", 0.5)) * road_w
		var g_scroll := float(_ghost_state.get("scroll", 0.0))
		var gy := player_y - (g_scroll - scroll)
		var gap_m := int(round((g_scroll - scroll) / 12.0))
		if gy < 60.0 and _hud_font != null:
			var txt := "%s +%dм" % [str(challenge_config.get("name", "ДРУГ")), maxi(1, gap_m)]
			var tw := _hud_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17).x
			draw_rect(Rect2(gx - tw * 0.5 - 10.0, 266.0, tw + 20.0, 28.0), Color(0.04, 0.08, 0.12, 0.85))
			draw_string(_hud_font, Vector2(gx - tw * 0.5, 286.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color(0.45, 0.94, 1.0, 0.95))
		elif gy > H - 40.0 and _hud_font != null:
			var txt := "%s %dм" % [str(challenge_config.get("name", "ДРУГ")), gap_m]
			var tw := _hud_font.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17).x
			draw_rect(Rect2(gx - tw * 0.5 - 10.0, H - 78.0, tw + 20.0, 28.0), Color(0.04, 0.08, 0.12, 0.85))
			draw_string(_hud_font, Vector2(gx - tw * 0.5, H - 58.0), txt, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 17, Color(0.45, 0.94, 1.0, 0.85))

	if road_event_type == EVENT_RADAR:
		var ry := float(road_event.get("y", -2000.0))
		var tgt := int(road_event.target_kmh)
		var is_fast := str(road_event.get("mode", "fast")) == "fast"
		var rcol := Color(0.34, 0.92, 1.0) if is_fast else Color(0.98, 0.72, 0.20)
		if ry > -120.0 and ry < H + 120.0:
			for sx in [road_x - 16.0, road_x + road_w + 16.0]:
				draw_circle(Vector2(sx, ry), 14.0, Color(0.14, 0.16, 0.18))
				draw_circle(Vector2(sx, ry), 8.0, rcol)
				_glow(Vector2(sx, ry), 36.0, Color(rcol.r, rcol.g, rcol.b, 0.45))
			if _hud_font != null:
				var badge := ("РАДАР %d+ КМ/Ч" % tgt) if is_fast else ("ЛИМИТ ≤ %d КМ/Ч" % tgt)
				var tw := _hud_font.get_string_size(badge, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20).x
				draw_rect(Rect2(road_x + road_w * 0.5 - tw * 0.5 - 14.0, ry - 42.0, tw + 28.0, 32.0), Color(0.05, 0.07, 0.09, 0.90))
				draw_string(_hud_font, Vector2(road_x + road_w * 0.5 - tw * 0.5, ry - 19.0), badge, HORIZONTAL_ALIGNMENT_LEFT, -1.0, 20, rcol)
	elif road_event_type == EVENT_ROADWORKS and closed_lane >= 0:
		var head_y := float(road_event.get("head_y", -2000.0))
		var taper_len := float(road_event.get("taper_len", 440.0))
		var zone_len := float(road_event.get("zone_len", 2600.0))
		var barrier_head := head_y - taper_len
		var tail_y := barrier_head - zone_len
		var edge_x := (road_x + 12.0) if closed_lane == 0 else (road_x + road_w - 12.0)
		var inner_x := (road_x + lane_w) if closed_lane == 0 else (road_x + road_w - lane_w)
		# Taper cones
		for i in range(7):
			var frac := float(i) / 6.0
			var cy := lerpf(head_y, barrier_head, frac)
			if cy < -40.0 or cy > H + 40.0:
				continue
			var cx := lerpf(edge_x, inner_x, frac)
			draw_circle(Vector2(cx, cy), 10.0, Color(0.98, 0.44, 0.10))
			draw_circle(Vector2(cx, cy), 5.0, Color(0.98, 0.96, 0.92))
		# Barrier blocks along closed lane
		var y0 := maxf(-60.0, tail_y)
		var y1 := minf(H + 60.0, barrier_head)
		if y1 > y0:
			var step := 110.0
			var by: float = floor(y0 / step) * step
			var blink := 0.4 + 0.6 * (0.5 + 0.5 * sin(t * 14.0))
			while by < y1:
				if by >= tail_y and by <= barrier_head:
					draw_rect(Rect2(inner_x - 8.0, by, 16.0, 62.0), Color(0.95, 0.46, 0.12))
					draw_rect(Rect2(inner_x - 8.0, by + 18.0, 16.0, 22.0), Color(0.95, 0.95, 0.95))
					_glow(Vector2(inner_x, by + 31.0), 22.0, Color(1.0, 0.65, 0.12, 0.42 * blink))
				by += step
