class_name BoardView
extends Node2D
## Показує поле й програє кроки, які повертає Board. Власної логіки гри не має.

signal move_started
signal move_finished
signal goal_progress(key: String)

const HOP := 0.062          # секунд на одну клітинку падіння
const PIECE_SCALE := 0.92

var board: Board
var cell := 76.0
var origin := Vector2.ZERO
var busy := false
var input_enabled := true
var cascade := 0

var _nodes := {}     # id фішки -> Node2D
var _crates := {}    # клітинка -> Sprite2D
var _ices := {}
var _chains := {}
var _pieces_layer: Node2D
var _over_layer: Node2D
var _fx_layer: Node2D
var _sel_mark: Sprite2D
var _press := -1
var _press_pos := Vector2.ZERO
var _selected := -1
var _idle := 0.0
var _hint_tweens: Array = []
var _frame_box: StyleBoxFlat
var _base_pos := Vector2.ZERO


func _ready() -> void:
	_pieces_layer = Node2D.new()
	_over_layer = Node2D.new()
	_fx_layer = Node2D.new()
	_sel_mark = Sprite2D.new()
	_sel_mark.texture = Art.dot
	_sel_mark.modulate = Color(1, 1, 1, 0.28)
	_sel_mark.visible = false
	add_child(_sel_mark)
	add_child(_pieces_layer)
	add_child(_over_layer)
	add_child(_fx_layer)
	_frame_box = StyleBoxFlat.new()
	_frame_box.bg_color = Art.FRAME
	_frame_box.set_corner_radius_all(20)
	_frame_box.anti_aliasing = true


## Ставить поле в заданий прямокутник (у координатах батька).
func show_board(b: Board, area: Rect2) -> void:
	board = b
	cell = floorf(min(area.size.x / b.w, area.size.y / b.h, 92.0))
	position = area.position + (area.size - Vector2(b.w, b.h) * cell) / 2.0
	_base_pos = position
	origin = Vector2.ZERO
	for layer in [_pieces_layer, _over_layer, _fx_layer]:
		for c in layer.get_children():
			c.queue_free()
	_nodes.clear()
	_crates.clear()
	_ices.clear()
	_chains.clear()
	_selected = -1
	_sel_mark.visible = false
	_sel_mark.scale = Vector2.ONE * cell * 1.25 / 32.0
	for i in b.w * b.h:
		if b.playable[i] == 0:
			continue
		if b.crate[i] > 0:
			_crates[i] = _overlay(i, Art.crate2 if b.crate[i] > 1 else Art.crate1, 0.96)
		var p = b.pieces[i]
		if p != null:
			_make_piece(p["id"], p["kind"], p["color"], center(i))
		if b.ice[i] > 0:
			_ices[i] = _overlay(i, Art.ice2 if b.ice[i] > 1 else Art.ice1, 0.98)
		if b.chain[i] > 0:
			_chains[i] = _overlay(i, Art.chain, 0.96)
	queue_redraw()
	_idle = 0.0


func center(i: int) -> Vector2:
	return Vector2((i % board.w + 0.5) * cell, (i / board.w + 0.5) * cell)


func _overlay(i: int, tex: Texture2D, size: float) -> Sprite2D:
	var s := Sprite2D.new()
	s.texture = tex
	s.scale = Vector2.ONE * cell * size / tex.get_width()
	s.position = center(i)
	_over_layer.add_child(s)
	return s


func _make_piece(id: int, kind: int, color: int, pos: Vector2) -> Node2D:
	var n := Node2D.new()
	n.position = pos
	var sh := Sprite2D.new()
	sh.texture = Art.shadow
	sh.position = Vector2(0, cell * 0.4)
	sh.scale = Vector2(cell * 0.8 / 96.0, cell * 0.2 / 32.0)
	n.add_child(sh)
	var sp := Sprite2D.new()
	n.add_child(sp)
	n.set_meta("sp", sp)
	n.set_meta("color", color)
	_set_look(n, kind, color)
	_pieces_layer.add_child(n)
	_nodes[id] = n
	return n


