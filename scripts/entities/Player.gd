class_name WCPlayer
extends CharacterBody3D
## Isometric player rig: WASD move, mouse-aim, LMB fire (melee arc or guns),
## Space dash (i-frames), Q/E programs, F interact handled by Dungeon via
## collect(). Data-driven weapon + affix modifiers; statuses via SynergyEngine.

signal fired
signal dashed
signal program_cast(id: String)

var move_speed := 7.2
var aim_dir := Vector3.FORWARD
var fire_cd := 0.0
var dash_cd := 0.0
var dash_time := 0.0
var dash_dir := Vector3.ZERO
var dash_charges := 1
var iframes := 0.0
var prog_cds := {"slot1": 0.0, "slot2": 0.0}
var overdrive := 0.0
var heat := 0.0
var overheated := false
var overheat_t := 0.0
var shots_fired := 0
var cloak := 0.0
var alive := true
var statuses := {}
var weapon := {}
var wbase := {}
var programs: Array = ["blink"]
var dungeon = null
var _t := 0.0
var _body: MeshInstance3D
var _rig: Node3D
var _shell: Array = []
var _mat: StandardMaterial3D
var held: Node3D
var held_kind := "gun"
var camera: Camera3D

func _ready() -> void:
	add_to_group("player")
	collision_layer = 2
	collision_mask = 1
	statuses = SynergyEngine.empty_statuses()
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.42
	cap.height = 1.5
	shape.shape = cap
	shape.position.y = 0.75
	add_child(shape)
	_build_visual()
	_apply_run_stats()

func _build_visual() -> void:
	var tint: Color = GameDB.ORIGINS.get(RunManager.origin, {}).get("color", Color.CYAN)
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.08, 0.08, 0.12)
	_mat.emission_enabled = true
	_mat.emission = tint
	_mat.emission_energy_multiplier = 1.2
	_shell = []
	_body = _pbox(Vector3(0.8, 1.0, 0.55), Vector3(0, 0.95, 0), _mat)
	# jacket skirt
	_pbox(Vector3(0.9, 0.35, 0.65), Vector3(0, 0.35, 0), _mat)
	# chest light core
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = tint
	core_mat.emission_enabled = true
	core_mat.emission = tint
	core_mat.emission_energy_multiplier = 4.0
	core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pbox(Vector3(0.2, 0.3, 0.06), Vector3(0, 1.15, 0.29), core_mat)
	# head + visor
	_pbox(Vector3(0.45, 0.4, 0.45), Vector3(0, 1.7, 0), _mat)
	var visor_mat := StandardMaterial3D.new()
	visor_mat.albedo_color = tint
	visor_mat.emission_enabled = true
	visor_mat.emission = tint
	visor_mat.emission_energy_multiplier = 5.0
	visor_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_pbox(Vector3(0.5, 0.12, 0.06), Vector3(0, 1.72, 0.24), visor_mat)
	# shoulder lamp (origin color beacon)
	_pbox(Vector3(0.22, 0.18, 0.3), Vector3(-0.5, 1.45, 0), visor_mat)
	_pbox(Vector3(0.22, 0.3, 0.3), Vector3(0.5, 1.4, 0), _mat)
	_rebuild_held()
	# X-ray outline (inverted hull) so the rig reads through walls.
	var sil := MeshInstance3D.new()
	sil.name = "XRay"
	var sm := BoxMesh.new()
	sm.size = Vector3(0.85, 1.05, 0.6)
	sil.mesh = sm
	var smat := StandardMaterial3D.new()
	smat.albedo_color = tint
	smat.emission_enabled = true
	smat.emission = tint.lightened(0.3)
	smat.emission_energy_multiplier = 2.2
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.no_depth_test = true
	smat.cull_mode = BaseMaterial3D.CULL_FRONT
	sil.material_override = smat
	sil.position = Vector3(0, 0.95, 0)
	sil.scale = Vector3.ONE * 1.07
	sil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(sil)

