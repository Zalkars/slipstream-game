extends RefCounted

# Shared by traffic spawning and the offline race sprite builder.
const TRAFFIC_COLORS := [
	Color("#e8e7e3"), Color("#b9bdc1"), Color("#3d4147"), Color("#1b1e22"),
	Color("#5e2b2b"), Color("#2c4a6e"), Color("#3c5c48"), Color("#c9c3b4"),
	Color("#7a1f24"), Color("#1f6a78"), Color("#d1a12c"), Color("#e3ddd0"),
	Color("#4b3b66"), Color("#8a5a2b"), Color("#2f6b3f"), Color("#9aa4ae"),
	Color("#df642c"), Color("#367fc2"), Color("#69b8ac"), Color("#bccb68"),
	Color("#b66b94"), Color("#e6c465"), Color("#73749e"), Color("#8eb9ce"),
]
const TRAILER_COLORS := [
	Color("#d9dad6"), Color("#c3c5c1"), Color("#8f969c"),
	Color("#b7b0a4"), Color("#6d7c86"), Color("#a4483f"),
	Color("#315c86"), Color("#537c59"), Color("#d1ad55"), Color("#7b5c87"),
]
const BUS_ACCENTS := [
	Color("#d64a3a"), Color("#2e7fbe"), Color("#3f9a5c"),
	Color("#e0a52a"), Color("#e8e4d8"),
	Color("#8758a5"), Color("#34aeb0"), Color("#df7840"),
]

const SILHOUETTES := ["hatch", "sedan", "offroad", "van", "muscle", "sport",
	"pickup", "ev", "hyper", "truck", "bus"]
const STRIPE_ACCENTS := [Color("#e6bd63"), Color("#70d4d7"), Color("#e46c4d"), Color("#e7e2d4")]


static func contrast(body: Color) -> Color:
	return Color(0.12, 0.13, 0.15) if body.v > 0.55 else Color(0.94, 0.93, 0.90)


# One finite appearance catalogue drives the spawner, the offline bake and QA.
# Commercial colours are curated pairs rather than a Cartesian product, so
# greater visual variety does not multiply the atlas memory by every colour.
static func variants(sil: String, colour_index: int) -> Array:
	var body: Color = TRAFFIC_COLORS[colour_index % TRAFFIC_COLORS.size()]
	var base := {"silhouette": sil, "color": body, "stripe": false,
		"stripe_color": contrast(body), "trailer": TRAILER_COLORS[0], "accent": BUS_ACCENTS[0]}
	var result: Array = [base]
	if sil in ["truck", "bus"]:
		var colours: Array = TRAILER_COLORS if sil == "truck" else BUS_ACCENTS
		var field := "trailer" if sil == "truck" else "accent"
		base[field] = colours[colour_index % colours.size()]
		var second: Dictionary = base.duplicate()
		second[field] = colours[(colour_index + 3) % colours.size()]
		result.append(second)
	else:
		var striped: Dictionary = base.duplicate()
		striped.stripe = true
		result.append(striped)
		if sil in ["hatch", "sedan", "muscle", "sport", "ev", "hyper"]:
			var accent: Color = STRIPE_ACCENTS[colour_index % STRIPE_ACCENTS.size()]
			# Keep accent stripes readable on bright and similarly hued paint.
			if Vector3(body.r - accent.r, body.g - accent.g, body.b - accent.b).length() < 0.40:
				accent = Color("#233852")
			if accent.is_equal_approx(contrast(body)):
				accent = Color("#e46c4d")
			var special: Dictionary = striped.duplicate()
			special.stripe_color = accent
			result.append(special)
	return result


static func pick(sil: String, body: Color) -> Dictionary:
	var index := TRAFFIC_COLORS.find(body)
	var choices := variants(sil, maxi(0, index))
	# Plain paint stays common; liveries are frequent enough to notice.
	if randf() < 0.45:
		return choices[0].duplicate()
	return choices[randi_range(1, choices.size() - 1)].duplicate()
