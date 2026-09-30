class_name WCHUD
extends CanvasLayer
## In-run HUD: vitals, energy, threat/objective, kill + loot feed, minimap,
## program cooldown pips, boss bar, damage vignette, center announcements.

var hp_bar: ProgressBar
var en_bar: ProgressBar
var hp_label: Label
var obj_label: Label
var feed: RichTextLabel
var announce_label: Label
var minimap: Control
var boss_bar: ProgressBar
var boss_label: Label
var boss_box: Control
var heat_bar: ProgressBar
var stamina_bar: ProgressBar
var radial: RadialMag
var interact_label: Label
var _obj_base := "Reach the EXIT uplink"
var _obj_t := 0.0
var prog_labels: Array = []
var weapon_label: Label
var loot_panel: PanelContainer
var loot_rich: RichTextLabel
var loot_b1: Button
var loot_b2: Button
var pending_loot := {}
var loot_queue: Array = []
var loot_timer := 0.0
var vignette: ColorRect
var _feed_lines: Array = []
var _announce_t := 0.0
var dungeon: WCDungeon = null

func _ready() -> void:
	layer = 10
	_build()
	RunManager.hp_changed.connect(_on_hp)
	RunManager.energy_changed.connect(_on_en)
	RunManager.kill_confirmed.connect(_on_kill)
	RunManager.loot_dropped.connect(_on_loot)
	RunManager.objective_changed.connect(func(t): _obj_base = t)
	RunManager.leveled_up.connect(func(lv): announce("LEVEL UP — %d" % lv, Color(0.976, 0.941, 0.008)))

