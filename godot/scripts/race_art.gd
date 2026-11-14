class_name RaceArt
extends Node

# Gameplay car sprites.
#
# The race is a top-down 2D scene, so a live 3D car would need its own render
# pass every frame. Instead each car is rendered once from a chase camera into
# a SubViewport, cropped to its silhouette and cached as a texture. The race
# then draws one sprite per car: the old frame budget, but with real volumes,
# glass, wheels and paint for the classes that have a garage model.
#
# Sprites are generated lazily, one per frame, so a new traffic colour never
# stalls the run; until a sprite is ready the caller keeps drawing the 2D art.
# Trucks and buses have no 3D model and always stay 2D.

const MODEL := preload("res://scripts/car_model.gd")

# Big enough for a crisp sprite on a 1080p phone, small enough that a cold
# render is cheap. The image is cropped to the alpha bounds afterwards.
const VP_W := 320
const VP_H := 480
const ORTHO := 5.35

var _vp: SubViewport
var _cam: Camera3D
var _model

# sig -> {"tex": ImageTexture, "w": int, "h": int}
var _cache: Dictionary = {}
# sig -> normalized car dict, waiting in _queue
var _pending: Dictionary = {}
var _queue: Array = []
var _busy := false
# After repeated blank readbacks the driver is assumed broken (some GLES
# devices refuse texture readback); every caller then keeps the 2D art.
var _disabled := false
var _fails := 0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build()


func _build() -> void:
	_vp = SubViewport.new()
	_vp.name = "RaceArtView"
	_vp.size = Vector2i(VP_W, VP_H)
	_vp.transparent_bg = true
	_vp.own_world_3d = true
	_vp.msaa_3d = Viewport.MSAA_4X
	_vp.gui_disable_input = true
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	add_child(_vp)

	var we := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_CLEAR_COLOR
	env.background_color = Color(0, 0, 0, 0)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.60, 0.65, 0.72)
	env.ambient_light_energy = 0.30
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.tonemap_exposure = 1.02
	we.environment = env
	_vp.add_child(we)

	# High key, because the chase camera sees mostly the roof and the bonnet.
	var key := DirectionalLight3D.new()
	_vp.add_child(key)
	key.rotation_degrees = Vector3(-62.0, 34.0, 0.0)
	key.light_energy = 0.72
	key.light_color = Color(1.0, 0.97, 0.92)

	var fill := DirectionalLight3D.new()
	_vp.add_child(fill)
	fill.rotation_degrees = Vector3(-28.0, -68.0, 0.0)
	fill.light_energy = 0.20
	fill.light_color = Color(0.72, 0.82, 1.0)

	var rim := DirectionalLight3D.new()
	_vp.add_child(rim)
	rim.rotation_degrees = Vector3(-20.0, 202.0, 0.0)
	rim.light_energy = 0.34
	rim.light_color = Color(0.95, 0.96, 1.0)

	_cam = Camera3D.new()
	_cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	_cam.size = ORTHO
	_cam.position = Vector3(0.0, 4.60, -3.00)
	_vp.add_child(_cam)
	_cam.look_at(Vector3(0.0, 0.65, 0.30), Vector3.UP)
	_cam.current = true

	_model = MODEL.new()
	_model.name = "Car"
	_vp.add_child(_model)


# --- public API -------------------------------------------------------------

# Returns a ready sprite for this car, or {} and queues the render. Call it
# every frame; it is free once the sprite exists.
func take(car: Dictionary) -> Dictionary:
	if _disabled:
		return {}
	var key := _key(car)
	if key == "":
		return {}
	if _cache.has(key):
		return _cache[key]
	if not _pending.has(key):
		_pending[key] = _clean(car)
		_queue.append(key)
	return {}


# Draws a cached sprite centred in a w x h box, keeping the model's aspect.
func draw(ci: CanvasItem, center: Vector2, w: float, h: float, sprite: Dictionary) -> void:
	var sw := float(sprite.w)
	var sh := float(sprite.h)
	if sw < 1.0 or sh < 1.0:
		return
	var k := minf(h * 0.96 / sh, w * 0.99 / sw)
	var size := Vector2(sw, sh) * k
	ci.draw_texture_rect_region(sprite.tex, Rect2(center - size * 0.5, size),
		Rect2(Vector2.ZERO, Vector2(sw, sh)))


