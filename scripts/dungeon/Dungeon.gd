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
var vault_center := Vector3.ZERO
var has_vault := false
var vault_item := {}
var _offer_n := 0
var terminals: Array = []
var zone_names: Array = []
var cur_zone := 0
var _zone_t := 0.0
var _glow_mats := {}
var _terminal_mat: StandardMaterial3D
var clear_timer := 0.0
var float_layer: Node3D
var fx_layer: Node3D
var _slowmo_token := 0
var _streak := 0
var _last_kill_t := -99.0

func setup(p_contract: Dictionary) -> void:
	contract = p_contract
	threat = int(p_contract.get("threat", 1))
	var rooms_per_zone := 4 + threat
	layout = _generate_layout(threat, rooms_per_zone, 3)
	var sector := String(p_contract.get("sector", "The Sprawl"))
	zone_names = ["%s — APPROACH" % sector, "%s — SPRAWL" % sector, "%s — CORE" % sector]
	cur_zone = 0

static func rust_available() -> bool:
	return ClassDB.class_exists("WCDungeonRust")

func _generate_layout(p_threat: int, rooms_per_zone: int, zones: int) -> Dictionary:
	## Prefer the compiled Rust core when present; GDScript fallback otherwise.
	if rust_available():
		var rust = ClassDB.instantiate("WCDungeonRust")
		var seed := randi()
		var raw = rust.call("generate_sector", seed, p_threat, rooms_per_zone, zones)
		rust.free()
		if typeof(raw) == TYPE_DICTIONARY:
			var d: Dictionary = raw
			if not d.is_empty() and (d.get("rooms") as Array).size() >= rooms_per_zone:
				return d
	return DungeonGen.generate_sector(p_threat, rooms_per_zone, 0, zones)

func zone_of(cell: Vector2i) -> int:
	var w: int = layout["w"]
	var borders: Array = layout.get("borders", [])
	var z := 0
	for b in borders.size():
		var bd: Dictionary = borders[b]
		var cut: float = float(w) * float(b + 1) / float(borders.size() + 1)
		cut += float(bd["amp"]) * sin(float(cell.y) * float(bd["freq"]) + float(bd["phase"]))
		if cell.x >= int(cut):
			z = b + 1
	return z

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
	e.ambient_light_color = Color(0.14, 0.12, 0.26)
	e.ambient_light_energy = 1.6
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
	sun.light_color = Color(0.62, 0.58, 0.95)
	sun.light_energy = 0.95
	sun.shadow_enabled = false
	add_child(sun)
	# Cool fill from the camera side so faces turned from the key stay
	# modeled instead of falling to flat black at some angles.
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-52, 32, 0)
	fill.light_color = Color(0.45, 0.65, 1.0)
	fill.light_energy = 0.45
	fill.shadow_enabled = false
	add_child(fill)
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
	_build_skyline()

func _build_skyline() -> void:
	## Distant neon megastructure silhouettes ringing the sector.
	if layout.is_empty():
		return
	var w: int = layout["w"]
	var h: int = layout["h"]
	var rng := RandomNumberGenerator.new()
	rng.seed = int(layout["seed"]) ^ 0x5eed
	var cols := [Color(0.02, 0.85, 0.91), Color(1.0, 0.16, 0.43),
		Color(0.976, 0.941, 0.008), Color(0.75, 0.35, 1.0)]
	var half_w := w * CELL / 2.0
	var half_h := h * CELL / 2.0
	for i in 46:
		var side := i % 4
		var px := 0.0
		var pz := 0.0
		match side:
			0: px = rng.randf_range(-half_w, half_w); pz = -half_h - rng.randf_range(14, 60)
			1: px = rng.randf_range(-half_w, half_w); pz = half_h + rng.randf_range(14, 60)
			2: px = -half_w - rng.randf_range(14, 60); pz = rng.randf_range(-half_h, half_h)
			_: px = half_w + rng.randf_range(14, 60); pz = rng.randf_range(-half_h, half_h)
		var bw := rng.randf_range(6, 16)
		var bh := rng.randf_range(10, 46)
		var bd := rng.randf_range(6, 16)
		var col: Color = cols[rng.randi() % cols.size()]
		var tower := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(bw, bh, bd)
		tower.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.01, 0.01, 0.03)
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = rng.randf_range(0.25, 0.8)
		tower.material_override = mat
		tower.position = Vector3(px, bh / 2.0 - 2.0, pz)
		add_child(tower)
		# lit crown
		if rng.randf() < 0.6:
			var crown := MeshInstance3D.new()
			var cm := BoxMesh.new()
			cm.size = Vector3(bw * 0.7, 0.5, bd * 0.7)
			crown.mesh = cm
			var cmat := StandardMaterial3D.new()
			cmat.albedo_color = col
			cmat.emission_enabled = true
			cmat.emission = col
			cmat.emission_energy_multiplier = 3.5
			cmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			crown.material_override = cmat
			crown.position = Vector3(px, bh - 1.75, pz)
			add_child(crown)