class RadialMag extends Control:
	## Segmented radial magazine: one arc segment per round, center count.
	var mag := 30
	var ammo := 30
	var reloading := false
	var col := Color(0.02, 0.85, 0.91)
	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5 - 4.0
		draw_circle(c, r + 2.0, Color(0.008, 0.008, 0.02, 0.9))
		var n := maxi(mag, 1)
		var low := ammo <= n / 4
		var pulse := 1.0
		if low and not reloading:
			pulse = 0.7 + 0.3 * sin(float(Time.get_ticks_msec()) / 150.0)
		var track := col.lerp(Color.WHITE, 0.15) if not low else Color(1.0, 0.25, 0.15)
		draw_arc(c, r, 0, TAU, 64, Color(track.r, track.g, track.b, 0.35), 2.0)
		for i in mini(mag, 40):
			var a0 := -PI * 0.5 + TAU * float(i) / float(n)
			var a1 := a0 + TAU / float(n) * 0.68
			var scol := Color(0.2, 0.22, 0.28, 0.9)
			if not reloading and i < ammo:
				var head := 1.0 - 0.45 * float(i) / float(maxi(n - 1, 1))
				var base := col.lerp(Color.WHITE, 0.3)
				if low:
					base = Color(1.0, 0.3, 0.2)
				scol = Color(base.r * head * pulse, base.g * head * pulse, base.b * head * pulse, 1.0)
			draw_arc(c, r - 4.0, a0, a1, 6, scol, 5.0)
		var f := get_theme_default_font()
		var txt := ".." if reloading else str(ammo)
		var ts := f.get_string_size(txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20)
		draw_string(f, c - Vector2(ts.x * 0.5, -ts.y * 0.35),
			txt, HORIZONTAL_ALIGNMENT_LEFT, -1, 20,
			Color(1.0, 0.65, 0.25) if reloading else Color.WHITE)
		var ts2 := f.get_string_size("RNDS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9)
		draw_string(f, c - Vector2(ts2.x * 0.5, -ts.y * 0.35 - 12.0),
			"RNDS", HORIZONTAL_ALIGNMENT_LEFT, -1, 9, Color(0.55, 0.6, 0.75))
		if reloading:
			var sa := fmod(float(Time.get_ticks_msec()) / 280.0, TAU)
			draw_arc(c, r - 4.0, sa, sa + 1.1, 12, Color.WHITE, 5.0)

func _style_bar(bar: ProgressBar, fill_col: Color) -> void:
	var bg := StyleBoxFlat.new()
	bg.bg_color = Color(0.015, 0.015, 0.03, 0.85)
	bg.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", bg)
	var fill := StyleBoxFlat.new()
	fill.bg_color = fill_col
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("fill", fill)

func _panel_style(border: Color) -> StyleBox:
	return WCTheme.panel(border, Color(0.02, 0.02, 0.05, 0.85))

func _build() -> void:
	# vignette
	vignette = ColorRect.new()
	vignette.color = Color(1, 0.1, 0.2, 0.0)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	# top-left vitals in a dark backing panel for readability over the floor
	var vital_box := PanelContainer.new()
	vital_box.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vital_box.position = Vector2(14, 12)
	var vb := StyleBoxFlat.new()
	vb.bg_color = Color(0.008, 0.008, 0.02, 0.78)
	vb.border_color = Color(0.35, 0.38, 0.5, 0.9)
	vb.set_border_width_all(1)
	vb.set_corner_radius_all(5)
	vb.content_margin_left = 10
	vb.content_margin_right = 10
	vb.content_margin_top = 8
	vb.content_margin_bottom = 8
	vital_box.add_theme_stylebox_override("panel", vb)
	add_child(vital_box)
	var vitals := VBoxContainer.new()
	vital_box.add_child(vitals)
	hp_label = Label.new()
	hp_label.add_theme_font_size_override("font_size", 15)
	vitals.add_child(hp_label)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(300, 16)
	hp_bar.show_percentage = false
	_style_bar(hp_bar, Color(1.0, 0.16, 0.43))
	vitals.add_child(hp_bar)
	en_bar = ProgressBar.new()
	en_bar.custom_minimum_size = Vector2(300, 9)
	en_bar.show_percentage = false
	_style_bar(en_bar, Color(0.02, 0.85, 0.91))
	vitals.add_child(en_bar)
	heat_bar = ProgressBar.new()
	heat_bar.custom_minimum_size = Vector2(300, 6)
	heat_bar.show_percentage = false
	heat_bar.max_value = 100.0
	heat_bar.value = 0.0
	_style_bar(heat_bar, Color(1.0, 0.55, 0.1))
	vitals.add_child(heat_bar)
	stamina_bar = ProgressBar.new()
	stamina_bar.custom_minimum_size = Vector2(300, 6)
	stamina_bar.show_percentage = false
	stamina_bar.max_value = 100.0
	stamina_bar.value = 100.0
	_style_bar(stamina_bar, Color(0.45, 1.0, 0.35))
	vitals.add_child(stamina_bar)
	radial = RadialMag.new()
	radial.custom_minimum_size = Vector2(76, 76)
	vitals.add_child(radial)
	obj_label = Label.new()
	obj_label.add_theme_font_size_override("font_size", 14)
	obj_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.6))
	vitals.add_child(obj_label)
	# programs row
	var progs := HBoxContainer.new()
	progs.add_theme_constant_override("separation", 6)
	vitals.add_child(progs)
	for i in 3:
		var l := Label.new()
		l.add_theme_font_size_override("font_size", 13)
		l.add_theme_color_override("font_color", Color(0.4, 0.95, 1.0))
		progs.add_child(l)
		prog_labels.append(l)
	weapon_label = Label.new()
	weapon_label.add_theme_font_size_override("font_size", 13)
	weapon_label.add_theme_color_override("font_color", Color(0.85, 0.88, 1.0))
	vitals.add_child(weapon_label)
	# top-right minimap + threat
	minimap = _Minimap.new()
	minimap.custom_minimum_size = Vector2(230, 230)
	minimap.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	minimap.position = Vector2(-244, 12)
	add_child(minimap)
	# boss bar top-center
	boss_box = VBoxContainer.new()
	boss_box.set_anchors_preset(Control.PRESET_CENTER_TOP)
	boss_box.position = Vector2(-260, 10)
	boss_box.custom_minimum_size = Vector2(520, 0)
	add_child(boss_box)
	boss_label = Label.new()
	boss_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	boss_label.add_theme_font_size_override("font_size", 16)
	boss_label.add_theme_color_override("font_color", Color(1.0, 0.2, 0.35))
	boss_box.add_child(boss_label)
	boss_bar = ProgressBar.new()
	boss_bar.show_percentage = false
	boss_box.add_child(boss_bar)
	boss_box.visible = false
	# feed bottom-left
	feed = RichTextLabel.new()
	feed.set_anchors_preset(Control.PRESET_BOTTOM_LEFT)
	feed.position = Vector2(14, -190)
	feed.custom_minimum_size = Vector2(430, 176)
	feed.bbcode_enabled = true
	feed.scroll_following = true
	feed.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(feed)
	interact_label = Label.new()
	interact_label.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	interact_label.position = Vector2(-200, -120)
	interact_label.custom_minimum_size = Vector2(400, 30)
	interact_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	interact_label.add_theme_font_size_override("font_size", 18)
	interact_label.add_theme_color_override("font_color", Color(0.976, 0.941, 0.008))
	interact_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(interact_label)
	# announce center
	announce_label = Label.new()
	announce_label.set_anchors_preset(Control.PRESET_CENTER)
	announce_label.position = Vector2(-300, -80)
	announce_label.custom_minimum_size = Vector2(600, 60)
	announce_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	announce_label.add_theme_font_size_override("font_size", 34)
	announce_label.add_theme_color_override("font_color", Color(1, 1, 1))
	announce_label.add_theme_color_override("font_shadow_color", Color(1.0, 0.16, 0.43))
	announce_label.add_theme_constant_override("shadow_offset_x", 2)
	announce_label.add_theme_constant_override("shadow_offset_y", 2)
	announce_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(announce_label)
	# controls hint bottom-right
	var hint := Label.new()
	hint.text = "WASD move (screen) · LMB fire · SPACE dash · TAB swap · R/RMB reload · Q/E programs · 1/2 loot · F hack"
	hint.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	hint.position = Vector2(-660, -30)
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.6, 0.65, 0.8))
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hint)
	_build_loot_panel()
	_refresh_bars()
	for c in get_children():
		if c is Control:
			(c as Control).theme = WCTheme.make_theme()

