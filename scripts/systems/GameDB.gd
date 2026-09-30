extends Node
## GameDB — static data authority for WIRECRAWL.
## Weapons, armor sets, programs, origins, enemies, contracts, synergies, tuning.
## Pure data + balance formulas. No scene-tree dependencies.

const VERSION := "0.15"

const DAMAGE_TYPES := ["kinetic", "thermal", "volt", "cryo", "toxic", "void"]
const DAMAGE_COLORS := {
	"kinetic": Color(0.85, 0.85, 0.9),
	"thermal": Color(1.0, 0.42, 0.15),
	"volt": Color(0.25, 0.9, 1.0),
	"cryo": Color(0.55, 0.8, 1.0),
	"toxic": Color(0.45, 1.0, 0.35),
	"void": Color(1.0, 0.16, 0.43),
}

const RARITY_ORDER := ["common", "rare", "epic", "legendary", "mythic"]
const RARITY_COLORS := {
	"common": Color(0.7, 0.7, 0.75),
	"rare": Color(0.3, 0.6, 1.0),
	"epic": Color(0.75, 0.35, 1.0),
	"legendary": Color(1.0, 0.65, 0.15),
	"mythic": Color(1.0, 0.16, 0.43),
}
const RARITY_WEIGHT_BASE := {"common": 52.0, "rare": 28.0, "epic": 13.0, "legendary": 5.5, "mythic": 1.5}
const RARITY_POWER := {"common": 1.0, "rare": 1.18, "epic": 1.42, "legendary": 1.75, "mythic": 2.2}

const MELEE_STAMINA_COST := 25.0
const MAG_SIZE := {"smg": 40, "scattergun": 6, "railspike": 5, "plasma": 12,
	"thumper": 4, "cryo": 30, "toxin": 20}
const RELOAD_TIME := {"smg": 1.3, "scattergun": 1.8, "railspike": 1.6, "plasma": 1.5,
	"thumper": 2.0, "cryo": 1.3, "toxin": 1.6}

const ORIGINS := {
	"solo": {
		"name": "Street Solo",
		"desc": "Chrome muscle. +25 max HP, +15% melee damage, +30 stamina. Starts with Scattergun + Katana.",
		"hp": 125, "energy": 100, "speed": 7.2,
		"mods": {"max_hp": 25, "melee_mult": 1.15, "lifesteal": 0.02, "stamina_max": 30, "stamina_regen": 1.3},
		"program": "overdrive", "weapon": "katana",
		"color": Color(1.0, 0.16, 0.43),
	},
	"netrunner": {
		"name": "Netrunner",
		"desc": "Ice and daemons. +30 max energy, faster cooldowns, starts with System Shock.",
		"hp": 95, "energy": 130, "speed": 7.0,
		"mods": {"max_energy": 30, "cdr": 0.20, "program_power": 1.25},
		"program": "system_shock", "weapon": "smg",
		"color": Color(0.25, 0.9, 1.0),
	},
	"techie": {
		"name": "Techie",
		"desc": "Turret tinkerer. Ally damage +40%, +10 armor, 20% faster reloads. Starts with ICE Turret.",
		"hp": 110, "energy": 110, "speed": 6.8,
		"mods": {"armor": 10, "ally_mult": 1.4, "thorns": 4.0, "reload_mult": 0.8},
		"program": "ice_turret", "weapon": "railspike",
		"color": Color(0.976, 0.941, 0.008),
	},
}

