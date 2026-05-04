@tool
class_name ArrowOverlay
extends Control

var graph: ProjectMapper

func _init(g : GraphEdit) -> void:
	graph = g

func _process(_delta: float) -> void: queue_redraw()

func _draw() -> void:
	if not graph: return
	var s = graph.settings
	for conn in graph.get_connection_list():
		if conn["from_port"] == 0 and conn["to_port"] == 0: continue
		var from_node: GraphNode = graph._graph_nodes.get(conn["from_node"])
		var to_node:   GraphNode = graph._graph_nodes.get(conn["to_node"])
		if not from_node or not to_node: continue

		var p0 := (from_node.position_offset + from_node.get_output_port_position(conn["from_port"])) * graph.zoom - graph.scroll_offset
		var p3 := (to_node.position_offset   + to_node.get_input_port_position(conn["to_port"]))    * graph.zoom - graph.scroll_offset
		var midpoint: Vector2; var tangent: Vector2

		if graph.connection_lines_curvature > 0:
			var cp_dist : float = abs(p3.x - p0.x) * graph.connection_lines_curvature
			var p1 := p0 + Vector2(cp_dist, 0); var p2 := p3 - Vector2(cp_dist, 0)
			midpoint = 0.125*p0 + 0.375*p1 + 0.375*p2 + 0.125*p3
			tangent  = (0.75*(p1-p0) + 1.5*(p2-p1) + 0.75*(p3-p2)).normalized()
		else:
			midpoint = (p0 + p3) * 0.5; tangent = (p3 - p0).normalized()
		if tangent == Vector2.ZERO: tangent = Vector2.RIGHT

		var edge_key     = graph._edge_key(conn["from_node"], conn["to_node"])
		var arrow_color  = graph.settings.call_edge_out_color if graph._green_edges.has(edge_key) else graph.settings.call_edge_color
		var arrow_size   = s.arrow_size         * graph.zoom
		var outline_size = s.arrow_outline_size * graph.zoom
		var outline_color: Color = s.arrow_outline_color

		draw_colored_polygon(_arrow_triangle(midpoint, tangent, arrow_size + outline_size), outline_color)
		draw_colored_polygon(_arrow_triangle(midpoint, tangent, arrow_size),                arrow_color)

func _arrow_triangle(center: Vector2, direction: Vector2, size: float) -> PackedVector2Array:
	var points := PackedVector2Array()
	points.append(center + direction * (size * 0.5))
	points.append(center - direction.rotated(0.6)  * (size * 0.6))
	points.append(center - direction.rotated(-0.6) * (size * 0.6))
	return points
