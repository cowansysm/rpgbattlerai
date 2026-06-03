class_name Phase3Demo
extends Node
## Phase 3 demo controller. Places a BattleUnit marker on the map and
## provides keybinds to toggle movement/target overlays.
## Validates the runtime-state pattern: marker is a BattleUnit, not raw stats.

@export var character_id := "human_rogue"
@export var start := Vector2i(0, 0)
@export var weapon_range := 3

var _unit: BattleUnit
var _graph: HexGraph
var _overlay: OverlayController


func setup(builder: MapBuilder, map_data: MapData) -> void:
	# Create a BattleUnit from the loaded character.
	var c := GameData.get_character(character_id)
	var fs := GameData.get_final_stats(character_id)
	if not c or not fs:
		Log.error("Phase3Demo", "Character '%s' not found" % character_id)
		return
	_unit = BattleUnit.from_character(c, fs)
	_unit.position = start

	# Build the hex graph with GameData.get_terrain as injected provider.
	_graph = HexGraph.new()
	_graph.build(map_data, GameData.get_terrain)

	# Create overlay controller.
	_overlay = OverlayController.new()
	_overlay.graph = _graph
	_overlay.builder = builder
	add_child(_overlay)

	Log.info("Phase3Demo", "Marker placed at (%d, %d) — %s Move=%d Jump=%d" % [
		start.x, start.y, c.display_name,
		_unit.stats.effective_move(), _unit.stats.effective_jump_climb()])


func _unhandled_input(event: InputEvent) -> void:
	if not _unit or not _overlay:
		return
	if event.is_action_pressed("demo_show_move"):
		_show_move()
	elif event.is_action_pressed("demo_show_targets"):
		_show_targets()
	elif event.is_action_pressed("demo_clear"):
		_overlay.clear()


func _show_move() -> void:
	var move: int = _unit.stats.effective_move()
	var jump: int = _unit.stats.effective_jump_climb()
	_overlay.show_movement(_unit.position, move, jump)
	Log.info("Phase3Demo", "Movement overlay: Move=%d Jump=%d from (%d,%d)" % [
		move, jump, _unit.position.x, _unit.position.y])


func _show_targets() -> void:
	_overlay.show_targets(_unit.position, weapon_range)
	Log.info("Phase3Demo", "Target overlay: range=%d from (%d,%d)" % [
		weapon_range, _unit.position.x, _unit.position.y])
