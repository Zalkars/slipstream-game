class_name Asphalt
extends RefCounted

# Procedural road material (0.8.0 Stage 3).
#
# One quad per frame covers the carriageway; everything else happens in the
# road shader, so the whole surface costs a handful of texture taps per pixel:
#   * a 256x256 seamless detail texture (R aggregate grain, G mid wear,
#     B crack network, A stains / low spots) and its normal map, generated
#     once with FastNoiseLite and Image.bump_map_to_normal_map (native code);
#   * surface types that change along the route with soft transitions:
#     fresh dark asphalt, old grey asphalt with cracks and patches, rutted
#     lanes that hold water, concrete slabs with joints and steel expansion
#     joints, and repair zones with milling and yellow temporary lines;
#   * wear and weather: wheel-track polish, oil drips, manholes, cat's eyes,
#     uneven drying (tracks first, low spots and ruts last), wet darkening
#     and specular for the 2D lights, a soft sun glint by day.
# Road coordinate v = scroll - screen_y grows with the distance driven.

const TILE := 256
# Surface types last ~1800 m of road and fade into the next over ~125 m.
const SEG_LEN := 21600.0
const SEG_BLEND := 1500.0
# The aggregate texture: 512 texels over 256 canvas px = one texel per device
# pixel on a 1440-wide phone, so the asphalt is never magnified (blurred).
const GRAIN := 512

