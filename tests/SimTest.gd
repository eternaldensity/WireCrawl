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
	_test_audio()
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
	_add_test_key("interact", [KEY_F])
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
	# W maps to camera-forward (screen-up), D to camera-right
	var camf: Vector3 = -dng.cam.global_transform.basis.z
	camf.y = 0.0
	var camr: Vector3 = dng.cam.global_transform.basis.x
	camr.y = 0.0
	_check(dng.player._screen_wish(Vector2(0, -1)).normalized().dot(camf.normalized()) > 0.99,
		"move_w_screen_up")
	_check(dng.player._screen_wish(Vector2(1, 0)).normalized().dot(camr.normalized()) > 0.99,
		"move_d_screen_right")
	_check(dng.enemies_alive > 0, "dungeon_spawns_enemies", "(%d)" % dng.enemies_alive)
	_check(dng.cam != null, "dungeon_camera")
	var foes := get_tree().get_nodes_in_group("enemies")
	_check(not foes.is_empty(), "enemies_in_tree")
	if foes.size() > 1:
		var champ: WCEnemy = null
		for f in foes:
			var fe := f as WCEnemy
			if fe != null and not fe.elite and not fe.is_boss:
				champ = fe
				break
		if champ == null:
			_check(true, "elite_modifier_skipped_all_elite")
		else:
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
	# x-ray silhouettes present
	_check(dng.player.get_node_or_null("Rig/XRay") != null, "player_xray")
	# projectile collision: freeze a live foe, shoot it for real
	var victim: WCEnemy = null
	for f in get_tree().get_nodes_in_group("enemies"):
		var fe := f as WCEnemy
		if fe != null and not fe.dead:
			victim = fe
			break
	_check(victim != null, "live_target_found")
	if victim != null:
		_check(victim.get_node_or_null("Rig/XRay") != null, "enemy_xray")
		victim.statuses["frozen"] = 99.0
		var vhp0: float = victim.hp
		# hermetic shot: teleport victim beside the player (crate-free
		# spawn ground), verify line of sight, then fire point-blank
		var muzzle: Vector3 = dng.player.global_position + Vector3(0, 1.1, 0)
		var fired := false
		for off in [Vector3(2.5, 0, 0), Vector3(-2.5, 0, 0), Vector3(0, 0, 2.5), Vector3(0, 0, -2.5)]:
			victim.global_position = dng.player.global_position + off
			var aim: Vector3 = (victim.global_position + Vector3(0, 1.0, 0) - muzzle).normalized()
			var params := PhysicsRayQueryParameters3D.create(muzzle, victim.global_position + Vector3(0, 1.0, 0))
			params.collision_mask = 1
			params.exclude = [dng.player.get_rid()]
			var hit: Dictionary = dng.get_world_3d().direct_space_state.intersect_ray(params)
			if hit.is_empty():
				WCProjectile.spawn(dng, muzzle, aim,
					{"faction": "player", "damage": 60.0, "dmg_type": "kinetic",
						"speed": 30.0, "color": Color.WHITE})
				fired = true
				break
		if not fired:
			_check(true, "projectile_skipped_no_lane")
		else:
			for _i in 15:
				await get_tree().physics_frame
			_check(victim.hp < vhp0 or victim.dead, "projectile_hits",
				"(hp %.0f -> %.0f)" % [vhp0, victim.hp])
	# weapon swap + equip paths
	var first_id: String = dng.player.weapon.get("weapon_id", "?")
	dng.player.swap_weapon()
	_check(String(dng.player.weapon.get("weapon_id", "?")) != first_id, "weapon_swap",
		"(%s -> %s)" % [first_id, String(dng.player.weapon.get("weapon_id", "?"))])
	_check(dng.player.held_kind == "blade", "held_blade_model")
	# melee fire path: plant player next to a live foe and swing
	var foe2: WCEnemy = null
	for f in get_tree().get_nodes_in_group("enemies"):
		var fe2 := f as WCEnemy
		if fe2 != null and not fe2.dead:
			foe2 = fe2
			break
	if foe2 != null:
		dng.player.global_position = foe2.global_position + Vector3(2.2, 0, 0)
		dng.player.aim_dir = (foe2.global_position - dng.player.global_position).normalized()
		var fhp0: float = foe2.hp
		dng.player.try_fire()
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(foe2.hp < fhp0 or foe2.dead, "melee_hits",
			"(hp %.0f -> %.0f)" % [fhp0, foe2.hp])
	else:
		_check(true, "melee_skipped_no_foe")
	var better: Dictionary = LootFactory.roll_weapon(6, 3.0, "railspike", "legendary")
	dng.player.equip_item(better, "primary")
	_check(String(RunManager.loadout["primary"].get("weapon_id", "")) == "railspike", "equip_item")
	_check(dng.player.held_kind == "gun", "held_gun_model")
	# destructible crates break + free
	var crates := get_tree().get_nodes_in_group("crates")
	_check(not crates.is_empty(), "crates_exist", "(%d)" % crates.size())
	if not crates.is_empty():
		var crate := crates[0] as WCPropCrate
		crate.take_hit(99999.0, "kinetic", [], crate.global_position + Vector3(1, 0, 0))
		await get_tree().physics_frame
		await get_tree().physics_frame
		_check(not is_instance_valid(crate), "crate_breaks")
	_check(dng.has_vault, "vault_exists")
	_check(String(dng.vault_item.get("rarity", "")) in ["epic", "legendary", "mythic"],
		"vault_loot_floor", "(%s)" % String(dng.vault_item.get("rarity", "?")))
	# heat: sustained fire overheats and locks the trigger
	dng.player.heat = 99.0
	dng.player.overheated = false
	var shots0: int = dng.player.shots_fired
	dng.player.fire_cd = 0.0
	dng.player.try_fire()
	_check(dng.player.overheated, "overheat_triggers")
	var shots1: int = dng.player.shots_fired
	dng.player.fire_cd = 0.0
	dng.player.try_fire()
	_check(dng.player.shots_fired == shots1, "overheat_locks_fire",
		"(shots %d -> %d)" % [shots0, shots1])
	# loot queue: two offers while panel busy keeps both
	var hud := WCHUD.new()
	add_child(hud)
	hud.dungeon = dng
	await get_tree().process_frame
	var qa: Dictionary = LootFactory.roll_weapon(2, 0.0, "smg", "rare")
	var qb: Dictionary = LootFactory.roll_weapon(2, 0.0, "katana", "epic")
	hud.show_loot(qa)
	hud.show_loot(qb)
	_check(hud.loot_queue.size() == 1 and not hud.pending_loot.is_empty(), "loot_queues",
		"(pending=%s queued=%d)" % [String(hud.pending_loot.get("name", "?")), hud.loot_queue.size()])
	hud.choose_loot("secondary")
	_check(String(hud.pending_loot.get("weapon_id", "")) == "katana", "loot_advances",
		"(now %s)" % String(hud.pending_loot.get("weapon_id", "?")))
	hud.queue_free()
	# terminals: teleport to one and hack it
	if not dng.terminals.is_empty():
		var tp: Vector3 = (dng.terminals[0] as Dictionary)["pos"]
		dng.player.global_position = tp
		var cr0: int = RunManager.credits_earned
		dng.try_hack()
		_check(RunManager.credits_earned > cr0, "hack_pays",
			"(%d -> %d)" % [cr0, RunManager.credits_earned])
		_check(bool((dng.terminals[0] as Dictionary)["taken"]), "hack_marks_taken")
	else:
		_check(true, "hack_skipped_no_terminals")
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

