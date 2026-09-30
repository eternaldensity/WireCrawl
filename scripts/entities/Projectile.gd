class_name WCProjectile
extends Area3D
## Pooled-style projectile: moves linearly (optionally arced), pierces N foes,
## applies damage + status via SynergyEngine, spawns splash. Hits resolved by
## faction: "player" projectiles hit group "enemies"; "enemy" hit "player".

var faction := "player"
var damage := 10.0
var dmg_type := "kinetic"
var speed := 30.0
var life := 1.6
var pierce := 0
var splash := 0.0
var color := Color.WHITE
var direction := Vector3.FORWARD
var arc_height := 0.0
var tags: Array = []
var _age := 0.0
var _hit: Array = []
var _mesh: MeshInstance3D

static func spawn(parent: Node, pos: Vector3, dir: Vector3, opts: Dictionary) -> WCProjectile:
	var p := WCProjectile.new()
	p.faction = String(opts.get("faction", "player"))
	p.damage = float(opts.get("damage", 10.0))
	p.dmg_type = String(opts.get("dmg_type", "kinetic"))
	p.speed = float(opts.get("speed", 30.0))
	p.pierce = int(opts.get("pierce", 0))
	p.splash = float(opts.get("splash", 0.0))
	p.color = opts.get("color", Color.WHITE)
	p.direction = dir.normalized()
	p.tags = opts.get("tags", []).duplicate()
	p.arc_height = float(opts.get("arc", 0.0))
	parent.add_child(p)
	p.global_position = pos
	p._build_visual()
	return p

func _build_visual() -> void:
	collision_layer = 16
	collision_mask = 0
	monitoring = true
	monitorable = false
	var shape := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.28
	shape.shape = sphere
	add_child(shape)
	_mesh = MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.16
	sm.height = 0.32
	_mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.material_override = mat
	add_child(_mesh)
	# Trail glow quad
	var trail := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(0.08, 0.08, 0.9)
	trail.mesh = bm
	trail.material_override = mat
	trail.position = Vector3(0, 0, 0.45)
	add_child(trail)
	body_entered.connect(_on_body)
	area_entered.connect(_on_area)

func _ready() -> void:
	# Orient along direction
	if direction.length() > 0.01:
		look_at(global_position + direction, Vector3.UP)

func _physics_process(delta: float) -> void:
	_age += delta
	if _age >= life:
		_explode_if_needed()
		queue_free()
		return
	var step: Vector3 = direction * speed * delta
	if arc_height > 0.0:
		step.y += sin(_age / life * PI) * arc_height * delta
	global_position += step

func _on_body(body: Node3D) -> void:
	_resolve_hit(body)

func _on_area(a: Area3D) -> void:
	_resolve_hit(a)

func _resolve_hit(node: Node) -> void:
	if faction == "player" and node.is_in_group("enemies"):
		if node in _hit:
			return
		_hit.append(node)
		if node.has_method("take_hit"):
			node.take_hit(damage, dmg_type, tags, global_position)
		AudioDirector.play("hit", 0.9 + damage / 200.0)
		if splash > 0.0:
			_explode()
			queue_free()
			return
		if pierce > 0:
			pierce -= 1
		else:
			queue_free()
	elif faction == "enemy" and node.is_in_group("player"):
		if node.has_method("take_hit"):
			node.take_hit(damage, dmg_type, tags, global_position)
		queue_free()

func _explode_if_needed() -> void:
	if splash > 0.0 and faction == "player":
		_explode()

func _explode() -> void:
	AudioDirector.play("explode")
	var fx_parent := get_parent()
	# Damage all enemies in radius
	var q := PhysicsShapeQueryParameters3D.new()
	var shape := SphereShape3D.new()
	shape.radius = splash
	q.shape = shape
	q.transform = Transform3D(Basis(), global_position)
	q.collision_mask = 4  # enemy layer bit? enemies are bodies in group
	var space := get_world_3d().direct_space_state
	for body in get_tree().get_nodes_in_group("enemies"):
		if (body as Node3D).global_position.distance_to(global_position) <= splash:
			if body.has_method("take_hit"):
				body.take_hit(damage * 0.6, dmg_type, tags, global_position)
	if fx_parent != null and fx_parent.has_method("spawn_blast_fx"):
		fx_parent.spawn_blast_fx(global_position, splash, color)