func _set_look(n: Node2D, kind: int, color: int) -> void:
	var sp: Sprite2D = n.get_meta("sp")
	sp.texture = Art.piece_texture(kind, color)
	sp.scale = Vector2.ONE * cell * PIECE_SCALE / sp.texture.get_width()
	sp.rotation = PI / 2 if kind == Board.Kind.BAR_V else 0.0
	n.set_meta("color", color)
	n.set_meta("kind", kind)


func _draw() -> void:
	if board == null:
		return
	for i in board.w * board.h:
		if board.playable[i] == 1:
			var r := Rect2(Vector2(i % board.w, i / board.w) * cell - Vector2(13, 13), Vector2(cell + 26, cell + 26))
			draw_style_box(_frame_box, r)
	for i in board.w * board.h:
		if board.playable[i] == 1:
			var x := i % board.w
			var y := i / board.w
			draw_rect(Rect2(Vector2(x, y) * cell - Vector2(0.3, 0.3), Vector2(cell + 0.6, cell + 0.6)),
					Art.CELL_B if (x + y) % 2 == 1 else Art.CELL_A)


# ---------------------------------------------------------------- введення

func _cell_at(local: Vector2) -> int:
	var x := int(floor(local.x / cell))
	var y := int(floor(local.y / cell))
	var i := board.idx(x, y)
	if i < 0 or board.playable[i] == 0:
		return -1
	return i


func _unhandled_input(event: InputEvent) -> void:
	if board == null or not input_enabled:
		return
	if event is InputEventScreenTouch:
		if event.index != 0:
			return
		var local := to_local(event.position)
		if event.pressed:
			_touch()
			_press = _cell_at(local)
			_press_pos = local
		else:
			if _press >= 0 and _cell_at(local) == _press:
				_tap(_press)
			_press = -1
	elif event is InputEventScreenDrag and _press >= 0 and event.index == 0:
		var d: Vector2 = to_local(event.position) - _press_pos
		if d.length() > cell * 0.32:
			var dir := Vector2i(signi(int(d.x)), 0) if absf(d.x) > absf(d.y) else Vector2i(0, signi(int(d.y)))
			var target := board.idx(_press % board.w + dir.x, _press / board.w + dir.y)
			var from := _press
			_press = -1
			_select(-1)
			if target >= 0:
				_try_swap(from, target)


func _tap(i: int) -> void:
	if busy:
		return
	if _selected >= 0 and _selected != i and board.can_swap(_selected, i):
		var from := _selected
		_select(-1)
		_try_swap(from, i)
		return
	var p = board.pieces[i]
	if p != null and p["kind"] != Board.Kind.NORMAL and board._swappable(i):
		_select(-1)
		var steps := board.play_tap(i)
		if not steps.is_empty():
			_run(steps)
		return
	if p != null and board._swappable(i) and _selected != i:
		_select(i)
	else:
		if p != null and not board._swappable(i):
			_shake_piece(i)
		_select(-1)


func _select(i: int) -> void:
	_selected = i
	_sel_mark.visible = i >= 0
	if i >= 0:
		_sel_mark.position = center(i)


func _try_swap(a: int, b: int) -> void:
	if busy:
		return
	var steps := board.play_swap(a, b)
	if steps.is_empty():
		Sfx.play("bad")
		_shake_piece(a)
		return
	_run(steps)


func _shake_piece(i: int) -> void:
	var p = board.pieces[i]
	if p == null or not _nodes.has(p["id"]):
		return
	var n: Node2D = _nodes[p["id"]]
	var c := center(i)
	var tw := create_tween()
	tw.tween_property(n, "position", c + Vector2(6, 0), 0.04)
	tw.tween_property(n, "position", c - Vector2(6, 0), 0.06)
	tw.tween_property(n, "position", c, 0.04)


