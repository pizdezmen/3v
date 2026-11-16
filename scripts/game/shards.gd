class_name Shards
extends Node2D
## Уламки каменів. Камінь розколюється на ламані скалки своєї справжньої форми
## й кольору; разом вони одразу близько 30% площі каменя, далі зменшуються
## в падінні й летять униз за екран. Числа обрав власник на сторінці зразків.

const COUNT := 7          # уламків з одного каменя
const AREA := 0.30        # сумарна площа уламків від площі каменя
const SHRINK := 0.70      # наскільки зменшуються, долетівши до низу екрана
const FORCE := 0.70       # сила розльоту
const WEIGHT := 0.80      # вага (швидкість падіння)
const SPIN := 0.90        # обертання
const FLASH := true       # спалах у клітинці
const MAX_LIVE := 420     # коли уламків на екрані забагато, камені дають менше скалок

var _items: Array = []
var _add: CanvasItemMaterial


func _ready() -> void:
	_add = CanvasItemMaterial.new()
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


## pos: центр каменя (у координатах цього вузла), d: розмір каменя на екрані.
func shatter(pos: Vector2, tex: Texture2D, d: float, rot: float, cell: float, color: Color) -> void:
	var u := cell / 37.0      # сторінка зразків мала клітинку 37
	var n := COUNT if _items.size() < MAX_LIVE else 3
	var k := sqrt(AREA)
	var ts := tex.get_size()
	var bottom := to_local(Vector2(0, get_viewport_rect().size.y)).y + cell
	for poly in _cut(d, n):
		var c := Vector2.ZERO
		for v in poly:
			c += v
		c /= poly.size()
		var pts := PackedVector2Array()
		var uvs := PackedVector2Array()
		for v in poly:
			pts.append(v - c)
			uvs.append((v / d + Vector2(0.5, 0.5)) * ts)
		var node := Polygon2D.new()
		node.texture = tex
		node.polygon = pts
		node.uv = uvs
		var cr := c.rotated(rot)
		node.position = pos + cr
		node.rotation = rot
		node.scale = Vector2.ONE * k
		add_child(node)
		var dir := cr.normalized() if cr.length() > 0.01 else Vector2.UP
		_items.append({
			"n": node, "k": k, "y0": pos.y, "bottom": bottom,
			"v": Vector2((dir.x * 55.0 + randf_range(-30.0, 30.0)) * FORCE,
					(dir.y * 40.0 - 70.0 - randf() * 60.0) * FORCE) * u,
			"g": 900.0 * WEIGHT * u,
			"vr": randf_range(-4.5, 4.5) * SPIN,
		})
	if FLASH:
		var f := Sprite2D.new()
		f.texture = Art.dot
		f.material = _add
		f.position = pos
		f.modulate = Color.WHITE.lerp(color, 0.35)
		f.modulate.a = 0.5
		var s0 := cell / Art.dot.get_width()
		f.scale = Vector2.ONE * s0
		add_child(f)
		move_child(f, 0)
		var tw := f.create_tween().set_parallel(true)
		tw.tween_property(f, "scale", Vector2.ONE * s0 * 2.0, 0.22)
		tw.tween_property(f, "modulate", Color(color.r, color.g, color.b, 0.0), 0.22)
		tw.chain().tween_callback(f.queue_free)


func _process(delta: float) -> void:
	if _items.is_empty():
		return
	var dt := minf(delta, 0.05)
	var keep: Array = []
	for s in _items:
		var node: Polygon2D = s["n"]
		s["v"].y += s["g"] * dt
		node.position += s["v"] * dt
		node.rotation += s["vr"] * dt
		var prog := clampf((node.position.y - s["y0"]) / maxf(1.0, s["bottom"] - s["y0"]), 0.0, 1.0)
		node.scale = Vector2.ONE * s["k"] * (1.0 - SHRINK * prog)
		if node.position.y > s["bottom"]:
			node.queue_free()
		else:
			keep.append(s)
	_items = keep


## Розкол квадрата каменя на опуклі ламані скалки: щоразу ділимо найбільший шматок.
func _cut(d: float, n: int) -> Array:
	var h := d / 2.0
	var polys: Array = [[Vector2(-h, -h), Vector2(h, -h), Vector2(h, h), Vector2(-h, h)]]
	var guard := 0
	while polys.size() < n and guard < 60:
		guard += 1
		var bi := 0
		for i in range(1, polys.size()):
			if _area(polys[i]) > _area(polys[bi]):
				bi = i
		var p: Array = polys[bi]
		var ce := Vector2.ZERO
		for v in p:
			ce += v
		ce /= p.size()
		var jit := d * 0.05
		var parts := _split(p, ce + Vector2(randf_range(-jit, jit), randf_range(-jit, jit)), randf() * PI)
		if parts[0].size() < 3 or parts[1].size() < 3:
			continue
		polys.remove_at(bi)
		polys.append(parts[0])
		polys.append(parts[1])
	return polys


func _area(p: Array) -> float:
	var a := 0.0
	for i in p.size():
		var q: Vector2 = p[(i + 1) % p.size()]
		a += p[i].x * q.y - q.x * p[i].y
	return absf(a) / 2.0


func _split(p: Array, pt: Vector2, ang: float) -> Array:
	var nrm := Vector2(cos(ang), sin(ang))
	var a: Array = []
	var b: Array = []
	for i in p.size():
		var u: Vector2 = p[i]
		var v: Vector2 = p[(i + 1) % p.size()]
		var du := (u - pt).dot(nrm)
		var dv := (v - pt).dot(nrm)
		if du >= 0.0:
			a.append(u)
		else:
			b.append(u)
		if (du >= 0.0) != (dv >= 0.0):
			var m := u.lerp(v, du / (du - dv))
			a.append(m)
			b.append(m)
	return [a, b]
