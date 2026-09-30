class_name WCEnemy
extends CharacterBody3D
## Modular enemy: data-driven from GameDB.ENEMIES + threat scaling.
## Behaviors: chaser (melee), dasher (lunge), shooter (ranged), tank (slow slam),
## boss (phases: summons + radial bursts + charge). Status effects via
## SynergyEngine with DoT tick, stagger, freeze/slow. Drops credits/health/loot.

signal died(enemy: WCEnemy)

var key := "punk"
var data := {}
var hp := 30.0
var max_hp := 30.0
var dmg := 8.0
var speed := 5.0
var xp := 10
var creds := 5
var behavior := "chaser"
var threat := 1
var is_boss := false
var statuses := {}
var attack_cd := 0.0
var special_cd := 4.0
var dash_cd := 2.0
var dashing := 0.0
var dash_dir := Vector3.ZERO
var target: Node3D = null
var flying := false
var dead := false
var elite := false
var innate: Array = []
var strafe_dir := 1.0
var strafe_t := 0.0
var windup := 0.0
var retarget_t := 0.0
var stuck_t := 0.0
var detour := 0.0
var detour_t := 0.0
var pace := 1.0
var _t := 0.0
var _body: MeshInstance3D
var _rig: Node3D
var _shards: Array = []
var _ring: MeshInstance3D
var _hpbg: Sprite3D
var _hpfg: Sprite3D
var _bar_t := 0.0
var _mat: StandardMaterial3D
var _base_y := 0.0
var dungeon = null

static var _bar_tex: Texture2D = null

static func bar_texture() -> Texture2D:
	if _bar_tex == null:
		var img := Image.create(16, 2, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_bar_tex = ImageTexture.create_from_image(img)
	return _bar_tex

static func spawn(parent: Node, p_key: String, pos: Vector3, p_threat: int) -> WCEnemy:
	var e := WCEnemy.new()
	e.key = p_key
	e.threat = p_threat
	parent.add_child(e)
	e.global_position = pos
	return e

func _ready() -> void:
	add_to_group("enemies")
	data = GameDB.ENEMIES.get(key, GameDB.ENEMIES["punk"])
	behavior = String(data.get("behavior", "chaser"))
	is_boss = behavior == "boss"
	flying = bool(data.get("flying", false))
	max_hp = float(data["hp"]) * GameDB.threat_hp_mult(threat)
	dmg = float(data["dmg"]) * GameDB.threat_dmg_mult(threat)
	speed = float(data["speed"])
	pace = randf_range(0.9, 1.1)
	speed *= pace
	xp = int(data["xp"])
	creds = int(data["creds"])
	hp = max_hp
	statuses = SynergyEngine.empty_statuses()
	if String(data.get("status", "")) != "":
		statuses[String(data["status"])] = 999.0  # innate aura carrier
		innate.append(String(data["status"]))  # auras never self-damage
	collision_layer = 4
	collision_mask = 1  # collide with world only (avoid enemy stacking physics)
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	var sc: float = float(data.get("scale", 1.0))
	cap.radius = 0.45 * sc
	cap.height = 1.6 * sc
	shape.shape = cap
	shape.position.y = 0.8 * sc
	add_child(shape)
	_build_visual(sc)
	target = get_tree().get_first_node_in_group("player")

func _glow(col: Color, energy := 3.0) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = col
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = energy
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m

func _armor(col: Color) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.05, 0.05, 0.09)
	m.emission_enabled = true
	m.emission = col
	m.emission_energy_multiplier = 0.9
	m.metallic = 0.75
	m.roughness = 0.35
	return m

