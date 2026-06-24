class_name RunMapDisplay
extends Control
## Renders a RunGraph as a 2D node-and-edge map with visual states.
## Handles click input on selectable nodes.

signal node_clicked(node_id: String)
signal node_hovered(node_id: String)

const COL_SPACING: float = 120.0
const ROW_SPACING: float = 100.0
const NODE_RADIUS: float = 22.0
const LEFT_MARGIN: float = 60.0
const TOP_MARGIN: float = 60.0

const COLOR_VISITED := Color(0.4, 0.4, 0.4)
const COLOR_CURRENT := Color(1.0, 0.85, 0.2)
const COLOR_SELECTABLE := Color(0.3, 0.9, 0.4)
const COLOR_UNREACHABLE := Color(0.25, 0.25, 0.25)
const COLOR_EDGE_DEFAULT := Color(0.35, 0.35, 0.35)
const COLOR_EDGE_VISITED := Color(0.5, 0.5, 0.5)
const COLOR_EDGE_SELECTABLE := Color(0.3, 0.8, 0.3, 0.7)

const KIND_COLORS: Dictionary = {
	"start": Color(0.3, 0.7, 0.3),
	"battle": Color(0.8, 0.25, 0.25),
	"boss": Color(0.6, 0.1, 0.1),
	"event": Color(0.8, 0.7, 0.2),
	"boon": Color(0.9, 0.75, 0.1),
	"hazard": Color(0.6, 0.2, 0.6),
	"shop": Color(0.2, 0.5, 0.8),
	"rest": Color(0.2, 0.7, 0.5),
}

const KIND_LABELS: Dictionary = {
	"start": "S",
	"battle": "B",
	"boss": "!B",
	"event": "?",
	"boon": "*",
	"hazard": "!",
	"shop": "$",
	"rest": "R",
}

var _graph: RunGraph = null
var _visited: Array[String] = []
var _current: String = ""
var _selectable: Array[String] = []
var _node_positions: Dictionary = {}  # node_id -> Vector2
var _node_rects: Dictionary = {}      # node_id -> Rect2
var _hovered_node: String = ""


func set_state(graph: RunGraph, visited: Array[String], current: String,
		selectable: Array[String]) -> void:
	_graph = graph
	_visited = visited
	_current = current
	_selectable = selectable
	if _graph:
		_layout_nodes()
	queue_redraw()


func _layout_nodes() -> void:
	_node_positions.clear()
	_node_rects.clear()
	if _graph == null:
		return
	var max_col: int = 0
	var max_row: int = 0
	for node_id in _graph.nodes:
		var n: Dictionary = _graph.nodes[node_id]
		var col: int = int(n["column"])
		var row: int = int(n["row"])
		max_col = maxi(max_col, col)
		max_row = maxi(max_row, row)
		var x: float = LEFT_MARGIN + col * COL_SPACING
		var y: float = TOP_MARGIN + row * ROW_SPACING
		_node_positions[str(node_id)] = Vector2(x, y)
		_node_rects[str(node_id)] = Rect2(
			x - NODE_RADIUS, y - NODE_RADIUS,
			NODE_RADIUS * 2, NODE_RADIUS * 2)
	custom_minimum_size = Vector2(
		LEFT_MARGIN * 2 + max_col * COL_SPACING,
		TOP_MARGIN * 2 + max_row * ROW_SPACING)


func _draw() -> void:
	if _graph == null:
		return
	# Draw edges
	for edge in _graph.edges:
		var from_id: String = str(edge["from"])
		var to_id: String = str(edge["to"])
		if not _node_positions.has(from_id) or not _node_positions.has(to_id):
			continue
		var from_pos: Vector2 = _node_positions[from_id]
		var to_pos: Vector2 = _node_positions[to_id]
		var color: Color = _edge_color(from_id, to_id)
		draw_line(from_pos, to_pos, color, 2.0)

	# Draw nodes
	for node_id in _graph.nodes:
		var id_str: String = str(node_id)
		if not _node_positions.has(id_str):
			continue
		var pos: Vector2 = _node_positions[id_str]
		var n: Dictionary = _graph.nodes[node_id]
		var kind: String = str(n.get("kind", "battle"))
		_draw_node(pos, id_str, kind)


func _draw_node(pos: Vector2, node_id: String, kind: String) -> void:
	var fill_color: Color = KIND_COLORS.get(kind, Color(0.5, 0.5, 0.5))
	var outline_color: Color = Color.WHITE
	var outline_width: float = 1.5

	if node_id == _current:
		outline_color = COLOR_CURRENT
		outline_width = 3.0
	elif _selectable.has(node_id):
		fill_color = fill_color.lightened(0.2)
		outline_color = COLOR_SELECTABLE
		outline_width = 2.5
		if node_id == _hovered_node:
			fill_color = fill_color.lightened(0.15)
	elif _visited.has(node_id):
		fill_color = fill_color.darkened(0.4)
		outline_color = COLOR_VISITED
	else:
		fill_color = fill_color.darkened(0.5)
		outline_color = COLOR_UNREACHABLE

	# Filled circle
	draw_circle(pos, NODE_RADIUS, fill_color)
	# Outline
	_draw_circle_outline(pos, NODE_RADIUS, outline_color, outline_width)
	# Kind label
	var label: String = KIND_LABELS.get(kind, "?")
	var font: Font = ThemeDB.fallback_font
	var font_size: int = 14
	var text_size: Vector2 = font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
	var text_pos: Vector2 = pos - text_size / 2 + Vector2(0, text_size.y * 0.35)
	draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)


func _draw_circle_outline(center: Vector2, radius: float, color: Color,
		width: float) -> void:
	var points: int = 32
	var prev: Vector2 = center + Vector2(radius, 0)
	for i in range(1, points + 1):
		var angle: float = TAU * i / points
		var next: Vector2 = center + Vector2(cos(angle), sin(angle)) * radius
		draw_line(prev, next, color, width)
		prev = next


func _edge_color(from_id: String, to_id: String) -> Color:
	if from_id == _current and _selectable.has(to_id):
		return COLOR_EDGE_SELECTABLE
	if _visited.has(from_id) and _visited.has(to_id):
		return COLOR_EDGE_VISITED
	return COLOR_EDGE_DEFAULT


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_LEFT:
			var click_pos: Vector2 = mb.position
			for node_id in _node_rects:
				if _selectable.has(node_id) and (_node_rects[node_id] as Rect2).has_point(click_pos):
					node_clicked.emit(node_id)
					return
	elif event is InputEventMouseMotion:
		var motion: InputEventMouseMotion = event as InputEventMouseMotion
		var new_hover: String = ""
		for node_id in _node_rects:
			if _selectable.has(node_id) and (_node_rects[node_id] as Rect2).has_point(motion.position):
				new_hover = node_id
				break
		if new_hover != _hovered_node:
			_hovered_node = new_hover
			if not _hovered_node.is_empty():
				node_hovered.emit(_hovered_node)
			queue_redraw()