func _glow_mat(col: Color) -> ShaderMaterial:
	## Radial-falloff glow decal (planar UV): soft neon instead of flat stickers.
	var key := col.to_html(false)
	if _glow_mats.has(key):
		return _glow_mats[key]
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode unshaded, cull_disabled;
uniform vec4 glow_color : source_color = vec4(0.02, 0.85, 0.91, 1.0);
uniform float pulse_speed = 2.0;
uniform float pulse_amp = 0.18;
void fragment() {
	vec2 cuv = UV - vec2(0.5);
	float d = clamp(length(cuv) * 2.0, 0.0, 1.0);
	float a = (1.0 - d) * (1.0 - d);
	float p = 1.0 + pulse_amp * sin(TIME * pulse_speed + UV.x * 6.2831);
	ALBEDO = glow_color.rgb;
	EMISSION = glow_color.rgb * 2.2 * p;
	ALPHA = a * glow_color.a;
}
"""
	var m := ShaderMaterial.new()
	m.shader = sh
	m.set_shader_parameter("glow_color", col)
	_glow_mats[key] = m
	return m

func _neon_grid_material() -> ShaderMaterial:
	var sh := Shader.new()
	sh.code = """
shader_type spatial;
render_mode diffuse_lambert, specular_disabled;
uniform vec4 base_color : source_color = vec4(0.015, 0.015, 0.045, 1.0);
uniform vec4 line_cyan : source_color = vec4(0.02, 0.85, 0.91, 1.0);
uniform vec4 line_pink : source_color = vec4(1.0, 0.16, 0.43, 1.0);
varying vec3 wpos;
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
void vertex() { wpos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz; }
void fragment() {
	vec2 cell = floor(wpos.xz / 4.0);
	float h = hash(cell);
	vec2 g = abs(fract(wpos.xz / 4.0) - 0.5);
	float line = smoothstep(0.46, 0.5, max(g.x, g.y));
	float core = smoothstep(0.487, 0.5, max(g.x, g.y));
	float flow = 0.85 + 0.15 * sin(wpos.x * 0.4 + wpos.z * 0.23 - TIME * 1.6);
	vec2 sub = abs(fract(wpos.xz / 1.0) - 0.5);
	float subline = smoothstep(0.44, 0.5, max(sub.x, sub.y)) * 0.25;
	vec2 g2 = abs(fract(wpos.xz / 20.0) - 0.5);
	float major = smoothstep(0.465, 0.5, max(g2.x, g2.y));
	float checker = mod(cell.x + cell.y, 2.0);
	// per-tile tonal variety + occasional hot data tile
	vec3 col = base_color.rgb * (0.75 + h * 0.5) + checker * 0.012;
	col += vec3(0.05, 0.02, 0.10) * smoothstep(0.6, 1.0, sin(wpos.x * 0.11) * sin(wpos.z * 0.13));
	vec3 line_col = mix(line_cyan.rgb, line_pink.rgb, step(0.82, h));
	float data_tile = step(0.965, h);
	col += line_col * (line * 0.55 + subline * 0.4);
	col += line_pink.rgb * major * 0.9;
	col += line_cyan.rgb * data_tile * (0.5 + 0.5 * sin(TIME * 2.0 + h * 40.0));
	// circuit traces: sparse axis runs with dash gaps + node pads
	vec2 big = floor(wpos.xz / 8.0);
	float seg = step(0.78, hash(big * 0.5 + 3.7));
	float dashx = step(0.45, fract(wpos.x * 0.125));
	float dashz = step(0.45, fract(wpos.z * 0.125));
	float trace_h = smoothstep(0.03, 0.008, abs(fract(wpos.z / 8.0) - 0.5)) * seg * dashx;
	float trace_v = smoothstep(0.03, 0.008, abs(fract(wpos.x / 8.0) - 0.5)) * seg * dashz;
	vec2 pad_uv = abs(fract(wpos.xz / 8.0) - 0.5);
	float pad = smoothstep(0.045, 0.015, length(pad_uv)) * seg;
	col += line_cyan.rgb * (trace_h + trace_v) * 0.8;
	col += line_pink.rgb * pad * 1.2;
	// data pools: soft radial glow fields on hashed blocks
	vec2 pb = floor(wpos.xz / 24.0);
	float pool = smoothstep(0.22, 0.05, length(fract(wpos.xz / 24.0) - 0.5)) * step(0.68, hash(pb + 9.1));
	col += mix(line_cyan.rgb, line_pink.rgb, hash(pb + 4.2)) * pool * 0.35;
	ALBEDO = col;
	EMISSION = (line_col * (line * 1.6 + subline * 0.5) + vec3(1.0) * core * 1.2) * flow
		+ line_pink.rgb * major * 2.2
		+ line_cyan.rgb * data_tile * 2.5
		+ line_cyan.rgb * (trace_h + trace_v) * 1.8 + line_pink.rgb * pad * 2.4;
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
	wall_mat.albedo_color = Color(0.035, 0.038, 0.085)
	wall_mat.emission_enabled = true
	wall_mat.emission = Color(0.35, 0.06, 0.16)
	wall_mat.emission_energy_multiplier = 0.09
	wall_mat.metallic = 0.55
	wall_mat.roughness = 0.5
	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color(0.02, 0.85, 0.91)
	trim_mat.emission_enabled = true
	trim_mat.emission = Color(0.02, 0.85, 0.91)
	trim_mat.emission_energy_multiplier = 3.0
	trim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var trim_palette: Array = [trim_mat]
	for pc in [Color(1.0, 0.16, 0.43), Color(0.976, 0.941, 0.008), Color(0.55, 0.4, 1.0)]:
		var pmat := StandardMaterial3D.new()
		pmat.albedo_color = pc
		pmat.emission_enabled = true
		pmat.emission = pc
		pmat.emission_energy_multiplier = 3.0
		pmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		trim_palette.append(pmat)
	var win_pink: StandardMaterial3D = trim_palette[1]
	var walls := StaticBody3D.new()
	walls.collision_layer = 1
	walls.collision_mask = 0
	add_child(walls)
	var wlrng := RandomNumberGenerator.new()
	wlrng.seed = int(layout["seed"]) ^ 0xbeef
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
				var run_trim: StandardMaterial3D = trim_palette[absi(x * 7 + y * 13) % trim_palette.size()]
				trim.material_override = run_trim
				trim.position = Vector3(cx, 3.45, cz - CELL / 2.0 + 0.06)
				walls.add_child(trim)
				# lit window strips on the floor-facing side
				var mx := x + (x2 - x) / 2
				var faced := 0
				for face in [-1, 1]:
					var ny: int = y + face
					if ny >= 0 and ny < h and tiles[ny * w + mx] != DungeonGen.TILE_VOID:
						faced = face
				if faced != 0 and wlrng.randf() < 0.8:
					var span := x2 - x
					var nwin := clampi(span / 4, 1, 3)
					for k in nwin:
						var wcell := x + 1 + int(float(maxi(span - 2, 1)) * (float(k) + 0.5) / float(nwin))
						var wx := ox + (float(wcell) + 0.5) * CELL
						var wz := oz + (float(y) + 0.5) * CELL + float(faced) * (CELL / 2.0 + 0.06)
						var win := MeshInstance3D.new()
						var wqm := QuadMesh.new()
						wqm.size = Vector2(1.7, 0.9)
						win.mesh = wqm
						win.material_override = _glow_mat(Color(0.02, 0.85, 0.91) if ((x + k) % 2 == 0) else Color(1.0, 0.16, 0.43))
						win.position = Vector3(wx, 2.1, wz)
						if faced < 0:
							win.rotation.y = PI
						walls.add_child(win)
						# bright core so windows read as lit, not flat paint
						var core := MeshInstance3D.new()
						var cqm := QuadMesh.new()
						cqm.size = Vector2(1.0, 0.5)
						core.mesh = cqm
						core.material_override = _glow_mat(Color(0.85, 0.95, 1.0))
						core.position = Vector3(wx, 2.1, wz + (0.03 if faced >= 0 else -0.03))
						if faced < 0:
							core.rotation.y = PI
						walls.add_child(core)
				# conduit pipe along the run's middle (short of the ends so it
				# never floats across openings; drops removed — they read as
				# sticks in open floor wherever facing flips mid-run)
				if wlrng.randf() < 0.85:
					var face_sign := 1.0 if faced >= 0 else -1.0
					var pipe := MeshInstance3D.new()
					var pm2 := BoxMesh.new()
					pm2.size = Vector3(maxf(length * 0.6 - 0.4, 1.0), 0.18, 0.18)
					pipe.mesh = pm2
					pipe.material_override = wall_mat
					pipe.position = Vector3(cx, 2.95, cz + face_sign * (CELL / 2.0 + 0.12))
					walls.add_child(pipe)
				x = x2
			else:
				x += 1
	_room_tints()
	_build_props(ox, oz)
	_build_exit(ox, oz)

func _room_tints() -> void:
	## Subtle per-room floor glow so sectors read as distinct zones.
	var cols := [Color(0.02, 0.85, 0.91), Color(1.0, 0.16, 0.43),
		Color(0.976, 0.941, 0.008), Color(0.55, 0.4, 1.0)]
	var ti := 0
	for r in layout["rooms"] as Array:
		var room := r as Rect2i
		var col: Color = cols[ti % cols.size()]
		ti += 1
		var q := MeshInstance3D.new()
		var qm := QuadMesh.new()
		qm.size = Vector2(float(room.size.x) * CELL * 0.94, float(room.size.y) * CELL * 0.94)
		q.mesh = qm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(col.r, col.g, col.b, 0.07)
		mat.emission_enabled = true
		mat.emission = col
		mat.emission_energy_multiplier = 0.5
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		q.material_override = mat
		q.rotation.x = -PI / 2.0
		q.position = _cell_to_world(Vector2i(room.position.x + room.size.x / 2,
			room.position.y + room.size.y / 2)) + Vector3(0, 0.025, 0)
		add_child(q)

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
	var holo_colors := [Color(0.02, 0.85, 0.91), Color(1.0, 0.16, 0.43), Color(0.976, 0.941, 0.008)]
	var props := StaticBody3D.new()
	props.collision_layer = 1
	props.collision_mask = 0
	add_child(props)
	var placed := 0
	var ri := 0
	for r in layout["rooms"] as Array:
		var room := r as Rect2i
		# holo billboard pillar at room corner (lights throttled: every 3rd
		# room or special rooms, to bound forward-render light counts)
		var corner := Vector2i(room.position.x + 1, room.position.y + 1)
		var hc: Color = holo_colors[rng.randi() % holo_colors.size()]
		_holo_pillar(props, _cell_to_world(corner) + Vector3(0, 0, 0), hc,
			ri % 3 == 0 or _room_has_tile(room, DungeonGen.TILE_LOOT))
		ri += 1
		# crates: 0-3 per room, never on spawn/exit
		for _i in rng.randi_range(0, 2):
			var cx := rng.randi_range(room.position.x + 1, room.position.x + room.size.x - 2)
			var cy := rng.randi_range(room.position.y + 1, room.position.y + room.size.y - 2)
			if tiles[cy * w + cx] == DungeonGen.TILE_VOID:
				continue
			var wp := _cell_to_world(Vector2i(cx, cy))
			if wp.distance_to(_cell_to_world(layout["spawn"])) < 6.0:
				continue
			var crate := WCPropCrate.spawn(props, wp + Vector3(rng.randf_range(-1, 1), 0, rng.randf_range(-1, 1)),
				rng.randf_range(0.8, 1.4))
			crate.dungeon = self
			placed += 1
			if placed > 40:
				break
		# cover pillars in large rooms (combat geometry)
		if room.size.x >= 10 and room.size.y >= 9 and rng.randf() < 0.55:
			var center := Vector2i(room.position.x + room.size.x / 2, room.position.y + room.size.y / 2)
			for _pi in rng.randi_range(1, 2):
				var pc := Vector2i(rng.randi_range(room.position.x + 2, room.position.x + room.size.x - 3),
					rng.randi_range(room.position.y + 2, room.position.y + room.size.y - 3))
				if pc == center or pc == center + Vector2i(1, 0):
					continue
				if tiles[pc.y * w + pc.x] == DungeonGen.TILE_VOID:
					continue
				_pillar(props, _cell_to_world(pc), rng)
	_floor_dressing(props, rng)

func _floor_dressing(parent: Node, rng: RandomNumberGenerator) -> void:
	## Flat glow inlays on the floor: drains, hazard strips, data rings.
	var tiles: PackedByteArray = layout["tiles"]
	var w: int = layout["w"]
	var h: int = layout["h"]
	var cols := [Color(0.02, 0.85, 0.91), Color(1.0, 0.16, 0.43), Color(0.976, 0.941, 0.008)]
	for _i in 30:
		var cx := rng.randi_range(1, w - 2)
		var cy := rng.randi_range(1, h - 2)
		if tiles[cy * w + cx] == DungeonGen.TILE_VOID:
			continue
		var col: Color = cols[rng.randi() % cols.size()]
		var quad := MeshInstance3D.new()
		var qm := QuadMesh.new()
		var kind := rng.randi() % 3
		if kind == 0:
			qm.size = Vector2(1.6, 1.6)
		elif kind == 1:
			qm.size = Vector2(3.2, 0.35)
		else:
			qm.size = Vector2(0.5, 2.4)
		quad.mesh = qm
		quad.material_override = _glow_mat(Color(col.r, col.g, col.b, 0.85))
		quad.rotation.x = -PI / 2.0
		quad.rotation.z = rng.randf() * PI if kind != 0 else 0.0
		quad.position = _cell_to_world(Vector2i(cx, cy)) + Vector3(rng.randf_range(-1, 1), 0.03, rng.randf_range(-1, 1))
		parent.add_child(quad)

func _pillar(parent: Node, pos: Vector3, rng: RandomNumberGenerator) -> void:
	var pillar := MeshInstance3D.new()
	var bm := BoxMesh.new()
	bm.size = Vector3(2.2, 4.2, 2.2)
	pillar.mesh = bm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.04, 0.04, 0.09)
	mat.emission_enabled = true
	mat.emission = Color(0.02, 0.85, 0.91) if rng.randf() < 0.5 else Color(1.0, 0.16, 0.43)
	mat.emission_energy_multiplier = 0.7
	mat.metallic = 0.6
	mat.roughness = 0.45
	pillar.material_override = mat
	pillar.position = pos + Vector3(0, 2.1, 0)
	parent.add_child(pillar)
	var cs := CollisionShape3D.new()
	var bs := BoxShape3D.new()
	bs.size = Vector3(2.2, 4.2, 2.2)
	cs.shape = bs
	cs.position = pillar.position
	parent.add_child(cs)

