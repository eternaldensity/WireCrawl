class_name WCDungeon
extends Node3D
## Sector orchestrator: generates layout via DungeonGen, builds the neon 3D
## city (floors, walls, props, rain, lighting), spawns encounters, owns FX
## (floaters, blasts, beams, slashes), ally deployables, program AoEs, loot
## offering, room-clear tracking, boss + extraction flow.

signal room_cleared(idx: int, total: int)
signal boss_spawned(boss_name: String)
signal extraction_ready
signal loot_offered(item: Dictionary)

const CELL := 4.0

var layout := {}
var threat := 1
var contract := {}
var player: WCPlayer
var cam: Camera3D
var cam_shake := 0.0
var enemies_alive := 0
var rooms_total := 0
var boss: WCEnemy = null
var exit_pos := Vector3.ZERO
var extracted := false
var clear_timer := 0.0
var float_layer: Node3D
var fx_layer: Node3D

func setup(p_contract: Dictionary) -> void:
	contract = p_contract
	threat = int(p_contract.get("threat", 1))
	var room_target: int = int(p_contract.get("rooms", 9))
	layout = DungeonGen.generate(threat, room_target)

func _ready() -> void:
	_build_environment()
	_build_level()
	_spawn_player()
	_spawn_encounters()
	_build_camera()

# ---------------- environment (sky, glow, rain) ----------------
func _build_environment() -> void:
	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.008, 0.008, 0.02)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.12, 0.1, 0.22)
	e.ambient_light_energy = 1.2
	e.glow_enabled = true
	e.glow_intensity = 1.4
	e.glow_strength = 1.25
	e.glow_bloom = 0.25
	e.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT
	e.fog_enabled = true
	e.fog_light_color = Color(0.06, 0.03, 0.12)
	e.fog_density = 0.02
	e.tonemap_mode = Environment.TONE_MAPPER_ACES
	e.adjustment_enabled = true
	e.adjustment_saturation = 1.35
	e.adjustment_contrast = 1.12
	env.environment = e
	add_child(env)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-58, -30, 0)
	sun.light_color = Color(0.55, 0.5, 0.9)
	sun.light_energy = 0.7
	sun.shadow_enabled = false
	add_child(sun)
	var magenta := OmniLight3D.new()
	magenta.light_color = Color(1.0, 0.16, 0.43)
	magenta.light_energy = 2.0
	magenta.omni_range = 40.0
	magenta.position = Vector3(0, 8, 0)
	add_child(magenta)
	# rain
	var rain := GPUParticles3D.new()
	rain.amount = 900
	rain.lifetime = 1.1
	var pm := ParticleProcessMaterial.new()
	pm.direction = Vector3(0.15, -1, 0.05)
	pm.spread = 4.0
	pm.initial_velocity_min = 28.0
	pm.initial_velocity_max = 34.0
	pm.gravity = Vector3.ZERO
	pm.scale_min = 0.03
	pm.scale_max = 0.06
	pm.color = Color(0.4, 0.8, 1.0, 0.5)
	rain.process_material = pm
	rain.draw_pass_1 = QuadMesh.new()
	rain.position = Vector3(0, 14, 0)
	var rain_box := BoxMesh.new()
	rain_box.size = Vector3(90, 1, 90)
	rain.visibility_aabb = AABB(Vector3(-45, -15, -45), Vector3(90, 20, 90))
	add_child(rain)
	float_layer = Node3D.new()
	float_layer.name = "Floaters"
	add_child(float_layer)
	fx_layer = Node3D.new()
	fx_layer.name = "FX"
	add_child(fx_layer)

func _neon_grid_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec4 base_color : source_color = vec4(0.015, 0.015, 0.045, 1.0);
uniform vec4 line_cyan : source_color = vec4(0.02, 0.85, 0.91, 1.0);
uniform vec4 line_pink : source_color = vec4(1.0, 0.16, 0.43, 1.0);
varying vec3 wpos;
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 g = abs(fract(wpos.xz / 4.0) - 0.5);
	float line = smoothstep(0.46, 0.5, max(g.x, g.y));
	vec2 g2 = abs(fract(wpos.xz / 20.0) - 0.5);
	float major = smoothstep(0.465, 0.5, max(g2.x, g2.y));
	float checker = mod(floor(wpos.x / 4.0) + floor(wpos.z / 4.0), 2.0);
	vec3 col = base_color.rgb + checker * 0.012;
	col += line_cyan.rgb * line * 0.55;
	col += line_pink.rgb * major * 0.9;
	ALBEDO = col;
	EMISSION = line_cyan.rgb * line * 1.6 + line_pink.rgb * major * 2.2;
	ROUGHNESS = 0.35;
	METALLIC = 0.6;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	return m

