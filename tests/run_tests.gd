extends SceneTree
## Автотести логіки. Запуск: godot --headless -s tests/run_tests.gd

var failed := 0
var passed := 0


func check(cond: bool, name: String) -> void:
	if cond:
		passed += 1
	else:
		failed += 1
		print("  FAIL: ", name)


func make(layout: Array, goals: Dictionary = {"red": 99}, moves: int = 30) -> Board:
	var b := Board.new()
	b.setup({"layout": layout, "goals": goals, "moves": moves}, 12345)
	return b


func kind_at(b: Board, x: int, y: int) -> int:
	var p = b.pieces[b.idx(x, y)]
	return -1 if p == null else p["kind"]


func count_kind(b: Board, kind: int) -> int:
	var n := 0
	for p in b.pieces:
		if p != null and p["kind"] == kind:
			n += 1
	return n


func invariants(b: Board, name: String, allow_empty: bool = false) -> void:
	var ids := {}
	for i in b.w * b.h:
		var p = b.pieces[i]
		if b.playable[i] == 0:
			check(p == null, name + ": фішка в дірці")
			continue
		if b.crate[i] > 0:
			check(p == null, name + ": фішка в ящику")
			continue
		check(p != null or allow_empty, name + ": порожня клітинка %d" % i)
		if p != null:
			check(not ids.has(p["id"]), name + ": повтор id")
			ids[p["id"]] = true
	check(b._find_groups().is_empty(), name + ": лишився збіг")


func _init() -> void:
	test_fill()
	test_basic_match()
	test_boosters_created()
	test_booster_effects()
	test_combos()
	test_obstacles()
	test_holes_and_slide()
	test_goals_and_finale()
	test_shuffle()
	test_random_games()
	test_levels()
	print("Тести: пройдено %d, помилок %d" % [passed, failed])
	quit(1 if failed > 0 else 0)


func test_fill() -> void:
	for s in 20:
		var b := Board.new()
		b.setup({"layout": [".........", ".........", ".........", ".........", ".........",
				".........", "........."], "goals": {"red": 10}, "moves": 10}, s)
		check(b._find_groups().is_empty(), "початкове поле без збігів")
		check(not b.find_moves().is_empty(), "початкове поле має ходи")


func test_basic_match() -> void:
	var b := make([
		"rgbyr",
		"ggryb",
		"rbgby",
		"ybryg",
	])
	# зелена (2,2) вгору: ряд g g g у рядку 1
	check(b.play_swap(b.idx(0, 0), b.idx(1, 0)).size() == 1, "хід без збігу повертається")
	check(b.moves_left == 30, "невдалий хід не витрачає ходи")
	var steps := b.play_swap(b.idx(2, 2), b.idx(2, 1))
	check(steps.size() >= 3, "вдалий хід дає кроки")
	check(b.moves_left == 29, "вдалий хід витрачає хід")
	invariants(b, "базовий збіг")
	check(not b.can_swap(b.idx(0, 0), b.idx(2, 0)), "несусідні не міняються")


func test_boosters_created() -> void:
	var b := make([
		"rrgrb",
		"byrby",
		"ygbyg",
		"bybgb",
	])
	b.play_swap(b.idx(2, 0), b.idx(2, 1))  # зелена вниз, червона вгору: r r r r
	check(count_kind(b, Board.Kind.BAR_V) + count_kind(b, Board.Kind.BAR_H) == 1, "4 в ряд дає брусок")
	b = make([
		"rrgrr",
		"byrby",
		"ygbyg",
		"bybgb",
	])
	b.play_swap(b.idx(2, 0), b.idx(2, 1))
	check(count_kind(b, Board.Kind.STAR) == 1, "5 в ряд дає зірку")
	b = make([
		"rrgrb",
		"byrby",
		"ygryg",
		"bybgb",
	])
	b.play_swap(b.idx(3, 0), b.idx(2, 0))
	check(count_kind(b, Board.Kind.BOMB) == 1, "кут дає бомбу")
	b = make([
		"rrgby",
		"rgrby",
		"ygbyg",
		"bybgb",
	])
	b.play_swap(b.idx(1, 1), b.idx(2, 1))
	check(count_kind(b, Board.Kind.SHUR) == 1, "квадрат дає сюрикен")
	invariants(b, "створення бустерів")


