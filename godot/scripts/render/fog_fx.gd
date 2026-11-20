class_name FogFx
extends Node

# Living fog (0.8.0 Stage 5).
#
# A full-screen fog shader rendered into a SubViewport at the preset's post
# resolution (1/4 .. 1) and stretched over the frame with premultiplied alpha.
#   * Up to four fbm octaves of a seamless noise texture, each layer moving
#     with the road at its own parallax and drifting with the wind: wisps,
#     holes and banks instead of a flat grey veil.
#   * Vertical density gradient: the top of the screen is what lies ahead, so
#     in dense fog traffic emerges from white at the last moment. Visibility
#     is balanced so the gap to the next car is still readable.
#   * Density along the route: banks in hollows and by water, thinning out.
#     The pattern is derived from the run seed and the distance driven, so in
#     a duel or daily challenge both players drive through the same fog.
#   * In-scattering: the brightest lights (headlight cones, lamps, stop
#     lights) light up the fog around them - visible beams, halos, red glow.

const FOG_SHADER := """
shader_type canvas_item;
render_mode unshaded, blend_disabled;
uniform sampler2D noise : repeat_enable, filter_linear;
uniform vec2 screen = vec2(720.0, 1560.0);
uniform float density = 0.0;
uniform float scroll = 0.0;
uniform vec2 wind = vec2(0.0);
uniform float time = 0.0;
uniform int octaves = 2;
uniform vec3 fog_col = vec3(0.72, 0.76, 0.80);
uniform float bank_top = 1.0;
uniform float bank_bottom = 1.0;
uniform int light_count = 0;
uniform vec4 l_pos[8];   // xy position, z rotation, w size
uniform vec4 l_col[8];   // rgb colour * energy, a kind (0 cone, 1 point)

float fbm(vec2 p) {
	float a = 0.0;
	float w = 0.55;
	float tot = 0.0;
	for (int i = 0; i < 4; i++) {
		if (i >= octaves) { break; }
		vec4 n = texture(noise, p);
		a += (i == 0 ? n.r : (i == 1 ? n.g : (i == 2 ? n.b : n.a))) * w;
		tot += w;
		w *= 0.5;
		p = p * 2.03 + vec2(0.17, 0.31);
	}
	return a / max(tot, 0.001);
}

void fragment() {
	vec2 px = UV * screen;
	float ahead = 1.0 - UV.y;  // 1 at the top of the screen (far ahead)
	// Two layers at different parallax: low fog hugging the road moves with
	// it, the upper layer slower; both drift with the wind.
	vec2 p1 = vec2(px.x, px.y - scroll) / 900.0 + wind * time * 0.010;
	vec2 p2 = vec2(px.x * 0.7, px.y - scroll * 0.55) / 1400.0 + wind * time * 0.006 + vec2(0.41, 0.13);
	float n = fbm(p1) * 0.6 + fbm(p2) * 0.4;
	float wisps = smoothstep(0.25, 0.85, n);
	float bank = mix(bank_bottom, bank_top, ahead);
	float grad = mix(0.32, 1.0, pow(ahead, 1.35));
	float d = density * bank * grad * (0.55 + 0.75 * wisps);
	d += density * 0.55 * smoothstep(0.62, 1.0, ahead) * bank_top;
	// Soft saturation: thick fog keeps its texture instead of flattening.
	float a = min(1.0 - exp(-d * 1.6), 0.94);

	vec3 scatter = vec3(0.0);
	for (int i = 0; i < 8; i++) {
		if (i >= light_count) { break; }
		vec4 lp = l_pos[i];
		vec4 lc = l_col[i];
		vec2 dv = px - lp.xy;
		float s = 0.0;
		if (lc.a < 0.5) {
			// Headlight cone pointing up (rotated): a visible beam in the fog.
			float c = cos(-lp.z);
			float sn = sin(-lp.z);
			vec2 loc = vec2(dv.x * c - dv.y * sn, dv.x * sn + dv.y * c);
			float along = -loc.y;
			float width = 18.0 + along * 0.32;
			s = exp(-pow(loc.x / width, 2.0) * 1.6) * exp(-max(along, 0.0) / (lp.w * 0.75)) * smoothstep(-20.0, 30.0, along);
			s += exp(-dot(dv, dv) / (60.0 * 60.0)) * 0.6;
		} else {
			// Lamp halo / glow dome.
			float r = length(dv) / max(lp.w * 0.55, 1.0);
			s = 1.0 / (1.0 + r * r * 6.0) * (1.0 - smoothstep(0.8, 1.6, r));
		}
		scatter += lc.rgb * s;
	}
	// Light scatters only where there is fog to scatter it.
	vec3 rgb = fog_col * a + scatter * clamp(density * (0.6 + wisps), 0.0, 1.2) * 0.55;
	COLOR = vec4(rgb, a);
}
"""

var game  # Game
var stack  # RenderStack
var params: Dictionary = {}
var vp: SubViewport
var rect: ColorRect
var view: TextureRect
var mat: ShaderMaterial
var _screen := Vector2(720, 1560)
var _scale := 0.5
var _time := 0.0
var _pos := PackedVector4Array()
var _col := PackedVector4Array()

static var _noise_tex: ImageTexture


