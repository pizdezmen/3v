class_name LevelGen
extends RefCounted
## Генератор рівнів нескінченного режиму.
## Рівень будується з номера (той самий номер = той самий рівень),
## а кількість ходів підбирає бот, який кілька разів проходить рівень.

const BOT_GAMES := 8
const MOVE_CAP := 70


static func generate(number: int) -> Dictionary:
	var fallback := {}
	for attempt in 12:
		var level := _build(number, attempt)
		var stats := Bot.measure(level, BOT_GAMES, MOVE_CAP, number * 13 + attempt)
		if stats["wins"] == 0:
			continue
		var d := difficulty(number)
		var moves := int(round(stats["p50"] * lerpf(1.3, 1.02, d))) + 2
		level["moves"] = clampi(moves, 8, 60)
		level["bot"] = stats
		if stats["wins"] >= BOT_GAMES - 2 and stats["p50"] >= 8:
			return level
		if fallback.is_empty():
			fallback = level
	if fallback.is_empty():
		fallback = {"layout": [".......", ".......", ".......", ".......", ".......", ".......", "......."],
				"goals": {"red": 20, "blue": 20}, "moves": 20}
	return fallback


static func difficulty(number: int) -> float:
	return clampf((number - 1) / 30.0, 0.0, 1.0)


static func _hole(shape: int, x: int, y: int, w: int, h: int, k: int) -> bool:
	var mx: int = min(x, w - 1 - x)
	var my: int = min(y, h - 1 - y)
	var cx := absf(x - (w - 1) / 2.0)
	var cy := absf(y - (h - 1) / 2.0)
	match shape:
		1:  # зрізані кути
			return mx + my < k
		2:  # дірка в центрі
			return cx < 1.0 and cy < 1.0
		3:  # виїмки з боків
			return mx < k and cy < 1.5
		4:  # кути й центр
			return mx + my < k or (cx + cy < 1.0)
		5:  # хрест із дірок у центрі
			return (cx < 0.6 and cy < 1.6) or (cy < 0.6 and cx < 1.6)
		6:  # виїмки згори і знизу
			return my < k and cx < 1.5
	return false


static func _build(number: int, attempt: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = number * 7919 + attempt * 104729 + 17
	var d := difficulty(number)
	var w := rng.randi_range(7, 9)
	var h := rng.randi_range(8, 10 if d < 0.4 else 12)
	var shape := rng.randi_range(0, 6)
	var k := rng.randi_range(1, 2)
	var grid: Array = []
	for y in h:
		var row: Array = []
		for x in w:
			row.append("#" if _hole(shape, x, y, w, h, k) else ".")
		grid.append(row)
	var kinds := ["crate", "ice", "chain"]
	for i in 2:
		var j := rng.randi_range(0, 2)
		var t = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = t
	var kind_count := 1
	if rng.randf() < 0.35 + d * 0.5:
		kind_count = 2
	if d > 0.5 and rng.randf() < d * 0.5:
		kind_count = 3
	var used: Array = []
	for i in kind_count:
		var kind: String = kinds[i]
		var placed := _place(grid, kind, rng, d, w, h)
		if placed > 0:
			used.append(kind)
	var goals := {}
	for kind in used:
		goals[kind] = 0
	var colors := ["red", "green", "blue", "yellow"]
	var color_goals := 0
	if goals.is_empty():
		color_goals = 2
	elif goals.size() == 1 and rng.randf() < 0.6:
		color_goals = 1
	for i in color_goals:
		var c: String = colors[rng.randi_range(0, colors.size() - 1)]
		colors.erase(c)
		goals[c] = int(round((35 + d * 35 + rng.randi_range(0, 12)) / 5.0)) * 5
	# місяці, які треба опустити донизу: окремий генератор чисел, щоб решта рівнів не змінилась
	var mrng := RandomNumberGenerator.new()
	mrng.seed = number * 6151 + attempt * 31 + 5
	if number >= 4 and goals.size() < 3 and mrng.randf() < 0.3:
		var columns: Array = []
		for x in w:
			for y in h:
				if grid[y][x] == "#":
					continue
				if grid[y][x] == "." and y < h - 3:
					columns.append([x, y])
				break
		var want := mrng.randi_range(1, 3)
		var placed_moons := 0
		while placed_moons < want and not columns.is_empty():
			var pick: Array = columns.pop_at(mrng.randi_range(0, columns.size() - 1))
			grid[pick[1]][pick[0]] = "M"
			placed_moons += 1
		if placed_moons > 0:
			goals["moon"] = 0
	var layout: Array = []
	for row in grid:
		layout.append("".join(row))
	return {"layout": layout, "goals": goals, "moves": 30}


## Розставляє перешкоди дзеркально. Повертає, скільки поставлено.
static func _place(grid: Array, kind: String, rng: RandomNumberGenerator, d: float, w: int, h: int) -> int:
	var placed := 0
	var half := (w + 1) / 2
	var pattern := rng.randi_range(0, 2)
	var amount := int(7 + d * 9 + rng.randi_range(0, 4))
	if kind == "chain":
		# ланцюг ламають лише бустери, тож їх менше: не більш як п'ята частина поля
		amount = mini(int(4 + d * 6 + rng.randi_range(0, 2)), w * h / 5)
	var tries := 0
	if kind == "crate" and pattern == 0:
		# стіна внизу
		var rows := 2 + int(d > 0.3) + int(rng.randf() < d)
		for y in range(h - rows, h):
			for x in w:
				if grid[y][x] == "." and (y > h - rows or rng.randf() < 0.8 or x == w - 1 - x):
					var strong := rng.randf() < d * 0.7
					grid[y][x] = "2" if strong else "1"
					grid[y][w - 1 - x] = grid[y][x]
					placed += 1
		return placed
	while placed < amount and tries < 80:
		tries += 1
		var x := rng.randi_range(0, half - 1)
		var y := rng.randi_range(1 if kind != "crate" else 2, h - 1)
		if pattern == 1:
			y = rng.randi_range(h / 2, h - 1)
		if grid[y][x] != "." or grid[y][w - 1 - x] != ".":
			continue
		var ch := "c"
		if kind == "crate":
			ch = "2" if rng.randf() < d * 0.6 else "1"
		elif kind == "ice":
			ch = "I" if rng.randf() < 0.25 + d * 0.5 else "i"
		grid[y][x] = ch
		grid[y][w - 1 - x] = ch
		placed += 1 if x == w - 1 - x else 2
	return placed