# ---------------- level construction ----------------
func _build_level() -> void:
	var w: int = layout["w"]
	var h: int = layout["h"]
	var tiles: PackedByteArray = layout["tiles"]
	# Floor: one big plane under everything + dark base
	var floor_body := StaticBody3D.new()
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	add_child(floor_body)
	var plane := MeshInstance3D.new()
	var pm := PlaneMesh.new()
	pm.size = Vector2(w * CELL, h * CELL)
	plane.mesh = pm
	plane.material_override = _neon_grid_material()
	floor_body.add_child(plane)
	var col := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(w * CELL, 1.0, h * CELL)
	col.shape = box
	col.position.y = -0.5
	floor_body.add_child(col)
	var ox := -w * CELL / 2.0
	var oz := -h * CELL / 2.0
	# Walls: boundary runs merged per row
	var wall_mat := StandardMaterial3D.new()
	wall_mat.albedo_color = Color(0.03, 0.03, 0.07)
	wall_mat.emission_enabled = true
	wall_mat.emission = Color(1.0, 0.16, 0.43)
	wall_mat.emission_energy_multiplier = 0.35
	wall_mat.metallic = 0.7
	wall_mat.roughness = 0.4
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.02, 0.85, 0.91)
	trim_mat.emission_enabled = true
	trim_mat.emission = Color(0.02, 0.85, 0.91)
	trim_mat.emission_energy_multiplier = 3.0
	trim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var walls := StaticBody3D.new()
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	for y in h:
		var x := 0
		while x < w:
			if _is_wall_cell(tiles, w, h, x, y):
				var x2 := x
				while x2 < w and _is_wall_cell(tiles, w, h, x2, y):
					x2 += 1
				var length := float(x2 - x) * CELL
				var cx := ox + (float(x) + float(x2 - x) / 2.0) * CELL
				var cz := oz + (float(y) + 0.5) * CELL
				var wall := MeshInstance3D.new()
				var bm := BoxMesh.new()
				bm.size = Vector3(length, 3.4, CELL)
				wall.mesh = bm
				wall.material_override = wall_mat
				wall.position = Vector3(cx, 1.7, cz)
				walls.add_child(wall)
				var cs := CollisionShape3D.new()
				var bs := BoxShape3D.new()
				bs.size = Vector3(length, 3.4, CELL)
				cs.shape = bs
				cs.position = Vector3(cx, 1.7, cz)
				walls.add_child(cs)
				# neon trim strip on top edge
				var trim := MeshInstance3D.new()
				var tm := BoxMesh.new()
				tm.size = Vector3(length, 0.1, 0.12)
				trim.mesh = tm
				trim.material_override = trim_mat if (y % 2 == 0) else wall_mat
				trim.position = Vector3(cx, 3.45, cz - CELL / 2.0 + 0.06)
				walls.add_child(trim)
				x = x2
			else:
				x += 1
	_build_props(ox, oz)
	_build_exit(ox, oz)

func _is_wall_cell(tiles: PackedByteArray, w: int, h: int, x: int, y: int) -> bool:
	if tiles[y * w + x] != DungeonGen.TILE_VOID:
		return false
	for dy in [-1, 0, 1]:
		for dx in [-1, 0, 1]:
			var nx: int = x + dx
			var ny: int = y + dy
			if nx >= 0 and ny >= 0 and nx < w and ny < h:
				if tiles[ny * w + nx] != DungeonGen.TILE_VOID:
					return true
	return false

func _cell_to_world(cell: Vector2i) -> Vector3:
	return DungeonGen.world_pos(layout, cell, CELL)