func test_booster_effects() -> void:
	var b := make([
		"rgbyr",
		"gHryb",
		"rbgby",
		"ybryg",
	], {"red": 99})
	var before: int = b.goals["red"]
	var steps := b.play_tap(b.idx(1, 1))
	check(steps.size() >= 1 and steps[0]["type"] == "clear", "натиск на брусок")
	check(steps[0]["removed"].size() >= 5, "брусок чистить ряд")
	check(b.goals["red"] < before, "червоні зараховано")
	invariants(b, "брусок")

	b = make([
		"rgbyrg",
		"gbrybr",
		"rbBbyg",
		"ybrygb",
		"gyrbyr",
		"rgbyrg",
	])
	steps = b.play_tap(b.idx(2, 2))
	check(steps[0]["removed"].size() >= 25, "бомба чистить 5x5")
	invariants(b, "бомба")

	b = make([
		"rgbyr",
		"gSryb",
		"rbgby",
		"ybryg",
	], {"blue": 99})
	steps = b.play_swap(b.idx(1, 1), b.idx(1, 2))  # зірка на синю
	var blues := 0
	for e in steps[1]["removed"]:
		if e["color"] == 2:
			blues += 1
	check(blues >= 5, "зірка прибирає всі сині")
	invariants(b, "зірка")

	b = make([
		"rgbyr",
		"gPryb",
		"rb1by",
		"ybryg",
	], {"crate": 0})
	steps = b.play_tap(b.idx(1, 1))
	check(b.crate[b.idx(2, 2)] == 0, "сюрикен летить у ящик-ціль")
	check(b.is_won(), "ціль ящиків виконано")
	invariants(b, "сюрикен")


func test_combos() -> void:
	var rows := [
		"rgbyrgb",
		"gbrybry",
		"rbgbygr",
		"ybrygby",
		"gyrbyrg",
		"rgbyrgb",
		"bygrbyr",
	]
	var pairs := [["H", "V"], ["H", "B"], ["B", "B"], ["S", "S"], ["S", "H"], ["S", "B"],
			["S", "P"], ["P", "P"], ["P", "H"], ["P", "B"]]
	for pair in pairs:
		var layout := rows.duplicate()
		layout[3] = "ybr" + pair[0] + pair[1] + "by"
		var b := make(layout)
		var steps := b.play_swap(b.idx(3, 3), b.idx(4, 3))
		check(steps.size() >= 2, "комбінація %s+%s" % pair)
		var removed := 0
		for s in steps:
			if s["type"] == "clear":
				removed += s["removed"].size()
		check(removed >= 9, "комбінація %s+%s щось прибирає (%d)" % [pair[0], pair[1], removed])
		invariants(b, "комбінація %s+%s" % pair)
	var b2 := make(rows.duplicate())
	b2.pieces[b2.idx(3, 3)]["kind"] = Board.Kind.STAR
	b2.pieces[b2.idx(4, 3)]["kind"] = Board.Kind.STAR
	var st := b2.play_swap(b2.idx(3, 3), b2.idx(4, 3))
	check(st[1]["removed"].size() >= 45, "зірка+зірка чистить поле")


func test_obstacles() -> void:
	var b := make([
		"rgbyr",
		"gg2yb",
		"rbgby",
		"ybryg",
	], {"crate": 0})
	check(b.goals["crate"] == 1, "ціль 'усі ящики' рахується з поля")
	b.play_swap(b.idx(2, 2), b.idx(2, 1) ) # ящик не міняється
	check(b.moves_left == 30, "ящик не рухається")
	b = make([
		"rgbyr",
		"ggryb",
		"rb2by",
		"ybryg",
	], {"crate": 0})
	# g (2,?) немає; зробимо збіг поруч: r(2,1) і g... перевіримо удар бустером
	b = make([
		"rgbyr",
		"gH2yb",
		"rbgby",
		"ybryg",
	], {"crate": 0})
	b.play_tap(b.idx(1, 1))
	check(b.crate[b.idx(2, 1)] == 1, "удар знімає одну рейку")
	check(not b.is_won(), "ящик ще стоїть")

	b = make([
		"rgbyr",
		"ggIyb",
		"rbgby",
		"ybryg",
	], {"ice": 0})
	# фішка під льодом: зробимо її зеленою
	b.pieces[b.idx(2, 1)]["color"] = 1
	b.pieces[b.idx(2, 1)]["kind"] = Board.Kind.NORMAL
	# вже збіг g g g(лід): зробимо хід деінде, щоб запустити перевірку
	check(not b.can_swap(b.idx(2, 1), b.idx(2, 2)), "замерзла фішка не рухається")
	var groups := b._find_groups()
	check(groups.size() == 1, "замерзла фішка бере участь у збігу")
	b._begin_step()
	b._apply_groups(groups, [], false)
	check(b.ice[b.idx(2, 1)] == 1, "збіг знімає шар льоду")
	check(b.pieces[b.idx(2, 1)] != null, "фішка під льодом лишається")

	b = make([
		"rgbyr",
		"ggcyb",
		"rbgby",
		"ybryg",
	], {"chain": 0})
	b.pieces[b.idx(2, 1)]["color"] = 1
	groups = b._find_groups()
	b._begin_step()
	b._apply_groups(groups, [], false)
	check(b.chain[b.idx(2, 1)] == 0, "збіг знімає ланцюг")
	check(b.is_won(), "ціль ланцюгів виконано")


