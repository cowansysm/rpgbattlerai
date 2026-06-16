class_name CameraRig
extends Node3D
## FFT-style camera: fixed pitch, four 90° snap views, zoom, and pan.

@export var pitch_deg: float = 40.0
@export var zoom_val: float = 10.0
@export var zoom_min: float = 4.0
@export var zoom_max: float = 20.0
@export var pan_speed: float = 8.0
@export var zoom_step: float = 1.0
@export var mouse_pan_speed: float = 0.02

const YAW_ANGLES := [0.0, 90.0, 180.0, 270.0]
const TWEEN_DURATION := 0.3

var _yaw_index: int = 0
var _current_yaw_deg: float = 0.0	# Continuous yaw for smooth spherical interpolation
var _camera: Camera3D
var _tweening := false
var _mmb_dragging: bool = false
var _mmb_last_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	_camera = Camera3D.new()
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = zoom_val
	add_child(_camera)
	_apply_transform()


func _apply_transform() -> void:
	var yaw_rad := deg_to_rad(_current_yaw_deg)
	var pitch_rad := deg_to_rad(pitch_deg)

	# Position camera on a sphere around the pivot (rig's origin).
	var dist := zoom_val * 1.5
	var offset := Vector3(
		sin(yaw_rad) * cos(pitch_rad) * dist,
		sin(pitch_rad) * dist,
		cos(yaw_rad) * cos(pitch_rad) * dist
	)
	_camera.position = offset
	_camera.look_at(global_position, Vector3.UP)
	_camera.size = zoom_val


func rotate_view(dir: int) -> void:
	if _tweening:
		return
	_yaw_index = wrapi(_yaw_index + dir, 0, 4)
	_tween_to_current_yaw(dir)


func _tween_to_current_yaw(dir: int) -> void:
	_tweening = true
	# Tween the yaw angle by ±90° so the camera follows the spherical arc.
	var target_yaw := _current_yaw_deg + dir * 90.0
	var tw := create_tween()
	tw.tween_method(_set_yaw_deg, _current_yaw_deg, target_yaw, TWEEN_DURATION)\
		.set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
	tw.tween_callback(func() -> void:
		_tweening = false
	)


func _set_yaw_deg(deg: float) -> void:
	_current_yaw_deg = deg
	_apply_transform()


func zoom_by(delta: float) -> void:
	zoom_val = clampf(zoom_val + delta, zoom_min, zoom_max)
	_apply_transform()


func pan(input_dir: Vector2, dt: float) -> void:
	# Pan relative to the camera's yaw so WASD always feels correct.
	_apply_pan(input_dir * pan_speed * dt)


func _apply_pan(world_dir: Vector2) -> void:
	var yaw_rad := deg_to_rad(_current_yaw_deg)
	var forward := Vector3(-sin(yaw_rad), 0.0, -cos(yaw_rad))
	var right := Vector3(cos(yaw_rad), 0.0, -sin(yaw_rad))
	position += right * world_dir.x + forward * world_dir.y


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("camera_rotate_left"):
		rotate_view(-1)
	elif event.is_action_pressed("camera_rotate_right"):
		rotate_view(1)
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			_mmb_dragging = mb.pressed
			_mmb_last_pos = mb.position
			get_viewport().set_input_as_handled()
		elif mb.pressed:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				zoom_by(-zoom_step)
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				zoom_by(zoom_step)
	elif event is InputEventMouseMotion and _mmb_dragging:
		var motion := event as InputEventMouseMotion
		var delta := motion.position - _mmb_last_pos
		_mmb_last_pos = motion.position
		_apply_pan(Vector2(-delta.x, delta.y) * mouse_pan_speed)
		get_viewport().set_input_as_handled()


func _process(dt: float) -> void:
	var input_dir := Vector2.ZERO
	if Input.is_action_pressed("camera_pan_right"):
		input_dir.x += 1.0
	if Input.is_action_pressed("camera_pan_left"):
		input_dir.x -= 1.0
	if Input.is_action_pressed("camera_pan_up"):
		input_dir.y += 1.0
	if Input.is_action_pressed("camera_pan_down"):
		input_dir.y -= 1.0
	if input_dir != Vector2.ZERO:
		pan(input_dir, dt)


func get_camera() -> Camera3D:
	return _camera