func _world_to_cell(wp: Vector3) -> Vector2i:
	var w: int = layout["w"]
	var h: int = layout["h"]
	return Vector2i(clampi(int(round(wp.x / CELL + float(w) / 2.0)), 0, w - 1),
		clampi(int(round(wp.z / CELL + float(h) / 2.0)), 0, h - 1))

func _build_props(ox: float, oz: float) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout["seed"]) ^ 0x9e37
	var tiles: PackedByteArray = layout["tiles"]
	var w: int = layout["w"]
	var h: int = layout["h"]
	var crate_mat := StandardMaterial3D.new()
	crate_mat.albedo_color = Color(0.05, 0.06, 0.1)
	crate_mat.emission_enabled = true
	crate_mat.emission = Color(0.976, 0.941, 0.008)
	crate_mat.emission_energy_multiplier = 0.5
	var holo_colors := [Color(0.02, 0.85, 0.91), Color(1.0, 0.16, 0.43), Color(0.976, 0.941, 0.008)]
	var props := StaticBody3D.new()
	props.collision_layer = 1
	props.collision_mask = 0
	add_child(props)
	var placed := 0
	for r in layout["rooms"] as Array:
		var room := r as Rect2i
		# holo billboard pillar at room corner
		var corner := Vector2i(room.position.x + 1, room.position.y + 1)
		var hc: Color = holo_colors[rng.randi() % holo_colors.size()]
		_holo_pillar(props, _cell_to_world(corner) + Vector3(0, 0, 0), hc)
		# crates: 0-3 per room, never on spawn/exit
		for _i in rng.randi_range(0, 2):
			var cx := rng.randi_range(room.position.x + 1, room.position.x + room.size.x - 2)
			var cy := rng.randi_range(room.position.y + 1, room.position.y + room.size.y - 2)
			if tiles[cy * w + cx] == DungeonGen.TILE_VOID:
				continue
			var wp := _cell_to_world(Vector2i(cx, cy))
			if wp.distance_to(_cell_to_world(layout["spawn"])) < 6.0:
				continue
			var crate := MeshInstance3D.new()
			var bm := BoxMesh.new()
			var s := rng.randf_range(0.8, 1.4)
			bm.size = Vector3(s, s, s)
			crate.mesh = bm
			crate.material_override = crate_mat
			crate.position = wp + Vector3(rng.randf_range(-1, 1), s / 2.0, rng.randf_range(-1, 1))
			props.add_child(crate)
			var cs := CollisionShape3D.new()
			var bs := BoxShape3D.new()
			bs.size = Vector3(s, s, s)
			cs.shape = bs
			cs.position = crate.position
			props.add_child(cs)
			placed += 1
			if placed > 40:
				break

func _holo_pillar(parent: Node, pos: Vector3, col: Color) -> void:
	var pillar := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.25
	cm.bottom_radius = 0.35
	cm.height = 5.0
	pillar.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.04, 0.08)
	mat.emission_enabled = true
	mat.emission = col
	mat.emission_energy_multiplier = 0.8
	pillar.material_override = mat
	pillar.position = pos + Vector3(0, 2.5, 0)
	parent.add_child(pillar)
	# floating holo sign
	var sign_mesh := MeshInstance3D.new()
	var q := QuadMesh.new()
	q.size = Vector2(2.2, 1.1)
	sign_mesh.mesh = q
	var smat := StandardMaterial3D.new()
	smat.albedo_color = col
	smat.emission_enabled = true
	smat.emission = col
	smat.emission_energy_multiplier = 3.0
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	sign_mesh.material_override = smat
	sign_mesh.position = pos + Vector3(0, 4.2, 0)
	parent.add_child(sign_mesh)
	var light := OmniLight3D.new()
	light.light_color = col
	light.light_energy = 1.2
	light.omni_range = 10.0
	light.position = pos + Vector3(0, 3.0, 0)
	parent.add_child(light)