func _box(size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	_rig.add_child(mi)
	return mi

func _build_visual(sc: float) -> void:
	var col: Color = data.get("color", Color.RED)
	_mat = _armor(col)
	_rig = Node3D.new()
	_rig.name = "Rig"
	add_child(_rig)
	var glow := _glow(col, 3.2)
	var white := _glow(Color.WHITE, 5.0)
	var dark := _armor(col.darkened(0.25))
	if flying:
		# Spotter drone: hovering core + rotor ring + sensor + antenna.
		_body = MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.45 * sc
		sm.height = 0.7 * sc
		_body.mesh = sm
		_body.material_override = _mat
		_body.position = Vector3(0, 1.6, 0)
		_rig.add_child(_body)
		var rotor := MeshInstance3D.new()
		var tm := TorusMesh.new()
		tm.inner_radius = 0.5 * sc
		tm.outer_radius = 0.68 * sc
		rotor.mesh = tm
		rotor.material_override = glow
		rotor.position = Vector3(0, 1.6, 0)
		_rig.add_child(rotor)
		var sensor := MeshInstance3D.new()
		var ssm := SphereMesh.new()
		ssm.radius = 0.14 * sc
		ssm.height = 0.28 * sc
		sensor.mesh = ssm
		sensor.material_override = white
		sensor.position = Vector3(0, 1.28, -0.15 * sc)
		_rig.add_child(sensor)
		_box(Vector3(0.06 * sc, 0.7 * sc, 0.06 * sc), Vector3(0, 2.2, 0), dark)
		_box(Vector3(0.16 * sc, 0.16 * sc, 0.16 * sc), Vector3(0, 2.6, 0), glow)
	else:
		# Humanoid base: torso + head + visor.
		var bulky := 1.35 if (behavior == "tank" or is_boss) else 1.0
		var slim := 0.75 if behavior == "dasher" else 1.0
		_body = _box(Vector3(0.9 * sc * slim * bulky, 1.1 * sc, 0.6 * sc * bulky),
			Vector3(0, 1.0 * sc, 0), _mat)
		_box(Vector3(0.5 * sc, 0.42 * sc, 0.5 * sc), Vector3(0, 1.78 * sc, 0), dark)
		_box(Vector3(0.56 * sc * slim, 0.11 * sc, 0.06), Vector3(0, 1.8 * sc, -0.26 * sc), white)
		_box(Vector3(0.7 * sc, 0.09 * sc, 0.62 * sc), Vector3(0, 0.52 * sc, 0), glow)
		match key:
			"punk":
				_box(Vector3(0.1 * sc, 0.45 * sc, 0.65 * sc), Vector3(0, 2.2 * sc, 0), glow)
				_box(Vector3(0.22 * sc, 0.8 * sc, 0.22 * sc), Vector3(-0.58 * sc, 1.0 * sc, 0), dark)
				_box(Vector3(0.22 * sc, 0.8 * sc, 0.22 * sc), Vector3(0.58 * sc, 1.0 * sc, 0), dark)
			"razor":
				var bl := _box(Vector3(0.08 * sc, 0.95 * sc, 0.28 * sc), Vector3(-0.34 * sc, 1.35 * sc, -0.3 * sc), glow)
				bl.rotation.z = 0.5
				var br := _box(Vector3(0.08 * sc, 0.95 * sc, 0.28 * sc), Vector3(0.34 * sc, 1.35 * sc, -0.3 * sc), glow)
				br.rotation.z = -0.5
			"hexer":
				var robe := MeshInstance3D.new()
				var cm := CylinderMesh.new()
				cm.top_radius = 0.3 * sc
				cm.bottom_radius = 0.75 * sc
				cm.height = 1.7 * sc
				robe.mesh = cm
				robe.material_override = dark
				robe.position = Vector3(0, 0.85 * sc, 0)
				_rig.add_child(robe)
				for si in 2:
					var shard := _box(Vector3(0.18 * sc, 0.18 * sc, 0.18 * sc),
						Vector3(1.0, 1.4, 0), _glow(Color(0.75, 0.35, 1.0), 4.0))
					_shards.append(shard)
			"enforcer", "brute":
				_box(Vector3(0.5 * sc, 0.35 * sc, 0.6 * sc), Vector3(-0.88 * sc, 1.62 * sc, 0), dark)
				_box(Vector3(0.5 * sc, 0.35 * sc, 0.6 * sc), Vector3(0.88 * sc, 1.62 * sc, 0), dark)
				_box(Vector3(0.4 * sc, 0.5 * sc, 0.1), Vector3(0, 1.15 * sc, -0.42 * sc * bulky), glow)
				_box(Vector3(0.3 * sc, 0.7 * sc, 0.3 * sc), Vector3(-0.62 * sc, 0.6 * sc, 0), dark)
				_box(Vector3(0.3 * sc, 0.7 * sc, 0.3 * sc), Vector3(0.62 * sc, 0.6 * sc, 0), dark)
			_:
				if is_boss:
					for spi in 3:
						_box(Vector3(0.14 * sc, 0.6 * sc, 0.14 * sc),
							Vector3((float(spi) - 1.0) * 0.35 * sc, 2.25 * sc, -0.1 * sc), glow)
					_box(Vector3(0.5 * sc, 0.6 * sc, 0.12), Vector3(0, 1.2 * sc, -0.45 * sc * bulky),
						_glow(Color(1.0, 0.9, 0.2), 4.5))
	# ground status ring
	_ring = MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.45 * sc
	tm.outer_radius = 0.6 * sc
	_ring.mesh = tm
	var rm := StandardMaterial3D.new()
	rm.albedo_color = col
	rm.emission_enabled = true
	rm.emission = col
	rm.emission_energy_multiplier = 2.5
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_ring.material_override = rm
	_ring.position.y = 0.06
	add_child(_ring)
	# X-ray outline: inverted hull (back faces) of the core mesh, depth-test
	# off, slightly larger — a glowing rim readable through walls.
	var sil := MeshInstance3D.new()
	sil.name = "XRay"
	sil.mesh = _body.mesh
	var smat := StandardMaterial3D.new()
	smat.albedo_color = col
	smat.emission_enabled = true
	smat.emission = col.lightened(0.3)
	smat.emission_energy_multiplier = 2.2
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.no_depth_test = true
	smat.cull_mode = BaseMaterial3D.CULL_FRONT
	sil.material_override = smat
	sil.position = _body.position
	sil.scale = Vector3.ONE * 1.07
	sil.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_rig.add_child(sil)
	# floating HP bar (bosses use the HUD bar instead)
	if not is_boss:
		_hpbg = Sprite3D.new()
		_hpbg.texture = bar_texture()
		_hpbg.pixel_size = 0.05
		_hpbg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_hpbg.modulate = Color(0, 0, 0, 0.7)
		_hpbg.position = Vector3(0, 2.35 * sc, 0)
		_hpbg.visible = false
		add_child(_hpbg)
		_hpfg = Sprite3D.new()
		_hpfg.texture = bar_texture()
		_hpfg.pixel_size = 0.05
		_hpfg.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		_hpfg.modulate = Color(0.2, 1.0, 0.3) if not elite else Color(0.976, 0.941, 0.008)
		_hpfg.position = Vector3(0, 2.35 * sc, 0)
		_hpfg.visible = false
		add_child(_hpfg)
	if is_boss:
		AudioDirector.play("boss")
	# materialize-in effect
	scale = Vector3.ONE * 0.05
	var pop := create_tween()
	pop.tween_property(self, "scale", Vector3.ONE, 0.32).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

func make_elite() -> void:
	## Champion modifier: +80% HP, +25% dmg, gold ring, bonus loot on death.
	if elite or is_boss:
		return
	elite = true
	max_hp *= 1.8
	hp = max_hp
	dmg *= 1.25
	xp *= 2
	creds *= 2
	scale *= 1.18
	if _hpfg != null:
		_hpfg.modulate = Color(0.976, 0.941, 0.008)
	if _ring != null:
		var rm := _ring.material_override as StandardMaterial3D
		rm.emission = Color(0.976, 0.941, 0.008)
		rm.albedo_color = rm.emission

func _physics_process(delta: float) -> void:
	if dead:
		return
	_t += delta
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")
		if target == null:
			return
	# occasionally pick up an ally/drone instead of the player
	retarget_t -= delta
	if retarget_t <= 0.0:
		retarget_t = 2.5
		if randf() < 0.3:
			var best: Node3D = null
			var best_d := 9.0
			for a in get_tree().get_nodes_in_group("allies"):
				if not (a is WCAlly) or (a as WCAlly).dead_flag:
					continue
				var d: float = global_position.distance_to((a as Node3D).global_position)
				if d < best_d:
					best_d = d
					best = a
			if best != null:
				target = best
			elif not target.is_in_group("player"):
				target = get_tree().get_first_node_in_group("player")
	# Status tick
	SynergyEngine.tick(statuses, delta)
	var dot: float = SynergyEngine.dot_damage(statuses, max_hp, delta, innate)
	if dot > 0.0:
		_damage_raw(dot)
		if hp <= 0.0:
			_die()
			return
	var slowed := 1.0
	if SynergyEngine.has(statuses, "chilled"):
		slowed *= 0.7
	if SynergyEngine.has(statuses, "frozen"):
		slowed = 0.0
	if SynergyEngine.has(statuses, "staggered"):
		slowed *= 0.4
	attack_cd -= delta
	special_cd -= delta
	dash_cd -= delta
	var to_t: Vector3 = target.global_position - global_position
	to_t.y = 0.0
	var dist := to_t.length()
	var dir := Vector3.ZERO
	if dist > 0.05:
		dir = to_t / dist
	var vel := Vector3.ZERO
	match behavior:
		"chaser", "tank":
			if dist > (1.6 if behavior == "chaser" else 2.2):
				vel = dir * speed * slowed
			elif attack_cd <= 0.0:
				_melee(dir)
		"dasher":
			if windup > 0.0:
				windup -= delta
				vel = Vector3.ZERO
				if _mat != null:
					_mat.emission_energy_multiplier = 3.0 + sin(_t * 30.0) * 1.5
				if windup <= 0.0:
					dashing = 0.35
					dash_cd = 2.4
					dash_dir = dir
					if _mat != null:
						_mat.emission_energy_multiplier = 0.9
					AudioDirector.play("dash", 0.7)
			elif dashing > 0.0:
				dashing -= delta
				vel = dash_dir * speed * 3.2
			elif dist < 9.0 and dist > 2.0 and dash_cd <= 0.0 and _los_clear(target.global_position):
				windup = 0.45  # telegraph: glow strobes, then lunge
				AudioDirector.play("dash", 0.5)
			elif dist > 1.7:
				vel = dir * speed * slowed
			elif attack_cd <= 0.0:
				_melee(dir)
		"shooter":
			strafe_t -= delta
			if strafe_t <= 0.0:
				strafe_t = randf_range(1.5, 3.0)
				strafe_dir = -strafe_dir
			var clear := _los_clear(target.global_position)
			if dist > 16.0 or not clear:
				vel = dir * speed * slowed  # reposition for a lane
			elif dist < 7.0:
				vel = -dir * speed * 0.7 * slowed
			else:
				vel = dir.rotated(Vector3.UP, PI / 2.0) * strafe_dir * speed * 0.45 * slowed
			if attack_cd <= 0.0 and dist < 22.0 and clear:
				_shoot(dir)
		"boss":
			_boss_brain(delta, dir, dist, slowed)
			vel = _boss_vel(dir, dist, slowed)
	velocity.x = vel.x
	velocity.z = vel.z
	velocity.y = -9.8 if not flying else 0.0
	# separation from other enemies (cheap, no physics dependency)
	for o in get_tree().get_nodes_in_group("enemies"):
		if o == self:
			continue
		var d: Vector3 = global_position - (o as Node3D).global_position
		d.y = 0.0
		var l := d.length()
		if l > 0.01 and l < 2.1:
			velocity += d / l * 4.5
	# unstick: pushing into a wall means walk along it for a bit
	if is_on_wall() and Vector2(vel.x, vel.z).length() > 0.5:
		stuck_t += delta
	else:
		stuck_t = maxf(0.0, stuck_t - delta * 2.0)
	if detour_t > 0.0:
		detour_t -= delta
		if dir.length() > 0.01:
			var side: Vector3 = dir.rotated(Vector3.UP, detour * PI / 2.0)
			velocity.x = side.x * speed * slowed
			velocity.z = side.z * speed * slowed
		if detour_t <= 0.0 or _los_clear(target.global_position):
			detour = 0.0
	elif stuck_t > 0.5 and dir.length() > 0.01:
		detour = 1.0 if randf() < 0.5 else -1.0
		detour_t = randf_range(0.6, 1.2)
		stuck_t = 0.0
	move_and_slide()
	# face target
	if dir.length() > 0.01:
		var yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, 10.0 * delta)
	# procedural locomotion: bob + sway (+ shard orbit, hover)
	var move_amount: float = clampf(Vector2(velocity.x, velocity.z).length() / maxf(speed, 0.1), 0.0, 1.5)
	if flying:
		_rig.position.y = sin(_t * 4.0) * 0.15
	else:
		_rig.position.y = absf(sin(_t * (5.0 + 3.0 * move_amount))) * 0.09 * move_amount
		_rig.rotation.z = sin(_t * 3.0) * 0.03
	if not _shards.is_empty():
		for si in _shards.size():
			var s := _shards[si] as MeshInstance3D
			var a := _t * 2.2 + TAU * float(si) / float(_shards.size())
			s.position = Vector3(cos(a) * 1.1, 1.4 + sin(_t * 3.0 + float(si)) * 0.15, sin(a) * 1.1)
	if _hpfg != null:
		if _bar_t > 0.0:
			_bar_t -= delta
			_hpbg.visible = true
			_hpfg.visible = true
			var frac := clampf(hp / maxf(max_hp, 1.0), 0.0, 1.0)
			_hpfg.scale = Vector3(maxf(frac, 0.001), 1.0, 1.0)
			_hpfg.position.x = -0.4 * (1.0 - frac)
			if not elite:
				_hpfg.modulate = Color(1.0 - frac, 0.1 + frac * 0.9, 0.2)
		else:
			_hpbg.visible = false
			_hpfg.visible = false
	_update_ring()

