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
	_add_key("equip_1", [KEY_1])
	_add_key("equip_2", [KEY_2])
	if not InputMap.has_action("swap_weapon"):
		InputMap.add_action("swap_weapon")
		var tab := InputEventKey.new()
		tab.physical_keycode = KEY_TAB
		InputMap.action_add_event("swap_weapon", tab)
		for wheel in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			var mbw := InputEventMouseButton.new()
			mbw.button_index = wheel
			InputMap.action_add_event("swap_weapon", mbw)
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
var tab := "deploy"
var rail_box: VBoxContainer
var tab_content: VBoxContainer

func show_title() -> void:
	_clear()
	screen = Control.new()
	screen.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.theme = WCTheme.make_theme()
	add_child(screen)
	var bg := ColorRect.new()
	bg.color = BG
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	screen.add_child(bg)
	_data_rain(bg)
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 32)
	margin.add_theme_constant_override("margin_right", 32)
	margin.add_theme_constant_override("margin_top", 18)
	margin.add_theme_constant_override("margin_bottom", 18)
	screen.add_child(margin)
	var shell := VBoxContainer.new()
	shell.add_theme_constant_override("separation", 12)
	margin.add_child(shell)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	shell.add_child(head)
	head.add_child(WCTheme.header("WIRECRAWL", NEON_PINK, 46))
	var sub := WCTheme.body("NEON ABYSS — a cyberpunk dungeon-crawler", 17, NEON_CYAN)
	sub.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	head.add_child(sub)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 20)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shell.add_child(body)
	rail_box = VBoxContainer.new()
	rail_box.custom_minimum_size = Vector2(250, 0)
	rail_box.add_theme_constant_override("separation", 8)
	body.add_child(rail_box)
	var scroll := ScrollContainer.new()
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	body.add_child(scroll)
	tab_content = VBoxContainer.new()
	tab_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tab_content.add_theme_constant_override("separation", 12)
	scroll.add_child(tab_content)
	_refresh_title()

func _refresh_title() -> void:
	if screen == null:
		return
	_render_rail()
	_render_tab()

func _render_rail() -> void:
	for c in rail_box.get_children():
		c.queue_free()
	var tabs := [["deploy", "▸ DEPLOY", NEON_PINK], ["chrome", "▸ CHROME", NEON_YELLOW],
		["profile", "▸ PROFILE", NEON_CYAN], ["settings", "▸ SETTINGS", Color(0.6, 0.65, 0.9)]]
	for t in tabs:
		var b := Button.new()
		b.text = String(t[1]) if tab != String(t[0]) else "▶ " + String(t[1]).substr(2)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if tab == String(t[0]):
			WCTheme.style_button(b, t[2])
			b.disabled = true
		var id := String(t[0])
		b.pressed.connect(func():
			tab = id
			AudioDirector.play("ui")
			_refresh_title())
		rail_box.add_child(b)
	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	rail_box.add_child(spacer)
	var cred := PanelContainer.new()
	cred.add_theme_stylebox_override("panel", WCTheme.panel(NEON_YELLOW))
	rail_box.add_child(cred)
	var cv := VBoxContainer.new()
	cred.add_child(cv)
	cv.add_child(WCTheme.body("CREDITS", 12, NEON_YELLOW))
	cv.add_child(WCTheme.header("%d cr" % int(SaveSystem.profile.get("credits", 0)), NEON_YELLOW, 24))
	rail_box.add_child(WCTheme.body("v%s · Godot 4.7" % GameDB.VERSION, 11, WCTheme.DIM))

func _render_tab() -> void:
	for c in tab_content.get_children():
		c.queue_free()
	match tab:
		"deploy":
			_tab_deploy()
		"chrome":
			_tab_chrome()
		"profile":
			_tab_profile()
		"settings":
			_tab_settings()

