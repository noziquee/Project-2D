extends Node2D
## The bow's scene root (MainHand). It holds the bow sprite, the nocked "Arrow" sprite and the HandAnim clips.
##
## The nocked arrow is shown and hidden by the clips themselves, on the same key as the spawn_effect event that
## releases the real arrow (bow_draw shows it, bow_shoot and bow_heavy_shoot hide it on the release frame, idle,
## RESET and bow_return keep it hidden). This script only covers the case no clip can: an attack cancelled in the
## middle of a draw or a charge (a hit, death) when the pose is kept instead of playing RESET. AttackComponent2D calls
## on_attack_cancelled() on the mounted weapon, if it has the method, and the arrow is put away.

@onready var _arrow: CanvasItem = get_node_or_null(^"Arrow") as CanvasItem

func on_attack_cancelled() -> void:
	if is_instance_valid(_arrow):
		_arrow.visible = false

## True while the nocked arrow is on the bow (tests and tools).
func is_arrow_shown() -> bool:
	return is_instance_valid(_arrow) and _arrow.visible
