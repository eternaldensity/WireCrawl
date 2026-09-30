extends Node
## RunManager — owns the active dungeon run: loadout, stats, threat scaling,
## kills/objectives, loot+credits earned, extraction, and post-run settlement.
## Emits signals consumed by HUD and Main. Pure run-state, no rendering.

signal hp_changed(hp: float, max_hp: float)
signal energy_changed(e: float, max_e: float)
signal xp_changed(xp: int, level: int, origin: String)
signal credits_changed(c: int)
signal kill_confirmed(enemy_name: String, xp: int)
signal loot_dropped(item: Dictionary)
signal objective_changed(text: String)
signal run_ended(victory: bool, summary: Dictionary)
signal leveled_up(new_level: int)

var active := false
var origin := "solo"
var run_level := 1
var run_xp := 0
var hp := 100.0
var max_hp := 100.0
var energy := 100.0
var max_energy := 100.0
var armor := 0.0
var speed_mult := 1.0
var dmg_mult := 1.0
var program_power := 1.0
var cdr := 0.0
var lifesteal := 0.0
var luck := 0.0
var reload_mult := 1.0
var stamina_max := 100.0
var stamina_regen_mult := 1.0
var bonus_hp := 0.0
var level_dmg := 1.0
var origin_ally := 1.0
var set_dmg := 0.0
var kill_heal := 0.0
var lifesteal_set := 0.0
var overdrive_dur_bonus := 0.0
var prog_power_set := 1.0
var prog_cost_mult := 1.0
var ally_set := 1.0
var failsafe_enabled := false
var failsafe_used := false
var failsafe_popped := false
var speed_set := 0.0
var dash_bonus := 0.0
var cloak_kill := 0.0
var set_counts := {}
var threat := 1
var contract := {}
var kills := 0
var credits_earned := 0
var xp_earned := 0
var loot_earned: Array = []
var rooms_cleared := 0
var boss_spawned := false
var boss_dead := false
var extracted := false
var loadout := {"primary": {}, "secondary": {}, "armor": [], "programs": ["blink"]}
var statuses := {}

func start_run(p_origin: String, p_contract: Dictionary, primary: Dictionary, secondary: Dictionary, armor_pieces: Array, programs: Array) -> void:
	origin = p_origin
	contract = p_contract
	threat = int(p_contract.get("threat", 1))
	luck = 0.0
	bonus_hp = 0.0
	level_dmg = 1.0
	origin_ally = float(GameDB.ORIGINS[origin]["mods"].get("ally_mult", 1.0))
	failsafe_used = false
	failsafe_popped = false
	run_level = SaveSystem.origin_level(origin)
	run_xp = 0
	kills = 0
	credits_earned = 0
	xp_earned = 0
	loot_earned = []
	rooms_cleared = 0
	boss_spawned = false
	boss_dead = false
	extracted = false
	loadout = {"primary": primary, "secondary": secondary, "armor": armor_pieces, "programs": programs, "companion": {}}
	statuses = SynergyEngine.empty_statuses()
	active = true
	_recalc_stats()
	hp = max_hp
	energy = max_energy
	objective_changed.emit("Reach the EXIT uplink — clear rooms for loot")

