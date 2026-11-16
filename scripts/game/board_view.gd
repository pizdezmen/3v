class_name BoardView
extends Node2D
## Показує поле й програє кроки, які повертає Board. Власної логіки гри не має.

signal move_started
signal move_finished
signal goal_progress(key: String)

const HOP := 0.089          # секунд на одну клітинку падіння
const PIECE_SCALE := 0.92
const BOUNCE := 0.09        # висота відскоку після падіння, у частках клітинки
const LAND_TIME := 0.22     # присідання і відскок після приземлення

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
var _shards: Shards
var _birth: BirthFx
var _shadow_layer: Node2D
var _live_cache: Array = []
var _live_frame := -1
var _white: ShaderMaterial
const CASCADE_SCALE := [0, 2, 4, 7, 9, 12, 14, 16, 19, 21]   # мажорна пентатоніка в півтонах
var _dim_box: StyleBoxFlat
var _cell_boxes := {}
var _base_pos := Vector2.ZERO
var _clock := 0.0
var _pending := false      # поле ще осідає: попереду падіння або збіги
var _step_until := 0.0     # до цього часу наступний крок осідання чекає
var _busy_until := {}      # id каменя -> час, до якого він рухається
var _dead := {}            # id каменів, прибраних до появи на екрані


func _ready() -> void:
	_pieces_layer = Node2D.new()
	_over_layer = Node2D.new()
	_fx_layer = Node2D.new()
	_sel_mark = Sprite2D.new()
	_sel_mark.texture = Art.dot
	_sel_mark.modulate = Color(1, 1, 1, 0.28)
	_sel_mark.visible = false
	add_child(_sel_mark)
	_shadow_layer = Node2D.new()
	_shadow_layer.draw.connect(_draw_shadows)
	add_child(_shadow_layer)
	add_child(_pieces_layer)
	add_child(_over_layer)
	add_child(_fx_layer)
	_shards = Shards.new()
	add_child(_shards)
	_birth = BirthFx.new()
	_birth.view = self
	add_child(_birth)
	var sh := Shader.new()
	sh.code = "shader_type canvas_item;\nvoid fragment() { COLOR = vec4(1.0, 1.0, 1.0, texture(TEXTURE, UV).a * COLOR.a); }"
	_white = ShaderMaterial.new()
	_white.shader = sh
	_dim_box = StyleBoxFlat.new()
	_dim_box.bg_color = Color(5 / 255.0, 4 / 255.0, 16 / 255.0, 0.6)
	_dim_box.set_corner_radius_all(36)
	_dim_box.anti_aliasing = true


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
	_busy_until.clear()
	_dead.clear()
	_pending = false
	_step_until = 0.0
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
	sp.rotation = 0.0
	n.set_meta("color", color)
	n.set_meta("kind", kind)
	n.set_meta("live", kind != Board.Kind.NORMAL)


