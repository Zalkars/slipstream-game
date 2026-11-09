class_name Cars
extends RefCounted

# Car roster: price in coins, speed in px/s, ratings are cosmetic (1..10).

const LIST := [
	{
		"id": 0,
		"name": "HATCH",
		"silhouette": "hatch",
		"sub": "ГОРОДСКОЙ ХЭТЧБЕК",
		"desc": "Лёгкий и послушный. С него начинают все.",
		"price": 0,
		"speed": 740.0,
		"top": 1100.0,
		"grow": 340.0,
		"handling": 11.6,
		"color": "#b32b26",
		"stripe": true,
		"stripe_color": "#f0ede4",
		"wing": false,
	},
	{
		"id": 1,
		"name": "VAN",
		"silhouette": "van",
		"sub": "ГОРОДСКОЙ ФУРГОН",
		"desc": "Практичный и вместительный. Такси в городе начинается с него.",
		"price": 250,
		"speed": 730.0,
		"top": 1060.0,
		"grow": 320.0,
		"handling": 10.6,
		"color": "#d9b23c",
		"stripe": false,
		"stripe_color": "#2b2a22",
		"wing": false,
	},
	{
		"id": 2,
		"name": "SEDAN GT",
		"silhouette": "sedan",
		"sub": "СПОРТИВНЫЙ СЕДАН",
		"desc": "Быстрее и стабильнее. Хороший шаг вперёд.",
		"price": 600,
		"speed": 775.0,
		"top": 1170.0,
		"grow": 360.0,
		"handling": 12.5,
		"color": "#d8dade",
		"stripe": false,
		"stripe_color": "#2b3036",
		"wing": false,
	},
	{
		"id": 3,
		"name": "OFF-ROAD",
		"silhouette": "offroad",
		"sub": "КВАДРО-КРОССОВЕР",
		"desc": "Высокая посадка, рейлинги и запасное колесо — для любой погоды.",
		"price": 1000,
		"speed": 765.0,
		"top": 1140.0,
		"grow": 355.0,
		"handling": 11.4,
		"color": "#5c6b38",
		"stripe": false,
		"stripe_color": "#d9d2ae",
		"wing": false,
	},
	{
		"id": 4,
		"name": "MUSCLE",
		"silhouette": "muscle",
		"sub": "АМЕРИКАНСКИЙ МАСКЛ",
		"desc": "Тяжёлый характер, мощный разгон и громкий вид.",
		"price": 1600,
		"speed": 805.0,
		"top": 1230.0,
		"grow": 395.0,
		"handling": 12.0,
		"color": "#29496e",
		"stripe": true,
		"stripe_color": "#f0ede4",
		"wing": true,
	},
	{
		"id": 5,
		"name": "PICKUP",
		"silhouette": "pickup",
		"sub": "РАБОЧИЙ ПИКАП",
		"desc": "Кузов позади принимает всё, что не влезло в салон.",
		"price": 2200,
		"speed": 790.0,
		"top": 1190.0,
		"grow": 380.0,
		"handling": 11.2,
		"color": "#7c5340",
		"stripe": true,
		"stripe_color": "#e8dfd0",
		"wing": false,
	},
	{
		"id": 6,
		"name": "SPORT",
		"silhouette": "sport",
		"sub": "ТРЕКОВЫЙ КУПЕ",
		"desc": "Точные реакции и высокая максимальная скорость.",
		"price": 3200,
		"speed": 840.0,
		"top": 1300.0,
		"grow": 405.0,
		"handling": 13.8,
		"color": "#d79a25",
		"stripe": true,
		"stripe_color": "#1c2024",
		"wing": true,
	},
	{
		"id": 7,
		"name": "VOLT EV",
		"silhouette": "ev",
		"sub": "ЭЛЕКТРОКАР",
		"desc": "Тихий, мгновенный и невероятно технологичный.",
		"price": 4200,
		"speed": 855.0,
		"top": 1320.0,
		"grow": 420.0,
		"handling": 14.4,
		"color": "#2ea8b8",
		"stripe": true,
		"stripe_color": "#eaf6f8",
		"wing": false,
	},
	{
		"id": 8,
		"name": "HYPER",
		"silhouette": "hyper",
		"sub": "ГИПЕРКАР",
		"desc": "Вершина гаража. Держись крепче.",
		"price": 5600,
		"speed": 880.0,
		"top": 1380.0,
		"grow": 430.0,
		"handling": 15.4,
		"color": "#1e2228",
		"stripe": true,
		"stripe_color": "#e23b30",
		"wing": true,
	},
]


static func get_car(i: int) -> Dictionary:
	return LIST[clampi(i, 0, LIST.size() - 1)]


static func speed_rating(car: Dictionary) -> int:
	var t := clampf((float(car.top) - 1050.0) / 330.0, 0.0, 1.0)
	return 1 + int(round(9.0 * t))


static func accel_rating(car: Dictionary) -> int:
	var t := clampf((float(car.grow) - 330.0) / 100.0, 0.0, 1.0)
	return 1 + int(round(9.0 * t))


static func grip_rating(car: Dictionary) -> int:
	var t := clampf((float(car.handling) - 11.2) / 4.2, 0.0, 1.0)
	return 1 + int(round(9.0 * t))
