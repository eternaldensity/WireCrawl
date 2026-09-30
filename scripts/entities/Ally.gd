class_name WCAlly
extends CharacterBody3D
## Friendly deployables: "turret" (stationary auto-cannon) and "hound"
## (melee daemon that taunts + chases). Scale with program_power.

var kind := "turret"
var power := 1.0
var life := 20.0
var damage := 12.0
var fire_cd := 0.0
var speed := 6.0
var target: WCEnemy = null
var _t := 0.0
var _mesh: MeshInstance3D

static func spawn(parent: Node, pos: Vector3, p_kind: String, p_power: float) -> WCAlly:
	var a := WCAlly.new()
	a.kind = p_kind
	a.power = p_power
	parent.add_child(a)
	a.global_position = pos
	return a

func _ready() -> void:
	add_to_group("allies")
	collision_layer = 2
	collision_mask = 1
	var shape := CollisionShape3D.new()
	var cap := CapsuleShape3D.new()
	cap.radius = 0.4
	cap.height = 1.2
	shape.shape = cap
	shape.position.y = 0.6
	add_child(shape)
	if kind == "turret":
		life = 20.0
		damage = 14.0 * power
	else:
		life = 30.0
		damage = 18.0 * power
		speed = 7.0
	_mesh = MeshInstance3D.new()
	var col := Color(0.25, 0.9, 1.0) if kind == "turret" else Color(1.0, 0.16, 0.43)
	if kind == "turret":
		var cm := CylinderMesh.new()
		cm.top_radius = 0.35
		cm.bottom_radius = 0.5
		cm.height = 1.1
		_mesh.mesh = cm
		_mesh.position.y = 0.55
	else:
		var bm := BoxMesh.new()
		bm.size = Vector3(0.7, 0.6, 1.1)
		_mesh.mesh = bm
		_mesh.position.y = 0.5
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col.darkened(0.5)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 2.2
	_mesh.material_override = mat
	add_child(_mesh)
	AudioDirector.play("turret")

func _physics_process(delta: float) -> void:
	_t += delta
	life -= delta
	if life <= 0.0:
		_expire()
		return
	_acquire()
	if kind == "turret":
		velocity = Vector3.ZERO
		velocity.y = -9.8
		move_and_slide()
		fire_cd -= delta
		if target != null and fire_cd <= 0.0:
			fire_cd = 0.45
			var dir: Vector3 = (target.global_position + Vector3(0, 1, 0) - (global_position + Vector3(0, 1, 0))).normalized()
			WCProjectile.spawn(get_parent(), global_position + Vector3(0, 1.1, 0), dir,
				{"faction": "player", "damage": damage, "dmg_type": "volt",
					"speed": 34.0, "color": Color(0.3, 0.95, 1.0)})
			AudioDirector.play("shoot", 1.2)
	else:
		if target != null:
			var to: Vector3 = target.global_position - global_position
			to.y = 0.0
			if to.length() > 1.6:
				velocity = to.normalized() * speed
			else:
				velocity = Vector3.ZERO
				fire_cd -= delta
				if fire_cd <= 0.0:
					fire_cd = 0.8
					target.take_hit(damage, "void", ["melee"], global_position)
					AudioDirector.play("melee", 1.2)
		else:
			# follow player
			var p := get_tree().get_first_node_in_group("player") as Node3D
			if p != null:
				var to2: Vector3 = p.global_position - global_position
				to2.y = 0.0
				velocity = to2.normalized() * speed * 0.8 if to2.length() > 3.0 else Vector3.ZERO
			else:
				velocity = Vector3.ZERO
		velocity.y = -9.8
		move_and_slide()

func _acquire() -> void:
	var best_d := 20.0
	var best: WCEnemy = null
	for o in get_tree().get_nodes_in_group("enemies"):
		if not (o is WCEnemy) or (o as WCEnemy).dead:
			continue
		var d: float = global_position.distance_to((o as Node3D).global_position)
		if d < best_d:
			best_d = d
			best = o
	target = best

func _expire() -> void:
	var tw := create_tween()
	tw.tween_property(_mesh, "scale", Vector3.ZERO, 0.2)
	tw.tween_callback(queue_free)
