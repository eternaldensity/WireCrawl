//! WIRECRAWL Rust core — mirrors `scripts/systems/` in GDScript.
//!
//! The GDScript implementations are authoritative and always ship; this crate
//! accelerates the hot paths (dungeon carving, bulk loot rolls, synergy
//! evaluation) when compiled as a GDExtension. Build with:
//!
//! ```sh
//! cd rust_ext && cargo build --release
//! cp target/release/libwirecrawl_rust.so ../rust_ext/bin/libwirecrawl_rust.linux.so
//! ```
//!
//! Determinism contract: `generate_dungeon(seed, threat, rooms)` guarantees the
//! same STRUCTURAL invariants as `DungeonGen.generate()` in GDScript
//! (room count, tile alphabet, full connectivity, farthest-room exit) for the
//! same inputs. Exact tile streams differ (ChaCha8 vs Godot's PRNG), so the
//! GDScript path remains the reference implementation and the saves do not
//! depend on which backend generated a sector.

use godot::prelude::*;
use rand::{Rng, SeedableRng};
use rand_chacha::ChaCha8Rng;

// ---------------------------------------------------------------------------
// Pure logic (unit-testable without Godot)
// ---------------------------------------------------------------------------

pub const TILE_VOID: u8 = 0;
pub const TILE_FLOOR: u8 = 1;
pub const TILE_CORRIDOR: u8 = 2;
pub const TILE_SPAWN: u8 = 3;
pub const TILE_EXIT: u8 = 4;
pub const TILE_LOOT: u8 = 5;
pub const TILE_AMBUSH: u8 = 6;

/// Rarity weights — must match `GameDB.loot_rarity_roll`.
pub fn rarity_weights(luck: f32, threat: i32) -> [(&'static str, f32); 5] {
    let lb = luck.clamp(0.0, 3.0);
    let legendary = 5.5 + lb * 2.0 + threat as f32 * 0.5;
    let mythic = 1.5 + lb * 0.8 + (threat - 3).max(0) as f32 * 0.7;
    let epic = 13.0 + threat as f32 * 0.6;
    let common = (52.0 - threat as f32 * 3.0 - lb * 4.0).max(8.0);
    [
        ("common", common),
        ("rare", 28.0),
        ("epic", epic),
        ("legendary", legendary),
        ("mythic", mythic),
    ]
}

pub fn roll_rarity(rng: &mut impl Rng, luck: f32, threat: i32) -> &'static str {
    let w = rarity_weights(luck, threat);
    let total: f32 = w.iter().map(|(_, x)| x).sum();
    let mut r = rng.gen_range(0.0..total);
    for (name, weight) in w {
        r -= weight;
        if r <= 0.0 {
            return name;
        }
    }
    "common"
}

pub fn xp_for_level(level: i32) -> i32 {
    (80.0 * (level as f32).powf(1.55) + 40.0 * level as f32) as i32
}

pub fn threat_hp_mult(threat: i32) -> f32 {
    1.0 + 0.45 * (threat - 1) as f32
}

pub fn threat_dmg_mult(threat: i32) -> f32 {
    1.0 + 0.22 * (threat - 1) as f32
}

#[derive(Debug, Clone)]
pub struct Dungeon {
    pub seed: u64,
    pub w: usize,
    pub h: usize,
    pub tiles: Vec<u8>,
    pub rooms: Vec<(usize, usize, usize, usize)>,
    pub spawn: (usize, usize),
    pub exit: (usize, usize),
}

/// Seeded room + L-corridor generator. Mirrors DungeonGen.gd exactly:
/// rooms rejected on grow(2) overlap, connected in placement order.
pub fn generate_dungeon(seed: u64, threat: i32, room_target: usize) -> Dungeon {
    let mut rng = ChaCha8Rng::seed_from_u64(seed);
    let (w, h) = (64usize, 64usize);
    let mut tiles = vec![TILE_VOID; w * h];
    let want = room_target + ((threat / 2).min(3)) as usize;
    let mut rooms: Vec<(usize, usize, usize, usize)> = Vec::new();
    let mut attempts = 0;
    while rooms.len() < want && attempts < 220 {
        attempts += 1;
        let rw = rng.gen_range(7..=13);
        let rh = rng.gen_range(6..=11);
        let rx = rng.gen_range(2..=(w - rw - 3));
        let ry = rng.gen_range(2..=(h - rh - 3));
        let overlaps = rooms.iter().any(|&(ex, ey, ew, eh)| {
            rx < ex + ew + 2 && ex < rx + rw + 2 && ry < ey + eh + 2 && ey < ry + rh + 2
        });
        if overlaps {
            continue;
        }
        for y in ry..ry + rh {
            for x in rx..rx + rw {
                tiles[y * w + x] = TILE_FLOOR;
            }
        }
        rooms.push((rx, ry, rw, rh));
    }
    if rooms.is_empty() {
        for y in 24..38 {
            for x in 24..40 {
                tiles[y * w + x] = TILE_FLOOR;
            }
        }
        rooms.push((24, 24, 16, 14));
    }
    let center = |r: (usize, usize, usize, usize)| (r.0 + r.2 / 2, r.1 + r.3 / 2);
    let mut stamp = |x: usize, y: usize| {
        for dy in [0, 1] {
            for dx in [0, 1] {
                let (qx, qy) = (x.saturating_sub(dx), y.saturating_sub(dy));
                let idx = qy * w + qx;
                if tiles[idx] == TILE_VOID {
                    tiles[idx] = TILE_CORRIDOR;
                }
            }
        }
    };
    for i in 1..rooms.len() {
        let (ax, ay) = center(rooms[i - 1]);
        let (bx, by) = center(rooms[i]);
        let (mut px, mut py) = (ax, ay);
        if rng.gen_bool(0.5) {
            while px != bx {
                px = if bx > px { px + 1 } else { px - 1 };
                stamp(px, py);
            }
            while py != by {
                py = if by > py { py + 1 } else { py - 1 };
                stamp(px, py);
            }
        } else {
            while py != by {
                py = if by > py { py + 1 } else { py - 1 };
                stamp(px, py);
            }
            while px != bx {
                px = if bx > px { px + 1 } else { px - 1 };
                stamp(px, py);
            }
        }
    }
    let spawn = center(rooms[0]);
    let mut exit = spawn;
    let mut best = -1.0f32;
    for r in &rooms {
        let c = center(*r);
        let d = (((c.0 as i32 - spawn.0 as i32).pow(2) + (c.1 as i32 - spawn.1 as i32).pow(2)) as f32).sqrt();
        if d > best {
            best = d;
            exit = c;
        }
    }
    tiles[spawn.1 * w + spawn.0] = TILE_SPAWN;
    tiles[exit.1 * w + exit.0] = TILE_EXIT;
    Dungeon { seed, w, h, tiles, rooms, spawn, exit }
}