func _process(delta: float) -> void:
	if _announce_t > 0.0:
		_announce_t -= delta
		if _announce_t <= 0.0:
			announce_label.text = ""
	# objective tracker: distance to exit + foes remaining
	_obj_t -= delta
	if _obj_t <= 0.0:
		_obj_t = 0.25
		_refresh_objective()
	_prune_feed()
	if dungeon != null and dungeon.boss != null and is_instance_valid(dungeon.boss):
		boss_box.visible = not (dungeon.boss as WCEnemy).dead
		boss_label.text = "☠ " + String((dungeon.boss as WCEnemy).data.get("name", "BOSS"))
		boss_bar.max_value = (dungeon.boss as WCEnemy).max_hp
		boss_bar.value = (dungeon.boss as WCEnemy).hp
	elif boss_box != null:
		boss_box.visible = false
	if loot_timer > 0.0:
		loot_timer -= delta
		if loot_timer <= 0.0:
			_advance_loot()
	if dungeon != null and dungeon.player != null and is_instance_valid(dungeon.player):
		var wp: Dictionary = dungeon.player.weapon
		var ws: Dictionary = RunManager.loadout.get("secondary", {})
		var ammo_txt := ""
		if dungeon.player.held_kind == "gun" and dungeon.player.reloading:
			ammo_txt = " ⟳"
		weapon_label.text = "▶ %s%s (%.0f)  |  %s (%.0f)  [TAB]" % [
			String(wp.get("name", "?")), ammo_txt, float(wp.get("dps", 0)),
			String(ws.get("name", "—")), float(ws.get("dps", 0))]
	# program cooldown labels
	if dungeon != null and dungeon.player != null and is_instance_valid(dungeon.player):
		var p: WCPlayer = dungeon.player
		heat_bar.value = p.heat
		heat_bar.modulate = Color(1.0, 0.3, 0.15) if p.overheated else Color.WHITE
		stamina_bar.max_value = p.max_stamina()
		stamina_bar.value = p.stamina
		radial.mag = p.mag_size()
		radial.ammo = int(p.weapon.get("ammo", 0))
		radial.reloading = p.reloading
		radial.col = GameDB.DAMAGE_COLORS.get(String(p.wbase.get("dmg_type", "kinetic")), Color.WHITE)
		radial.queue_redraw()
		_update_prog_labels(p)

