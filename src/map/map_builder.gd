class_name MapBuilder
extends Node3D
## Builds a 3D hex map scene from a MapData resource.
## Iterates TileRecords, instantiates HexTile nodes at correct world positions.

var tiles: Dictionary = {}  # Vector2i → HexTile


func build(map_data: MapData) -> void:
	var mesh := TileMesh.make_hex_mesh()
	var highlight_mat := HighlightMaterial.make()

	# Compute floor elevation so walls extend to the lowest tile
	var floor_elev := 0
	for tile_rec in map_data.tiles:
		if tile_rec.elevation < floor_elev:
			floor_elev = tile_rec.elevation

	for tile_rec in map_data.tiles:
		var mat := TerrainPalette.material_for(tile_rec.terrain, tile_rec.elevation)
		var hex_tile := HexTile.new()
		hex_tile.setup(tile_rec.q, tile_rec.r, tile_rec.elevation,
			tile_rec.terrain, mesh, mat, highlight_mat, floor_elev)
		add_child(hex_tile)
		tiles[tile_rec.coord()] = hex_tile

	Log.info("MapBuilder", "Built %d tiles for map '%s'" % [tiles.size(), map_data.id])


func focus_center() -> Vector3:
	if tiles.is_empty():
		return Vector3.ZERO
	var sum := Vector3.ZERO
	for tile in tiles.values():
		sum += tile.position
	return sum / tiles.size()


func get_tile(coord: Vector2i) -> HexTile:
	return tiles.get(coord)
