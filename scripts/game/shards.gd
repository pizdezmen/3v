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
const MAX_LIVE := 320     # коли уламків на екрані забагато, камені дають менше скалок

var _items: Array = []
var _add: CanvasItemMaterial


func _ready() -> void:
	_add = CanvasItemMaterial.new()
	_add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD


## pos: центр каменя (у координатах цього вузла), d: розмір каменя на екрані.
func shatter(pos: Vector2, tex: Texture2D, d: float, rot: float, cell: float, color: Color) -> void:
	var u := cell / 37.0      # сторінка зразків мала клітинку 37
	# що більше уламків уже летить, то менше скалок дає кожен новий камінь
	var live := _items.size()
	var n := COUNT
	if live > MAX_LIVE:
		n = 2
	elif live > MAX_LIVE / 2:
		n = 3
	elif live > MAX_LIVE / 4:
		n = 5
	var k := sqrt(AREA)
	# малюнок каменя лежить на спільному аркуші: беремо його ділянку
	var uv0 := Vector2.ZERO
	var uv1 := Vector2.ONE
	var base_tex := tex
	if tex is AtlasTexture:
		base_tex = (tex as AtlasTexture).atlas
		var sz := base_tex.get_size()
		var reg: Rect2 = (tex as AtlasTexture).region
		uv0 = reg.position / sz
		uv1 = reg.size / sz
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
			uvs.append(uv0 + (v / d + Vector2(0.5, 0.5)) * uv1)
		var cr := c.rotated(rot)
		var dir := cr.normalized() if cr.length() > 0.01 else Vector2.UP
		_items.append({
			"tex": base_tex, "pts": pts, "uvs": uvs, "p": pos + cr, "r": rot, "s": k,
			"k": k, "y0": pos.y, "bottom": bottom,
			"v": Vector2((dir.x * 55.0 + randf_range(-30.0, 30.0)) * FORCE,
					(dir.y * 40.0 - 70.0 - randf() * 60.0) * FORCE) * u,
			"g": 900.0 * WEIGHT * u,
			"vr": randf_range(-4.5, 4.5) * SPIN,
		})
	if FLASH and live < MAX_LIVE / 2:
		var f := Sprite2D.new()
		f.texture = Art.dot
		f.material = _add
		f.position = pos
		f.modulate = Color.WHITE.lerp(color, 0.35)
		f.modulate.a = 0.5
		var s0 := cell / Art.dot.get_width()
		f.scale = Vector2.ONE * s0
		add_child(f)
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
		s["v"].y += s["g"] * dt
		s["p"] += s["v"] * dt
		s["r"] += s["vr"] * dt
		var prog := clampf((s["p"].y - s["y0"]) / maxf(1.0, s["bottom"] - s["y0"]), 0.0, 1.0)
		s["s"] = s["k"] * (1.0 - SHRINK * prog)
		if s["p"].y <= s["bottom"]:
			keep.append(s)
	_items = keep
	queue_redraw()


## Усі уламки одного малюнка йдуть на екран одним викликом, щоб великі вибухи не гальмували.
func _draw() -> void:
	var groups := {}
	for s in _items:
		var tex: Texture2D = s["tex"]
		if not groups.has(tex):
			groups[tex] = [PackedVector2Array(), PackedVector2Array(), PackedInt32Array()]
		var g: Array = groups[tex]
		var pts: PackedVector2Array = s["pts"]
		var uvs: PackedVector2Array = s["uvs"]
		var base: int = g[0].size()
		var co := cos(s["r"]) * s["s"] as float
		var si := sin(s["r"]) * s["s"] as float
		var p: Vector2 = s["p"]
		for i in pts.size():
			var v := pts[i]
			g[0].append(Vector2(p.x + v.x * co - v.y * si, p.y + v.x * si + v.y * co))
			g[1].append(uvs[i])
		for i in range(1, pts.size() - 1):
			g[2].append(base)
			g[2].append(base + i)
			g[2].append(base + i + 1)
	var white := PackedColorArray([Color.WHITE])
	for tex in groups:
		var g: Array = groups[tex]
		RenderingServer.canvas_item_add_triangle_array(get_canvas_item(), g[2], g[0], white, g[1],
				PackedInt32Array(), PackedFloat32Array(), tex.get_rid())


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
