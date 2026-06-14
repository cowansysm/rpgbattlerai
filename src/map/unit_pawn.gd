class_name UnitPawn
extends Node3D
## 3D token representing one deployed character on the hex map.
## Two visual layers: team-colored cylinder body + symbol face on top.
## Spec reference: phase8-spec.md §3.2

const TWEEN_DURATION := 0.3
const FLIP_DURATION := 0.25

var unit: BattleUnit

var _body: MeshInstance3D
var _symbol_face: MeshInstance3D
var _default_material: StandardMaterial3D
var _active_material: StandardMaterial3D


func setup(battle_unit: BattleUnit, graph: HexGraph) -> void:
	unit = battle_unit

	var race: String = unit.character.race
	var job_class: String = unit.character.classes[0] if not unit.character.classes.is_empty() else ""
	var team: String = unit.team

	# Cylinder body
	_body = MeshInstance3D.new()
	_body.mesh = PawnFactory.make_token_mesh()
	_default_material = PawnFactory.team_material(team)
	_active_material = PawnFactory.active_material(team)
	_body.material_override = _default_material
	add_child(_body)

	# Symbol face on top (PlaneMesh facing up)
	_symbol_face = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(0.35, 0.35)
	_symbol_face.mesh = plane
	_symbol_face.material_override = PawnFactory.symbol_material(race, job_class, team)
	_symbol_face.position.y = PawnFactory.TOKEN_HEIGHT * 0.5 + 0.001
	_symbol_face.rotation.x = 0  # PlaneMesh already faces up by default in Godot
	add_child(_symbol_face)

	place(unit.position, graph)


func place(coord: Vector2i, graph: HexGraph) -> void:
	var elev: int = graph.elevation(coord)
	var world_pos := HexWorld.hex_to_world(coord.x, coord.y, elev)
	world_pos.y += TileMesh.TILE_HEIGHT * 0.5 + PawnFactory.TOKEN_HEIGHT * 0.5
	position = world_pos


func move_to(coord: Vector2i, graph: HexGraph) -> Tween:
	var elev: int = graph.elevation(coord)
	var target := HexWorld.hex_to_world(coord.x, coord.y, elev)
	target.y += TileMesh.TILE_HEIGHT * 0.5 + PawnFactory.TOKEN_HEIGHT * 0.5
	var tw := create_tween()
	tw.tween_property(self, "position", target, TWEEN_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	return tw


func set_active(active: bool) -> void:
	if _body:
		_body.material_override = _active_material if active else _default_material


func set_downed(downed: bool) -> Tween:
	var tw := create_tween()
	if downed:
		tw.tween_property(self, "rotation_degrees:x", 180.0, FLIP_DURATION)\
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	else:
		tw.tween_property(self, "rotation_degrees:x", 0.0, FLIP_DURATION)\
			.set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_CUBIC)
	return tw


func remove() -> void:
	queue_free()
