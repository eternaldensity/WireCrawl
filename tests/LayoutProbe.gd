extends Node
## LayoutProbe — headless layout dump (scene mode so autoloads exist):
##   godot --headless --path . res://tests/LayoutProbe.tscn
## Instantiates Main.tscn, walks Control rects for each title tab, and flags
## zero-area / off-screen / overflow anomalies. Container layout runs fully
## under the dummy rasterizer, so rects are meaningful.

func _ready() -> void:
	var vp := get_viewport().get_visible_rect().size
	print("PROBE viewport=%s" % str(vp))
	var main_scene: Node = load("res://scenes/Main.tscn").instantiate()
	add_child(main_scene)
	for _i in 3:
		await get_tree().process_frame
	for t in ["deploy", "chrome", "profile", "settings"]:
		main_scene.tab = t
		main_scene._refresh_title()
		for _i in 3:
			await get_tree().process_frame
		_dump_tab(main_scene, t, vp)
	print("---- PROBE DONE ----")
	get_tree().quit()

func _dump_tab(main_scene: Node, tab: String, vp: Vector2) -> void:
	print("== TAB %s ==" % tab)
	var screen: Control = main_scene.screen
	_walk(screen, 0, vp)

func _walk(c: Node, depth: int, vp: Vector2) -> void:
	if not (c is Control):
		for ch in c.get_children():
			_walk(ch, depth, vp)
		return
	var cc := c as Control
	var r := cc.get_global_rect()
	var label := ""
	if c is Label:
		label = ("'%s'" % (c as Label).text.left(28).replace("\n", "\\n"))
	elif c is Button:
		label = ("[%s]" % (c as Button).text.left(24))
	elif c is OptionButton:
		label = "(OptionButton)"
	var flags := ""
	if r.size.x <= 0.0 or r.size.y <= 0.0:
		flags += " ZERO-AREA"
	if r.position.x < -1.0 or r.position.y < -1.0:
		flags += " NEG-OFF"
	if r.end.x > vp.x + 1.0 or r.end.y > vp.y + 1.0:
		flags += " OVERFLOW-VP"
	var vis := "" if cc.visible else " HIDDEN"
	var pad := ""
	for _i in depth:
		pad += "  "
	print("%s%s r=(%d,%d %dx%d)%s%s %s" % [pad, c.get_class(),
		int(r.position.x), int(r.position.y), int(r.size.x), int(r.size.y),
		vis, flags, label])
	for ch in cc.get_children():
		_walk(ch, depth + 1, vp)
