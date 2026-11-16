extends Node
## Текстури й кольори затвердженого вигляду.

const PIECE_COLORS := [Color("#e23b58"), Color("#1fb875"), Color("#3384f5"), Color("#f5b416")]
const FRAME := Color("#4b4884")
const CELL_A := Color("#2c2b4d")
const CELL_B := Color("#262544")
const PANEL := Color("#262544")
const LABEL := Color("#a9a2d9")
const LILAC := Color("#cfc8ff")
const GOLD := Color("#f6c445")
const BG_TOP := Color("#0b0a1d")
const BG_BOTTOM := Color("#1c1640")
const VIOLET := Color("#a06bff")

var pieces: Array = []
var bar: Texture2D
var bomb: Texture2D
var star: Texture2D
var shur: Texture2D
var crate1: Texture2D
var crate2: Texture2D
var ice1: Texture2D
var ice2: Texture2D
var chain: Texture2D
var shadow: Texture2D
var dot: Texture2D
var font_bold: Font
var font: Font


func _ready() -> void:
	# усі малюнки поля складаємо в один аркуш: тоді камені малюються одним викликом, а не кожен окремо
	var names := ["piece_0", "piece_1", "piece_2", "piece_3", "bar", "bomb", "star", "shur",
			"crate1", "crate2", "ice1", "ice2", "chain"]
	var tile := 256
	var pad := 2
	var step := tile + pad * 2
	var sheet := Image.create(step * 4, step * 4, false, Image.FORMAT_RGBA8)
	var slots: Array = []
	for i in names.size():
		var img: Image = (load("res://assets/art/%s.svg" % names[i]) as Texture2D).get_image()
		if img.is_compressed():
			img.decompress()
		img.convert(Image.FORMAT_RGBA8)
		if img.get_width() != tile or img.get_height() != tile:
			img.resize(tile, tile, Image.INTERPOLATE_LANCZOS)
		var at := Vector2i((i % 4) * step + pad, (i / 4) * step + pad)
		sheet.blit_rect(img, Rect2i(0, 0, tile, tile), at)
		slots.append(Rect2(at.x, at.y, tile, tile))
	var sheet_tex := ImageTexture.create_from_image(sheet)
	var parts: Array = []
	for r in slots:
		var t := AtlasTexture.new()
		t.atlas = sheet_tex
		t.region = r
		parts.append(t)
	pieces = parts.slice(0, 4)
	bar = parts[4]
	bomb = parts[5]
	star = parts[6]
	shur = parts[7]
	crate1 = parts[8]
	crate2 = parts[9]
	ice1 = parts[10]
	ice2 = parts[11]
	chain = parts[12]
	font_bold = load("res://assets/fonts/Rubik-ExtraBold.ttf")
	font = load("res://assets/fonts/Rubik-SemiBold.ttf")
	shadow = _radial(96, 32, Color(0, 0, 0, 0.5))
	dot = _radial(32, 32, Color(1, 1, 1, 1))


func _radial(width: int, height: int, color: Color) -> Texture2D:
	var img := Image.create(width, height, false, Image.FORMAT_RGBA8)
	for y in height:
		for x in width:
			var dx := (x + 0.5 - width / 2.0) / (width / 2.0)
			var dy := (y + 0.5 - height / 2.0) / (height / 2.0)
			var d := clampf(1.0 - sqrt(dx * dx + dy * dy), 0.0, 1.0)
			var c := color
			c.a *= smoothstep(0.0, 0.6, d)
			img.set_pixel(x, y, c)
	return ImageTexture.create_from_image(img)


func piece_texture(kind: int, color: int) -> Texture2D:
	match kind:
		Board.Kind.BAR_H, Board.Kind.BAR_V:
			return bar
		Board.Kind.BOMB:
			return bomb
		Board.Kind.STAR:
			return star
		Board.Kind.SHUR:
			return shur
	return pieces[clampi(color, 0, 3)]


func goal_texture(key: String) -> Texture2D:
	match key:
		"crate":
			return crate1
		"ice":
			return ice2
		"chain":
			return chain
	return pieces[Board.COLOR_NAMES.find(key)]


func label(text: String, size: int, color: Color = Color.WHITE, bold: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_override("font", font_bold if bold else font)
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return l


func box(fill: Color, radius: int = 36, border: Color = FRAME, border_w: int = 5) -> StyleBoxFlat:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.set_corner_radius_all(radius)
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.anti_aliasing = true
	return sb


func button(text: String, size: int = 44, accent: bool = false) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.add_theme_font_override("font", font_bold)
	b.add_theme_font_size_override("font_size", size)
	var base := Color("#6a4ee0") if accent else Color("#2c2b4d")
	var border := Color("#a58bff") if accent else FRAME
	b.add_theme_stylebox_override("normal", box(base, 30, border))
	b.add_theme_stylebox_override("hover", box(base.lightened(0.06), 30, border))
	b.add_theme_stylebox_override("pressed", box(base.darkened(0.15), 30, border))
	b.add_theme_stylebox_override("disabled", box(Color("#1d1c36"), 30, Color("#33315c")))
	b.add_theme_color_override("font_color", Color.WHITE)
	b.add_theme_color_override("font_hover_color", Color.WHITE)
	b.add_theme_color_override("font_pressed_color", LILAC)
	b.add_theme_color_override("font_disabled_color", Color("#6d6a99"))
	b.pressed.connect(func(): Sfx.play("click"))
	return b
