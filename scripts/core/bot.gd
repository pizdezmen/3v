class_name Bot
extends RefCounted
## Простий бот: грає рівень жадібно з дрібкою випадковості.
## Ним перевіряється складність ручних і згенерованих рівнів.


static func pick_move(board: Board, rng: RandomNumberGenerator) -> Dictionary:
	var moves := board.find_moves()
	if moves.is_empty():
		return {}
	moves.sort_custom(func(a, b): return a["score"] > b["score"])
	var r := rng.randf()
	var k := 0
	if r > 0.9 and moves.size() > 2:
		k = 2
	elif r > 0.7 and moves.size() > 1:
		k = 1
	return moves[k]


## Грає до перемоги або до move_cap ходів. Повертає {won, used}.
static func play(level: Dictionary, seed_value: int, move_cap: int = 0) -> Dictionary:
	var board := Board.new()
	var data := level.duplicate()
	if move_cap > 0:
		data["moves"] = move_cap
	board.setup(data, seed_value)
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_value * 31 + 7
	while board.moves_left > 0 and not board.is_won():
		var m := pick_move(board, rng)
		if m.is_empty():
			break
		if m["a"] == m["b"]:
			board.play_tap(m["a"])
		else:
			board.play_swap(m["a"], m["b"])
	return {"won": board.is_won(), "used": board.moves_total - board.moves_left}


## Статистика за кілька ігор: {wins, games, avg, p50, p80, max}
static func measure(level: Dictionary, games: int, move_cap: int, seed_base: int = 1) -> Dictionary:
	var used: Array = []
	for g in games:
		var r := play(level, seed_base + g * 977, move_cap)
		if r["won"]:
			used.append(r["used"])
	used.sort()
	var res := {"wins": used.size(), "games": games, "avg": 0.0, "p50": 0, "p80": 0, "max": 0}
	if used.is_empty():
		return res
	var total := 0
	for u in used:
		total += u
	res["avg"] = float(total) / used.size()
	res["p50"] = used[used.size() / 2]
	res["p80"] = used[min(used.size() - 1, int(used.size() * 0.8))]
	res["max"] = used[used.size() - 1]
	return res