func _build_exit(ox: float, oz: float) -> void:
	exit_pos = _cell_to_world(layout["exit"]) + Vector3(0, 0, 0)
	var term := Area3D.new()
	term.name = "ExitTerminal"
	term.collision_layer = 0
	term.collision_mask = 2
	add_child(term)
	term.position = exit_pos
	var shape := CollisionShape3D.new()
	var cyl := CylinderShape3D.new()
	cyl.radius = 2.2
	cyl.height = 4.0
	shape.shape = cyl
	shape.position.y = 1.0
	term.add_child(shape)
	var beam := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 1.4
	cm.bottom_radius = 1.4
	cm.height = 9.0
	beam.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.5, 0.45)
	mat.emission_enabled = true
	mat.emission = Color(0.2, 1.0, 0.5)
	mat.emission_energy_multiplier = 2.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	beam.material_override = mat
	beam.position.y = 4.5
	term.add_child(beam)
	var light := OmniLight3D.new()
	light.light_color = Color(0.2, 1.0, 0.5)
	light.light_energy = 2.5
	light.omni_range = 14.0
	light.position.y = 3.0
	term.add_child(light)
	term.body_entered.connect(_on_exit_enter)
	float_text(exit_pos + Vector3(0, 6, 0), "▼ EXTRACT ▼", Color(0.3, 1.0, 0.5))

# ---------------- actors ----------------
func _spawn_player() -> void:
	player = WCPlayer.new()
	add_child(player)
	player.global_position = _cell_to_world(layout["spawn"]) + Vector3(0, 0.5, 0)
	player.dungeon = self

func _spawn_encounters() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout["seed"]) ^ 0x51f3
	rooms_total = (layout["rooms"] as Array).size()
	var spawn_cell: Vector2i = layout["spawn"]
	var keys := ["punk", "razor", "drone", "enforcer", "hexer", "brute"]
	for i in range(1, rooms_total):
		var room: Rect2i = (layout["rooms"] as Array)[i]
		var center := Vector2i(room.position.x + room.size.x / 2, room.position.y + room.size.y / 2)
		var count := 2 + rng.randi() % 2 + (1 if threat >= 3 else 0)
		if tiles_at(center) == DungeonGen.TILE_AMBUSH:
			count += 2
		for _k in count:
			var cell := Vector2i(rng.randi_range(room.position.x + 1, room.position.x + room.size.x - 2),
				rng.randi_range(room.position.y + 1, room.position.y + room.size.y - 2))
			if not DungeonGen.is_walkable(layout, cell.x, cell.y):
				continue
			var ek := _pick_enemy(rng, keys)
			var e := WCEnemy.spawn(self, ek, _cell_to_world(cell) + Vector3(0, 0.5, 0), threat)
			e.dungeon = self
			enemies_alive += 1
		# loot chest in loot rooms
		if _room_has_tile(room, DungeonGen.TILE_LOOT):
			var item := LootFactory.roll_weapon(threat, RunManager.luck + 0.5)
			RunManager.register_loot(item)
			WCPickup.spawn(self, _cell_to_world(center) + Vector3(1.5, 0, 0), "loot", 0, item)
			if rng.randf() < 0.5:
				WCPickup.spawn(self, _cell_to_world(center) + Vector3(-1.5, 0, 0), "health", 25)
	# boss?
	var boss_key := String(contract.get("boss", ""))
	if boss_key != "":
		_spawn_boss(boss_key)

func tiles_at(cell: Vector2i) -> int:
	var w: int = layout["w"]
	return (layout["tiles"] as PackedByteArray)[cell.y * w + cell.x]

func _room_has_tile(room: Rect2i, tile: int) -> bool:
	var w: int = layout["w"]
	var tiles: PackedByteArray = layout["tiles"]
	for y in range(room.position.y, room.position.y + room.size.y):
		for x in range(room.position.x, room.position.x + room.size.x):
			if tiles[y * w + x] == tile:
				return true
	return false

func _pick_enemy(rng: RandomNumberGenerator, keys: Array) -> String:
	var t := threat
	var pool := ["punk", "punk", "razor", "drone"]
	if t >= 2:
		pool += ["enforcer", "hexer", "razor"]
	if t >= 3:
		pool += ["brute", "enforcer"]
	if t >= 4:
		pool += ["brute", "hexer", "hexer"]
	return pool[rng.randi() % pool.size()]

func _spawn_boss(boss_key: String) -> void:
	var c := _cell_to_world(layout["exit"])
	boss = WCEnemy.spawn(self, boss_key, c + Vector3(3, 0.5, 0), threat)
	boss.dungeon = self
	enemies_alive += 1
	RunManager.boss_spawned = true
	boss_spawned.emit(String(GameDB.ENEMIES[boss_key]["name"]))
	float_text(c + Vector3(0, 5, 0), "⚠ " + String(GameDB.ENEMIES[boss_key]["name"]) + " ⚠",
		Color(1.0, 0.16, 0.43))

