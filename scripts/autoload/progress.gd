extends Node
## Збережений прогрес: зірки кампанії, номер нескінченного рівня, налаштування.

const PATH := "user://save.json"
const CAMPAIGN_LEVELS := 20

var stars := {}          # "номер рівня" -> 1..3
var endless_level := 1
var sound_on := true
var vibration_on := true


func _ready() -> void:
	load_data()


func load_data() -> void:
	if not FileAccess.file_exists(PATH):
		return
	var data = JSON.parse_string(FileAccess.get_file_as_string(PATH))
	if not (data is Dictionary):
		return
	var s = data.get("stars", {})
	if s is Dictionary:
		for key in s:
			stars[String(key)] = clampi(int(s[key]), 0, 3)
	endless_level = max(1, int(data.get("endless_level", 1)))
	sound_on = bool(data.get("sound_on", true))
	vibration_on = bool(data.get("vibration_on", true))


func save_data() -> void:
	var f := FileAccess.open(PATH, FileAccess.WRITE)
	if f == null:
		return
	f.store_string(JSON.stringify({
		"stars": stars,
		"endless_level": endless_level,
		"sound_on": sound_on,
		"vibration_on": vibration_on,
	}))
	f.close()


func stars_for(level: int) -> int:
	return int(stars.get(str(level), 0))


func is_unlocked(level: int) -> bool:
	return level <= 1 or stars_for(level - 1) > 0


func set_stars(level: int, value: int) -> void:
	if value > stars_for(level):
		stars[str(level)] = value
		save_data()


func total_stars() -> int:
	var total := 0
	for key in stars:
		total += int(stars[key])
	return total


func next_campaign_level() -> int:
	for n in range(1, CAMPAIGN_LEVELS + 1):
		if stars_for(n) == 0:
			return n
	return CAMPAIGN_LEVELS


func vibrate(ms: int) -> void:
	if vibration_on and OS.has_feature("mobile"):
		Input.vibrate_handheld(ms)