func _update_prog_labels(p: WCPlayer) -> void:
	## True binding map: SPACE = dash, Q = programs[0], E = programs[1].
	## (Previously this row was shifted one slot off reality.)
	var keys := ["SPACE", "Q", "E"]
	for i in mini(3, prog_labels.size()):
		var pname := "Blink Dash"
		var cd := p.dash_cd
		if i > 0:
			var idx := i - 1
			var pid := String(p.programs[idx]) if idx < p.programs.size() else ""
			var pd: Dictionary = GameDB.PROGRAMS.get(pid, {})
			pname = String(pd.get("name", "—"))
			cd = float(p.prog_cds.get("slot%d" % i, 0.0))
		if cd > 0.0:
			(prog_labels[i] as Label).text = "[%s] %s %.1fs" % [keys[i], pname, cd]
		else:
			(prog_labels[i] as Label).text = "[%s] %s ✓" % [keys[i], pname]

func _build_loot_panel() -> void:
	loot_panel = PanelContainer.new()
	loot_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	loot_panel.position = Vector2(-260, -300)
	loot_panel.custom_minimum_size = Vector2(520, 0)
	var s := _panel_style(Color(0.976, 0.941, 0.008))
	loot_panel.add_theme_stylebox_override("panel", s)
	add_child(loot_panel)
	var pm := MarginContainer.new()
	pm.add_theme_constant_override("margin_left", 18)
	pm.add_theme_constant_override("margin_right", 18)
	pm.add_theme_constant_override("margin_top", 12)
	pm.add_theme_constant_override("margin_bottom", 10)
	loot_panel.add_child(pm)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	pm.add_child(v)
	loot_rich = RichTextLabel.new()
	loot_rich.bbcode_enabled = true
	loot_rich.fit_content = true
	loot_rich.scroll_active = false
	loot_rich.custom_minimum_size = Vector2(520, 104)
	var backing := StyleBoxFlat.new()
	backing.bg_color = Color(0.008, 0.008, 0.02, 0.88)
	backing.set_corner_radius_all(3)
	backing.content_margin_left = 8
	backing.content_margin_right = 8
	backing.content_margin_top = 6
	backing.content_margin_bottom = 6
	loot_rich.add_theme_stylebox_override("normal", backing)
	v.add_child(loot_rich)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	loot_b1 = Button.new()
	loot_b1.text = "[1] PRIMARY"
	row.add_child(loot_b1)
	loot_b1.pressed.connect(func(): choose_loot("primary"))
	loot_b2 = Button.new()
	loot_b2.text = "[2] SECONDARY"
	row.add_child(loot_b2)
	loot_b2.pressed.connect(func(): choose_loot("secondary"))
	var bx := Button.new()
	bx.text = "LEAVE"
	row.add_child(bx)
	bx.pressed.connect(func(): _advance_loot())
	loot_panel.visible = false
	WCBrackets.attach_to(loot_panel, Color(0.976, 0.941, 0.008))

func show_loot(item: Dictionary) -> void:
	loot_queue.append(item)
	if pending_loot.is_empty():
		_advance_loot()

func _advance_loot() -> void:
	if loot_queue.is_empty():
		pending_loot = {}
		loot_timer = 0.0
		loot_panel.visible = false
		return
	pending_loot = loot_queue.pop_front()
	loot_timer = 14.0
	var col: Color = GameDB.RARITY_COLORS.get(String(pending_loot.get("rarity", "common")), Color.WHITE)
	var queued := ""
	if not loot_queue.is_empty():
		queued = "  [color=#8888aa]+%d more in queue[/color]" % loot_queue.size()
	var kind := String(pending_loot.get("kind", "weapon"))
	if kind == "armor":
		_show_armor_offer(col, queued)
	elif kind == "companion":
		_show_companion_offer(col, queued)
	else:
		_show_weapon_offer(col, queued)
	loot_panel.visible = true

func _show_weapon_offer(col: Color, queued: String) -> void:
	var cur1: Dictionary = RunManager.loadout.get("primary", {})
	var cur2: Dictionary = RunManager.loadout.get("secondary", {})
	var ndps := float(pending_loot.get("dps", 0))
	var best := maxf(float(cur1.get("dps", 0)), float(cur2.get("dps", 0)))
	var verdict := "[color=#3dff66]UPGRADE[/color]" if ndps > best * 1.05 else "[color=#ff5f5f]SIDE-GRADE[/color]"
	loot_rich.text = "[color=#%s][b]%s[/b][/color] [color=#8888aa](%s, %.0f dps)[/color] %s%s\n[color=#aaaabb]vs %s (%.0f) / %s (%.0f) — [1] primary · [2] secondary[/color]" % [
		col.to_html(false), String(pending_loot.get("name", "?")),
		String(pending_loot.get("rarity", "")).capitalize(), ndps, verdict, queued,
		String(cur1.get("name", "—")), float(cur1.get("dps", 0)),
		String(cur2.get("name", "—")), float(cur2.get("dps", 0))]
	loot_b1.text = "[1] PRIMARY"
	loot_b2.text = "[2] SECONDARY"
	loot_b2.visible = true