func _rebuild_held() -> void:
	## Visible held weapon: mono-blade for melee archetypes, distinct gun
	## shapes per ranged archetype, glow-tinted by damage type.
	if held != null and is_instance_valid(held):
		for ch in held.get_children():
			_shell.erase(ch)
		held.queue_free()
	held = Node3D.new()
	_rig.add_child(held)
	var dtype := String(wbase.get("dmg_type", "kinetic"))
	var dcol: Color = GameDB.DAMAGE_COLORS.get(dtype, Color.WHITE)
	var darkm := StandardMaterial3D.new()
	darkm.albedo_color = Color(0.09, 0.09, 0.12)
	darkm.emission_enabled = true
	darkm.emission = Color(0.3, 0.3, 0.4)
	darkm.emission_energy_multiplier = 0.4
	darkm.metallic = 0.8
	var glowm := StandardMaterial3D.new()
	glowm.albedo_color = dcol
	glowm.emission_enabled = true
	glowm.emission = dcol
	glowm.emission_energy_multiplier = 4.0
	glowm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	if not bool(wbase.get("projectile", true)):
		held_kind = "blade"
		_hbox(Vector3(0.16, 0.2, 0.16), Vector3(0.58, 1.0, 0.4), darkm)
		_hbox(Vector3(0.07, 0.1, 1.9), Vector3(0.62, 1.05, 1.35), darkm)
		_hbox(Vector3(0.03, 0.05, 1.9), Vector3(0.62, 1.12, 1.35), glowm)
		if String(weapon.get("weapon_id", "")) == "whip":
			_hbox(Vector3(0.05, 0.05, 2.6), Vector3(0.58, 0.9, 1.7), glowm)
	else:
		held_kind = "gun"
		var wid := String(weapon.get("weapon_id", "smg"))
		var heavy := wid in ["plasma", "thumper", "toxin"]
		var long := wid in ["railspike", "plasma"]
		_hbox(Vector3(0.2, 0.24, 0.75 if not heavy else 0.95), Vector3(0.5, 0.95, 0.35), darkm)
		_hbox(Vector3(0.1, 0.1, 1.0 if long else 0.55), Vector3(0.5, 1.0, 0.95 if long else 0.8), darkm)
		_hbox(Vector3(0.14, 0.14, 0.14), Vector3(0.5, 1.0, 1.35 if long else 1.0), glowm)
		_hbox(Vector3(0.06, 0.12, 0.06), Vector3(0.5, 1.15, 0.3), glowm)
		if wid == "scattergun":
			_hbox(Vector3(0.16, 0.16, 0.4), Vector3(0.42, 1.0, 0.7), darkm)
			_hbox(Vector3(0.16, 0.16, 0.4), Vector3(0.58, 1.0, 0.7), darkm)

func _hbox(size: Vector3, pos: Vector3, mat: Material) -> void:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	held.add_child(mi)
	_shell.append(mi)

