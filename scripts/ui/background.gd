extends Control
## Живий фон. Небо одне на всю гру й існує завжди: воно рухається, а рівні лише
## плавно перетворюють його з одного стану в інший (без різкої зміни).

const TRANSITION := 9.0      # тривалість перетворення, с
const MOTION := 2.4          # швидкість руху
const STAR_AMOUNT := 1.3     # кількість зір
const SHOOTING := true       # падаючі зорі
const STAR_COUNT := 260
const NUM := ["stars", "neb", "aur", "moon", "moon_y", "hor"]
const COL := ["top", "bot", "neb_a", "neb_b", "aur_c", "hor_c"]

## Стани неба: набори чисел, між якими небо плавно перетікає.
const STATES := {
	"night": {"top": Color8(11, 10, 29), "bot": Color8(28, 22, 64), "stars": 1.0, "neb": 0.0,
		"neb_a": Color8(90, 70, 200), "neb_b": Color8(60, 110, 220), "aur": 0.0, "aur_c": Color8(80, 255, 190),
		"moon": 0.0, "moon_y": 1.25, "hor": 0.0, "hor_c": Color8(255, 150, 110)},
	"aurora": {"top": Color8(6, 14, 32), "bot": Color8(16, 34, 62), "stars": 0.8, "neb": 0.15,
		"neb_a": Color8(40, 160, 150), "neb_b": Color8(60, 90, 200), "aur": 1.0, "aur_c": Color8(90, 255, 185),
		"moon": 0.0, "moon_y": 1.25, "hor": 0.0, "hor_c": Color8(80, 220, 190)},
	"nebula": {"top": Color8(20, 9, 40), "bot": Color8(44, 18, 72), "stars": 1.0, "neb": 1.0,
		"neb_a": Color8(200, 80, 220), "neb_b": Color8(90, 90, 255), "aur": 0.0, "aur_c": Color8(200, 120, 255),
		"moon": 0.0, "moon_y": 1.25, "hor": 0.0, "hor_c": Color8(220, 120, 255)},
	"moon": {"top": Color8(10, 16, 44), "bot": Color8(30, 44, 92), "stars": 0.55, "neb": 0.2,
		"neb_a": Color8(110, 140, 255), "neb_b": Color8(80, 110, 220), "aur": 0.0, "aur_c": Color8(150, 200, 255),
		"moon": 1.0, "moon_y": 0.8, "hor": 0.15, "hor_c": Color8(150, 180, 255)},
	"dawn": {"top": Color8(24, 18, 60), "bot": Color8(88, 44, 92), "stars": 0.3, "neb": 0.3,
		"neb_a": Color8(255, 130, 150), "neb_b": Color8(150, 100, 230), "aur": 0.0, "aur_c": Color8(255, 180, 150),
		"moon": 0.5, "moon_y": 0.72, "hor": 1.0, "hor_c": Color8(255, 160, 110)},
	"deep": {"top": Color8(4, 4, 12), "bot": Color8(12, 10, 30), "stars": 1.5, "neb": 0.35,
		"neb_a": Color8(50, 70, 190), "neb_b": Color8(130, 60, 190), "aur": 0.0, "aur_c": Color8(100, 120, 255),
		"moon": 0.0, "moon_y": 1.25, "hor": 0.0, "hor_c": Color8(80, 90, 200)},
}
## Порядок станів у кампанії та нескінченному режимі.
const ORDER := ["night", "aurora", "moon", "nebula", "deep", "dawn"]

var state := "night"
var _from := {}
var _to := {}
var _cur := {}
var _t_start := -100.0
var _clock := 0.0
var _stars := []
var _nebs := []
var _shoot := {"t": -10.0, "x": 0.0, "y": 0.0, "a": 0.0}
var _glow: Node2D
var _moon: Node2D
var _blob: GradientTexture2D
var _band: GradientTexture2D
var _fade: GradientTexture2D


