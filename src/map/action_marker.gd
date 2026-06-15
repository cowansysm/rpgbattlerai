class_name ActionMarker
extends MeshInstance3D
## Animated 3D billboard icon that drops in above a target, holds briefly,
## then fades out and removes itself. Fire-and-forget visual feedback for
## combat actions (abilities, attacks, items).
## Spec reference: phase10-spec.md §3

const QUAD_SIZE := Vector2(0.3, 0.3)
const DROP_HEIGHT := 0.5
const DROP_DURATION := 0.2
const HOLD_DURATION := 0.4
const FADE_DURATION := 0.3


static func create(icon_id: String) -> ActionMarker:
	var marker := ActionMarker.new()
	var quad := QuadMesh.new()
	quad.size = QUAD_SIZE
	marker.mesh = quad

	var mat := SymbolAtlas.make_3d_material(icon_id)
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	marker.material_override = mat

	return marker


func play() -> void:
	var rest_y := position.y
	position.y += DROP_HEIGHT

	var tw := create_tween()
	# Phase 1 — Drop: descend to resting point
	tw.tween_property(self, "position:y", rest_y, DROP_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# Phase 2 — Hold: pause at resting point
	tw.tween_interval(HOLD_DURATION)
	# Phase 3 — Fade: smooth alpha to zero
	tw.tween_method(_set_alpha, 1.0, 0.0, FADE_DURATION)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	# Phase 4 — Cleanup
	tw.tween_callback(queue_free)


func _set_alpha(alpha: float) -> void:
	var mat: StandardMaterial3D = material_override
	if mat:
		mat.albedo_color.a = alpha
