class_name BirthFx
extends Node2D
## Світло народження бустера: хвости каменів, що збираються, ядро в паузі,
## спалах, хвиля, іскри, характер і "життя" бустерів. Числа обрав власник
## на сторінці зразків "Народження бустерів".

const GATHER := 0.44      # камені збираються дугою з хвостом
const PAUSE := 0.16       # пауза з ядром
const REVEAL := 0.52      # бустер проступає зі світла
const GLOW := 0.7         # сила світіння
const SPARKS := 12        # іскри світла при появі
const BOUNCE := 1.0       # пружність появи
const STAR_COLS := [Color("#3384f5"), Color("#e23b58"), Color("#f5b416"), Color("#1fb875")]
const STAR_DIRS := [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]

var view: BoardView
var _births: Array = []
var _blob: GradientTexture2D
var _sparks: Array = []
var _time := 0.0


static func smooth(v: float) -> float:
	v = clampf(v, 0.0, 1.0)
	return v * v * (3.0 - 2.0 * v)


static func ease_out(v: float) -> float:
	v = clampf(v, 0.0, 1.0)
	return 1.0 - pow(1.0 - v, 3.0)


static func ease_in(v: float) -> float:
	v = clampf(v, 0.0, 1.0)
	return v * v * v


static func back(v: float, k: float) -> float:
	v = clampf(v, 0.0, 1.0)
	var c := 1.70158 * k
	return 1.0 + (c + 1.0) * pow(v - 1.0, 3.0) + c * pow(v - 1.0, 2.0)


## Де камінь у мить p (0..1) на шляху з from до to: дуга, спершу легкий відтяг назад.
## Повертає [позиція, просування e].
static func gather_pos(from: Vector2, to: Vector2, p: float, side: int, cell: float) -> Array:
	var d := to - from
	var l := d.length()
	if l < 1.0:
		return [from, p * p]
	var e := p * p * (2.3 * p - 1.3)
	var nrm := Vector2(-d.y, d.x) / l
	var mid := from + d * 0.5 + nrm * (cell * 0.55 * side)
	var w := 1.0 - e
	return [from * (w * w) + mid * (2.0 * w * e) + to * (e * e), e]


func _ready() -> void:
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = add
	var g := Gradient.new()
	g.colors = PackedColorArray([Color(1, 1, 1, 1), Color(1, 1, 1, 0)])
	g.offsets = PackedFloat32Array([0.0, 1.0])
	_blob = GradientTexture2D.new()
	_blob.gradient = g
	_blob.width = 64
	_blob.height = 64
	_blob.fill = GradientTexture2D.FILL_RADIAL
	_blob.fill_from = Vector2(0.5, 0.5)
	_blob.fill_to = Vector2(1.0, 0.5)
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	for i in 40:
		_sparks.append([rng.randf() * TAU, 0.6 + rng.randf() * 1.6, 0.5 + rng.randf() * 0.8])


## cells: [[звідки, бік дуги]], pos: де з'явиться бустер.
func start(pos: Vector2, cells: Array, hue: Color, kind: int) -> void:
	_births.append({"t": 0.0, "pos": pos, "cells": cells, "hue": hue, "kind": kind})


func clear() -> void:
	_births.clear()


func _process(delta: float) -> void:
	_time += delta
	for b in _births:
		b["t"] += delta
	_births = _births.filter(func(b): return b["t"] < GATHER + PAUSE + REVEAL + 0.3)
	queue_redraw()


func _glow(p: Vector2, r: float, c: Color, a: float) -> void:
	if a <= 0.004 or r <= 0.5:
		return
	draw_texture_rect(_blob, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(c.r, c.g, c.b, minf(a, 1.0)))