## Стан неба для рівня кампанії (небо міняється кожні кілька рівнів).
static func state_for_campaign(number: int) -> String:
	var bounds := [3, 7, 10, 14, 17]
	for i in bounds.size():
		if number <= bounds[i]:
			return ORDER[i]
	return ORDER[5]


static func state_for_endless(number: int) -> String:
	return ORDER[int((number - 1) / 3) % ORDER.size()]


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_from = STATES["night"].duplicate()
	_to = _from.duplicate()
	_cur = _from.duplicate()
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in STAR_COUNT:
		_stars.append([rng.randf(), rng.randf(), 1.0 + rng.randf() * 2.6, rng.randf() * TAU, 0.6 + rng.randf() * 1.8, rng.randf()])
	for i in 7:
		_nebs.append([rng.randf(), rng.randf(), 0.35 + rng.randf() * 0.4, rng.randf() * TAU, rng.randf() * TAU, i % 2])
	_blob = _gradient([Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 1.0], true)
	_band = _gradient([Color(1, 1, 1, 0), Color(1, 1, 1, 1), Color(1, 1, 1, 0)], [0.0, 0.75, 1.0], false)
	_fade = _gradient([Color(1, 1, 1, 0), Color(1, 1, 1, 1)], [0.0, 1.0], false)
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_glow = Node2D.new()
	_glow.material = add
	_glow.draw.connect(_draw_glow)
	add_child(_glow)
	_moon = Node2D.new()
	_moon.draw.connect(_draw_moon)
	add_child(_moon)


func _gradient(colors: Array, offsets: Array, radial: bool) -> GradientTexture2D:
	var g := Gradient.new()
	g.colors = PackedColorArray(colors)
	g.offsets = PackedFloat32Array(offsets)
	var t := GradientTexture2D.new()
	t.gradient = g
	t.width = 64 if radial else 4
	t.height = 64
	if radial:
		t.fill = GradientTexture2D.FILL_RADIAL
		t.fill_from = Vector2(0.5, 0.5)
		t.fill_to = Vector2(1.0, 0.5)
	else:
		t.fill_from = Vector2(0, 0)
		t.fill_to = Vector2(0, 1)
	return t


## Плавно перетворює небо в інший стан, починаючи з того вигляду, який є зараз.
func go_to(key: String) -> void:
	if key == state or not STATES.has(key):
		return
	state = key
	_from = _cur.duplicate()
	_to = STATES[key].duplicate()
	_t_start = _clock


func _process(delta: float) -> void:
	_clock += minf(delta, 0.05)
	var v := clampf((_clock - _t_start) / TRANSITION, 0.0, 1.0)
	var u := v * v * v * (v * (v * 6.0 - 15.0) + 10.0)
	for k in NUM:
		_cur[k] = lerpf(_from[k], _to[k], u)
	for k in COL:
		_cur[k] = (_from[k] as Color).lerp(_to[k], u)
	queue_redraw()
	_glow.queue_redraw()
	_moon.queue_redraw()


func _draw() -> void:
	var s := size
	var top: Color = _cur["top"]
	var bot: Color = _cur["bot"]
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
			PackedColorArray([top, top, bot, bot]))


func _put_blob(p: Vector2, r: float, c: Color, a: float) -> void:
	if a <= 0.003:
		return
	_glow.draw_texture_rect(_blob, Rect2(p - Vector2(r, r), Vector2(r, r) * 2.0), false, Color(c.r, c.g, c.b, minf(a, 1.0)))