func setup(p_game, p_stack) -> void:
	game = p_game
	stack = p_stack
	_make_noise()
	vp = SubViewport.new()
	vp.name = "FogView"
	vp.transparent_bg = true
	vp.disable_3d = true
	vp.gui_disable_input = true
	vp.render_target_update_mode = SubViewport.UPDATE_DISABLED
	stack.add_child(vp)
	rect = ColorRect.new()
	var sh := Shader.new()
	sh.code = FOG_SHADER
	mat = ShaderMaterial.new()
	mat.shader = sh
	mat.set_shader_parameter("noise", _noise_tex)
	rect.material = mat
	vp.add_child(rect)
	view = TextureRect.new()
	view.name = "Fog"
	view.texture = vp.get_texture()
	view.stretch_mode = TextureRect.STRETCH_SCALE
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var premul := CanvasItemMaterial.new()
	premul.blend_mode = CanvasItemMaterial.BLEND_MODE_PREMULT_ALPHA
	view.material = premul
	view.visible = false
	# Fog sits under bloom (lamps glow through it) and under the screen drops.
	stack.overlay.add_child(view)
	stack.overlay.move_child(view, 0)
	_pos.resize(8)
	_col.resize(8)


func apply_params(p: Dictionary) -> void:
	params = p
	mat.set_shader_parameter("octaves", int(p.get("fog_octaves", 2)))


func set_post_scale(s: float) -> void:
	_scale = clampf(s, 0.2, 1.0)
	_resize()


func relayout(size: Vector2) -> void:
	_screen = size
	_resize()


func _resize() -> void:
	if vp == null:
		return
	var size := Vector2i(maxi(16, int(_screen.x * _scale)), maxi(16, int(_screen.y * _scale)))
	vp.size = size
	rect.position = Vector2.ZERO
	rect.size = Vector2(size)
	view.position = Vector2.ZERO
	view.size = _screen
	mat.set_shader_parameter("screen", _screen)


static func _make_noise() -> void:
	if _noise_tex != null:
		return
	var chans: Array = []
	for i in range(4):
		var fn := FastNoiseLite.new()
		fn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
		fn.frequency = 0.02 * pow(1.9, i)
		fn.seed = 501 + i * 17
		fn.fractal_type = FastNoiseLite.FRACTAL_FBM
		fn.fractal_octaves = 2
		var img := fn.get_seamless_image(128, 128, false, false, 0.1, true)
		img.convert(Image.FORMAT_L8)
		chans.append(img.get_data())
	var data := PackedByteArray()
	data.resize(128 * 128 * 4)
	for i in range(128 * 128):
		data[i * 4] = chans[0][i]
		data[i * 4 + 1] = chans[1][i]
		data[i * 4 + 2] = chans[2][i]
		data[i * 4 + 3] = chans[3][i]
	_noise_tex = ImageTexture.create_from_image(Image.create_from_data(128, 128, false, Image.FORMAT_RGBA8, data))


# Fog banks along the route: 0.35 .. 1.25, smooth over ~1500 px, from the
# run seed so both duel players meet the same banks at the same distance.
static func bank_at(run_seed: int, v: float) -> float:
	var s := float(posmod(run_seed, 9973)) * 0.731
	var a := sin(v / 1700.0 + s) * 0.5 + sin(v / 4100.0 + s * 2.3) * 0.35 + sin(v / 830.0 + s * 0.7) * 0.15
	return clampf(0.80 + a * 0.45, 0.35, 1.25)


func density_now() -> float:
	var g = game
	var f: float = g.fog_amount
	# Dawn: a thin ground haze that burns off as the sun climbs.
	var tod: float = g.time_of_day
	var dawn := exp(-pow(fposmod(tod - 0.97 + 0.5, 1.0) - 0.5, 2.0) / 0.004)
	return clampf(f * 0.95 + dawn * 0.10 + float(g.rain_amount) * 0.08, 0.0, 1.0)


func frame(dt: float) -> void:
	var g = game
	_time += dt
	var dens := density_now()
	var on := dens > 0.015
	view.visible = on
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS if on else SubViewport.UPDATE_DISABLED
	if not on:
		return
	var run_seed: int = g.active_run_seed if not g.demo else 1
	var v_top: float = g.scroll + g.H
	var v_bot: float = g.scroll
	var night: float = g.get_night_factor()
	var amb: Color = g.get_sky_ambient()
	var pale := Color(0.74, 0.77, 0.80) * amb
	pale = pale.lerp(Color(0.10, 0.12, 0.16), night * 0.75)
	# Morning fog with a low sun is warmer.
	var warm := clampf((amb.r - amb.b) * 1.5, 0.0, 0.4) * (1.0 - night)
	pale = pale.lerp(Color(0.95, 0.82, 0.66), warm)
	mat.set_shader_parameter("density", dens)
	mat.set_shader_parameter("scroll", float(g.scroll))
	mat.set_shader_parameter("wind", Vector2(float(g.rain_vx) / 600.0 - float(g.wind) * 0.4, 0.15))
	mat.set_shader_parameter("time", _time)
	mat.set_shader_parameter("fog_col", Vector3(pale.r, pale.g, pale.b))
	mat.set_shader_parameter("bank_top", bank_at(run_seed, v_top))
	mat.set_shader_parameter("bank_bottom", bank_at(run_seed, v_bot))
	# The brightest lights scatter in the fog.
	var lit = g.lighting_fx
	var n := 0
	var maxl := int(params.get("fog_lights", 4))
	if lit != null:
		for oi in range(lit._req_count):
			if n >= maxl:
				break
			var r: Dictionary = lit._requests[lit._order[oi]] if oi < lit._order.size() else lit._requests[oi]
			var c: Color = r.col
			var e := float(r.energy)
			var p: Vector2 = r.pos
			if p.y < -400.0 or p.y > g.H + 200.0:
				continue
			_pos[n] = Vector4(p.x, p.y, float(r.rot), float(r.size))
			_col[n] = Vector4(c.r * e, c.g * e, c.b * e, float(r.kind))
			n += 1
	mat.set_shader_parameter("light_count", n)
	mat.set_shader_parameter("l_pos", _pos)
	mat.set_shader_parameter("l_col", _col)
	view.position = Vector2.ZERO