const WEAPONS := {
	"katana": {"name": "Street Katana", "slot": "melee", "dmg": 26.0, "rate": 2.1, "range": 3.2,
		"dmg_type": "kinetic", "desc": "Fast mono-edge slashes. High crit (20%).",
		"crit": 0.20, "projectile": false, "spread": 0.0, "pellets": 1},
	"whip": {"name": "Mono Whip", "slot": "melee", "dmg": 18.0, "rate": 2.8, "range": 4.6,
		"dmg_type": "volt", "desc": "Arcing whip that chains to 2 targets.",
		"crit": 0.12, "projectile": false, "spread": 0.0, "pellets": 1, "chain": 2},
	"scattergun": {"name": "Scattergun", "slot": "primary", "dmg": 9.0, "rate": 1.4, "range": 14.0,
		"dmg_type": "kinetic", "desc": "6-pellet spread. Devastating close up.",
		"crit": 0.08, "projectile": true, "spread": 0.16, "pellets": 6, "speed": 34.0},
	"smg": {"name": "Hornet SMG", "slot": "primary", "dmg": 8.0, "rate": 9.0, "range": 20.0,
		"dmg_type": "kinetic", "desc": "Bullet hose. Applies statuses fast.",
		"crit": 0.10, "projectile": true, "spread": 0.07, "pellets": 1, "speed": 42.0},
	"railspike": {"name": "Railspike Rifle", "slot": "primary", "dmg": 55.0, "rate": 1.1, "range": 34.0,
		"dmg_type": "volt", "desc": "Piercing hypersonic spike. 100% pierce.",
		"crit": 0.25, "projectile": true, "spread": 0.0, "pellets": 1, "speed": 70.0, "pierce": 99},
	"plasma": {"name": "Plasma Caster", "slot": "heavy", "dmg": 34.0, "rate": 2.2, "range": 22.0,
		"dmg_type": "thermal", "desc": "Explosive plasma orbs (splash 3m).",
		"crit": 0.12, "projectile": true, "spread": 0.03, "pellets": 1, "speed": 26.0, "splash": 3.0},
	"thumper": {"name": "Thumper GL", "slot": "heavy", "dmg": 60.0, "rate": 0.8, "range": 20.0,
		"dmg_type": "thermal", "desc": "Arcing grenades, big splash 4.5m.",
		"crit": 0.05, "projectile": true, "spread": 0.02, "pellets": 1, "speed": 20.0, "splash": 4.5, "arc": true},
	"blackice": {"name": "BlackIce Edge", "slot": "melee", "dmg": 70.0, "rate": 1.2, "range": 3.6,
		"dmg_type": "void", "desc": "Legendary daemon blade. Marked targets take +50%.",
		"crit": 0.30, "projectile": false, "spread": 0.0, "pellets": 1, "mark_bonus": 1.5},
	"cryo": {"name": "Frostbite Needler", "slot": "primary", "dmg": 11.0, "rate": 5.0, "range": 19.0,
		"dmg_type": "cryo", "desc": "Applies Chilled fast. Shatter setup.",
		"crit": 0.12, "projectile": true, "spread": 0.05, "pellets": 1, "speed": 38.0},
	"toxin": {"name": "Miasma Sprayer", "slot": "heavy", "dmg": 14.0, "rate": 3.5, "range": 12.0,
		"dmg_type": "toxic", "desc": "Corroding cone. Melts armor.",
		"crit": 0.08, "projectile": true, "spread": 0.22, "pellets": 4, "speed": 24.0},
}