func _holo_pillar(parent: Node, pos: Vector3, col: Color, with_light := true) -> void:
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
	# gentle hover animation
	var bob := sign_mesh.create_tween()
	bob.set_loops()
	bob.tween_property(sign_mesh, "position:y", sign_mesh.position.y + 0.35, 1.6).set_ease(Tween.EASE_IN_OUT)
	bob.tween_property(sign_mesh, "position:y", sign_mesh.position.y, 1.6).set_ease(Tween.EASE_IN_OUT)
	if with_light:
		var light := OmniLight3D.new()
		light.light_color = col
		light.light_energy = 1.2
		light.omni_range = 10.0
		light.position = pos + Vector3(0, 3.0, 0)
		parent.add_child(light)
	# hackable terminal marker: shared pulsing gold ring at the pillar base
	var tring := MeshInstance3D.new()
	var ttm := TorusMesh.new()
	ttm.inner_radius = 0.7
	ttm.outer_radius = 0.9
	tring.mesh = ttm
	if _terminal_mat == null:
		_terminal_mat = StandardMaterial3D.new()
		_terminal_mat.albedo_color = Color(0.35, 0.3, 0.05)
		_terminal_mat.emission_enabled = true
		_terminal_mat.emission = Color(0.976, 0.941, 0.008)
		_terminal_mat.emission_energy_multiplier = 1.1
		_terminal_mat.metallic = 0.6
		_terminal_mat.roughness = 0.4
		var pulse := create_tween()
		pulse.set_loops()
		pulse.tween_property(_terminal_mat, "emission_energy_multiplier", 1.9, 1.2).set_ease(Tween.EASE_IN_OUT)
		pulse.tween_property(_terminal_mat, "emission_energy_multiplier", 1.1, 1.2).set_ease(Tween.EASE_IN_OUT)
	tring.material_override = _terminal_mat
	tring.position = pos + Vector3(0, 0.08, 0)
	parent.add_child(tring)
	terminals.append({"pos": pos + Vector3(0, 0, 0), "taken": false, "ring": tring})

