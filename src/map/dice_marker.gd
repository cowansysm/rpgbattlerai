class_name DiceMarker
extends Node3D
## Animated 3D D6 cube showing a dice roll result above a pawn.
## Tumbles in place, settles with the result face on top, then fades out
## and self-destructs. Fire-and-forget visual feedback for combat dice rolls.
## Attack dice are tinted gold, defense dice light blue.

const CUBE_SIZE := 0.12
const HALF := CUBE_SIZE / 2.0
const FACE_OFFSET := HALF + 0.001
const QUAD_SIZE := CUBE_SIZE * 0.95

const ROLL_DURATION := 2.0
const HOLD_DURATION := 1.0
const FADE_DURATION := 0.3

const ATK_COLOR := Color(1.0, 0.85, 0.2)    # Gold
const DEF_COLOR := Color(0.4, 0.75, 1.0)    # Light blue
const BODY_COLOR := Color(0.15, 0.15, 0.15) # Dark cube body

const TEX_SIZE := 64
const PIP_RADIUS := 6
const PIP_COLOR := Color(0.15, 0.15, 0.15)
const FACE_BG := Color(0.95, 0.95, 0.92)

# Rotation to put value V on top (+Y). Standard d6 layout: opposite faces sum to 7.
# +Y=1, -Y=6, +Z=2, -Z=5, +X=3, -X=4
const _RESULT_ROTATIONS := {
	1: Vector3(0, 0, 0),
	2: Vector3(-PI / 2, 0, 0),
	3: Vector3(0, 0, PI / 2),
	4: Vector3(0, 0, -PI / 2),
	5: Vector3(PI / 2, 0, 0),
	6: Vector3(PI, 0, 0),
}

static var _pip_textures: Dictionary = {}  # int (1-6) -> ImageTexture

var _value: int
var _is_attack: bool
var _body: MeshInstance3D
var _faces: Array[MeshInstance3D] = []
var _face_materials: Array[StandardMaterial3D] = []


static func create(value: int, is_attack: bool = true) -> DiceMarker:
	_ensure_textures()
	var marker := DiceMarker.new()
	marker._value = clampi(value, 1, 6)
	marker._is_attack = is_attack
	marker._build()
	return marker


func _build() -> void:
	var tint := ATK_COLOR if _is_attack else DEF_COLOR

	# Core body (BoxMesh)
	_body = MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(CUBE_SIZE, CUBE_SIZE, CUBE_SIZE)
	_body.mesh = box
	var body_mat := StandardMaterial3D.new()
	body_mat.albedo_color = BODY_COLOR
	body_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	body_mat.render_priority = -1  # Render behind face quads
	_body.material_override = body_mat
	add_child(_body)

	# Six face quads with pip textures
	# QuadMesh default: XY plane facing +Z
	var face_defs := [
		{"value": 1, "pos": Vector3(0, FACE_OFFSET, 0), "rot": Vector3(-PI / 2, 0, 0)},
		{"value": 6, "pos": Vector3(0, -FACE_OFFSET, 0), "rot": Vector3(PI / 2, 0, 0)},
		{"value": 2, "pos": Vector3(0, 0, FACE_OFFSET), "rot": Vector3(0, 0, 0)},
		{"value": 5, "pos": Vector3(0, 0, -FACE_OFFSET), "rot": Vector3(0, PI, 0)},
		{"value": 3, "pos": Vector3(FACE_OFFSET, 0, 0), "rot": Vector3(0, PI / 2, 0)},
		{"value": 4, "pos": Vector3(-FACE_OFFSET, 0, 0), "rot": Vector3(0, -PI / 2, 0)},
	]
	for fd in face_defs:
		var face := MeshInstance3D.new()
		var quad := QuadMesh.new()
		quad.size = Vector2(QUAD_SIZE, QUAD_SIZE)
		face.mesh = quad
		var mat := StandardMaterial3D.new()
		mat.albedo_texture = _pip_textures[fd["value"]]
		mat.albedo_color = tint
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = true
		face.material_override = mat
		face.position = fd["pos"]
		face.rotation = fd["rot"]
		_body.add_child(face)
		_faces.append(face)
		_face_materials.append(mat)