func summon_adds(pos: Vector3, count: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var keys := ["punk", "razor", "drone"]
	for _i in count:
		var e := WCEnemy.spawn(self, keys[rng.randi() % keys.size()],
			pos + Vector3(rng.randf_range(-3, 3), 0.5, rng.randf_range(-3, 3)), threat)
		e.dungeon = self
		enemies_alive += 1

func _process(delta: float) -> void:
	if player != null and cam != null:
		var target: Vector3 = player.global_position + Vector3(6.5, 13.5, 9.5)
		if cam_shake > 0.0:
			cam_shake -= delta * 3.0
			target += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * cam_shake
		cam.global_position = cam.global_position.lerp(target, 1.0 - pow(0.001, delta))
	# rain follows player
	clear_timer += delta

func _build_camera() -> void:
	cam = Camera3D.new()
	cam.name = "IsoCam"
	cam.projection = Camera3D.PROJECTION_ORTHOGONAL
	cam.size = 26.0
	cam.far = 200.0
	add_child(cam)
	cam.global_position = player.global_position + Vector3(6.5, 13.5, 9.5)
	cam.look_at(player.global_position, Vector3.UP)
	player.camera = cam
	cam.make_current()

# ---------------- combat callbacks ----------------
func on_enemy_died(e: WCEnemy) -> void:
	enemies_alive = maxi(0, enemies_alive - 1)
	RunManager.register_kill({"name": e.data.get("name", "?"), "xp": e.xp, "creds": e.creds})
	cam_shake = minf(1.2, cam_shake + (0.8 if e.is_boss else 0.25))
	spawn_blast_fx(e.global_position + Vector3(0, 1, 0), 1.6, e.data.get("color", Color.RED))
	# drops
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	WCPickup.spawn(self, e.global_position, "credits", e.creds)
	if rng.randf() < 0.18:
		WCPickup.spawn(self, e.global_position, "health", 15)
	if rng.randf() < 0.12:
		WCPickup.spawn(self, e.global_position, "energy", 20)
	var drop_chance := 0.10 + 0.03 * threat + (0.5 if e.is_boss else 0.0)
	if rng.randf() < drop_chance:
		var item := LootFactory.roll_weapon(threat, RunManager.luck + (1.0 if e.is_boss else 0.0))
		RunManager.register_loot(item)
		WCPickup.spawn(self, e.global_position, "loot", 0, item)
		float_text(e.global_position + Vector3(0, 3, 0),
			"◈ " + String(item["name"]), GameDB.RARITY_COLORS[item["rarity"]])
	if e.is_boss:
		RunManager.boss_dead = true
		float_text(e.global_position + Vector3(0, 4, 0), "TARGET DOWN — EXTRACT!", Color(0.3, 1.0, 0.5))
		extraction_ready.emit()
		# boss shower
		for _i in 3:
			var bonus := LootFactory.roll_weapon(threat, RunManager.luck + 1.0)
			RunManager.register_loot(bonus)
			WCPickup.spawn(self, e.global_position + Vector3(rng.randf_range(-3, 3), 0, rng.randf_range(-3, 3)),
				"loot", 0, bonus)

func _on_exit_enter(body: Node3D) -> void:
	if extracted:
		return
	if not body.is_in_group("player"):
		return
	if RunManager.boss_spawned and not RunManager.boss_dead:
		float_text(exit_pos + Vector3(0, 4, 0), "KILL THE BOSS FIRST", Color(1.0, 0.3, 0.3))
		AudioDirector.play("hurt", 0.7)
		return
	extracted = true
	AudioDirector.play("levelup")
	RunManager.end_run(true)

# ---------------- programs / AoE ----------------
func deploy_turret(pos: Vector3, power: float) -> void:
	WCAlly.spawn(self, pos + Vector3(0, 0.5, 0), "turret", power)
	float_text(pos + Vector3(0, 2, 0), "TURRET ONLINE", Color(0.3, 0.9, 1.0))

func summon_hound(pos: Vector3) -> void:
	WCAlly.spawn(self, pos, "hound", RunManager.program_power)
	float_text(pos + Vector3(0, 2, 0), "HOUND unleashed", Color(1.0, 0.16, 0.43))

func blackout_blast(pos: Vector3, power: float) -> void:
	AudioDirector.play("explode")
	spawn_blast_fx(pos, 6.0, Color(0.3, 0.9, 1.0))
	for o in get_tree().get_nodes_in_group("enemies"):
		if (o as Node3D).global_position.distance_to(pos) < 6.0 and o is WCEnemy:
			(o as WCEnemy).take_hit(90.0 * power, "volt", ["program"], pos)
			(o as WCEnemy).statuses["shocked"] = 4.0
			(o as WCEnemy).statuses["staggered"] = 1.5

func system_shock(pos: Vector3, power: float) -> void:
	AudioDirector.play("synergy")
	var hit: Array = []
	var from := pos
	for _i in 5:
		var best: WCEnemy = null
		var best_d := 12.0
		for o in get_tree().get_nodes_in_group("enemies"):
			if o in hit or not (o is WCEnemy) or (o as WCEnemy).dead:
				continue
			var d: float = from.distance_to((o as Node3D).global_position)
			if d < best_d:
				best_d = d
				best = o
		if best == null:
			break
		hit.append(best)
		spawn_beam_fx(from + Vector3(0, 1.5, 0), best.global_position + Vector3(0, 1.2, 0), Color(0.4, 0.95, 1.0))
		from = best.global_position
		best.take_hit(55.0 * power, "volt", ["program"], pos)
		best.statuses["marked"] = 4.0
		best.statuses["shocked"] = 3.0

func offer_loot(item: Dictionary) -> void:
	loot_offered.emit(item)
	# auto-compare: equip if strictly better DPS and same-or-better rarity tier
	var cur: Dictionary = RunManager.loadout.get("primary", {})
	if cur.is_empty() or float(item.get("dps", 0)) > float(cur.get("dps", 0)) * 1.08:
		RunManager.loadout["primary"] = item
		player.weapon = item
		player.wbase = GameDB.WEAPONS[String(item.get("weapon_id", "smg"))]
		float_text(player.global_position + Vector3(0, 2.6, 0),
			"AUTO-EQUIPPED: " + String(item["name"]), GameDB.RARITY_COLORS[item["rarity"]])

# ---------------- FX ----------------
func float_text(pos: Vector3, text: String, color: Color) -> void:
	var label := Label3D.new()
	label.text = text
	label.font_size = 64
	label.pixel_size = 0.012
	label.modulate = color
	label.outline_size = 12
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	float_layer.add_child(label)
	label.global_position = pos
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y + 1.6, 1.1)
	tw.tween_property(label, "modulate:a", 0.0, 1.1)
	tw.chain().tween_callback(label.queue_free)

