class_name AbilitySymbolPawn
extends RigidBody3D
## Physics-dropped 3D icon token showing an ability's symbol beside a target.
## Lifecycle: SPAWN → FALL (physics) → DWELL (rest) → SINK (tween) → free.
## Replaces ActionMarker for ability/attack/item visual feedback.

signal landed

enum State { FALL, DWELL, SINK }

const PAWN_SIZE := 0.2

var _state: int = State.FALL
var _land_y: float = 0.0
var _landed: bool = false
var _fall_timer: float = 0.0
var _max_land_wait: float = 0.8
var _dwell_time: float = 2.5
var _sink_duration: float = 1.0
var _body_mesh: MeshInstance3D
var _material: StandardMaterial3D
var _collider: StaticBody3D


static func create(icon_id: String, land_y: float) -> AbilitySymbolPawn:
	var pawn := AbilitySymbolPawn.new()
	pawn._land_y = land_y
	pawn._max_land_wait = float(Constants.get_value("SYMBOL_PAWN_MAX_LAND_WAIT", 0.8))
	pawn._dwell_time = float(Constants.get_value("SYMBOL_PAWN_DWELL", 2.5))
	pawn._sink_duration = float(Constants.get_value("SYMBOL_PAWN_SINK_DURATION", 1.0))

	# Physics properties
	pawn.mass = float(Constants.get_value("SYMBOL_PAWN_MASS", 1.0))
	pawn.gravity_scale = float(Constants.get_value("SYMBOL_PAWN_GRAVITY_SCALE", 1.4))
	var bounce_val: float = float(Constants.get_value("SYMBOL_PAWN_BOUNCE", 0.25))
	var linear_damp_val: float = float(Constants.get_value("SYMBOL_PAWN_LINEAR_DAMP", 0.2))
	var angular_damp_val: float = float(Constants.get_value("SYMBOL_PAWN_ANGULAR_DAMP", 0.2))
	pawn.linear_damp = linear_damp_val
	pawn.angular_damp = angular_damp_val

	# Physics material for bounce
	var phys_mat := PhysicsMaterial.new()
	phys_mat.bounce = bounce_val
	pawn.physics_material_override = phys_mat

	# Collision: layer 8 only (dedicated symbol pawn layer)
	pawn.collision_layer = 1 << 7  # Layer 8 (0-indexed bit 7)
	pawn.collision_mask = 1 << 7

	# Visual mesh — small box textured with ability icon
	pawn._body_mesh = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(PAWN_SIZE, PAWN_SIZE * 0.3, PAWN_SIZE)
	pawn._body_mesh.mesh = box
	pawn._material = SymbolAtlas.make_3d_material(icon_id)
	pawn._material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	pawn._body_mesh.material_override = pawn._material
	pawn.add_child(pawn._body_mesh)

	# Collision shape for the pawn body
	var col_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(PAWN_SIZE, PAWN_SIZE * 0.3, PAWN_SIZE)
	col_shape.shape = shape
	pawn.add_child(col_shape)

	# Add initial tumble for visual variety
	pawn.angular_velocity = Vector3(
		randf_range(-3.0, 3.0),
		randf_range(-1.0, 1.0),
		randf_range(-3.0, 3.0))

	return pawn


func setup_landing_collider(parent: Node, world_pos: Vector3) -> void:
	## Creates a thin static body at the landing surface so the pawn has
	## something to collide with. Call after adding the pawn to the scene.
	_collider = StaticBody3D.new()
	_collider.collision_layer = 1 << 7
	_collider.collision_mask = 1 << 7
	var col_shape := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.6, 0.02, 0.6)
	col_shape.shape = shape
	_collider.add_child(col_shape)
	_collider.position = Vector3(world_pos.x, _land_y, world_pos.z)
	parent.add_child(_collider)


func _physics_process(delta: float) -> void:
	if _state != State.FALL:
		return

	_fall_timer += delta

	# Detect landing: body sleeping or velocity very low or timeout
	var vel_low: bool = linear_velocity.length() < 0.1 and _fall_timer > 0.15
	var timed_out: bool = _fall_timer >= _max_land_wait

	if sleeping or vel_low or timed_out:
		_on_landed()


func _on_landed() -> void:
	if _landed:
		return
	_landed = true
	_state = State.DWELL
	freeze = true
	landed.emit()

	# Start dwell timer, then sink
	get_tree().create_timer(_dwell_time).timeout.connect(_start_sink)


func _start_sink() -> void:
	_state = State.SINK
	freeze = true

	var tw := create_tween()
	tw.tween_property(self, "position:y", position.y - 1.0, _sink_duration)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.parallel().tween_method(_set_alpha, 1.0, 0.0, _sink_duration)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(_cleanup)


func _set_alpha(alpha: float) -> void:
	if _material:
		_material.albedo_color.a = alpha


func _cleanup() -> void:
	if is_instance_valid(_collider):
		_collider.queue_free()
	queue_free()
