extends Node
## DungeonGen — deterministic procedural sector layouts (seeded).
## Single-district `generate()` plus multi-zone `generate_sector()`: an
## elongated grid split into wiggly-bordered zones chained west→east, rooms
## dealt per zone and connected in zone order for sequential traversal.
## Output adds: zones, borders[], room_zones[].
## Hot paths are mirrored in rust_ext/src/lib.rs.

const TILE_VOID := 0
const TILE_FLOOR := 1
const TILE_CORRIDOR := 2
const TILE_SPAWN := 3
const TILE_EXIT := 4
const TILE_LOOT := 5
const TILE_AMBUSH := 6

func generate(threat: int, room_target := 9, dungeon_seed := 0) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	if dungeon_seed == 0:
		rng.randomize()
		dungeon_seed = rng.randi()
	rng.seed = dungeon_seed
	var w := 64
	var h := 64
	var tiles := PackedByteArray()
	tiles.resize(w * h)
	tiles.fill(TILE_VOID)
	var rooms: Array = []
	var attempts := 0
	var want: int = room_target + mini(threat / 2, 3)
	while rooms.size() < want and attempts < 220:
		attempts += 1
		var rw: int = rng.randi_range(7, 13)
		var rh: int = rng.randi_range(6, 11)
		var rx: int = rng.randi_range(2, w - rw - 3)
		var ry: int = rng.randi_range(2, h - rh - 3)
		var cand := Rect2i(rx, ry, rw, rh)
		var overlap := false
		for r in rooms:
			if (r as Rect2i).grow(2).intersects(cand):
				overlap = true
				break
		if overlap:
			continue
		rooms.append(cand)
		_carve_rect(tiles, w, h, cand, TILE_FLOOR)
	if rooms.is_empty():
		rooms.append(Rect2i(24, 24, 16, 14))
		_carve_rect(tiles, w, h, rooms[0], TILE_FLOOR)
	# Connect in placement order with L corridors (guaranteed connectivity).
	for i in range(1, rooms.size()):
		_connect(tiles, w, h, _center(rooms[i - 1]), _center(rooms[i]), rng)
	# Spawn = room 0 center; exit = farthest room center.
	var spawn := _center(rooms[0])
	var exit := spawn
	var best := -1.0
	for r in rooms:
		var c := _center(r)
		var d := Vector2(spawn - c).length()
		if d > best:
			best = d
			exit = c
	_put_tile(tiles, w, spawn, TILE_SPAWN)
	_put_tile(tiles, w, exit, TILE_EXIT)
	# Special rooms: loot + ambush (not spawn/exit).
	var order: Array = rooms.duplicate()
	order.shuffle()
	var specials := {"loot": 0, "ambush": 0}
	for r in order:
		var c := _center(r)
		if c == spawn or c == exit:
			continue
		if specials["loot"] < 1 + threat / 3:
			_put_tile(tiles, w, c + Vector2i(1, 0), TILE_LOOT)
			specials["loot"] += 1
		elif specials["ambush"] < 1 + threat / 2:
			_put_tile(tiles, w, c, TILE_AMBUSH)
			specials["ambush"] += 1
	return {"seed": dungeon_seed, "w": w, "h": h, "tiles": tiles,
		"rooms": rooms, "spawn": spawn, "exit": exit, "threat": threat,
		"zones": 1, "borders": [], "room_zones": []}

