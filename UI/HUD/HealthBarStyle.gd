extends RefCounted
## Local health-bar styling, inspired by the Status Effects component palette.
## This is intentionally limited to health-bar visuals; it has no gameplay dependencies.

const FONT_PATH := "res://UI/HUD/Fredoka-Variable.ttf"

const COLOR_BACKGROUND := Color("231d1d")
const COLOR_PANEL := Color("4a3a31")
const COLOR_PANEL_BORDER := Color("2e2423")
const COLOR_HEADER := Color("5b4639")
const COLOR_ACCENT := Color("ffc23e")
const COLOR_TEXT := Color("f7f1e5")
const COLOR_TEXT_DIM := Color("b9ac9c")
const COLOR_OUTLINE := Color("241c1c")
const COLOR_HEALTH_HIGH := Color("5fc46b")
const COLOR_HEALTH_MID := Color("ffc23e")
const COLOR_HEALTH_LOW := Color("d75452")
const COLOR_DAMAGE_TRAIL := Color("d9c9a9")
const COLOR_DEAD := Color("77706b")

static var _fonts: Dictionary = {}

static func get_font(weight: int = 600) -> Font:
	if _fonts.has(weight):
		return _fonts[weight] as Font
	if not ResourceLoader.exists(FONT_PATH):
		return null
	var base_font := load(FONT_PATH) as Font
	if base_font == null:
		return null
	var variation := FontVariation.new()
	variation.base_font = base_font
	variation.variation_opentype = {"wght": weight}
	_fonts[weight] = variation
	return variation

static func style_label(label: Label, font_size: int, color: Color = COLOR_TEXT,
		weight: int = 600, outline_size: int = 2) -> void:
	var font := get_font(weight)
	if font != null:
		label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", COLOR_OUTLINE)
	label.add_theme_constant_override("outline_size", outline_size)

static func panel_style(compact: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_PANEL
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(3 if compact else 4)
	style.set_corner_radius_all(6 if compact else 12)
	style.shadow_color = Color(0, 0, 0, 0.38)
	style.shadow_size = 5 if not compact else 2
	style.shadow_offset = Vector2(0, 3 if not compact else 1)
	style.anti_aliasing = true
	return style

static func bar_background(compact: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_BACKGROUND
	style.border_color = COLOR_PANEL_BORDER
	style.set_border_width_all(1 if compact else 2)
	style.set_corner_radius_all(3 if compact else 5)
	style.anti_aliasing = true
	return style

static func health_fill(color: Color, compact: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = color.lightened(0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(2 if compact else 4)
	style.anti_aliasing = true
	return style

static func damage_fill(compact: bool = false) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_DAMAGE_TRAIL
	style.border_color = COLOR_TEXT
	style.set_border_width_all(1 if compact else 2)
	style.set_corner_radius_all(2 if compact else 4)
	style.anti_aliasing = true
	return style
