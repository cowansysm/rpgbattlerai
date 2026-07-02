class_name IntentPlan
extends RefCounted
## Serializable representation of one AI unit's committed intent for a round.
## Produced by TelegraphService from the AI's AIPlan.
## Consumed by the telegraph overlay for visual feedback.
## Spec reference: alpha-phaseA15-spec.md §3


var unit_id: String = ""
var unit_ref: BattleUnit = null			# Runtime reference (not serialized)
var move_to: Vector2i = Vector2i.MAX	# Destination tile, or current pos if no move
var path: Array = []					# Array[Vector2i] — ordered path from current to move_to
var action_kind: String = ""			# "attack", "ability", "defend", "wait", "use_item", ""
var ability_id: String = ""
var item_id: String = ""
var target_pos: Vector2i = Vector2i.MAX
var target_unit_id: String = ""			# For single-target actions
var aoe_footprint: Array = []			# Array[Vector2i] — hexes affected by AoE
var projection: Dictionary = {}			# {min: int, mid: int, max: int} from OutcomeProjection
var committed: bool = false
## A19: arc of this action against the target (Hex.Arc int); -1 when not applicable
var arc: int = -1
## A18/A19: data-only annotation of likely reactions (e.g. ["counter"]) for telegraph overlay
var likely_reactions: Array = []
