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
var _t := 0.0
var _body: MeshInstance3D
var _ring: MeshInstance3D
var _mat: StandardMaterial3D
var _base_y := 0.0
var dungeon = null

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
	xp = int(data["xp"])
	creds = int(data["creds"])
	hp = max_hp
	statuses = SynergyEngine.empty_statuses()
	if String(data.get("status", "")) != "":
		statuses[String(data["status"])] = 999.0  # innate aura carrier
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

func _build_visual(sc: float) -> void:
	var col: Color = data.get("color", Color.RED)
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = col.darkened(0.55)
	_mat.emission_enabled = true
	_mat.emission = col
	_mat.emission_energy_multiplier = 1.6
	_body = MeshInstance3D.new()
	if flying:
		var sm := SphereMesh.new()
		sm.radius = 0.45 * sc
		sm.height = 0.7 * sc
		_body.mesh = sm
		_body.position.y = 1.6
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.9 * sc, 1.5 * sc, 0.6 * sc)
		_body.mesh = bm
		_body.position.y = 0.85 * sc
	_body.material_override = _mat
	add_child(_body)
	# visor eye
	var eye := MeshInstance3D.new()
	var em := BoxMesh.new()
	em.size = Vector3(0.6 * sc, 0.12 * sc, 0.05)
	eye.mesh = em
	var eym := StandardMaterial3D.new()
	eym.albedo_color = Color.WHITE
	eym.emission_enabled = true
	eym.emission = Color.WHITE
	eym.emission_energy_multiplier = 5.0
	eym.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	eye.material_override = eym
	eye.position = Vector3(0, (1.25 if not flying else 1.6) * sc, 0.32 * sc)
	add_child(eye)
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
	if is_boss:
		AudioDirector.play("boss")

func _physics_process(delta: float) -> void:
	if dead:
		return
	_t += delta
	if target == null or not is_instance_valid(target):
		target = get_tree().get_first_node_in_group("player")
		if target == null:
			return
	# Status tick
	SynergyEngine.tick(statuses, delta)
	var dot: float = SynergyEngine.dot_damage(statuses, max_hp, delta)
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
			if dashing > 0.0:
				dashing -= delta
				vel = dash_dir * speed * 3.2
			elif dist < 9.0 and dist > 2.0 and dash_cd <= 0.0:
				dashing = 0.35
				dash_cd = 2.4
				dash_dir = dir
				AudioDirector.play("dash", 0.7)
			elif dist > 1.7:
				vel = dir * speed * slowed
			elif attack_cd <= 0.0:
				_melee(dir)
		"shooter":
			if dist > 16.0:
				vel = dir * speed * slowed
			elif dist < 7.0:
				vel = -dir * speed * 0.7 * slowed
			else:
				vel = Vector3.ZERO
			if attack_cd <= 0.0 and dist < 22.0:
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
		if l > 0.01 and l < 1.4:
			velocity += d / l * 3.0
	move_and_slide()
	# face target
	if dir.length() > 0.01:
		var yaw := atan2(-dir.x, -dir.z)
		rotation.y = lerp_angle(rotation.y, yaw, 10.0 * delta)
	# hover / bob
	if flying:
		_body.position.y = 1.6 + sin(_t * 4.0) * 0.15
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

func _melee(dir: Vector3) -> void:
	attack_cd = 1.1 if not is_boss else 0.8
	AudioDirector.play("melee", 0.8)
	if target != null and target.has_method("take_hit"):
		var d: float = global_position.distance_to(target.global_position)
		if d < (2.6 if not is_boss else 4.2):
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
		tw.tween_property(_mat, "emission_energy_multiplier", 1.6, 0.12)

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
	tw.tween_property(_body, "scale", Vector3.ZERO, 0.25)
	tw.tween_property(_body, "position:y", 2.0, 0.25)
	tw.chain().tween_callback(queue_free)
