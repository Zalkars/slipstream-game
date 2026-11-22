class_name WeatherFx
extends Node2D

# Rain, puddles, wet road and screen drops (0.8.0 Stage 4).
#
# Game owns the weather state (rain_amount, storm_amount, wetness, wind,
# rain_vx / rain_vy, lightning); this node only renders it. All randomness
# here comes from its own RandomNumberGenerator, never from Game.run_rng, so
# visuals cannot change a seeded race.
#
#   air rain     3 MultiMesh layers (near: big, blurred; far: thin), slanted by
#                wind and car speed; lit by the 2D lights, so at night the
#                drops are only seen inside headlight cones and lamp pools.
#   splashes     MultiMesh of crowns on the asphalt, animated in the shader.
#   puddles      noise-shaped water quads, fill with rain and dry after it,
#                ripple rings while it rains, mirror-like light highlights.
#   reflections  every light source smears into a long streak on wet asphalt.
#   spray        mist plumes behind every car, bursts through puddles.
#   screen drops lens sprites (Medium) or refraction of the frame (High+);
#                drops gather and run down at low speed, get blown away fast,
#                bursts in storms and when overtaking through spray.
#   lightning    a shadow-casting directional flash plus the bolt.

const RAIN_SHADER := """
shader_type canvas_item;
uniform vec2 offset = vec2(0.0);
uniform vec2 area = vec2(900.0, 1800.0);
uniform vec2 origin = vec2(-90.0, -120.0);
uniform vec2 dir = vec2(0.0, 1.0);
uniform float len = 40.0;
uniform float width = 1.5;
uniform float alpha = 0.3;
uniform vec3 tint = vec3(0.75, 0.80, 0.88);
void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	vec2 p = origin + fract(c.xy + offset / area) * area;
	vec2 side = vec2(-dir.y, dir.x);
	float l = len * (0.7 + 0.6 * c.z);
	VERTEX = p + dir * (VERTEX.y * l) + side * (VERTEX.x * width);
	COLOR = vec4(tint, alpha * (0.55 + 0.45 * c.w));
}
void fragment() {
	float across = 1.0 - abs(UV.x * 2.0 - 1.0);
	float along = smoothstep(0.0, 0.7, UV.y) * (0.5 + 0.5 * UV.y);
	COLOR.a *= pow(across, 1.4) * along;
}
"""

const SPLASH_SHADER := """
shader_type canvas_item;
uniform float time = 0.0;
uniform float road_speed = 700.0;
uniform vec4 area = vec4(80.0, -40.0, 560.0, 1600.0);
uniform float alpha = 0.4;
uniform float life = 0.26;
uniform vec3 tint = vec3(0.80, 0.86, 0.95);
float h(float n) { return fract(sin(n) * 43758.5453); }
void vertex() {
	vec4 c = INSTANCE_CUSTOM;
	float ph = time / life + c.z;
	float cyc = floor(ph);
	float k = ph - cyc;
	float id = c.x * 917.0 + cyc * 13.17;
	vec2 p = area.xy + vec2(h(id), h(id + 4.3)) * area.zw;
	p.y += k * life * road_speed;
	float r = (1.5 + 4.0 * c.w) * (0.25 + k);
	VERTEX = p + VERTEX * vec2(r * 2.0, r * 0.9);
	COLOR = vec4(tint, alpha * (1.0 - k) * (1.0 - k));
}
void fragment() {
	float d = length(UV * 2.0 - 1.0);
	float crown = smoothstep(0.62, 0.86, d) * (1.0 - smoothstep(0.86, 1.0, d));
	float core = (1.0 - smoothstep(0.0, 0.3, d)) * 0.5;
	COLOR.a *= crown + core * step(COLOR.a, 0.3);
}
"""

