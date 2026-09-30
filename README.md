# WIRECRAWL: NEON ABYSS

A cyberpunk isometric action dungeon-crawler, mechanically based on **Minecraft Dungeons**
(isometric ARPG, procedurally generated runs, rarity-tiered loot, difficulty/threat scaling)
with a deep-cyberpunk theme: neon sprawl sectors, chrome rigs, daemon programs, Black-Wall bosses.

**Engine:** Godot 4.7 (GL Compatibility) · **Scripting:** GDScript systems + optional **Rust GDExtension** core.

## Play

1. Open in Godot: `project.godot` → run `scenes/Main.tscn` (or press F5).
2. Pick a **rig** (Street Solo / Netrunner / Techie), a **contract** (threat 1–6),
   two **programs** (Q/E), install **cyberware** with banked credits.
3. `JACK IN` → clear the sector, grab loot, reach the green **EXTRACT** beam.
   Boss contracts must kill the boss first.
4. Spend credits on permanent cyberware; push to threat 6 / CHROME DRAGON.

**Controls:** WASD move · mouse aim · LMB fire · SPACE dash (i-frames) ·
TAB/wheel weapon swap · Q/E programs · 1/2 loot choice · ESC pause.

## Systems (all modular, see SYSTEMS.md)

| System | File | Role |
|---|---|---|
| Static data + balance formulas | `scripts/systems/GameDB.gd` | single source of truth |
| Run state / settlement | `scripts/systems/RunManager.gd` | HP/energy/XP/loot/threat |
| Procedural loot | `scripts/systems/LootFactory.gd` | rarity rolls, affixes, sets |
| Status synergies | `scripts/systems/SynergyEngine.gd` | 6 data-driven combos |
| Dungeon generation | `scripts/systems/DungeonGen.gd` | seeded rooms + corridors |
| Persistence | `scripts/systems/SaveSystem.gd` | versioned JSON profile |
| Procedural audio | `scripts/systems/AudioDirector.gd` | synth SFX + generative darksynth |
| Sector builder | `scripts/dungeon/Dungeon.gd` | neon city, encounters, FX, AoE |
| Player / enemies / allies | `scripts/entities/*.gd` | rigs, 5 AI behaviors, boss phases |
| HUD / shell | `scripts/ui/HUD.gd`, `scripts/Main.gd` | menus, shop, minimap, debrief |
| Rust core (optional) | `rust_ext/` | dungeon/loot/synergy acceleration |

No external assets: all visuals (neon grid shader, holo pillars, rain, glow)
and all audio are generated in code.

## Verify

```sh
python3 tests/test_balance.py                    # balance math mirror
godot --headless --path . --import               # project import, must be script-error free
godot --headless --path . res://tests/SimTest.tscn  # systems sim + dungeon boot test
godot --headless --path . res://tests/LayoutProbe.tscn  # title layout rect dump (see tests/LayoutProbe.gd)
cd rust_ext && cargo test                        # rust core (needs cargo + C linker)
```
The compiled Rust core is optional: copy
`rust_ext/wirecrawl.gdextension.template` → `rust_ext/wirecrawl.gdextension`
after `cargo build --release`, placing the lib in `rust_ext/bin/`.

## Progression & synergies (short)

- **Damage/statuses:** Kinetic · Thermal(Burn) · Volt(Shock) · Cryo(Chill) ·
  Toxic(Corrode) · Void(Mark). Combos: **Superconduct** (volt+chill),
  **Plasma Burn** (fire+toxic), **Shatter** (kinetic vs chill, executes),
  **Meltdown** (void vs marked), **Feedback Loop**, **Black Ice** (freeze).
- **Loot:** 10 weapon archetypes × 5 rarities × 18 affixes; armor in 4 sets
  with real 2pc/3pc bonuses (drops from foes, chests, vaults, bosses);
  3 companion drone chassis; power scales with threat; mythic odds rise
  at threat 5–6.
- **Meta:** origin levels, 3 cyberware tracks × 5 tiers, 6 contracts, credits.
