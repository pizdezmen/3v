extends SceneTree
## Статистика бота для ручних рівнів і перевірка генератора.
## Запуск: godot --headless -s tools/calibrate.gd

func _init() -> void:
	var dir := DirAccess.open("res://levels")
	var files := Array(dir.get_files())
	files.sort()
	for f in files:
		if not f.ends_with(".json"):
			continue
		var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://levels/" + f))
		var free := Bot.measure(data, 40, 90, 3)
		var wins := 0
		for g in 40:
			if Bot.play(data, 5000 + g * 31)["won"]:
				wins += 1
		print("CAL %s %d %d" % [f, free["p50"], free["p80"]])
		print("%s  ходів %d  бот: avg %.1f p50 %d p80 %d max %d  (перемог без ліміту %d/40, з лімітом %d/40)" % [
			f, data["moves"], free["avg"], free["p50"], free["p80"], free["max"], free["wins"], wins])
	var t0 := Time.get_ticks_msec()
	for n in [1, 2, 3, 5, 8, 12, 20, 35, 60]:
		var lv := LevelGen.generate(n)
		print("endless %d: %dx%d moves %d goals %s bot %s" % [n, String(lv["layout"][0]).length(),
				lv["layout"].size(), lv["moves"], lv["goals"], lv.get("bot", {})])
		for row in lv["layout"]:
			print("    ", row)
	print("генерація 9 рівнів: %d мс" % (Time.get_ticks_msec() - t0))
	quit()
