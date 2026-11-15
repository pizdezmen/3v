extends Node
## Звуки: невеликий пул програвачів, щоб кілька ефектів звучали разом.

const NAMES := ["click", "swap", "bad", "match", "create", "line", "bomb", "star", "fly",
		"wood", "ice", "chain", "win", "lose", "land", "shuffle"]

var _streams := {}
var _players: Array = []
var _next := 0
var _last := {}


func _ready() -> void:
	for n in NAMES:
		var path := "res://assets/sfx/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_players.append(p)


func play(sound: String, pitch: float = 1.0, volume_db: float = 0.0) -> void:
	if not Progress.sound_on or not _streams.has(sound):
		return
	var now := Time.get_ticks_msec()
	if now - int(_last.get(sound, -1000)) < 35:
		return
	_last[sound] = now
	var p: AudioStreamPlayer = _players[_next]
	_next = (_next + 1) % _players.size()
	p.stream = _streams[sound]
	p.pitch_scale = pitch
	p.volume_db = volume_db
	p.play()
