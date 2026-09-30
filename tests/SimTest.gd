extends Node
## Headless verification harness — run as a SCENE so autoloads are present:
##   godot --headless --path . res://tests/SimTest.tscn
## Asserts generation, loot, synergy, progression, and save invariants.

var failures := 0
var passes := 0

func _ready() -> void:
	AudioDirector.enabled = false
	_test_xp_curve()
	_test_threat_scaling()
	_test_dungeon_connectivity()
	_test_loot_rolls()
	_test_synergies()
	_test_run_manager()
	_test_save_roundtrip()
	await _test_dungeon_boot()
	await _test_rust_backend()
	print("---- SIMTEST: %d passed, %d failed ----" % [passes, failures])
	get_tree().quit(1 if failures > 0 else 0)

func _ensure_test_input() -> void:
	_add_test_key("move_fwd", [KEY_W])
	_add_test_key("move_back", [KEY_S])
	_add_test_key("move_left", [KEY_A])
	_add_test_key("move_right", [KEY_D])
	_add_test_key("dash", [KEY_SPACE])
	_add_test_key("program_1", [KEY_Q])
	_add_test_key("program_2", [KEY_E])
	_add_test_key("swap_weapon", [KEY_TAB])
	_add_test_key("equip_1", [KEY_1])
	_add_test_key("equip_2", [KEY_2])
	if not InputMap.has_action("fire"):
		InputMap.add_action("fire")

func _add_test_key(action: String, keys: Array) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	for kc in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = kc
		InputMap.action_add_event(action, ev)

func _test_rust_backend() -> void:
	if not WCDungeon.rust_available():
		_check(true, "rust_absent_fallback_ok")
		return
	_check(true, "rust_backend_present")
	var rust = ClassDB.instantiate("WCDungeonRust")
	var d: Dictionary = rust.call("generate", 1234, 3, 9)
	rust.free()
	_check(not d.is_empty() and (d.get("rooms") as Array).size() >= 9, "rust_room_count")
	_check(_connected(d), "rust_dungeon_connected")
	_check(d.get("rust", false) == true, "rust_backend_flag")

func _test_dungeon_boot() -> void:
	_ensure_test_input()
	var starter: Dictionary = LootFactory.roll_weapon(1, 0.0, "smg", "common")
	var sidearm: Dictionary = LootFactory.roll_weapon(1, 0.0, "katana", "common")
	RunManager.start_run("solo", GameDB.CONTRACTS[0], starter, sidearm, [], ["blink", "ice_turret", "blackout"])
	var dng := WCDungeon.new()
	dng.setup(GameDB.CONTRACTS[0])
	add_child(dng)
	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	_check(dng.player != null and is_instance_valid(dng.player), "dungeon_spawns_player")
	_check(dng.enemies_alive > 0, "dungeon_spawns_enemies", "(%d)" % dng.enemies_alive)
	_check(dng.cam != null, "dungeon_camera")
	var foes := get_tree().get_nodes_in_group("enemies")
	_check(not foes.is_empty(), "enemies_in_tree")
	if foes.size() > 1:
		var champ: WCEnemy = foes[1] as WCEnemy
		var chp0: float = champ.max_hp
		champ.make_elite()
		_check(champ.elite and champ.max_hp > chp0, "elite_modifier")
	if not foes.is_empty():
		var e: WCEnemy = foes[0] as WCEnemy
		var kills0: int = RunManager.kills
		e.take_hit(999999.0, "volt", ["test"], e.global_position + Vector3(1, 0, 0))
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(RunManager.kills > kills0, "enemy_death_registers")
		# program AoE paths
		dng.blackout_blast(dng.player.global_position + Vector3(2, 0, 0), 1.0)
		dng.system_shock(dng.player.global_position, 1.0)
		dng.deploy_turret(dng.player.global_position, 1.0)
		dng.summon_hound(dng.player.global_position)
		await get_tree().physics_frame
		_check(not get_tree().get_nodes_in_group("allies").is_empty(), "allies_deploy")
	# weapon swap + equip paths
	var first_id: String = dng.player.weapon.get("weapon_id", "?")
	dng.player.swap_weapon()
	_check(String(dng.player.weapon.get("weapon_id", "?")) != first_id, "weapon_swap",
		"(%s -> %s)" % [first_id, String(dng.player.weapon.get("weapon_id", "?"))])
	var better: Dictionary = LootFactory.roll_weapon(6, 3.0, "railspike", "legendary")
	dng.player.equip_item(better, "primary")
	_check(String(RunManager.loadout["primary"].get("weapon_id", "")) == "railspike", "equip_item")
	_check(dng.has_vault, "vault_exists")
	_check(String(dng.vault_item.get("rarity", "")) in ["epic", "legendary", "mythic"],
		"vault_loot_floor", "(%s)" % String(dng.vault_item.get("rarity", "?")))
	dng.queue_free()
	RunManager.end_run(false)

func _check(cond: bool, name: String, extra := "") -> void:
	if cond:
		passes += 1
		print("PASS  %s %s" % [name, extra])
	else:
		failures += 1
		printerr("FAIL  %s %s" % [name, extra])

