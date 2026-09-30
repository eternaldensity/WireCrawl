extends Node
## Main — game shell: input bootstrap, screen flow
## TITLE (origin + contract + programs + cyberware shop) → DUNGEON → DEBRIEF.
## Pause menu, death/victory screens. All UI built in code, neon-styled.

var screen: Control
var dungeon: WCDungeon = null
var hud: WCHUD = null
var sel_origin := "solo"
var sel_contract := 0
var sel_prog1 := "ice_turret"
var sel_prog2 := "blackout"
var paused := false

const NEON_PINK := Color(1.0, 0.16, 0.43)
const NEON_CYAN := Color(0.02, 0.85, 0.91)
const NEON_YELLOW := Color(0.976, 0.941, 0.008)
const BG := Color(0.015, 0.015, 0.035)

func _ready() -> void:
	_ensure_input()
	_apply_volumes()
	show_title()

func _ensure_input() -> void:
	_add_key("move_fwd", [KEY_W, KEY_UP])
	_add_key("move_back", [KEY_S, KEY_DOWN])
	_add_key("move_left", [KEY_A, KEY_LEFT])
	_add_key("move_right", [KEY_D, KEY_RIGHT])
	_add_key("dash", [KEY_SPACE, KEY_SHIFT])
	_add_key("program_1", [KEY_Q])
	_add_key("program_2", [KEY_E])
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		if not InputMap.action_has_event("fire", mb):
			InputMap.action_add_event("fire", mb)
	if not InputMap.has_action("pause"):
		InputMap.add_action("pause")
		var k := InputEventKey.new()
		k.physical_keycode = KEY_ESCAPE
		InputMap.action_add_event("pause", k)

func _add_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for kc in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = kc
		var exists := false
		for e in InputMap.action_get_events(action):
			if e is InputEventKey and (e as InputEventKey).physical_keycode == kc:
				exists = true
		if not exists:
			InputMap.action_add_event(action, ev)

func _apply_volumes() -> void:
	var s: Dictionary = SaveSystem.profile.get("settings", {})
	AudioDirector.set_volumes(float(s.get("master_vol", 0.8)),
		float(s.get("music_vol", 0.6)), float(s.get("sfx_vol", 0.9)))

func _clear() -> void:
	if dungeon != null:
		dungeon.queue_free()
		dungeon = null
	if hud != null:
		hud.queue_free()
		hud = null
	if screen != null:
		screen.queue_free()
		screen = null
	get_tree().paused = false
	paused = false

# ================= TITLE =================
func show_title() -> void:
	_clear()
	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)
	_rain_lines(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 36)
	margin.add_theme_constant_override("margin_right", 36)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	screen.add_child(margin)
	var root := HBoxContainer.new()
	root.add_theme_constant_override("separation", 28)
	margin.add_child(root)
	var left := VBoxContainer.new()
	left.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	left.add_theme_constant_override("separation", 10)
	root.add_child(left)
	var title := Label.new()
	title.text = "WIRECRAWL"
	title.add_theme_font_size_override("font_size", 72)
	title.add_theme_color_override("font_color", NEON_PINK)
	left.add_child(title)
	var sub := Label.new()
	sub.text = "NEON ABYSS — a cyberpunk dungeon-crawler"
	sub.add_theme_font_size_override("font_size", 18)
	sub.add_theme_color_override("font_color", NEON_CYAN)
	left.add_child(sub)
	left.add_child(_label("— CHOOSE YOUR RIG —", NEON_YELLOW, 16))
	var orig_row := HBoxContainer.new()
	orig_row.add_theme_constant_override("separation", 10)
	left.add_child(orig_row)
	for oid in ["solo", "netrunner", "techie"]:
		orig_row.add_child(_origin_card(oid))
	left.add_child(_label("— CONTRACT (threat scales loot + danger) —", NEON_YELLOW, 16))
	var unlocked: int = int(SaveSystem.profile.get("contracts_unlocked", 1))
	for i in GameDB.CONTRACTS.size():
		var c: Dictionary = GameDB.CONTRACTS[i]
		left.add_child(_contract_row(i, c, i < unlocked))
	left.add_child(_label("— PROGRAMS (Q / E slots) —", NEON_YELLOW, 16))
	var prog_row := HBoxContainer.new()
	prog_row.add_theme_constant_override("separation", 8)
	left.add_child(prog_row)
	prog_row.add_child(_program_picker(1))
	prog_row.add_child(_program_picker(2))
	var right := VBoxContainer.new()
	right.custom_minimum_size = Vector2(330, 0)
	right.add_theme_constant_override("separation", 10)
	root.add_child(right)
	right.add_child(_label("— PROFILE —", NEON_CYAN, 16))
	right.add_child(_profile_panel())
	right.add_child(_label("— CYBERWARE (persistent) —", NEON_CYAN, 16))
	for track in ["muscle", "ice", "ghost"]:
		right.add_child(_cyberware_row(track))
	var launch := Button.new()
	launch.text = "▶ JACK IN"
	launch.custom_minimum_size = Vector2(0, 56)
	launch.add_theme_font_size_override("font_size", 24)
	right.add_child(launch)
	launch.pressed.connect(func():
		AudioDirector.play("ui")
		start_dungeon())
	var hint := _label("WASD move · mouse aim · LMB fire · SPACE dash · Q/E programs · ESC pause", Color(0.55, 0.6, 0.75), 12)
	right.add_child(hint)