const PUDDLE_SHADER := """
shader_type canvas_item;
uniform sampler2D noise : repeat_enable, filter_linear;
uniform float level = 0.5;
uniform float rain = 0.0;
uniform float time = 0.0;
uniform vec3 sky = vec3(0.5, 0.55, 0.62);
uniform bool ripples = true;
varying float v_shine;
float h(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void fragment() {
	vec2 q = UV * 2.0 - 1.0;
	float seedv = COLOR.r * 31.0;
	float n = texture(noise, UV * 0.55 + vec2(seedv, seedv * 0.7)).g;
	float n2 = texture(noise, UV * 1.6 + vec2(seedv * 1.3, 0.2)).a;
	// Depth: deepest in the middle, ragged edge from the noise; the water
	// line moves outwards as the puddle fills.
	float depth = (1.0 - length(q)) + (n - 0.5) * 0.55 + (n2 - 0.5) * 0.18;
	float water = smoothstep(1.0 - level, 1.04 - level, depth);
	if (water <= 0.002) { discard; }
	float deep = clamp((depth - (1.0 - level)) * 2.2, 0.0, 1.0);
	vec3 col = mix(vec3(0.09, 0.10, 0.11), sky * 0.55, 0.35 + deep * 0.25);
	vec3 nrm = vec3(0.0, 0.0, 1.0);
	if (ripples && rain > 0.02) {
		// Rain rings: a few drops per cell, each ring expanding and fading.
		vec2 uvp = UV * vec2(COLOR.g * 10.0, COLOR.b * 10.0);
		for (int i = 0; i < 2; i++) {
			vec2 cell = floor(uvp + float(i) * 0.5);
			vec2 f = uvp + float(i) * 0.5 - cell;
			float t0 = h(cell + float(i) * 7.0);
			float k = fract(time * (0.8 + t0 * 0.6) + t0);
			vec2 c = vec2(h(cell * 1.3), h(cell * 2.1)) * 0.6 + 0.2;
			float d = length(f - c);
			float ring = exp(-pow((d - k * 0.45) / 0.035, 2.0)) * (1.0 - k) * step(h(cell + 3.0), rain * 1.1);
			col += vec3(0.65, 0.72, 0.82) * ring * 0.35;
			nrm.xy += normalize(f - c + 0.0001) * ring * 0.6;
		}
	}
	COLOR = vec4(col, water * (0.55 + deep * 0.4) * COLOR.a);
	NORMAL_MAP = normalize(nrm) * 0.5 + 0.5;
	v_shine = 1.0;
}
void light() {
	vec3 hv = normalize(LIGHT_DIRECTION + vec3(0.0, 0.0, 1.0));
	float sp = pow(max(dot(NORMAL, hv), 0.0), 160.0) * 5.0;
	float nl = clamp(max(dot(NORMAL, LIGHT_DIRECTION), 0.0) / max(LIGHT_DIRECTION.z, 0.08), 0.0, 1.5);
	LIGHT = vec4(LIGHT_COLOR.rgb * LIGHT_ENERGY * (COLOR.rgb * nl * 0.6 + vec3(sp)), LIGHT_COLOR.a);
}
"""

const DROP_SHADER := """
shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_tex : hint_screen_texture, filter_linear_mipmap;
uniform bool refract = true;
uniform vec3 glint = vec3(1.0);
varying vec4 drop_tint;
void vertex() {
	drop_tint = COLOR;
}
void fragment() {
	vec4 d = texture(TEXTURE, UV);
	if (d.a < 0.01) { discard; }
	vec2 local_n = d.rg * 2.0 - 1.0;
	vec2 down = normalize(drop_tint.gb * 2.0 - 1.0);
	vec2 n = vec2(down.y, -down.x) * local_n.x + down * local_n.y;
	vec3 base;
	if (refract) {
		// A drop is a tiny lens: it shows the scene upside down and pulled in.
		vec2 off = n * 0.035 * drop_tint.r;
		base = textureLod(screen_tex, SCREEN_UV - off, 1.0).rgb;
		base = mix(base, base * 1.12 + 0.02, 0.5);
	} else {
		base = vec3(0.0);
	}
	float rim = smoothstep(0.55, 1.0, length(n));
	float spec = pow(clamp(dot(n, normalize(vec2(-0.5, -0.7))), 0.0, 1.0), 6.0);
	vec3 col = base * (1.0 - rim * 0.45) + glint * spec * 0.55;
	float a = d.a * drop_tint.a;
	if (!refract) {
		// Lens-sprite fallback: a dark rim and a highlight, no frame read.
		col = glint * spec * 0.7 + vec3(0.05, 0.06, 0.07) * rim;
		a *= rim * 0.55 + spec * 0.8 + 0.08;
	}
	COLOR = vec4(col, a);
}
"""

var game  # Game
var stack  # RenderStack
var params: Dictionary = {}
var rng := RandomNumberGenerator.new()

var _rain_layers: Array = []      # MultiMeshInstance2D
var _rain_offsets: Array = [Vector2.ZERO, Vector2.ZERO, Vector2.ZERO]
var _splash: MultiMeshInstance2D
var _splash_mat: ShaderMaterial
var _puddle_mat: ShaderMaterial
var _drop_layer: DrawLayer
var _drop_mat: ShaderMaterial
var _flash_light: DirectionalLight2D
var _time := 0.0
var puddle_level := 0.0

