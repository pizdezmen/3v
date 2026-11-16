extends Control
## Ігровий екран: верхня панель ("Цілі" і "Ходи"), поле, шестерня налаштувань.

const CONTENT_W := 720.0

var main: Control
var mode := "campaign"   # або "endless"
var number := 1

var board: Board
var view: BoardView
var _level := {}
var _panel: Panel
var _moves_label: Label
var _goal_nodes := {}    # ключ цілі -> {label, shown, box}
var _goals_box: Control
var _dialog: Control
var _loading: Label
var _thread: Thread
var _finished := false
var _gear: Widgets.Gear
var autoplay := false    # демонстрація: рівень проходить бот
var _auto_rng := RandomNumberGenerator.new()
var _auto_frame := 0
var _perf_calls := 0
var _perf_time := 0.0
var _perf_sum := 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build.call_deferred()


func _build() -> void:
	var x0 := (size.x - CONTENT_W) / 2.0
	var top: float = 34.0 + (main.safe_top() if main else 0.0)
	_panel = Panel.new()
	_panel.add_theme_stylebox_override("panel", Art.box(Art.PANEL, 36))
	_panel.position = Vector2(x0 + 22, top)
	_panel.size = Vector2(676, 170)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_panel)
	var divider := ColorRect.new()
	divider.color = Art.FRAME
	divider.position = Vector2(462, 24)
	divider.size = Vector2(5, 122)
	_panel.add_child(divider)
	var goals_title := Art.label("ЦІЛІ", 24, Art.LABEL)
	goals_title.position = Vector2(34, 14)
	_panel.add_child(goals_title)
	var moves_title := Art.label("ХОДИ", 24, Art.LABEL)
	moves_title.position = Vector2(467, 14)
	moves_title.size = Vector2(209, 30)
	_panel.add_child(moves_title)
	_moves_label = Art.label("0", 92)
	_moves_label.position = Vector2(467, 44)
	_moves_label.size = Vector2(209, 112)
	_panel.add_child(_moves_label)
	_goals_box = Control.new()
	_goals_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_goals_box.position = Vector2(28, 52)
	_goals_box.size = Vector2(430, 100)
	_panel.add_child(_goals_box)

	view = BoardView.new()
	add_child(view)
	view.move_started.connect(_on_move_started)
	view.move_finished.connect(_on_move_finished)
	view.goal_progress.connect(_on_goal_progress)

	_gear = Widgets.Gear.new()
	_gear.position = Vector2(x0 + CONTENT_W - 126, size.y - 126)
	_gear.pressed.connect(_settings)
	add_child(_gear)

	_loading = Art.label("Створюю рівень…", 40, Art.LILAC)
	_loading.set_anchors_preset(Control.PRESET_FULL_RECT)
	_loading.visible = false
	add_child(_loading)
	_load_level()


func _load_level() -> void:
	_finished = false
	if mode == "campaign":
		var path := "res://levels/%02d.json" % number
		_level = JSON.parse_string(FileAccess.get_file_as_string(path))
		_start()
	else:
		view.visible = false
		_panel.visible = false
		_loading.visible = true
		_thread = Thread.new()
		_thread.start(LevelGen.generate.bind(number))


func _process(_delta: float) -> void:
	if board != null:
		# поки відкрите вікно або рівень завершено, поле не реагує на дотики
		view.input_enabled = not _finished and not is_instance_valid(_dialog) \
				and board.moves_left > 0 and not board.is_won()
	_auto_frame += 1
	if autoplay and "perf" in OS.get_cmdline_user_args():
		_perf_calls = max(_perf_calls, int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)))
		_perf_time = max(_perf_time, Performance.get_monitor(Performance.TIME_PROCESS))
		_perf_sum += Performance.get_monitor(Performance.TIME_PROCESS)
		if _auto_frame % 120 == 0:
			print("perf: max draw calls=%d max process=%.1f ms avg=%.2f ms" % [_perf_calls, _perf_time * 1000.0, _perf_sum / 120.0 * 1000.0])
			_perf_calls = 0
			_perf_time = 0.0
			_perf_sum = 0.0
	var rush: bool = autoplay and "rush" in OS.get_cmdline_user_args() and _auto_frame % 7 == 0
	if autoplay and board != null and view.input_enabled and (rush or not view.is_busy()) and not is_instance_valid(_dialog):
		var m := Bot.pick_move(board, _auto_rng)
		if not m.is_empty():
			if m["a"] == m["b"]:
				view._tap(m["a"])
			else:
				view._try_swap(m["a"], m["b"])
	if _thread != null and not _thread.is_alive():
		_level = _thread.wait_to_finish()
		_thread = null
		_loading.visible = false
		view.visible = true
		_panel.visible = true
		_start()