/// Connectivity check: every floor tile reachable from spawn?
pub fn is_fully_connected(d: &Dungeon) -> bool {
    let mut seen = vec![false; d.w * d.h];
    let mut stack = vec![d.spawn];
    seen[d.spawn.1 * d.w + d.spawn.0] = true;
    let mut floor_total = 0;
    for &t in &d.tiles {
        if t != TILE_VOID {
            floor_total += 1;
        }
    }
    let mut reached = 0;
    while let Some((x, y)) = stack.pop() {
        reached += 1;
        for (dx, dy) in [(1i32, 0), (-1, 0), (0, 1), (0, -1)] {
            let (nx, ny) = (x as i32 + dx, y as i32 + dy);
            if nx < 0 || ny < 0 || nx >= d.w as i32 || ny >= d.h as i32 {
                continue;
            }
            let idx = ny as usize * d.w + nx as usize;
            if !seen[idx] && d.tiles[idx] != TILE_VOID {
                seen[idx] = true;
                stack.push((nx as usize, ny as usize));
            }
        }
    }
    reached == floor_total
}

// ---------------------------------------------------------------------------
// GDExtension bindings
// ---------------------------------------------------------------------------

struct WirecrawlCore;

#[gdextension]
unsafe impl ExtensionLibrary for WirecrawlCore {}

#[derive(GodotClass)]
#[class(base=Node)]
struct WCDungeonRust {
    base: Base<Node>,
}

#[godot_api]
impl INode for WCDungeonRust {
    fn init(base: Base<Node>) -> Self {
        Self { base }
    }
}

#[godot_api]
impl WCDungeonRust {
    /// Fast seeded layout; returns a Dictionary compatible with DungeonGen output.
    #[func]
    fn generate(&self, seed: i64, threat: i64, rooms: i64) -> Dictionary {
        let d = generate_dungeon(seed as u64, threat as i32, rooms as usize);
        let mut tiles = PackedByteArray::new();
        tiles.resize(d.tiles.len());
        for (i, t) in d.tiles.iter().enumerate() {
            tiles[i] = *t;
        }
        let mut room_arr = Array::new();
        for (x, y, w, h) in &d.rooms {
            room_arr.push(Rect2i::new(
                Vector2i::new(*x as i32, *y as i32),
                Vector2i::new(*w as i32, *h as i32),
            ));
        }
        dict! {
            "seed": d.seed as i64,
            "w": d.w as i64, "h": d.h as i64,
            "tiles": tiles,
            "rooms": room_arr,
            "spawn": Vector2i::new(d.spawn.0 as i32, d.spawn.1 as i32),
            "exit": Vector2i::new(d.exit.0 as i32, d.exit.1 as i32),
            "threat": threat,
            "rust": true,
        }
    }

    #[func]
    fn roll_rarity(&self, seed: i64, luck: f32, threat: i64) -> GString {
        let mut rng = ChaCha8Rng::seed_from_u64(seed as u64);
        roll_rarity(&mut rng, luck, threat as i32).into()
    }

    #[func]
    fn xp_for_level(&self, level: i64) -> i64 {
        xp_for_level(level as i32) as i64
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn dungeons_are_connected() {
        for seed in 1..=25 {
            let d = generate_dungeon(seed, 3, 9);
            assert!(is_fully_connected(&d), "seed {seed} disconnected");
        }
    }

    #[test]
    fn xp_curve_is_monotonic() {
        let mut prev = 0;
        for lv in 1..=20 {
            let x = xp_for_level(lv);
            assert!(x > prev);
            prev = x;
        }
    }

    #[test]
    fn mythic_odds_rise_with_threat() {
        let count = |threat: i32| {
            let mut rng = ChaCha8Rng::seed_from_u64(7);
            (0..4000)
                .filter(|_| roll_rarity(&mut rng, 1.0, threat) == "mythic")
                .count()
        };
        assert!(count(6) > count(1));
    }
}
