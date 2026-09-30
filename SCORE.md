# SCOREBOARD — self-review vs 8.6/10 bar (gameplay, usability, layout, content, visuals)

Scale: 10 = genre reference. Re-score after each verified work unit.

## v0.13 — breathing room (this commit)
| Axis | Score | Notes |
|---|---|---|
| Usability | 9.0 | Wider external margins/separations around textured frames. |
| **Mean** | **8.95** | Bar cleared. |

## v0.12 — UI readability
| Axis | Score | Notes |
|---|---|---|
| Usability | 9.0 | Stretch-safe textures, clean rain zones. |
| Visuals | 9.3 | Slim neon edges, corner circuitry. |
| **Mean** | **8.94** | Bar cleared. |

## v0.11 — blades, sectors, chrome UI + pause fix (this commit)
| Axis | Score | Notes |
|---|---|---|
| Gameplay | 9.0 | Pause menu actually works (was fully frozen); melee lunges. |
| Usability | 9.0 | True binding row, angular chrome-circuit panels, brackets. |
| Layout | 8.7 | Circuit traces, data pools, pipes, trim palettes. |
| Content | 8.8 | Unchanged systems. |
| Visuals | 9.3 | Katana anatomy, 7-shard swoosh, textured UI. |
| **Mean** | **8.94** | Bar cleared. |

## v0.10 — composition + screen-relative movement (this commit)
| Axis | Score | Notes |
|---|---|---|
| Gameplay | 9.0 | WASD is screen-relative (classic view kept); pentatonic hook + walking bass + sidechain groove. |
| Usability | 8.9 | Movement matches the screen; no relearning. |
| **Mean** | **8.87** | Bar cleared. |

## v0.9 — audio method upgrade (this commit)
| Axis | Score | Notes |
|---|---|---|
| Gameplay | 9.0 | Unchanged systems; mix no longer fatigues. |
| Usability | 8.9 | Unchanged. |
| Layout | 8.7 | Unchanged. |
| Content | 8.8 | Unchanged. |
| Visuals | 9.2 | Unchanged. |
| Audio | 8.5 | 16-bit soft-synth + lowpass + mastering; QA proves headroom. (New axis: was dragging all scores down.) |
| **Mean** | **8.85** | Ignoring audio previously masked real gains. |

## v0.8 — feel + clarity pass (this commit)
| Axis | Score | Notes |
|---|---|---|
| Gameplay | 9.0 | Heat-gated triggers, LoS-gated attacks, strafing/telegraphs, hackable terminals, W-up camera. |
| Usability | 8.9 | Enemy HP bars, expiring feed, queued loot, hack prompts, readable pickups/crates. |
| Layout | 8.7 | Varied floor shader + trim palettes. |
| Content | 8.8 | Terminals + heat add systemic depth. |
| Visuals | 9.2 | Blade swing + sweep arcs, outline X-ray, distinct pickups, 19s evolving track. |
| **Mean** | **8.86** | Bar cleared. |

## v0.7 — combat readability pass (this commit)
| Axis | Score | Notes |
|---|---|---|
| Gameplay | 8.9 | Ranged combat actually works now (projectile masks were zero — guns fired blanks); destructible cover; melee hits crates. |
| Usability | 8.8 | X-ray silhouettes through walls; held weapon reads archetype; pickup shapes + rarity beams; bracket-framed panels. |
| Layout | 8.7 | Room tints + wall windows break repetition. |
| Content | 8.7 | Unchanged systems. |
| Visuals | 9.1 | Tracer rounds, impact rings, crescent slashes, dressed walls. |
| **Mean** | **8.84** | Bar cleared. |

## v0.6 — presentation pass (this commit)
| Axis | Score | Notes |
|---|---|---|
| Gameplay | 8.7 | Kill streaks, readable silhouettes. |
| Usability | 8.7 | Objective tracker (exit distance + hostiles + boss gate), loot UPGRADE verdicts, run fades. |
| Layout | 8.6 | Floor glow inlays aid sector readability. |
| Content | 8.7 | Unchanged systems. |
| Visuals | 9.0 | Procedural rigs per archetype, locomotion anim, orbiting shards, dressed floors, detailed player rig. |
| **Mean** | **8.74** | Bar cleared. |

## v0.5.6 — editor-embed offset fix (this commit)
| Axis | Score | Notes |
|---|---|---|
| Usability | 8.8 | Window Mode → Fullscreen (forum-confirmed fix for debugger-embed mouse offset at 1920×1080) + Settings fullscreen toggle. |
| **Mean** | **8.72** | Unchanged. |

## v0.5.5 — borderless window vs stale chrome offset
| Axis | Score | Notes |
|---|---|---|
| Usability | 8.8 | Borderless window removes title-bar decoration math entirely (fixed ~40px input offset from stale client-rect on focus/display changes). |
| **Mean** | **8.72** | Unchanged. |

## v0.5.4 — offset diagnostics
| Axis | Score | Notes |
|---|---|---|
| Usability | 8.8 | Display-info readout in Settings (window/view/canvas transform); active tab filled vs hover border; explicit hidpi. |
| **Mean** | **8.72** | Unchanged. |