const ROAD_SHADER := """
shader_type canvas_item;

uniform sampler2D detail : repeat_enable, filter_linear_mipmap;
uniform sampler2D detail_n : hint_normal, repeat_enable, filter_linear_mipmap;
uniform sampler2D grain_tex : repeat_enable, filter_linear_mipmap;
uniform float seg_blend = 1500.0;
uniform float scroll = 0.0;
uniform float road_x = 101.0;
uniform float road_w = 518.0;
uniform float lane_w = 129.5;
uniform float wetness = 0.0;
uniform float sun = 1.0;
uniform float detail_level = 2.0;
uniform float normal_strength = 1.0;
uniform float seg_len = 21600.0;
uniform float seed = 0.0;

varying vec2 world;
varying float v_spec;
varying float v_shine;

void vertex() {
	world = VERTEX;
}

float hash1(float n) { return fract(sin(n * 12.9898 + seed * 78.233) * 43758.5453); }

// Surface type parameters:
//   a = (tint 0 dark..1 grey, cracks, ruts, concrete)
//   b = (milling, marking wear, yellow lines, patches)
//   c = (porous, chip seal, red surfacing, patchwork)
void seg_params(float idx, out vec4 a, out vec4 b, out vec4 c) {
	float r = hash1(idx);
	c = vec4(0.0);
	if (r < 0.17) {        // fresh dark asphalt, bright paint
		a = vec4(0.62, 0.0, 0.15, 0.0); b = vec4(0.0, 0.0, 0.0, 0.05);
	} else if (r < 0.36) { // old grey: cracks, patches, worn paint
		a = vec4(1.0, 1.0, 0.35, 0.0); b = vec4(0.0, 0.65, 0.0, 1.0);
	} else if (r < 0.48) { // rutted lanes
		a = vec4(0.85, 0.35, 1.0, 0.0); b = vec4(0.0, 0.35, 0.0, 0.3);
	} else if (r < 0.58) { // concrete slabs (bridge / flyover)
		a = vec4(1.0, 0.15, 0.1, 1.0); b = vec4(0.0, 0.25, 0.0, 0.0);
	} else if (r < 0.66) { // road repair: milling, yellow temporary lines
		a = vec4(0.78, 0.2, 0.2, 0.0); b = vec4(1.0, 0.85, 1.0, 0.6);
	} else if (r < 0.77) { // porous drainage asphalt: very dark, open, dries fast
		a = vec4(0.35, 0.0, 0.1, 0.0); b = vec4(0.0, 0.1, 0.0, 0.0); c = vec4(1.0, 0.0, 0.0, 0.0);
	} else if (r < 0.88) { // chip seal: light, coarse stones on top
		a = vec4(0.9, 0.25, 0.2, 0.0); b = vec4(0.0, 0.45, 0.0, 0.2); c = vec4(0.0, 1.0, 0.0, 0.0);
	} else if (r < 0.93) { // red high-friction surfacing
		a = vec4(0.7, 0.0, 0.1, 0.0); b = vec4(0.0, 0.15, 0.0, 0.0); c = vec4(0.0, 0.3, 1.0, 0.0);
	} else {               // patchwork: decades of repairs
		a = vec4(0.95, 0.6, 0.4, 0.0); b = vec4(0.0, 0.55, 0.0, 1.0); c = vec4(0.0, 0.0, 0.0, 1.0);
	}
}

void fragment() {
	float u = world.x - road_x;
	float v = scroll - world.y;
	// Surface type with a soft transition into the next segment.
	float sidx = floor(v / seg_len);
	float st = v / seg_len - sidx;
	vec4 pa; vec4 pb; vec4 pc4; vec4 qa; vec4 qb; vec4 qc;
	seg_params(sidx, pa, pb, pc4);
	seg_params(sidx + 1.0, qa, qb, qc);
	float bl = smoothstep(1.0 - seg_blend / seg_len, 1.0, st);
	// A ragged edge: transitions follow the aggregate, not a ruler.
	vec4 d = texture(detail, vec2(u, v) / 256.0);
	vec4 big = texture(detail, vec2(u, v) / 1100.0 + vec2(0.37, 0.71));
	// A ragged, patchy front: the new surface arrives in tongues, not a line.
	float rag = (big.g - 0.5) * 0.6 + (d.g - 0.5) * 0.25;
	bl = clamp(bl + rag * 4.0 * bl * (1.0 - bl), 0.0, 1.0);
	vec4 A = mix(pa, qa, bl);
	vec4 B = mix(pb, qb, bl);
	vec4 C = mix(pc4, qc, bl);

	// Lane geometry: distance to the nearest wheel track and lane centre.
	float lx = u / lane_w;
	float lf = fract(lx) - 0.5;
	float track = exp(-pow((abs(lf) - 0.33) / 0.085, 2.0));
	float centre = exp(-pow(lf / 0.12, 2.0));

	// --- albedo ---
	vec3 asphalt = mix(vec3(0.245, 0.25, 0.262), vec3(0.39, 0.392, 0.398), A.x);
	vec3 concrete = vec3(0.53, 0.53, 0.505);
	vec3 col = mix(asphalt, concrete, A.w);
	col = mix(col, vec3(0.20, 0.205, 0.215), C.x);              // porous
	col = mix(col, vec3(0.43, 0.41, 0.38), C.y * 0.8);          // chip seal
	col = mix(col, vec3(0.40, 0.17, 0.14), C.z * 0.85);         // red surfacing
	float grain = texture(grain_tex, vec2(u, v) / 256.0).r;
	col *= 0.80 + grain * (0.38 + C.x * 0.2);
	// Chip seal and porous mixes: individual stones catch the light.
	float chip = smoothstep(0.70, 0.80, grain) * (C.y * 0.16 + C.x * 0.05);
	col += vec3(chip);
	col *= 0.90 + big.g * 0.20;
	float h = grain;  // height for the hand-made normal tweaks
	if (detail_level > 0.5) {
		// Repairs feather into the aggregate and end inside their placement cell.
		vec2 patch_pos = vec2(u / 128.0, v / 240.0);
		vec2 pc = floor(patch_pos);
		float pr = hash1(pc.x * 17.0 + pc.y * 131.0);
		vec2 edge = (fract(patch_pos) - vec2(0.5)) * vec2(1.0, 1.16);
		edge += (vec2(pr, fract(pr * 13.71)) - 0.5) * 0.10;
		float shape = length(edge) + (d.g - 0.5) * 0.10;
		float patch = step(0.89 - C.w * 0.36, pr) * (1.0 - smoothstep(0.24, 0.39, shape)) * B.w;
		// Patchwork repairs come in every age: fresh black to faded grey.
		float age = hash1(pc.x * 7.0 + pc.y * 59.0) * C.w;
		col = mix(col, mix(vec3(0.21, 0.215, 0.225), vec3(0.33, 0.33, 0.335), age) * (0.85 + grain * 0.3), patch * 0.72);
		// Cracks: a thin network at a larger scale, only where the road is
		// tired (masked by the low-frequency wear), never a cobblestone grid.
		float cn = texture(detail, vec2(u, v) / 430.0 + vec2(0.21, 0.08)).b;
		float crack = smoothstep(0.91, 0.99, cn) * A.y * (1.0 - patch) * smoothstep(0.50, 0.78, big.b);
		col *= 1.0 - crack * 0.30;
		h -= crack * 0.8;
		// Ruts and tyre polish.
		col *= 1.0 - track * (0.06 + 0.16 * A.z);
		// Oil drips between the wheel tracks.
		float oil = smoothstep(0.74, 0.88, texture(detail, vec2(u * 1.7, v) / 620.0 + vec2(0.13, 0.52)).a) * centre * (0.4 + 0.6 * big.b);
		col *= 1.0 - oil * 0.45;
		// Concrete: transverse joints and a steel expansion joint every 4 slabs.
		float slab = mod(v, 360.0);
		float joint = (1.0 - smoothstep(0.0, 2.2, abs(slab - 180.0))) * A.w;
		float steel = (1.0 - smoothstep(4.0, 7.0, abs(mod(v, 1440.0) - 720.0))) * A.w;
		col = mix(col, vec3(0.08), joint * 0.8);
		col = mix(col, vec3(0.42, 0.44, 0.46), steel);
		h -= joint * 0.7;
		// Milling: fine longitudinal grooves of a fresh repair.
		float mill = B.x * (0.5 + 0.5 * sin(u * 1.35));
		col *= 1.0 - mill * 0.12;
		h += mill * 0.25;
		// Manholes: a cast-iron lid in a random lane every ~1400 px.
		float mcell = floor(v / 1400.0);
		float mlane = floor(hash1(mcell * 3.1) * 4.0);
		vec2 mc = vec2((mlane + 0.5) * lane_w + (hash1(mcell * 5.7) - 0.5) * lane_w * 0.3, mcell * 1400.0 + 700.0);
		float md = length(vec2(u, v) - mc);
		float lid = 1.0 - smoothstep(24.0, 26.0, md);
		float ring = lid * smoothstep(19.0, 21.0, md);
		float bars = lid * step(0.5, fract((u - mc.x) / 7.0)) * (1.0 - ring);
		float has_lid = step(0.45, hash1(mcell * 9.3));
		col = mix(col, vec3(0.16, 0.16, 0.17) * (0.8 + 0.4 * bars), lid * has_lid);
		h += (ring * 0.6 - bars * 0.3) * has_lid;
	}

	// --- markings ---
	float paint = 0.0;
	float wear = B.y;
	float edge_l = step(12.0, u) * step(u, 19.0);
	float edge_r = step(road_w - 19.0, u) * step(u, road_w - 12.0);
	paint = max(edge_l, edge_r);
	float lb = u / lane_w;
	float near_line = abs(lb - floor(lb + 0.5)) * lane_w;
	float inner = step(0.5, lb) * step(lb, 3.5);
	float dash = step(1.0 - 96.0 / 250.0, fract(v / 250.0));
	paint = max(paint, step(near_line, 3.5) * dash * inner);
	// Worn paint: the aggregate shows through.
	float keep = smoothstep(wear * 0.8 - 0.08, wear * 0.8 + 0.08, grain * 0.45 + big.r * 0.55 + 0.12);
	paint *= mix(1.0, keep, wear);
	vec3 paint_col = vec3(0.93, 0.92, 0.87);
	// Repair zones: a thin yellow double line straddling the lane boundary
	// (two 3 px lines 4.5 px either side), replacing the white dashes.
	float yel = B.z * step(abs(near_line - 4.5), 1.5) * inner;
	paint *= 1.0 - B.z * 0.85 * inner * step(near_line, 8.0);
	col = mix(col, paint_col, paint * 0.95);
	col = mix(col, vec3(0.92, 0.70, 0.12), yel);
	h += (paint + yel) * 0.35;
	// Cat's eyes on the edge lines.
	float stud = (1.0 - smoothstep(2.0, 3.0, length(vec2(min(abs(u - 15.5), abs(u - road_w + 15.5)), mod(v, 190.0) - 95.0))));
	col = mix(col, vec3(1.0, 0.95, 0.78), stud);

	// Edge darkening near the kerb (grime).
	float kerb = 1.0 - smoothstep(0.0, 34.0, min(u, road_w - u));
	col *= 1.0 - kerb * 0.22;

	// --- water ---
	// Drying is uneven: wheel tracks clear first, ruts and low spots last.
	float bias = track * 0.30 * (1.0 - A.z) - (big.a - 0.5) * 0.55 - track * A.z * 0.25 + paint * 0.1;
	float wet = clamp(wetness * 1.35 - bias * (1.0 - wetness * 0.6), 0.0, 1.0) * step(0.001, wetness);
	wet *= 1.0 - C.x * 0.55;  // drainage asphalt sheds water
	col *= 1.0 - wet * (0.28 - A.w * 0.08);
	col = mix(col, col * vec3(0.92, 0.96, 1.05), wet);

	COLOR = vec4(col, 1.0);

	// --- normals & specular for the 2D lights ---
	vec3 n = texture(detail_n, vec2(u, v) / 256.0).xyz * 2.0 - 1.0;
	n.xy *= 1.0 + C.y * 0.6 + C.x * 0.3;
	n.xy *= normal_strength * (1.0 - wet * 0.75);
	n = normalize(n);
	//NORMALS NORMAL_MAP = n * 0.5 + 0.5;
	float spec = 0.05 + wet * 0.85 + paint * 0.25 + stud * 0.9;
	v_spec = spec;
	v_shine = mix(0.12, 0.92, wet);
	// Soft sun glint by day (the sun is not a Light2D: it would light every
	// layer at full-screen cost).
	vec3 L = normalize(vec3(-0.35, 0.55, 0.76));
	float g = pow(max(dot(n, normalize(L + vec3(0.0, 0.0, 1.0))), 0.0), 18.0 + wet * 60.0);
	COLOR.rgb += vec3(1.0, 0.97, 0.9) * g * sun * (0.04 + wet * 0.30);
}

// Lambert + Blinn specular. Wet asphalt is a poor but long mirror: the
// highlight of every lamp gets tight and bright, which is what reads as
// "wet" at night. Shadows are applied by the engine after this.
void light() {
	// Relief relative to a flat road, so a lamp far away still lights the
	// asphalt fully and the normal map only adds texture.
	float nl = clamp(max(dot(NORMAL, LIGHT_DIRECTION), 0.0) / max(LIGHT_DIRECTION.z, 0.08), 0.0, 1.8);
	vec3 hv = normalize(LIGHT_DIRECTION + vec3(0.0, 0.0, 1.0));
	float sp = pow(max(dot(NORMAL, hv), 0.0), mix(6.0, 120.0, v_shine)) * v_spec * (1.0 + v_shine * 1.6);
	LIGHT = vec4(LIGHT_COLOR.rgb * LIGHT_ENERGY * (COLOR.rgb * nl + vec3(sp)), LIGHT_COLOR.a);
}
"""

