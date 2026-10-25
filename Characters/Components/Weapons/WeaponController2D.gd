extends Node
class_name WeaponController2D
## Owns the question "can this character equip this weapon?" (guide section 10.5).
##
## validate_equip() and can_equip() report every reason a weapon would be refused and change nothing
## (9.7c-1). equip() gives the character the weapon's attacks (9.7c-2) and, when the weapon has a
## weapon_scene that is not the one mounted, swaps that scene in under WeaponFacingPivot first (9.7c-3).
## A weapon with no scene, or the scene already mounted, keeps the weapon that is there.
##
## equip() only touches the mounted weapon and the AttackComponent2D's attacks (the default attack and the
## `attacks` list). It never starts, cancels or resets anything, because equipping is refused during a
## swing or charge, and the cooldown keeps running (switching weapons is not a free cooldown reset).
##
## Like the other components, it must not read `context` in _ready(); Character2D (or a test) hands it
## the shared context through initialize().

## The weapon was equipped: the attack component now has its attacks.
signal weapon_equipped(weapon: WeaponDefinition2D)
## equip() refused or failed; `problems` are readable messages. The previous weapon is kept.
signal equip_failed(weapon: WeaponDefinition2D, problems: Array)

## The weapon equipped when the controller is initialized (9.7c-4). Empty keeps whatever the character
## scene has: the mounted weapon and the attacks set on its AttackComponent2D.
@export var starting_weapon: WeaponDefinition2D
## The weapons equip_next() cycles through, in order (11.4). Empty or a single entry means there is nothing to switch to.
## Put starting_weapon in the list too, so the cycle continues from it.
@export var loadout: Array[WeaponDefinition2D] = []

var context: CharacterContext2D
var attack_component: AttackComponent2D
## Optional (13.2): given by Character2D when the character has a SkillComponent2D. Equipping a weapon sets its skills there.
var skill_component: SkillComponent2D
var _initialized := false
## The weapon given to the last successful equip() (null until then).
var _equipped_weapon: WeaponDefinition2D

func initialize(shared_context: CharacterContext2D, attacks: AttackComponent2D) -> void:
	context = shared_context
	attack_component = attacks
	_initialized = (
		context != null
		and context.character != null
		and is_instance_valid(attack_component)
		and is_instance_valid(context.weapon_animation_player)
	)
	if not _initialized:
		push_warning("WeaponController2D needs a character context, an attack component and a weapon AnimationPlayer. Equipping is disabled.")
		return
	if starting_weapon != null:
		equip(starting_weapon)

func is_initialized() -> bool:
	return _initialized

func get_equipped_weapon() -> WeaponDefinition2D:
	return _equipped_weapon

## Equips `weapon`: its first combo attack becomes the character's default attack and the rest of its
## combo and its heavy attack become the `attacks` list. A weapon whose weapon_scene is not the one
## mounted now is swapped in first (9.7c-3). Returns false, emits equip_failed and keeps the previous
## weapon (mount and attacks) when validate_equip() finds a problem or the attack component rejects an
## attack.
func equip(weapon: WeaponDefinition2D) -> bool:
	var problems := validate_equip(weapon)
	if problems.is_empty():
		problems = _mount_problems(weapon)
	if not problems.is_empty():
		_fail(weapon, problems)
		return false
	var old_mount: Node2D = null
	if _needs_swap(weapon):
		var new_mount := weapon.instantiate_weapon()
		if new_mount == null:
			_fail_with(weapon, "%s: its weapon_scene could not be instantiated." % _label(weapon))
			return false
		old_mount = _swap_mount(new_mount)
		if old_mount == null:
			new_mount.free()
			_fail_with(weapon, "%s: the new weapon could not be bound to the character; the previous weapon is kept." % _label(weapon))
			return false
	var snapshot := _snapshot_attacks()
	if not _set_attacks_from(weapon):
		# Put the old weapon back first: the old attacks are validated against the weapon player.
		if old_mount != null:
			_restore_mount(old_mount)
		_restore_attacks(snapshot)
		_fail_with(weapon, "%s: the attack component rejected the weapon's attacks; the previous weapon is kept." % _label(weapon))
		return false
	if old_mount != null:
		old_mount.free()
	_equipped_weapon = weapon
	if is_instance_valid(skill_component):
		skill_component.set_skills(weapon.active_skills)
	weapon_equipped.emit(weapon)
	return true

