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
var interact_label: Label
var _obj_base := "Reach the EXIT uplink"
var _obj_t := 0.0
var prog_labels: Array = []
var weapon_label: Label
var loot_panel: PanelContainer
var loot_rich: RichTextLabel
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

func _panel_style(border: Color) -> StyleBoxFlat:
	return WCTheme.panel(border, Color(0.02, 0.02, 0.05, 0.85))

func _build() -> void:
	# vignette
	vignette = ColorRect.new()
	vignette.color = Color(1, 0.1, 0.2, 0.0)
	vignette.set_anchors_preset(Control.PRESET_FULL_RECT)
	vignette.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(vignette)
	# top-left vitals
	var vitals := VBoxContainer.new()
	vitals.set_anchors_preset(Control.PRESET_TOP_LEFT)
	vitals.position = Vector2(14, 12)
	vitals.add_theme_constant_override("separation", 4)
	add_child(vitals)
	hp_label = Label.new()
	hp_label.add_theme_font_size_override("font_size", 15)
	vitals.add_child(hp_label)
	hp_bar = ProgressBar.new()
	hp_bar.custom_minimum_size = Vector2(300, 16)
	hp_bar.show_percentage = false
	vitals.add_child(hp_bar)
	en_bar = ProgressBar.new()
	en_bar.custom_minimum_size = Vector2(300, 9)
	en_bar.show_percentage = false
	vitals.add_child(en_bar)
	heat_bar = ProgressBar.new()
	heat_bar.custom_minimum_size = Vector2(300, 6)
	heat_bar.show_percentage = false
	heat_bar.max_value = 100.0
	heat_bar.value = 0.0
	vitals.add_child(heat_bar)
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
	hint.text = "WASD move (screen) · Mouse aim · LMB fire · SPACE dash · TAB swap · Q/E programs · 1/2 loot"
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
		weapon_label.text = "▶ %s (%.0f)  |  %s (%.0f)  [TAB]" % [
			String(wp.get("name", "?")), float(wp.get("dps", 0)),
			String(ws.get("name", "—")), float(ws.get("dps", 0))]
	# program cooldown labels
	if dungeon != null and dungeon.player != null and is_instance_valid(dungeon.player):
		var p: WCPlayer = dungeon.player
		heat_bar.value = p.heat
		heat_bar.modulate = Color(1.0, 0.3, 0.15) if p.overheated else Color.WHITE
		for i in mini(3, prog_labels.size()):
			var pid := String(p.programs[i]) if i < p.programs.size() else ""
			var pd: Dictionary = GameDB.PROGRAMS.get(pid, {})
			var cd: float = float(p.prog_cds.get("slot%d" % (i + 1), 0.0)) if i > 0 else p.dash_cd
			var key: String = ["SPACE", "Q", "E"][i]
			if cd > 0.0:
				(prog_labels[i] as Label).text = "[%s] %s %.1fs" % [key, pd.get("name", "Dash"), cd]
			else:
				(prog_labels[i] as Label).text = "[%s] %s ✓" % [key, pd.get("name", "Dash")]

func _build_loot_panel() -> void:
	loot_panel = PanelContainer.new()
	loot_panel.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	loot_panel.position = Vector2(-260, -300)
	loot_panel.custom_minimum_size = Vector2(520, 0)
	var s := _panel_style(Color(0.976, 0.941, 0.008))
	loot_panel.add_theme_stylebox_override("panel", s)
	add_child(loot_panel)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 4)
	loot_panel.add_child(v)
	loot_rich = RichTextLabel.new()
	loot_rich.bbcode_enabled = true
	loot_rich.fit_content = true
	loot_rich.scroll_active = false
	loot_rich.custom_minimum_size = Vector2(500, 90)
	v.add_child(loot_rich)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	v.add_child(row)
	var b1 := Button.new()
	b1.text = "[1] PRIMARY"
	row.add_child(b1)
	b1.pressed.connect(func(): choose_loot("primary"))
	var b2 := Button.new()
	b2.text = "[2] SECONDARY"
	row.add_child(b2)
	b2.pressed.connect(func(): choose_loot("secondary"))
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
	var cur1: Dictionary = RunManager.loadout.get("primary", {})
	var cur2: Dictionary = RunManager.loadout.get("secondary", {})
	var ndps := float(pending_loot.get("dps", 0))
	var best := maxf(float(cur1.get("dps", 0)), float(cur2.get("dps", 0)))
	var verdict := "[color=#3dff66]UPGRADE[/color]" if ndps > best * 1.05 else "[color=#ff5f5f]SIDE-GRADE[/color]"
	loot_rich.text = "[color=#%s][b]%s[/b][/color] [color=#8888aa](%s, %.0f dps)[/color] %s\n[color=#aaaabb]vs %s (%.0f) / %s (%.0f) — [1] primary · [2] secondary[/color]" % [
		col.to_html(false), String(pending_loot.get("name", "?")),
		String(pending_loot.get("rarity", "")).capitalize(), ndps, verdict,
		String(cur1.get("name", "—")), float(cur1.get("dps", 0)),
		String(cur2.get("name", "—")), float(cur2.get("dps", 0))]
	loot_panel.visible = true

func choose_loot(slot: String) -> void:
	if pending_loot.is_empty() or dungeon == null:
		return
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
	_push_feed("[color=#%s]◈ %s[/color] [color=#8888aa](%s %.0f dps)[/color]" % [
		col.to_html(false), String(item.get("name", "?")),
		String(item.get("rarity", "")).capitalize(), float(item.get("dps", 0))])

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