func _peak_16(data: PackedByteArray) -> int:
	## Manual little-endian decode (matches AudioDirector._pack_bytes).
	var peak := 0
	var i := 0
	while i + 1 < data.size():
		var v := int(data[i]) | (int(data[i + 1]) << 8)
		if v >= 32768:
			v -= 65536
		peak = maxi(peak, absi(v))
		i += 997 * 2  # sparse scan: fast + representative
	return peak

func _test_audio() -> void:
	var names := ["shoot", "shoot_heavy", "melee", "hit", "explode", "pickup",
		"credits", "levelup", "dash", "hurt", "boss", "ui", "synergy", "turret"]
	var all_ok := true
	for sfx in names:
		var w: AudioStreamWAV = AudioDirector._synth(sfx)
		if w.format != AudioStreamWAV.FORMAT_16_BITS or w.data.size() < 500:
			all_ok = false
			break
		var peak := _peak_16(w.data)
		if peak < 500 or peak > 32760:
			all_ok = false
			break
	_check(all_ok, "sfx_16bit_headroom")
	var mb: AudioStreamWAV = AudioDirector.music_bass.stream
	var mh: AudioStreamWAV = AudioDirector.music_player.stream
	_check(mb != null and mh != null, "music_streams_present")
	if mb != null and mh != null:
		_check(mb.data.size() > 200000 and mh.data.size() > 200000, "music_length",
			"(%d/%d bytes)" % [mb.data.size(), mh.data.size()])
		var pl := _peak_16(mb.data)
		var ph := _peak_16(mh.data)
		_check(pl > 2000 and pl < 32760 and ph > 1000 and ph < 32760, "music_headroom",
			"(low=%d high=%d)" % [pl, ph])
