class_name WCPickup
extends Area3D
## Dungeon floor pickup: loot orb (weapon/armor), credits, health cell, energy.
## Magnet-attracted to player, collected on touch. Neon hologram visual + bob.

var kind := "credits"  # credits | health | energy | loot
var amount := 10
var item := {}
var color := Color(0.976, 0.941, 0.008)
var _visual: Node3D
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
	_visual = Node3D.new()
	add_child(_visual)
	match kind:
		"credits":
			_coin(_visual, color)
		"health":
			_cross(_visual, color)
		"energy":
			_cell(_visual, color)
		"loot":
			_cache(_visual, color)
	body_entered.connect(_on_body)

func _pmat(col: Color, energy := 3.5) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = col
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = energy
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return mat

func _pbox(parent: Node3D, size: Vector3, pos: Vector3, mat: Material) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = size
	mi.mesh = bm
	mi.material_override = mat
	mi.position = pos
	parent.add_child(mi)
	return mi

func _coin(parent: Node3D, col: Color) -> void:
	## Spinning credit chip.
	var coin := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.3
	cm.bottom_radius = 0.3
	cm.height = 0.08
	coin.mesh = cm
	coin.material_override = _pmat(col, 4.0)
	coin.rotation.x = PI / 2.2
	parent.add_child(coin)
	_pbox(parent, Vector3(0.34, 0.34, 0.1), Vector3.ZERO, _pmat(col.darkened(0.3), 1.5))

func _cross(parent: Node3D, col: Color) -> void:
	## Medkit cross.
	var mat := _pmat(col, 4.0)
	_pbox(parent, Vector3(0.55, 0.2, 0.2), Vector3.ZERO, mat)
	_pbox(parent, Vector3(0.2, 0.55, 0.2), Vector3.ZERO, mat)
	var shell := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(0.7, 0.7, 0.3)
	shell.mesh = sm
	shell.material_override = _pmat(col.darkened(0.5), 1.0)
	shell.position.z = -0.08
	parent.add_child(shell)

func _cell(parent: Node3D, col: Color) -> void:
	## Energy diamond.
	var gem := _pbox(parent, Vector3(0.34, 0.5, 0.34), Vector3.ZERO, _pmat(col, 4.5))
	gem.rotation.y = PI / 4.0
	_pbox(parent, Vector3(0.5, 0.1, 0.5), Vector3(0, -0.35, 0), _pmat(col.darkened(0.2), 2.0))

func _cache(parent: Node3D, col: Color) -> void:
	## Loot cache: holo chip + rarity ring; epic+ gets a light pillar.
	_pbox(parent, Vector3(0.45, 0.12, 0.65), Vector3(0, 0.1, 0), _pmat(col, 4.0))
	_pbox(parent, Vector3(0.3, 0.3, 0.3), Vector3(0, 0.45, 0), _pmat(col.lightened(0.3), 4.5))
	var ring := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.42
	tm.outer_radius = 0.55
	ring.mesh = tm
	ring.material_override = _pmat(col, 3.0)
	ring.position.y = -0.35
	parent.add_child(ring)
	var r := String(item.get("rarity", "common"))
	if r in ["epic", "legendary", "mythic"]:
		var beam := MeshInstance3D.new()
		var cm := CylinderMesh.new()
		cm.top_radius = 0.12
		cm.bottom_radius = 0.22
		cm.height = 6.0
		beam.mesh = cm
		var bmat := _pmat(col, 2.0)
		bmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		bmat.albedo_color.a = 0.5
		beam.material_override = bmat
		beam.position.y = 2.6
		parent.add_child(beam)

func _process(delta: float) -> void:
	_t += delta
	_visual.position.y = 0.25 + sin(_t * 3.0) * 0.15
	_visual.rotate_y(delta * (3.5 if kind == "loot" else 2.0))
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