func _label(t: String, c: Color, fs: int) -> Label:
	var l := Label.new()
	l.text = t
	l.add_theme_font_size_override("font_size", fs)
	l.add_theme_color_override("font_color", c)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return l

func _panel(border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	var s := StyleBoxFlat.new()
	s.bg_color = Color(0.03, 0.03, 0.07, 0.95)
	s.border_color = border
	s.set_border_width_all(1)
	s.set_corner_radius_all(4)
	s.content_margin_left = 10
	s.content_margin_right = 10
	s.content_margin_top = 8
	s.content_margin_bottom = 8
	p.add_theme_stylebox_override("panel", s)
	return p

func _origin_card(oid: String) -> Control:
	var o: Dictionary = GameDB.ORIGINS[oid]
	var p := _panel(o["color"] if sel_origin != oid else Color.WHITE)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	p.add_child(v)
	var name := _label("%s  Lv%d" % [o["name"], SaveSystem.origin_level(oid)], o["color"], 16)
	v.add_child(name)
	var d := _label(o["desc"], Color(0.75, 0.78, 0.9), 12)
	v.add_child(d)
	var b := Button.new()
	b.text = "SELECT" if sel_origin != oid else "✓ ACTIVE"
	v.add_child(b)
	b.pressed.connect(func():
		sel_origin = oid
		AudioDirector.play("ui")
		show_title())
	return p

func _contract_row(i: int, c: Dictionary, open: bool) -> Control:
	var p := _panel(NEON_CYAN if sel_contract != i else Color.WHITE)
	var h := HBoxContainer.new()
	p.add_child(h)
	var t := _label(("%d. %s  [THREAT %d] — %s" % [i + 1, c["name"], c["threat"], c["desc"]]
		+ ("  (reward %dcr)" % c["reward"]) if open else "%d. ▓▓▓ LOCKED — clear previous contract" % [i + 1]),
		Color(0.85, 0.88, 1.0) if open else Color(0.4, 0.4, 0.5), 13)
	t.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(t)
	if open:
		var b := Button.new()
		b.text = "✓" if sel_contract == i else "GO"
		h.add_child(b)
		b.pressed.connect(func():
			sel_contract = i
			AudioDirector.play("ui")
			show_title())
	return p

func _program_picker(slot: int) -> Control:
	var p := _panel(NEON_PINK)
	p.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("SLOT %s" % ("Q" if slot == 1 else "E"), NEON_PINK, 13))
	var cur: String = sel_prog1 if slot == 1 else sel_prog2
	var opt := OptionButton.new()
	for pid in ["ice_turret", "blackout", "overdrive", "hound", "system_shock"]:
		opt.add_item("%s %s" % [GameDB.PROGRAMS[pid]["icon"], GameDB.PROGRAMS[pid]["name"]])
		if pid == cur:
			opt.select(opt.item_count - 1)
	v.add_child(opt)
	var desc := _label(GameDB.PROGRAMS[cur]["desc"], Color(0.7, 0.75, 0.9), 11)
	v.add_child(desc)
	opt.item_selected.connect(func(idx: int):
		var ids := ["ice_turret", "blackout", "overdrive", "hound", "system_shock"]
		if slot == 1:
			sel_prog1 = ids[idx]
		else:
			sel_prog2 = ids[idx]
		AudioDirector.play("ui")
		show_title())
	return p