func _draw() -> void:
	if view == null or view.board == null:
		return
	var s: float = view.cell
	var px := s / 56.0        # сторінка зразків мала клітинку 56
	for b in _births:
		var tm: float = b["t"]
		var t_r := tm - GATHER - PAUSE
		var pos: Vector2 = b["pos"]
		var hue: Color = b["hue"]
		var kind: int = b["kind"]
		# хвости каменів
		if tm < GATHER:
			var p := tm / GATHER
			for c in b["cells"]:
				for j in range(7, 0, -1):
					var pp := p - j * 0.045
					if pp < 0.0:
						continue
					var q: Array = gather_pos(c[0], pos, pp, c[1], s)
					_glow(q[0], s * 0.42 * (1.0 - j / 9.0), hue, GLOW * 0.55 * (1.0 - j / 8.0) * smooth(p * 4.0))
				if kind == Board.Kind.SHUR:
					var q0: Array = gather_pos(c[0], pos, p, c[1], s)
					if q0[1] > 0.3:
						_glow(q0[0], s * 0.4, Color("#e3e9f6"), (q0[1] - 0.3) * GLOW)
		# ядро в паузі
		if tm > GATHER * 0.75 and t_r < REVEAL * 0.5:
			var ca := smooth((tm - GATHER * 0.75) / (GATHER * 0.25 + PAUSE)) if t_r < 0.0 else 1.0 - smooth(t_r / (REVEAL * 0.5))
			var cr := s * (0.35 + 0.55 * ca)
			_glow(pos, cr * 1.7, hue, ca * (0.4 + GLOW * 0.6))
			_glow(pos, cr * 0.8, Color.WHITE, ca)
		if t_r <= 0.0:
			continue
		var p2 := clampf(t_r / REVEAL, 0.0, 1.0)
		# бустер проступає зі світла
		_glow(pos, s * (0.9 + 0.7 * p2), Color.WHITE, (1.0 - p2) * (0.3 + GLOW * 0.6))
		_glow(pos, s * 1.5, hue, (1.0 - p2) * GLOW * 0.6)
		if kind == Board.Kind.STAR:
			var d := s * 0.95 * ease_out(p2)
			for i in 4:
				_glow(pos + STAR_DIRS[i] * d, s * (0.5 + 0.5 * p2), STAR_COLS[i], (1.0 - p2) * (0.5 + GLOW * 0.9))
		if kind == Board.Kind.BOMB and p2 > 0.55:
			var fp := sin((p2 - 0.55) / 0.45 * PI)
			var fuse: Vector2 = pos + Vector2(0.36, -0.38) * s * 0.92
			_glow(fuse, s * (0.25 + 0.5 * fp), Color("#f6c445"), fp * (0.6 + GLOW * 0.6))
			_glow(fuse, s * 0.14, Color.WHITE, fp)
		# спалах
		if t_r < 0.26:
			var fa := 1.0 - t_r / 0.26
			_glow(pos, s * 2.6, Color.WHITE, fa * (0.35 + GLOW * 0.5))
			draw_rect(Rect2(pos - Vector2(s, s) / 2.0, Vector2(s, s)), Color(1, 1, 1, fa * 0.14))
		# хвиля
		if t_r < 0.42:
			var ra := t_r / 0.42
			draw_arc(pos, s * (0.4 + 2.9 * ease_out(ra)), 0.0, TAU, 48,
					Color(1, 1, 1, (1.0 - ra) * (0.25 + GLOW * 0.4)), (4.0 * (1.0 - ra) + 1.0) * px, true)
		# іскри
		var age := t_r / 0.62
		if age < 1.0:
			for i in SPARKS:
				var sp: Array = _sparks[i]
				var dist: float = s * sp[1] * 1.5 * ease_out(age)
				var q2 := pos + Vector2(cos(sp[0]), sin(sp[0])) * dist + Vector2(0, 40.0 * age * age * px)
				_glow(q2, 7.0 * sp[2] * px, hue, (1.0 - age) * (0.7 + GLOW * 0.4))
				_glow(q2, 2.6 * sp[2] * px, Color.WHITE, 1.0 - age)
	# життя після появи: зірка переливається, запал бомби жевріє
	for n in view.live_boosters():
		var kind: int = n.get_meta("kind")
		if kind == Board.Kind.STAR:
			_glow(n.position, s * 0.95, STAR_COLS[int(_time * 1.2) % 4], (0.12 + 0.1 * sin(_time * 3.2)) * (0.4 + GLOW) * n.modulate.a)
		elif kind == Board.Kind.BOMB:
			var fl := 0.55 + 0.45 * sin(_time * 17.0) * sin(_time * 5.3)
			var fuse: Vector2 = n.position + Vector2(0.36, -0.38) * s * 0.92
			_glow(fuse, s * 0.26, Color("#f6c445"), fl * (0.35 + GLOW * 0.5) * n.modulate.a)
			_glow(fuse, s * 0.09, Color.WHITE, fl * 0.9 * n.modulate.a)