func _pbox(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	_rig.add_child(mi)
	_shell.append(mi)
	return mi

func _apply_run_stats() -> void:
	move_speed = float(GameDB.ORIGINS.get(RunManager.origin, {}).get("speed", 7.0)) * RunManager.speed_mult
	weapon = RunManager.loadout.get("primary", {})
	if weapon.is_empty():
		weapon = LootFactory.roll_weapon(1, 0.0, GameDB.ORIGINS[RunManager.origin]["weapon"], "common")
		RunManager.loadout["primary"] = weapon
	wbase = GameDB.WEAPONS.get(String(weapon.get("weapon_id", "smg")), GameDB.WEAPONS["smg"])
	programs = RunManager.loadout.get("programs", ["blink"])
	if programs.size() < 3:
		programs = (programs + ["blink", "blink", "blink"]).slice(0, 3)
	_rebuild_held()

func stat_rate_mult() -> float:
	var m := 1.0
	for a in weapon.get("affixes", []):
		if String(a["id"]) == "fast_hands":
			m *= 1.22
	if overdrive > 0.0:
		m *= 1.35
	return m

func stat_damage() -> float:
	var power: float = float(weapon.get("power", 1.0))
	var d: float = float(wbase.get("dmg", 10.0)) * power * RunManager.dmg_mult
	for a in weapon.get("affixes", []):
		match String(a["id"]):
			"overclocked": d *= 1.45
			"multishot": d *= 0.88
	if overdrive > 0.0:
		d *= 1.6
	return d

func _physics_process(delta: float) -> void:
	if not alive or not RunManager.active:
		return
	_t += delta
	RunManager.regen(delta)
	SynergyEngine.tick(statuses, delta)
	var dot: float = SynergyEngine.dot_damage(statuses, RunManager.max_hp, delta)
	if dot > 0.0:
		RunManager.take_damage(dot * 0.5)
	fire_cd -= delta
	dash_cd -= delta
	iframes -= delta
	if overheated:
		overheat_t -= delta
		if overheat_t <= 0.0:
			overheated = false
			heat = 50.0
	else:
		heat = maxf(0.0, heat - 40.0 * delta)
	if dash_time > 0.0:
		dash_time -= delta
	for k in prog_cds.keys():
		prog_cds[k] = maxf(0.0, float(prog_cds[k]) - delta * (1.0 + RunManager.cdr))
	if overdrive > 0.0:
		overdrive -= delta
		RunManager.take_damage(RunManager.max_hp * 0.015 * delta * 10.0 * 0.1)
	if cloak > 0.0:
		cloak -= delta
	# Move — screen-relative: W goes screen-up regardless of camera yaw.
	var input := Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_fwd"))
	var wish := _screen_wish(input)
	var spd: float = move_speed
	if dash_time > 0.0:
		velocity = dash_dir * move_speed * 3.4
	else:
		velocity = wish * spd
	velocity.y = -9.8
	move_and_slide()
	_update_aim()
	# face aim
	if aim_dir.length() > 0.05:
		rotation.y = lerp_angle(rotation.y, atan2(-aim_dir.x, -aim_dir.z), 14.0 * delta)
	# fire
	if Input.is_action_just_pressed("dash"):
		try_dash()
	if InputMap.has_action("swap_weapon") and Input.is_action_just_pressed("swap_weapon"):
		swap_weapon()
	if Input.is_action_just_pressed("program_1"):
		cast_program(0)
	if Input.is_action_just_pressed("program_2"):
		cast_program(1)
	if InputMap.has_action("interact") and Input.is_action_just_pressed("interact"):
		if dungeon != null and dungeon.has_method("try_hack"):
			dungeon.try_hack()
	if Input.is_action_pressed("fire") and fire_cd <= 0.0:
		try_fire()
	# cloak visual + walk bob
	var cloak_a := 0.65 if cloak > 0.0 else 0.0
	for part in _shell:
		(part as MeshInstance3D).transparency = cloak_a
	var stride: float = clampf(Vector2(velocity.x, velocity.z).length() / 7.0, 0.0, 1.5)
	_rig.position.y = absf(sin(_t * 9.0)) * 0.07 * stride

func _screen_wish(input: Vector2) -> Vector3:
	## Maps WASD to camera space: W = screen-up, D = screen-right.
	## Falls back to world mapping when no camera is attached (tests).
	if camera == null:
		var raw := Vector3(input.x, 0, input.y)
		return raw.normalized() if raw.length() > 1.0 else raw
	var fwd: Vector3 = -camera.global_transform.basis.z
	fwd.y = 0.0
	var right: Vector3 = camera.global_transform.basis.x
	right.y = 0.0
	if fwd.length() < 0.01 or right.length() < 0.01:
		var raw2 := Vector3(input.x, 0, input.y)
		return raw2.normalized() if raw2.length() > 1.0 else raw2
	var wish: Vector3 = right.normalized() * input.x - fwd.normalized() * input.y
	return wish.normalized() if wish.length() > 1.0 else wish

func _has_affix(id: String) -> bool:
	for a in weapon.get("affixes", []):
		if String(a["id"]) == id:
			return true
	return false

func _update_aim() -> void:
	var vp := get_viewport()
	if vp == null or camera == null:
		return
	var mp := vp.get_mouse_position()
	var ro := camera.project_ray_origin(mp)
	var rd := camera.project_ray_normal(mp)
	# intersect y=1 plane
	if absf(rd.y) > 0.001:
		var t: float = (1.0 - ro.y) / rd.y
		if t > 0.0:
			var hit: Vector3 = ro + rd * t
			var d: Vector3 = hit - global_position
			d.y = 0.0
			if d.length() > 0.3:
				aim_dir = d.normalized()

func try_fire() -> void:
	if overheated:
		return
	var rate: float = float(wbase.get("rate", 4.0)) * stat_rate_mult()
	fire_cd = 1.0 / rate
	shots_fired += 1
	if bool(wbase.get("projectile", true)):
		heat += 100.0 / 30.0 if String(wbase.get("slot", "primary")) == "primary" else 100.0 / 8.0
		if heat >= 100.0:
			_trigger_overheat()
	var pellets: int = int(wbase.get("pellets", 1))
	for a in weapon.get("affixes", []):
		if String(a["id"]) == "multishot":
			pellets += 1
	if bool(wbase.get("projectile", true)):
		AudioDirector.play("shoot_heavy" if wbase.get("slot") == "heavy" else "shoot")
		if dungeon != null and dungeon.has_method("spawn_flash_fx"):
			dungeon.spawn_flash_fx(global_position + Vector3(0, 1.1, 0) + aim_dir * 1.2,
				GameDB.DAMAGE_COLORS.get(String(wbase.get("dmg_type", "kinetic")), Color.WHITE))
		var spread: float = float(wbase.get("spread", 0.05))
		for i in pellets:
			var dir := aim_dir.rotated(Vector3.UP, randf_range(-spread, spread) * pellets)
			var opts := {"faction": "player", "damage": stat_damage() / maxf(1.0, float(pellets) * 0.7),
				"dmg_type": String(wbase.get("dmg_type", "kinetic")),
				"speed": float(wbase.get("speed", 36.0)),
				"color": GameDB.DAMAGE_COLORS.get(String(wbase.get("dmg_type", "kinetic")), Color.WHITE),
				"pierce": int(wbase.get("pierce", 0)) + (2 if _has_affix("pierce") else 0),
				"splash": float(wbase.get("splash", 0.0)) + (2.0 if _has_affix("splash") else 0.0),
				"arc": 6.0 if bool(wbase.get("arc", false)) else 0.0,
				"tags": _weapon_tags()}
			WCProjectile.spawn(get_parent(), global_position + Vector3(0, 1.1, 0) + aim_dir * 0.8, dir, opts)
		# chain affix handled on impact via extra tag
	else:
		AudioDirector.play("melee")
		_melee_arc(pellets)

func _lane_clear(space: PhysicsDirectSpaceState3D, to_pos: Vector3) -> bool:
	var params := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.1, 0), to_pos + Vector3(0, 1.0, 0))
	params.collision_mask = 1
	params.exclude = [get_rid()]
	return space.intersect_ray(params).is_empty()