func test_holes_and_slide() -> void:
	var b := make([
		"rg#yr",
		"gb#yb",
		"rH.by",
		"yb1yg",
		"gyrbr",
	])
	b.play_tap(b.idx(1, 2))
	invariants(b, "поле з дірками")
	# під ящиком клітинка має заповнитись по діагоналі
	b = make([
		"rgbyr",
		"g111b",
		"rbHby",
		"ybryg",
	])
	b.play_tap(b.idx(2, 2))
	check(b.pieces[b.idx(1, 2)] != null and b.pieces[b.idx(3, 2)] != null, "діагональне заповнення")
	invariants(b, "діагональне заповнення", true)
	for i in 30:
		var m := b.find_moves()
		if m.is_empty():
			break
		if m[0]["a"] == m[0]["b"]:
			b.play_tap(m[0]["a"])
		else:
			b.play_swap(m[0]["a"], m[0]["b"])
		invariants(b, "гра під ящиками", true)


func test_goals_and_finale() -> void:
	var b := make([
		"rgbyr",
		"gHryb",
		"rbgby",
		"ybryg",
	], {"red": 1}, 10)
	b.play_tap(b.idx(1, 1))
	check(b.is_won(), "перемога після збору цілі")
	check(b.stars() == 3, "три зірки за багато ходів")
	var steps := b.play_finale()
	check(steps.size() >= 2 and steps[0]["type"] == "finale", "салют створює бустери")
	check(not b.has_boosters(), "після салюту бустерів немає")
	invariants(b, "салют")


func test_shuffle() -> void:
	var b := make([
		"rgbyr",
		"gbryb",
		"rgbyr",
		"gbryb",
	])
	var s := b._shuffle()
	check(s["ok"], "перемішування знаходить поле з ходами")
	invariants(b, "перемішування")


func test_random_games() -> void:
	var layouts := [
		["..2...2..", ".........", "..#...#..", "..i.c.i..", ".........", "1.......1", "..I...I..", "........."],
		["##.....##", "#.......#", ".........", "....#....", ".........", "#..ccc..#", "##22222##"],
	]
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for layout in layouts:
		for g in 6:
			var b := Board.new()
			b.setup({"layout": layout, "goals": {"red": 400}, "moves": 60}, 100 + g)
			while b.moves_left > 0:
				var m := Bot.pick_move(b, rng)
				if m.is_empty():
					break
				var steps: Array
				if m["a"] == m["b"]:
					steps = b.play_tap(m["a"])
				else:
					steps = b.play_swap(m["a"], m["b"])
				check(not steps.is_empty(), "бот робить дозволений хід")
				invariants(b, "випадкова гра")
				if failed > 20:
					return


func test_levels() -> void:
	var dir := DirAccess.open("res://levels")
	if dir == null:
		return
	var n := 0
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var data = JSON.parse_string(FileAccess.get_file_as_string("res://levels/" + f))
		check(data is Dictionary and data.has("layout"), "рівень %s читається" % f)
		if not (data is Dictionary):
			continue
		var b := Board.new()
		b.setup(data, 1)
		check(b.w <= 9 and b.h <= 12, "рівень %s не більший за 9x12" % f)
		check(not b.goals.is_empty(), "рівень %s має цілі" % f)
		check(not b.find_moves().is_empty(), "рівень %s має ходи" % f)
		n += 1
	print("  рівнів перевірено: ", n)