func nearest_terminal(pos: Vector3) -> int:
	for i in terminals.size():
		var t: Dictionary = terminals[i]
		if bool(t.get("taken", true)):
			continue
		if (t["pos"] as Vector3).distance_to(pos) < 3.4:
			return i
	return -1

func try_hack() -> void:
	if player == null or not is_instance_valid(player):
		return
	var idx := nearest_terminal(player.global_position)
	if idx < 0:
		return
	var t: Dictionary = terminals[idx]
	t["taken"] = true
	terminals[idx] = t
	var ring := t.get("ring") as MeshInstance3D
	if ring != null and is_instance_valid(ring):
		ring.queue_free()
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var creds := rng.randi_range(25, 60)
	RunManager.credits_earned += creds
	RunManager.energy = minf(RunManager.max_energy, RunManager.energy + 40.0)
	AudioDirector.play("pickup", 1.4)
	float_text(player.global_position + Vector3(0, 2.6, 0), "HACKED +%dcr" % creds,
		Color(0.976, 0.941, 0.008))
	spawn_blast_fx(player.global_position + Vector3(0, 1.0, 0), 1.5, Color(0.976, 0.941, 0.008))
	if rng.randf() < 0.25:
		var bonus := LootFactory.roll_weapon(threat, RunManager.luck)
		RunManager.register_loot(bonus)
		WCPickup.spawn(self, player.global_position + Vector3(1.5, 0, 0), "loot", 0, bonus)

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
	var pulse := beam.create_tween()
	pulse.set_loops()
	pulse.tween_property(beam, "scale:x", 1.25, 0.9).set_ease(Tween.EASE_IN_OUT)
	pulse.parallel().tween_property(beam, "scale:z", 1.25, 0.9).set_ease(Tween.EASE_IN_OUT)
	pulse.tween_property(beam, "scale:x", 1.0, 0.9).set_ease(Tween.EASE_IN_OUT)
	pulse.parallel().tween_property(beam, "scale:z", 1.0, 0.9).set_ease(Tween.EASE_IN_OUT)
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
	var room_zones: Array = layout.get("room_zones", [])
	var keys := ["punk", "razor", "drone", "enforcer", "hexer", "brute"]
	for i in range(1, rooms_total):
		var room: Rect2i = (layout["rooms"] as Array)[i]
		var z: int = int(room_zones[i]) if i < room_zones.size() else 0
		var teff := threat + z
		var center := Vector2i(room.position.x + room.size.x / 2, room.position.y + room.size.y / 2)
		var count := 2 + rng.randi() % 2 + (1 if teff >= 3 else 0)
		if tiles_at(center) == DungeonGen.TILE_AMBUSH:
			count += 2
		for _k in count:
			var cell := Vector2i(rng.randi_range(room.position.x + 1, room.position.x + room.size.x - 2),
				rng.randi_range(room.position.y + 1, room.position.y + room.size.y - 2))
			if not DungeonGen.is_walkable(layout, cell.x, cell.y):
				continue
			var ek := _pick_enemy(rng, keys, teff)
			var e := WCEnemy.spawn(self, ek, _cell_to_world(cell) + Vector3(0, 0.5, 0), teff)
			e.dungeon = self
			if rng.randf() < 0.12 + 0.03 * z and not e.is_boss:
				e.make_elite()
				float_text(e.global_position + Vector3(0, 2.6, 0), "★ ELITE", Color(0.976, 0.941, 0.008))
			enemies_alive += 1
		# loot chest in loot rooms (deeper zones pay better luck)
		if _room_has_tile(room, DungeonGen.TILE_LOOT):
			var item := LootFactory.roll_weapon(teff, RunManager.luck + 0.5 + 0.3 * z)
			RunManager.register_loot(item)
			WCPickup.spawn(self, _cell_to_world(center) + Vector3(1.5, 0, 0), "loot", 0, item)
			if rng.randf() < 0.5:
				WCPickup.spawn(self, _cell_to_world(center) + Vector3(-1.5, 0, 0), "health", 25)
	# boss?
	var boss_key := String(contract.get("boss", ""))
	if boss_key != "":
		_spawn_boss(boss_key)
	_build_vault(rng)

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