static var _drop_tex: ImageTexture
static var _streak_tex: ImageTexture
static var _head_streak_tex: ImageTexture

# Visual-only particle pools.
var mist: Array = []    # {p, v, life, max, size}
var drops: Array = []   # screen drops {p, r, v, life, age, trail, stick}
const DROP_MAX_DRIFT := 0.28  # maximum lateral speed relative to vertical speed
const DROP_RESPONSE := 3.4
var _drop_spawn := 0.0
var _last_over := {}


func setup(p_game, p_stack) -> void:
	game = p_game
	stack = p_stack
	name = "WeatherFx"
	rng.seed = 90210
	_make_textures()
	var layer_cfg := [
		# far, mid, near: count, width, length scale, speed, alpha
		[520, 1.2, 0.8, 0.80, 0.36],
		[300, 1.8, 1.0, 1.00, 0.46],
		[110, 3.0, 1.35, 1.30, 0.50],
	]
	for i in range(3):
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_2D
		mm.use_custom_data = true
		var quad := QuadMesh.new()
		quad.size = Vector2(1, 1)
		mm.mesh = quad
		mm.instance_count = int(layer_cfg[i][0])
		for k in range(mm.instance_count):
			mm.set_instance_transform_2d(k, Transform2D.IDENTITY)
			mm.set_instance_custom_data(k, Color(rng.randf(), rng.randf(), rng.randf(), rng.randf()))
		var mi := MultiMeshInstance2D.new()
		mi.multimesh = mm
		mi.name = "Rain%d" % i
		var sh := Shader.new()
		sh.code = RAIN_SHADER
		var mat := ShaderMaterial.new()
		mat.shader = sh
		mi.material = mat
		mi.light_mask = RenderStack.MASK_AIR
		mi.z_index = 9 + i
		mi.set_meta("cfg", layer_cfg[i])
		stack.add_child(mi)
		_rain_layers.append(mi)
	# Splashes on the asphalt.
	var smm := MultiMesh.new()
	smm.transform_format = MultiMesh.TRANSFORM_2D
	smm.use_custom_data = true
	var sq := QuadMesh.new()
	sq.size = Vector2(1, 1)
	smm.mesh = sq
	smm.instance_count = 220
	for k in range(smm.instance_count):
		smm.set_instance_transform_2d(k, Transform2D.IDENTITY)
		smm.set_instance_custom_data(k, Color(rng.randf(), 0.0, rng.randf(), rng.randf()))
	_splash = MultiMeshInstance2D.new()
	_splash.name = "Splashes"
	_splash.multimesh = smm
	var ssh := Shader.new()
	ssh.code = SPLASH_SHADER
	_splash_mat = ShaderMaterial.new()
	_splash_mat.shader = ssh
	_splash.material = _splash_mat
	_splash.light_mask = RenderStack.MASK_ROAD | RenderStack.MASK_AIR
	_splash.z_index = -13
	stack.add_child(_splash)
	# Puddles.
	var psh := Shader.new()
	psh.code = PUDDLE_SHADER
	_puddle_mat = ShaderMaterial.new()
	_puddle_mat.shader = psh
	_puddle_mat.set_shader_parameter("noise", Asphalt._detail)
	stack.puddle_layer.material = _puddle_mat
	stack.puddle_painters.append(paint_puddles)
	stack.road_glow_painters.append(paint_reflections)
	stack.particle_painters.append(paint_spray)
	stack.overlay_painters.append(paint_lightning)
	stack.bloom_painters.append(paint_lightning_bloom)
	# Screen drops on the FX overlay (above fog).
	_drop_layer = DrawLayer.new("ScreenDrops", 0, paint_drops)
	var dsh := Shader.new()
	dsh.code = DROP_SHADER
	_drop_mat = ShaderMaterial.new()
	_drop_mat.shader = dsh
	_drop_layer.material = _drop_mat
	stack.overlay.add_child(_drop_layer)
	# Lightning lights everything for a moment, with shadows from all objects.
	_flash_light = DirectionalLight2D.new()
	_flash_light.name = "LightningFlash"
	_flash_light.color = Color(0.80, 0.86, 1.0)
	_flash_light.height = 0.55
	_flash_light.rotation = deg_to_rad(28.0)
	_flash_light.range_item_cull_mask = RenderStack.MASK_ROAD | RenderStack.MASK_OBJECTS | RenderStack.MASK_AIR
	_flash_light.shadow_item_cull_mask = 1
	_flash_light.enabled = false
	add_child(_flash_light)