## Equips the next weapon of `loadout` after the one equipped now (11.4), wrapping around. Returns false and
## changes nothing when there is nothing to switch to or the character is in a swing or charge. A weapon that
## cannot be equipped is skipped (its problems are logged by equip(), the old weapon stays mounted), and the
## next one is tried; false when none could be equipped.
func equip_next() -> bool:
	if not _initialized or loadout.is_empty() or context.is_attacking:
		return false
	var start := loadout.find(_equipped_weapon)
	for step in range(1, loadout.size() + 1):
		var candidate: WeaponDefinition2D = loadout[(start + step) % loadout.size()]
		if candidate == null or candidate == _equipped_weapon:
			continue
		if equip(candidate):
			return true
	return false

## True when validate_equip() finds nothing wrong.
func can_equip(weapon: WeaponDefinition2D) -> bool:
	return validate_equip(weapon).is_empty()

## Every reason `weapon` would be refused right now, as readable messages that name the weapon (and the
## attack or clip involved). Empty when it can be equipped. Changes nothing.
##
## Checked:
##   - the controller is initialized and the character has a WeaponFacingPivot (the player rig);
##   - the character is not in a swing or a charge;
##   - the weapon's own data (WeaponDefinition2D.validate());
##   - the clips: against the weapon's scene when it has one, otherwise against the weapon player
##     the character has now;
##   - per attack, what AttackComponent2D would reject: no effect scene (10.1), an effect scene that cannot
##     be instantiated or lacks the attack's effect clip, and a THRESHOLD release with no charge_threshold.
func validate_equip(weapon: WeaponDefinition2D) -> Array[String]:
	var problems: Array[String] = []
	if weapon == null:
		problems.append("WeaponController2D: no weapon given.")
		return problems
	var label := _label(weapon)
	if not _initialized:
		problems.append("%s: the weapon controller is not initialized (needs a character context, an attack component and a weapon AnimationPlayer)." % label)
		return problems
	if not is_instance_valid(context.weapon_facing_root):
		_add(problems, "%s: this character has no WeaponFacingPivot, so its weapon cannot be swapped (only the layered player rig supports equipping)." % label)
	if context.is_attacking:
		_add(problems, "%s: cannot be equipped during a swing or charge." % label)
	if context.is_casting:
		_add(problems, "%s: cannot be equipped during a skill cast." % label)

	for message in weapon.validate():
		_add(problems, message)
	if weapon.weapon_scene != null:
		for message in weapon.validate_scene():
			_add(problems, message)
	else:
		for message in weapon.validate(context.weapon_animation_player):
			_add(problems, message)

	for attack in weapon.get_all_attacks():
		if attack.effect_scene == null:
			_add(problems, "%s: attack '%s' has no effect_scene (every attack needs its own effect scene)." % [label, attack.id])
		if attack.effect_scene != null and not attack.effect_scene.can_instantiate():
			_add(problems, "%s: attack '%s' has an effect_scene that cannot be instantiated." % [label, attack.id])
		if attack.effect_scene != null and AttackSlash2D.scene_lacks_animation(attack.effect_scene, attack.effect_animation):
			_add(problems, "%s: attack '%s' needs clip '%s' (effect_animation) in its effect_scene." % [label, attack.id, attack.effect_animation])
		if attack.release_mode == AttackDefinition2D.ReleaseMode.THRESHOLD and attack.charge_threshold <= 0.0:
			_add(problems, "%s: attack '%s' uses a THRESHOLD release, which needs charge_threshold > 0." % [label, attack.id])
	return problems

## The mounted weapon must sit directly under the WeaponFacingPivot to be swapped out.
func _mount_problems(weapon: WeaponDefinition2D) -> Array[String]:
	var problems: Array[String] = []
	if _needs_swap(weapon) and (context.weapon_pivot == null or context.weapon_pivot.get_parent() != context.weapon_facing_root):
		problems.append("%s: the mounted weapon is not a direct child of WeaponFacingPivot, so it cannot be swapped out." % _label(weapon))
	return problems