func play() -> void:
	# Randomized extra full rotations for visual variety
	var extra_x := TAU * float(randi_range(2, 4))
	var extra_z := TAU * float(randi_range(2, 4))
	if randf() > 0.5:
		extra_x = -extra_x
	if randf() > 0.5:
		extra_z = -extra_z

	var target_rot: Vector3 = _RESULT_ROTATIONS[_value]
	var final_rotation := Vector3(
		target_rot.x + extra_x,
		0.0,
		target_rot.z + extra_z,
	)

	var tw := create_tween()
	# Phase 1 — Roll: tumble with deceleration (2s)
	tw.tween_property(self, "rotation", final_rotation, ROLL_DURATION)\
		.from(Vector3.ZERO)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	# Phase 2 — Hold: display result (1s)
	tw.tween_interval(HOLD_DURATION)
	# Phase 3 — Fade: smooth alpha transition (0.3s)
	tw.tween_method(_set_alpha, 1.0, 0.0, FADE_DURATION)\
		.set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_CUBIC)
	# Phase 4 — Cleanup
	tw.tween_callback(queue_free)


func _set_alpha(alpha: float) -> void:
	var body_mat: StandardMaterial3D = _body.material_override
	if body_mat:
		body_mat.albedo_color.a = alpha
	for mat in _face_materials:
		mat.albedo_color.a = alpha


# --- Pip texture generation ---

static func _ensure_textures() -> void:
	if not _pip_textures.is_empty():
		return
	for v in range(1, 7):
		var img := Image.create(TEX_SIZE, TEX_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(FACE_BG)
		_draw_pips(img, v)
		_pip_textures[v] = ImageTexture.create_from_image(img)


static func _draw_pips(img: Image, value: int) -> void:
	var cx := TEX_SIZE / 2
	var cy := TEX_SIZE / 2
	var off := 16  # Distance from center to pip cluster

	var positions: Array[Vector2i] = []
	match value:
		1:
			positions = [Vector2i(cx, cy)]
		2:
			positions = [Vector2i(cx - off, cy - off),
						Vector2i(cx + off, cy + off)]
		3:
			positions = [Vector2i(cx - off, cy + off),
						Vector2i(cx, cy),
						Vector2i(cx + off, cy - off)]
		4:
			positions = [Vector2i(cx - off, cy - off),
						Vector2i(cx + off, cy - off),
						Vector2i(cx - off, cy + off),
						Vector2i(cx + off, cy + off)]
		5:
			positions = [Vector2i(cx - off, cy - off),
						Vector2i(cx + off, cy - off),
						Vector2i(cx, cy),
						Vector2i(cx - off, cy + off),
						Vector2i(cx + off, cy + off)]
		6:
			positions = [Vector2i(cx - off, cy - off),
						Vector2i(cx + off, cy - off),
						Vector2i(cx - off, cy),
						Vector2i(cx + off, cy),
						Vector2i(cx - off, cy + off),
						Vector2i(cx + off, cy + off)]

	for pos in positions:
		_draw_circle(img, pos.x, pos.y)


static func _draw_circle(img: Image, px: int, py: int) -> void:
	for y in range(py - PIP_RADIUS, py + PIP_RADIUS + 1):
		for x in range(px - PIP_RADIUS, px + PIP_RADIUS + 1):
			if (x - px) * (x - px) + (y - py) * (y - py) <= PIP_RADIUS * PIP_RADIUS:
				if x >= 0 and x < TEX_SIZE and y >= 0 and y < TEX_SIZE:
					img.set_pixel(x, y, PIP_COLOR)