# QA hook: render straight away and hand back the cropped image.
func render_preview(car: Dictionary) -> Image:
	return await _render(_clean(car))


func cached_count() -> int:
	return _cache.size()


# --- generation -------------------------------------------------------------

func _process(_delta: float) -> void:
	if _busy or _queue.is_empty() or _vp == null:
		return
	var key := str(_queue.pop_front())
	var car: Dictionary = _pending.get(key, {})
	if car.is_empty():
		return
	_busy = true
	await _generate(key, car)
	_busy = false


func _generate(key: String, car: Dictionary) -> void:
	var img := await _render(car)
	if img == null:
		# A blank frame usually means the viewport had not been drawn yet
		# (first frame, or a resize). One retry, then keep the 2D art.
		img = await _render(car)
	_pending.erase(key)
	if img == null:
		_fails += 1
		if _fails >= 6:
			_disabled = true
			_queue.clear()
			_pending.clear()
		return
	_fails = 0
	var tex := ImageTexture.create_from_image(img)
	_cache[key] = {"tex": tex, "w": img.get_width(), "h": img.get_height()}


func _render(car: Dictionary) -> Image:
	if _vp == null or _model == null:
		return null
	_model.show_car(car)
	_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	await RenderingServer.frame_post_draw
	await RenderingServer.frame_post_draw
	var img := _vp.get_texture().get_image()
	if img == null:
		return null
	_vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	img.convert(Image.FORMAT_RGBA8)
	var bb := _alpha_bounds(img)
	if bb.size.x < 4 or bb.size.y < 4:
		return null
	return img.get_region(bb)


# Tight crop around the car. The scan is strided: a pixel of extra margin is
# invisible at gameplay size, and a full-resolution walk would cost a hitch on
# every new traffic colour.
func _alpha_bounds(img: Image) -> Rect2i:
	var w := img.get_width()
	var h := img.get_height()
	if w < 2 or h < 2:
		return Rect2i()
	var data := img.get_data()
	var step := 2
	var minx := w
	var miny := h
	var maxx := -1
	var maxy := -1
	for y in range(0, h, step):
		var row := y * w * 4
		for x in range(0, w, step):
			if data[row + x * 4 + 3] > 8:
				if x < minx:
					minx = x
				if x > maxx:
					maxx = x
				if y < miny:
					miny = y
				if y > maxy:
					maxy = y
	if maxx < minx or maxy < miny:
		return Rect2i()
	minx = maxi(0, minx - step)
	miny = maxi(0, miny - step)
	maxx = mini(w - 1, maxx + step)
	maxy = mini(h - 1, maxy + step)
	return Rect2i(minx, miny, maxx - minx + 1, maxy - miny + 1)


# --- keys -------------------------------------------------------------------

func _key(car: Dictionary) -> String:
	var sil := _silhouette(car)
	if sil == "":
		return ""
	return "%s|%s|%s|%s" % [
		sil,
		Color(car.get("color", Color("#b32b26"))).to_html(),
		str(bool(car.get("stripe", false))),
		Color(car.get("stripe_color", Color("#f0ede4"))).to_html(),
	]


func _clean(car: Dictionary) -> Dictionary:
	return {
		"silhouette": _silhouette(car),
		"color": Color(car.get("color", Color("#b32b26"))).to_html(),
		"stripe": bool(car.get("stripe", false)),
		"stripe_color": Color(car.get("stripe_color", Color("#f0ede4"))).to_html(),
	}


# Traffic kinds borrow the garage classes; a silhouette already set by the
# spawner wins. Truck and bus have no model, so they return "" and stay 2D.
func _silhouette(car: Dictionary) -> String:
	var s := str(car.get("silhouette", ""))
	if MODEL.SPECS.has(s):
		return s
	match int(car.get("kind", 0)):
		1:
			return "offroad"
		3:
			return "van"
		5:
			return "sport"
		6:
			return "pickup"
		0:
			return "sedan"
	return ""