var game  # Game
var params: Dictionary = {}
var material: ShaderMaterial
var _normals := true

static var _detail: ImageTexture
static var _detail_n: ImageTexture
static var _grain: ImageTexture
static var _shaders: Dictionary = {}


func _init(p_game) -> void:
	game = p_game
	_make_textures()
	material = ShaderMaterial.new()
	material.shader = _shader(true)
	material.set_shader_parameter("detail", _detail)
	material.set_shader_parameter("detail_n", _detail_n)
	material.set_shader_parameter("grain_tex", _grain)
	_apply_surface_spacing()


static func surface_segment_length() -> float:
	return maxf(SEG_BLEND * 2.0, float(ProjectSettings.get_setting("slipstream/road/surface_segment_length", SEG_LEN)))


func _apply_surface_spacing() -> void:
	material.set_shader_parameter("seg_len", surface_segment_length())
	material.set_shader_parameter("seg_blend", SEG_BLEND)


static func _shader(normals: bool) -> Shader:
	if not _shaders.has(normals):
		var sh := Shader.new()
		sh.code = ROAD_SHADER.replace("//NORMALS ", "") if normals else ROAD_SHADER
		_shaders[normals] = sh
	return _shaders[normals]


func apply_params(p: Dictionary) -> void:
	params = p
	_normals = bool(p.get("normal_maps", true))
	material.shader = _shader(_normals)
	material.set_shader_parameter("detail", _detail)
	material.set_shader_parameter("detail_n", _detail_n)
	material.set_shader_parameter("grain_tex", _grain)
	_apply_surface_spacing()
	material.set_shader_parameter("detail_level", float(p.get("asphalt_detail", 1)))


