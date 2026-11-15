extends Control
## Корінь гри: тримає фон і перемикає екрани.

const Background := preload("res://scripts/ui/background.gd")
const MenuScreen := preload("res://scripts/ui/menu.gd")
const LevelsScreen := preload("res://scripts/ui/levels.gd")
const GameScreen := preload("res://scripts/game/game.gd")

var _screen: Control


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var bg := Background.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var args := OS.get_cmdline_user_args()
	if args.size() >= 1 and args[0] == "level":
		play_campaign(int(args[1]) if args.size() > 1 else 1)
	elif args.size() >= 1 and args[0] == "levels":
		show_levels()
	elif args.size() >= 1 and args[0] == "endless":
		play_endless()
	else:
		show_menu()


func _set_screen(c: Control) -> void:
	if _screen:
		_screen.queue_free()
	_screen = c
	c.set("main", self)
	c.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(c)
	c.modulate.a = 0.0
	c.create_tween().tween_property(c, "modulate:a", 1.0, 0.18)


func show_menu() -> void:
	_set_screen(MenuScreen.new())


func show_levels() -> void:
	_set_screen(LevelsScreen.new())


func play_campaign(number: int) -> void:
	var g := GameScreen.new()
	g.mode = "campaign"
	g.number = clampi(number, 1, Progress.CAMPAIGN_LEVELS)
	g.autoplay = "auto" in OS.get_cmdline_user_args()
	_set_screen(g)


func play_endless() -> void:
	var g := GameScreen.new()
	g.mode = "endless"
	g.number = Progress.endless_level
	g.autoplay = "auto" in OS.get_cmdline_user_args()
	_set_screen(g)


func safe_top() -> float:
	if not OS.has_feature("mobile"):
		return 0.0
	var win := DisplayServer.window_get_size()
	if win.y <= 0:
		return 0.0
	return DisplayServer.get_display_safe_area().position.y * size.y / win.y


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if _screen and _screen.has_method("back"):
			_screen.back()
		else:
			get_tree().quit()