func _tab_deploy() -> void:
	tab_content.add_child(WCTheme.section("CHOOSE YOUR RIG", NEON_YELLOW))
	var orig_row := HBoxContainer.new()
	orig_row.add_theme_constant_override("separation", 10)
	tab_content.add_child(orig_row)
	for oid in ["solo", "netrunner", "techie"]:
		orig_row.add_child(_origin_card(oid))
	tab_content.add_child(WCTheme.section("CONTRACT — threat scales loot + danger", NEON_YELLOW))
	var unlocked: int = int(SaveSystem.profile.get("contracts_unlocked", 1))
	for i in GameDB.CONTRACTS.size():
		var c: Dictionary = GameDB.CONTRACTS[i]
		tab_content.add_child(_contract_row(i, c, i < unlocked))
	tab_content.add_child(WCTheme.section("PROGRAMS — Q / E slots", NEON_YELLOW))
	var prog_row := HBoxContainer.new()
	prog_row.add_theme_constant_override("separation", 8)
	tab_content.add_child(prog_row)
	prog_row.add_child(_program_picker(1))
	prog_row.add_child(_program_picker(2))
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", WCTheme.panel(NEON_PINK))
	tab_content.add_child(bar)
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 16)
	bar.add_child(h)
	var c0: Dictionary = GameDB.CONTRACTS[clampi(sel_contract, 0, 5)]
	var summary := WCTheme.body("Run: %s · %s · Threat %d · %s / %s" % [
		GameDB.ORIGINS[sel_origin]["name"], c0["name"], c0["threat"],
		GameDB.PROGRAMS[sel_prog1]["name"], GameDB.PROGRAMS[sel_prog2]["name"]], 15)
	summary.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	summary.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	h.add_child(summary)
	var launch := Button.new()
	launch.text = "▶ JACK IN"
	launch.custom_minimum_size = Vector2(280, 60)
	launch.add_theme_font_size_override("font_size", 26)
	WCTheme.style_button(launch, NEON_PINK)
	h.add_child(launch)
	launch.pressed.connect(func():
		AudioDirector.play("ui")
		start_dungeon())

func _tab_chrome() -> void:
	tab_content.add_child(WCTheme.section("CYBERWARE — permanent rig upgrades", NEON_YELLOW))
	tab_content.add_child(WCTheme.body("Installed chrome persists across runs. Earn credits by completing contracts.", 13, WCTheme.DIM))
	for track in ["muscle", "ice", "ghost"]:
		tab_content.add_child(_cyberware_row(track))

func _tab_profile() -> void:
	tab_content.add_child(WCTheme.section("PROFILE", NEON_CYAN))
	tab_content.add_child(_profile_panel())
	tab_content.add_child(WCTheme.section("RIG MASTERY", NEON_CYAN))
	for oid in ["solo", "netrunner", "techie"]:
		var o: Dictionary = GameDB.ORIGINS[oid]
		var p := PanelContainer.new()
		p.add_theme_stylebox_override("panel", WCTheme.panel(o["color"]))
		tab_content.add_child(p)
		var v := VBoxContainer.new()
		p.add_child(v)
		v.add_child(WCTheme.header("%s — Level %d" % [o["name"], SaveSystem.origin_level(oid)], o["color"], 18))
		var xp: int = int(SaveSystem.profile["origins"][oid].get("xp", 0))
		var need: int = GameDB.xp_for_level(SaveSystem.origin_level(oid))
		v.add_child(WCTheme.body("XP %d / %d to next level" % [xp, need], 12, WCTheme.DIM))

func _tab_settings() -> void:
	tab_content.add_child(WCTheme.section("AUDIO", NEON_CYAN))
	tab_content.add_child(_volume_row("master_vol", "Master"))
	tab_content.add_child(_volume_row("music_vol", "Music"))
	tab_content.add_child(_volume_row("sfx_vol", "SFX"))
	tab_content.add_child(WCTheme.section("GAMEPLAY", NEON_CYAN))
	var shake := CheckButton.new()
	shake.text = "Screen shake"
	shake.button_pressed = bool(SaveSystem.profile.get("settings", {}).get("screenshake", true))
	shake.add_theme_font_size_override("font_size", 14)
	tab_content.add_child(shake)
	shake.toggled.connect(func(on: bool):
		SaveSystem.profile["settings"]["screenshake"] = on
		SaveSystem.save_profile())
	tab_content.add_child(WCTheme.section("CONTROLS", NEON_CYAN))
	tab_content.add_child(WCTheme.body("WASD move · mouse aim · LMB fire · SPACE dash (i-frames) · TAB / wheel weapon swap · Q / E programs · 1 / 2 loot choice · ESC pause", 13))
	tab_content.add_child(WCTheme.section("DISPLAY", NEON_CYAN))
	tab_content.add_child(WCTheme.body("The game renders at your window size — maximize or fullscreen the window for higher fidelity. UI scales automatically (1080p base).", 13, WCTheme.DIM))

