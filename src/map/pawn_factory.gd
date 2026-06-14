class_name PawnFactory
extends RefCounted
## Creates cylindrical token meshes, team-colored materials, and NATO-style
## symbol textures for unit pawns. Follows the DecorationFactory pattern.
## Spec reference: phase8-spec.md §3.1, §3.4

const TOKEN_RADIUS := 0.21
const TOKEN_HEIGHT := 0.105
const SYMBOL_SIZE := 128

const TEAM_COLORS := {
	"playerA": Color(0.2, 0.4, 0.9),
	"playerB": Color(0.9, 0.2, 0.2),
}

const TEAM_EMIT := {
	"playerA": Color(0.3, 0.5, 1.0),
	"playerB": Color(1.0, 0.3, 0.3),
}

# Cache for symbol textures — keyed by "race:class:team"
static var _symbol_cache: Dictionary = {}


static func make_token_mesh() -> Mesh:
	var m := CylinderMesh.new()
	m.top_radius = TOKEN_RADIUS
	m.bottom_radius = TOKEN_RADIUS
	m.height = TOKEN_HEIGHT
	m.radial_segments = 16
	m.rings = 0
	return m


static func team_material(team: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_color = TEAM_COLORS.get(team, Color(0.5, 0.5, 0.5))
	return m


static func active_material(team: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	var base: Color = TEAM_COLORS.get(team, Color(0.5, 0.5, 0.5))
	m.albedo_color = base.lightened(0.3)
	m.emission_enabled = true
	m.emission = TEAM_EMIT.get(team, Color(0.5, 0.5, 0.5))
	m.emission_energy_multiplier = 0.8
	return m


static func make_symbol_texture(race: String, job_class: String, team: String) -> ImageTexture:
	var key := "%s:%s:%s" % [race, job_class, team]
	if _symbol_cache.has(key):
		return _symbol_cache[key]

	var img := Image.create(SYMBOL_SIZE, SYMBOL_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))

	var team_color: Color = TEAM_COLORS.get(team, Color(0.5, 0.5, 0.5))
	var fill_color := team_color.lightened(0.3)
	fill_color.a = 0.8

	_draw_race_frame(img, race, fill_color)
	_draw_class_icon(img, job_class, Color.WHITE)

	var tex := ImageTexture.create_from_image(img)
	_symbol_cache[key] = tex
	return tex


static func symbol_material(race: String, job_class: String, team: String) -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.albedo_texture = make_symbol_texture(race, job_class, team)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA_SCISSOR
	m.alpha_scissor_threshold = 0.1
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	return m


# --- Frame drawing (race) ---

static func _draw_race_frame(img: Image, race: String, fill: Color) -> void:
	var cx := SYMBOL_SIZE / 2
	var cy := SYMBOL_SIZE / 2
	match race:
		"human":
			_draw_rect_frame(img, cx, cy, 48, 48, fill, Color.WHITE)
		"elf":
			_draw_diamond_frame(img, cx, cy, 48, fill, Color.WHITE)
		"halfling":
			_draw_circle_frame(img, cx, cy, 44, fill, Color.WHITE)
		"dwarf":
			_draw_hexagon_frame(img, cx, cy, 46, fill, Color.WHITE)
		_:
			_draw_rect_frame(img, cx, cy, 48, 48, fill, Color.WHITE)


static func _draw_rect_frame(img: Image, cx: int, cy: int, hw: int, hh: int,
		fill: Color, outline: Color) -> void:
	var x0 := cx - hw
	var y0 := cy - hh
	var x1 := cx + hw
	var y1 := cy + hh
	# Fill interior
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			if x >= 0 and x < SYMBOL_SIZE and y >= 0 and y < SYMBOL_SIZE:
				img.set_pixel(x, y, fill)
	# Outline (3px)
	for t in range(3):
		_draw_line_h(img, x0 - t, x1 + t, y0 - t, outline)
		_draw_line_h(img, x0 - t, x1 + t, y1 + t, outline)
		_draw_line_v(img, x0 - t, y0 - t, y1 + t, outline)
		_draw_line_v(img, x1 + t, y0 - t, y1 + t, outline)


static func _draw_diamond_frame(img: Image, cx: int, cy: int, radius: int,
		fill: Color, outline: Color) -> void:
	# Filled diamond
	for y in range(cy - radius, cy + radius + 1):
		var dy := absi(y - cy)
		var half_w := radius - dy
		for x in range(cx - half_w, cx + half_w + 1):
			if x >= 0 and x < SYMBOL_SIZE and y >= 0 and y < SYMBOL_SIZE:
				img.set_pixel(x, y, fill)
	# Outline edges
	for i in range(radius + 1):
		for t in range(3):
			_safe_pixel(img, cx + i + t, cy - radius + i, outline)
			_safe_pixel(img, cx - i - t, cy - radius + i, outline)
			_safe_pixel(img, cx + i + t, cy + radius - i, outline)
			_safe_pixel(img, cx - i - t, cy + radius - i, outline)


static func _draw_circle_frame(img: Image, cx: int, cy: int, radius: int,
		fill: Color, outline: Color) -> void:
	# Filled circle
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			var dx := x - cx
			var dy := y - cy
			var dist_sq := dx * dx + dy * dy
			if dist_sq <= radius * radius:
				if x >= 0 and x < SYMBOL_SIZE and y >= 0 and y < SYMBOL_SIZE:
					img.set_pixel(x, y, fill)
	# Outline ring
	for angle in range(360):
		var rad := deg_to_rad(float(angle))
		for t in range(3):
			var r := radius + t
			var px := cx + int(round(cos(rad) * r))
			var py := cy + int(round(sin(rad) * r))
			_safe_pixel(img, px, py, outline)


static func _draw_hexagon_frame(img: Image, cx: int, cy: int, radius: int,
		fill: Color, outline: Color) -> void:
	# Get 6 vertices of flat-top hexagon
	var verts: Array[Vector2i] = []
	for i in range(6):
		var angle := deg_to_rad(60.0 * i)
		verts.append(Vector2i(cx + int(round(cos(angle) * radius)),
			cy + int(round(sin(angle) * radius))))
	# Scanline fill
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			if _point_in_polygon(x, y, verts):
				_safe_pixel(img, x, y, fill)
	# Outline edges
	for i in range(6):
		var a := verts[i]
		var b := verts[(i + 1) % 6]
		for t in range(3):
			_draw_line_bresenham(img, a.x, a.y, b.x, b.y, outline, t)


# --- Icon drawing (class) ---

static func _draw_class_icon(img: Image, job_class: String, color: Color) -> void:
	var cx := SYMBOL_SIZE / 2
	var cy := SYMBOL_SIZE / 2
	var s := 24  # icon half-size
	match job_class:
		"fighter":
			# Saltire (X)
			_draw_thick_line(img, cx - s, cy - s, cx + s, cy + s, color, 3)
			_draw_thick_line(img, cx + s, cy - s, cx - s, cy + s, color, 3)
		"archer":
			# Upward arrow
			_draw_thick_line(img, cx, cy - s, cx, cy + s, color, 3)
			_draw_thick_line(img, cx - s / 2, cy - s / 2, cx, cy - s, color, 3)
			_draw_thick_line(img, cx + s / 2, cy - s / 2, cx, cy - s, color, 3)
		"rogue":
			# Diagonal slash
			_draw_thick_line(img, cx - s, cy + s, cx + s, cy - s, color, 3)
		"barbarian":
			# Double cross (double-bar cross)
			_draw_thick_line(img, cx, cy - s, cx, cy + s, color, 3)
			_draw_thick_line(img, cx - s, cy - s / 3, cx + s, cy - s / 3, color, 3)
			_draw_thick_line(img, cx - s, cy + s / 3, cx + s, cy + s / 3, color, 3)
		"black_mage":
			# Lightning bolt (zigzag)
			_draw_thick_line(img, cx + s / 3, cy - s, cx - s / 4, cy - 2, color, 3)
			_draw_thick_line(img, cx - s / 4, cy - 2, cx + s / 4, cy + 2, color, 3)
			_draw_thick_line(img, cx + s / 4, cy + 2, cx - s / 3, cy + s, color, 3)
		"white_mage":
			# Upright cross (+)
			_draw_thick_line(img, cx - s, cy, cx + s, cy, color, 3)
			_draw_thick_line(img, cx, cy - s, cx, cy + s, color, 3)
		"red_mage":
			# Hourglass — dual nature (offense + healing)
			_draw_thick_line(img, cx - s, cy - s, cx + s, cy - s, color, 3)
			_draw_thick_line(img, cx - s, cy - s, cx + s, cy + s, color, 3)
			_draw_thick_line(img, cx + s, cy - s, cx - s, cy + s, color, 3)
			_draw_thick_line(img, cx - s, cy + s, cx + s, cy + s, color, 3)
		"bard":
			# Wave/tilde
			for x in range(cx - s, cx + s + 1):
				var t := float(x - cx) / float(s)
				var wave_y := int(round(sin(t * PI * 2.0) * float(s) * 0.4))
				for thick in range(-1, 2):
					_safe_pixel(img, x, cy + wave_y + thick, color)
		_:
			# Fallback: dot
			_draw_circle_filled(img, cx, cy, 6, color)


# --- Drawing primitives ---

static func _draw_line_h(img: Image, x0: int, x1: int, y: int, color: Color) -> void:
	if y < 0 or y >= SYMBOL_SIZE:
		return
	for x in range(maxi(0, x0), mini(SYMBOL_SIZE, x1 + 1)):
		img.set_pixel(x, y, color)


static func _draw_line_v(img: Image, x: int, y0: int, y1: int, color: Color) -> void:
	if x < 0 or x >= SYMBOL_SIZE:
		return
	for y in range(maxi(0, y0), mini(SYMBOL_SIZE, y1 + 1)):
		img.set_pixel(x, y, color)


static func _draw_thick_line(img: Image, x0: int, y0: int, x1: int, y1: int,
		color: Color, thickness: int) -> void:
	for t in range(thickness):
		var offset := t - thickness / 2
		_draw_line_bresenham(img, x0, y0 + offset, x1, y1 + offset, color, 0)
		_draw_line_bresenham(img, x0 + offset, y0, x1 + offset, y1, color, 0)


static func _draw_line_bresenham(img: Image, x0: int, y0: int, x1: int, y1: int,
		color: Color, _offset: int) -> void:
	var dx := absi(x1 - x0)
	var dy := absi(y1 - y0)
	var sx := 1 if x0 < x1 else -1
	var sy := 1 if y0 < y1 else -1
	var err := dx - dy
	var x := x0
	var y := y0
	while true:
		_safe_pixel(img, x, y, color)
		if x == x1 and y == y1:
			break
		var e2 := 2 * err
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy


static func _draw_circle_filled(img: Image, cx: int, cy: int, radius: int,
		color: Color) -> void:
	for y in range(cy - radius, cy + radius + 1):
		for x in range(cx - radius, cx + radius + 1):
			if (x - cx) * (x - cx) + (y - cy) * (y - cy) <= radius * radius:
				_safe_pixel(img, x, y, color)


static func _safe_pixel(img: Image, x: int, y: int, color: Color) -> void:
	if x >= 0 and x < SYMBOL_SIZE and y >= 0 and y < SYMBOL_SIZE:
		img.set_pixel(x, y, color)


static func _point_in_polygon(px: int, py: int, verts: Array[Vector2i]) -> bool:
	var inside := false
	var n := verts.size()
	var j := n - 1
	for i in range(n):
		var vi := verts[i]
		var vj := verts[j]
		if ((vi.y > py) != (vj.y > py)) and \
			(px < (vj.x - vi.x) * (py - vi.y) / (vj.y - vi.y) + vi.x):
			inside = not inside
		j = i
	return inside
