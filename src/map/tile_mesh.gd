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
