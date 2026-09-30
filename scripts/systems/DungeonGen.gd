extends Node
## DungeonGen — deterministic procedural sector layouts (seeded).
## Grid dungeon: rooms placed via random walk + BSP-ish splits, connected by
## L-corridors. Output: {seed, w, h, tiles (0 void,1 floor,2 corridor,3 spawn,
## 4 exit,5 loot,6 ambush), rooms[], spawn, exit, threat}.
## Same algorithm is mirrored in rust_ext/src/lib.rs (authoritative port).

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
		"rooms": rooms, "spawn": spawn, "exit": exit, "threat": threat}

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