func apply_params(p: Dictionary) -> void:
	params = p
	if _drop_mat != null:
		_drop_mat.set_shader_parameter("refract", int(p.get("screen_drops", 0)) >= 2)
	if _puddle_mat != null:
		_puddle_mat.set_shader_parameter("ripples", bool(p.get("puddle_ripples", true)))
	if int(p.get("screen_drops", 0)) == 0:
		drops.clear()


static func _make_textures() -> void:
	if _drop_tex != null:
		return
	# Drop: RG = refraction normal, A = coverage, slightly flattened at the
	# bottom where gravity pulls the water.
	var s := 64
	var img := Image.create(s, s, false, Image.FORMAT_RGBA8)
	for y in range(s):
		for x in range(s):
			var p := Vector2((float(x) - 31.5) / 31.5, (float(y) - 31.5) / 31.5)
			p.y *= 1.0 + 0.15 * clampf(p.y, 0.0, 1.0)
			var d := p.length()
			if d >= 1.0:
				img.set_pixel(x, y, Color(0.5, 0.5, 0.0, 0.0))
				continue
			var a := clampf((1.0 - d) * 6.0, 0.0, 1.0)
			img.set_pixel(x, y, Color(p.x * 0.5 + 0.5, p.y * 0.5 + 0.5, 0.0, a))
	_drop_tex = ImageTexture.create_from_image(img)
	_streak_tex = Fx.streak_tex()
	var head_streak := _streak_tex.get_image()
	head_streak.flip_y()
	_head_streak_tex = ImageTexture.create_from_image(head_streak)


# --- per frame --------------------------------------------------------------

func frame(dt: float) -> void:
	var g = game
	_time += dt
	var rain: float = g.rain_amount
	var W: float = g.W
	var H: float = g.H
	# Air rain.
	var vel := Vector2(g.rain_vx, g.rain_vy)
	var dir := vel.normalized() if vel.length_squared() > 1.0 else Vector2(0, 1)
	var density := float(params.get("rain_density", 0.6))
	var nlayers := int(params.get("rain_layers", 3))
	var night: float = g.get_night_factor()
	var tint := Color(0.72, 0.78, 0.88).lerp(Color(0.80, 0.84, 0.90), 1.0 - night)
	for i in range(3):
		var mi: MultiMeshInstance2D = _rain_layers[i]
		var cfg: Array = mi.get_meta("cfg")
		var on := rain > 0.02 and i >= 3 - nlayers
		mi.visible = on
		if not on:
			continue
		var count := int(float(cfg[0]) * density * clampf(rain * 1.15, 0.0, 1.0))
		mi.multimesh.visible_instance_count = count
		var spd := vel * float(cfg[3])
		_rain_offsets[i] = Vector2(_rain_offsets[i]) + spd * dt
		var area := Vector2(W + 240.0, H + 300.0)
		_rain_offsets[i] = Vector2(fposmod(_rain_offsets[i].x, area.x), fposmod(_rain_offsets[i].y, area.y))
		var m: ShaderMaterial = mi.material
		m.set_shader_parameter("offset", _rain_offsets[i])
		m.set_shader_parameter("area", area)
		m.set_shader_parameter("origin", Vector2(-120.0, -150.0))
		m.set_shader_parameter("dir", dir)
		# Motion blur: a streak is as long as the path its drop covers in a
		# 1/60 s shutter, so the near layer smears longest.
		m.set_shader_parameter("len", clampf(vel.length() * float(cfg[3]) * 0.024 * float(cfg[2]), 10.0, 70.0))
		m.set_shader_parameter("width", float(cfg[1]))
		m.set_shader_parameter("alpha", float(cfg[4]) * clampf(rain * 1.4, 0.0, 1.0))
		m.set_shader_parameter("tint", Vector3(tint.r, tint.g, tint.b))
	# Splashes.
	var ns := int(float(params.get("splashes", 90)) * clampf(rain * 1.2, 0.0, 1.0))
	_splash.visible = ns > 0
	if ns > 0:
		_splash.multimesh.visible_instance_count = mini(ns, _splash.multimesh.instance_count)
		_splash_mat.set_shader_parameter("time", _time)
		_splash_mat.set_shader_parameter("road_speed", float(g.speed) if g.running else float(g.DEMO_SPEED))
		_splash_mat.set_shader_parameter("area", Vector4(g.road_x - 20.0, -60.0, g.road_w + 40.0, H + 60.0))
		_splash_mat.set_shader_parameter("alpha", 0.45 * rain)
	# Puddles fill with rain and dry slower than the asphalt.
	var target := clampf(float(g.wetness) * 1.1 + rain * 0.2, 0.0, 1.0)
	puddle_level = lerpf(puddle_level, target, 1.0 - exp(-dt * (0.25 if target > puddle_level else 0.05)))
	_update_spray(dt)
	_update_drops(dt)
	# Lightning.
	var fl: float = g.lightning
	_flash_light.enabled = fl > 0.03
	if _flash_light.enabled:
		_flash_light.energy = fl * 1.4 * (0.72 + 0.28 * sin(float(g.t) * 83.0))
		_flash_light.shadow_enabled = int(params.get("shadow_lights", 0)) > 0
	_drop_layer.queue_redraw()


