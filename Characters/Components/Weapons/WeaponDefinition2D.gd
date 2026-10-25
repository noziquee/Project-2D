extends Resource
class_name WeaponDefinition2D
## One weapon: which attacks it gives its wielder and the scene that holds its sprite and the
## AnimationPlayer with the clips those attacks name.
##
## 9.7a defined and validated the data; 9.7b added the weapon scene (Weapons/Sword.tscn is the sword's).
## Nothing equips a weapon yet: the player scene mounts the sword scene directly. Equipping arrives in
## 9.7c (WeaponController2D).
##
## Data only. Runtime state (combo index, charge time, cooldowns) never lives here: this resource
## is shared by every character that wields the weapon.

## Identifier for logs, tests and (later) equip-by-id.
@export var weapon_id: StringName = &""
@export var display_name: String = ""
## The weapon's own scene: a Node2D root (it becomes WeaponFacingPivot's child on the player) with the
## sprite and an AnimationPlayer holding this weapon's clips and attack_event keys. Empty means the clips
## live on the character's own rig (the goblin's weapon still works that way).
@export var weapon_scene: PackedScene

@export_group("Attacks")
## The light combo, in order. The first entry is the weapon's default attack. Later entries are
## reached through next_attack / combo_sequence links on the attacks themselves (see
## AttackDefinition2D); listing them here registers them so those links resolve.
@export var basic_combo: Array[AttackDefinition2D] = []
## The charged or heavy attack. Optional.
@export var heavy_attack: AttackDefinition2D

@export_group("Skills")
## The weapon's active skills (13.1), at most MAX_SKILL_SLOTS, each in its own slot (SkillDefinition2D.slot).
## Optional. Equipping the weapon gives them to the character's SkillComponent2D, if it has one.
@export var active_skills: Array[SkillDefinition2D] = []

# Added in a later phase (guide section 10.5):
# @export var passive_skills: Array[PassiveDefinition2D]

## How many active skill slots a weapon has (decided in 13.0).
const MAX_SKILL_SLOTS := 3

## The attack a character starts with when this weapon is equipped: the first non-empty entry of
## basic_combo. Null when the combo has none.
func get_default_attack() -> AttackDefinition2D:
	for entry in basic_combo:
		if entry != null:
			return entry
	return null

## Every non-empty attack of the weapon: the basic combo in order, then the heavy attack.
## Duplicate ids are kept here (validate() reports them).
func get_all_attacks() -> Array[AttackDefinition2D]:
	var all: Array[AttackDefinition2D] = []
	for entry in basic_combo:
		if entry != null:
			all.append(entry)
	if heavy_attack != null:
		all.append(heavy_attack)
	return all

## The attacks beyond the default one, in the shape AttackComponent2D.attacks expects: the rest of
## the combo, then the heavy attack. Entries with the same id as the default attack are left out.
func get_extra_attacks() -> Array[AttackDefinition2D]:
	var extras: Array[AttackDefinition2D] = []
	var default_attack := get_default_attack()
	for attack in get_all_attacks():
		if attack == default_attack:
			continue
		if default_attack != null and attack.id == default_attack.id:
			continue
		extras.append(attack)
	return extras

## The skill with this id, or null.
func get_skill(skill_id: StringName) -> SkillDefinition2D:
	if skill_id == &"":
		return null
	for skill in active_skills:
		if skill != null and skill.id == skill_id:
			return skill
	return null

## The skill in this 0-based slot, or null.
func get_skill_in_slot(slot: int) -> SkillDefinition2D:
	for skill in active_skills:
		if skill != null and skill.slot == slot:
			return skill
	return null

func get_skill_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for skill in active_skills:
		if skill != null:
			ids.append(skill.id)
	return ids

## The attack with this id, or null. An empty id finds nothing.
func get_attack(attack_id: StringName) -> AttackDefinition2D:
	if attack_id == &"":
		return null
	for attack in get_all_attacks():
		if attack.id == attack_id:
			return attack
	return null