const AFFIXES := [
	{"id": "volt_core", "name": "Volt Core", "desc": "+30% dmg as Volt, 15% Shock on hit",
		"tags": ["dmg", "volt"], "weight": 10.0},
	{"id": "pyro_core", "name": "Pyro Core", "desc": "+30% dmg as Thermal, 15% Burn on hit",
		"tags": ["dmg", "thermal"], "weight": 10.0},
	{"id": "cryo_core", "name": "Cryo Core", "desc": "+30% dmg as Cryo, 15% Chill on hit",
		"tags": ["dmg", "cryo"], "weight": 10.0},
	{"id": "toxin_core", "name": "Toxin Core", "desc": "+30% dmg as Toxic, 15% Corrode on hit",
		"tags": ["dmg", "toxic"], "weight": 10.0},
	{"id": "void_edge", "name": "Void Edge", "desc": "+25% Void dmg, +10% crit vs Marked",
		"tags": ["dmg", "void", "crit"], "weight": 5.0},
	{"id": "crit_optic", "name": "Crit Optic", "desc": "+15% crit chance, +40% crit damage",
		"tags": ["crit"], "weight": 9.0},
	{"id": "fast_hands", "name": "Fast Hands", "desc": "+22% attack speed",
		"tags": ["speed"], "weight": 9.0},
	{"id": "vampire", "name": "Vampire Rig", "desc": "Heal 3% of damage dealt",
		"tags": ["sustain"], "weight": 7.0},
	{"id": "chain", "name": "Arc Chain", "desc": "Hits chain to +1 nearby enemy (50% dmg)",
		"tags": ["chain"], "weight": 6.0},
	{"id": "splash", "name": "Splash Core", "desc": "+2m explosion on hit (60% dmg)",
		"tags": ["splash"], "weight": 6.0},
	{"id": "pierce", "name": "Pierce Mod", "desc": "Shots pierce +2 targets",
		"tags": ["pierce"], "weight": 6.0},
	{"id": "execute", "name": "Executioner", "desc": "+60% dmg to enemies below 30% HP",
		"tags": ["execute"], "weight": 5.0},
	{"id": "overclocked", "name": "Overclock Slot", "desc": "+45% damage, -10 max HP cost",
		"tags": ["risk"], "weight": 5.0},
	{"id": "multishot", "name": "Multishot", "desc": "+1 projectile, -12% damage",
		"tags": ["projectile"], "weight": 5.0},
	{"id": "shield", "name": "Aegis Weave", "desc": "+25 max shield, +3 armor",
		"tags": ["defense"], "weight": 7.0},
	{"id": "haste_kill", "name": "Kill Haste", "desc": "+35% speed for 3s on kill",
		"tags": ["speed"], "weight": 6.0},
	{"id": "big_mag", "name": "Drum Mag", "desc": "+50% magazine size",
		"tags": ["ammo"], "weight": 6.0},
	{"id": "marathon", "name": "Marathon Weave", "desc": "+40 max stamina, +30% stamina regen",
		"tags": ["stamina"], "weight": 6.0},
]

const ARMOR_SETS := {
	"solo": {"name": "Berserker Chrome", "color": Color(1.0, 0.16, 0.43),
		"bonus2": "+15% damage, +10% lifesteal on takedown",
		"bonus3": "Overdrive also grants 3s invulnerability"},
	"netrunner": {"name": "Daemon Weave", "color": Color(0.25, 0.9, 1.0),
		"bonus2": "Programs apply Marked; Marked take +25%",
		"bonus3": "On boss kill, spawn a friendly Glitch Hound"},
	"techie": {"name": "Forge Plate", "color": Color(0.976, 0.941, 0.008),
		"bonus2": "Allies +50% damage, turret +1 barrel",
		"bonus3": "Turret revives you once per run (50% HP)"},
	"ghost": {"name": "Ghost Skin", "color": Color(0.55, 0.8, 1.0),
		"bonus2": "Dash leaves a decoy; +20% dodge window",
		"bonus3": "Below 25% HP: 4s cloak + full energy"},
}

const PROGRAMS := {
	"blink": {"name": "Blink Dash", "cd": 3.0, "cost": 0.0,
		"desc": "Phase-dash in aim direction. i-frames 0.35s. (All rigs)",
		"icon": "»"},
	"ice_turret": {"name": "ICE Turret", "cd": 14.0, "cost": 30.0,
		"desc": "Deploy auto-turret 20s. Scales with program power.",
		"icon": "⌖"},
	"blackout": {"name": "Blackout Grenade", "cd": 10.0, "cost": 25.0,
		"desc": "EMP blast: heavy Volt dmg + Shock + blind.",
		"icon": "✸"},
	"overdrive": {"name": "Overdrive", "cd": 22.0, "cost": 0.0,
		"desc": "+60% dmg & speed, drain HP. Berserker fantasy.",
		"icon": "▲"},
	"hound": {"name": "Glitch Hound", "cd": 25.0, "cost": 45.0,
		"desc": "Summon melee daemon ally 30s. Taunts enemies.",
		"icon": "◆"},
	"system_shock": {"name": "System Shock", "cd": 9.0, "cost": 20.0,
		"desc": "Chain lightning to 5 targets. Applies Marked.",
		"icon": "⚡"},
}

