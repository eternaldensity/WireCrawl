extends Node
## SynergyEngine — status-effect interaction resolver (data-driven combos).
## Units carry `statuses: Dictionary` (id -> remaining seconds).
## apply_hit() rolls base status, then checks SYNERGIES table for combos and
## returns a list of triggered event dicts for VFX / floating text / damage.

const STATUS_COLORS := {
	"burning": Color(1.0, 0.45, 0.12),
	"shocked": Color(0.3, 0.95, 1.0),
	"chilled": Color(0.55, 0.8, 1.0),
	"corroded": Color(0.45, 1.0, 0.35),
	"marked": Color(1.0, 0.16, 0.43),
	"frozen": Color(0.75, 0.92, 1.0),
	"superconduct": Color(0.6, 1.0, 1.0),
	"plasma": Color(1.0, 0.6, 0.15),
	"overclocked": Color(0.976, 0.941, 0.008),
	"staggered": Color(1.0, 1.0, 1.0),
}

const STATUS_DOT := {  # dps as fraction of max HP per second
	"burning": 0.030, "corroded": 0.022, "plasma": 0.055, "superconduct": 0.0,
}

func empty_statuses() -> Dictionary:
	return {"burning": 0.0, "shocked": 0.0, "chilled": 0.0, "corroded": 0.0,
		"marked": 0.0, "frozen": 0.0, "superconduct": 0.0, "plasma": 0.0,
		"overclocked": 0.0, "staggered": 0.0}

func tick(statuses: Dictionary, delta: float) -> void:
	for k in statuses.keys():
		statuses[k] = maxf(0.0, float(statuses[k]) - delta)

func has(statuses: Dictionary, id: String) -> bool:
	return float(statuses.get(id, 0.0)) > 0.0

func dot_damage(statuses: Dictionary, max_hp: float, delta: float) -> float:
	var total := 0.0
	for k in STATUS_DOT.keys():
		if has(statuses, k):
			total += float(STATUS_DOT[k]) * max_hp * delta
	return total

func apply_hit(statuses: Dictionary, dmg_type: String, tags: Array, power: float) -> Array:
	## tags may contain "kinetic_hit"/"void_hit" etc. Returns triggered events.
	var events: Array = []
	match dmg_type:
		"thermal":
			if randf() < 0.25 + power * 0.05:
				statuses["burning"] = maxf(float(statuses["burning"]), 3.0)
		"volt":
			if randf() < 0.25 + power * 0.05:
				statuses["shocked"] = maxf(float(statuses["shocked"]), 3.0)
		"cryo":
			if randf() < 0.30 + power * 0.05:
				statuses["chilled"] = maxf(float(statuses["chilled"]), 3.5)
		"toxic":
			if randf() < 0.30 + power * 0.05:
				statuses["corroded"] = maxf(float(statuses["corroded"]), 4.0)
		"void":
			statuses["marked"] = maxf(float(statuses["marked"]), 4.0)
	for combo in GameDB.SYNERGIES:
		var need: Array = combo["combo"]
		var ok := true
		for req in need:
			if req.ends_with("_hit"):
				if not tags.has(req):
					ok = false
					break
			elif not has(statuses, req):
				ok = false
				break
		if ok:
			var ev := _trigger(combo["id"], statuses)
			events.append(ev)
	return events

func _trigger(combo_id: String, statuses: Dictionary) -> Dictionary:
	match combo_id:
		"superconduct":
			statuses["shocked"] = 0.0
			statuses["superconduct"] = 4.0
			return {"id": "superconduct", "text": "SUPERCONDUCT!", "burst": 80.0,
				"dmg_type": "volt", "chain": 3, "color": STATUS_COLORS["superconduct"]}
		"plasma_burn":
			statuses["burning"] = 0.0
			statuses["plasma"] = 4.0
			return {"id": "plasma", "text": "PLASMA BURN!", "burst": 40.0,
				"dmg_type": "thermal", "explode_on_death": true, "color": STATUS_COLORS["plasma"]}
		"shatter":
			statuses["chilled"] = 0.0
			return {"id": "shatter", "text": "SHATTER!", "mult": 2.0, "execute": 0.20,
				"color": Color(0.8, 0.95, 1.0)}
		"meltdown":
			return {"id": "meltdown", "text": "MELTDOWN!", "mult": 1.5, "spread_mark": 3,
				"color": STATUS_COLORS["marked"]}
		"feedback":
			return {"id": "feedback", "text": "FEEDBACK LOOP", "energy_refund": 0.5,
				"rate_buff": 1.25, "color": STATUS_COLORS["overclocked"]}
		"frostbite":
			statuses["frozen"] = 2.5
			return {"id": "frozen", "text": "BLACK ICE!", "color": STATUS_COLORS["frozen"]}
	return {"id": combo_id, "text": combo_id.to_upper() + "!", "color": Color.WHITE}
