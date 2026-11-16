class_name Board
extends RefCounted
## Чиста логіка поля "три в ряд" без жодної графіки.
## Кожен хід повертає список кроків (steps), які екран лише програє як анімацію.

enum Kind { NORMAL, BAR_H, BAR_V, BOMB, STAR, SHUR, MOON }
# MOON: місяць. Не збирається у збіги, не рухається пальцем і не ламається бустерами,
# лише падає; коли доходить до нижньої клітинки стовпця, виходить з поля (ціль "moon").

# Комбінації бустерів (значення продовжують Kind, щоб жити в одній черзі).
const C_CROSS := 10      # брусок + брусок: ряд і стовпець
const C_BIG_CROSS := 11  # брусок + бомба: три ряди і три стовпці
const C_BIG_BOMB := 12   # бомба + бомба: великий вибух
const C_NOVA := 13       # зірка + зірка: усе поле
const C_SHUR3 := 14      # сюрикен + сюрикен: три сюрикени

const COLOR_NAMES := ["red", "green", "blue", "yellow"]
const DIRS := [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]
const FLY_TIME := 0.42

var w := 0
var h := 0
var num_colors := 4
var playable := PackedByteArray()
var pieces: Array = []            # null або {id, kind, color}
var crate := PackedInt32Array()   # міцність ящика (0 = немає)
var ice := PackedInt32Array()     # шари льоду на фішці (0..2)
var chain := PackedByteArray()    # 1 = ланцюг на клітинці: камені падають крізь, гравець їх не рухає, ламає лише бустер
var glow := PackedInt32Array()    # сяйво під клітинкою (0..2 рівні): рівень знімається, коли на клітинці прибирають камінь
var goals := {}                   # назва -> скільки ще лишилось
var goals_start := {}
var moves_left := 0
var moves_total := 0
var rng := RandomNumberGenerator.new()

var _next_id := 1
var _matched := false   # у цьому кроці зібрався збіг каменів (для звуку)
var _rm: Array = []
var _bl: Array = []
var _cr: Array = []
var _fx: Array = []
var _tr: Array = []
var _queue: Array = []
var _protected := {}
var _targeted := {}


# ---------------------------------------------------------------- підготовка

func setup(level: Dictionary, seed_value: int) -> void:
	rng.seed = seed_value
	var layout: Array = level["layout"]
	h = layout.size()
	w = 0
	for row in layout:
		w = max(w, String(row).length())
	num_colors = clampi(int(level.get("colors", 4)), 3, 4)
	var n := w * h
	playable.resize(n)
	crate.resize(n)
	ice.resize(n)
	chain.resize(n)
	glow.resize(n)
	glow.fill(0)
	pieces.resize(n)
	var random_cells: Array = []
	for y in h:
		var row := String(layout[y])
		for x in w:
			var i := y * w + x
			var ch := row[x] if x < row.length() else "#"
			playable[i] = 1
			crate[i] = 0
			ice[i] = 0
			chain[i] = 0
			pieces[i] = null
			match ch:
				"#", " ":
					playable[i] = 0
				"1":
					crate[i] = 1
				"2":
					crate[i] = 2
				"i":
					ice[i] = 1
					random_cells.append(i)
				"I":
					ice[i] = 2
					random_cells.append(i)
				"c":
					chain[i] = 1
					random_cells.append(i)
				"H":
					pieces[i] = _new_piece(Kind.BAR_H, -1)
				"V":
					pieces[i] = _new_piece(Kind.BAR_V, -1)
				"B":
					pieces[i] = _new_piece(Kind.BOMB, -1)
				"S":
					pieces[i] = _new_piece(Kind.STAR, -1)
				"P":
					pieces[i] = _new_piece(Kind.SHUR, -1)
				"M":
					pieces[i] = _new_piece(Kind.MOON, -1)
				"r":
					pieces[i] = _new_piece(Kind.NORMAL, 0)
				"g":
					pieces[i] = _new_piece(Kind.NORMAL, 1)
				"b":
					pieces[i] = _new_piece(Kind.NORMAL, 2)
				"y":
					pieces[i] = _new_piece(Kind.NORMAL, 3)
				_:
					random_cells.append(i)
	_fill_random(random_cells)
	# сяйво задається окремою сіткою цифр: "glow": ["0120", ...]
	var glow_rows: Array = level.get("glow", [])
	for y in mini(h, glow_rows.size()):
		var grow := String(glow_rows[y])
		for x in mini(w, grow.length()):
			if playable[y * w + x] == 1:
				glow[y * w + x] = clampi(grow.unicode_at(x) - 48, 0, 2)
	moves_total = int(level.get("moves", 20))
	moves_left = moves_total
	goals = {}
	var src: Dictionary = level.get("goals", {})
	for key in src:
		var v = src[key]
		var amount := 0
		if v is String or int(v) <= 0:
			amount = count_on_board(key)
		else:
			amount = int(v)
		if amount > 0:
			goals[key] = amount
	goals_start = goals.duplicate()