func _exit_tree() -> void:
	if _thread != null:
		_thread.wait_to_finish()
		_thread = null


func _start() -> void:
	board = Board.new()
	board.setup(_level, randi())
	var area_top := _panel.position.y + _panel.size.y + 36.0
	var x0 := (size.x - CONTENT_W) / 2.0
	var area := Rect2(x0 + 22, area_top, 676, size.y - area_top - 150.0)
	view.show_board(board, area)
	view.input_enabled = true
	view.busy = false
	_build_goals()
	_moves_label.text = str(board.moves_left)
	_moves_label.add_theme_color_override("font_color", Color.WHITE)
	view.modulate.a = 0.0
	view.create_tween().tween_property(view, "modulate:a", 1.0, 0.25)
	if _level.has("tip") and Progress.stars_for(number) == 0 and mode == "campaign" and not autoplay:
		_show_tip()


func _build_goals() -> void:
	for c in _goals_box.get_children():
		c.queue_free()
	_goal_nodes.clear()
	var keys: Array = board.goals.keys()
	var n: int = max(1, keys.size())
	var slot := 430.0 / n
	var icon := 88.0 if n <= 2 else 66.0
	var font := 54 if n <= 2 else 40
	for k in keys.size():
		var key: String = keys[k]
		var box := Control.new()
		box.position = Vector2(slot * k, 0)
		box.size = Vector2(slot, 100)
		_goals_box.add_child(box)
		var tex := TextureRect.new()
		tex.texture = Art.goal_texture(key)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		tex.size = Vector2(icon, icon)
		tex.position = Vector2(4, (100 - icon) / 2.0)
		tex.pivot_offset = tex.size / 2.0
		box.add_child(tex)
		var l := Art.label(str(board.goals[key]), font)
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
		l.position = Vector2(icon + 14, 0)
		l.size = Vector2(slot - icon - 14, 100)
		box.add_child(l)
		_goal_nodes[key] = {"label": l, "shown": int(board.goals[key]), "icon": tex, "box": box, "x": icon + 14, "font": font}


func _on_goal_progress(key: String) -> void:
	if not _goal_nodes.has(key):
		return
	var g: Dictionary = _goal_nodes[key]
	if g["shown"] <= 0:
		return
	g["shown"] -= 1
	var l: Label = g["label"]
	if g["shown"] > 0:
		l.text = str(g["shown"])
	else:
		l.visible = false
		var check := Widgets.Check.new(g["font"] * 0.9)
		check.position = Vector2(g["x"], (100 - check.size.y) / 2.0)
		g["box"].add_child(check)
	var icon: TextureRect = g["icon"]
	if not icon.has_meta("tw") or not (icon.get_meta("tw") as Tween).is_running():
		var tw := icon.create_tween()
		tw.tween_property(icon, "scale", Vector2.ONE * 1.15, 0.06)
		tw.tween_property(icon, "scale", Vector2.ONE, 0.1)
		icon.set_meta("tw", tw)


func _on_move_started() -> void:
	_moves_label.text = str(max(board.moves_left, 0))
	if board.moves_left <= 3:
		_moves_label.add_theme_color_override("font_color", Color("#ff8597"))


func _on_move_finished() -> void:
	if _finished:
		return
	if autoplay:
		var bad := view.debug_mismatches()
		print("settled: moves_left=%d mismatches=%d" % [board.moves_left, bad])
	for key in _goal_nodes:
		# про всяк випадок зводимо лічильники з логікою
		while _goal_nodes[key]["shown"] > board.goals.get(key, 0):
			_on_goal_progress(key)
	if board.is_won():
		_win()
	elif board.moves_left <= 0:
		_lose()