func _recalc_stats() -> void:
	## Full stat rebuild from base + cyberware + levels + armor + set bonuses.
	## Called at run start, on level-up, and whenever gear changes.
	var base: Dictionary = GameDB.ORIGINS[origin]
	var cw: Dictionary = SaveSystem.cyberware_bonus()
	var armor_hp := 0.0
	var armor_armor := 0.0
	var armor_energy := 0
	var armor_speed := 0.0
	var sets: Array = []
	for piece in loadout.get("armor", []):
		var st: Dictionary = piece.get("stats", {})
		armor_hp += float(st.get("max_hp", 0))
		armor_armor += float(st.get("armor", 0))
		armor_energy += int(st.get("max_energy", 0))
		armor_speed += float(st.get("speed", 0.0))
		sets.append(String(piece.get("set", "")))
	set_counts = LootFactory.set_bonus_count(sets)
	set_dmg = 0.0
	kill_heal = 0.0
	lifesteal_set = 0.0
	overdrive_dur_bonus = 0.0
	prog_power_set = 1.0
	prog_cost_mult = 1.0
	ally_set = 1.0
	failsafe_enabled = false
	speed_set = 0.0
	dash_bonus = 0.0
	cloak_kill = 0.0
	if int(set_counts.get("solo", 0)) >= 2:
		set_dmg += 0.12
		kill_heal += 4.0
	if int(set_counts.get("solo", 0)) >= 3:
		set_dmg += 0.10
		lifesteal_set += 0.04
		overdrive_dur_bonus += 4.0
	if int(set_counts.get("netrunner", 0)) >= 2:
		prog_power_set *= 1.25
		prog_cost_mult *= 0.85
	if int(set_counts.get("netrunner", 0)) >= 3:
		prog_power_set *= 1.10
		ally_set *= 1.4
	if int(set_counts.get("techie", 0)) >= 2:
		ally_set *= 1.5
	if int(set_counts.get("techie", 0)) >= 3:
		failsafe_enabled = true
	if int(set_counts.get("ghost", 0)) >= 2:
		speed_set += 0.08
		dash_bonus += 0.15
	if int(set_counts.get("ghost", 0)) >= 3:
		cloak_kill += 0.15
	max_hp = float(base["hp"]) + float(base["mods"].get("max_hp", 0)) + cw["max_hp"] + float(SaveSystem.origin_level(origin) - 1) * 6.0 + bonus_hp + armor_hp
	max_energy = float(base["energy"]) + float(base["mods"].get("max_energy", 0)) + float(cw["max_energy"]) + armor_energy
	armor = float(base["mods"].get("armor", 0)) + armor_armor
	speed_mult = float(cw["speed"]) + armor_speed + speed_set
	dmg_mult = float(cw["dmg_mult"]) * float(base["mods"].get("melee_mult", 1.0)) * level_dmg * (1.0 + set_dmg)
	program_power = float(cw["program_power"]) * float(base["mods"].get("program_power", 1.0)) * prog_power_set
	cdr = clampf(float(cw["cdr"]) + float(base["mods"].get("cdr", 0.0)), 0.0, 0.5)
	lifesteal = float(base["mods"].get("lifesteal", 0.0)) + lifesteal_set
	reload_mult = float(base["mods"].get("reload_mult", 1.0))
	stamina_max = 100.0 + float(base["mods"].get("stamina_max", 0.0))
	stamina_regen_mult = float(base["mods"].get("stamina_regen", 1.0))
	hp = minf(hp, max_hp)
	energy = minf(energy, max_energy)
	hp_changed.emit(hp, max_hp)
	energy_changed.emit(energy, max_energy)

func ally_power() -> float:
	return program_power * origin_ally * ally_set

func equip_armor(item: Dictionary) -> Dictionary:
	## Equip armor, recalc, return the replaced piece ({} if slot was empty).
	var slot := String(item.get("slot", "core"))
	var old := {}
	var gear: Array = loadout.get("armor", [])
	for i in gear.size():
		if String((gear[i] as Dictionary).get("slot", "")) == slot:
			old = gear[i]
			gear[i] = item
			break
	if old.is_empty():
		gear.append(item)
	loadout["armor"] = gear
	_recalc_stats()
	if not old.is_empty():
		SaveSystem.add_credits(int(20.0 * float(item.get("threat", 1))))
	return old

func gear_lines() -> Array:
	## Human-readable loadout summary for the pause screen.
	var lines: Array = []
	for piece in loadout.get("armor", []):
		var pd := piece as Dictionary
		lines.append("◈ %s [%s]" % [String(pd.get("name", "?")), String(pd.get("rarity", "?")).capitalize()])
	for sid in set_counts.keys():
		var n: int = int(set_counts[sid])
		if n >= 2:
			lines.append("◆ %s %dpc: %s" % [GameDB.ARMOR_SETS[sid]["name"], n,
				GameDB.ARMOR_SETS[sid]["bonus3"] if n >= 3 else GameDB.ARMOR_SETS[sid]["bonus2"]])
	var comp: Dictionary = loadout.get("companion", {})
	if not comp.is_empty():
		lines.append("⬢ %s (%s, %.0f dps)" % [String(comp.get("name", "?")),
			String(comp.get("rarity", "?")).capitalize(), float(comp.get("dps", 0))])
	if lines.is_empty():
		lines.append("No armor installed — strip it from the fallen.")
	return lines