func _boss_vel(dir: Vector3, dist: float, slowed: float) -> Vector3:
	if dashing > 0.0:
		return dash_dir * speed * 4.0
	if dist > 3.0:
		return dir * speed * slowed
	return Vector3.ZERO

func _boss_brain(delta: float, dir: Vector3, dist: float, slowed: float) -> void:
	if dashing > 0.0:
		dashing -= delta
		return
	var phase := 1.0 - hp / max_hp  # 0..1 enrage
	if dist < 3.4 and attack_cd <= 0.0:
		_melee(dir)
	if special_cd <= 0.0:
		special_cd = lerpf(5.0, 2.6, phase)
		var roll := randf()
		if roll < 0.45:
			_radial_burst()
		elif roll < 0.75:
			dashing = 0.6
			dash_dir = dir
			dash_cd = 1.5
			AudioDirector.play("dash", 0.6)
		else:
			_summon_adds()

func _los_clear(to_pos: Vector3) -> bool:
	## True when no world geometry blocks the shot/melee lane.
	var params := PhysicsRayQueryParameters3D.create(
		global_position + Vector3(0, 1.2, 0), to_pos + Vector3(0, 1.0, 0))
	params.collision_mask = 1
	params.exclude = [get_rid()]
	var hit: Dictionary = get_world_3d().direct_space_state.intersect_ray(params)
	return hit.is_empty()