func get_attack_ids() -> Array[StringName]:
	var ids: Array[StringName] = []
	for attack in get_all_attacks():
		ids.append(attack.id)
	return ids

## Problems with this weapon as readable messages, each naming the weapon (and the attack or clip
## involved). Empty when the weapon is valid.
##
## Without `animation_player` only the data is checked. With one (the AnimationPlayer the weapon's
## clips live on) every attack's weapon, recovery and charge clip must exist on it.
func validate(animation_player: AnimationPlayer = null) -> Array[String]:
	var problems: Array[String] = []
	var label := _label()
	if weapon_id == &"":
		problems.append("%s: weapon_id is empty." % label)
	if weapon_scene != null and not weapon_scene.can_instantiate():
		problems.append("%s: weapon_scene cannot be instantiated." % label)
	if get_default_attack() == null:
		problems.append("%s: basic_combo has no attack; it needs at least one." % label)

	# Empty entries and ids.
	for i in basic_combo.size():
		if basic_combo[i] == null:
			problems.append("%s: basic_combo[%d] is empty." % [label, i])
	var seen: Dictionary = {}
	for attack in get_all_attacks():
		if attack.id == &"":
			problems.append("%s: an attack has an empty id (an empty id means 'no attack')." % label)
		elif seen.has(attack.id):
			problems.append("%s: attack id '%s' is listed more than once (basic_combo / heavy_attack ids must be unique)." % [label, attack.id])
		seen[attack.id] = true

	# Links must stay inside the weapon, and every combo entry must be reachable from the first.
	for attack in get_all_attacks():
		var link := attack.next_attack
		if link != null and link.id != attack.id and get_attack(link.id) == null:
			problems.append("%s: attack '%s' has next_attack '%s', which is not part of this weapon (add it to basic_combo)." % [label, attack.id, link.id])
		for entry in attack.combo_sequence:
			if entry != null and get_attack(entry.id) == null:
				problems.append("%s: attack '%s' has combo_sequence entry '%s', which is not part of this weapon (add it to basic_combo)." % [label, attack.id, entry.id])
	problems.append_array(_unreachable_combo_problems(label))
	problems.append_array(_skill_problems(label))

	if animation_player != null:
		problems.append_array(_clip_problems(label, animation_player))
	return problems

## A new instance of weapon_scene, or null when there is no scene or its root is not a Node2D. The caller
## owns the instance (mount it or free it).
func instantiate_weapon() -> Node2D:
	if weapon_scene == null or not weapon_scene.can_instantiate():
		return null
	var instance := weapon_scene.instantiate()
	if not instance is Node2D:
		instance.free()
		return null
	return instance as Node2D

## Problems with the weapon's own scene, as readable messages naming the weapon: it cannot be
## instantiated, its root is not a Node2D, it has no AnimationPlayer, or one of the clips its attacks name
## is missing from that player. Empty when the scene is fine, and also when the weapon has no scene (there
## is nothing to check; use validate(animation_player) against the character's rig then).
func validate_scene() -> Array[String]:
	var problems: Array[String] = []
	if weapon_scene == null:
		return problems
	var label := _label()
	if not weapon_scene.can_instantiate():
		problems.append("%s: weapon_scene cannot be instantiated." % label)
		return problems
	var instance := weapon_scene.instantiate()
	if not instance is Node2D:
		problems.append("%s: weapon_scene root must be a Node2D (it is mounted under the character's weapon pivot)." % label)
		instance.free()
		return problems
	var player := CharacterContext2D.find_weapon_player(instance)
	if player == null:
		problems.append("%s: weapon_scene has no AnimationPlayer child (expected one called HandAnim, or any AnimationPlayer)." % label)
	else:
		problems.append_array(_clip_problems(label, player))
	instance.free()
	return problems

