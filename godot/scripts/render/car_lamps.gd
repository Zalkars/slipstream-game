class_name CarLamps
extends RefCounted

# Where the lamps of a given car are on screen. Anchors are measured offline
# from the real 3D models and 2D paintings (bake_race_lamps.gd ->
# art/race/lamps.gd), per class, so every light sits on its lens.

const LAMPS := preload("res://art/race/lamps.gd")

# Fallback for anything the table does not know (old body fractions).
const DEFAULT := {
	"head": [0.23, 0.03, 0.77, 0.03], "tail": [0.21, 0.965, 0.79, 0.965],
	"ind_f": [0.08, 0.04, 0.92, 0.04], "ind_r": [0.08, 0.96, 0.92, 0.96],
}


# Table entry for a car. 3D sprites are keyed by silhouette; 2D paintings by
# traffic kind + silhouette, or "player|silhouette" for the player's car.
static func anchors(car: Dictionary, sprite: Dictionary, is_player: bool) -> Dictionary:
	var sil := str(car.get("silhouette", "sedan"))
	if not sprite.is_empty():
		return LAMPS.LAMPS_3D.get(sil, DEFAULT)
	var key := ("player|%s" % sil) if is_player else ("%d|%s" % [int(car.get("kind", 0)), sil])
	return LAMPS.LAMPS_2D.get(key, LAMPS.LAMPS_3D.get(sil, DEFAULT))


# The box the art is drawn in: 3D sprites keep their aspect inside w x h
# (RaceArt.draw), 2D paintings fill it.
static func draw_box(sprite: Dictionary, w: float, h: float) -> Vector2:
	if sprite.is_empty():
		return Vector2(w, h)
	var sw := float(sprite.w)
	var sh := float(sprite.h)
	if sw < 1.0 or sh < 1.0:
		return Vector2(w, h)
	var k := minf(h * 0.96 / sh, w * 0.99 / sw)
	return Vector2(sw, sh) * k


# Fills out[cat] = [left, right] screen positions for head/tail/ind_f/ind_r.
static func points(a: Dictionary, center: Vector2, box: Vector2, rot: float, out: Dictionary) -> void:
	for cat in ["head", "tail", "ind_f", "ind_r"]:
		var v: Array = a.get(cat, DEFAULT[cat])
		var l := Vector2((float(v[0]) - 0.5) * box.x, (float(v[1]) - 0.5) * box.y)
		var r := Vector2((float(v[2]) - 0.5) * box.x, (float(v[3]) - 0.5) * box.y)
		if rot != 0.0:
			l = l.rotated(rot)
			r = r.rotated(rot)
		var pair: Array = out.get(cat, [])
		if pair.size() != 2:
			pair = [Vector2.ZERO, Vector2.ZERO]
			out[cat] = pair
		pair[0] = center + l
		pair[1] = center + r
