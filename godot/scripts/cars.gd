class_name Cars
extends RefCounted

# Car roster: price in coins, speed in px/s, ratings are cosmetic (1..10).

const LIST := [
	{
		"id": 0,
		"name": "HATCH",
		"sub": "ГОРОДСКОЙ ХЭТЧБЕК",
		"desc": "Лёгкий и послушный. С него начинают все.",
		"price": 0,
		"speed": 740.0,
		"top": 1100.0,
		"grow": 340.0,
		"handling": 12.0,
		"color": "#b32b26",
		"stripe": true,
		"stripe_color": "#f0ede4",
		"wing": false,
	},
	{
		"id": 1,
		"name": "SEDAN GT",
		"sub": "СПОРТИВНЫЙ СЕДАН",
		"desc": "Быстрее и стабильнее. Хороший шаг вперёд.",
		"price": 600,
		"speed": 775.0,
		"top": 1170.0,
		"grow": 355.0,
		"handling": 12.4,
		"color": "#d8dade",
		"stripe": false,
		"stripe_color": "#2b3036",
		"wing": false,
	},
	{
		"id": 2,
		"name": "MUSCLE",
		"sub": "АМЕРИКАНСКИЙ МАСКЛ",
		"desc": "Тяжёлый характер, мощный разгон и громкий вид.",
		"price": 1600,
		"speed": 805.0,
		"top": 1230.0,
		"grow": 370.0,
		"handling": 12.1,
		"color": "#29496e",
		"stripe": true,
		"stripe_color": "#f0ede4",
		"wing": true,
	},
	{
		"id": 3,
		"name": "SPORT",
		"sub": "ТРЕКОВЫЙ КУПЕ",
		"desc": "Точные реакции и высокая максимальная скорость.",
		"price": 3200,
		"speed": 840.0,
		"top": 1300.0,
		"grow": 390.0,
		"handling": 13.2,
		"color": "#d79a25",
		"stripe": true,
		"stripe_color": "#1c2024",
		"wing": true,
	},
	{
		"id": 4,
		"name": "HYPER",
		"sub": "ГИПЕРКАР",
		"desc": "Вершина гаража. Держись крепче.",
		"price": 5600,
		"speed": 880.0,
		"top": 1380.0,
		"grow": 410.0,
		"handling": 13.8,
		"color": "#1e2228",
		"stripe": true,
		"stripe_color": "#e23b30",
		"wing": true,
	},
]


static func get_car(i: int) -> Dictionary:
	return LIST[clampi(i, 0, LIST.size() - 1)]


static func speed_rating(car: Dictionary) -> int:
	var t := clampf((float(car.top) - 1050.0) / 380.0, 0.0, 1.0)
	return 1 + int(round(9.0 * t))


static func accel_rating(car: Dictionary) -> int:
	var t := clampf((float(car.grow) - 320.0) / 100.0, 0.0, 1.0)
	return 1 + int(round(9.0 * t))


static func grip_rating(car: Dictionary) -> int:
	var t := clampf((float(car.handling) - 11.0) / 3.2, 0.0, 1.0)
	return 1 + int(round(9.0 * t))
