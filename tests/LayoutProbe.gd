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
	await _test_clicks(main_scene)
	print("---- PROBE DONE: %d passed, %d failed ----" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)

var passes := 0
var failures := 0

func _nav_check(cond: bool, name: String, extra := "") -> void:
	if cond:
		passes += 1
		print("PASS  %s %s" % [name, extra])
	else:
		failures += 1
		printerr("FAIL  %s %s" % [name, extra])

func _find_button(n: Node) -> Button:
	if n is Button:
		return n as Button
	for ch in n.get_children():
		var b := _find_button(ch)
		if b != null:
			return b
	return null

func _test_clicks(main_scene: Node) -> void:
	## Every rail button must route to its own tab; GO buttons to own contract.
	var ids := ["deploy", "chrome", "profile", "settings"]
	var btns: Array = []
	for ch in main_scene.rail_box.get_children():
		if ch is Button:
			btns.append(ch)
	_nav_check(btns.size() == 4, "nav_count", "(%d)" % btns.size())
	for k in mini(4, btns.size()):
		(btns[k] as Button).pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_nav_check(main_scene.tab == ids[k], "nav_%s" % ids[k], "(tab=%s)" % main_scene.tab)
		var first: Control = main_scene.tab_content.get_child(0)
		_nav_check(int(first.get_global_rect().position.y) == int(main_scene.tab_scroll.get_global_rect().position.y),
			"nav_top_%s" % ids[k], "(content starts at scroll origin)")
		btns.clear()
		for ch in main_scene.rail_box.get_children():
			if ch is Button:
				btns.append(ch)
	# Contract GO routing with in-memory unlock (no save written).
	main_scene.tab = "deploy"
	var prev_unlock: int = int(SaveSystem.profile.get("contracts_unlocked", 1))
	SaveSystem.profile["contracts_unlocked"] = 6
	main_scene._refresh_title()
	await get_tree().process_frame
	var gos: Array = []
	for row in main_scene.tab_content.get_children():
		var b := _find_button(row)
		if b != null and b.text == "GO":
			gos.append(b)
	_nav_check(gos.size() == 5, "contract_go_count", "(%d)" % gos.size())
	if gos.size() >= 2:
		(gos[1] as Button).pressed.emit()
		await get_tree().process_frame
		await get_tree().process_frame
		_nav_check(main_scene.sel_contract == 2, "contract_go_routes",
			"(sel=%d)" % main_scene.sel_contract)
	SaveSystem.profile["contracts_unlocked"] = prev_unlock
	main_scene._refresh_title()
	await get_tree().process_frame

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
