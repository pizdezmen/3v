extends Control
## Головне меню: "Кампанія" і "Нескінченний режим".

var main: Control
var _dialog: Control


func _ready() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 28)
	add_child(col)

	var t1 := Art.label("Сяйво", 132)
	var t2 := Art.label("камень", 104, Art.LILAC)
	col.add_child(t1)
	col.add_child(t2)

	var gems := HBoxContainer.new()
	gems.alignment = BoxContainer.ALIGNMENT_CENTER
	gems.add_theme_constant_override("separation", 22)
	for i in 4:
		var r := TextureRect.new()
		r.texture = Art.pieces[i]
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = Vector2(118, 118)
		gems.add_child(r)
	col.add_child(_spacer(24))
	col.add_child(gems)
	col.add_child(_spacer(56))

	var campaign := Art.button("Кампанія", 52, true)
	campaign.custom_minimum_size = Vector2(540, 128)
	campaign.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	campaign.pressed.connect(func(): main.show_levels())
	col.add_child(campaign)
	col.add_child(Art.label("Зірок: %d із %d" % [Progress.total_stars(), Progress.CAMPAIGN_LEVELS * 3], 30, Art.LABEL, false))
	col.add_child(_spacer(8))

	var endless := Art.button("Нескінченний режим", 44)
	endless.custom_minimum_size = Vector2(540, 128)
	endless.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	endless.pressed.connect(func(): main.play_endless())
	col.add_child(endless)
	col.add_child(Art.label("Рівень %d" % Progress.endless_level, 30, Art.LABEL, false))

	var gear := Widgets.Gear.new()
	gear.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	gear.position = Vector2(size.x - 126, size.y - 126)
	gear.offset_left = -126
	gear.offset_top = -126
	gear.offset_right = -30
	gear.offset_bottom = -30
	gear.pressed.connect(_settings)
	add_child(gear)


func _spacer(h: float) -> Control:
	var c := Control.new()
	c.custom_minimum_size = Vector2(0, h)
	return c


func _settings() -> void:
	_dialog = Widgets.dialog(self, "Налаштування", Widgets.settings_rows(), [["Готово", func(): pass, true]])


func back() -> void:
	if is_instance_valid(_dialog):
		_dialog.queue_free()
	else:
		get_tree().quit()