func _pick_enemy(rng: RandomNumberGenerator, keys: Array, teff: int) -> String:
	var t := teff
	var pool := ["punk", "punk", "razor", "drone"]
	if t >= 2:
		pool += ["enforcer", "hexer", "razor"]
	if t >= 3:
		pool += ["brute", "enforcer"]
	if t >= 4:
		pool += ["brute", "hexer", "hexer"]
	return pool[rng.randi() % pool.size()]

func _build_vault(rng: RandomNumberGenerator) -> void:
	## Secret vault: farthest non-exit room gets elite guards + epic+ loot.
	var rooms: Array = layout.get("rooms", [])
	var spawn_cell: Vector2i = layout.get("spawn", Vector2i.ZERO)
	var exit_cell: Vector2i = layout.get("exit", Vector2i.ZERO)
	var best_room := -1
	var best_d := -1.0
	for i in range(1, rooms.size()):
		var room := rooms[i] as Rect2i
		var c := Vector2i(room.position.x + room.size.x / 2, room.position.y + room.size.y / 2)
		if c == exit_cell:
			continue
		var d := Vector2(c - spawn_cell).length()
		if d > best_d:
			best_d = d
			best_room = i
	if best_room < 0:
		return
	var vroom := rooms[best_room] as Rect2i
	var vc := Vector2i(vroom.position.x + vroom.size.x / 2, vroom.position.y + vroom.size.y / 2)
	vault_center = _cell_to_world(vc)
	has_vault = true
	for _g in 2:
		var cell := Vector2i(rng.randi_range(vroom.position.x + 1, vroom.position.x + vroom.size.x - 2),
			rng.randi_range(vroom.position.y + 1, vroom.position.y + vroom.size.y - 2))
		if not DungeonGen.is_walkable(layout, cell.x, cell.y):
			continue
		var guard := WCEnemy.spawn(self, ["enforcer", "hexer", "brute"][rng.randi() % 3],
			_cell_to_world(cell) + Vector3(0, 0.5, 0), threat + 1)
		guard.dungeon = self
		guard.make_elite()
		enemies_alive += 1
	vault_item = LootFactory.roll_weapon(threat + 1, RunManager.luck + 1.5)
	for _r in 6:
		if String(vault_item.get("rarity", "")) in ["epic", "legendary", "mythic"]:
			break
		vault_item = LootFactory.roll_weapon(threat + 1, RunManager.luck + 1.5)
	if not (String(vault_item.get("rarity", "")) in ["epic", "legendary", "mythic"]):
		vault_item = LootFactory.roll_weapon(threat + 1, RunManager.luck + 1.5, "", "epic")
	RunManager.register_loot(vault_item)
	WCPickup.spawn(self, vault_center + Vector3(0, 0, 0), "loot", 0, vault_item)
	WCPickup.spawn(self, vault_center + Vector3(1.5, 0, 0), "health", 40)
	float_text(vault_center + Vector3(0, 4, 0), "◆ VAULT ◆", Color(0.976, 0.941, 0.008))

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
		var shake_on := bool(SaveSystem.profile.get("settings", {}).get("screenshake", true))
		if cam_shake > 0.0 and shake_on:
			cam_shake -= delta * 3.0
			target += Vector3(randf_range(-1, 1), 0, randf_range(-1, 1)) * cam_shake
		elif not shake_on:
			cam_shake = 0.0
		cam.global_position = cam.global_position.lerp(target, 1.0 - pow(0.001, delta))
	# rain follows player
	clear_timer += delta
	_zone_t -= delta
	if _zone_t <= 0.0 and player != null:
		_zone_t = 0.5
		var z := zone_of(_world_to_cell(player.global_position))
		if z != cur_zone:
			cur_zone = z
			if z < zone_names.size():
				float_text(player.global_position + Vector3(0, 4.5, 0),
					"◆ %s ◆" % String(zone_names[z]), Color(0.02, 0.85, 0.91))
				AudioDirector.play("levelup", 1.2)

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
	hitstop(0.15, 0.35 if e.is_boss else 0.05)
	# kill streak callouts
	if clear_timer - _last_kill_t < 3.0:
		_streak += 1
	else:
		_streak = 1
	_last_kill_t = clear_timer
	var callout := ""
	match _streak:
		2: callout = "DOUBLE KILL!"
		3: callout = "TRIPLE KILL!"
		4: callout = "RAMPAGE!"
		5: callout = "OVERDRIVE x5!"
	if _streak > 5:
		callout = "OVERDRIVE x%d!" % _streak
	if callout != "" and player != null and is_instance_valid(player):
		float_text(player.global_position + Vector3(0, 3.0, 0), callout,
			Color(0.976, 0.941, 0.008))
		if _streak >= 3:
			AudioDirector.play("synergy", 1.2)
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
	var drop_chance := 0.10 + 0.03 * threat + (0.5 if e.is_boss else 0.0) + (0.35 if e.elite else 0.0)
	if rng.randf() < drop_chance:
		var item := LootFactory.roll_weapon(threat, RunManager.luck + (1.0 if e.is_boss else 0.0) + (0.5 if e.elite else 0.0))
		RunManager.register_loot(item)
		WCPickup.spawn(self, e.global_position, "loot", 0, item)
		float_text(e.global_position + Vector3(0, 3, 0),
			"◈ " + String(item["name"]), GameDB.RARITY_COLORS[item["rarity"]])
	if e.elite:
		float_text(e.global_position + Vector3(0, 4, 0), "ELITE DOWN", Color(0.976, 0.941, 0.008))
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
	## Loot choice flows to the HUD panel ([1]/[2]/click); no auto-equip.
	loot_offered.emit(item)
	_offer_n += 1
	if player != null and is_instance_valid(player):
		float_text(player.global_position + Vector3(0, 3.0 + float(_offer_n % 3) * 0.8, 0),
			"◈ " + String(item["name"]), GameDB.RARITY_COLORS[item["rarity"]])

