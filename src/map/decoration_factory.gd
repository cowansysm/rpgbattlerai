class_name DecorationFactory
extends RefCounted
## Creates simple marker meshes for terrain decorations (trees, boulders).
## Placeholder art only — gameplay semantics live in data, not meshes.

static func make_tree() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = 0.0
	m.bottom_radius = 0.25
	m.height = 0.6
	m.radial_segments = 6
	m.rings = 0
	return m


static func make_boulder() -> Mesh:
	var m := SphereMesh.new()
	m.radius = 0.2
	m.height = 0.3
	m.radial_segments = 6
	m.rings = 3
	return m


static func decoration_for(terrain: String) -> Mesh:
	match terrain:
		"trees":
			return make_tree()
		"rocks":
			return make_boulder()
		_:
			return null
