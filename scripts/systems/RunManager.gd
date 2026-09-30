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
var loadout := {"primary": {}, "armor": [], "programs": ["blink"]}
var statuses := {}

func start_run(p_origin: String, p_contract: Dictionary, primary: Dictionary, armor_pieces: Array, programs: Array) -> void:
	origin = p_origin
	contract = p_contract
	threat = int(p_contract.get("threat", 1))
	var base: Dictionary = GameDB.ORIGINS[origin]
	var cw: Dictionary = SaveSystem.cyberware_bonus()
	max_hp = float(base["hp"]) + float(base["mods"].get("max_hp", 0)) + cw["max_hp"] + float(SaveSystem.origin_level(origin) - 1) * 6.0
	max_energy = float(base["energy"]) + float(base["mods"].get("max_energy", 0)) + float(cw["max_energy"])
	hp = max_hp
	energy = max_energy
	armor = float(base["mods"].get("armor", 0))
	speed_mult = float(cw["speed"])
	dmg_mult = float(cw["dmg_mult"]) * float(base["mods"].get("melee_mult", 1.0))
	program_power = float(cw["program_power"]) * float(base["mods"].get("program_power", 1.0))
	cdr = clampf(float(cw["cdr"]) + float(base["mods"].get("cdr", 0.0)), 0.0, 0.5)
	lifesteal = float(base["mods"].get("lifesteal", 0.0))
	luck = 0.0
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
	loadout = {"primary": primary, "armor": armor_pieces, "programs": programs}
	statuses = SynergyEngine.empty_statuses()
	active = true
	_apply_armor_stats()
	objective_changed.emit("Reach the EXIT uplink — clear rooms for loot")

func _apply_armor_stats() -> void:
	for piece in loadout.get("armor", []):
		var st: Dictionary = piece.get("stats", {})
		max_hp += float(st.get("max_hp", 0))
		armor += float(st.get("armor", 0))
		max_energy += float(st.get("max_energy", 0))
		speed_mult += float(st.get("speed", 0.0))
	hp = minf(hp, max_hp)
	energy = minf(energy, max_energy)

func damage_mult_for(dmg_type: String) -> float:
	var m := dmg_mult
	if dmg_type == "melee":
		m *= 1.0
	return m

func take_damage(amount: float) -> float:
	if not active:
		return 0.0
	var mitigated: float = maxf(1.0, amount - armor * 0.6)
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
		max_hp += 8.0
		hp = minf(max_hp, hp + max_hp * 0.4)
		dmg_mult *= 1.05
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