# --- spray --------------------------------------------------------------------

func _update_spray(dt: float) -> void:
	var g = game
	var wet: float = g.wetness
	for i in range(mist.size() - 1, -1, -1):
		var m: Dictionary = mist[i]
		m.life -= dt
		if m.life <= 0.0:
			mist.remove_at(i)
			continue
		m.p += m.v * dt
		m.v *= pow(0.2, dt)
	if wet < 0.08:
		return
	var cap := 160 if int(params.get("level", 1)) >= 2 else 90
	var spd: float = g.speed if g.running else float(g.DEMO_SPEED)
	var speed_k := clampf(spd / maxf(1.0, float(g.top_speed)), 0.2, 1.3)
	# Every car throws a plume from its rear wheels.
	for c in g.cars:
		var cy := float(c.y)
		if cy < -100.0 or cy > g.H + 80.0:
			continue
		if rng.randf() < wet * 0.5 * dt * 60.0 * 0.25 and mist.size() < cap:
			var side := -1.0 if rng.randf() < 0.5 else 1.0
			mist.append({"p": Vector2(float(c.x) + side * float(c.w) * 0.32, cy + float(c.h) * 0.48),
				"v": Vector2(side * rng.randf_range(10.0, 40.0), rng.randf_range(60.0, 160.0) * speed_k),
				"life": 0.6, "max": 0.6, "size": rng.randf_range(16.0, 30.0) * float(c.w) / float(g.car_w)})
	if g.running and not g.demo and mist.size() < cap:
		for side in [-1.0, 1.0]:
			if rng.randf() < wet * speed_k * dt * 60.0 * 0.45:
				mist.append({"p": Vector2(g.player_x + side * g.car_w * 0.34, g.player_y + g.car_h * 0.5),
					"v": Vector2(side * rng.randf_range(20.0, 60.0), spd * rng.randf_range(0.25, 0.45)),
					"life": 0.7, "max": 0.7, "size": rng.randf_range(22.0, 40.0)})
		# Driving through a puddle throws water out to both sides.
		if puddle_level > 0.2:
			var over := _over_puddle(g.player_x, g.player_y)
			if over != -1 and not _last_over.has(over):
				for k in range(18):
					var s := -1.0 if k % 2 == 0 else 1.0
					mist.append({"p": Vector2(g.player_x + s * g.car_w * 0.4, g.player_y + rng.randf_range(-20.0, 40.0)),
						"v": Vector2(s * rng.randf_range(160.0, 380.0), rng.randf_range(-60.0, 160.0)),
						"life": 0.55, "max": 0.55, "size": rng.randf_range(10.0, 22.0)})
				_burst_drops(6)
			_last_over = {} if over == -1 else {over: true}


func _over_puddle(x: float, y: float) -> int:
	var g = game
	for i in range(g.puddles.size()):
		var p: Dictionary = g.puddles[i]
		var py := fposmod(float(p.y) + float(g.scroll), float(g.ROAD_CYCLE))
		for k in [-1.0, 0.0, 1.0]:
			var yy: float = py + k * float(g.ROAD_CYCLE)
			if absf(yy - y) < float(p.ry) * 0.8 * puddle_level:
				var px: float = g.road_x + g.road_w * float(p.x)
				if absf(px - x) < float(p.rx) * 0.8 * puddle_level + g.car_w * 0.3:
					return i
	return -1


