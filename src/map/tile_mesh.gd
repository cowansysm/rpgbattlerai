class_name TileMesh
extends RefCounted
## Factory for the shared hex tile mesh (CylinderMesh with 6 radial segments).
## Flat-top orientation achieved by rotating the tile node 30° at instantiation.

const TILE_HEIGHT := 0.1


static func make_hex_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = HexWorld.HEX_SIZE
	m.bottom_radius = HexWorld.HEX_SIZE
	m.height = TILE_HEIGHT
	m.radial_segments = 6
	m.rings = 0
	return m


static func make_wall_mesh(wall_height: float) -> Mesh:
	## Hex-shaped cylinder for the vertical side face below a tile.
	## No top cap needed (the base tile sits on top); bottom cap closes
	## the column at ground level.
	var m := CylinderMesh.new()
	m.top_radius = HexWorld.HEX_SIZE
	m.bottom_radius = HexWorld.HEX_SIZE
	m.height = wall_height
	m.radial_segments = 6
	m.rings = 0
	return m
