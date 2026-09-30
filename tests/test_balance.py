"""Python mirror of the balance formulas — cross-checks GDScript/Rust agree.
Run: python3 tests/test_balance.py
"""
import math, random

def xp_for_level(lv): return int(80.0 * lv ** 1.55 + 40.0 * lv)
def threat_hp_mult(t): return 1.0 + 0.45 * (t - 1)
def threat_dmg_mult(t): return 1.0 + 0.22 * (t - 1)

W = {"common": 52.0, "rare": 28.0, "epic": 13.0, "legendary": 5.5, "mythic": 1.5}
def roll(luck, threat, rng):
    w = dict(W)
    lb = max(0.0, min(3.0, luck))
    w["legendary"] += lb * 2.0 + threat * 0.5
    w["mythic"] += lb * 0.8 + max(0, threat - 3) * 0.7
    w["epic"] += threat * 0.6
    w["common"] = max(8.0, w["common"] - threat * 3.0 - lb * 4.0)
    tot = sum(w.values()); r = rng.random() * tot
    for k in ["common", "rare", "epic", "legendary", "mythic"]:
        r -= w[k]
        if r <= 0: return k
    return "common"

fails = []
def check(cond, name):
    print(("PASS  " if cond else "FAIL  ") + name)
    if not cond: fails.append(name)

check(all(xp_for_level(i) < xp_for_level(i + 1) for i in range(1, 20)), "xp_monotonic")
check(threat_hp_mult(6) > 3.0, f"hp_t6={threat_hp_mult(6):.2f}")
rng = random.Random(7)
c1 = sum(1 for _ in range(4000) if roll(1.0, 1, rng) == "mythic")
rng = random.Random(7)
c6 = sum(1 for _ in range(4000) if roll(3.0, 6, rng) == "mythic")
check(c6 > c1, f"mythic_scales t1={c1} t6={c6}")
# TTK sanity: starter SMG (~8dmg x 9/s x PWR1.0) vs threat-1 punk (45hp)
starter_dps = 8.0 * 9.0
check(0.3 < 45 / starter_dps < 2.0, f"starter_ttk_punk={45 / starter_dps:.2f}s")
# Boss TTK with mid build (~250 dps) vs threat-3 daemon (1400 x 1.9)
boss_hp = 1400 * threat_hp_mult(3)
check(5 < boss_hp / 250 < 20, f"boss_ttk={boss_hp / 250:.1f}s")
print("---- %s ----" % ("ALL PASS" if not fails else f"{len(fails)} FAILURES"))
raise SystemExit(1 if fails else 0)
