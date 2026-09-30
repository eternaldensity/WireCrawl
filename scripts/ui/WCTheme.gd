class_name WCTheme
extends RefCounted
## Shared neon UI theme. Build once via make_theme() and assign to root
## Controls; use panel()/header()/section() helpers for consistent styling.
## Fixes: plain default Godot widgets, unreadable low-contrast rows.

static var _cached: Theme = null

const PINK := Color(1.0, 0.16, 0.43)
const CYAN := Color(0.02, 0.85, 0.91)
const YELLOW := Color(0.976, 0.941, 0.008)
const INK := Color(0.015, 0.015, 0.035)
const PANEL_BG := Color(0.03, 0.035, 0.08, 0.94)
const TEXT := Color(0.86, 0.89, 1.0)
const DIM := Color(0.55, 0.6, 0.75)

static func make_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()
	# Buttons (default cyan accent; per-button accents via style_button()).
	t.set_stylebox("normal", "Button", _btn_box(CYAN.darkened(0.35)))
	t.set_stylebox("hover", "Button", _btn_box(CYAN))
	t.set_stylebox("pressed", "Button", _btn_box(PINK))
	t.set_stylebox("disabled", "Button", _btn_box(Color(0.25, 0.25, 0.3)))
	t.set_stylebox("focus", "Button", StyleBoxEmpty.new())
	t.set_color("font_color", "Button", TEXT)
	t.set_color("font_hover_color", "Button", Color.WHITE)
	t.set_color("font_pressed_color", "Button", Color.WHITE)
	t.set_color("font_disabled_color", "Button", Color(0.45, 0.45, 0.5))
	t.set_font_size("font_size", "Button", 15)
	# OptionButtons match.
	for item in ["normal", "hover", "pressed", "disabled"]:
		t.set_stylebox(item, "OptionButton", t.get_stylebox(item, "Button"))
	t.set_stylebox("focus", "OptionButton", StyleBoxEmpty.new())
	for col in ["font_color", "font_hover_color", "font_pressed_color"]:
		t.set_color(col, "OptionButton", Color.WHITE)
	t.set_font_size("font_size", "OptionButton", 14)
	# Sliders: dark track, neon fill.
	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.08, 0.09, 0.16)
	track.set_corner_radius_all(3)
	track.content_margin_top = 3
	track.content_margin_bottom = 3
	t.set_stylebox("slider", "HSlider", track)
	var fill := StyleBoxFlat.new()
	fill.bg_color = Color(0.02, 0.55, 0.62)
	fill.set_corner_radius_all(3)
	t.set_stylebox("grabber_area", "HSlider", fill)
	t.set_stylebox("grabber_area_highlight", "HSlider", fill)
	t.set_stylebox("focus", "HSlider", StyleBoxEmpty.new())
	_cached = t
	return t

static func _btn_box(border: Color) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.05, 0.06, 0.12, 0.96)
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 12
	s.content_margin_right = 12
	s.content_margin_top = 7
	s.content_margin_bottom = 7
	return s

static func style_button(b: Button, accent: Color, filled := false) -> void:
	## Per-button accent (primary actions, selections). Filled variant reads
	## as "active location" and can't be confused with hover (border-only).
	var n := _btn_box(accent.darkened(0.35))
	if filled:
		n.bg_color = Color(accent.r * 0.3, accent.g * 0.3, accent.b * 0.3, 0.96)
	b.add_theme_stylebox_override("normal", n)
	b.add_theme_stylebox_override("hover", _btn_box(accent))
	b.add_theme_stylebox_override("pressed", _btn_box(PINK))
	b.add_theme_color_override("font_hover_color", Color.WHITE)

static func panel(border: Color, bg := PANEL_BG) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(6)
	s.content_margin_left = 14
	s.content_margin_right = 14
	s.content_margin_top = 10
	s.content_margin_bottom = 10
	s.shadow_color = Color(border.r, border.g, border.b, 0.25)
	s.shadow_size = 6
	return s

static func header(text: String, color: Color, size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.add_theme_color_override("font_shadow_color", Color(color.r, color.g, color.b, 0.8))
	l.add_theme_constant_override("shadow_offset_x", 2)
	l.add_theme_constant_override("shadow_offset_y", 2)
	return l

static func section(title: String, accent: Color) -> HBoxContainer:
	## Accent-bar section header row.
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var bar := ColorRect.new()
	bar.color = accent
	bar.custom_minimum_size = Vector2(4, 22)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(bar)
	h.add_child(header(title, accent, 17))
	return h

static func body(text: String, size := 13, color := TEXT) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

static func rarity_color(rarity: String) -> Color:
	return GameDB.RARITY_COLORS.get(rarity, Color.WHITE)