func _draw_glow() -> void:
	var w := size.x
	var h := size.y
	var k := w / 360.0          # сторінка зразка мала ширину 360
	var t := _clock * MOTION
	# туманність
	var neb: float = _cur["neb"]
	for n in _nebs:
		var p := Vector2((n[0] + sin(t * 0.03 + n[3]) * 0.12) * w, (n[1] + cos(t * 0.024 + n[4]) * 0.08) * h)
		var r: float = n[2] * w * (1.0 + 0.08 * sin(t * 0.05 + n[3]))
		_put_blob(p, r, _cur["neb_a"] if n[5] == 1 else _cur["neb_b"], neb * 0.26)
	# світло знизу
	var hor: float = _cur["hor"]
	if hor > 0.003:
		var hc: Color = _cur["hor_c"]
		_glow.draw_texture_rect(_fade, Rect2(0, h * 0.45, w, h * 0.55), false,
				Color(hc.r, hc.g, hc.b, hor * (0.5 + 0.04 * sin(t * 0.3))))
	# зорі
	var st: float = _cur["stars"]
	var count := int(round(STAR_COUNT * minf(1.0, STAR_AMOUNT * 0.62 * maxf(0.2, st))))
	var bright := minf(1.0, st)
	for i in count:
		var s: Array = _stars[i]
		var p := Vector2(fmod(s[0] * w + t * (1.2 + s[5] * 2.2) * k, w), fmod(s[1] * h + t * 0.5 * s[5] * k, h))
		var a: float = bright * (0.55 + 0.45 * sin(t * s[4] + s[3])) * (0.35 + s[5] * 0.6)
		_glow.draw_circle(p, s[2] * k * 0.5, Color(1, 1, 1, a))
		if s[2] > 3.0:
			_put_blob(p, s[2] * k * 2.0, Color8(200, 210, 255), a * 0.35)
	# північне сяйво
	var aur: float = _cur["aur"]
	if aur > 0.003:
		var ac: Color = _cur["aur_c"]
		var rows := [0.2, 0.8, 0.92]
		var step := 6.0 * k
		for r in 3:
			var x := -10.0 * k
			while x < w + 10.0 * k:
				var ph := x / k * 0.012 + r * 2.1
				var yc: float = h * rows[r] + (sin(ph + t * 0.22) * 34.0 + sin(ph * 2.3 - t * 0.13) * 14.0) * k
				var hh := (110.0 + 60.0 * sin(ph * 1.7 + t * 0.3 + r)) * k
				var a2 := aur * (0.05 + 0.045 * sin(ph * 3.1 + t * 0.5 + r * 1.3))
				if a2 > 0.0:
					_glow.draw_texture_rect(_band, Rect2(x, yc - hh, step + 1.0, hh + 20.0 * k), false, Color(ac.r, ac.g, ac.b, a2))
				x += step
	# сяйво місяця
	var moon: float = _cur["moon"]
	if moon > 0.003:
		_put_blob(Vector2(w * 0.26, h * _cur["moon_y"]), 34.0 * 4.2 * k, Color8(190, 205, 255), moon * 0.3)
	# падаюча зоря
	if SHOOTING:
		if t - _shoot["t"] > 7.0 + _shoot["a"] * 6.0:
			_shoot = {"t": t, "x": w * (0.1 + randf() * 0.6), "y": h * (0.05 + randf() * 0.3), "a": randf()}
		var age: float = (t - _shoot["t"]) / 0.9
		if age < 1.0:
			var head := Vector2(_shoot["x"] + age * 150.0 * k, _shoot["y"] + age * 70.0 * k)
			var al := sin(age * PI) * minf(1.0, st + 0.3)
			_glow.draw_polyline_colors(PackedVector2Array([head - Vector2(60, 28) * k, head]),
					PackedColorArray([Color(1, 1, 1, 0), Color(1, 1, 1, al)]), 2.0 * k, true)


func _draw_moon() -> void:
	var moon: float = _cur["moon"]
	if moon <= 0.003:
		return
	var k := size.x / 360.0
	var c := Vector2(size.x * 0.26, size.y * _cur["moon_y"])
	var a := minf(1.0, moon * 1.2)
	_moon.draw_circle(c, 34.0 * k, Color(Color("#e9edff"), a))
	for m in [[-10.0, -8.0, 8.0], [9.0, 6.0, 6.0], [-3.0, 14.0, 4.5]]:
		_moon.draw_circle(c + Vector2(m[0], m[1]) * k, m[2] * k, Color(160 / 255.0, 172 / 255.0, 220 / 255.0, 0.5 * a))