## basic_combo entries that no next_attack / combo_sequence chain starting at the default attack
## reaches. They could never be performed by chaining.
func _unreachable_combo_problems(label: String) -> Array[String]:
	var problems: Array[String] = []
	var first := get_default_attack()
	if first == null:
		return problems
	var reached: Dictionary = {}
	var queue: Array[AttackDefinition2D] = [first]
	while not queue.is_empty():
		var current: AttackDefinition2D = queue.pop_front()
		if reached.has(current.id):
			continue
		reached[current.id] = true
		if current.next_attack != null:
			var linked := get_attack(current.next_attack.id)
			if linked != null:
				queue.append(linked)
		for entry in current.combo_sequence:
			if entry != null:
				var in_sequence := get_attack(entry.id)
				if in_sequence != null:
					queue.append(in_sequence)
	for entry in basic_combo:
		if entry != null and entry != first and entry.id != first.id and not reached.has(entry.id):
			problems.append("%s: basic_combo entry '%s' cannot be reached from '%s' (no next_attack or combo_sequence leads to it)." % [label, entry.id, first.id])
	return problems

## Problems with the active skills: too many, empty entries, each skill's own data, duplicate ids and duplicate slots.
func _skill_problems(label: String) -> Array[String]:
	var problems: Array[String] = []
	if active_skills.size() > MAX_SKILL_SLOTS:
		problems.append("%s: has %d active skills but only %d slots." % [label, active_skills.size(), MAX_SKILL_SLOTS])
	var seen_ids: Dictionary = {}
	var seen_slots: Dictionary = {}
	for i in active_skills.size():
		var skill := active_skills[i]
		if skill == null:
			problems.append("%s: active_skills[%d] is empty." % [label, i])
			continue
		for message in skill.validate(null, MAX_SKILL_SLOTS):
			problems.append("%s: %s" % [label, message])
		if skill.id != &"":
			if seen_ids.has(skill.id):
				problems.append("%s: skill id '%s' is listed more than once (active_skills ids must be unique)." % [label, skill.id])
			seen_ids[skill.id] = true
		if seen_slots.has(skill.slot):
			problems.append("%s: skills '%s' and '%s' both use slot %d." % [label, seen_slots[skill.slot], skill.id, skill.slot])
		else:
			seen_slots[skill.slot] = skill.id
	return problems

func _clip_problems(label: String, animation_player: AnimationPlayer) -> Array[String]:
	var problems: Array[String] = []
	for skill in active_skills:
		if skill != null and skill.weapon_animation != &"" and not animation_player.has_animation(skill.weapon_animation):
			problems.append("%s: skill '%s' needs clip '%s' (weapon_animation) on the weapon AnimationPlayer." % [label, skill.id, skill.weapon_animation])
	for attack in get_all_attacks():
		if not animation_player.has_animation(attack.weapon_animation):
			problems.append("%s: attack '%s' needs clip '%s' (weapon_animation) on the weapon AnimationPlayer." % [label, attack.id, attack.weapon_animation])
		if attack.recovery_animation != &"":
			if not animation_player.has_animation(attack.recovery_animation):
				problems.append("%s: attack '%s' needs clip '%s' (recovery_animation) on the weapon AnimationPlayer." % [label, attack.id, attack.recovery_animation])
			elif attack.recovery_animation == attack.weapon_animation:
				problems.append("%s: attack '%s' recovery_animation must differ from weapon_animation ('%s')." % [label, attack.id, attack.weapon_animation])
		if attack.charge_animation != &"" and not animation_player.has_animation(attack.charge_animation):
			problems.append("%s: attack '%s' needs clip '%s' (charge_animation) on the weapon AnimationPlayer." % [label, attack.id, attack.charge_animation])
	return problems

func _label() -> String:
	if weapon_id != &"":
		return "weapon '%s'" % weapon_id
	if display_name != "":
		return "weapon '%s'" % display_name
	return "weapon (unnamed)"