# ---------------------------------------------------------------- програвання кроків

func _run(steps: Array) -> void:
	busy = true
	cascade = 0
	_touch()
	var real_move: bool = not (steps.size() == 1 and steps[0]["type"] == "swap")
	if real_move:
		move_started.emit()
	await play_steps(steps)
	busy = false
	if real_move:
		move_finished.emit()


func play_steps(steps: Array) -> void:
	for s in steps:
		match s["type"]:
			"swap":
				await _anim_swap(s)
			"clear":
				await _anim_clear(s)
			"fall":
				await _anim_fall(s)
			"shuffle":
				await _anim_shuffle(s)
			"finale":
				await _anim_finale(s)


func _wait(t: float) -> void:
	await get_tree().create_timer(max(t, 0.01)).timeout


func _at(t: float, c: Callable) -> void:
	if t <= 0.005:
		c.call()
	else:
		create_tween().tween_callback(c).set_delay(t)


func _anim_swap(s: Dictionary) -> void:
	var na: Node2D = _nodes.get(s["ida"])
	var nb: Node2D = _nodes.get(s["idb"])
	var pa := center(s["a"])
	var pb := center(s["b"])
	Sfx.play("swap")
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	if na:
		na.z_index = 1
		tw.tween_property(na, "position", pb, 0.14)
	if nb:
		tw.tween_property(nb, "position", pa, 0.14)
	await tw.finished
	if not s["ok"]:
		Sfx.play("bad")
		var back := create_tween().set_parallel(true).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		if na:
			back.tween_property(na, "position", pa, 0.14)
		if nb:
			back.tween_property(nb, "position", pb, 0.14)
		await back.finished
	if na:
		na.z_index = 0


func _anim_clear(s: Dictionary) -> void:
	cascade += 1
	var any_match := false
	for e in s["removed"]:
		_at(e["t"], _remove_node.bind(e))
		if e["to"] >= 0:
			any_match = true
	if any_match:
		Sfx.play("match", min(1.0 + (cascade - 1) * 0.12, 2.0))
	for e in s["blockers"]:
		_at(e["t"], _blocker_event.bind(e))
	for e in s["created"]:
		_at(e["t"] + 0.1, _create_event.bind(e))
	for e in s["transformed"]:
		_at(e["t"], _transform_event.bind(e))
	for e in s["fx"]:
		_at(e["t"], _fx_event.bind(e))
	await _wait(s["dur"] + 0.24)


func _remove_node(e: Dictionary) -> void:
	if e["goal"] != "":
		goal_progress.emit(e["goal"])
	var n: Node2D = _nodes.get(e["id"])
	if n == null:
		return
	_nodes.erase(e["id"])
	var tw := create_tween()
	var sp: Sprite2D = n.get_meta("sp")
	if e["to"] >= 0 and e["to"] != e["idx"]:
		tw.set_parallel(true)
		tw.tween_property(n, "position", center(e["to"]), 0.16).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_property(n, "scale", Vector2.ONE * 0.4, 0.16)
		tw.tween_property(n, "modulate:a", 0.0, 0.16).set_delay(0.06)
		tw.chain().tween_callback(n.queue_free)
	else:
		tw.tween_property(n, "scale", Vector2.ONE * 1.18, 0.05)
		tw.set_parallel(true)
		tw.tween_property(n, "scale", Vector2.ONE * 0.2, 0.13).set_delay(0.05)
		tw.tween_property(n, "modulate:a", 0.0, 0.13).set_delay(0.05)
		tw.chain().tween_callback(n.queue_free)
	var color := Color.WHITE
	if e["color"] >= 0:
		color = Art.PIECE_COLORS[e["color"]].lightened(0.25)
	else:
		color = Art.VIOLET.lightened(0.3)
	_burst(center(e["idx"]), color, 7)
	if sp == null:
		return