func _play(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < board.w and y < board.h and board.playable[y * board.w + x] == 1


func _draw() -> void:
	if board == null:
		return
	# затемнення під полем, щоб живе небо не сперечалося з каменями
	draw_style_box(_dim_box, Rect2(Vector2(-28, -28), Vector2(board.w, board.h) * cell + Vector2(56, 56)))
	# поле без рамки: клітинки лежать просто на затемненні, зовнішні кути закруглені
	for i in board.w * board.h:
		if board.playable[i] != 1:
			continue
		var x := i % board.w
		var y := i / board.w
		var col: Color = Art.CELL_B if (x + y) % 2 == 1 else Art.CELL_A
		var r := Rect2(Vector2(x, y) * cell - Vector2(0.3, 0.3), Vector2(cell + 0.6, cell + 0.6))
		var mask := 0
		var bit := 1
		for d in [Vector2i(-1, -1), Vector2i(1, -1), Vector2i(1, 1), Vector2i(-1, 1)]:
			if not (_play(x + d.x, y) or _play(x, y + d.y) or _play(x + d.x, y + d.y)):
				mask |= bit
			bit <<= 1
		if mask == 0:
			draw_rect(r, col)
		else:
			draw_style_box(_cell_box(mask, col), r)


func _cell_box(mask: int, col: Color) -> StyleBoxFlat:
	var key := mask + (16 if col == Art.CELL_B else 0)
	if not _cell_boxes.has(key):
		var sb := StyleBoxFlat.new()
		sb.bg_color = col
		sb.anti_aliasing = true
		var rad := 22
		sb.corner_radius_top_left = rad if mask & 1 else 0
		sb.corner_radius_top_right = rad if mask & 2 else 0
		sb.corner_radius_bottom_right = rad if mask & 4 else 0
		sb.corner_radius_bottom_left = rad if mask & 8 else 0
		_cell_boxes[key] = sb
	return _cell_boxes[key]


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


## Перевірка для тестів: чи збігається намальоване з логікою, коли поле осіло.
func debug_mismatches() -> int:
	var bad := 0
	var seen := {}
	for i in board.w * board.h:
		var p = board.pieces[i]
		if p == null:
			continue
		seen[p["id"]] = true
		var n: Node2D = _nodes.get(p["id"])
		if n == null or n.position.distance_to(center(i)) > 1.0 or n.get_meta("kind") != p["kind"]:
			bad += 1
			if OS.is_debug_build():
				print("  mismatch cell ", i, " piece ", p, " node ", n, " pos ", n.position if n else null, " want ", center(i), " meta ", n.get_meta("kind") if n else null, " busy ", _busy_until.get(p["id"], 0.0) - _clock)
	for id in _nodes:
		if not seen.has(id):
			bad += 1
			if OS.is_debug_build():
				print("  extra node ", id, " at ", _nodes[id].position)
	for i in _crates:
		if board.crate[i] == 0:
			bad += 1
	for i in _ices:
		if board.ice[i] == 0:
			bad += 1
	for i in _chains:
		if board.chain[i] == 0:
			bad += 1
	return bad


## Чи відбувається щось на полі (осідання або салют).
func is_busy() -> bool:
	return busy or _pending


func _idle_piece(i: int) -> bool:
	var p = board.pieces[i]
	return p != null and _nodes.has(p["id"]) and _clock >= _busy_until.get(p["id"], 0.0)


func _mark_busy(id: int, dur: float) -> void:
	_busy_until[id] = max(_busy_until.get(id, 0.0), _clock + dur)


func _hold(dur: float) -> void:
	_step_until = max(_step_until, _clock + dur)


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
		if not _idle_piece(i):
			return
		var steps := board.begin_tap(i)
		if not steps.is_empty():
			_touch()
			_pending = true
			_hold(steps[0]["dur"] + 0.24)
			move_started.emit()
			_start_clear(steps[0], 0.0)
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


## Хід приймається будь-коли: і під час падіння, і під час вибухів.
## Не можна рухати лише той камінь, який сам зараз летить.
func _try_swap(a: int, b: int) -> void:
	if busy:
		return
	if not board.can_swap(a, b):
		Sfx.play("bad")
		if board.pieces[a] != null and _idle_piece(a):
			_shake_piece(a)
		return
	if not (_idle_piece(a) and _idle_piece(b)):
		return
	var steps := board.begin_swap(a, b)
	if steps.is_empty():
		return
	_touch()
	var s: Dictionary = steps[0]
	var swap_time := 0.14 if s["ok"] else 0.3
	_mark_busy(s["ida"], swap_time)
	_mark_busy(s["idb"], swap_time)
	_hold(swap_time)
	_start_swap(s)
	if s["ok"]:
		_pending = true
		_hold(0.14 + steps[1]["dur"] + 0.24)
		move_started.emit()
		_start_clear(steps[1], 0.14)


func _shake_piece(i: int) -> void:
	var p = board.pieces[i]
	if p == null or not _nodes.has(p["id"]):
		return
	var n: Node2D = _nodes[p["id"]]
	var c := center(i)
	var tw := n.create_tween()
	tw.tween_property(n, "position", c + Vector2(6, 0), 0.04)
	tw.tween_property(n, "position", c - Vector2(6, 0), 0.06)
	tw.tween_property(n, "position", c, 0.04)


# ---------------------------------------------------------------- програвання кроків

## Наступний крок осідання: падіння, потім збіги, потім перевірка ходів.
func _advance() -> void:
	var fall := board.step_gravity()
	if not fall["moves"].is_empty():
		_start_fall(fall)
		_hold(fall["ticks"] * HOP + LAND_TIME)
		return
	var clear := board.step_matches()
	if not clear.is_empty():
		_start_clear(clear, 0.0)
		_hold(clear["dur"] + 0.24)
		return
	var shuffle := board.step_shuffle()
	if not shuffle.is_empty():
		for m in shuffle["moves"]:
			_mark_busy(m["id"], 0.6)
		_anim_shuffle(shuffle)
		if shuffle["ok"]:
			_hold(0.6)
			return
	_pending = false
	cascade = 0
	move_finished.emit()


## Послідовне програвання готових кроків (фінальний салют).
func play_steps(steps: Array) -> void:
	for s in steps:
		match s["type"]:
			"clear":
				_start_clear(s, 0.0)
				var extra := 0.0 if s["created"].is_empty() else BirthFx.GATHER + BirthFx.PAUSE + 0.06
				await _wait(max(s["dur"] + 0.24, extra))
			"fall":
				_start_fall(s)
				await _wait(s["ticks"] * HOP + LAND_TIME)
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


func _start_swap(s: Dictionary) -> void:
	var pa := center(s["a"])
	var pb := center(s["b"])
	Sfx.play("swap")
	var pairs := [[_nodes.get(s["ida"]), pa, pb], [_nodes.get(s["idb"]), pb, pa]]
	for pair in pairs:
		var n: Node2D = pair[0]
		if n == null:
			continue
		var tw := n.create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
		tw.tween_property(n, "position", pair[2], 0.14)
		if not s["ok"]:
			tw.tween_property(n, "position", pair[1], 0.14)
	if not s["ok"]:
		create_tween().tween_callback(Sfx.play.bind("bad")).set_delay(0.14)


func _start_clear(s: Dictionary, offset: float) -> void:
	cascade += 1
	var any_match := false
	for e in s["removed"]:
		_at(offset + e["t"], _remove_node.bind(e))
		if e["to"] >= 0:
			any_match = true
	if any_match:
		# кожен наступний збіг каскаду звучить на сходинку гами вище
		_at(offset, Sfx.play.bind("match", pow(2.0, CASCADE_SCALE[mini(cascade - 1, CASCADE_SCALE.size() - 1)] / 12.0)))
	for e in s["blockers"]:
		_at(offset + e["t"], _blocker_event.bind(e))
	if not s["created"].is_empty():
		# рух далі починається, коли бустер уже проступає
		_hold(offset + BirthFx.GATHER + BirthFx.PAUSE + 0.06)
	for e in s["created"]:
		# камені групи, з якої народжується бустер
		var cells: Array = []
		var hue := Color.WHITE
		for r in s["removed"]:
			if r["to"] == e["idx"]:
				var rn: Node2D = _nodes.get(r["id"])
				if rn != null:
					rn.set_meta("bkind", e["kind"])
				cells.append([center(r["idx"]), 1 if (r["idx"] % board.w + r["idx"] / board.w) % 2 == 1 else -1])
				if r["color"] >= 0:
					hue = Art.PIECE_COLORS[r["color"]]
		_at(offset + e["t"], _birth.start.bind(center(e["idx"]), cells, hue, e["kind"]))
		_at(offset + e["t"] + BirthFx.GATHER + BirthFx.PAUSE, _create_event.bind(e))
	for e in s["transformed"]:
		_at(offset + e["t"], _transform_event.bind(e))
	for e in s["fx"]:
		_at(offset + e["t"], _fx_event.bind(e))


func _remove_node(e: Dictionary) -> void:
	if e["goal"] != "":
		goal_progress.emit(e["goal"])
	var n: Node2D = _nodes.get(e["id"])
	if n == null:
		# камінь зник раніше, ніж устиг з'явитися на екрані (бустер одразу підірвали)
		_dead[e["id"]] = true
		return
	_nodes.erase(e["id"])
	_busy_until.erase(e["id"])
	var sp: Sprite2D = n.get_meta("sp")
	if e["to"] >= 0:
		# камені, що зливаються в бустер, уламків не дають: вони летять дугою з хвостом
		var from := n.position
		var to := center(e["to"])
		var side := 1 if (e["idx"] % board.w + e["idx"] / board.w) % 2 == 1 else -1
		var dark: bool = n.get_meta("bkind", -1) == Board.Kind.BOMB
		n.z_index = 1
		var tw := n.create_tween()
		tw.tween_method(func(p: float):
			var q: Array = BirthFx.gather_pos(from, to, p, side, cell)
			n.position = q[0]
			n.scale = Vector2.ONE * (1.0 - 0.45 * maxf(0.0, q[1]))
			var c := Color.WHITE.lerp(Color(0.3, 0.24, 0.5), maxf(0.0, q[1]) * 0.75) if dark else Color.WHITE
			c.a = 1.0 - BirthFx.smooth((p - 0.82) / 0.18)
			n.modulate = c
		, 0.0, 1.0, BirthFx.GATHER)
		tw.tween_callback(n.queue_free)
		return
	# камінь розколюється на уламки своєї форми й кольору
	var color: Color = Art.VIOLET
	if e["color"] >= 0:
		color = Art.PIECE_COLORS[e["color"]]
	elif e["kind"] == Board.Kind.BOMB:
		color = Art.GOLD
	elif e["kind"] == Board.Kind.SHUR:
		color = Color("#e3e9f6")
	elif e["kind"] == Board.Kind.STAR:
		color = Color.WHITE
	if sp != null and sp.texture != null:
		_shards.shatter(n.position, sp.texture, cell * PIECE_SCALE, sp.rotation, cell, color)
	else:
		_burst(center(e["idx"]), color, 7)
	n.queue_free()


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
	var tw := s.create_tween()
	tw.tween_property(s, "scale", base * 1.12, 0.06)
	tw.tween_property(s, "scale", base, 0.1)


func _vanish(s: Node2D) -> void:
	var tw := s.create_tween().set_parallel(true)
	tw.tween_property(s, "scale", s.scale * 1.25, 0.16)
	tw.tween_property(s, "modulate:a", 0.0, 0.16)
	tw.chain().tween_callback(s.queue_free)


func _create_event(e: Dictionary) -> void:
	if _dead.has(e["id"]):
		_dead.erase(e["id"])
		return
	Sfx.play("create")
	var pos := center(e["idx"])
	if "auto" in OS.get_cmdline_user_args():
		print("birth kind=%d frame=%d" % [e["kind"], Engine.get_frames_drawn()])
	var n := _make_piece(e["id"], e["kind"], -1, pos)
	n.set_meta("live", false)
	var kind: int = e["kind"]
	var sp: Sprite2D = n.get_meta("sp")
	var base := sp.scale
	var rot0 := sp.rotation
	# біла постать, з якої проступає бустер
	var white := Sprite2D.new()
	white.texture = sp.texture
	white.material = _white
	sp.add_child(white)
	var tw := n.create_tween()
	tw.tween_method(func(p: float):
		var k := 0.5 + 0.5 * BirthFx.back(p, BirthFx.BOUNCE)
		var sc := Vector2(k, k)
		var rot := 0.0
		var dy := 0.0
		if kind == Board.Kind.BOMB:
			# бомба падає згори й присідає
			dy = -(1.0 - BirthFx.ease_in(p / 0.5)) * cell * 0.95
			if p > 0.5:
				var sq := sin(PI * clampf((p - 0.5) / 0.3, 0.0, 1.0)) * 0.24
				sc *= Vector2(1.0 + sq, 1.0 - sq)
		elif kind == Board.Kind.SHUR:
			rot = -(1.0 - BirthFx.ease_out(p)) * PI * 3.0
		elif kind == Board.Kind.STAR:
			rot = -(1.0 - BirthFx.ease_out(p)) * PI * 0.5
		sp.scale = base * sc
		sp.rotation = rot0 + rot
		sp.position = Vector2(0, dy)
		white.modulate.a = 1.0 - BirthFx.smooth(p / 0.85)
	, 0.0, 1.0, BirthFx.REVEAL)
	tw.tween_callback(func():
		white.queue_free()
		sp.scale = base
		sp.position = Vector2.ZERO
		n.set_meta("live", true))
	_shake(cell * 0.06)
	_push_neighbours(pos, e["id"])


## Хвиля від появи бустера легко штовхає сусідні камені.
func _push_neighbours(pos: Vector2, skip_id: int) -> void:
	for id in _nodes:
		if id == skip_id:
			continue
		var n: Node2D = _nodes[id]
		var d := n.position - pos
		var dist := d.length() / cell
		if dist < 0.3 or dist > 3.6:
			continue
		var sp: Sprite2D = n.get_meta("sp")
		var dir := d.normalized()
		var amp := 13.0 / maxf(1.0, dist) * (0.8 + BirthFx.GLOW * 0.5) * cell / 56.0
		var tw := n.create_tween()
		tw.tween_interval(dist * 0.045)
		tw.tween_method(func(u: float): sp.position = dir * (sin(u * PI) * (1.0 - u) * amp), 0.0, 1.0, 0.42)


## Тіні всіх каменів малюються одним шаром під каменями (один виклик замість окремого на кожен камінь).
func _draw_shadows() -> void:
	var half := Vector2(cell * 0.4, cell * 0.1)
	for c in _pieces_layer.get_children():
		var n := c as Node2D
		if n == null or n.modulate.a <= 0.02:
			continue
		var h := half * n.scale.x
		_shadow_layer.draw_texture_rect(Art.shadow, Rect2(n.position + Vector2(0, cell * 0.4) - h, h * 2.0), false,
				Color(1, 1, 1, n.modulate.a))


func live_boosters() -> Array:
	if _live_frame == Engine.get_process_frames():
		return _live_cache
	_live_frame = Engine.get_process_frames()
	var out: Array = []
	_live_cache = out
	for id in _nodes:
		var n: Node2D = _nodes[id]
		if n.get_meta("live", false):
			out.append(n)
	return out


func _transform_event(e: Dictionary) -> void:
	var n: Node2D = _nodes.get(e["id"])
	if n == null:
		return
	_set_look(n, e["kind"], -1)
	n.scale = Vector2.ONE * 0.5
	var tw := n.create_tween()
	tw.tween_property(n, "scale", Vector2.ONE * 1.2, 0.1)
	tw.tween_property(n, "scale", Vector2.ONE, 0.08)


func _start_fall(s: Dictionary) -> void:
	for m in s["moves"]:
		var path: Array = m["path"]
		var n: Node2D = _nodes.get(m["id"])
		var t := 0
		if n == null:
			n = _make_piece(m["id"], m["kind"], m["color"], center(path[0][0]) - Vector2(0, cell))
			n.modulate.a = 0.0
			var tw0 := n.create_tween()
			var first_tick: int = path[0][1]
			if first_tick > 0:
				tw0.tween_interval(first_tick * HOP)
				t = first_tick
			tw0.tween_property(n, "modulate:a", 1.0, HOP * 0.6)
		var tw := n.create_tween()
		t = 0
		for step in path:
			var tick: int = step[1]
			if tick > t:
				tw.tween_interval((tick - t) * HOP)
			tw.tween_property(n, "position", center(step[0]), HOP)
			t = tick + 1
		var sp: Sprite2D = n.get_meta("sp")
		var base: Vector2 = Vector2.ONE * cell * PIECE_SCALE / sp.texture.get_width()
		# приземлення: камінь трохи присідає і легко відскакує
		var rest := center(path[path.size() - 1][0])
		tw.tween_property(sp, "scale", base * Vector2(1.1, 0.88), 0.05)
		tw.tween_property(sp, "scale", base, 0.07)
		tw.parallel().tween_property(n, "position", rest - Vector2(0, cell * BOUNCE), 0.08) \
				.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
		tw.tween_property(n, "position", rest, 0.09).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		_mark_busy(m["id"], t * HOP + LAND_TIME)
	Sfx.play("land", 1.0, -4.0)


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
			Sfx.play("bomb", 1.0 if e["r"] <= 1 else 0.8)
			Progress.vibrate(30)
			_ring(pos, cell * (e["r"] * 2 + 1.6), Color(1, 0.85, 0.5, 0.75), 0.32)
			_shake(6.0 if e["r"] <= 1 else 11.0)
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
	if board == null:
		return
	_clock += delta
	_shadow_layer.queue_redraw()
	# життя після появи: усі бустери ледь дихають, сюрикен ще й повільно обертається
	var breath := 1.0 + 0.045 * (0.5 - 0.5 * cos(_clock * TAU / 2.6))
	for n in live_boosters():
		var sp: Sprite2D = n.get_meta("sp")
		if n.get_meta("kind") == Board.Kind.SHUR:
			sp.rotation += 0.9 * delta
		sp.scale = Vector2.ONE * cell * PIECE_SCALE / sp.texture.get_width() * breath
	if _pending and not busy and _clock >= _step_until:
		_advance()
	if busy or _pending or not input_enabled:
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
		var tw := n.create_tween().set_loops()
		tw.tween_property(n, "scale", Vector2.ONE * 1.13, 0.32).set_trans(Tween.TRANS_SINE)
		tw.tween_property(n, "scale", Vector2.ONE, 0.32).set_trans(Tween.TRANS_SINE)
		tw.tween_interval(0.25)
		_hint_tweens.append(tw)