func _fill_random(cells: Array) -> void:
	for attempt in 60:
		for i in cells:
			pieces[i] = null
		for i in cells:
			var options: Array = []
			for c in num_colors:
				options.append(c)
			_shuffle_array(options)
			var p := _new_piece(Kind.NORMAL, options[0])
			pieces[i] = p
			for c in options:
				p["color"] = c
				if _match_score_at(i) == 0:
					break
		if _find_groups().is_empty() and not find_moves().is_empty():
			return


func _new_piece(kind: int, color: int) -> Dictionary:
	var p := {"id": _next_id, "kind": kind, "color": color}
	_next_id += 1
	return p


func count_on_board(key: String) -> int:
	var total := 0
	for i in w * h:
		match key:
			"crate":
				if crate[i] > 0:
					total += 1
			"ice":
				if ice[i] > 0:
					total += 1
			"chain":
				if chain[i] > 0:
					total += 1
			"glow":
				total += glow[i]
			"moon":
				if pieces[i] != null and pieces[i]["kind"] == Kind.MOON:
					total += 1
			_:
				var p = pieces[i]
				if p != null and p["kind"] == Kind.NORMAL and COLOR_NAMES[p["color"]] == key:
					total += 1
	return total


# ---------------------------------------------------------------- допоміжне