func paint_spray(ci: CanvasItem) -> void:
	var g = game
	var tex: Texture2D = g.glow_tex
	for m in mist:
		var k: float = float(m.life) / float(m.max)
		var r: float = float(m.size) * (1.6 - k * 0.6)
		var a := 0.20 * k * float(g.wetness)
		ci.draw_texture_rect(tex, Rect2(m.p - Vector2(r, r * 0.8), Vector2(r * 2.0, r * 1.6)), false, Color(0.86, 0.90, 0.96, a))
	# Game's own particles (brake smoke, spray, debris), drawn as soft lit
	# puffs so the spray glows inside headlight beams.
	for p in g.particles:
		var a2: float = clampf(float(p.life) / float(p.max), 0.0, 1.0)
		var col: Color = p.col
		col.a = col.a * a2
		var rr: float = float(p.size) * (0.5 + a2 * 0.5)
		if rr > 3.5 and col.a < 0.6:
			ci.draw_texture_rect(tex, Rect2(p.p - Vector2(rr, rr) * 1.6, Vector2(rr, rr) * 3.2), false, col)
		else:
			ci.draw_circle(p.p, rr, col)


# --- puddles & reflections ----------------------------------------------------

func paint_puddles(ci: CanvasItem) -> void:
	var g = game
	if puddle_level < 0.03:
		return
	var amb: Color = g.get_sky_ambient()
	_puddle_mat.set_shader_parameter("level", clampf(puddle_level * 0.85, 0.0, 0.95))
	_puddle_mat.set_shader_parameter("rain", float(g.rain_amount))
	_puddle_mat.set_shader_parameter("time", _time)
	_puddle_mat.set_shader_parameter("sky", Vector3(amb.r, amb.g, amb.b))
	for i in range(g.puddles.size()):
		var p: Dictionary = g.puddles[i]
		var base_y := fposmod(float(p.y) + float(g.scroll), float(g.ROAD_CYCLE))
		for k in [-1.0, 0.0, 1.0]:
			var y: float = base_y + k * float(g.ROAD_CYCLE)
			var rx := float(p.rx) * 1.3
			var ry := float(p.ry) * 1.3
			if y < -ry or y > g.H + ry:
				continue
			var x: float = g.road_x + g.road_w * float(p.x)
			ci.draw_set_transform(Vector2(x, y), float(p.rot), Vector2.ONE)
			# Per-puddle seed and ripple density travel in the vertex colour.
			ci.draw_rect(Rect2(-rx, -ry, rx * 2.0, ry * 2.0),
				Color(fposmod(float(p.phase), 1.0), rx / 60.0, ry / 60.0, 1.0))
	ci.draw_set_transform(Vector2.ZERO)


# Long, soft streaks under every lamp on wet asphalt (additive, unshaded).
func paint_reflections(ci: CanvasItem) -> void:
	var g = game
	var wet: float = g.wetness
	if wet < 0.05:
		return
	var lit = g.lighting_fx
	if lit == null:
		return
	var tex := _streak_tex
	var k := wet * (0.35 + 0.65 * clampf(puddle_level, 0.0, 1.0))
	var wob := sin(_time * 3.1) * 1.5
	for i in range(lit.count):
		var s: Dictionary = lit.sources[i]
		var e := float(s.energy) * k
		var col: Color = s.col
		var p: Vector2 = s.pos
		match int(s.kind):
			Lighting.HEAD:
				# The bright end follows the lens, and the reflection fades up the road.
				var tint := Color(col.r * e * 0.22, col.g * e * 0.22, col.b * e * 0.22, 1.0)
				var tilt := float(s.dir) + PI * 0.5
				if is_zero_approx(tilt):
					ci.draw_texture_rect(_head_streak_tex, Rect2(p.x + wob - 14.0, p.y - 230.0, 28.0, 230.0), false, tint)
				else:
					ci.draw_set_transform(p + Vector2(wob, 0.0), tilt)
					ci.draw_texture_rect(_head_streak_tex, Rect2(-14.0, -230.0, 28.0, 230.0), false, tint)
					ci.draw_set_transform(Vector2.ZERO)
			Lighting.TAIL, Lighting.BRAKE:
				var f := 0.55 if int(s.kind) == Lighting.BRAKE else 0.32
				ci.draw_texture_rect(tex, Rect2(p.x - 10.0 - wob, p.y + 6.0, 20.0, 170.0), false,
					Color(col.r * e * f, col.g * e * f, col.b * e * f, 1.0))
			Lighting.STREET:
				ci.draw_texture_rect(tex, Rect2(p.x - 18.0 + wob, p.y, 36.0, 260.0), false,
					Color(col.r * e * 0.30, col.g * e * 0.30, col.b * e * 0.30, 1.0))
			Lighting.NITRO, Lighting.SIGNAL, Lighting.BEACON, Lighting.SPARK:
				ci.draw_texture_rect(tex, Rect2(p.x - 8.0, p.y, 16.0, 90.0), false,
					Color(col.r * e * 0.3, col.g * e * 0.3, col.b * e * 0.3, 1.0))
	# Sky sheen on soaked asphalt by day.
	var day := 1.0 - float(g.get_night_factor())
	if wet > 0.25 and day > 0.05:
		var a := 0.05 * wet * day
		ci.draw_texture_rect(tex, Rect2(g.road_x + 40.0, 0.0, 60.0, g.H), false, Color(a * 0.8, a * 0.88, a, 1.0))
		ci.draw_texture_rect(tex, Rect2(g.road_x + g.road_w - 100.0, 0.0, 60.0, g.H), false, Color(a * 0.8, a * 0.88, a, 1.0))


