class_name WCTheme
extends RefCounted
## Shared neon UI theme. Build once via make_theme() and assign to root
## Controls; use panel()/header()/section() helpers for consistent styling.
## Fixes: plain default Godot widgets, unreadable low-contrast rows.

static var _cached: Theme = null
static var _tex_cache := {}

const PINK := Color(1.0, 0.16, 0.43)
const CYAN := Color(0.02, 0.85, 0.91)
const YELLOW := Color(0.976, 0.941, 0.008)
const INK := Color(0.015, 0.015, 0.035)
const PANEL_BG := Color(0.03, 0.035, 0.08, 0.94)
const TEXT := Color(0.86, 0.89, 1.0)
const DIM := Color(0.55, 0.6, 0.75)

static func _paint(accent: Color, w: int, h: int, cut: int, glow_px: int, filled: bool) -> ImageTexture:
	## Bakes one angular panel/button face: cut corners, neon edge + glow,
	## chrome top sheen, faint circuit traces + node pads.
	var img := Image.create(w, h, false, Image.FORMAT_RGBA8)
	var fy := float(h)
	for y in h:
		for x in w:
			# 45-degree cut corners -> transparent
			var cx: float = minf(float(x), float(w - 1 - x))
			var cy: float = minf(float(y), float(h - 1 - y))
			if cx + cy < float(cut):
				img.set_pixel(x, y, Color(0, 0, 0, 0))
				continue
			var edge: float = minf(minf(float(x), float(w - 1 - x)), minf(float(y), float(h - 1 - y)))
			var col := Color(0.028, 0.032, 0.075, 0.96)
			if filled:
				col = col.lerp(Color(accent.r * 0.35, accent.g * 0.35, accent.b * 0.35, 0.96), 0.55)
			# chrome sheen from the top edge (vertical only: stretch-safe)
			var sheen: float = clampf(1.0 - float(y) / (fy * 0.15), 0.0, 1.0) * 0.07
			col.r += sheen
			col.g += sheen
			col.b += sheen
			# corner-zone circuits only (stretched middles stay clean dark)
			var tr := 0.0
			for zone_x in [10.0, float(w) - 10.0]:
				var dx: float = absf(float(x) - zone_x)
				if dx < 22.0:
					for ly in [fy * 0.32, fy * 0.68]:
						var in_seg: bool = (zone_x < float(w) * 0.5 and float(x) >= zone_x - 4.0 and float(x) <= zone_x + 12.0) or (zone_x >= float(w) * 0.5 and float(x) <= zone_x + 4.0 and float(x) >= zone_x - 12.0)
						if absf(float(y) - ly) < 1.0 and in_seg:
							tr = 0.6
					if dx < 1.0 and float(y) > fy * 0.2 and float(y) < fy * 0.8:
						tr = 0.6
			var pad := 0.0
			for p in [Vector2(14, fy * 0.32), Vector2(14, fy * 0.68), Vector2(float(w) - 14, fy * 0.32), Vector2(float(w) - 14, fy * 0.68)]:
				if Vector2(float(x), float(y)).distance_to(p) < 2.4:
					pad = 1.0
			col.r += accent.r * (tr * 0.12 + pad * 0.4)
			col.g += accent.g * (tr * 0.12 + pad * 0.4)
			col.b += accent.b * (tr * 0.12 + pad * 0.4)
			# slim neon edge + short outer glow falloff
			if edge < 2.0:
				col = Color(accent.r, accent.g, accent.b, 1.0)
			elif edge < 2.0 + float(glow_px):
				var g: float = 1.0 - (edge - 2.0) / float(glow_px)
				col.r += accent.r * g * 0.4
				col.g += accent.g * g * 0.4
				col.b += accent.b * g * 0.4
			img.set_pixel(x, y, col)
	return ImageTexture.create_from_image(img)

static func _tex(accent: Color, kind: String, state: String) -> StyleBoxTexture:
	var key := "%s_%s_%s" % [accent.to_html(false), kind, state]
	if _tex_cache.has(key):
		return _tex_cache[key]
	var w := 96
	var h := 96
	var cut := 12
	var glow := 4
	if kind == "btn":
		w = 64
		h = 32
		cut = 7
		glow = 3
	var a := accent
	if state == "hover":
		a = accent.lightened(0.35)
	elif state == "pressed":
		a = PINK.lightened(0.1)
	elif state == "disabled":
		a = Color(0.3, 0.3, 0.35)
	var tex := _paint(a, w, h, cut, glow, state == "pressed" or state == "active")
	var sb := StyleBoxTexture.new()
	sb.texture = tex
	sb.expand_margin_left = cut
	sb.expand_margin_top = cut
	sb.expand_margin_right = cut
	sb.expand_margin_bottom = cut
	if kind == "btn":
		sb.content_margin_left = 12
		sb.content_margin_right = 12
		sb.content_margin_top = 7
		sb.content_margin_bottom = 7
	else:
		sb.content_margin_left = 14
		sb.content_margin_right = 14
		sb.content_margin_top = 10
		sb.content_margin_bottom = 10
	_tex_cache[key] = sb
	return sb

static func make_theme() -> Theme:
	if _cached != null:
		return _cached
	var t := Theme.new()
	# Buttons (default cyan accent; per-button accents via style_button()).
	t.set_stylebox("normal", "Button", _tex(CYAN.darkened(0.2), "btn", "normal"))
	t.set_stylebox("hover", "Button", _tex(CYAN, "btn", "hover"))
	t.set_stylebox("pressed", "Button", _tex(PINK, "btn", "pressed"))
	t.set_stylebox("disabled", "Button", _tex(Color(0.25, 0.25, 0.3), "btn", "disabled"))
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

static func style_button(b: Button, accent: Color, filled := false) -> void:
	## Per-button accent (primary actions, selections). Filled variant reads
	## as "active location" and can't be confused with hover (border-only).
	b.add_theme_stylebox_override("normal", _tex(accent.darkened(0.2), "btn", "active" if filled else "normal"))
	b.add_theme_stylebox_override("hover", _tex(accent, "btn", "hover"))
	b.add_theme_stylebox_override("pressed", _tex(PINK, "btn", "pressed"))
	b.add_theme_color_override("font_hover_color", Color.WHITE)

static func panel(border: Color, bg := PANEL_BG) -> StyleBoxTexture:
	return _tex(border, "panel", "normal")

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
