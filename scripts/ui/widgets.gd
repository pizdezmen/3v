class_name Widgets
extends RefCounted
## Дрібні елементи інтерфейсу, намальовані кодом.


class StarRow extends Control:
	var filled := 0
	var star_size := 40.0
	var gap := 6.0

	func _init(count: int = 0, size_px: float = 40.0) -> void:
		filled = count
		star_size = size_px
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(star_size * 3 + gap * 2, star_size)

	func _draw() -> void:
		var total := star_size * 3 + gap * 2
		var x0 := (size.x - total) / 2.0
		for i in 3:
			var c := Vector2(x0 + star_size / 2.0 + i * (star_size + gap), size.y / 2.0)
			var pts := PackedVector2Array()
			for k in 10:
				var r := star_size / 2.0 if k % 2 == 0 else star_size * 0.24
				var a := -PI / 2 + k * PI / 5
				pts.append(c + Vector2(cos(a), sin(a)) * r)
			draw_colored_polygon(pts, Art.GOLD if i < filled else Color("#3b3966"))


class Gear extends Button:
	func _init() -> void:
		custom_minimum_size = Vector2(96, 96)
		size = Vector2(96, 96)
		flat = true
		focus_mode = Control.FOCUS_NONE
		for s in ["normal", "hover", "pressed", "focus"]:
			add_theme_stylebox_override(s, StyleBoxEmpty.new())
		pressed.connect(func(): Sfx.play("click"))

	func _draw() -> void:
		var c := size / 2.0
		# «серпанок»: напівпрозоре коло без рамки з м'якою тінню
		draw_texture_rect(Art.dot, Rect2(c - Vector2(62, 56), Vector2(124, 124)), false, Color(0, 0, 0, 0.45))
		var fill := Color(44 / 255.0, 40 / 255.0, 86 / 255.0, 0.68 if not button_pressed else 0.9)
		draw_circle(c, 46, fill, true, -1.0, true)
		var pts := PackedVector2Array()
		for k in 16:
			var r := 31.0 if k % 2 == 0 else 22.0
			var a := k * PI / 8
			pts.append(c + Vector2(cos(a), sin(a)) * r)
		draw_colored_polygon(pts, Art.LILAC)
		draw_circle(c, 22, Art.LILAC)
		draw_circle(c, 10, Color(44 / 255.0, 40 / 255.0, 86 / 255.0))


class Check extends Control:
	func _init(size_px: float) -> void:
		custom_minimum_size = Vector2(size_px, size_px)
		size = custom_minimum_size
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var s := size.x
		draw_polyline(PackedVector2Array([Vector2(s * 0.12, s * 0.55), Vector2(s * 0.4, s * 0.82), Vector2(s * 0.9, s * 0.22)]),
				Color("#5fe3a1"), s * 0.16, true)


## Вікно поверх екрана: заголовок, довільний вміст, кнопки.
static func dialog(parent: Control, title: String, body: Array, buttons: Array) -> Control:
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.02, 0.08, 0.72)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	parent.add_child(overlay)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", Art.box(Art.PANEL, 44))
	panel.custom_minimum_size = Vector2(580, 0)
	center.add_child(panel)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 44)
	panel.add_child(margin)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 26)
	margin.add_child(col)
	if title != "":
		var t := Art.label(title, 52)
		t.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(t)
	for item in body:
		col.add_child(item)
	for b in buttons:
		var btn := Art.button(b[0], 42, b.size() > 2 and b[2])
		btn.custom_minimum_size = Vector2(0, 104)
		var action: Callable = b[1]
		btn.pressed.connect(func():
			overlay.queue_free()
			action.call())
		col.add_child(btn)
	panel.pivot_offset = Vector2(290, 200)
	panel.scale = Vector2.ONE * 0.85
	overlay.modulate.a = 0.0
	var tw := overlay.create_tween().set_parallel(true)
	tw.tween_property(overlay, "modulate:a", 1.0, 0.15)
	tw.tween_property(panel, "scale", Vector2.ONE, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	return overlay


static func settings_rows() -> Array:
	var rows: Array = []
	var sound := Art.button("", 38)
	sound.custom_minimum_size = Vector2(0, 96)
	var vib := Art.button("", 38)
	vib.custom_minimum_size = Vector2(0, 96)
	var refresh := func():
		sound.text = "Звук: " + ("увімкнено" if Progress.sound_on else "вимкнено")
		vib.text = "Вібрація: " + ("увімкнено" if Progress.vibration_on else "вимкнено")
	refresh.call()
	sound.pressed.connect(func():
		Progress.sound_on = not Progress.sound_on
		Progress.save_data()
		refresh.call())
	vib.pressed.connect(func():
		Progress.vibration_on = not Progress.vibration_on
		Progress.save_data()
		refresh.call())
	rows.append(sound)
	rows.append(vib)
	return rows
