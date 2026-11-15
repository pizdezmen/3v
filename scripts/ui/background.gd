extends Control
## Фон "нічне небо": темний градієнт і зорі.

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(queue_redraw)


func _draw() -> void:
	var s := size
	draw_polygon(PackedVector2Array([Vector2.ZERO, Vector2(s.x, 0), s, Vector2(0, s.y)]),
			PackedColorArray([Art.BG_TOP, Art.BG_TOP, Art.BG_BOTTOM, Art.BG_BOTTOM]))
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for i in 150:
		var p := Vector2(rng.randf() * s.x, rng.randf() * s.y)
		var r := rng.randf_range(1.2, 3.0)
		draw_circle(p, r, Color(1, 1, 1, rng.randf_range(0.25, 0.8)))
