extends Control
## Кампанія: сітка з 20 рівнів із зірками.

var main: Control


func _ready() -> void:
	var col := VBoxContainer.new()
	col.set_anchors_preset(Control.PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 36)
	add_child(col)
	col.add_child(Art.label("Кампанія", 76))
	col.add_child(Art.label("Зірок: %d із %d" % [Progress.total_stars(), Progress.CAMPAIGN_LEVELS * 3], 30, Art.LABEL, false))

	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 20)
	grid.add_theme_constant_override("v_separation", 20)
	grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	col.add_child(grid)
	var next := Progress.next_campaign_level()
	for n in range(1, Progress.CAMPAIGN_LEVELS + 1):
		var open := Progress.is_unlocked(n)
		var b := Art.button(str(n), 54, open and n == next and Progress.stars_for(n) == 0)
		b.custom_minimum_size = Vector2(150, 150)
		b.disabled = not open
		b.pressed.connect(main.play_campaign.bind(n))
		if open:
			b.add_theme_constant_override("outline_size", 0)
			var stars := Widgets.StarRow.new(Progress.stars_for(n), 30.0)
			stars.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
			stars.offset_top = -44
			stars.offset_bottom = -12
			b.add_child(stars)
			b.alignment = HORIZONTAL_ALIGNMENT_CENTER
			var sb_names := ["normal", "hover", "pressed"]
			for s in sb_names:
				var sb: StyleBoxFlat = b.get_theme_stylebox(s).duplicate()
				sb.content_margin_bottom = 40
				b.add_theme_stylebox_override(s, sb)
		grid.add_child(b)

	var back_btn := Art.button("Назад", 40)
	back_btn.custom_minimum_size = Vector2(320, 100)
	back_btn.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	back_btn.pressed.connect(back)
	col.add_child(back_btn)


func back() -> void:
	main.show_menu()