const ENEMIES := {
	"punk": {"name": "Street Punk", "hp": 45.0, "dmg": 10.0, "speed": 5.0, "xp": 12,
		"creds": 6, "behavior": "chaser", "color": Color(1.0, 0.35, 0.2), "scale": 1.0},
	"razor": {"name": "Razor Girl", "hp": 32.0, "dmg": 14.0, "speed": 8.5, "xp": 15,
		"creds": 8, "behavior": "dasher", "color": Color(1.0, 0.16, 0.43), "scale": 0.9},
	"drone": {"name": "Spotter Drone", "hp": 28.0, "dmg": 8.0, "speed": 4.5, "xp": 14,
		"creds": 9, "behavior": "shooter", "color": Color(0.25, 0.9, 1.0), "scale": 0.8, "flying": true},
	"enforcer": {"name": "Corp Enforcer", "hp": 130.0, "dmg": 18.0, "speed": 3.8, "xp": 30,
		"creds": 18, "behavior": "tank", "color": Color(0.976, 0.65, 0.1), "scale": 1.35},
	"hexer": {"name": "Hexer", "hp": 60.0, "dmg": 12.0, "speed": 3.2, "xp": 26,
		"creds": 16, "behavior": "shooter", "color": Color(0.75, 0.35, 1.0), "scale": 1.0, "status": "corroded"},
	"brute": {"name": "Cyber Brute", "hp": 260.0, "dmg": 26.0, "speed": 3.0, "xp": 55,
		"creds": 30, "behavior": "tank", "color": Color(1.0, 0.42, 0.15), "scale": 1.7},
	"boss_netdaemon": {"name": "NET DAEMON", "hp": 1400.0, "dmg": 30.0, "speed": 3.4, "xp": 600,
		"creds": 400, "behavior": "boss", "color": Color(1.0, 0.16, 0.43), "scale": 2.4},
	"boss_chromedragon": {"name": "CHROME DRAGON", "hp": 2200.0, "dmg": 36.0, "speed": 4.2, "xp": 1000,
		"creds": 700, "behavior": "boss", "color": Color(0.976, 0.941, 0.008), "scale": 2.8},
}

const SYNERGIES := [
	{"id": "superconduct", "name": "SUPERCONDUCT",
		"combo": ["shocked", "chilled"], "result": "superconduct",
		"desc": "Volt+Chill: 80 Volt burst + chains to 3, +50% crit taken 4s"},
	{"id": "plasma_burn", "name": "PLASMA BURN",
		"combo": ["burning", "corroded"], "result": "plasma",
		"desc": "Fire+Toxic: 4s plasma DoT + 4m explosion on death"},
	{"id": "shatter", "name": "SHATTER",
		"combo": ["chilled", "kinetic_hit"], "result": "shatter",
		"desc": "Heavy Kinetic vs Chilled: +100% dmg, executes below 20%"},
	{"id": "meltdown", "name": "MELTDOWN",
		"combo": ["marked", "void_hit"], "result": "meltdown",
		"desc": "Void vs Marked: +50% dmg, spreads Marked to 3 nearby"},
	{"id": "feedback", "name": "FEEDBACK LOOP",
		"combo": ["shocked", "overclocked"], "result": "feedback",
		"desc": "Shock while Overdriven: refund 50% energy, +25% rate 3s"},
	{"id": "frostbite", "name": "BLACK ICE",
		"combo": ["chilled", "void_hit"], "result": "frozen",
		"desc": "Void vs Chilled: Freeze 2.5s (bosses: 60% slow)"},
]