func damage_mult_for(dmg_type: String) -> float:
	var m := dmg_mult
	if dmg_type == "melee":
		m *= 1.0
	return m

func take_damage(amount: float) -> float:
	if not active:
		return 0.0
	var mitigated: float = maxf(1.0, amount - armor * 0.6)
	if failsafe_enabled and not failsafe_used and mitigated >= hp and hp > 0.0:
		failsafe_used = true
		failsafe_popped = true
		hp = 1.0
		hp_changed.emit(hp, max_hp)
		return mitigated
	hp = maxf(0.0, hp - mitigated)
	hp_changed.emit(hp, max_hp)
	if hp <= 0.0:
		end_run(false)
	return mitigated

func heal(amount: float) -> void:
	hp = minf(max_hp, hp + amount)
	hp_changed.emit(hp, max_hp)

func spend_energy(amount: float) -> bool:
	if energy < amount:
		return false
	energy -= amount
	energy_changed.emit(energy, max_energy)
	return true

func regen(delta: float) -> void:
	var changed := false
	if energy < max_energy:
		energy = minf(max_energy, energy + 14.0 * delta)
		changed = true
	if changed:
		energy_changed.emit(energy, max_energy)

func gain_xp(amount: int) -> void:
	run_xp += amount
	xp_earned += amount
	var need := GameDB.xp_for_level(run_level)
	while run_xp >= need:
		run_xp -= need
		run_level += 1
		bonus_hp += 8.0
		level_dmg *= 1.05
		_recalc_stats()
		hp = minf(max_hp, hp + max_hp * 0.4)
		hp_changed.emit(hp, max_hp)
		leveled_up.emit(run_level)
		need = GameDB.xp_for_level(run_level)
	xp_changed.emit(run_xp, run_level, origin)

func register_kill(enemy: Dictionary) -> void:
	kills += 1
	var xp: int = int(float(enemy.get("xp", 10)) * (1.0 + 0.15 * float(threat - 1)))
	var creds: int = int(float(enemy.get("creds", 5)) * (1.0 + 0.2 * float(threat - 1)))
	credits_earned += creds
	kill_confirmed.emit(String(enemy.get("name", "foe")), xp)
	gain_xp(xp)
	credits_changed.emit(credits_earned)
	if lifesteal > 0.0:
		heal(max_hp * lifesteal)
	if kill_heal > 0.0:
		heal(kill_heal)

func register_loot(item: Dictionary) -> void:
	loot_earned.append(item)
	loot_dropped.emit(item)

func end_run(victory: bool) -> Dictionary:
	if not active:
		return {}
	active = false
	extracted = victory
	var res := SaveSystem.add_xp(origin, xp_earned)
	SaveSystem.add_credits(credits_earned + int(contract.get("reward", 0)) if victory else credits_earned)
	SaveSystem.profile["runs"] = int(SaveSystem.profile.get("runs", 0)) + 1
	SaveSystem.profile["kills"] = int(SaveSystem.profile.get("kills", 0)) + kills
	if not victory:
		SaveSystem.profile["deaths"] = int(SaveSystem.profile.get("deaths", 0)) + 1
	if victory:
		var cidx: int = int(SaveSystem.profile.get("contracts_unlocked", 1))
		SaveSystem.profile["contracts_unlocked"] = mini(6, maxi(cidx, _contract_index() + 1))
		SaveSystem.profile["best_threat"] = maxi(int(SaveSystem.profile.get("best_threat", 0)), threat)
	SaveSystem.save_profile()
	var summary := {"victory": victory, "kills": kills, "xp": xp_earned,
		"credits": credits_earned, "loot": loot_earned.size(),
		"levels_gained": res[0], "new_level": res[1], "rooms": rooms_cleared}
	run_ended.emit(victory, summary)
	return summary

func _contract_index() -> int:
	for i in GameDB.CONTRACTS.size():
		if String(GameDB.CONTRACTS[i]["id"]) == String(contract.get("id", "")):
			return i
	return 0