## True when the weapon has a scene that is not the one mounted now. A weapon with no scene, or the
## mounted scene, keeps the weapon that is there.
func _needs_swap(weapon: WeaponDefinition2D) -> bool:
	if weapon.weapon_scene == null:
		return false
	var mounted_path := context.weapon_pivot.scene_file_path if context.weapon_pivot != null else ""
	return weapon.weapon_scene.resource_path == "" or weapon.weapon_scene.resource_path != mounted_path

## Replaces the mounted weapon with `new_mount`, which takes the old one's name and place under
## WeaponFacingPivot (so paths such as WeaponFacingPivot/MainHand stay valid). The context is bound to the
## new weapon and the attack component listens to its player. Returns the old mount, taken out of the
## tree but not freed (the caller frees it, or hands it to _restore_mount()). Returns null, with nothing
## changed, when the new weapon cannot be bound.
func _swap_mount(new_mount: Node2D) -> Node2D:
	var old_mount := context.weapon_pivot
	var parent := context.weapon_facing_root
	var index := old_mount.get_index()
	parent.remove_child(old_mount)
	new_mount.name = old_mount.name
	parent.add_child(new_mount)
	parent.move_child(new_mount, index)
	if not context.bind_weapon(new_mount):
		parent.remove_child(new_mount)
		parent.add_child(old_mount)
		parent.move_child(old_mount, index)
		return null
	attack_component.rebind_weapon_player()
	return old_mount

## Undoes _swap_mount(): frees the weapon that was mounted, puts `old_mount` back in its place and binds
## the context and the attack component to it again.
func _restore_mount(old_mount: Node2D) -> void:
	var parent := context.weapon_facing_root
	var failed_mount := context.weapon_pivot
	var index := failed_mount.get_index()
	parent.remove_child(failed_mount)
	failed_mount.free()
	parent.add_child(old_mount)
	parent.move_child(old_mount, index)
	context.bind_weapon(old_mount)
	attack_component.rebind_weapon_player()

## The default attack and the `attacks` list as they are now.
func _snapshot_attacks() -> Dictionary:
	var old_attacks: Array[AttackDefinition2D] = []
	for old_attack in attack_component.attacks:
		old_attacks.append(old_attack)
	return {"definition": attack_component.definition, "attacks": old_attacks}

## Gives the attack component the weapon's attacks: the default attack first (so the extras are
## registered against it), then the extras. False when either is rejected; nothing is undone here.
func _set_attacks_from(weapon: WeaponDefinition2D) -> bool:
	var extras := weapon.get_extra_attacks()
	if attack_component.set_attack_definition(weapon.get_default_attack()):
		return attack_component.set_attacks(extras) == extras.size()
	return false

func _restore_attacks(snapshot: Dictionary) -> void:
	attack_component.set_attack_definition(snapshot["definition"])
	attack_component.set_attacks(snapshot["attacks"])

## Applies the weapon's attacks and puts the old ones back if they are rejected (the mounted weapon is
## not touched). equip() uses the pieces separately, because a swapped mount must be restored first.
func _apply_attacks(weapon: WeaponDefinition2D) -> bool:
	var snapshot := _snapshot_attacks()
	if _set_attacks_from(weapon):
		return true
	_restore_attacks(snapshot)
	return false

func _fail_with(weapon: WeaponDefinition2D, message: String) -> void:
	var problems: Array[String] = [message]
	_fail(weapon, problems)

func _fail(weapon: WeaponDefinition2D, problems: Array[String]) -> void:
	for message in problems:
		push_warning("WeaponController2D: %s" % message)
	equip_failed.emit(weapon, problems)

func _add(problems: Array[String], message: String) -> void:
	if not problems.has(message):
		problems.append(message)

func _label(weapon: WeaponDefinition2D) -> String:
	if weapon.weapon_id != &"":
		return "weapon '%s'" % weapon.weapon_id
	if weapon.display_name != "":
		return "weapon '%s'" % weapon.display_name
	return "weapon (unnamed)"