func generate_sector(threat: int, rooms_per_zone := 6, dungeon_seed := 0, zones := 3) -> Dictionary:
	## Elongated multi-zone sector: 40 cells of width per zone, wiggly
	## sine borders, rooms dealt round-robin per zone, connected in zone
	## order so the run flows west → east through every district.
	var rng := RandomNumberGenerator.new()
	if dungeon_seed == 0:
		rng.randomize()
		dungeon_seed = rng.randi()
	rng.seed = dungeon_seed
	var w := 40 * maxi(zones, 1)
	var h := 72
	var tiles := PackedByteArray()
	tiles.resize(w * h)
	tiles.fill(TILE_VOID)
	var borders: Array = []
	for b in maxi(zones - 1, 0):
		borders.append({"amp": rng.randf_range(3.0, 6.0), "freq": rng.randf_range(0.12, 0.28),
			"phase": rng.randf_range(0.0, TAU)})
	var rooms: Array = []
	var room_zones: Array = []
	for z in zones:
		var placed := 0
		var attempts := 0
		while placed < rooms_per_zone and attempts < 160:
			attempts += 1
			var rw: int = rng.randi_range(7, 13)
			var rh: int = rng.randi_range(6, 11)
			var rx: int = rng.randi_range(2, w - rw - 3)
			var ry: int = rng.randi_range(2, h - rh - 3)
			var cand := Rect2i(rx, ry, rw, rh)
			var cc := _center(cand)
			if _zone_of_x(w, borders, cc.x, cc.y) != z:
				continue
			var overlap := false
			for r in rooms:
				if (r as Rect2i).grow(2).intersects(cand):
					overlap = true
					break
			if overlap:
				continue
			rooms.append(cand)
			room_zones.append(z)
			_carve_rect(tiles, w, h, cand, TILE_FLOOR)
			placed += 1
	if rooms.is_empty():
		rooms.append(Rect2i(24, 24, 16, 14))
		room_zones.append(0)
		_carve_rect(tiles, w, h, rooms[0], TILE_FLOOR)
	# Chain in zone order (stable within zone): guarantees every district
	# is reachable and the critical path crosses each border once.
	var order: Array = []
	for z in zones:
		for i in rooms.size():
			if int(room_zones[i]) == z:
				order.append(i)
	for i in range(1, order.size()):
		_connect(tiles, w, h, _center(rooms[order[i - 1]]), _center(rooms[order[i]]), rng)
	# Spawn: westmost zone-0 room; exit: eastmost last-zone room.
	var spawn := _center(rooms[order[0]])
	var exit := spawn
	var spawn_x := 1 << 30
	var exit_x := -1
	for i in rooms.size():
		var c := _center(rooms[i])
		if int(room_zones[i]) == 0 and c.x < spawn_x:
			spawn_x = c.x
			spawn = c
		if int(room_zones[i]) == zones - 1 and c.x > exit_x:
			exit_x = c.x
			exit = c
	_put_tile(tiles, w, spawn, TILE_SPAWN)
	_put_tile(tiles, w, exit, TILE_EXIT)
	# Specials dealt round-robin per zone so every district pays loot.
	var per_zone: Array = []
	for z in zones:
		var lst: Array = []
		for i in rooms.size():
			var c := _center(rooms[i])
			if int(room_zones[i]) == z and c != spawn and c != exit:
				lst.append(rooms[i])
		lst.shuffle()
		per_zone.append(lst)
	var loot_each := 1 + threat / 4
	var ambush_each := 1 + threat / 3
	for z in zones:
		var li := 0
		for r in per_zone[z]:
			if li >= loot_each + ambush_each:
				break
			var c := _center(r)
			if li < loot_each:
				_put_tile(tiles, w, c + Vector2i(1, 0), TILE_LOOT)
			else:
				_put_tile(tiles, w, c, TILE_AMBUSH)
			li += 1
	return {"seed": dungeon_seed, "w": w, "h": h, "tiles": tiles,
		"rooms": rooms, "room_zones": room_zones, "spawn": spawn, "exit": exit,
		"threat": threat, "zones": zones, "borders": borders}

func _zone_of_x(w: int, borders: Array, x: int, y: int) -> int:
	var z := 0
	for b in borders.size():
		var bd: Dictionary = borders[b]
		var cut: float = float(w) * float(b + 1) / float(borders.size() + 1)
		cut += float(bd["amp"]) * sin(float(y) * float(bd["freq"]) + float(bd["phase"]))
		if x >= int(cut):
			z = b + 1
	return z

func _carve_rect(tiles: PackedByteArray, w: int, h: int, r: Rect2i, v: int) -> void:
	for y in range(r.position.y, r.position.y + r.size.y):
		for x in range(r.position.x, r.position.x + r.size.x):
			if x >= 0 and y >= 0 and x < w and y < h:
				tiles[y * w + x] = v

func _center(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)

func _put_tile(tiles: PackedByteArray, w: int, p: Vector2i, v: int) -> void:
	tiles[p.y * w + p.x] = v

func _connect(tiles: PackedByteArray, w: int, h: int, a: Vector2i, b: Vector2i, rng: RandomNumberGenerator) -> void:
	var p := a
	var horiz_first := rng.randf() < 0.5
	if horiz_first:
		while p.x != b.x:
			p.x += signi(b.x - p.x)
			_stamp(tiles, w, h, p)
		while p.y != b.y:
			p.y += signi(b.y - p.y)
			_stamp(tiles, w, h, p)
	else:
		while p.y != b.y:
			p.y += signi(b.y - p.y)
			_stamp(tiles, w, h, p)
		while p.x != b.x:
			p.x += signi(b.x - p.x)
			_stamp(tiles, w, h, p)

func _stamp(tiles: PackedByteArray, w: int, h: int, p: Vector2i) -> void:
	for dy in [-1, 0]:
		for dx in [-1, 0]:
			var q := p + Vector2i(dx, dy)
			if q.x >= 0 and q.y >= 0 and q.x < w and q.y < h:
				var idx := q.y * w + q.x
				if tiles[idx] == TILE_VOID:
					tiles[idx] = TILE_CORRIDOR

func is_walkable(d: Dictionary, x: int, y: int) -> bool:
	var w: int = d["w"]
	var h: int = d["h"]
	if x < 0 or y < 0 or x >= w or y >= h:
		return false
	return (d["tiles"] as PackedByteArray)[y * w + x] != TILE_VOID

func world_pos(d: Dictionary, cell: Vector2i, cell_size := 4.0) -> Vector3:
	return Vector3((float(cell.x) - float(d["w"]) / 2.0) * cell_size, 0.0,
		(float(cell.y) - float(d["h"]) / 2.0) * cell_size)

func random_floor_cell(d: Dictionary, rng: RandomNumberGenerator) -> Vector2i:
	var w: int = d["w"]
	var h: int = d["h"]
	var tiles: PackedByteArray = d["tiles"]
	for _i in 200:
		var x := rng.randi_range(0, w - 1)
		var y := rng.randi_range(0, h - 1)
		if tiles[y * w + x] != TILE_VOID:
			return Vector2i(x, y)
	return d["spawn"]