# --- screen drops -------------------------------------------------------------

func _burst_drops(n: int) -> void:
	if int(params.get("screen_drops", 0)) == 0:
		return
	for i in range(n):
		if drops.size() >= _drop_cap():
			return
		_spawn_drop(rng.randf_range(8.0, 20.0), rng.randf_range(1.5, 3.5))


func _drop_cap() -> int:
	match int(params.get("level", 1)):
		1:
			return 24
		2:
			return 40
	return 60 if int(params.get("level", 1)) >= 3 else 0


# Drops gather where the airflow over the glass is slowest: along the edges of
# the screen. A distance from the nearest edge drawn with a squared random
# keeps about two thirds of the drops in the outer quarter on each side.
func _edge_x() -> float:
	var g = game
	var from_edge: float = g.W * 0.5 * pow(rng.randf(), 2.2)
	return from_edge if rng.randf() < 0.5 else g.W - from_edge


func _spawn_drop(r: float, life: float) -> void:
	var g = game
	drops.append({"p": Vector2(_edge_x(), rng.randf_range(-10.0, g.H * 0.92)),
		"r": r, "v": Vector2.ZERO, "life": life, "age": 0.0, "trail": 0.0,
		"stick": rng.randf_range(0.15, 0.9)})


# Every drop runs DOWN the screen. Small drops cling and creep, heavy ones
# run and leave a trail of beads; at speed the airflow only nudges them a
# little sideways, towards the edge they are already closest to.
func _update_drops(dt: float) -> void:
	var g = game
	var mode := int(params.get("screen_drops", 0))
	if mode == 0:
		return
	var rain: float = g.rain_amount
	var spd: float = g.speed if g.running else 0.0
	var fast := clampf((spd - 400.0) / 700.0, 0.0, 1.0)
	_drop_spawn += dt * rain * (6.0 + float(g.storm_amount) * 10.0)
	while _drop_spawn >= 1.0:
		_drop_spawn -= 1.0
		if drops.size() < _drop_cap():
			_spawn_drop(rng.randf_range(5.0, 13.0), rng.randf_range(2.5, 6.0))
	# Storm gusts throw a sudden volley.
	if float(g.storm_amount) > 0.3 and rng.randf() < dt * 0.35 * float(g.storm_amount):
		_burst_drops(10)
	# Overtaking through another car's spray.
	if g.running and float(g.wetness) > 0.3:
		for c in g.cars:
			var dy := float(c.y) - float(g.player_y)
			if dy > 0.0 and dy < float(g.car_h) * 1.3 and absf(float(c.x) - float(g.player_x)) < float(g.lane_w) * 0.9:
				if rng.randf() < dt * 3.0:
					_burst_drops(3)
	var wind_x: float = clampf(g.rain_vx / 900.0, -0.6, 0.6)
	var half: float = g.W * 0.5
	var approach := 1.0 - exp(-dt * DROP_RESPONSE)
	for i in range(drops.size() - 1, -1, -1):
		var d: Dictionary = drops[i]
		d.life -= dt
		d.age += dt
		var r: float = d.r
		# Downward speed grows with the drop's weight; small ones cling.
		var heavy := clampf((r - 6.0) / 10.0, 0.0, 1.0)
		var fall := lerpf(6.0 + 20.0 * (1.0 - float(d.stick)), 120.0 + r * 5.0, heavy) * (1.0 + fast * 0.32)
		# Wind and air flowing across the glass bend the path gently.
		var side := clampf((float(d.p.x) - half) / maxf(half * 0.45, 1.0), -1.0, 1.0)
		var drift := (side * 19.0 * fast + wind_x * (5.0 + 20.0 * fast)) * (0.4 + heavy * 0.6)
		var limit := fall * DROP_MAX_DRIFT
		var velocity: Vector2 = d.v.lerp(Vector2(clampf(drift, -limit, limit), fall), approach)
		d.v = velocity
		d.p += velocity * dt
		if heavy > 0.25:
			d.trail += dt
			if d.trail > 0.10 and velocity.y > 55.0 and drops.size() < _drop_cap() + 20:
				d.trail = 0.0
				drops.append({"p": d.p - velocity.normalized() * r * 0.92, "r": maxf(2.5, r * 0.30),
					"v": velocity * 0.06, "life": 1.1, "age": 0.0, "trail": 0.0, "stick": 1.0})
				# The running drop loses a little water to every bead it leaves.
				d.r = maxf(5.0, r * 0.985)
		if d.life <= 0.0 or d.p.y > g.H + 40.0 or d.p.x < -40.0 or d.p.x > g.W + 40.0:
			drops.remove_at(i)
	# Merging: drops that touch join into a heavier one that will run.
	if drops.size() > 1:
		for a in range(drops.size() - 1, 0, -1):
			var da: Dictionary = drops[a]
			var db: Dictionary = drops[a - 1]
			var contact := (float(da.r) + float(db.r)) * 0.55
			if da.p.distance_squared_to(db.p) < contact * contact:
				var area_a := float(da.r) * float(da.r)
				var area_b := float(db.r) * float(db.r)
				db.v = db.v.lerp(da.v, area_a / (area_a + area_b))
				db.r = minf(26.0, sqrt(area_a + area_b))
				db.life = maxf(float(db.life), float(da.life))
				db.age = maxf(float(db.age), float(da.age))
				drops.remove_at(a)


