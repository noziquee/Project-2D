# Track W8 Smoke-Test Follow-up — Shared Sword Recovery Clips

## Finding

The smoke-test log showed that the shared `Sword_Slash1.tres` and `Sword_Slash2.tres` resources were temporarily configured to use `sword_slash_return_1` and `sword_slash_return_2`. The player Sword scene has those clips, but `GoblinSword.tscn` did not. Because the goblin deliberately reuses the same attack resources, its weapon controller rejected the default slash and follow-up attack. That rejection cascaded into many unrelated-looking AI, timing, damage, and attack-choice failures; a later null `movement_multiplier` error was a consequence of trying to start without a valid default attack.

## Changes

- Added `sword_slash_return_1` and `sword_slash_return_2` clips to `Weapons/GoblinSword/GoblinSword.tscn`. They use the goblin knife's own return pose (rotation and scale blend back to idle), so shared attack resources can validate and play when configured for clip-driven recovery.
- Extended the `GW1` smoke check to require both shared recovery clips.
- Left attack data, combat rules, and the tests' expected behavior unchanged.

## Verification

Static inspection confirms that both animation names are present in the GoblinSword AnimationLibrary and the smoke check expects them. Godot was not available in the editing environment, so the smoke suite has not been rerun here. Run the full smoke suite in Godot and inspect the new `SUMMARY` before considering this fix verified.