func spawn_blast_fx(pos: Vector3, radius: float, color: Color) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	m.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 3.5
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	fx_layer.add_child(m)
	m.global_position = pos
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * radius * 2.0, 0.3)
	tw.tween_property(m, "transparency", 1.0, 0.35)
	tw.chain().tween_callback(m.queue_free)

func spawn_slash_fx(pos: Vector3, dir: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.4, 0.12, 0.5)
	m.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	fx_layer.add_child(m)
	m.global_position = pos
	m.rotation.y = atan2(-dir.x, -dir.z)
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3(1.6, 1, 1), 0.15)
	tw.tween_property(m, "transparency", 1.0, 0.18)
	tw.chain().tween_callback(m.queue_free)

func spawn_beam_fx(a: Vector3, b: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var cm := CylinderMesh.new()
	cm.top_radius = 0.08
	cm.bottom_radius = 0.08
	var dist := a.distance_to(b)
	cm.height = dist
	m.mesh = cm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	fx_layer.add_child(m)
	m.global_position = (a + b) / 2.0
	m.look_at(b, Vector3.UP)
	m.rotate_object_local(Vector3.RIGHT, PI / 2.0)
	var tw := m.create_tween()
	tw.tween_property(m, "transparency", 1.0, 0.25)
	tw.tween_callback(m.queue_free)
