# SYSTEMS — module contracts for WIRECRAWL

Each system owns one concern and talks to others only through the interfaces
below. Autoloads boot in the order listed in `project.godot`.

## 1. GameDB (autoload, data-only)
- Owns: ORIGINS, WEAPONS, AFFIXES, ARMOR_SETS, PROGRAMS, ENEMIES, SYNERGIES,
  CONTRACTS, CYBERWARE_TRACKS, RARITY tables.
- Pure static funcs: `xp_for_level`, `threat_hp_mult`, `threat_dmg_mult`,
  `loot_rarity_roll(rng, luck, threat)`, `weapon_dps`.
- Nobody writes to GameDB. Balance changes happen here (mirrored in Rust).

## 2. SaveSystem (autoload)
- `load_profile / save_profile` (atomic JSON), `add_xp(origin, n) -> [gained, lv]`,
  `add_credits/spend_credits`, `buy_cyberware(track)`, `cyberware_bonus()`.
- Emits nothing; callers re-read profile.

## 3. AudioDirector (autoload)
- `play(name, pitch)` — cached synthesized SFX. Generative music starts in `_ready`:
  64-step Am–F–C–G darksynth (soft bass, pad chords, kick/snare/hats, sparse
  plucks, loop riser).
- `set_volumes(master, music, sfx)`. `enabled=false` silences (used headless).

## 4. RunManager (autoload, run state)
- `start_run(origin, contract, primary, secondary, armor, programs)`; signals:
  `hp_changed, energy_changed, xp_changed, credits_changed, kill_confirmed,
  loot_dropped, objective_changed, run_ended, leveled_up`.
- `loadout` holds **primary + secondary** weapons (TAB/wheel swaps via
  `WCPlayer.swap_weapon`), armor pieces, programs.
- `take_damage` (armor mitigation), `heal`, `spend_energy`, `regen`,
  `gain_xp` (multi-level), `register_kill/register_loot`, `end_run(victory)`
  (settles XP/credits/unlocks into SaveSystem).

## 5. LootFactory (autoload)
- `roll_weapon(threat, luck, force_id, force_rarity)`, `roll_armor(threat, luck)`,
  `set_bonus_count(sets)`, `describe(item)`. Own RNG instance.

## 6. SynergyEngine (autoload)
- `empty_statuses, tick, has, dot_damage, apply_hit(statuses, dmg_type, tags, power)`.
- Combos are data (`GameDB.SYNERGIES`); `apply_hit` returns event dicts the
  caller resolves (burst damage, chains, freezes) — engine never touches nodes.

## 7. DungeonGen (autoload)
- `generate(threat, rooms, seed) -> {tiles, rooms, spawn, exit, ...}`,
  `is_walkable`, `world_pos`, `random_floor_cell`.
- Guarantee: all non-void tiles connected (corridors carved in placement order).

## 8. Dungeon (per-run Node3D, `scripts/dungeon/Dungeon.gd`)
- `setup(contract)` BEFORE entering tree → `_ready` builds environment, level,
  player, encounters, camera. Layout comes from the Rust core when the
  extension is loaded (`WCDungeonRust`, see §11), else `DungeonGen`.
  Post-layout, `_build_vault` seeds a far-room vault (elite guards + epic+
  loot) on either backend. Holo pillars double as hackable terminals
  (`try_hack`: credits/energy/bonus loot). Camera sits on +Z so W is screen-up.
- Owns FX API used by entities: `float_text, spawn_damage_number,
  spawn_blast_fx, spawn_flash_fx, spawn_impact_fx, spawn_slash_fx (crescent),
  spawn_beam_fx`; room tints + wall window strips dress sectors; program AoE: `deploy_turret, summon_hound, blackout_blast,
  system_shock`; flow: `on_enemy_died, offer_loot, summon_adds`.
- Signals: `room_cleared, boss_spawned, extraction_ready, loot_offered`.
  Kill-streak callouts (double/rampage/overdrive) with energy-free fanfare.

## 9. Entities (`scripts/entities/`)
- `WCPlayer`: input → move/aim/fire/dash/programs/hack; heat-gated trigger
  (primary 30-shot / heavy 8-shot mags, 1.2s overheat lock); reads RunManager
  for vitals, LootFactory item for damage; visible blade/gun models rebuilt
  on swap/equip; X-ray outline; writes via RunManager/SynergyEngine/Dungeon.
- `WCEnemy`: data-driven AI (`chaser/dasher/shooter/tank/boss`) with LoS-gated
  attacks, shooter strafing, dasher telegraphs, statuses, floating HP bars,
  synergy event resolution, `make_elite()` champions, procedural rig models
  (mohawks, blades, rotors, robes+orbiting shards, pauldrons, boss crowns),
  walk-bob/sway locomotion, drops via `dungeon.on_enemy_died`.
- `WCProjectile`: faction-based hit resolution (player mask hits world+foes,
  enemy mask hits world+player), pierce/splash/arc, wall impact FX.
- `WCPickup`: magnet + `player.collect(kind, amount, item)`; distinct models
  (coin, cross, diamond, cache + rarity beam).
- `WCPropCrate`: destructible cover with hazard-stripe affordance, loot pop.
- `WCAlly`: turret/hound deployables scaling with program power.

## 10. UI (`scripts/ui/HUD.gd`, `scripts/ui/WCTheme.gd`, `scripts/Main.gd`)
- `WCTheme`: single neon theme (buttons, sliders, panels, headers, sections,
  corner brackets via `WCBrackets`).
  Assigned to every root Control (title shell, HUD roots, pause, debrief).
- Title shell: nav rail (DEPLOY / CHROME / PROFILE / SETTINGS) + scrollable
  content; selections re-render the tab only (`_refresh_title`).
- HUD observes RunManager signals + polls dungeon (boss bar, cooldowns, minimap,
  dual-weapon readout, exit-distance + hostiles objective tracker). Loot choice
  panel (`[1]`/`[2]`/click, 14s timeout, UPGRADE verdict, queued offers) calls
  `WCPlayer.equip_item`. Feed lines expire after 7s.
- Main owns screen flow + runtime InputMap bootstrap + pause + debrief +
  run-start fade transition.

## 11. Rust core (`rust_ext/`, optional)
- Mirrors §§1,5–7 hot paths (`generate_dungeon`, `roll_rarity`, `xp_for_level`,
  connectivity). Exposed as `WCDungeonRust` GDExtension when compiled;
  `WCDungeon._generate_layout` uses it when `ClassDB` reports it, else the
  GDScript fallback. Verified: `cargo test` 3/3, cdylib links (zig-cc),
  loads on 4.7.2 (`Initialize godot-rust`), generates connected sectors
  through the engine (SimTest `rust_*`).
- Repo ships the `.gdextension.template` + sources only; build with
  `cargo build --release` and copy the template to use it.