func _blocker_event(e: Dictionary) -> void:
	if e["goal"] != "":
		goal_progress.emit(e["goal"])
	var i: int = e["idx"]
	match e["what"]:
		"crate":
			Sfx.play("wood", randf_range(0.9, 1.1))
			_burst(center(i), Color("#c79263"), 8)
			var s: Sprite2D = _crates.get(i)
			if s == null:
				return
			if e["left"] > 0:
				s.texture = Art.crate1
				_pop(s)
			else:
				_crates.erase(i)
				_vanish(s)
		"ice":
			Sfx.play("ice", randf_range(0.9, 1.15))
			_burst(center(i), Color("#dff4ff"), 8)
			var s: Sprite2D = _ices.get(i)
			if s == null:
				return
			if e["left"] > 0:
				s.texture = Art.ice1
				_pop(s)
			else:
				_ices.erase(i)
				_vanish(s)
		"chain":
			Sfx.play("chain")
			_burst(center(i), Color("#c9d1df"), 8)
			var s: Sprite2D = _chains.get(i)
			if s != null:
				_chains.erase(i)
				_vanish(s)


func _pop(s: Node2D) -> void:
	var base := s.scale
	var tw := create_tween()
	tw.tween_property(s, "scale", base * 1.12, 0.06)
	tw.tween_property(s, "scale", base, 0.1)


func _vanish(s: Node2D) -> void:
	var tw := create_tween().set_parallel(true)
	tw.tween_property(s, "scale", s.scale * 1.25, 0.16)
	tw.tween_property(s, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(s.queue_free)


func _create_event(e: Dictionary) -> void:
	Sfx.play("create")
	var n := _make_piece(e["id"], e["kind"], -1, center(e["idx"]))
	n.scale = Vector2.ONE * 0.2
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector2.ONE * 1.25, 0.12).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(n, "scale", Vector2.ONE, 0.1)
	_ring(center(e["idx"]), cell * 1.6, Color(1, 1, 1, 0.5), 0.25)


func _transform_event(e: Dictionary) -> void:
	var n: Node2D = _nodes.get(e["id"])
	if n == null:
		return
	_set_look(n, e["kind"], -1)
	n.scale = Vector2.ONE * 0.5
	var tw := create_tween()
	tw.tween_property(n, "scale", Vector2.ONE * 1.2, 0.1)
	tw.tween_property(n, "scale", Vector2.ONE, 0.08)


func _anim_fall(s: Dictionary) -> void:
	for m in s["moves"]:
		var path: Array = m["path"]
		var n: Node2D = _nodes.get(m["id"])
		var tw := create_tween()
		var t := 0
		if n == null:
			n = _make_piece(m["id"], m["kind"], m["color"], center(path[0][0]) - Vector2(0, cell))
			n.modulate.a = 0.0
			var first_tick: int = path[0][1]
			if first_tick > 0:
				tw.tween_interval(first_tick * HOP)
				t = first_tick
			tw.tween_property(n, "modulate:a", 1.0, HOP * 0.6)
			tw.parallel().tween_property(n, "position", center(path[0][0]), HOP)
			t += 1
			path = path.slice(1)
		for step in path:
			var tick: int = step[1]
			if tick > t:
				tw.tween_interval((tick - t) * HOP)
			tw.tween_property(n, "position", center(step[0]), HOP)
			t = tick + 1
		var sp: Sprite2D = n.get_meta("sp")
		var base: Vector2 = Vector2.ONE * cell * PIECE_SCALE / sp.texture.get_width()
		tw.tween_property(sp, "scale", base * Vector2(1.08, 0.9), 0.05)
		tw.tween_property(sp, "scale", base, 0.09)
	Sfx.play("land", 1.0, -4.0)
	await _wait(s["ticks"] * HOP + 0.07)


