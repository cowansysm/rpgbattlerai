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
var _chevron: MeshInstance3D		## A19: facing indicator
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

	# A19: facing chevron (small plane in front of the token)
	_chevron = MeshInstance3D.new()
	var chevron_plane := PlaneMesh.new()
	chevron_plane.size = Vector2(0.12, 0.08)
	_chevron.mesh = chevron_plane
	var chevron_mat := StandardMaterial3D.new()
	chevron_mat.albedo_color = Color(1.0, 1.0, 0.0, 0.9)
	chevron_mat.flags_unshaded = true
	_chevron.material_override = chevron_mat
	_chevron.position.y = PawnFactory.TOKEN_HEIGHT * 0.5 + 0.002
	add_child(_chevron)

	place(unit.position, graph)
	set_facing(unit.facing)


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


## A19: Yaw the pawn and position the chevron in the facing direction.
func set_facing(dir: int) -> void:
	var yaw_deg: float = HexWorld.direction_yaw(dir)
	rotation_degrees.y = yaw_deg
	# Move the chevron forward in local +Z (after yaw, +Z points in the facing direction)
	var offset: float = 0.26
	_chevron.position.x = sin(deg_to_rad(yaw_deg)) * offset
	_chevron.position.z = cos(deg_to_rad(yaw_deg)) * offset


func remove() -> void:
	queue_free()