func _profile_panel() -> Control:
	var p := _panel(NEON_YELLOW)
	var v := VBoxContainer.new()
	p.add_child(v)
	v.add_child(_label("Credits: %dcr" % int(SaveSystem.profile.get("credits", 0)), NEON_YELLOW, 15))
	var lv := "Levels — Solo %d · Net %d · Tech %d" % [
		SaveSystem.origin_level("solo"), SaveSystem.origin_level("netrunner"), SaveSystem.origin_level("techie")]
	v.add_child(_label(lv, Color(0.8, 0.82, 0.95), 12))
	v.add_child(_label("Runs %d · Kills %d · Best threat %d" % [
		int(SaveSystem.profile.get("runs", 0)), int(SaveSystem.profile.get("kills", 0)),
		int(SaveSystem.profile.get("best_threat", 0))], Color(0.7, 0.72, 0.85), 12))
	return p

func _cyberware_row(track: String) -> Control:
	var p := _panel(GameDB.CYBERWARE_TRACKS[track]["color"])
	var v := VBoxContainer.new()
	p.add_child(v)
	var lvl: int = int(SaveSystem.profile.get("cyberware", {}).get(track, 0))
	v.add_child(_label("%s  %d/5" % [GameDB.CYBERWARE_TRACKS[track]["name"], lvl],
		GameDB.CYBERWARE_TRACKS[track]["color"], 13))
	if lvl < 5:
		v.add_child(_label("Next: " + GameDB.CYBERWARE_TRACKS[track]["per_level"][lvl], Color(0.75, 0.78, 0.9), 11))
		var b := Button.new()
		b.text = "INSTALL — %dcr" % (200 + lvl * 350)
		v.add_child(b)
		b.pressed.connect(func():
			if SaveSystem.buy_cyberware(track):
				AudioDirector.play("levelup")
			else:
				AudioDirector.play("hurt", 0.8)
			show_title())
	else:
		v.add_child(_label("MAXED", NEON_YELLOW, 11))
	return p

func _rain_lines(parent: Control) -> void:
	# subtle animated scanline overlay (cheap cyberpunk vibe)
	var lines := ColorRect.new()
	lines.color = Color(0.02, 0.85, 0.91, 0.03)
	lines.set_anchors_preset(Control.PRESET_FULL_RECT)
	lines.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lines)

# ================= DUNGEON =================
func start_dungeon() -> void:
	_clear()
	var c: Dictionary = GameDB.CONTRACTS[clampi(sel_contract, 0, GameDB.CONTRACTS.size() - 1)]
	var starter := LootFactory.roll_weapon(int(c["threat"]), 0.0, GameDB.ORIGINS[sel_origin]["weapon"], "common")
	var armor := [LootFactory.roll_armor(1, 0.0)]
	var progs: Array = [sel_prog1, sel_prog2, "blink"]
	RunManager.start_run(sel_origin, c, starter, armor, progs)
	dungeon = WCDungeon.new()
	dungeon.setup(c)  # must run before add_child: _ready builds from layout
	add_child(dungeon)
	# Dungeon._ready builds on add; wire signals deferred
	call_deferred("_wire_dungeon")