# Seamless 256x256 detail texture and its normal map, generated once per run of
# the game (shared by every Game instance) with native noise and bump-to-normal.
static func _make_textures() -> void:
	if _detail != null:
		return
	var grain := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.09, 3, 11, FastNoiseLite.FRACTAL_FBM)
	var wear := _noise(FastNoiseLite.TYPE_SIMPLEX_SMOOTH, 0.022, 2, 23, FastNoiseLite.FRACTAL_FBM)
	var cell := FastNoiseLite.new()
	cell.noise_type = FastNoiseLite.TYPE_CELLULAR
	cell.cellular_return_type = FastNoiseLite.RETURN_DISTANCE2_SUB
	cell.frequency = 0.028
	cell.seed = 37
	cell.fractal_type = FastNoiseLite.FRACTAL_NONE
	var crack := cell.get_seamless_image(TILE, TILE, true, false, 0.1, true)
	var stain := _noise(FastNoiseLite.TYPE_CELLULAR, 0.018, 1, 41, FastNoiseLite.FRACTAL_NONE)
	for img in [grain, wear, crack, stain]:
		img.convert(Image.FORMAT_L8)
	var g := grain.get_data()
	var w := wear.get_data()
	var c := crack.get_data()
	var s := stain.get_data()
	var n := TILE * TILE
	var rgba := PackedByteArray()
	rgba.resize(n * 4)
	for i in range(n):
		var gi := g[i]
		var ci := c[i]
		rgba[i * 4] = gi
		rgba[i * 4 + 1] = w[i]
		rgba[i * 4 + 2] = ci
		rgba[i * 4 + 3] = s[i]
	var detail := Image.create_from_data(TILE, TILE, false, Image.FORMAT_RGBA8, rgba)
	detail.generate_mipmaps()
	_detail = ImageTexture.create_from_image(detail)
	# Sharp aggregate at 512: five octaves, the finest about one texel, plus
	# its normal map - both generated natively (no per-pixel GDScript).
	var gfn := FastNoiseLite.new()
	gfn.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	gfn.frequency = 0.075
	gfn.seed = 11
	gfn.fractal_type = FastNoiseLite.FRACTAL_FBM
	gfn.fractal_octaves = 5
	gfn.fractal_gain = 0.62
	var gimg := gfn.get_seamless_image(GRAIN, GRAIN, false, false, 0.1, true)
	gimg.convert(Image.FORMAT_L8)
	var gtex := gimg.duplicate()
	gtex.generate_mipmaps()
	_grain = ImageTexture.create_from_image(gtex)
	gimg.convert(Image.FORMAT_RGBA8)
	gimg.bump_map_to_normal_map(3.0)
	gimg.generate_mipmaps()
	_detail_n = ImageTexture.create_from_image(gimg)