const CONTRACTS := [
	{"id": "c1", "name": "RAT HOLE", "sector": "The Undergrid",
		"threat": 1, "rooms": 7, "boss": "", "desc": "Clear the Undergrid service tunnels. Light resistance.",
		"mods": [], "reward": 150},
	{"id": "c2", "name": "NEON MARKET", "sector": "Kabuki Bazaar",
		"threat": 2, "rooms": 9, "boss": "", "desc": "Punks + drones. Shock-heavy. Watch the Hexers.",
		"mods": ["shocked_foes"], "reward": 300},
	{"id": "c3", "name": "DATA FORTRESS", "sector": "Arasaka Relay",
		"threat": 3, "rooms": 10, "boss": "boss_netdaemon", "desc": "BOSS: NET DAEMON. Bring Volt resist and burst.",
		"mods": ["tank_foes"], "reward": 600},
	{"id": "c4", "name": "CHROME FOUNDRIES", "sector": "Iron Sump",
		"threat": 4, "rooms": 12, "boss": "", "desc": "Brutes and Enforcers. Fire + armor shred.",
		"mods": ["tank_foes", "burning_foes"], "reward": 900},
	{"id": "c5", "name": "BLACK WALL", "sector": "Null Zone",
		"threat": 5, "rooms": 13, "boss": "boss_netdaemon", "desc": "Void-touched. Everything hits harder. Mythic odds up.",
		"mods": ["void_foes", "fast_foes"], "reward": 1400},
	{"id": "c6", "name": "DRAGON'S LAIR", "sector": "Skyline Spire",
		"threat": 6, "rooms": 14, "boss": "boss_chromedragon", "desc": "FINAL: CHROME DRAGON. Max threat. Best loot.",
		"mods": ["tank_foes", "fast_foes", "void_foes"], "reward": 2200},
]

const CYBERWARE_TRACKS := {
	"muscle": {"name": "Muscle Weave", "color": Color(1.0, 0.16, 0.43),
		"per_level": ["+8% damage", "+12 max HP", "+10% dmg / +8 HP", "+15% crit dmg", "+12% dmg, +5% lifesteal"]},
	"ice": {"name": "Neural ICE", "color": Color(0.25, 0.9, 1.0),
		"per_level": ["+10% program power", "-8% cooldowns", "+25 energy", "programs chain +1", "-20% cds, +20% power"]},
	"ghost": {"name": "Ghost Protocol", "color": Color(0.55, 0.8, 1.0),
		"per_level": ["+5% speed", "+15% dodge window", "+1 dash charge", "+20% status dmg", "cloak on kill (1s)"]},
}

# ---- Balance formulas (single source of truth; mirrored in rust_ext) ----
static func xp_for_level(level: int) -> int:
	return int(80.0 * pow(float(level), 1.55) + 40.0 * float(level))

static func threat_hp_mult(threat: int) -> float:
	return 1.0 + 0.45 * float(threat - 1)

static func threat_dmg_mult(threat: int) -> float:
	return 1.0 + 0.22 * float(threat - 1)

static func loot_rarity_roll(rng: RandomNumberGenerator, luck: float, threat: int) -> String:
	var w := RARITY_WEIGHT_BASE.duplicate()
	var luck_boost: float = clampf(luck, 0.0, 3.0)
	w["legendary"] += luck_boost * 2.0 + float(threat) * 0.5
	w["mythic"] += luck_boost * 0.8 + float(maxi(0, threat - 3)) * 0.7
	w["epic"] += float(threat) * 0.6
	w["common"] = maxf(8.0, w["common"] - float(threat) * 3.0 - luck_boost * 4.0)
	var total := 0.0
	for k in w:
		total += w[k]
	var r: float = rng.randf() * total
	for k in RARITY_ORDER:
		r -= w[k]
		if r <= 0.0:
			return k
	return "common"

static func weapon_dps(base: Dictionary, rarity: String, threat: int) -> float:
	var mult: float = RARITY_POWER.get(rarity, 1.0)
	return float(base["dmg"]) * float(base["rate"]) * mult * (1.0 + 0.08 * float(threat))
