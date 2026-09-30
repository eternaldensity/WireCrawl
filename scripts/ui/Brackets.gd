class_name WCBrackets
extends Control
## Cyberpunk corner-bracket frame: neon L-corners overlaid on a panel.
## Full-rect overlay, mouse-transparent. Attach to PanelContainers.

var color := Color(0.02, 0.85, 0.91)
var arm := 18.0
var width := 2.5

static func attach_to(panel: Control, col: Color) -> WCBrackets:
	var b := WCBrackets.new()
	b.color = col
	b.set_anchors_preset(Control.PRESET_FULL_RECT)
	b.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(b)
	# ensure overlay draws above panel content
	panel.move_child(b, panel.get_child_count() - 1)
	return b

func _draw() -> void:
	var r := Rect2(Vector2(3, 3), size - Vector2(6, 6))
	var c := color
	draw_line(r.position, r.position + Vector2(arm, 0), c, width)
	draw_line(r.position, r.position + Vector2(0, arm), c, width)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x - arm, r.position.y), c, width)
	draw_line(Vector2(r.end.x, r.position.y), Vector2(r.end.x, r.position.y + arm), c, width)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x + arm, r.end.y), c, width)
	draw_line(Vector2(r.position.x, r.end.y), Vector2(r.position.x, r.end.y - arm), c, width)
	draw_line(r.end, r.end - Vector2(arm, 0), c, width)
	draw_line(r.end, r.end - Vector2(0, arm), c, width)

func _notification(what: int) -> void:
	if what == NOTIFICATION_RESIZED:
		queue_redraw()
