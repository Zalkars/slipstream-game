extends RefCounted

# Each draw has the same odds at any hour. Unallocated rolls are clear skies.
# SLIP3 codes keep their original odds and durations so old duels replay the
# same weather; from SLIP4 on, rain, storms and fog turn up within a run.
enum { CLEAR, CLOUDY, RAIN, STORM, FOG }
const CHANCES := [22, 20, 7, 13]  # cloudy, rain, storm, fog (percent)
const DURATION := [
	Vector2(40.0, 70.0),
	Vector2(35.0, 60.0),
	Vector2(40.0, 70.0),
	Vector2(28.0, 45.0),
	Vector2(35.0, 60.0),
]
const CHANCES_V3 := [15, 5, 1, 4]
const DURATION_V3 := [
	Vector2(90.0, 135.0),
	Vector2(55.0, 90.0),
	Vector2(32.0, 57.0),
	Vector2(23.0, 40.0),
	Vector2(35.0, 60.0),
]
const FORECAST_VERSION := 4


static func pick(roll: int, version := FORECAST_VERSION) -> int:
	var chances: Array = CHANCES if version >= FORECAST_VERSION else CHANCES_V3
	for i in range(chances.size()):
		roll -= int(chances[i])
		if roll < 0:
			return i + 1
	return CLEAR


static func duration(state: int, version := FORECAST_VERSION) -> Vector2:
	var table: Array = DURATION if version >= FORECAST_VERSION else DURATION_V3
	return table[clampi(state, 0, table.size() - 1)]
