extends RefCounted

# Each draw has the same odds at any hour. Unallocated rolls are clear skies.
enum { CLEAR, CLOUDY, RAIN, STORM, FOG }
const CHANCES := [15, 5, 1, 4]  # cloudy, rain, storm, fog (percent)
const DURATION := [
	Vector2(90.0, 135.0),
	Vector2(55.0, 90.0),
	Vector2(32.0, 57.0),
	Vector2(23.0, 40.0),
	Vector2(35.0, 60.0),
]


static func pick(roll: int) -> int:
	for i in range(CHANCES.size()):
		roll -= int(CHANCES[i])
		if roll < 0:
			return i + 1
	return CLEAR