func _wire_dungeon() -> void:
	if dungeon == null:
		return
	hud = WCHUD.new()
	add_child(hud)
	hud.dungeon = dungeon
	hud.obj_label.text = "◈ Reach the EXIT uplink — clear rooms for loot"
	dungeon.loot_offered.connect(func(item): hud._on_loot(item))
	dungeon.extraction_ready.connect(func(): hud.announce("EXTRACT — HEAD TO THE GREEN BEAM", Color(0.3, 1.0, 0.5)))
	if not RunManager.run_ended.is_connected(_on_run_ended):
		RunManager.run_ended.connect(_on_run_ended)
	hud.announce(String(GameDB.CONTRACTS[clampi(sel_contract, 0, 5)]["name"]) + " — " +
		String(GameDB.CONTRACTS[clampi(sel_contract, 0, 5)]["sector"]), NEON_CYAN)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("pause") and dungeon != null:
		toggle_pause()

func toggle_pause() -> void:
	paused = not paused
	get_tree().paused = paused
	if paused:
		var dim := ColorRect.new()
		dim.name = "PauseDim"
		dim.color = Color(0, 0, 0, 0.7)
		dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		hud.add_child(dim)
		var box := _panel(NEON_CYAN)
		box.set_anchors_preset(Control.PRESET_CENTER)
		box.position = Vector2(-200, -140)
		box.custom_minimum_size = Vector2(400, 280)
		box.name = "PauseBox"
		dim.add_child(box)
		var v := VBoxContainer.new()
		v.add_theme_constant_override("separation", 8)
		box.add_child(v)
		v.add_child(_label("‖ PAUSED", NEON_CYAN, 28))
		var resume := Button.new()
		resume.text = "RESUME"
		v.add_child(resume)
		resume.pressed.connect(toggle_pause)
		var abandon := Button.new()
		abandon.text = "ABANDON RUN (keep loot, no reward)"
		v.add_child(abandon)
		abandon.pressed.connect(func():
			RunManager.end_run(false))
		var quit := Button.new()
		quit.text = "QUIT TO TITLE"
		v.add_child(quit)
		quit.pressed.connect(func(): show_title())
	else:
		for c in hud.get_children():
			if c.name == "PauseDim":
				c.queue_free()

func _on_run_ended(victory: bool, summary: Dictionary) -> void:
	call_deferred("_show_debrief", victory, summary)

func _show_debrief(victory: bool, summary: Dictionary) -> void:
	get_tree().paused = false
	paused = false
	if dungeon != null:
		dungeon.queue_free()
		dungeon = null
	if hud != null:
		hud.queue_free()
		hud = null
	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(screen)
	var bg := ColorRect.new()
	bg.color = Color(0.01, 0.01, 0.03, 0.92)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(center)
	var box := _panel(NEON_YELLOW if victory else NEON_PINK)
	box.custom_minimum_size = Vector2(560, 0)
	center.add_child(box)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	box.add_child(v)
	v.add_child(_label("★ CONTRACT COMPLETE ★" if victory else "✕ FLATLINED ✕",
		NEON_YELLOW if victory else NEON_PINK, 34))
	v.add_child(_label("Kills %d · XP %d · Credits +%d · Drops %d · +%d level(s) → Lv%d" % [
		summary.get("kills", 0), summary.get("xp", 0), summary.get("credits", 0),
		summary.get("loot", 0), summary.get("levels_gained", 0), summary.get("new_level", 1)],
		Color(0.85, 0.88, 1.0), 14))
	v.add_child(_label("— TOP LOOT —", NEON_CYAN, 14))
	var loot: Array = RunManager.loot_earned
	loot.sort_custom(func(a, b): return float(a.get("dps", 0)) > float(b.get("dps", 0)))
	for i in mini(5, loot.size()):
		var it: Dictionary = loot[i]
		v.add_child(_label("◈ %s (%s, %.0f dps)" % [it.get("name", "?"), it.get("rarity", "?"), float(it.get("dps", 0))],
			GameDB.RARITY_COLORS.get(String(it.get("rarity", "common")), Color.WHITE), 13))
	var again := Button.new()
	again.text = "↻ JACK IN AGAIN"
	v.add_child(again)
	again.pressed.connect(func(): start_dungeon())
	var back := Button.new()
	back.text = "SAFEHOUSE"
	v.add_child(back)
	back.pressed.connect(func(): show_title())