static func _noise(kind: int, freq: float, octaves: int, seed_val: int, fractal: int) -> Image:
	var fn := FastNoiseLite.new()
	fn.noise_type = kind
	fn.frequency = freq
	fn.seed = seed_val
	fn.fractal_type = fractal
	fn.fractal_octaves = octaves
	return fn.get_seamless_image(TILE, TILE, false, false, 0.1, true)


func paint_surface(ci: CanvasItem) -> void:
	var g = game
	var m := material
	m.set_shader_parameter("scroll", float(g.scroll))
	m.set_shader_parameter("road_x", float(g.road_x))
	m.set_shader_parameter("road_w", float(g.road_w))
	m.set_shader_parameter("lane_w", float(g.lane_w))
	m.set_shader_parameter("wetness", float(g.wetness))
	var night: float = g.get_night_factor()
	m.set_shader_parameter("sun", (1.0 - night) * (1.0 - float(g.cloud_amount) * 0.7))
	m.set_shader_parameter("seed", float(int(g.active_run_seed) % 997) if not g.demo else 0.0)
	# The surface itself is drawn by the strips (draw_rect_part).


func draw_rect_part(ci: CanvasItem, y: float, h: float) -> void:
	ci.draw_rect(Rect2(game.road_x, y, game.road_w, h + 0.5), Color.WHITE)


func paint_markings(_ci: CanvasItem) -> void:
	pass  # markings are part of the road shader
