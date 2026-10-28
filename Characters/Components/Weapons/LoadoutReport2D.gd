class_name LoadoutReport2D
extends RefCounted
## Everything wrong, and everything suspicious, about one weapon's loadout, found in a single pass (H3.1).
##
## The chain it walks: the weapon definition, its scene (root, animation player, the clips its attacks and skills name),
## each attack's effect scene (nodes, hit shape, clips) and its statuses, each skill (data, slot collisions, duplicate
## ids, its attack's effect scene) and the status and passive references. No step stops the others, so a deliberately
## broken weapon lists all of its problems at once instead of one per run.
##
## problems are things that make the weapon unusable; WeaponController2D refuses a weapon that has any.
## warnings are things that work but are probably not what the author meant; they never block anything.

var weapon_label := ""
var problems: Array[String] = []
var warnings: Array[String] = []

func is_valid() -> bool:
	return problems.is_empty()

## A readable report: a header line, then one line per problem and per warning.
func to_text() -> String:
	var lines: Array[String] = ["%s: %d problem(s), %d warning(s)" % [weapon_label, problems.size(), warnings.size()]]
	for message in problems:
		lines.append("  problem: %s" % message)
	for message in warnings:
		lines.append("  warning: %s" % message)
	return "\n".join(lines)

## The report for `weapon`. `animation_player` is the player that holds the clips of a weapon with no scene of its own
## (the character's rig); a weapon with a scene is checked against its own player and ignores it.
static func for_weapon(weapon: WeaponDefinition2D, animation_player: AnimationPlayer = null) -> LoadoutReport2D:
	var report := LoadoutReport2D.new()
	if weapon == null:
		report.weapon_label = "no weapon"
		report.problems.append("LoadoutReport2D: no weapon given.")
		return report
	var label := weapon._label()
	report.weapon_label = label
	var has_scene := weapon.weapon_scene != null

	# 1. The definition itself (attacks, combo links, skills, passives) and, for a scene-less weapon, its clips on the rig.
	for message in weapon.validate(null if has_scene else animation_player):
		report._add_problem(message)
	# 2. The weapon scene: instantiable, a Node2D root, an AnimationPlayer holding every clip the attacks and skills name.
	for message in weapon.validate_scene():
		report._add_problem(message)

	# 3. Each attack: effect scene present, usable, with its clip and its own structure; its statuses.
	for attack in weapon.get_all_attacks():
		var owner_text := "attack '%s'" % attack.id
		if attack.effect_scene == null:
			report._add_problem("%s: %s has no effect_scene (every attack needs its own effect scene)." % [label, owner_text])
		elif not attack.effect_scene.can_instantiate():
			report._add_problem("%s: %s has an effect_scene that cannot be instantiated." % [label, owner_text])
		else:
			if AttackSlash2D.scene_lacks_animation(attack.effect_scene, attack.effect_animation):
				report._add_problem("%s: %s needs clip '%s' (effect_animation) in its effect_scene." % [label, owner_text, attack.effect_animation])
			report._add_effect_scene_problems(label, owner_text, attack)
		if attack.release_mode == AttackDefinition2D.ReleaseMode.THRESHOLD and attack.charge_threshold <= 0.0:
			report._add_problem("%s: %s uses a THRESHOLD release, which needs charge_threshold > 0." % [label, owner_text])
		report._add_attack_status_problems(label, owner_text, attack)

	# 4. Each skill's attack: its effect scene and statuses (the skill's own data was checked in step 1).
	for skill in weapon.active_skills:
		if skill == null:
			continue
		if skill.attack != null:
			var skill_text := "skill '%s' attack '%s'" % [skill.id, skill.attack.id]
			if skill.attack.effect_scene != null and skill.attack.effect_scene.can_instantiate():
				report._add_effect_scene_problems(label, skill_text, skill.attack)
			report._add_attack_status_problems(label, skill_text, skill.attack)
		if skill.status_effect != null:
			report._add_tick_problem(label, "skill '%s'" % skill.id, skill.status_effect)

	# 5. Passive status references.
	for passive in weapon.passive_skills:
		if passive != null and passive.status_effect != null:
			report._add_tick_problem(label, "passive '%s'" % passive.id, passive.status_effect)

	# 6. Warnings: ignored fields, and attack clips that never spawn their effect.
	for message in weapon.get_warnings():
		report._add_warning(message)
	report._add_event_warnings(weapon, label)
	return report

func _add_problem(message: String) -> void:
	if not problems.has(message):
		problems.append(message)

func _add_warning(message: String) -> void:
	if not warnings.has(message):
		warnings.append(message)

func _add_effect_scene_problems(label: String, owner_text: String, attack: AttackDefinition2D) -> void:
	for message in AttackEffect2D.validate_scene(attack.effect_scene, attack.effect_animation):
		_add_problem("%s: %s: %s" % [label, owner_text, message])

## An attack's status_effects: no empty entries, each with an id and a duration, and none that can never tick.
func _add_attack_status_problems(label: String, owner_text: String, attack: AttackDefinition2D) -> void:
	for i in attack.status_effects.size():
		var status := attack.status_effects[i]
		if status == null:
			_add_problem("%s: %s: status_effects[%d] is empty." % [label, owner_text, i])
			continue
		if status.id == &"":
			_add_problem("%s: %s: status_effects[%d] has an empty id." % [label, owner_text, i])
		if status.duration <= 0.0:
			_add_problem("%s: %s: status '%s' needs a duration above 0." % [label, owner_text, status.id])
		_add_tick_problem(label, owner_text, status)

## Damage per tick with no tick interval: the status would hold damage it can never deal.
func _add_tick_problem(label: String, owner_text: String, status: StatusEffectDefinition2D) -> void:
	if status.tick_damage > 0 and status.tick_interval <= 0.0:
		_add_problem("%s: %s: status '%s' has tick_damage %d but tick_interval 0, so it never ticks." % [label, owner_text, status.id, status.tick_damage])

## A weapon scene's attack clips should call attack_event(&"spawn_effect") at least once, or the attack plays but never
## spawns its effect. Only a warning: a clip may legitimately be driven some other way.
func _add_event_warnings(weapon: WeaponDefinition2D, label: String) -> void:
	if weapon.weapon_scene == null or not weapon.weapon_scene.can_instantiate():
		return
	var instance := weapon.weapon_scene.instantiate()
	var player := CharacterContext2D.find_weapon_player(instance)
	if player != null:
		for attack in weapon.get_all_attacks():
			if player.has_animation(attack.weapon_animation) and not _clip_spawns_effect(player.get_animation(attack.weapon_animation)):
				_add_warning("%s: attack '%s': clip '%s' has no attack_event(&\"spawn_effect\") key, so the attack never spawns its effect." % [label, attack.id, attack.weapon_animation])
	instance.free()

static func _clip_spawns_effect(clip: Animation) -> bool:
	for i in clip.get_track_count():
		if clip.track_get_type(i) != Animation.TYPE_METHOD:
			continue
		for k in clip.track_get_key_count(i):
			if clip.method_track_get_name(i, k) != &"attack_event":
				continue
			var params := clip.method_track_get_params(i, k)
			if params.size() >= 1 and (typeof(params[0]) == TYPE_STRING_NAME or typeof(params[0]) == TYPE_STRING) and StringName(params[0]) == &"spawn_effect":
				return true
	return false
