extends Node
## LootFactory — procedural loot with Minecraft-Dungeons-style power curve.
## Every drop: {key, weapon_id, name, rarity, power, dps, affixes[], level_req}.
## Affix count by rarity (0/1/2/3/4), power scaling by threat + luck.
## Armor pieces: {slot, set, rarity, stats}. Consumables handled by pickup code.

var rng := RandomNumberGenerator.new()

func _ready() -> void:
	rng.randomize()

func roll_weapon(threat: int, luck := 0.0, force_id := "", force_rarity := "") -> Dictionary:
	var wid: String = force_id
	if wid == "":
		wid = GameDB.WEAPONS.keys()[rng.randi() % GameDB.WEAPONS.size()]
		# Heavies/void skew to higher threat
		if threat < 2 and GameDB.WEAPONS[wid]["slot"] == "heavy" and randf() < 0.6:
			wid = ["smg", "scattergun", "katana", "cryo"][rng.randi() % 4]
		if wid == "blackice" and (threat < 4 and force_id == "") and randf() < 0.85:
			wid = "katana"
	var rarity: String = force_rarity
	if rarity == "":
		rarity = GameDB.loot_rarity_roll(rng, luck, threat)
	var base: Dictionary = GameDB.WEAPONS[wid]
	var affix_count: int = {"common": 0, "rare": 1, "epic": 2, "legendary": 3, "mythic": 4}.get(rarity, 0)
	var affixes: Array = []
	var pool: Array = GameDB.AFFIXES.duplicate()
	while affixes.size() < affix_count and not pool.is_empty():
		var total := 0.0
		for a in pool:
			total += float(a["weight"])
		var r: float = rng.randf() * total
		var picked: Dictionary = pool[0]
		for a in pool:
			r -= float(a["weight"])
			if r <= 0.0:
				picked = a
				break
		affixes.append(picked)
		pool.erase(picked)
	var power: float = GameDB.RARITY_POWER.get(rarity, 1.0) * (1.0 + 0.12 * float(threat - 1))
	var dps: float = float(base["dmg"]) * float(base["rate"]) * power
	var has_big_mag := false
	for a in affixes:
		match String(a["id"]):
			"overclocked": dps *= 1.45
			"multishot": dps *= 1.55
			"fast_hands": dps *= 1.22
			"big_mag": has_big_mag = true
	var mag: int = int(GameDB.MAG_SIZE.get(wid, 30))
	if has_big_mag:
		mag = int(mag * 1.5)
	var item := {
		"key": "w_%d_%d" % [Time.get_ticks_msec(), rng.randi()],
		"kind": "weapon", "weapon_id": wid,
		"name": _item_name(base["name"], rarity),
		"rarity": rarity, "power": snappedf(power, 0.01),
		"dps": snappedf(dps, 0.1),
		"affixes": affixes, "threat": threat,
		"mag": mag, "ammo": mag,
	}
	return item

func roll_armor(threat: int, luck := 0.0) -> Dictionary:
	var rarity := GameDB.loot_rarity_roll(rng, luck, threat)
	var slot: String = ["core", "plating", "legs"][rng.randi() % 3]
	var set_id: String = GameDB.ARMOR_SETS.keys()[rng.randi() % GameDB.ARMOR_SETS.size()]
	var mult: float = GameDB.RARITY_POWER.get(rarity, 1.0)
	var stats := {
		"max_hp": int((10 + threat * 6) * mult) if slot != "legs" else int(6 * mult),
		"armor": int((3 + threat * 2) * mult),
		"max_energy": int(12 * mult) if slot == "core" else 0,
		"speed": snappedf(0.03 * mult, 0.001) if slot == "legs" else 0.0,
	}
	return {"key": "a_%d_%d" % [Time.get_ticks_msec(), rng.randi()],
		"kind": "armor", "slot": slot, "set": set_id,
		"name": "%s %s [%s]" % [GameDB.ARMOR_SETS[set_id]["name"],
			{"core": "Core", "plating": "Plating", "legs": "Servos"}[slot], rarity.capitalize()],
		"rarity": rarity, "stats": stats, "threat": threat, "affixes": []}

func _item_name(base_name: String, rarity: String) -> String:
	var prefixes := {"common": "", "rare": "Tuned ", "epic": "Overclocked ",
		"legendary": "Legendary ", "mythic": "MYTHIC "}
	return prefixes.get(rarity, "") + base_name

func set_bonus_count(loadout_sets: Array) -> Dictionary:
	## loadout_sets: array of set ids equipped. Returns {set_id: count}.
	var counts := {}
	for s in loadout_sets:
		counts[s] = int(counts.get(s, 0)) + 1
	return counts

func describe(item: Dictionary) -> String:
	var lines: Array = []
	lines.append("[b]%s[/b]  (%s, PWR %.2f)" % [item.get("name", "?"),
		String(item.get("rarity", "")).capitalize(), float(item.get("power", 1.0))])
	if item.get("kind") == "weapon":
		var base: Dictionary = GameDB.WEAPONS[item["weapon_id"]]
		lines.append("%s  DPS %.0f  %s" % [base["desc"], float(item.get("dps", 0)),
			String(base["dmg_type"]).to_upper()])
	for a in item.get("affixes", []):
		lines.append("◆ %s — %s" % [a["name"], a["desc"]])
	if item.get("kind") == "armor":
		lines.append("Set: %s" % GameDB.ARMOR_SETS[item["set"]]["name"])
		lines.append(str(item["stats"]))
	return "\n".join(lines)