func _weapon_tags() -> Array:
	var tags: Array = []
	for a in weapon.get("affixes", []):
		match String(a["id"]):
			"chain": tags.append("chain_affix")
			"execute": tags.append("execute_affix")
			"volt_core": tags.append("volt_core")
			"pyro_core": tags.append("pyro_core")
			"cryo_core": tags.append("cryo_core")
			"toxin_core": tags.append("toxin_core")
	return tags

func _melee_arc(pellets: int) -> void:
	var wrange: float = float(wbase.get("range", 3.2))
	var dmg: float = stat_damage()
	var dtype := String(wbase.get("dmg_type", "kinetic"))
	var chain: int = int(wbase.get("chain", 0))
	var wave := 0
	var space := get_world_3d().direct_space_state
	for e in get_tree().get_nodes_in_group("enemies"):
		if not (e is WCEnemy):
			continue
		var to: Vector3 = (e as Node3D).global_position - global_position
		to.y = 0.0
		if to.length() > wrange + 0.6:
			continue
		if to.normalized().angle_to(aim_dir) > 1.1:
			continue
		if not _lane_clear(space, (e as Node3D).global_position):
			continue
		(e as WCEnemy).take_hit(dmg, dtype, _weapon_tags() + ["melee"], global_position)
		wave += 1
		if _has_affix("chain"):
			(e as WCEnemy)._chain_lightning(1, dmg * 0.5)
		if _has_affix("splash") and dungeon != null and dungeon.has_method("spawn_blast_fx"):
			dungeon.spawn_blast_fx((e as Node3D).global_position, 2.0,
				GameDB.DAMAGE_COLORS.get(dtype, Color.WHITE))
		if _has_affix("vampire"):
			RunManager.heal(dmg * 0.03)
		if chain > 0:
			(e as WCEnemy)._chain_lightning(chain, dmg * 0.5)
	for cr in get_tree().get_nodes_in_group("crates"):
		var cto: Vector3 = (cr as Node3D).global_position - global_position
		cto.y = 0.0
		if cto.length() > wrange + 0.6:
			continue
		if cto.normalized().angle_to(aim_dir) > 1.1:
			continue
		if not _lane_clear(space, (cr as Node3D).global_position):
			continue
		(cr as WCPropCrate).take_hit(dmg, dtype, _weapon_tags() + ["melee"], global_position)
		wave += 1
	if dungeon != null and dungeon.has_method("spawn_slash_fx"):
		dungeon.spawn_slash_fx(global_position + aim_dir * 1.6, aim_dir,
			GameDB.DAMAGE_COLORS.get(dtype, Color.WHITE))
	_swing_held()
	fired.emit()