func _melee(dir: Vector3) -> void:
	attack_cd = 1.1 if not is_boss else 0.8
	AudioDirector.play("melee", 0.8)
	if target != null and target.has_method("take_hit"):
		var d: float = global_position.distance_to(target.global_position)
		if d < (2.6 if not is_boss else 4.2) and _los_clear(target.global_position):
			target.take_hit(dmg, "kinetic", ["kinetic_hit", "melee"], global_position)

func _shoot(dir: Vector3) -> void:
	attack_cd = 1.8
	AudioDirector.play("shoot", 0.7)
	var from := global_position + Vector3(0, 1.2, 0)
	WCProjectile.spawn(get_parent(), from, dir,
		{"faction": "enemy", "damage": dmg, "dmg_type": "volt",
			"speed": 16.0, "color": Color(1.0, 0.3, 0.4)})

func _radial_burst() -> void:
	AudioDirector.play("explode", 0.8)
	var n := 10 if not is_boss else 14
	for i in n:
		var a := TAU * float(i) / float(n)
		var dir := Vector3(cos(a), 0, sin(a))
		WCProjectile.spawn(get_parent(), global_position + Vector3(0, 1.2, 0), dir,
			{"faction": "enemy", "damage": dmg * 0.7, "dmg_type": "void",
				"speed": 13.0, "color": Color(1.0, 0.16, 0.43)})