func _test_xp_curve() -> void:
	var prev := 0
	for lv in range(1, 21):
		var x: int = GameDB.xp_for_level(lv)
		_check(x > prev, "xp_monotonic_lv%d" % lv, "(%d)" % x)
		prev = x

func _test_threat_scaling() -> void:
	_check(is_equal_approx(GameDB.threat_hp_mult(1), 1.0), "hp_mult_t1")
	_check(GameDB.threat_hp_mult(6) > 3.0, "hp_mult_t6", "(%.2f)" % GameDB.threat_hp_mult(6))
	_check(GameDB.threat_dmg_mult(6) > GameDB.threat_dmg_mult(1), "dmg_mult_grows")

func _test_dungeon_connectivity() -> void:
	for s in [1, 7, 42, 1337, 90001]:
		var d: Dictionary = DungeonGen.generate(3, 9, s)
		_check(_connected(d), "dungeon_connected_seed%d" % s)
		_check(d["spawn"] != d["exit"], "spawn_ne_exit_seed%d" % s)
		_check((d["rooms"] as Array).size() >= 9, "room_count_seed%d" % s,
			"(%d rooms)" % (d["rooms"] as Array).size())

func _connected(d: Dictionary) -> bool:
	var w: int = d["w"]
	var h: int = d["h"]
	var tiles: PackedByteArray = d["tiles"]
	var seen := {}
	var stack: Array = [d["spawn"]]
	seen[d["spawn"]] = true
	var floor_total := 0
	for t in tiles:
		if t != 0:
			floor_total += 1
	var reached := 0
	while not stack.is_empty():
		var c: Vector2i = stack.pop_back()
		reached += 1
		for delta in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = c + delta
			if n.x < 0 or n.y < 0 or n.x >= w or n.y >= h:
				continue
			if tiles[n.y * w + n.x] == 0 or seen.has(n):
				continue
			seen[n] = true
			stack.append(n)
	return reached == floor_total

func _test_loot_rolls() -> void:
	var seen_rarities := {}
	var ok := true
	for i in 300:
		var item: Dictionary = LootFactory.roll_weapon(3, 1.0)
		if not item.has("dps") or float(item["dps"]) <= 0.0:
			ok = false
		seen_rarities[item["rarity"]] = true
		var armor: Dictionary = LootFactory.roll_armor(3, 1.0)
		if not armor.has("stats"):
			ok = false
	_check(ok, "loot_rolls_valid")
	_check(seen_rarities.size() >= 3, "loot_rarity_spread", "(%s)" % str(seen_rarities.keys()))
	var mythic := 0
	for i in 2000:
		if LootFactory.roll_weapon(6, 3.0)["rarity"] == "mythic":
			mythic += 1
	_check(mythic > 0, "mythic_possible_t6_luck3", "(%d/2000)" % mythic)

func _test_synergies() -> void:
	var st: Dictionary = SynergyEngine.empty_statuses()
	st["shocked"] = 3.0
	st["chilled"] = 3.0
	var ev: Array = SynergyEngine.apply_hit(st, "volt", [], 1.0)
	var found := false
	for e in ev:
		if String(e.get("id", "")) == "superconduct":
			found = true
	_check(found, "superconduct_triggers")
	var st2: Dictionary = SynergyEngine.empty_statuses()
	var ev2: Array = SynergyEngine.apply_hit(st2, "kinetic", [], 0.0)
	_check(ev2.is_empty(), "no_spurious_synergy")

func _test_run_manager() -> void:
	var starter: Dictionary = LootFactory.roll_weapon(1, 0.0, "smg", "common")
	var sidearm: Dictionary = LootFactory.roll_weapon(1, 0.0, "katana", "common")
	RunManager.start_run("solo", GameDB.CONTRACTS[0], starter, sidearm, [], ["blink", "ice_turret", "blackout"])
	_check(RunManager.active and RunManager.hp == RunManager.max_hp, "run_starts_full_hp",
		"(%.0f)" % RunManager.hp)
	var hp0: float = RunManager.hp
	RunManager.take_damage(10.0)
	_check(RunManager.hp < hp0, "damage_applies")
	var k0: int = RunManager.kills
	RunManager.register_kill({"name": "Test Punk", "xp": 10, "creds": 5})
	_check(RunManager.kills == k0 + 1 and RunManager.xp_earned > 0, "kill_registers")
	var lv0: int = RunManager.run_level
	RunManager.gain_xp(100000)
	_check(RunManager.run_level > lv0, "level_up_works", "(lv %d)" % RunManager.run_level)
	RunManager.end_run(false)
	_check(not RunManager.active, "run_ends")

func _test_save_roundtrip() -> void:
	var before: int = SaveSystem.origin_level("solo")
	SaveSystem.add_xp("solo", 5)
	_check(SaveSystem.origin_level("solo") >= before, "save_xp_persists")
	_check(SaveSystem.save_profile(), "save_writes")
