class_name WCPropCrate
extends StaticBody3D
## Destructible cover crate: reads as cover (hazard-striped), takes weapon
## hits, breaks into credits/health with a pop. Gives the "mystery cubes"
## a function instead of being inert geometry.

var hp := 30.0
var size := 1.2
var dungeon = null
var dead := false
var _mat: StandardMaterial3D

static func spawn(parent: Node, pos: Vector3, p_size: float) -> WCPropCrate:
	var c := WCPropCrate.new()
	c.size = p_size
	c.hp = 18.0 + p_size * 12.0
	parent.add_child(c)
	c.global_position = pos
	return c

func _ready() -> void:
	add_to_group("props")
	add_to_group("crates")
	collision_layer = 1
	collision_mask = 0
	_mat = StandardMaterial3D.new()
	_mat.albedo_color = Color(0.07, 0.075, 0.11)
	_mat.emission_enabled = true
	_mat.emission = Color(0.976, 0.941, 0.008)
	_mat.emission_energy_multiplier = 0.25
	_mat.metallic = 0.5
	_mat.roughness = 0.55
	var box := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(size, size, size)
	box.mesh = bm
	box.material_override = _mat
	box.position.y = size / 2.0
	add_child(box)
	# hazard stripe = "cover, shootable" affordance
	var stripe := MeshInstance3D.new()
	var sm := BoxMesh.new()
	sm.size = Vector3(size * 1.01, size * 0.16, size * 1.01)
	stripe.mesh = sm
	var stmat := StandardMaterial3D.new()
	stmat.albedo_color = Color(0.976, 0.941, 0.008)
	stmat.emission_enabled = true
	stmat.emission = Color(0.976, 0.941, 0.008)
	stmat.emission_energy_multiplier = 1.6
	stmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	stripe.material_override = stmat
	stripe.position.y = size * 0.78
	add_child(stripe)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(size, size, size)
	cs.shape = bs
	cs.position.y = size / 2.0
	add_child(cs)

func take_hit(amount: float, _dmg_type: String, _tags: Array, _from: Vector3) -> void:
	if dead:
		return
	hp -= amount
	_mat.emission_energy_multiplier = 1.6
	var tw := create_tween()
	tw.tween_property(_mat, "emission_energy_multiplier", 0.25, 0.12)
	if hp <= 0.0:
		_break()

func _break() -> void:
	dead = true
	AudioDirector.play("explode", 1.2)
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	if dungeon != null:
		if dungeon.has_method("spawn_blast_fx"):
			dungeon.spawn_blast_fx(global_position + Vector3(0, 0.8, 0), 1.4,
				Color(0.976, 0.941, 0.008))
		if rng.randf() < 0.45:
			WCPickup.spawn(dungeon, global_position, "credits", rng.randi_range(5, 15))
		if rng.randf() < 0.12:
			WCPickup.spawn(dungeon, global_position, "health", 12)
	remove_from_group("crates")
	queue_free()