# ---------------- FX ----------------
func hitstop(scale := 0.25, dur := 0.06) -> void:
	_slowmo_token += 1
	var token := _slowmo_token
	Engine.time_scale = scale
	await get_tree().create_timer(dur, true, false, true).timeout
	if token == _slowmo_token and not get_tree().paused:
		Engine.time_scale = 1.0

func spawn_damage_number(pos: Vector3, amount: float, killing := false) -> void:
	var label := Label3D.new()
	label.text = "%d" % int(amount)
	label.font_size = 96 if killing else 48
	label.pixel_size = 0.008
	label.modulate = Color(0.976, 0.941, 0.008) if killing else Color(1, 1, 1, 0.9)
	label.outline_size = 8
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	float_layer.add_child(label)
	label.global_position = pos + Vector3(randf_range(-0.4, 0.4), 0, 0)
	var tw := label.create_tween()
	tw.set_parallel(true)
	tw.tween_property(label, "position:y", label.position.y + 1.2, 0.55)
	tw.tween_property(label, "modulate:a", 0.0, 0.55)
	tw.chain().tween_callback(label.queue_free)

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

func spawn_flash_fx(pos: Vector3, color: Color) -> void:
	var m := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.32
	sm.height = 0.64
	m.mesh = sm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 5.0
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	fx_layer.add_child(m)
	m.global_position = pos
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * 1.8, 0.09)
	tw.tween_property(m, "transparency", 1.0, 0.09)
	tw.chain().tween_callback(m.queue_free)

