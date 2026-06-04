extends Node3D
## Main map scene. Loads a MapData, builds the 3D hex map, wires camera and picker.

@export var map_id: String = "forest_clearing"


func _ready() -> void:
	var map_data: MapData = GameData.get_map(map_id)
	if not map_data:
		Log.error("MapScene", "Map '%s' not found in GameData" % map_id)
		return

	# Build hex tiles.
	var builder := MapBuilder.new()
	add_child(builder)
	builder.build(map_data)

	# Camera rig centered on map.
	var rig := CameraRig.new()
	rig.position = builder.focus_center()
	add_child(rig)

	# Tile picker wired to camera.
	var picker := TilePicker.new()
	picker.setup(rig.get_camera())
	add_child(picker)

	# Phase 4 demo: combat activation & action economy.
	var demo := Phase4Demo.new()
	demo.setup(builder, map_data)
	add_child(demo)

	# Wire tile picker to demo for selected-tile tracking.
	picker.tile_selected.connect(func(coord: Vector2i) -> void:
		demo.set_selected_tile(coord))

	# Basic directional light.
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45.0, -30.0, 0.0)
	light.light_energy = 1.0
	light.shadow_enabled = true
	add_child(light)

	# Ambient environment so shadows aren't pitch black.
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.55, 0.70, 0.85)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.4, 0.4, 0.5)
	env.ambient_light_energy = 0.5
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	Log.info("MapScene", "Map '%s' ready (%d tiles)" % [map_id, builder.tiles.size()])