func _win() -> void:
	_finished = true
	view.input_enabled = false
	var stars := board.stars()
	if autoplay:
		pass
	elif mode == "campaign":
		Progress.set_stars(number, stars)
	else:
		Progress.endless_level = max(Progress.endless_level, number + 1)
		Progress.save_data()
	await get_tree().create_timer(0.35).timeout
	var steps := board.play_finale()
	if not steps.is_empty():
		view.busy = true
		var tw := create_tween()
		tw.tween_method(func(v: float): _moves_label.text = str(int(round(v))), float(board.moves_left), 0.0, 0.8)
		await view.play_steps(steps)
		view.busy = false
	await get_tree().create_timer(0.3).timeout
	if not is_inside_tree():
		return
	Sfx.play("win")
	var body: Array = [Widgets.StarRow.new(stars, 96.0)]
	var buttons: Array = []
	if mode == "campaign":
		if number < Progress.CAMPAIGN_LEVELS:
			buttons.append(["Далі", func(): main.play_campaign(number + 1), true])
		else:
			body.append(_text("Кампанію пройдено. Далі чекає нескінченний режим."))
			buttons.append(["Нескінченний режим", func(): main.play_endless(), true])
		buttons.append(["Ще раз", func(): main.play_campaign(number)])
		buttons.append(["До рівнів", func(): main.show_levels()])
	else:
		buttons.append(["Далі", func(): main.play_endless(), true])
		buttons.append(["У меню", func(): main.show_menu()])
	_dialog = Widgets.dialog(self, "Рівень пройдено!", body, buttons)


func _lose() -> void:
	_finished = true
	view.input_enabled = false
	await get_tree().create_timer(0.4).timeout
	if not is_inside_tree():
		return
	Sfx.play("lose")
	var again := func():
		if mode == "campaign":
			main.play_campaign(number)
		else:
			main.play_endless()
	var out := func():
		if mode == "campaign":
			main.show_levels()
		else:
			main.show_menu()
	_dialog = Widgets.dialog(self, "Ходи закінчилися", [_text("Цього разу не вистачило зовсім трохи.")],
			[["Ще раз", again, true], ["До рівнів" if mode == "campaign" else "У меню", out]])


func _text(text: String) -> Label:
	var l := Art.label(text, 34, Art.LILAC, false)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size = Vector2(480, 0)
	return l


func _show_tip() -> void:
	var body: Array = []
	var icon_key: String = _level.get("tip_icon", "")
	var tex: Texture2D = null
	match icon_key:
		"bar":
			tex = Art.bar
		"bomb":
			tex = Art.bomb
		"star":
			tex = Art.star
		"shur":
			tex = Art.shur
		"crate":
			tex = Art.crate2
		"ice":
			tex = Art.ice2
		"chain":
			tex = Art.chain
		"red":
			tex = Art.pieces[0]
	if tex != null:
		var r := TextureRect.new()
		r.texture = tex
		r.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		r.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		r.custom_minimum_size = Vector2(150, 150)
		body.append(r)
	body.append(_text(_level["tip"]))
	_dialog = Widgets.dialog(self, "Рівень %d" % number, body, [["Грати", func(): pass, true]])


func _settings() -> void:
	if is_instance_valid(_dialog) or _finished:
		return
	var title := "Рівень %d" % number
	if mode == "endless":
		title = "Нескінченний режим, рівень %d" % number
	var restart := func():
		if mode == "campaign":
			main.play_campaign(number)
		else:
			main.play_endless()
	_dialog = Widgets.dialog(self, title, Widgets.settings_rows(), [
		["Продовжити", func(): pass, true],
		["Почати заново", restart],
		["Вийти", func(): back_out()],
	])


func back_out() -> void:
	if mode == "campaign":
		main.show_levels()
	else:
		main.show_menu()


func back() -> void:
	if is_instance_valid(_dialog):
		if not _finished:
			_dialog.queue_free()
	else:
		_settings()