func idx(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return -1
	return y * w + x


func is_cell(i: int) -> bool:
	return i >= 0 and playable[i] == 1


func _neighbor(i: int, d: Vector2i) -> int:
	var x := i % w + d.x
	var y := i / w + d.y
	if x < 0 or y < 0 or x >= w or y >= h:
		return -1
	var n := y * w + x
	return n if playable[n] == 1 else -1


func _is_booster(p: Dictionary) -> bool:
	return p["kind"] != Kind.NORMAL and p["kind"] != Kind.MOON


## Місяці, що дійшли до нижньої клітинки свого стовпця.
func _moons_at_bottom() -> Array:
	var res: Array = []
	for x in w:
		for y in range(h - 1, -1, -1):
			var i := y * w + x
			if playable[i] == 0:
				continue
			var p = pieces[i]
			if p != null and p["kind"] == Kind.MOON and crate[i] == 0 and ice[i] == 0:
				res.append(i)
			break
	return res


## Місяць виходить з поля. Викликається всередині кроку очищення.
func _collect_moons(cells: Array) -> void:
	for i in cells:
		var p: Dictionary = pieces[i]
		pieces[i] = null
		_rm.append({"id": p["id"], "idx": i, "t": 0.0, "to": -1, "goal": "moon" if _count("moon") else "",
				"kind": p["kind"], "color": -1, "exit": true})


## Чи є над клітинкою i у її стовпці місяць (для бота, підказки й сюрикена).
func _under_moon(i: int) -> bool:
	var x := i % w
	for y in range(i / w - 1, -1, -1):
		var p = pieces[y * w + x]
		if p != null and p["kind"] == Kind.MOON:
			return true
	return false


func _movable(i: int) -> bool:
	return pieces[i] != null and crate[i] == 0 and ice[i] == 0


func _empty(i: int) -> bool:
	return playable[i] == 1 and pieces[i] == null and crate[i] == 0


func _color_at(x: int, y: int) -> int:
	if x < 0 or y < 0 or x >= w or y >= h:
		return -1
	var p = pieces[y * w + x]
	if p == null or p["kind"] != Kind.NORMAL:
		return -1
	return p["color"]


func _run(x: int, y: int, dx: int, dy: int, color: int) -> int:
	var n := 0
	x += dx
	y += dy
	while _color_at(x, y) == color:
		n += 1
		x += dx
		y += dy
	return n


func _square_at(x: int, y: int, color: int) -> bool:
	for ox in [-1, 0]:
		for oy in [-1, 0]:
			if _color_at(x + ox, y + oy) == color and _color_at(x + ox + 1, y + oy) == color \
					and _color_at(x + ox, y + oy + 1) == color and _color_at(x + ox + 1, y + oy + 1) == color:
				return true
	return false


## Оцінка збігу, який утворює фішка в клітинці i (0 = збігу немає).
func _match_score_at(i: int) -> int:
	var p = pieces[i]
	if p == null or p["kind"] != Kind.NORMAL:
		return 0
	var x := i % w
	var y := i / w
	var c: int = p["color"]
	var hl := 1 + _run(x, y, -1, 0, c) + _run(x, y, 1, 0, c)
	var vl := 1 + _run(x, y, 0, -1, c) + _run(x, y, 0, 1, c)
	var sq := _square_at(x, y, c)
	if hl < 3 and vl < 3 and not sq:
		return 0
	if hl >= 5 or vl >= 5:
		return 60
	if hl >= 3 and vl >= 3:
		return 45
	if hl == 4 or vl == 4:
		return 32
	if sq:
		return 28
	return 10


func is_won() -> bool:
	for key in goals:
		if goals[key] > 0:
			return false
	return true


func _count(key: String) -> bool:
	if goals.get(key, 0) > 0:
		goals[key] -= 1
		return true
	return false


func _shuffle_array(arr: Array) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t


# ---------------------------------------------------------------- пошук збігів

func _find(parent: PackedInt32Array, i: int) -> int:
	while parent[i] != i:
		parent[i] = parent[parent[i]]
		i = parent[i]
	return i


## Групи збігів: лінії від 3 та квадрати 2x2, з'єднані спільними клітинками.
func _find_groups() -> Array:
	var n := w * h
	var parent := PackedInt32Array()
	parent.resize(n)
	for i in n:
		parent[i] = i
	var shapes: Array = []  # [тип 0=гориз 1=верт 2=квадрат, клітинки]
	for y in h:
		var x := 0
		while x < w:
			var c := _color_at(x, y)
			if c < 0:
				x += 1
				continue
			var x2 := x
			while _color_at(x2 + 1, y) == c:
				x2 += 1
			if x2 - x >= 2:
				var cells: Array = []
				for xx in range(x, x2 + 1):
					cells.append(y * w + xx)
				shapes.append([0, cells])
			x = x2 + 1
	for x in w:
		var y := 0
		while y < h:
			var c := _color_at(x, y)
			if c < 0:
				y += 1
				continue
			var y2 := y
			while _color_at(x, y2 + 1) == c:
				y2 += 1
			if y2 - y >= 2:
				var cells: Array = []
				for yy in range(y, y2 + 1):
					cells.append(yy * w + x)
				shapes.append([1, cells])
			y = y2 + 1
	for y in h - 1:
		for x in w - 1:
			var c := _color_at(x, y)
			if c >= 0 and _color_at(x + 1, y) == c and _color_at(x, y + 1) == c and _color_at(x + 1, y + 1) == c:
				shapes.append([2, [y * w + x, y * w + x + 1, (y + 1) * w + x, (y + 1) * w + x + 1]])
	if shapes.is_empty():
		return []
	for s in shapes:
		var cells: Array = s[1]
		var r0 := _find(parent, cells[0])
		for k in range(1, cells.size()):
			var r := _find(parent, cells[k])
			if r != r0:
				parent[r] = r0
	var by_root := {}
	for s in shapes:
		var cells: Array = s[1]
		var root := _find(parent, cells[0])
		if not by_root.has(root):
			by_root[root] = {"set": {}, "hmax": 0, "vmax": 0, "square": false,
					"hset": {}, "vset": {}, "best_run": [], "sq": []}
		var g: Dictionary = by_root[root]
		for c in cells:
			g["set"][c] = true
		if s[0] == 0:
			for c in cells:
				g["hset"][c] = true
			if cells.size() > g["hmax"]:
				g["hmax"] = cells.size()
				if cells.size() >= g["vmax"]:
					g["best_run"] = cells
		elif s[0] == 1:
			for c in cells:
				g["vset"][c] = true
			if cells.size() > g["vmax"]:
				g["vmax"] = cells.size()
				if cells.size() > g["hmax"]:
					g["best_run"] = cells
		else:
			g["square"] = true
			g["sq"] = cells
	return by_root.values()


func _group_kind(g: Dictionary, horizontal_swap: bool, swapped: bool) -> int:
	var hmax: int = g["hmax"]
	var vmax: int = g["vmax"]
	if max(hmax, vmax) >= 5:
		return Kind.STAR
	if hmax >= 3 and vmax >= 3:
		return Kind.BOMB
	if max(hmax, vmax) == 4:
		if swapped:
			return Kind.BAR_H if horizontal_swap else Kind.BAR_V
		return Kind.BAR_V if hmax == 4 else Kind.BAR_H
	if g["square"]:
		return Kind.SHUR
	return Kind.NORMAL


func _group_spawn(g: Dictionary, kind: int, swap_cells: Array) -> int:
	for c in swap_cells:
		if g["set"].has(c):
			return c
	if kind == Kind.BOMB:
		for c in g["hset"]:
			if g["vset"].has(c):
				return c
	if kind == Kind.SHUR:
		return g["sq"][rng.randi_range(0, 3)]
	var run: Array = g["best_run"]
	if run.is_empty():
		return g["set"].keys()[0]
	return run[run.size() / 2]


# ---------------------------------------------------------------- крок очищення

func _begin_step() -> void:
	_rm = []
	_bl = []
	_cr = []
	_fx = []
	_tr = []
	_queue = []
	_protected = {}
	_targeted = {}
	_matched = false


func _end_step() -> Dictionary:
	var dur := 0.0
	for e in _rm:
		dur = max(dur, e["t"])
	for e in _bl:
		dur = max(dur, e["t"])
	for e in _fx:
		dur = max(dur, e["t"] + e.get("dur", 0.0))
	return {"type": "clear", "removed": _rm, "blockers": _bl, "created": _cr,
			"fx": _fx, "transformed": _tr, "dur": dur, "matched": _matched}


func _step_empty() -> bool:
	return _rm.is_empty() and _bl.is_empty() and _cr.is_empty() and _fx.is_empty()


func _damage_crate(i: int, t: float) -> void:
	crate[i] -= 1
	var counted := false
	if crate[i] == 0:
		counted = _count("crate")
	_bl.append({"idx": i, "what": "crate", "left": crate[i], "t": t, "goal": "crate" if counted else ""})


func _damage_ice(i: int, t: float) -> void:
	ice[i] -= 1
	var counted := false
	if ice[i] == 0:
		counted = _count("ice")
	_bl.append({"idx": i, "what": "ice", "left": ice[i], "t": t, "goal": "ice" if counted else ""})


func _damage_chain(i: int, t: float) -> void:
	chain[i] = 0
	var counted := _count("chain")
	_bl.append({"idx": i, "what": "chain", "left": 0, "t": t, "goal": "chain" if counted else ""})


func _remove_piece(i: int, t: float, to: int = -1) -> void:
	var p = pieces[i]
	pieces[i] = null
	var goal := ""
	if p["kind"] == Kind.NORMAL and _count(COLOR_NAMES[p["color"]]):
		goal = COLOR_NAMES[p["color"]]
	_rm.append({"id": p["id"], "idx": i, "t": t, "to": to, "goal": goal,
			"kind": p["kind"], "color": p["color"]})
	if glow[i] > 0:
		glow[i] -= 1
		_bl.append({"idx": i, "what": "glow", "left": glow[i], "t": t, "goal": "glow" if _count("glow") else ""})


func _apply_groups(groups: Array, swap_cells: Array, horizontal_swap: bool) -> void:
	if not groups.is_empty():
		_matched = true
	for g in groups:
		var kind := _group_kind(g, horizontal_swap, not swap_cells.is_empty())
		var spawn := -1
		if kind != Kind.NORMAL:
			spawn = _group_spawn(g, kind, swap_cells)
		var adjacent := {}
		for c in g["set"]:
			for d in DIRS:
				var nb := _neighbor(c, d)
				if nb >= 0 and not g["set"].has(nb):
					adjacent[nb] = true
			if c == spawn:
				continue
			# ланцюг збігом не знімається: камінь під ним збирається, ланцюг лишається на клітинці
			if ice[c] > 0:
				_damage_ice(c, 0.0)
			else:
				_remove_piece(c, 0.0, spawn)
		if spawn >= 0:
			if ice[spawn] > 0:
				_damage_ice(spawn, 0.0)
			_remove_piece(spawn, 0.0, spawn)
			var np := _new_piece(kind, -1)
			pieces[spawn] = np
			_cr.append({"id": np["id"], "idx": spawn, "kind": kind, "t": 0.0})
			_protected[spawn] = true
		for nb in adjacent:
			if crate[nb] > 0:
				_damage_crate(nb, 0.05)
			elif ice[nb] > 0:
				_damage_ice(nb, 0.05)


## Удар бустера по клітинці.
func _hit(i: int, t: float, seen: Dictionary) -> void:
	if i < 0 or playable[i] == 0 or seen.has(i) or _protected.has(i):
		return
	seen[i] = true
	if crate[i] > 0:
		_damage_crate(i, t)
		return
	# вибух бустера знімає ланцюг разом із каменем під ним
	if chain[i] > 0:
		_damage_chain(i, t)
	var p = pieces[i]
	if p == null:
		return
	if ice[i] > 0:
		_damage_ice(i, t)
		return
	if p["kind"] == Kind.MOON:
		return
	_remove_piece(i, t)
	if p["kind"] != Kind.NORMAL:
		_queue.append({"t": t + 0.1, "idx": i, "kind": p["kind"]})


func _run_queue() -> void:
	var guard := 0
	while not _queue.is_empty() and guard < 2000:
		guard += 1
		var bi := 0
		for k in range(1, _queue.size()):
			if _queue[k]["t"] < _queue[bi]["t"]:
				bi = k
		var a: Dictionary = _queue[bi]
		_queue.remove_at(bi)
		if a.has("hit"):
			_hit(a["hit"], a["t"], {})
			if a.has("then"):
				_queue.append({"t": a["t"] + 0.02, "idx": a["hit"], "kind": a["then"]})
		elif a.has("trigger"):
			var p = pieces[a["idx"]]
			if p != null and p["id"] == a["trigger"]:
				_hit(a["idx"], a["t"], {})
		else:
			_activate(a)


func _hit_row(y: int, x0: int, t: float, seen: Dictionary) -> void:
	if y < 0 or y >= h:
		return
	for x in w:
		_hit(y * w + x, t + absf(x - x0) * 0.035, seen)


func _hit_col(x: int, y0: int, t: float, seen: Dictionary) -> void:
	if x < 0 or x >= w:
		return
	for y in h:
		_hit(y * w + x, t + absf(y - y0) * 0.035, seen)


func _hit_area(x0: int, y0: int, r: int, t: float, seen: Dictionary) -> void:
	for y in range(y0 - r, y0 + r + 1):
		for x in range(x0 - r, x0 + r + 1):
			var i := idx(x, y)
			if i >= 0:
				_hit(i, t + max(absi(x - x0), absi(y - y0)) * 0.03, seen)


func _best_color() -> int:
	var counts := [0, 0, 0, 0]
	for i in w * h:
		var p = pieces[i]
		if p != null and p["kind"] == Kind.NORMAL:
			counts[p["color"]] += 1
	var best := -1
	var best_score := -1.0
	for c in num_colors:
		if counts[c] == 0:
			continue
		var s := float(counts[c])
		if goals.get(COLOR_NAMES[c], 0) > 0:
			s += 100.0
		if s > best_score:
			best_score = s
			best = c
	return best


func _activate(a: Dictionary) -> void:
	var i: int = a["idx"]
	var t: float = a["t"]
	var x := i % w
	var y := i / w
	var seen := {}
	match int(a["kind"]):
		Kind.BAR_H:
			_fx.append({"fx": "line", "idx": i, "horizontal": true, "t": t, "dur": 0.3})
			_hit_row(y, x, t, seen)
		Kind.BAR_V:
			_fx.append({"fx": "line", "idx": i, "horizontal": false, "t": t, "dur": 0.3})
			_hit_col(x, y, t, seen)
		C_CROSS:
			_fx.append({"fx": "line", "idx": i, "horizontal": true, "t": t, "dur": 0.3})
			_fx.append({"fx": "line", "idx": i, "horizontal": false, "t": t, "dur": 0.3})
			_hit_row(y, x, t, seen)
			_hit_col(x, y, t, seen)
		C_BIG_CROSS:
			for o in [-1, 0, 1]:
				if y + o >= 0 and y + o < h:
					_fx.append({"fx": "line", "idx": (y + o) * w + x, "horizontal": true, "t": t, "dur": 0.3})
				if x + o >= 0 and x + o < w:
					_fx.append({"fx": "line", "idx": y * w + x + o, "horizontal": false, "t": t, "dur": 0.3})
				_hit_row(y + o, x, t, seen)
				_hit_col(x + o, y, t, seen)
		Kind.BOMB:
			# бомба: квадрат 3 на 3
			_fx.append({"fx": "bomb", "idx": i, "r": 1, "t": t, "dur": 0.3})
			_hit_area(x, y, 1, t, seen)
		C_BIG_BOMB:
			# дві бомби разом: квадрат 5 на 5
			_fx.append({"fx": "bomb", "idx": i, "r": 2, "t": t, "dur": 0.4})
			_hit_area(x, y, 2, t, seen)
		C_NOVA:
			_fx.append({"fx": "nova", "idx": i, "t": t, "dur": 0.6})
			for j in w * h:
				var d: int = max(absi(j % w - x), absi(j / w - y))
				_hit(j, t + 0.1 + d * 0.05, seen)
		Kind.STAR:
			_activate_star(a)
		Kind.SHUR:
			for d in DIRS:
				_hit(_neighbor(i, d), t, seen)
			_launch(i, t, a.get("carry", -1))
		C_SHUR3:
			for d in DIRS:
				_hit(_neighbor(i, d), t, seen)
			for k in 3:
				_launch(i, t + k * 0.08, -1)


func _activate_star(a: Dictionary) -> void:
	var i: int = a["idx"]
	var t: float = a["t"]
	var color: int = a.get("color", -1)
	if color < 0:
		color = _best_color()
	if color < 0:
		return
	var into: int = a.get("into", -1)
	var targets: Array = []
	for j in w * h:
		var p = pieces[j]
		if p != null and p["kind"] == Kind.NORMAL and p["color"] == color and not _protected.has(j):
			targets.append(j)
	_fx.append({"fx": "star", "idx": i, "targets": targets, "color": color, "t": t, "dur": 0.45})
	var k := 0
	for j in targets:
		if into >= 0 and _movable(j):
			var kind := into
			if into == Kind.BAR_H and rng.randf() < 0.5:
				kind = Kind.BAR_V
			var p: Dictionary = pieces[j]
			# фішка стає бустером: колір зараховуємо в ціль одразу
			_count(COLOR_NAMES[p["color"]])
			p["kind"] = kind
			p["color"] = -1
			_tr.append({"id": p["id"], "idx": j, "kind": kind, "t": t + 0.3})
			_queue.append({"t": t + 0.75 + k * 0.07, "idx": j, "trigger": p["id"]})
			k += 1
		else:
			_queue.append({"t": t + 0.4, "hit": j})


func _launch(from: int, t: float, carry: int) -> void:
	var target := _pick_target(from)
	if target < 0:
		return
	_fx.append({"fx": "fly", "idx": from, "to": target, "t": t, "dur": FLY_TIME, "carry": carry})
	var item := {"t": t + FLY_TIME, "hit": target}
	if carry >= 0:
		item["then"] = carry
	_queue.append(item)


## Куди летить сюрикен: спершу те, що треба для цілей рівня.
func _pick_target(from: int) -> int:
	var tiers: Array = [[], [], [], []]
	var moon_goal: bool = goals.get("moon", 0) > 0
	var glow_goal: bool = goals.get("glow", 0) > 0
	for j in w * h:
		if playable[j] == 0 or j == from or _targeted.has(j) or _protected.has(j):
			continue
		var p = pieces[j]
		if glow_goal and glow[j] > 0 and crate[j] == 0 and ice[j] == 0 and p != null and p["kind"] != Kind.MOON:
			tiers[0].append(j)
		elif moon_goal and _under_moon(j) and (crate[j] > 0 or (p != null and p["kind"] != Kind.MOON)):
			tiers[0].append(j)
		elif crate[j] > 0:
			tiers[0 if goals.get("crate", 0) > 0 else 2].append(j)
		elif p == null:
			continue
		elif ice[j] > 0:
			tiers[0 if goals.get("ice", 0) > 0 else 2].append(j)
		elif chain[j] > 0:
			tiers[0 if goals.get("chain", 0) > 0 else 2].append(j)
		elif p["kind"] == Kind.NORMAL:
			if goals.get(COLOR_NAMES[p["color"]], 0) > 0:
				tiers[1].append(j)
			else:
				tiers[3].append(j)
	for tier in tiers:
		if not tier.is_empty():
			var pick: int = tier[rng.randi_range(0, tier.size() - 1)]
			_targeted[pick] = true
			return pick
	return -1


# ---------------------------------------------------------------- падіння

func _above(i: int) -> int:
	var x := i % w
	var y := i / w - 1
	while y >= 0:
		if playable[y * w + x] == 1:
			return y * w + x
		y -= 1
	return -1


func _gravity() -> Dictionary:
	var paths := {}
	var order: Array = []
	var tick := 0
	while tick < 400:
		var moved := false
		for y in range(h - 1, -1, -1):
			for x in w:
				var c := y * w + x
				if not _empty(c):
					continue
				var a := _above(c)
				if a == -1:
					# коли всі цілі виконано, нові камені згори вже не з'являються
					if is_won():
						continue
					var np := _new_piece(Kind.NORMAL, rng.randi_range(0, num_colors - 1))
					pieces[c] = np
					paths[np["id"]] = {"id": np["id"], "spawn": true, "kind": np["kind"],
							"color": np["color"], "path": [[c, tick]]}
					order.append(np["id"])
					moved = true
				elif pieces[a] != null and _movable(a):
					_move_piece(a, c, tick, paths, order)
					moved = true
		if not moved:
			var empties: Array = []
			for y in range(h - 1, 0, -1):
				for x in w:
					if _empty(y * w + x):
						empties.append(y * w + x)
			var used := {}
			for c in empties:
				var x: int = c % w
				var y: int = c / w
				var sides := [-1, 1]
				if rng.randf() < 0.5:
					sides = [1, -1]
				for dx in sides:
					var s := idx(x + dx, y - 1)
					if s < 0 or playable[s] == 0 or used.has(s) or not _movable(s):
						continue
					used[s] = true
					used[c] = true
					_move_piece(s, c, tick, paths, order)
					moved = true
					break
		if not moved:
			break
		tick += 1
	var moves: Array = []
	for id in order:
		moves.append(paths[id])
	return {"type": "fall", "moves": moves, "ticks": tick}


func _move_piece(from: int, to: int, tick: int, paths: Dictionary, order: Array) -> void:
	var p: Dictionary = pieces[from]
	pieces[to] = p
	pieces[from] = null
	if not paths.has(p["id"]):
		paths[p["id"]] = {"id": p["id"], "spawn": false, "kind": p["kind"],
				"color": p["color"], "path": []}
		order.append(p["id"])
	paths[p["id"]]["path"].append([to, tick])


# ---------------------------------------------------------------- ходи

func _swappable(i: int) -> bool:
	return i >= 0 and playable[i] == 1 and _movable(i) and chain[i] == 0 and pieces[i]["kind"] != Kind.MOON


func can_swap(a: int, b: int) -> bool:
	if a < 0 or b < 0 or a == b or a >= w * h or b >= w * h:
		return false
	var d: int = absi(a % w - b % w) + absi(a / w - b / w)
	return d == 1 and _swappable(a) and _swappable(b)


func _combo_kind(ka: int, kb: int) -> Dictionary:
	# ka перетягнули на kb; результат спрацьовує в клітинці kb
	var bar_a := ka == Kind.BAR_H or ka == Kind.BAR_V
	var bar_b := kb == Kind.BAR_H or kb == Kind.BAR_V
	if ka == Kind.STAR and kb == Kind.STAR:
		return {"kind": C_NOVA}
	if ka == Kind.STAR or kb == Kind.STAR:
		var other := kb if ka == Kind.STAR else ka
		if other == Kind.BAR_V:
			other = Kind.BAR_H
		return {"kind": Kind.STAR, "into": other}
	if ka == Kind.SHUR and kb == Kind.SHUR:
		return {"kind": C_SHUR3}
	if ka == Kind.SHUR or kb == Kind.SHUR:
		return {"kind": Kind.SHUR, "carry": kb if ka == Kind.SHUR else ka}
	if bar_a and bar_b:
		return {"kind": C_CROSS}
	if ka == Kind.BOMB and kb == Kind.BOMB:
		return {"kind": C_BIG_BOMB}
	return {"kind": C_BIG_CROSS}


## Обмін двох сусідніх клітинок із повним розв'язанням ходу (для бота й тестів).
## Порожній список = хід неможливий.
func play_swap(a: int, b: int) -> Array:
	var steps := begin_swap(a, b)
	if steps.is_empty() or not steps[0]["ok"]:
		return steps
	_settle(steps)
	_after_move(steps)
	return steps


## Лише сам обмін і перше очищення. Далі поле доводять step_gravity і step_matches:
## так екран може приймати нові ходи, поки камені ще падають.
func begin_swap(a: int, b: int) -> Array:
	if not can_swap(a, b):
		return []
	var pa: Dictionary = pieces[a]
	var pb: Dictionary = pieces[b]
	var horizontal: bool = (a / w) == (b / w)
	pieces[a] = pb
	pieces[b] = pa
	var boost_a: bool = pa["kind"] != Kind.NORMAL
	var boost_b: bool = pb["kind"] != Kind.NORMAL
	_begin_step()
	var groups: Array = []
	if boost_a and boost_b:
		var combo := _combo_kind(pa["kind"], pb["kind"])
		_remove_piece(a, 0.0, b)
		_remove_piece(b, 0.0, b)
		combo["t"] = 0.12
		combo["idx"] = b
		_queue.append(combo)
	elif boost_a or boost_b:
		var bi := b if boost_a else a   # де тепер бустер
		var ni := a if boost_a else b   # де тепер звичайна фішка
		var bp: Dictionary = pieces[bi]
		var item := {"t": 0.0, "idx": bi, "kind": bp["kind"]}
		if bp["kind"] == Kind.STAR:
			item["color"] = pieces[ni]["color"]
		groups = _groups_with(a, b)
		_remove_piece(bi, 0.0)
		_queue.append(item)
	else:
		groups = _groups_with(a, b)
		if groups.is_empty():
			pieces[a] = pa
			pieces[b] = pb
			return [{"type": "swap", "a": a, "b": b, "ok": false, "ida": pa["id"], "idb": pb["id"]}]
	var steps: Array = [{"type": "swap", "a": a, "b": b, "ok": true, "ida": pa["id"], "idb": pb["id"]}]
	moves_left -= 1
	_apply_groups(groups, [b, a], horizontal)
	_run_queue()
	steps.append(_end_step())
	return steps


## Збіги, до яких належить хоча б одна з двох клітинок ходу.
func _groups_with(a: int, b: int) -> Array:
	var res: Array = []
	for g in _find_groups():
		if g["set"].has(a) or g["set"].has(b):
			res.append(g)
	return res


## Натиск на бустер із повним розв'язанням ходу.
func play_tap(i: int) -> Array:
	var steps := begin_tap(i)
	if steps.is_empty():
		return steps
	_settle(steps)
	_after_move(steps)
	return steps


## Лише спрацювання бустера на місці.
func begin_tap(i: int) -> Array:
	if not _swappable(i) or pieces[i]["kind"] == Kind.NORMAL:
		return []
	var kind: int = pieces[i]["kind"]
	_begin_step()
	_remove_piece(i, 0.0)
	_queue.append({"t": 0.0, "idx": i, "kind": kind})
	moves_left -= 1
	_run_queue()
	return [_end_step()]


## Один крок падіння. Порожній список moves = падати нічому.
func step_gravity() -> Dictionary:
	return _gravity()


## Один крок очищення збігів, що утворилися самі. Порожній словник = збігів немає.
func step_matches() -> Dictionary:
	var groups := _find_groups()
	var moons := _moons_at_bottom()
	if groups.is_empty() and moons.is_empty():
		return {}
	_begin_step()
	_collect_moons(moons)
	_apply_groups(groups, [], false)
	_run_queue()
	return _end_step()


## Перемішування, якщо ходів не лишилось. Порожній словник = не потрібне.
func step_shuffle() -> Dictionary:
	if is_won() or moves_left <= 0 or not find_moves().is_empty():
		return {}
	return _shuffle()


func _settle(steps: Array) -> void:
	for guard in 200:
		var fall := _gravity()
		if not fall["moves"].is_empty():
			steps.append(fall)
		var groups := _find_groups()
		var moons := _moons_at_bottom()
		if groups.is_empty() and moons.is_empty():
			return
		_begin_step()
		_collect_moons(moons)
		_apply_groups(groups, [], false)
		_run_queue()
		steps.append(_end_step())


func _after_move(steps: Array) -> void:
	if is_won() or moves_left <= 0:
		return
	if find_moves().is_empty():
		var s := _shuffle()
		if not s.is_empty():
			steps.append(s)


## Усі можливі ходи: {a, b, score}; a == b означає натиск на бустер.
func find_moves() -> Array:
	var res: Array = []
	for i in w * h:
		if not _swappable(i):
			continue
		var p: Dictionary = pieces[i]
		if p["kind"] != Kind.NORMAL:
			res.append({"a": i, "b": i, "score": 20 + _booster_value(p["kind"]) + _chain_reach(i, p["kind"])})
		for d in [Vector2i(1, 0), Vector2i(0, 1)]:
			var n := _neighbor(i, d)
			if n < 0 or not _swappable(n):
				continue
			var q: Dictionary = pieces[n]
			if p["kind"] != Kind.NORMAL and q["kind"] != Kind.NORMAL:
				res.append({"a": i, "b": n, "score": 40 + _booster_value(p["kind"]) + _booster_value(q["kind"])})
			elif p["kind"] != Kind.NORMAL or q["kind"] != Kind.NORMAL:
				var bk: int = p["kind"] if p["kind"] != Kind.NORMAL else q["kind"]
				var at: int = n if p["kind"] != Kind.NORMAL else i   # де бустер опиниться після обміну
				res.append({"a": i, "b": n, "score": 21 + _booster_value(bk) + _chain_reach(at, bk)})
			elif p["color"] != q["color"]:
				pieces[i] = q
				pieces[n] = p
				var s1 := _match_score_at(i)
				var s2 := _match_score_at(n)
				var bonus := 0
				if s1 > 0:
					bonus += _goal_bonus(i, q["color"])
				if s2 > 0:
					bonus += _goal_bonus(n, p["color"])
				pieces[i] = p
				pieces[n] = q
				if s1 + s2 > 0:
					res.append({"a": i, "b": n, "score": s1 + s2 + bonus})
	return res


## Скільки ланцюгів зачепить бустер із клітинки i (для бота й підказки).
func _chain_reach(i: int, kind: int) -> int:
	var n := 0
	var x0 := i % w
	var y0 := i / w
	match kind:
		Kind.BAR_H:
			for x in w:
				n += chain[y0 * w + x]
		Kind.BAR_V:
			for y in h:
				n += chain[y * w + x0]
		Kind.BOMB:
			for y in range(max(0, y0 - 1), min(h, y0 + 2)):
				for x in range(max(0, x0 - 1), min(w, x0 + 2)):
					n += chain[y * w + x]
		_:
			for j in w * h:
				if chain[j] > 0:
					n = 1
					break
	return n * (9 if goals.get("chain", 0) > 0 else 2)


func _booster_value(kind: int) -> int:
	match kind:
		Kind.STAR:
			return 30
		Kind.BOMB:
			return 18
		Kind.SHUR:
			return 14
	return 12


func _goal_bonus(i: int, color: int) -> int:
	var bonus := 0
	if goals.get(COLOR_NAMES[color], 0) > 0:
		bonus += 8
	for d in DIRS:
		var nb := _neighbor(i, d)
		if nb < 0:
			continue
		if crate[nb] > 0:
			bonus += 7 if goals.get("crate", 0) > 0 else 2
		elif ice[nb] > 0:
			bonus += 7 if goals.get("ice", 0) > 0 else 2
	if goals.get("moon", 0) > 0 and _under_moon(i):
		bonus += 10
	if goals.get("glow", 0) > 0:
		if glow[i] > 0:
			bonus += 6
		for d in DIRS:
			var gn := _neighbor(i, d)
			if gn >= 0 and glow[gn] > 0:
				bonus += 2
	# нижчі ходи трохи корисніші: більше каскадів
	bonus += (i / w) * 2 / max(1, h)
	return bonus


func _shuffle() -> Dictionary:
	var cells: Array = []
	for i in w * h:
		if playable[i] == 1 and _movable(i) and pieces[i]["kind"] == Kind.NORMAL:
			cells.append(i)
	if cells.size() < 2:
		return {}
	var list: Array = []
	for i in cells:
		list.append(pieces[i])
	var ok := false
	for attempt in 300:
		_shuffle_array(list)
		if attempt >= 150:
			for p in list:
				p["color"] = rng.randi_range(0, num_colors - 1)
		for k in cells.size():
			pieces[cells[k]] = list[k]
		if _find_groups().is_empty() and not find_moves().is_empty():
			ok = true
			break
	var moves: Array = []
	for k in cells.size():
		moves.append({"id": list[k]["id"], "idx": cells[k], "color": list[k]["color"]})
	return {"type": "shuffle", "moves": moves, "ok": ok}


# ---------------------------------------------------------------- фінальний салют

func has_boosters() -> bool:
	for i in w * h:
		var p = pieces[i]
		if p != null and _is_booster(p):
			return true
	return false


## Після перемоги: зайві ходи стають бустерами і всі бустери вибухають.
func play_finale(max_new: int = 12) -> Array:
	var steps: Array = []
	var cells: Array = []
	for i in w * h:
		if playable[i] == 1 and _movable(i) and pieces[i]["kind"] == Kind.NORMAL:
			cells.append(i)
	_shuffle_array(cells)
	var n: int = min(moves_left, min(max_new, cells.size()))
	if n > 0:
		var items: Array = []
		var kinds := [Kind.BAR_H, Kind.BAR_V, Kind.BOMB, Kind.SHUR]
		for k in n:
			var p: Dictionary = pieces[cells[k]]
			p["kind"] = kinds[rng.randi_range(0, 3)]
			p["color"] = -1
			items.append({"id": p["id"], "idx": cells[k], "kind": p["kind"]})
		steps.append({"type": "finale", "items": items})
	for guard in 25:
		var boosters: Array = []
		for i in w * h:
			var p = pieces[i]
			if p != null and _is_booster(p) and crate[i] == 0:
				boosters.append(i)
		if boosters.is_empty():
			break
		_begin_step()
		var t := 0.0
		for i in boosters:
			var p = pieces[i]
			if p == null:
				continue
			_queue.append({"t": t, "idx": i, "trigger": p["id"]})
			t += 0.14
		# замерзлі бустери звільняємо силою, щоб салют завжди закінчувався
		for i in boosters:
			ice[i] = 0
			chain[i] = 0
		_run_queue()
		if _step_empty():
			break
		steps.append(_end_step())
		_settle(steps)
	return steps


func stars() -> int:
	if moves_total <= 0:
		return 1
	var frac := float(moves_left) / float(moves_total)
	if frac >= 0.25:
		return 3
	if frac >= 0.1:
		return 2
	return 1
