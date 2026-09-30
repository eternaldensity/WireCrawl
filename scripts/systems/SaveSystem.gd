extends Node
## SaveSystem — persistent meta-progression (JSON in user://).
## Profile: level/xp per origin, credits, cyberware tracks, unlocked contracts,
## best threat cleared, settings. Versioned + atomic writes.

const PATH := "user://wirecrawl_save.json"
const SAVE_VERSION := 1

var profile := {}
var loaded_ok := false

func _ready() -> void:
	load_profile()

func default_profile() -> Dictionary:
	return {
		"version": SAVE_VERSION,
		"credits": 0,
		"origins": {
			"solo": {"level": 1, "xp": 0},
			"netrunner": {"level": 1, "xp": 0},
			"techie": {"level": 1, "xp": 0},
		},
		"cyberware": {"muscle": 0, "ice": 0, "ghost": 0},
		"contracts_unlocked": 1,
		"best_threat": 0,
		"runs": 0, "kills": 0, "deaths": 0,
		"settings": {"master_vol": 0.8, "music_vol": 0.6, "sfx_vol": 0.9, "screenshake": true},
	}

func load_profile() -> void:
	if not FileAccess.file_exists(PATH):
		profile = default_profile()
		save_profile()
		loaded_ok = true
		return
	var f := FileAccess.open(PATH, FileAccess.READ)
	if f == null:
		profile = default_profile()
		loaded_ok = false
		return
	var parsed = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY or int(parsed.get("version", 0)) != SAVE_VERSION:
		profile = default_profile()
	else:
		profile = parsed
	loaded_ok = true

func save_profile() -> bool:
	var tmp := PATH + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(profile, "\t"))
	f.close()
	return DirAccess.rename_absolute(tmp, PATH) == OK

func add_xp(origin: String, amount: int) -> Array:
	## Returns [levels_gained, new_level].
	var o: Dictionary = profile["origins"].get(origin, {"level": 1, "xp": 0})
	o["xp"] = int(o.get("xp", 0)) + amount
	var gained := 0
	while int(o["xp"]) >= GameDB.xp_for_level(int(o["level"])):
		o["xp"] = int(o["xp"]) - GameDB.xp_for_level(int(o["level"]))
		o["level"] = int(o["level"]) + 1
		gained += 1
	profile["origins"][origin] = o
	save_profile()
	return [gained, int(o["level"])]

func origin_level(origin: String) -> int:
	return int(profile["origins"].get(origin, {"level": 1}).get("level", 1))

func add_credits(n: int) -> void:
	profile["credits"] = int(profile.get("credits", 0)) + n
	save_profile()

func spend_credits(n: int) -> bool:
	if int(profile.get("credits", 0)) < n:
		return false
	profile["credits"] = int(profile["credits"]) - n
	save_profile()
	return true

func buy_cyberware(track: String) -> bool:
	var lvl: int = int(profile["cyberware"].get(track, 0))
	if lvl >= 5:
		return false
	var cost := 200 + lvl * 350
	if not spend_credits(cost):
		return false
	profile["cyberware"][track] = lvl + 1
	save_profile()
	return true

func cyberware_bonus() -> Dictionary:
	## Aggregate small multiplicative bonuses from tracks.
	var cw: Dictionary = profile.get("cyberware", {})
	var m: int = int(cw.get("muscle", 0))
	var ic: int = int(cw.get("ice", 0))
	var g: int = int(cw.get("ghost", 0))
	return {
		"dmg_mult": 1.0 + 0.08 * m,
		"max_hp": 12 * m,
		"program_power": 1.0 + 0.10 * ic,
		"cdr": clampf(0.08 * ic, 0.0, 0.35),
		"max_energy": 25 * ic,
		"speed": 1.0 + 0.02 * g,
		"dodge_window": 1.0 + 0.15 * g,
	}