func spawn_impact_fx(pos: Vector3, color: Color) -> void:
	## Wall/floor hit: hot flash + spark ring + debris kick.
	spawn_flash_fx(pos, color.lightened(0.4))
	var m := MeshInstance3D.new()
	var tm := TorusMesh.new()
	tm.inner_radius = 0.12
	tm.outer_radius = 0.3
	m.mesh = tm
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.emission_enabled = true
	mat.emission = color
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.material_override = mat
	fx_layer.add_child(m)
	m.global_position = pos
	var tw := m.create_tween()
	tw.set_parallel(true)
	tw.tween_property(m, "scale", Vector3.ONE * 2.6, 0.22)
	tw.tween_property(m, "transparency", 1.0, 0.22)
	tw.chain().tween_callback(m.queue_free)

func spawn_blast_fx(pos: Vector3, radius: float, color: Color) -> void:
	spawn_flash_fx(pos, color.lightened(0.5))
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
	## True crescent swoosh: shards placed along an arc in front of the
	## swing (facing convention: forward = (-sin yaw, 0, -cos yaw)),
	## sweeping forward and blooming outward as they fade.
	var base_yaw := atan2(-dir.x, -dir.z)
	var count := 7
	for k in count:
		var a := base_yaw - 0.75 + 1.5 * float(k) / float(count - 1)
		var off := Vector3(-sin(a), 0, -cos(a)) * 2.1
		var m := MeshInstance3D.new()
		var bm := BoxMesh.new()
		var core := k >= 2 and k <= 4
		bm.size = Vector3(0.55 if core else 0.35, 0.12, 0.28)
		m.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.emission_enabled = true
		mat.emission = color.lightened(0.35) if core else color
		mat.emission_energy_multiplier = 5.5 if core else 3.0
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.material_override = mat
		fx_layer.add_child(m)
		m.global_position = pos + off
		m.rotation.y = a + PI
		var tw := m.create_tween()
		tw.set_parallel(true)
		tw.tween_property(m, "rotation:y", a + PI + 0.5, 0.18).set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
		tw.tween_property(m, "position", m.position + off.normalized() * 0.9, 0.18)
		tw.tween_property(m, "scale", Vector3(1.4, 1, 1), 0.18)
		tw.tween_property(m, "transparency", 1.0, 0.2)
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