func _summon_adds() -> void:
	if dungeon != null and dungeon.has_method("summon_adds"):
		dungeon.summon_adds(global_position, 2 + threat / 2)

func take_hit(amount: float, dmg_type: String, tags: Array, from_pos: Vector3) -> void:
	if dead:
		return
	_bar_t = 3.0
	var mult := 1.0
	var ttags: Array = tags.duplicate()
	if dmg_type == "kinetic":
		ttags.append("kinetic_hit")
	if dmg_type == "void":
		ttags.append("void_hit")
	if SynergyEngine.has(statuses, "marked") and dmg_type == "void":
		mult *= 1.5
	var events: Array = SynergyEngine.apply_hit(statuses, dmg_type, ttags, 1.0)
	for ev in events:
		_resolve_synergy_event(ev, amount)
		if ev.has("mult"):
			mult *= float(ev["mult"])
		if ev.get("execute", 0.0) > 0.0 and hp <= max_hp * 0.3:
			_damage_raw(max_hp)  # execution
			_die()
			return
	_damage_raw(amount * mult)
	_flash()
	# damage numbers for heavy hits and killing blows
	if dungeon != null and dungeon.has_method("spawn_damage_number"):
		if hp <= 0.0 or amount * mult >= max_hp * 0.06:
			dungeon.spawn_damage_number(global_position + Vector3(0, 2.0, 0),
				amount * mult, hp <= 0.0)
	if hp <= 0.0:
		_die()

