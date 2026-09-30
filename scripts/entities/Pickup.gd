class_name WCPickup
extends Area3D
## Dungeon floor pickup: loot orb (weapon/armor), credits, health cell, energy.
## Magnet-attracted to player, collected on touch. Neon hologram visual + bob.

var kind := "credits"  # credits | health | energy | loot
var amount := 10
var item := {}
var color := Color(0.976, 0.941, 0.008)
var _mesh: MeshInstance3D
var _t := 0.0
var _player: Node3D = null

static func spawn(parent: Node, pos: Vector3, p_kind: String, p_amount := 10, p_item := {}) -> WCPickup:
	var pk := WCPickup.new()
	pk.kind = p_kind
	pk.amount = p_amount
	pk.item = p_item
	match p_kind:
		"credits": pk.color = Color(0.976, 0.941, 0.008)
		"health": pk.color = Color(0.3, 1.0, 0.4)
		"energy": pk.color = Color(0.3, 0.9, 1.0)
		"loot":
			var r := String(p_item.get("rarity", "common"))
			pk.color = GameDB.RARITY_COLORS.get(r, Color.WHITE)
	parent.add_child(pk)
	pk.global_position = pos + Vector3(0, 0.7, 0)
	return pk

func _ready() -> void:
	add_to_group("pickups")
	collision_layer = 32
	collision_mask = 2
	monitoring = true
	var shape := CollisionShape3D.new()
	var sp := SphereShape3D.new()
	sp.radius = 1.1
	shape.shape = sp
	add_child(shape)
	_mesh = MeshInstance3D.new()
	if kind == "loot":
		var bm := BoxMesh.new()
		bm.size = Vector3(0.5, 0.7, 0.5)
		_mesh.mesh = bm
		_mesh.rotation_degrees.y = 45
	else:
		var sm := SphereMesh.new()
		sm.radius = 0.28
		sm.height = 0.56
		_mesh.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mesh.material_override = mat
	add_child(_mesh)
	body_entered.connect(_on_body)

func _process(delta: float) -> void:
	_t += delta
	_mesh.position.y = 0.25 + sin(_t * 3.0) * 0.15
	_mesh.rotate_y(delta * 2.5)
	if _player == null or not is_instance_valid(_player):
		_player = get_tree().get_first_node_in_group("player")
	if _player != null:
		var d: float = global_position.distance_to(_player.global_position)
		if d < 6.0:
			global_position = global_position.move_toward(
				_player.global_position + Vector3(0, 0.7, 0), delta * (9.0 - d))

func _on_body(body: Node3D) -> void:
	if not body.is_in_group("player"):
		return
	if not body.has_method("collect"):
		return
	body.collect(kind, amount, item)
	queue_free()
