class_name RenderStack
extends Node2D

# The 0.8.0 frame. Game stays the single source of state; this node owns every
# visual system and the order in which they reach the screen:
#
#   z -30 ground      grass verge, shoulders                 lit, mask 1
#   z -20 road        asphalt material + markings            lit, mask 1
#   z -15 decals      road buffer (tyre marks, scorches)     lit, mask 1
#   z -14 puddles     puddle water                           lit, mask 1
#   z -12 road glow   wet reflections of every lamp          unshaded, add
#   z   0 Game._draw  rails, scenery, cars, items, events    lit, mask 2
#   z   2 fixtures    lamp housings above their light pools ambient only
#   z   4 particles   spray, smoke, debris                   lit, mask 4
#   z   8 emissive    lamps, light trails, sparks            unshaded, add
#   z   9 air         falling rain                           lit, mask 4
#   CanvasLayer 1     fog, bloom, lightning, screen drops, haze
#   CanvasLayer 5     HUD (main.gd)
#
# Light masks: 1 = receives shadows (the road), 2 = lit objects, 4 = lit air.

const MASK_ROAD := 1
const MASK_OBJECTS := 2
const MASK_AIR := 4

var game  # Game
var level := GfxPresets.MEDIUM
var params: Dictionary = GfxPresets.params(GfxPresets.MEDIUM)
var dyn := GfxPresets.DynamicRes.new()
var target_fps := 60
var post_scale := 0.5

var ground_painter: GroundPainter
var asphalt: Asphalt
var road_buffer: RoadBuffer
var bloom: Bloom
var systems: Array = []  # objects with optional apply_params/frame/set_post_scale

var overlay: CanvasLayer
var ground_layer: DrawLayer
var road_layer: DrawLayer
const ROAD_STRIPS := 4
var road_strips: Array = []
var decal_layer: DrawLayer
var puddle_layer: DrawLayer
var road_glow_layer: DrawLayer
var duel_ghost_layer: DrawLayer
var fixture_layer: DrawLayer
var particle_layer: DrawLayer
var emissive_layer: DrawLayer
var air_layer: DrawLayer
var overlay_layer: DrawLayer
var bloom_painters: Array = []  # Callables painting bloom sources (screen coords)
var road_glow_painters: Array = []
var emissive_painters: Array = []
var particle_painters: Array = []
var air_painters: Array = []
var overlay_painters: Array = []
var puddle_painters: Array = []
var _last_size := Vector2.ZERO
var last_cpu_ms := 0.0  # CPU time of the last frame() (QA perf mode)
var system_ms: Dictionary = {}  # per-system CPU time of the last frame


func setup(p_game) -> void:
	game = p_game
	name = "RenderStack"
	ground_painter = GroundPainter.new(game)
	ground_painter.grass_tex = game.grass_tex
	asphalt = Asphalt.new(game)

	ground_layer = _layer("Ground", -30, ground_painter.paint, MASK_ROAD)
	road_layer = _layer("Road", -20, _paint_road, MASK_ROAD)
	road_layer.material = asphalt.material
	# 2D lights are culled per canvas item. One screen-tall road item would
	# run every light over every road pixel; horizontal strips (same shader,
	# seamless because it works in world space) only see the lights that
	# actually reach them.
	for i in range(ROAD_STRIPS):
		var strip := DrawLayer.new("RoadStrip%d" % i, 0, _paint_road_strip.bind(i))
		strip.light_mask = MASK_ROAD
		strip.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
		strip.material = asphalt.material
		road_layer.add_child(strip)
		road_strips.append(strip)
	decal_layer = _layer("Decals", -15, _paint_decals, MASK_ROAD)
	# The buffer holds premultiplied colour (marks drawn over transparent black).
	var premul := CanvasItemMaterial.new()
	premul.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	decal_layer.material = premul
	puddle_layer = _layer("Puddles", -14, _paint_list.bind(puddle_painters), MASK_ROAD)
	road_glow_layer = _layer("RoadGlow", -12, _paint_list.bind(road_glow_painters), MASK_ROAD)
	road_glow_layer.material = DrawLayer.unshaded_material(CanvasItemMaterial.BLEND_MODE_ADD)
	duel_ghost_layer = _layer("DuelGhost", -1, game.paint_duel_ghost, 0)
	duel_ghost_layer.material = DrawLayer.unshaded_material()
	fixture_layer = _layer("StreetFixtures", 2, game.paint_street_fixtures, 0)
	particle_layer = _layer("Particles", 4, _paint_list.bind(particle_painters), MASK_AIR)
	emissive_layer = _layer("Emissive", 8, _paint_list.bind(emissive_painters), MASK_OBJECTS)
	emissive_layer.material = DrawLayer.unshaded_material(CanvasItemMaterial.BLEND_MODE_ADD)
	air_layer = _layer("Air", 9, _paint_list.bind(air_painters), MASK_AIR)

	overlay = CanvasLayer.new()
	overlay.name = "FxOverlay"
	overlay.layer = 1
	add_child(overlay)

	road_buffer = RoadBuffer.new()
	road_buffer.name = "RoadBuffer"
	add_child(road_buffer)

	bloom = Bloom.new()
	bloom.name = "Bloom"
	add_child(bloom)

	# Overlay painter (haze, flash, rewind tint) sits above fog and bloom.
	overlay_layer = DrawLayer.new("Overlay", 0, _paint_list.bind(overlay_painters))
	_relayout(true)