func _label(t: String, c: Color, fs: int) -> Label:
	return WCTheme.body(t, fs, c)

func _panel(border: Color) -> PanelContainer:
	var p := PanelContainer.new()
	p.add_theme_stylebox_override("panel", WCTheme.panel(border))
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
	if sel_origin == oid:
		WCTheme.style_button(b, o["color"])
	v.add_child(b)
	b.pressed.connect(func():
		sel_origin = oid
		AudioDirector.play("ui")
		_refresh_title())
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
			_refresh_title())
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
		_refresh_title())
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
			_refresh_title())
	else:
		v.add_child(_label("MAXED", NEON_YELLOW, 11))
	return p

func _volume_row(setting: String, title: String) -> Control:
	var h := HBoxContainer.new()
	var l := _label(title, Color(0.75, 0.78, 0.9), 12)
	l.custom_minimum_size = Vector2(60, 0)
	h.add_child(l)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.01
	slider.value = float(SaveSystem.profile.get("settings", {}).get(setting, 0.8))
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	h.add_child(slider)
	slider.value_changed.connect(func(v: float):
		SaveSystem.profile["settings"][setting] = v
		SaveSystem.save_profile()
		_apply_volumes())
	return h

func _data_rain(parent: Control) -> void:
	## Matrix-style falling glyph columns behind the title.
	_rain_lines(parent)
	var glyphs := ["01", "死", "電", "脳", ">><<", "##", "07", "夢", "AX", "99", "λ", "街"]
	var cols := [NEON_CYAN, NEON_PINK, NEON_YELLOW, Color(0.5, 1.0, 0.6)]
	for i in 30:
		var l := Label.new()
		var col: Color = cols[i % cols.size()]
		l.add_theme_font_size_override("font_size", 15)
		l.add_theme_color_override("font_color", col)
		l.modulate.a = randf_range(0.15, 0.5)
		l.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var x := randf_range(0.0, 1880.0)
		l.position = Vector2(x, randf_range(-900.0, 0.0))
		parent.add_child(l)
		_fall_loop(l, glyphs)

func _fall_loop(l: Label, glyphs: Array) -> void:
	if not is_instance_valid(l):
		return
	var lines := []
	for _i in randi_range(4, 10):
		lines.append(glyphs[randi() % glyphs.size()])
	l.text = "\n".join(lines)
	l.position.y = -320.0
	var tw := l.create_tween()
	tw.tween_property(l, "position:y", 1120.0, randf_range(5.0, 11.0))
	tw.tween_callback(func(): _fall_loop(l, glyphs))

func _rain_lines(parent: Control) -> void:
	# subtle animated scanline overlay (cheap cyberpunk vibe)
	var overlay := ColorRect.new()
	overlay.color = Color(0.02, 0.85, 0.91, 0.03)
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(overlay)

# ================= DUNGEON =================
func start_dungeon() -> void:
	_clear()
	var c: Dictionary = GameDB.CONTRACTS[clampi(sel_contract, 0, GameDB.CONTRACTS.size() - 1)]
	var starter := LootFactory.roll_weapon(int(c["threat"]), 0.0, GameDB.ORIGINS[sel_origin]["weapon"], "common")
	# Dual loadout: origin weapon + opposite-range sidearm (TAB/wheel swaps).
	var side_id := "katana"
	if GameDB.WEAPONS[starter["weapon_id"]]["slot"] == "melee":
		side_id = "smg"
	var sidearm := LootFactory.roll_weapon(1, 0.0, side_id, "common")
	var armor := [LootFactory.roll_armor(1, 0.0)]
	var progs: Array = [sel_prog1, sel_prog2, "blink"]
	RunManager.start_run(sel_origin, c, starter, sidearm, armor, progs)
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
	dungeon.loot_offered.connect(func(item):
		hud._on_loot(item)
		hud.show_loot(item))
	dungeon.boss_spawned.connect(func(boss_name: String):
		hud.announce("⚠ " + boss_name + " ⚠", Color(1.0, 0.16, 0.43)))
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
		dim.theme = WCTheme.make_theme()
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
	screen.theme = WCTheme.make_theme()
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