func _show_armor_offer(col: Color, queued: String) -> void:
	var slot := String(pending_loot.get("slot", "core"))
	var cur: Dictionary = {}
	for piece in RunManager.loadout.get("armor", []):
		if String((piece as Dictionary).get("slot", "")) == slot:
			cur = piece
	var st: Dictionary = pending_loot.get("stats", {})
	var set_id := String(pending_loot.get("set", ""))
	var counts: Dictionary = RunManager.set_counts
	var now: int = int(counts.get(set_id, 0))
	loot_rich.text = "[color=#%s][b]%s[/b][/color] [color=#8888aa](%s %s)[/color]%s\n[color=#aaaabb]%s → %s set %d/3 · HP +%d · ARM +%d — [1] equip (old salvaged)[/color]" % [
		col.to_html(false), String(pending_loot.get("name", "?")),
		String(pending_loot.get("rarity", "")).capitalize(), slot.capitalize(), queued,
		String(cur.get("name", "empty slot")), GameDB.ARMOR_SETS[set_id]["name"], mini(now + 1, 3),
		int(st.get("max_hp", 0)), int(st.get("armor", 0))]
	loot_b1.text = "[1] EQUIP"
	loot_b2.visible = false

func _show_companion_offer(col: Color, queued: String) -> void:
	var cur: Dictionary = RunManager.loadout.get("companion", {})
	loot_rich.text = "[color=#%s][b]%s[/b][/color] [color=#8888aa](%s drone)[/color]%s\n[color=#aaaabb]%.0f dps · %d HP vs %s — [1] equip (old salvaged)[/color]" % [
		col.to_html(false), String(pending_loot.get("name", "?")),
		String(pending_loot.get("rarity", "")).capitalize(), queued,
		float(pending_loot.get("dps", 0)), int(pending_loot.get("hp", 0)),
		String(cur.get("name", "empty slot"))]
	loot_b1.text = "[1] EQUIP"
	loot_b2.visible = false

func choose_loot(slot: String) -> void:
	if pending_loot.is_empty() or dungeon == null:
		return
	var kind := String(pending_loot.get("kind", "weapon"))
	if kind == "armor":
		RunManager.equip_armor(pending_loot)
		AudioDirector.play("levelup")
		if dungeon.player != null and is_instance_valid(dungeon.player):
			dungeon.float_text(dungeon.player.global_position + Vector3(0, 2.4, 0),
				"ARMORED: " + String(pending_loot.get("name", "?")),
				GameDB.RARITY_COLORS.get(String(pending_loot.get("rarity", "common")), Color.WHITE))
	elif kind == "companion":
		var old: Dictionary = RunManager.loadout.get("companion", {})
		RunManager.loadout["companion"] = pending_loot
		if not old.is_empty():
			SaveSystem.add_credits(int(30.0 * float(pending_loot.get("threat", 1))))
		AudioDirector.play("levelup")
		dungeon.refresh_companion()
	else:
		if dungeon.player != null and is_instance_valid(dungeon.player):
			dungeon.player.equip_item(pending_loot, slot)
	_advance_loot()

func _unhandled_input(event: InputEvent) -> void:
	if not loot_panel.visible or pending_loot.is_empty():
		return
	if event.is_action_pressed("equip_1"):
		choose_loot("primary")
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("equip_2"):
		choose_loot("secondary")
		get_viewport().set_input_as_handled()

func _refresh_objective() -> void:
	if dungeon == null or dungeon.player == null or not is_instance_valid(dungeon.player):
		obj_label.text = "◈ " + _obj_base
		return
	var d: float = dungeon.player.global_position.distance_to(dungeon.exit_pos)
	var foes := get_tree().get_nodes_in_group("enemies").size()
	var gate := ""
	if RunManager.boss_spawned and not RunManager.boss_dead:
		gate = " · ☠ BOSS FIRST"
	obj_label.text = "◈ %s — EXIT %dm · %d hostiles%s" % [_obj_base, int(d), foes, gate]
	if dungeon.nearest_terminal(dungeon.player.global_position) >= 0:
		interact_label.text = "◈ [F] HACK TERMINAL"
	else:
		interact_label.text = ""