func paint_drops(ci: CanvasItem) -> void:
	if drops.is_empty():
		return
	var g = game
	var glint: Color = g.lighting_fx.ambient.lerp(Color(1.0, 0.92, 0.78), 0.4) if g.lighting_fx != null else Color.WHITE
	_drop_mat.set_shader_parameter("glint", Vector3(glint.r, glint.g, glint.b) * 1.2)
	for d in drops:
		var r: float = d.r
		var v: Vector2 = d.v
		var down := v.normalized() if v.length_squared() > 0.01 else Vector2.DOWN
		var stretch := Vector2.ONE.lerp(Vector2(0.82, 1.80), smoothstep(12.0, 320.0, v.length()))
		var a := smoothstep(0.0, 0.12, float(d.age)) * smoothstep(0.0, 0.60, float(d.life))
		var size := Vector2(r, r) * stretch * 2.0
		ci.draw_set_transform(d.p, Vector2.DOWN.angle_to(down))
		ci.draw_texture_rect(_drop_tex, Rect2(-size * 0.5, size), false,
			Color(clampf(r / 12.0, 0.5, 2.0), down.x * 0.5 + 0.5, down.y * 0.5 + 0.5, a))
	ci.draw_set_transform(Vector2.ZERO)


# --- lightning ----------------------------------------------------------------

func paint_lightning(ci: CanvasItem) -> void:
	var g = game
	var flash_a: float = g.lightning * (0.72 + 0.28 * sin(float(g.t) * 83.0))
	if flash_a <= 0.02:
		return
	for b in g.lightning_branches:
		ci.draw_polyline(b, Color(0.74, 0.84, 1.0, 0.30 * flash_a), 4.0, true)
		ci.draw_polyline(b, Color(0.96, 0.99, 1.0, 0.72 * flash_a), 1.4, true)
	if g.lightning_bolt.size() >= 2:
		ci.draw_polyline(g.lightning_bolt, Color(0.60, 0.76, 1.0, 0.24 * flash_a), 12.0, true)
		ci.draw_polyline(g.lightning_bolt, Color(0.86, 0.93, 1.0, 0.66 * flash_a), 5.0, true)
		ci.draw_polyline(g.lightning_bolt, Color(1.0, 1.0, 1.0, 0.95 * flash_a), 1.8, true)


func paint_lightning_bloom(ci: CanvasItem) -> void:
	var g = game
	var flash_a: float = g.lightning
	if flash_a <= 0.02 or g.lightning_bolt.size() < 2:
		return
	ci.draw_polyline(g.lightning_bolt, Color(0.7, 0.8, 1.0, flash_a), 14.0, true)