func _resolve_synergy_event(ev: Dictionary, base_amount: float) -> void:
	AudioDirector.play("synergy")
	if dungeon != null and dungeon.has_method("float_text"):
		dungeon.float_text(global_position + Vector3(0, 2.2, 0),
			String(ev.get("text", "SYNERGY!")), ev.get("color", Color.WHITE))
	if ev.has("burst"):
		_damage_raw(float(ev["burst"]))
	if ev.get("chain", 0) > 0:
		_chain_lightning(int(ev["chain"]), base_amount * 0.5)
	if ev.get("spread_mark", 0) > 0:
		_spread_status("marked", int(ev["spread_mark"]))

func _chain_lightning(count: int, dmg_amount: float) -> void:
	var hit: Array = [self]
	var from := global_position
	for _i in count:
		var best: WCEnemy = null
		var best_d := 9.0
		for o in get_tree().get_nodes_in_group("enemies"):
			if o in hit or not (o is WCEnemy):
				continue
			var d: float = from.distance_to((o as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = o
		if best == null:
			break
		hit.append(best)
		from = best.global_position
		best.take_hit(dmg_amount, "volt", ["chain"], global_position)
		if dungeon != null and dungeon.has_method("spawn_beam_fx"):
			dungeon.spawn_beam_fx(global_position, best.global_position, Color(0.4, 0.95, 1.0))

func _spread_status(status_id: String, count: int) -> void:
	var n := 0
	for o in get_tree().get_nodes_in_group("enemies"):
		if o == self or not (o is WCEnemy):
			continue
		if (o as Node3D).global_position.distance_to(global_position) < 8.0:
			(o as WCEnemy).statuses[status_id] = 4.0
			n += 1
			if n >= count:
				break

func _damage_raw(amount: float) -> void:
	hp = maxf(0.0, hp - amount)

func _flash() -> void:
	if _mat != null:
		_mat.emission_energy_multiplier = 4.0
		var tw := create_tween()
		tw.tween_property(_mat, "emission_energy_multiplier", 0.9, 0.12)

func _update_ring() -> void:
	if _ring == null:
		return
	var active_status := ""
	for k in ["frozen", "superconduct", "plasma", "burning", "shocked", "chilled", "corroded", "marked"]:
		if SynergyEngine.has(statuses, k):
			active_status = k
			break
	var rm := _ring.material_override as StandardMaterial3D
	if active_status == "":
		rm.emission = data.get("color", Color.RED)
		_ring.visible = is_boss
	else:
		rm.emission = SynergyEngine.STATUS_COLORS.get(active_status, Color.WHITE)
		rm.albedo_color = rm.emission
		_ring.visible = true

func _die() -> void:
	if dead:
		return
	dead = true
	AudioDirector.play("explode", 1.1)
	if dungeon != null:
		if dungeon.has_method("on_enemy_died"):
			dungeon.on_enemy_died(self)
	died.emit(self)
	# death pop
	var tw := create_tween()
	tw.set_parallel(true)
	tw.tween_property(_rig, "scale", Vector3.ZERO, 0.25)
	tw.tween_property(_rig, "position:y", 2.0, 0.25)
	tw.chain().tween_callback(queue_free)