func announce(text: String, color := Color.WHITE) -> void:
	announce_label.text = text
	announce_label.add_theme_color_override("font_color", color)
	_announce_t = 2.4

func _on_hp(hp: float, max_hp: float) -> void:
	hp_bar.max_value = max_hp
	hp_bar.value = hp
	hp_label.text = "HP %d / %d" % [int(hp), int(max_hp)]
	var frac := hp / maxf(1.0, max_hp)
	vignette.color.a = clampf(0.45 * (1.0 - frac * 2.5), 0.0, 0.45)

func _on_en(e: float, max_e: float) -> void:
	en_bar.max_value = max_e
	en_bar.value = e

func _on_kill(enemy_name: String, xp: int) -> void:
	_push_feed("[color=#ff5f7a]✕ %s[/color]  [color=#8888aa]+%d xp[/color]" % [enemy_name, xp])

func _on_loot(item: Dictionary) -> void:
	var col: Color = GameDB.RARITY_COLORS.get(String(item.get("rarity", "common")), Color.WHITE)
	var sub := ""
	match String(item.get("kind", "weapon")):
		"weapon":
			sub = "(%s %.0f dps)" % [String(item.get("rarity", "")).capitalize(), float(item.get("dps", 0))]
		"armor":
			sub = "(%s %s)" % [String(item.get("rarity", "")).capitalize(), String(item.get("slot", "?")).capitalize()]
		"companion":
			sub = "(%s drone)" % String(item.get("rarity", "")).capitalize()
	_push_feed("[color=#%s]◈ %s[/color] [color=#8888aa]%s[/color]" % [
		col.to_html(false), String(item.get("name", "?")), sub])

func _push_feed(bb: String) -> void:
	_feed_lines.append({"bb": bb, "exp": Time.get_ticks_msec() / 1000.0 + 7.0})
	while _feed_lines.size() > 7:
		_feed_lines.pop_front()
	_render_feed()

func _prune_feed() -> void:
	var now := Time.get_ticks_msec() / 1000.0
	var kept: Array = []
	for e in _feed_lines:
		if float(e.get("exp", 0.0)) > now:
			kept.append(e)
	if kept.size() != _feed_lines.size():
		_feed_lines = kept
		_render_feed()

func _render_feed() -> void:
	var parts: Array = []
	for e in _feed_lines:
		parts.append(String(e.get("bb", "")))
	feed.text = "\n".join(parts)

func _refresh_bars() -> void:
	_on_hp(RunManager.hp, RunManager.max_hp)
	_on_en(RunManager.energy, RunManager.max_energy)

class _Minimap extends Control:
	func _draw() -> void:
		var hud := get_parent() as WCHUD
		if hud == null or hud.dungeon == null:
			return
		var d: Dictionary = hud.dungeon.layout
		if d.is_empty():
			return
		var w: int = d["w"]
		var h: int = d["h"]
		var tiles: PackedByteArray = d["tiles"]
		var s: float = minf(size.x / w, size.y / h)
		draw_rect(Rect2(Vector2.ZERO, size), Color(0.01, 0.01, 0.03, 0.8), true)
		for y in h:
			for x in w:
				var t: int = tiles[y * w + x]
				if t == 0:
					continue
				var c := Color(0.15, 0.2, 0.3)
				match t:
					3: c = Color(0.3, 1.0, 0.5)
					4: c = Color(0.2, 1.0, 0.5)
					5: c = Color(0.976, 0.941, 0.008)
					6: c = Color(1.0, 0.16, 0.43)
				draw_rect(Rect2(Vector2(x, y) * s, Vector2(s + 0.5, s + 0.5)), c, true)
		# player + exit + boss dots
		if hud.dungeon.player != null and is_instance_valid(hud.dungeon.player):
			var pp: Vector3 = hud.dungeon.player.global_position
			var cell: Vector2i = hud.dungeon._world_to_cell(pp)
			draw_circle(Vector2(cell) * s, 3.0, Color.WHITE)
		draw_circle(Vector2(d["exit"]) * s, 3.0, Color(0.3, 1.0, 0.5))
	func _process(_d: float) -> void:
		queue_redraw()