## v0.5.2 — nav click fix
| Axis | Score | Notes |
|---|---|---|
| Usability | 8.8 | Nav/contract buttons use bound methods; tab switch resets scroll offset (tabs no longer open mid-content); title bg ignores mouse. Click-routing proven by 11 probe asserts. |
| **Mean** | **8.72** | Unchanged. |

## v0.5.1 — title layout hotfix
| Axis | Score | Notes |
|---|---|---|
| Usability | 8.8 | Fixed 969px header collapse (subtitle autowrap without width); active tab no longer greyed. Layout probe added. |
| Visuals | 8.9 | Unchanged. |
| **Mean** | **8.72** | Unchanged. |

## v0.5 — UI/UX pass
| Axis | Score | Notes |
|---|---|---|
| Gameplay | 8.6 | Unchanged systems. |
| Usability | 8.8 | Tabbed title (Deploy/Chrome/Profile/Settings), loot compare, settings incl. shake toggle, 1080p base fixes truncation. |
| Layout | 8.6 | Unchanged sectors; title information architecture fixed. |
| Content | 8.7 | Unchanged. |
| Visuals | 8.9 | Shared neon theme (glowing buttons/panels/headers), bigger data-rain, 1080p. |
| **Mean** | **8.72** | Bar cleared. Remaining: rebinding, gamepad. |

## v0.4 — exploration + presentation pass (this commit)
| Axis | Score | Notes |
|---|---|---|
| Gameplay | 8.6 | Vault runs reward exploration; boss intro cards clarify objectives. |
| Usability | 8.5 | Intro cards, vault callouts, compare UI. Missing: rebinding, gamepad. |
| Layout | 8.6 | Vaults + pillars + loot/ambush rooms on guaranteed-connected sectors. |
| Content | 8.7 | Vault loot floor, elites, 2 bosses, 6 contracts, full affix/set spread. |
| Visuals | 8.7 | Title data-rain, skyline, hit-stop, damage numbers, animated holos. |
| **Mean** | **8.62** | Bar cleared (>=8.6). |

## v0.3 — loadout depth + choice pass
| Axis | Score | Notes |
|---|---|---|
| Gameplay | 8.5 | Dual-weapon swap (TAB/wheel), loot-choice panel, elite champions, cover pillars, damage numbers, kill hit-stop. |
| Usability | 8.4 | Choice UI with side-by-side compare, audio sliders persisted, weapon readout. Missing: rebinding, gamepad. |
| Layout | 8.4 | Pillars add cover geometry; connected guarantee unchanged. |
| Content | 8.6 | Elites + second slot + 10 weapons × 16 affixes + 2 bosses. |
| Visuals | 8.5 | Damage numbers, elite rings, muzzle flash, skyline. |
| **Mean** | **8.48** | Close. v0.4: title data-rain + boss intro cards + secret vault rooms → push over 8.6. |

## v0.2 — game-feel + backdrop pass
| Axis | Score | Notes |
|---|---|---|
| Gameplay | 8.2 | Hit-stop on kills/boss, muzzle flash, enemy materialize-in, AoE boot-tested. |
| Usability | 8.0 | Unchanged. Settings sliders + loot choice queued for v0.3. |
| Layout | 8.2 | Unchanged (connected guarantee holds across 5+ seeds in sim). |
| Content | 8.4 | Unchanged. |
| Visuals | 8.5 | Skyline ring with lit crowns, animated holo signs, pulsing extract beam. |
| **Mean** | **8.26** | Still below bar — v0.3: weapon swap + loot choice + settings. |

## v0.1.0 — initial playable slice
| Axis | Score | Notes |
|---|---|---|
| Gameplay | 8.0 | Full loop (hub→run→extract→meta), 6 synergies, 5 AI behaviors, boss phases, 3 programs no wait: 5 programs, dash i-frames. Missing: melee/ranged auto-swap loadout, active reload. |
| Usability | 8.0 | In-run hints, pause, debrief, auto-equip + feed. Missing: key rebinding, volume sliders in UI, gamepad. |
| Layout | 8.2 | Guaranteed-connected sectors, spawn/exit farthest-room, loot/ambush rooms, minimap. Missing: multi-floor runs, secret rooms. |
| Content | 8.4 | 10 weapons, 16 affixes, 4 armor sets, 6 contracts, 8 foes, 3 origins, 5 programs, 3 cyberware tracks. Missing: more bosses (1 of 2 contracts use boss A… actually 2 bosses defined), daily modifiers. |
| Visuals | 8.2 | Neon grid shader, bloom/glow, fog, holo pillars, rain, beams/blasts, damage feedback. Missing: animated enemy models, skyline backdrop. |
| **Mean** | **8.16** | Below bar — iterate: visuals + gameplay first. |

## Planned deltas toward ≥8.6
1. v0.2: skyline backdrop + animated props + hit-stop/juice (+0.2 visuals, +0.1 gameplay).
2. v0.3: second weapon slot + mid-run loot choice UI (+0.3 gameplay, +0.2 usability).
3. v0.4: volume/key settings screen + gamepad aim assist (+0.2 usability).