func _swing_held() -> void:
	## Visible swing: the held blade sweeps across in an arc.
	if held == null or not is_instance_valid(held):
		return
	held.rotation.y = -0.7
	var tw := held.create_tween()
	tw.tween_property(held, "rotation:y", 0.7, 0.16).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)

func swap_weapon() -> void:
	var sec: Dictionary = RunManager.loadout.get("secondary", {})
	if sec.is_empty():
		return
	RunManager.loadout["secondary"] = weapon
	RunManager.loadout["primary"] = sec
	weapon = sec
	wbase = GameDB.WEAPONS.get(String(weapon.get("weapon_id", "smg")), GameDB.WEAPONS["smg"])
	_rebuild_held()
	fire_cd = maxf(fire_cd, 0.25)
	AudioDirector.play("ui")
	if dungeon != null and dungeon.has_method("float_text"):
		dungeon.float_text(global_position + Vector3(0, 2.2, 0),
			"▶ " + String(weapon.get("name", "?")),
			GameDB.RARITY_COLORS.get(String(weapon.get("rarity", "common")), Color.WHITE))

func equip_item(item: Dictionary, slot: String) -> void:
	if slot != "primary" and slot != "secondary":
		slot = "primary"
	RunManager.loadout[slot] = item
	if slot == "primary":
		weapon = item
		wbase = GameDB.WEAPONS.get(String(item.get("weapon_id", "smg")), GameDB.WEAPONS["smg"])
		_rebuild_held()
	AudioDirector.play("levelup")
	if dungeon != null and dungeon.has_method("float_text"):
		dungeon.float_text(global_position + Vector3(0, 2.4, 0),
			"EQUIPPED [%s]: %s" % [slot.to_upper(), String(item.get("name", "?"))],
			GameDB.RARITY_COLORS.get(String(item.get("rarity", "common")), Color.WHITE))