func _layer(p_name: String, z: int, painter: Callable, mask: int) -> DrawLayer:
	var l := DrawLayer.new(p_name, z, painter)
	l.light_mask = mask
	l.texture_repeat = CanvasItem.TEXTURE_REPEAT_ENABLED
	add_child(l)
	return l


func add_system(s) -> void:
	systems.append(s)
	if s.has_method("apply_params"):
		s.apply_params(params)
	if s.has_method("set_post_scale"):
		s.set_post_scale(post_scale)


# Called once all systems have added their own overlay children, so the haze /
# flash overlay ends on top of fog and bloom.
func finish_setup() -> void:
	if overlay_layer.get_parent() == null:
		overlay.add_child(overlay_layer)
	else:
		overlay.move_child(overlay_layer, overlay.get_child_count() - 1)


func apply_preset(p_level: int, p_target_fps := -1) -> void:
	level = clampi(p_level, GfxPresets.LOW, GfxPresets.ULTRA)
	if p_target_fps > 0:
		target_fps = p_target_fps
	params = GfxPresets.params(level)
	dyn.reset(float(params.post_scale), target_fps)
	post_scale = dyn.scale()
	if asphalt != null:
		asphalt.apply_params(params)
	for s in systems:
		if s.has_method("apply_params"):
			s.apply_params(params)
	_relayout(true)


func _relayout(force := false) -> void:
	if game == null:
		return
	var size := Vector2(game.W, game.H)
	if not force and size == _last_size:
		return
	_last_size = size
	var sh := 27.0
	road_buffer.setup(game.road_x - sh - 4.0, game.road_w + (sh + 4.0) * 2.0, game.H, float(params.road_buffer_scale))
	bloom.setup(size, post_scale, _paint_bloom, overlay)
	bloom.set_enabled(bool(params.bloom))
	for s in systems:
		if s.has_method("relayout"):
			s.relayout(size)
		if s.has_method("set_post_scale"):
			s.set_post_scale(post_scale)


# Per frame, after the simulation tick.
func frame(delta: float) -> void:
	if game == null:
		return
	var t0 := Time.get_ticks_usec()
	_relayout()
	if dyn.feed(delta):
		post_scale = dyn.scale()
		bloom.set_post_scale(post_scale)
		for s in systems:
			if s.has_method("set_post_scale"):
				s.set_post_scale(post_scale)
	position = Vector2(game._sx, game._sy)
	for s in systems:
		if s.has_method("frame"):
			var ts := Time.get_ticks_usec()
			s.frame(delta)
			system_ms[s.get_script().get_global_name()] = float(Time.get_ticks_usec() - ts) / 1000.0
	road_buffer.update(game.scroll)
	var lit = game.lighting_fx
	var cfx = game.contact_fx
	var bloom_on: bool = (lit != null and lit.count > 0) or (cfx != null and not cfx.sparks.is_empty()) or float(game.lightning) > 0.02
	bloom.frame(Vector2(game.W, game.H), bloom_on)
	bloom.composite.position = position
	for l in [ground_layer, road_layer, decal_layer, puddle_layer, road_glow_layer,
			duel_ghost_layer, fixture_layer, particle_layer, emissive_layer, air_layer, overlay_layer]:
		l.queue_redraw()
	for st in road_strips:
		st.queue_redraw()
	last_cpu_ms = float(Time.get_ticks_usec() - t0) / 1000.0


func _paint_list(ci: CanvasItem, list: Array) -> void:
	for p in list:
		p.call(ci)


func _paint_road_strip(ci: CanvasItem, i: int) -> void:
	var h: float = (game.H + 80.0) / float(ROAD_STRIPS)
	asphalt.draw_rect_part(ci, -40.0 + h * float(i), h)


func _paint_road(ci: CanvasItem) -> void:
	asphalt.paint_surface(ci)
	asphalt.paint_markings(ci)


func _paint_decals(ci: CanvasItem) -> void:
	road_buffer.draw_to(ci, game.scroll, game.H)


func _paint_bloom(ci: CanvasItem) -> void:
	for p in bloom_painters:
		p.call(ci)