func _anim_shuffle(s: Dictionary) -> void:
	Sfx.play("shuffle")
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	var mid := Vector2(board.w, board.h) * cell / 2.0
	for m in s["moves"]:
		var n: Node2D = _nodes.get(m["id"])
		if n == null:
			continue
		tw.tween_property(n, "position", mid.lerp(n.position, 0.25), 0.22)
	await tw.finished
	var tw2 := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	for m in s["moves"]:
		var n: Node2D = _nodes.get(m["id"])
		if n == null:
			continue
		if n.get_meta("color") != m["color"]:
			_set_look(n, Board.Kind.NORMAL, m["color"])
		tw2.tween_property(n, "position", center(m["idx"]), 0.3)
	await tw2.finished


func _anim_finale(s: Dictionary) -> void:
	var t := 0.0
	for e in s["items"]:
		_at(t, func():
			Sfx.play("create", randf_range(0.95, 1.2))
			_transform_event(e)
			_ring(center(e["idx"]), cell * 1.6, Color(1, 0.9, 0.5, 0.6), 0.25))
		t += 0.09
	await _wait(t + 0.35)


# ---------------------------------------------------------------- ефекти

func _burst(pos: Vector2, color: Color, amount: int) -> void:
	var p := CPUParticles2D.new()
	p.position = pos
	p.texture = Art.dot
	p.one_shot = true
	p.explosiveness = 1.0
	p.amount = amount
	p.lifetime = 0.45
	p.spread = 180.0
	p.gravity = Vector2(0, 420)
	p.initial_velocity_min = cell * 1.4
	p.initial_velocity_max = cell * 3.2
	p.scale_amount_min = cell / 190.0
	p.scale_amount_max = cell / 95.0
	p.color = color
	var ramp := Gradient.new()
	ramp.set_color(0, Color(1, 1, 1, 1))
	ramp.set_color(1, Color(1, 1, 1, 0))
	p.color_ramp = ramp
	_fx_layer.add_child(p)
	p.emitting = true
	create_tween().tween_callback(p.queue_free).set_delay(0.7)


func _ring(pos: Vector2, size: float, color: Color, dur: float) -> void:
	var s := Sprite2D.new()
	s.texture = Art.dot
	s.position = pos
	s.modulate = color
	s.scale = Vector2.ONE * size * 0.3 / 32.0
	_fx_layer.add_child(s)
	var tw := create_tween().set_parallel(true)
	tw.tween_property(s, "scale", Vector2.ONE * size / 32.0, dur).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tw.tween_property(s, "modulate:a", 0.0, dur)
	tw.chain().tween_callback(s.queue_free)


func _beam(pos: Vector2, horizontal: bool) -> void:
	var s := Sprite2D.new()
	s.texture = Art.dot
	s.modulate = Color("#e6d9ff")
	var c := pos
	var length: float
	if horizontal:
		length = board.w * cell
		c.x = length / 2.0
	else:
		length = board.h * cell
		c.y = length / 2.0
		s.rotation = PI / 2
	s.position = c
	s.scale = Vector2(0.2, cell * 1.0 / 32.0)
	_fx_layer.add_child(s)
	var tw := create_tween()
	tw.tween_property(s, "scale", Vector2(length * 1.5 / 32.0, cell * 0.9 / 32.0), 0.12)
	tw.tween_property(s, "scale:y", 0.0, 0.2)
	tw.parallel().tween_property(s, "modulate:a", 0.0, 0.2)
	tw.tween_callback(s.queue_free)


func _shake(power: float) -> void:
	var tw := create_tween()
	for k in 5:
		tw.tween_property(self, "position", _base_pos + Vector2(randf_range(-1, 1), randf_range(-1, 1)) * power, 0.035)
	tw.tween_property(self, "position", _base_pos, 0.04)