func _trigger_overheat() -> void:
	overheated = true
	overheat_t = 1.2
	heat = 100.0
	AudioDirector.play("hurt", 1.4)
	if dungeon != null and dungeon.has_method("float_text"):
		dungeon.float_text(global_position + Vector3(0, 2.4, 0), "OVERHEAT!", Color(1.0, 0.5, 0.15))
	if dungeon != null and dungeon.has_method("spawn_impact_fx"):
		dungeon.spawn_impact_fx(global_position + Vector3(0, 1.2, 0), Color(1.0, 0.6, 0.2))

func try_dash() -> void:
	if dash_cd > 0.0:
		return
	dash_cd = 1.1
	var dir := _screen_wish(Vector2(
		Input.get_action_strength("move_right") - Input.get_action_strength("move_left"),
		Input.get_action_strength("move_back") - Input.get_action_strength("move_fwd")))
	if dir.length() < 0.1:
		dir = aim_dir
	dash_dir = dir.normalized()
	dash_time = 0.22
	iframes = 0.35
	AudioDirector.play("dash")
	dashed.emit()
	if dungeon != null and dungeon.has_method("spawn_blast_fx"):
		dungeon.spawn_blast_fx(global_position, 1.2, Color(0.3, 0.9, 1.0))

func cast_program(slot: int) -> void:
	if slot < 0 or slot >= programs.size():
		return
	var pid := String(programs[slot])
	if pid == "blink" or pid == "":
		try_dash()
		return
	var pdata: Dictionary = GameDB.PROGRAMS.get(pid, {})
	if pdata.is_empty():
		return
	var key := "slot%d" % (slot + 1)
	var cd: float = float(pdata.get("cd", 10.0)) * (1.0 - RunManager.cdr)
	if float(prog_cds.get(key, 0.0)) > 0.0:
		return
	if not RunManager.spend_energy(float(pdata.get("cost", 20.0))):
		if dungeon != null and dungeon.has_method("float_text"):
			dungeon.float_text(global_position + Vector3(0, 2.0, 0), "NO ENERGY", Color.YELLOW)
		return
	prog_cds[key] = cd
	AudioDirector.play("turret")
	match pid:
		"ice_turret":
			if dungeon != null and dungeon.has_method("deploy_turret"):
				dungeon.deploy_turret(global_position + aim_dir * 2.0, RunManager.program_power)
		"blackout":
			if dungeon != null and dungeon.has_method("blackout_blast"):
				dungeon.blackout_blast(global_position + aim_dir * 5.0, RunManager.program_power)
		"overdrive":
			overdrive = 8.0
			AudioDirector.play("levelup")
		"hound":
			if dungeon != null and dungeon.has_method("summon_hound"):
				dungeon.summon_hound(global_position + Vector3(1.5, 0, 0))
		"system_shock":
			if dungeon != null and dungeon.has_method("system_shock"):
				dungeon.system_shock(global_position, RunManager.program_power)
	program_cast.emit(pid)

func take_hit(amount: float, dmg_type: String, _tags: Array, _from: Vector3) -> void:
	if not alive or iframes > 0.0 or cloak > 0.0:
		return
	AudioDirector.play("hurt")
	var dealt: float = RunManager.take_damage(amount)
	iframes = 0.4
	if _mat != null:
		_mat.emission_energy_multiplier = 4.0
		var tw := create_tween()
		tw.tween_property(_mat, "emission_energy_multiplier", 1.2, 0.15)
	if RunManager.hp <= 0.0:
		alive = false

func collect(kind: String, amount: int, item: Dictionary) -> void:
	match kind:
		"credits":
			RunManager.credits_earned += amount
			AudioDirector.play("credits")
		"health":
			RunManager.heal(float(amount))
			AudioDirector.play("pickup")
		"energy":
			RunManager.energy = minf(RunManager.max_energy, RunManager.energy + float(amount))
			AudioDirector.play("pickup", 1.2)
		"loot":
			AudioDirector.play("levelup", 1.3)
			if dungeon != null and dungeon.has_method("offer_loot"):
				dungeon.offer_loot(item)
			else:
				RunManager.register_loot(item)
