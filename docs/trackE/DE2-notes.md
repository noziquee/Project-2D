# DE2: group attack slots

Written October 30, 2026 **without running Godot**. Decision DE2. 6 new checks, DE2-1 to DE2-6, new part `enemy_ai_slots`.

## What changed

- `EnemyBehaviorProfile`: `max_simultaneous_attackers` (0 = no limit, the default, so nothing changes for existing enemies) and `max_simultaneous_heavies` (0 = no extra limit).
- `EnemyAIController2D`: before an enemy starts its wind-up or heavy charge it asks for a slot on its target. If every slot is taken it cancels the wind-up and waits where it stands, asking again each frame. The slot is released when the swing or combo ends (`swing_ended`), when a charge is refused, when the target is lost or the enemy dies, when it switches target, when it leaves the tree, or after 0.5 s of doing nothing (so a refused swing cannot hold a slot for good).
- Holders are stored on the target node (meta `enemy_attack_slots`), so there is no global state to reset between tests. `holds_attack_slot()` and `last_slot_decision` give debug output ("took slot 1 of 1", "wait: 1 of 1 attack slots taken", heavy variants).
- Combo continuation is not gated: an enemy that holds a slot keeps it through its combo.
- The limit of the enemy asking is the one that counts, so give a group the same value. No profile file sets it yet; set it per group in the Inspector, or on a profile once you choose a number.

## Checks (part `enemy_ai_slots`)

| Check | Pins |
|---|---|
| DE2-1 | limit 1: never more than one goblin winding up or swinging at once |
| DE2-2 | limit 1: goblins still take turns (at least two swings in 10 s) |
| DE2-3 | the debug reason names the slot decision |
| DE2-4 | limit 0: goblins may attack together |
| DE2-5 | limit 0: nothing is tracked |
| DE2-6 | freed goblins leave no slot taken |

## Known limits

- A waiting enemy stands still in range; it does not yet step back or circle. Spacing for waiting enemies belongs with the repositioning work (Phase E gap).
- Skills and dash skills do not take slots.
- A heavy that waits for an opening holds its slot while it waits (the 0.5 s idle release frees it if it does nothing).
- Heavies take a slot as heavy only if the first chosen attack is chargeable; a heavy chosen later by the fallback keeps the slot kind it had.

## Next

Run the suite (expected total: last run + 4 for DE1 + 6 here), then telegraphs for skills and non-lane shapes (Phase F), and Phase C and E gaps.

## Addendum: circling while waiting (written October 30, 2026, not run)

- `EnemyBehaviorProfile.circle_while_waiting` (default false). With it on, an enemy that is in range but refused a slot walks sideways around its target (the side is picked once from the controller's seeded `rng`), pulled toward 90% of its attack range so it stays inside the distance it attacks from. It stops the moment it gets a slot. `EnemyAIController2D.is_waiting_for_slot()` reports the state.
- Checks DE2-7 to DE2-10 (part `enemy_ai_slots`): a waiting goblin moves at least 0.5 rad around the player, stays within 1.6 x its attack range, a goblin without the setting stays put, and circling never lets a second goblin attack. Expected total: DE2 now adds 10 checks, not 6.
- Still open: it does not avoid other enemies or walls while circling, and it only circles while waiting for a slot, not for cooldowns. The ranged profiles' repositioning (preferred and maximum range) is separate and not started.