func _fx_event(e: Dictionary) -> void:
	var pos := center(e["idx"])
	match e["fx"]:
		"line":
			Sfx.play("line", randf_range(0.95, 1.1))
			_beam(pos, e["horizontal"])
		"bomb":
			Sfx.play("bomb", 1.0 if e["r"] <= 2 else 0.8)
			Progress.vibrate(30)
			_ring(pos, cell * (e["r"] * 2 + 1.6), Color(1, 0.85, 0.5, 0.75), 0.32)
			_shake(6.0 if e["r"] <= 2 else 11.0)
		"nova":
			Sfx.play("star")
			Sfx.play("bomb", 0.7)
			Progress.vibrate(60)
			_ring(pos, cell * 24, Color(1, 1, 1, 0.8), 0.6)
			_shake(12.0)
		"star":
			Sfx.play("star")
			var col: Color = Art.PIECE_COLORS[e["color"]].lightened(0.45)
			_ring(pos, cell * 2.4, Color(1, 1, 1, 0.7), 0.3)
			for t in e["targets"]:
				var line := Line2D.new()
				line.width = cell * 0.09
				line.default_color = col
				line.begin_cap_mode = Line2D.LINE_CAP_ROUND
				line.end_cap_mode = Line2D.LINE_CAP_ROUND
				line.points = PackedVector2Array([pos, pos])
				_fx_layer.add_child(line)
				var tw := create_tween()
				tw.tween_method(func(v: float): line.set_point_position(1, pos.lerp(center(t), v)), 0.0, 1.0, 0.22)
				tw.tween_property(line, "modulate:a", 0.0, 0.22)
				tw.tween_callback(line.queue_free)
		"fly":
			Sfx.play("fly", randf_range(0.9, 1.15))
			var n := Node2D.new()
			n.position = pos
			var sp := Sprite2D.new()
			sp.texture = Art.shur
			sp.scale = Vector2.ONE * cell * 0.8 / sp.texture.get_width()
			n.add_child(sp)
			if e["carry"] >= 0:
				var extra := Sprite2D.new()
				extra.texture = Art.piece_texture(e["carry"], -1)
				extra.scale = Vector2.ONE * cell * 0.55 / extra.texture.get_width()
				extra.position = Vector2(0, -cell * 0.3)
				n.add_child(extra)
			_fx_layer.add_child(n)
			var target := center(e["to"])
			var bend := (target - pos).orthogonal().normalized() * cell * randf_range(-1.2, 1.2)
			var mid := (pos + target) / 2.0 + bend
			var tw := create_tween().set_parallel(true)
			tw.tween_method(func(v: float):
				n.position = pos.lerp(mid, v).lerp(mid.lerp(target, v), v), 0.0, 1.0, e["dur"]) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
			tw.tween_property(sp, "rotation", TAU * 2.0, e["dur"])
			tw.chain().tween_callback(func():
				_ring(target, cell * 1.8, Color(1, 1, 1, 0.6), 0.2)
				n.queue_free())


# ---------------------------------------------------------------- підказка

func _touch() -> void:
	_idle = 0.0
	for tw in _hint_tweens:
		if tw and tw.is_valid():
			tw.kill()
	_hint_tweens.clear()
	for id in _nodes:
		var n: Node2D = _nodes[id]
		if n.has_meta("hint"):
			n.remove_meta("hint")
			n.scale = Vector2.ONE


func _process(delta: float) -> void:
	if board == null or busy or not input_enabled:
		return
	_idle += delta
	if _idle > 5.0 and _hint_tweens.is_empty():
		_show_hint()


func _show_hint() -> void:
	var moves := board.find_moves()
	if moves.is_empty():
		_idle = 0.0
		return
	var best: Dictionary = moves[0]
	for m in moves:
		if m["score"] > best["score"]:
			best = m
	for i in [best["a"], best["b"]]:
		var p = board.pieces[i]
		if p == null or not _nodes.has(p["id"]):
			continue
		var n: Node2D = _nodes[p["id"]]
		if n.has_meta("hint"):
			continue
		n.set_meta("hint", true)
		var tw := create_tween().set_loops()
		tw.tween_property(n, "scale", Vector2.ONE * 1.13, 0.32).set_trans(Tween.TRANS_SINE)
		tw.tween_property(n, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(0.25)
		_hint_tweens.append(tw)
