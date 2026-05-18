@tool
class_name ProjectMapper
extends GraphEdit

@export var settings: ProjectMapperSettings:
	set(v):
		if settings and settings.changed.is_connected(_on_settings_changed):
			settings.changed.disconnect(_on_settings_changed)
		settings = v
		if settings:
			settings.changed.connect(_on_settings_changed)

var _graph_nodes : Dictionary
var _class_data : Dictionary
var _has_parent : Dictionary
var _has_child : Dictionary
var _green_edges : Dictionary
var _bordered : Dictionary
var _dropdown_open_nodes : Dictionary

@export var _toolbar_row : VBoxContainer
@export var spacer : Control
@export var toolbar_margin : MarginContainer
@export var _toolbar : HBoxContainer
@export var reorganise_button : Button
@export var expand_button : Button
@export var _search_bar : LineEdit
@export var scan_folder_button : Button

@export_group("Packed Scenes")
@export var section_toggle_packed : PackedScene
@export var item_button_packed : PackedScene
@export var todo_button_packed : PackedScene
@export var list_separator_packed : PackedScene
@export var icon_texture_packed : PackedScene

var _arrow_overlay : ArrowOverlay
var _selected_node : String = ""
var _editor_sync : bool = true
var _straight_lines : bool = false
var _all_expanded : bool = false
var _first_open : bool = true
var _last_script : String = ""
var _scan_folder_path : String = "res://"
var _folder_dialog : Window

func _ready() -> void:
	call_deferred("_apply_line_curve")
	call_deferred("_setup_arrow_overlay")
	visibility_changed.connect(_on_visibility_changed)
	if Engine.is_editor_hint():
		EditorInterface.get_resource_filesystem().filesystem_changed.connect(_on_filesystem_changed)
	call_deferred("_on_visibility_changed")
func _apply_line_curve() -> void:
	connection_lines_curvature = 0.0 if _straight_lines else 0.5

func _setup_arrow_overlay() -> void:
	if _arrow_overlay: _arrow_overlay.queue_free()
	_arrow_overlay = ArrowOverlay.new(self)
	add_child(_arrow_overlay)

func _on_settings_changed() -> void:
	_apply_line_curve()
	_refresh_visuals()
	if not _dropdown_open_nodes.is_empty():
		_rebuild_call_edges()
	_apply_layout()
	if not is_inside_tree():
		return
	await get_tree().process_frame
	if not is_inside_tree():
		return
	_zoom_to_fit()
	queue_redraw()

func _refresh_visuals() -> void:
	if _graph_nodes.is_empty():
		return

	for class_name_ in _graph_nodes:
		var graph_node : GraphNode = _graph_nodes[class_name_]
		var data : Dictionary = _class_data.get(class_name_)
		var is_builtin = data.get("builtin")
		var is_out_of_scope = data.get("out_of_scope", false)

		if is_builtin:
			graph_node.modulate = settings.builtin_modulate
		else:
			var dimmed := graph_node.modulate.a < 0.5
			graph_node.self_modulate = settings.out_of_scope_modulate if is_out_of_scope else _autoload_color(class_name_)
			graph_node.modulate = Color(1, 1, 1, settings.out_of_scope_modulate.a) if is_out_of_scope else Color.WHITE
			if dimmed: graph_node.modulate.a = 0.15
			if _dropdown_open_nodes.has(class_name_):
				_apply_border(graph_node, _autoload_color(class_name_))
			elif _bordered.get(class_name_) == "blue":
				_apply_blue_border(graph_node)
			elif _bordered.get(class_name_) == "green":
				_apply_green_border(graph_node)
			else:
				_remove_border(graph_node)

		_refresh_node_font_colors(graph_node, class_name_, data)
		
		if not _bordered.has(class_name_):
			var slot_color := _autoload_color(class_name_)
			_graph_nodes[class_name_].set_slot(0,
				_has_parent.has(class_name_), 0, slot_color,
				_has_child.has(class_name_), 0, slot_color)

	_refresh_call_slots()

	if _selected_node != "" and _graph_nodes.has(_selected_node):
		_on_node_selected(_graph_nodes[_selected_node])

func _section_color(label: String) -> Color:
	match label:
		"Scenes": return settings.font_scene
		"Signals": return settings.font_signal
		"Variables": return settings.font_variables_header
		"Functions": return settings.font_functions_header
		"Built-in Functions": return settings.font_builtin_functions_header
		"Static Functions": return settings.font_static_functions_header
		"Overrides": return settings.font_override_functions_header
		"TODOs": return settings.font_todo_header
	return Color.WHITE

func _refresh_node_font_colors(graph_node: GraphNode, class_name_: String, data: Dictionary) -> void:
	var overrides : Dictionary = _get_overrides(class_name_)
	var missing_super : Dictionary = {}
	for f in data.get("functions", []):
		if overrides.has(f["name"]) and not f.get("calls_super", false):
			missing_super[f["name"]] = true

	for child in graph_node.get_children():
		if child is Button:
			child.add_theme_color_override("font_hover_color", settings.font_hover)

	for dd in graph_node.get_meta("dropdowns", []):
		var toggle : Button = dd["toggle"]
		var section_col := _section_color(dd["label"])
		toggle.add_theme_color_override("font_color", section_col)
		for item in dd["items"]:
			if not item is Button: continue
			var item_type : String = item.get_meta("item_type", "")
			if item_type == "signal":
				var emitted : bool = item.get_meta("signal_emitted", false)
				item.add_theme_color_override("font_color", settings.font_signal if emitted else settings.font_signal_unemitted)
			elif item_type == "function":
				var fname : String = item.get_meta("func_name", "")
				item.add_theme_color_override("font_color", settings.font_missing_super if missing_super.has(fname) else section_col)
			else:
				item.add_theme_color_override("font_color", section_col)

func _on_expand_button_pressed():
	_all_expanded = !_all_expanded
	expand_button.text = "Collapse All" if _all_expanded else "Expand All"
	_set_all_dropdowns(_all_expanded)
	
func _on_straight_lines_checked(on: bool):
	_straight_lines = on
	_apply_line_curve()

func _on_sync_selection_changed(on: bool):
	_editor_sync = on

func _on_visibility_changed() -> void:
	if not is_visible_in_tree(): return
	if _first_open:
		_first_open = false
		_reorganise()

func _on_filesystem_changed() -> void:
	if is_visible_in_tree(): _reorganise()

func _process(_delta: float) -> void:
	if not _editor_sync or not Engine.is_editor_hint(): return
	var current_script : Script = EditorInterface.get_script_editor().get_current_script()
	if not current_script: return
	if current_script.resource_path == _last_script: return
	_last_script = current_script.resource_path
	for class_name_ in _class_data:
		if _class_data[class_name_].get("path", "") == _last_script:
			_select_node(class_name_)
			break

func _select_node(class_name_: String) -> void:
	if not _graph_nodes.has(class_name_): return
	for node in _graph_nodes.values(): node.selected = false
	var target_node : GraphNode = _graph_nodes[class_name_]
	target_node.selected = true
	scroll_offset = (target_node.position_offset + target_node.size / 2.0) * zoom - size / 2.0

func _on_scan_folder_pressed() -> void:
	if _folder_dialog and is_instance_valid(_folder_dialog):
		_folder_dialog.queue_free()

	var dialog := ConfirmationDialog.new()
	_folder_dialog = dialog
	dialog.title = "Select Folder to Scan"
	dialog.min_size = Vector2i(380, 480)

	var tree := Tree.new()
	tree.custom_minimum_size = Vector2(0, 400)
	dialog.add_child(tree)

	var folder_icon := EditorInterface.get_base_control().get_theme_icon("Folder", "EditorIcons")

	var root := tree.create_item()
	root.set_icon(0, folder_icon)
	root.set_text(0, "res:// (entire project)")
	root.set_metadata(0, "res://")
	_populate_folder_tree(tree, root, "res://", folder_icon)

	dialog.confirmed.connect(func():
		var selected := tree.get_selected()
		if selected:
			_on_folder_selected(selected.get_metadata(0))
		dialog.queue_free()
		_folder_dialog = null
	)
	dialog.canceled.connect(func():
		dialog.queue_free()
		_folder_dialog = null
	)
	EditorInterface.get_base_control().add_child(dialog)
	dialog.popup_centered()

func _populate_folder_tree(tree: Tree, parent_item: TreeItem, path: String, folder_icon: Texture2D) -> void:
	var dir := DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var subdirs: Array[String] = []
	var fname := dir.get_next()
	while fname != "":
		if not fname.begins_with(".") and dir.current_is_dir():
			var full := path.path_join(fname)
			if not full.begins_with("res://addons"):
				subdirs.append(fname)
		fname = dir.get_next()
	subdirs.sort()
	for d in subdirs:
		var full := path.path_join(d)
		var item := tree.create_item(parent_item)
		item.set_icon(0, folder_icon)
		item.set_text(0, d)
		item.set_metadata(0, full)
		_populate_folder_tree(tree, item, full, folder_icon)

func _on_folder_selected(path: String) -> void:
	_scan_folder_path = path
	var display := path.trim_prefix("res://").trim_suffix("/")
	scan_folder_button.text = "Scanning: /%s" % display if display != "" else "Scan Folder"
	if _folder_dialog and is_instance_valid(_folder_dialog):
		_folder_dialog.queue_free()
		_folder_dialog = null
	_reorganise()

func _reorganise() -> void:
	_clear_graph()
	_class_data = CodebaseParser.scan_project(_scan_folder_path)
	_create_class_nodes()
	if _toolbar_row: _toolbar_row.move_to_front() 
	_draw_inheritance_connections()
	_apply_layout()
	await get_tree().process_frame
	_zoom_to_fit()
	if _all_expanded: _set_all_dropdowns(true)
	if _search_bar and _search_bar.text != "": _apply_search(_search_bar.text)
	if not node_selected.is_connected(_on_node_selected):
		node_selected.connect(_on_node_selected)
	if not node_deselected.is_connected(_on_node_deselected):
		node_deselected.connect(_on_node_deselected)


func _clear_graph() -> void:
	clear_connections()
	for child in get_children():
		if child is GraphElement: child.free()
	_graph_nodes = {}
	_class_data = {}
	_has_parent = {}
	_has_child = {}
	_green_edges = {}
	_bordered = {}
	_dropdown_open_nodes = {}

func _set_all_dropdowns(expanded: bool) -> void:
	for graph_node in _graph_nodes.values():
		for dropdown in graph_node.get_meta("dropdowns", []):
			for item in dropdown["items"]: item.visible = expanded
			dropdown["toggle"].text = "%s %s (%d)" % ["▼" if expanded else "▶", dropdown["label"], dropdown["count"]]
		if not expanded: graph_node.reset_size()

	if expanded:
		for class_name_ in _graph_nodes:
			var gn: GraphNode = _graph_nodes[class_name_]
			var has_func_dd := false
			for dd in gn.get_meta("dropdowns", []):
				if dd["label"] != "Variables" and dd["label"] != "TODOs" and dd["label"] != "Signals" and dd["label"] != "Scenes" and dd["items"].size() > 0:
					has_func_dd = true
					break
			if has_func_dd:
				_dropdown_open_nodes[class_name_] = true
				_apply_border(gn, _autoload_color(class_name_))
	else:
		_dropdown_open_nodes.clear()
		for class_name_ in _graph_nodes:
			_remove_border(_graph_nodes[class_name_])

	_rebuild_call_edges()
	_apply_layout()
	_zoom_to_fit()

func _apply_search(query: String) -> void:
	for class_name_ in _graph_nodes:
		var base_alpha := settings.builtin_modulate.a if _class_data.get(class_name_, {}).get("builtin", false) else 1.0
		_graph_nodes[class_name_].modulate.a = base_alpha if _class_matches(class_name_, query) else base_alpha * 0.15

func _class_matches(class_name_: String, query: String) -> bool:
	if query == "": return true
	var query_lower := query.to_lower()
	if class_name_.to_lower().contains(query_lower): return true
	for variable in _class_data.get(class_name_, {}).get("variables", []):
		if (variable["name"] as String).to_lower().contains(query_lower): return true
	for signal_ in _class_data.get(class_name_, {}).get("signals", []):
		if (signal_["name"] as String).to_lower().contains(query_lower): return true
	for function_ in _class_data.get(class_name_, {}).get("functions", []):
		if (function_["name"] as String).to_lower().contains(query_lower): return true
	return false

func _zoom_to_fit() -> void:
	if _graph_nodes.is_empty(): return
	var min_pos := Vector2(INF, INF)
	var max_pos := Vector2(-INF, -INF)
	for node in _graph_nodes.values():
		min_pos = min_pos.min(node.position_offset)
		max_pos = max_pos.max(node.position_offset + node.size)
	var content_size := max_pos - min_pos
	if content_size.x <= 0 or content_size.y <= 0: return
	const PADDING := 80.0
	var toolbar_height := get_menu_hbox().size.y
	var available_size := size - Vector2(PADDING * 2, PADDING * 2 + toolbar_height)
	zoom = clamp(min(available_size.x / content_size.x, available_size.y / content_size.y), zoom_min, 1.0)
	scroll_offset = ((min_pos + max_pos) / 2.0) * zoom - size / 2.0

func _create_class_nodes() -> void:
	var child_counts : Dictionary = {}
	for class_name_ in _class_data:
		var parent_name : String = _class_data[class_name_]["extends"]
		if _class_data.has(parent_name):
			child_counts[parent_name] = child_counts.get(parent_name, 0) + 1

	var generation_map : Dictionary = {}
	var gen_queue : Array = []
	for class_name_ in _class_data:
		if not _class_data.has(_class_data[class_name_]["extends"]):
			gen_queue.append([class_name_, 0])
	while not gen_queue.is_empty():
		var item : Array = gen_queue.pop_front()
		var cn : String = item[0]
		var gen : int = item[1]
		if generation_map.has(cn): continue
		generation_map[cn] = gen
		for other in _class_data:
			if _class_data[other]["extends"] == cn:
				gen_queue.append([other, gen + 1])

	for class_name_ in _class_data:
		var data : Dictionary = _class_data[class_name_]
		var autoload_name: String = data.get("autoload_name", "")
		var graph_node := _make_node(class_name_, data["path"],
			data.get("scenes", []), data.get("variables", []), data.get("signals", []), data.get("functions", []),
			_get_overrides(class_name_), data.get("builtin", false),
			child_counts.get(class_name_, 0), autoload_name,
			generation_map.get(class_name_, 0), data.get("out_of_scope", false))
		add_child(graph_node)
		_graph_nodes[class_name_] = graph_node
		if autoload_name != "":
			graph_node.self_modulate = settings.autoload_color

func _draw_inheritance_connections() -> void:
	clear_connections()
	_has_parent.clear()
	_has_child.clear()
	
	for class_name_ in _class_data:
		var parent_name : String = _class_data[class_name_]["extends"]
		if _graph_nodes.has(parent_name):
			_has_parent[class_name_] = true
			_has_child[parent_name] = true
			
			connect_node(parent_name, 0, class_name_, 0)
	for class_name_ in _graph_nodes:
		var slot_color := _autoload_color(class_name_)
		_graph_nodes[class_name_].set_slot(0,
			_has_parent.has(class_name_), 0, slot_color,
			_has_child.has(class_name_), 0, slot_color)

func _edge_key(from_class: String, to_class: String) -> String:
	return from_class + "::" + to_class

func _slot_to_child_port(graph_node: GraphNode, slot_idx: int, left_or_right: bool) -> int:
	if slot_idx < 0 or slot_idx >= graph_node.get_child_count(): return -1
	
	var port := 0
	for i in range(slot_idx):
		if (graph_node.is_slot_enabled_left(i) if left_or_right else graph_node.is_slot_enabled_right(i)):
			port += 1

	return port

func _rebuild_call_edges() -> void:
	# Remove all non-inheritance connections
	for conn in get_connection_list().duplicate():
		var is_inheritance = (conn["from_port"] == 0 and conn["to_port"] == 0
			and _has_child.has(conn["from_node"])
			and _class_data.get(conn["to_node"], {}).get("extends", "") == conn["from_node"])
		if not is_inheritance:
			disconnect_node(conn["from_node"], conn["from_port"], conn["to_node"], conn["to_port"])

	_green_edges.clear()
	_bordered.clear()

	# Reset extra slots (1+) and borders on all nodes
	for class_name_ in _graph_nodes:
		var gn: GraphNode = _graph_nodes[class_name_]
		for i in range(1, gn.get_child_count()):
			gn.set_slot(i, false, 0, Color.WHITE, false, 0, Color.WHITE)
		if _dropdown_open_nodes.has(class_name_):
			_apply_border(gn, _autoload_color(class_name_))
		else:
			_remove_border(gn)

	if _dropdown_open_nodes.is_empty():
		_refresh_call_slots()
		return

	# Gather visible function set for each open node
	var open_func_sets: Dictionary = {}
	for target_class in _dropdown_open_nodes:
		if not _graph_nodes.has(target_class): continue
		var gn: GraphNode = _graph_nodes[target_class]
		var combined: Array = []
		for dd in gn.get_meta("dropdowns", []):
			if dd["label"] == "Variables" or dd["label"] == "TODOs" or dd["label"] == "Signals" or dd["label"] == "Scenes": continue
			if dd["items"].size() > 0 and dd["items"][0].visible:
				combined += dd.get("funcs", [])
		open_func_sets[target_class] = combined

	# Track which nodes already have a blue right-port assigned (and at which slot)
	var node_blue_out_slot: Dictionary = {}

	# Phase 1: Incoming blue edges — callers → open target function slots
	for target_class in open_func_sets:
		var func_arr: Array = open_func_sets[target_class]
		if func_arr.is_empty(): continue
		var target_node: GraphNode = _graph_nodes[target_class]
		var target_slot_map: Dictionary = target_node.get_meta("func_slot_map", {})

		var method_names: Dictionary = {}
		for f in func_arr: method_names[f["name"]] = true

		for caller_class in _class_data:
			if caller_class == target_class or not _graph_nodes.has(caller_class): continue
			var called_methods: Dictionary = {}
			for call in _class_data[caller_class].get("outbound_calls", []):
				if call["target"] == target_class and method_names.has(call["method"]):
					called_methods[call["method"]] = true
			if called_methods.is_empty(): continue

			# If the caller also has an open dropdown, Phase 2 will draw the connection
			# from its per-function green slot (gradient), so skip the blue port here.
			if open_func_sets.has(caller_class): continue

			var caller_node: GraphNode = _graph_nodes[caller_class]
			# Assign slot 1 for blue outgoing on this caller (shared across all targets it calls)
			var blue_slot: int = node_blue_out_slot.get(caller_class, 1)
			node_blue_out_slot[caller_class] = blue_slot
			caller_node.set_slot(blue_slot,
				caller_node.is_slot_enabled_left(blue_slot), 2, settings.call_edge_color,
				true, 2, settings.call_edge_color)
			var caller_out_port := _slot_to_child_port(caller_node, blue_slot, false)

			var our_min_slot := INF
			for f in func_arr:
				var s: int = target_slot_map.get(f["name"], -1)
				if s >= 0 and s < our_min_slot: our_min_slot = s

			var target_children := target_node.get_children()
			var slot_offset := 0
			for dd in target_node.get_meta("dropdowns", []):
				if dd["items"].is_empty() or dd["items"][0].visible: continue
				var dd_first_idx := target_children.find(dd["items"][0])
				if dd_first_idx >= 0 and dd_first_idx < our_min_slot:
					slot_offset += dd["items"].size()

			var conns_snap := get_connection_list()
			for f in func_arr:
				if not called_methods.has(f["name"]): continue
				var tslot: int = target_slot_map.get(f["name"], -1) - slot_offset
				if tslot < 0: continue
				target_node.set_slot(tslot, true, 2, settings.call_edge_color, false, 0, Color.WHITE)
				var to_port := _slot_to_child_port(target_node, tslot, true)
				if to_port < 0 or caller_out_port < 0: continue
				var already := false
				for conn in conns_snap:
					if conn["from_node"] == caller_class and conn["to_node"] == target_class \
							and conn["to_port"] == to_port and conn["from_port"] == caller_out_port:
						already = true
						break
				if not already:
					connect_node(caller_class, caller_out_port, target_class, to_port)

			if not _dropdown_open_nodes.has(caller_class):
				_apply_blue_border(caller_node)

	# Phase 2: Outgoing green edges — open nodes → callees
	# Each right-side green slot is placed at the height of the function making the call,
	# mirroring how Phase 1 places blue input slots at the height of the called function.
	for target_class in open_func_sets:
		var target_node: GraphNode = _graph_nodes[target_class]
		var target_slot_map: Dictionary = target_node.get_meta("func_slot_map", {})

		# Compute our_slot_min once across all visible outbound calls for this node,
		# mirroring how Phase 1 computes our_min_slot across all target functions before
		# the per-function loop. This gives a single consistent slot_offset for all calls.
		var our_slot_min := INF
		for c in _class_data[target_class].get("outbound_calls", []):
			if c["target"] == target_class or not _graph_nodes.has(c["target"]): continue
			var s: int = target_slot_map.get(c.get("caller", ""), -1)
			if s < 0: continue
			var _c := target_node.get_child(s) as Control
			if not _c or not _c.visible: continue
			if s < our_slot_min: our_slot_min = s

		var target_children := target_node.get_children()
		var slot_offset := 0
		if our_slot_min < INF:
			for dd in target_node.get_meta("dropdowns", []):
				if dd["items"].is_empty() or dd["items"][0].visible: continue
				var dd_first_idx := target_children.find(dd["items"][0])
				if dd_first_idx >= 0 and dd_first_idx < our_slot_min:
					slot_offset += dd["items"].size()

		var conns_snap := get_connection_list()
		for call in _class_data[target_class].get("outbound_calls", []):
			var callee_class: String = call["target"]
			if callee_class == target_class or not _graph_nodes.has(callee_class): continue
			var callee_node: GraphNode = _graph_nodes[callee_class]
			var callee_children := callee_node.get_children()
			var callee_slot_map: Dictionary = callee_node.get_meta("func_slot_map", {})

			# Find the slot of the function in the open node that makes this call
			var raw_caller_slot: int = target_slot_map.get(call.get("caller", ""), -1)
			if raw_caller_slot < 0: continue
			var caller_child := target_node.get_child(raw_caller_slot) as Control
			if not caller_child or not caller_child.visible: continue

			# Use green_slot (adjusted by the shared offset) for set_slot and port counting,
			# exactly mirroring how Phase 1 uses tslot with _slot_to_in_port. Port is counted
			# without a visibility check so it stays consistent with hidden-child slots.
			var green_slot := raw_caller_slot - slot_offset
			if green_slot < 0: continue

			target_node.set_slot(green_slot,
				target_node.is_slot_enabled_left(green_slot), 2, settings.call_edge_color,
				true, 3, settings.call_edge_out_color)
			target_node.update_minimum_size()
			var target_out_port := 0
			for i in range(green_slot):
				if target_node.is_slot_enabled_right(i):
					target_out_port += 1

			var cslot: int = -1
			if _dropdown_open_nodes.has(callee_class) and callee_slot_map.has(call["method"]):
				var candidate: int = callee_slot_map[call["method"]]
				if callee_node.get_child(candidate).visible:
					cslot = candidate
				else:
					# Function is in a closed dropdown; anchor to that section's toggle instead
					for dd in callee_node.get_meta("dropdowns", []):
						if dd.get("label") == "Variables" or dd.get("label") == "TODOs": continue
						for f in dd.get("funcs", []):
							if f["name"] == call["method"]:
								cslot = callee_children.find(dd["toggle"])
								break
						if cslot >= 0: break

			if cslot >= 0:
				var callee_min_slot := cslot
				var callee_slot_offset := 0
				for dd in callee_node.get_meta("dropdowns", []):
					if dd["items"].is_empty() or dd["items"][0].visible: continue
					var dd_first_idx := callee_children.find(dd["items"][0])
					if dd_first_idx >= 0 and dd_first_idx < callee_min_slot:
						callee_slot_offset += dd["items"].size()
				cslot -= callee_slot_offset
				# Blue input (type 2) on the open callee creates a green→blue gradient
				# with the green output (type 3) on the open caller's side.
				# Preserve any right port already placed on this slot by a prior Phase 2 iteration.
				callee_node.set_slot(cslot, true, 2, settings.call_edge_color,
					callee_node.is_slot_enabled_right(cslot),
					callee_node.get_slot_type_right(cslot),
					callee_node.get_slot_color_right(cslot))
			else:
				callee_node.set_slot(1, true, 3, settings.call_edge_out_color,
					callee_node.is_slot_enabled_right(1), 2, settings.call_edge_color)

			callee_node.update_minimum_size()
			var callee_in_slot := cslot if cslot >= 0 else 1
			var to_port := _slot_to_child_port(callee_node, callee_in_slot, true)
			if to_port < 0 or target_out_port < 0: continue
			var already := false
			for conn in conns_snap:
				if conn["from_node"] == target_class and conn["to_node"] == callee_class \
						and conn["from_port"] == target_out_port and conn["to_port"] == to_port:
					already = true
					break
			if not already:
				connect_node(target_class, target_out_port, callee_class, to_port)

			_green_edges[_edge_key(target_class, callee_class)] = true
			if not _dropdown_open_nodes.has(callee_class):
				_apply_green_border(callee_node)

func _refresh_call_slots() -> void:
	var connections := get_connection_list()
	var needs_input : Dictionary = {}
	var needs_output : Dictionary = {}
	var from_map : Dictionary = {}
	var to_map : Dictionary = {}
	for conn in connections:
		var is_inheritance = conn["to_port"] == 0 and _has_parent.has(conn["to_node"])
		if not is_inheritance:
			needs_input[conn["to_node"]] = true
			needs_output[conn["from_node"]] = true
		var fn: String = conn["from_node"]
		if not from_map.has(fn): from_map[fn] = []
		from_map[fn].append(conn)
		var tn: String = conn["to_node"]
		if not to_map.has(tn): to_map[tn] = []
		to_map[tn].append(conn)

	for class_name_ in _graph_nodes:
		var graph_node : GraphNode = _graph_nodes[class_name_]
		var has_input := needs_input.get(class_name_, false)
		var has_output := needs_output.get(class_name_, false)
		if not has_input and not has_output:
			graph_node.set_slot(1, false, 0, Color.WHITE, false, 0, Color.WHITE)
			graph_node.set_slot(2, graph_node.is_slot_enabled_left(2), 0, Color.WHITE, false, 0, Color.WHITE)
			if not _dropdown_open_nodes.has(class_name_):
				if _bordered.has(class_name_):
					_remove_border(graph_node)
					_bordered.erase(class_name_)
			continue
		var has_blue_outbound : bool = false
		var has_green_outbound : bool = false
		var has_green_inbound : bool = false
		for conn in from_map.get(class_name_, []):
			var is_child_inherit = conn["from_port"] == 0 and conn["to_port"] == 0 and _has_child.has(class_name_)
			if not is_child_inherit:
				if _green_edges.has(_edge_key(class_name_, conn["to_node"])): has_green_outbound = true
				else: has_blue_outbound = true
		for conn in to_map.get(class_name_, []):
			if conn["to_port"] != 0:
				if _green_edges.has(_edge_key(conn["from_node"], class_name_)): has_green_inbound = true
		var in_type := 3 if has_green_inbound else 2
		var in_color := settings.call_edge_out_color if has_green_inbound else settings.call_edge_color
		var has_outbound := has_blue_outbound or has_green_outbound
		var out_type := 2 if has_blue_outbound else 3
		var out_color := settings.call_edge_color if has_blue_outbound else settings.call_edge_out_color
		graph_node.set_slot(1, has_input, in_type, in_color, has_outbound, out_type, out_color)
		graph_node.set_slot(2, graph_node.is_slot_enabled_left(2), 0, Color.WHITE,
			has_blue_outbound and has_green_outbound, 3, settings.call_edge_out_color)
		if not _dropdown_open_nodes.has(class_name_):
			if has_blue_outbound or has_green_outbound: _apply_blue_border(graph_node)
			elif has_green_inbound: _apply_green_border(graph_node)
			elif _bordered.has(class_name_):
				_remove_border(graph_node)
				_bordered.erase(class_name_)

func _on_node_selected(node: Node) -> void:
	_selected_node = node.name
	_clear_highlights()
	_bring_to_front(node as GraphNode)
	var class_name_ : String = node.name
	var parent_name : String = _class_data.get(class_name_, {}).get("extends", "")
	while _graph_nodes.has(parent_name):
		var parent_node : GraphNode = _graph_nodes[parent_name]
		var child_node : GraphNode = _graph_nodes[class_name_]
		_apply_border(parent_node, settings.highlight_pink_color)
		parent_node.set_slot(0, true, 0, settings.highlight_pink_color, true, 0, settings.highlight_pink_color)
		child_node.set_slot(0, true, 0, settings.highlight_pink_color, _has_child.has(class_name_), 0, settings.highlight_pink_color)
		class_name_ = parent_name
		parent_name = _class_data.get(class_name_, {}).get("extends", "") as String

func _on_node_deselected(_node: Node) -> void:
	_selected_node = ""
	_clear_highlights()

func _bring_to_front(graph_node: GraphNode) -> void:
	graph_node.move_to_front()
	if _toolbar_row: _toolbar_row.move_to_front()

func _clear_highlights() -> void:
	for class_name_ in _graph_nodes:
		var graph_node : GraphNode = _graph_nodes[class_name_]
		_remove_border(graph_node)
		var slot_color := _autoload_color(class_name_)
		graph_node.set_slot(0,
			_has_parent.has(class_name_), 0, slot_color,
			_has_child.has(class_name_), 0, slot_color)

func _apply_border(graph_node: GraphNode, border_color: Color) -> void:
	for theme_type in ["panel", "titlebar", "panel_selected", "titlebar_selected"]:
		var base = theme_type.replace("_selected", "")
		var sb : StyleBoxFlat = graph_node.get_theme_stylebox(base).duplicate()
		sb.border_color = border_color
		if base == "titlebar":
			sb.set_border_width(SIDE_TOP, 2)
			sb.set_border_width(SIDE_LEFT, 2)
			sb.set_border_width(SIDE_RIGHT, 2)
			sb.set_border_width(SIDE_BOTTOM, 0)
		else:
			sb.set_border_width(SIDE_TOP, 0)
			sb.set_border_width(SIDE_LEFT, 2)
			sb.set_border_width(SIDE_RIGHT, 2)
			sb.set_border_width(SIDE_BOTTOM, 2)
		graph_node.add_theme_stylebox_override(theme_type, sb)

func _remove_border(graph_node: GraphNode) -> void:
	for t in ["panel", "titlebar", "panel_selected", "titlebar_selected"]:
		graph_node.remove_theme_stylebox_override(t)

func _apply_blue_border(graph_node: GraphNode) -> void: 
	_apply_border(graph_node, settings.call_edge_color)
	_bordered[graph_node.name] = "blue"
	
func _apply_green_border(graph_node: GraphNode) -> void: 
	_apply_border(graph_node, settings.call_edge_out_color)
	_bordered[graph_node.name] = "green"

func _autoload_color(class_name_: String) -> Color:
	return settings.autoload_color if _class_data.get(class_name_, {}).has("autoload_name") else Color.WHITE

func _apply_layout() -> void:
	if _class_data.is_empty(): return
	var sort_autoloads_first := func(a: String, b: String) -> bool:
		var a_auto = _class_data[a].has("autoload_name")
		var b_auto = _class_data[b].has("autoload_name")
		if a_auto != b_auto: return a_auto
		return a < b

	var children_map : Dictionary = {}
	var root_classes : Array = []
	for class_name_ in _class_data:
		var parent_name : String = _class_data[class_name_]["extends"]
		if parent_name == "" or not _graph_nodes.has(parent_name):
			root_classes.append(class_name_)
		else:
			if not children_map.has(parent_name): children_map[parent_name] = []
			children_map[parent_name].append(class_name_)

	var layer_map : Dictionary = {}
	var bfs_queue : Array = []
	for root in root_classes: bfs_queue.append([root, 0])
	while bfs_queue.size() > 0:
		var item : Array = bfs_queue.pop_front()
		var class_name_: String = item[0]
		var layer : int = item[1]
		if layer_map.has(class_name_): continue
		layer_map[class_name_] = layer
		for child in children_map.get(class_name_, []): bfs_queue.append([child, layer + 1])

	var nodes_by_layer := {}
	for class_name_ in layer_map:
		var layer : int = layer_map[class_name_]
		if not nodes_by_layer.has(layer): nodes_by_layer[layer] = []
		nodes_by_layer[layer].append(class_name_)
	if not nodes_by_layer.has(0): return
	nodes_by_layer[0].sort_custom(sort_autoloads_first)

	var node_height_with_sep := func(class_name_: String) -> float:
		return _graph_nodes[class_name_].size.y + settings.v_sep if _graph_nodes.has(class_name_) else float(settings.v_sep)

	var node_y_positions := {}
	var layer_right_edge := {}
	var layer0_nodes: Array = nodes_by_layer[0]
	var layer0_total_height := 0.0
	for class_name_ in layer0_nodes: layer0_total_height += node_height_with_sep.call(class_name_)
	var max_width := 0.0
	var cursor_y := -layer0_total_height / 2.0
	for class_name_ in layer0_nodes:
		node_y_positions[class_name_] = cursor_y
		if _graph_nodes.has(class_name_):
			_graph_nodes[class_name_].position_offset = Vector2(0, cursor_y)
			max_width = max(max_width, _graph_nodes[class_name_].size.x)
		cursor_y += node_height_with_sep.call(class_name_)
	layer_right_edge[0] = max_width

	for layer in range(1, nodes_by_layer.keys().max() + 1):
		if not nodes_by_layer.has(layer): continue
		var x_offset : float = layer_right_edge.get(layer - 1, 0.0) + settings.h_sep
		var nodes_by_parent : Dictionary = {}
		var parent_order : Array = []
		for class_name_ in nodes_by_layer[layer]:
			var parent_name : String = _class_data[class_name_]["extends"]
			if not nodes_by_parent.has(parent_name):
				nodes_by_parent[parent_name] = []
				parent_order.append(parent_name)
			nodes_by_parent[parent_name].append(class_name_)
		parent_order.sort_custom(func(a, b): return node_y_positions.get(a, 0.0) < node_y_positions.get(b, 0.0))
		var layer_max_width : float = 0.0
		var next_min_y : float = -INF
		for parent_name in parent_order:
			var group : Array = nodes_by_parent[parent_name]
			group.sort_custom(sort_autoloads_first)
			var group_height : float = 0.0
			for class_name_ in group: group_height += node_height_with_sep.call(class_name_)
			var start_y : float = max(node_y_positions.get(parent_name, 0.0) - group_height / 2.0 + node_height_with_sep.call(group[0]) / 2.0, next_min_y)
			var slot_cursor : float = start_y
			for class_name_ in group:
				node_y_positions[class_name_] = slot_cursor
				if _graph_nodes.has(class_name_):
					_graph_nodes[class_name_].position_offset = Vector2(x_offset, slot_cursor)
					layer_max_width = max(layer_max_width, _graph_nodes[class_name_].size.x)
				slot_cursor += node_height_with_sep.call(class_name_)
			next_min_y = start_y + group_height
		layer_right_edge[layer] = x_offset + layer_max_width

func _get_overrides(class_name_: String) -> Dictionary:
	var own_functions : Dictionary = {}
	for func_ in _class_data[class_name_].get("functions", []): own_functions[func_["name"]] = true
	var overrides : Dictionary = {}
	var parent_name : String = _class_data[class_name_]["extends"]
	while _class_data.has(parent_name):
		for func_ in _class_data[parent_name].get("functions", []):
			if own_functions.has(func_["name"]): overrides[func_["name"]] = true
		parent_name = _class_data[parent_name]["extends"]
	if ClassDB.class_exists(parent_name):
		for method in ClassDB.class_get_method_list(parent_name, false):
			if own_functions.has(method["name"]): overrides[method["name"]] = true
	return overrides

func _make_separator_line() -> HSeparator:
	return list_separator_packed.instantiate() as HSeparator

func _make_section_toggle(section_label: String, item_count: int) -> Button:
	var toggle := section_toggle_packed.instantiate()
	toggle.text = "▶ %s (%d)" % [section_label, item_count]
	toggle.add_theme_font_override("font", settings.bold_font)
	return toggle

func _make_node(class_name_: String, script_path: String, scenes: Array, variables: Array, signals: Array, functions: Array,
		overrides: Dictionary, builtin: bool = false, child_count: int = 0, autoload_name: String = "",
		generation: int = 0, out_of_scope: bool = false) -> GraphNode:
	var graph_node := GraphNode.new()
	var display_name := autoload_name if autoload_name != "" else class_name_
	graph_node.title = display_name
	graph_node.name = class_name_
	graph_node.set_meta("dropdowns", [])
	graph_node.set_meta("func_slot_map", {})

	var titlebar_hbox := graph_node.get_titlebar_hbox()
	var title_label := titlebar_hbox.get_child(0) as Label
	if title_label:
		title_label.mouse_filter = Control.MOUSE_FILTER_PASS
		title_label.tooltip_text = "This class is not present in the scanned folder" if out_of_scope else "Generation %d" % generation
	var icon_class := class_name_
	if not ClassDB.class_exists(icon_class):
		if script_path != "":
			var icon_script := load(script_path) as Script
			if icon_script:
				var native := icon_script.get_instance_base_type()
				if native != "":
					icon_class = native
		if not ClassDB.class_exists(icon_class):
			var visited := {}
			while icon_class != "" and not ClassDB.class_exists(icon_class) and not visited.has(icon_class):
				visited[icon_class] = true
				icon_class = _class_data.get(icon_class, {}).get("extends", "")
	if not ClassDB.class_exists(icon_class):
		icon_class = "Script"
	var icon_tex := EditorInterface.get_base_control().get_theme_icon(icon_class, "EditorIcons")
	if icon_tex:
		var icon_rect = icon_texture_packed.instantiate() as TextureRect
		icon_rect.texture = icon_tex
		titlebar_hbox.add_child(icon_rect)
		titlebar_hbox.move_child(icon_rect, 0)
	if child_count > 0:
		var count_label := Label.new()
		count_label.text = "(%d %s)" % [child_count, "Child" if child_count == 1 else "Children"]
		count_label.mouse_filter = Control.MOUSE_FILTER_PASS
		count_label.add_theme_font_size_override("font_size", title_label.get_theme_font_size("font_size"))
		titlebar_hbox.add_child(count_label)

	graph_node.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton or event is InputEventMouseMotion: _bring_to_front(graph_node))

	if builtin:
		graph_node.modulate = settings.builtin_modulate
	elif out_of_scope:
		graph_node.self_modulate = settings.out_of_scope_modulate
		graph_node.modulate = Color(1, 1, 1, settings.out_of_scope_modulate.a)

	var file_button := Button.new()
	file_button.text = "../%s/%s" % [script_path.get_base_dir().get_file(), script_path.get_file()]
	file_button.flat = true
	file_button.pressed.connect(func(): _open_script(script_path, 0))
	graph_node.add_child(file_button)

	var func_slot_map : Dictionary = graph_node.get_meta("func_slot_map")

	# Adds a section with items as direct children of graph_node (not VBoxContainer),
	# so each function button gets its own GraphNode slot for per-function port positioning.
	var add_items_direct := func(items_out: Array, item_arr: Array, make_btn: Callable, track_slots: bool) -> void:
		var sep0 := _make_separator_line() 
		sep0.visible = false
		graph_node.add_child(sep0)
		items_out.append(sep0)
		
		for i in item_arr.size():
			if i > 0:
				var sep := _make_separator_line()
				sep.visible = false
				graph_node.add_child(sep)
				items_out.append(sep)
			var btn : Button = make_btn.call(item_arr[i])
			btn.set_meta("section_item", true)
			btn.visible = false
			graph_node.add_child(btn)
			items_out.append(btn)
			if track_slots:
				func_slot_map[item_arr[i]["name"]] = graph_node.get_child_count() - 1
		var sep_end := _make_separator_line()
		sep_end.visible = false
		graph_node.add_child(sep_end)
		items_out.append(sep_end)

	if scenes.size() > 0:
		var toggle := _make_section_toggle("Scenes", scenes.size())
		toggle.add_theme_color_override("font_color", settings.font_scene)
		graph_node.add_child(toggle)
		var items : Array = []
		var make_scene_btn := func(scene_path_: String) -> Button:
			var btn := item_button_packed.instantiate()
			btn.text = " %s" % scene_path_.get_file()
			btn.tooltip_text = scene_path_
			btn.add_theme_color_override("font_color", settings.font_scene)
			btn.add_theme_color_override("font_hover_color", settings.font_hover)
			btn.set_meta("item_type", "scene")
			btn.pressed.connect(func(): EditorInterface.open_scene_from_path(scene_path_))
			return btn
		add_items_direct.call(items, scenes, make_scene_btn, false)
		toggle.pressed.connect(func():
			var expanding = not items[0].visible
			for item in items: item.visible = expanding
			toggle.text = "%s Scenes (%d)" % ["▼" if expanding else "▶", scenes.size()]
			if _dropdown_open_nodes.has(class_name_):
				call_deferred("_rebuild_call_edges")
			if not expanding: graph_node.reset_size())
		graph_node.get_meta("dropdowns").append({"toggle": toggle, "items": items, "label": "Scenes", "count": scenes.size()})

	if signals.size() > 0:
		var toggle := _make_section_toggle("Signals", signals.size())
		toggle.add_theme_color_override("font_color", settings.font_signal)
		graph_node.add_child(toggle)
		var items : Array = []
		var make_signal_btn := func(sig: Dictionary) -> Button:
			var btn := item_button_packed.instantiate()
			btn.text = " %s(%s)" % [sig["name"], sig["args"]]
			var color := settings.font_signal if sig["emitted"] else settings.font_signal_unemitted
			btn.add_theme_color_override("font_color", color)
			btn.add_theme_color_override("font_hover_color", settings.font_hover)
			btn.set_meta("item_type", "signal")
			btn.set_meta("signal_emitted", sig["emitted"])
			if not sig["emitted"]:
				btn.tooltip_text = "Signal is never emitted in this class"
			var line: int = sig["line"]
			btn.pressed.connect(func(): _open_script(script_path, line))
			return btn
		add_items_direct.call(items, signals, make_signal_btn, false)
		toggle.pressed.connect(func():
			var expanding = not items[0].visible
			for item in items: item.visible = expanding
			toggle.text = "%s Signals (%d)" % ["▼" if expanding else "▶", signals.size()]
			if _dropdown_open_nodes.has(class_name_):
				call_deferred("_rebuild_call_edges")
			if not expanding: graph_node.reset_size())
		graph_node.get_meta("dropdowns").append({"toggle": toggle, "items": items, "label": "Signals", "count": signals.size()})

	if variables.size() > 0:
		var toggle := _make_section_toggle("Variables", variables.size())
		toggle.add_theme_color_override("font_color", settings.font_variables_header)
		graph_node.add_child(toggle)
		var items : Array = []
		var make_var_btn := func(v: Dictionary) -> Button:
			var btn := item_button_packed.instantiate()
			btn.text = " %s: %s" % [v["name"], v["type"]]
			btn.add_theme_color_override("font_color", settings.font_variables_header)
			btn.add_theme_color_override("font_hover_color", settings.font_hover)
			btn.set_meta("item_type", "variable")
			var line: int = v["line"]
			btn.pressed.connect(func(): _open_script(script_path, line))
			return btn
		add_items_direct.call(items, variables, make_var_btn, false)
		toggle.pressed.connect(func():
			var expanding = not items[0].visible
			for item in items: item.visible = expanding
			toggle.text = "%s Variables (%d)" % ["▼" if expanding else "▶", variables.size()]
			if _dropdown_open_nodes.has(class_name_):
				call_deferred("_rebuild_call_edges")
			if not expanding: graph_node.reset_size())
		graph_node.get_meta("dropdowns").append({"toggle": toggle, "items": items, "label": "Variables", "count": variables.size()})

	var godot_method_names : Dictionary = {}
	var builtin_ancestor : String = _class_data[class_name_].get("extends", "")
	while _class_data.has(builtin_ancestor) and not _class_data[builtin_ancestor].get("builtin", false):
		builtin_ancestor = _class_data[builtin_ancestor].get("extends", "")
	if ClassDB.class_exists(builtin_ancestor):
		for method in ClassDB.class_get_method_list(builtin_ancestor, false):
			godot_method_names[method["name"]] = true

	var own_functions : Array = []
	var own_builtin_functions : Array = []
	var own_static_functions : Array = []
	var override_functions : Array = []
	for func_ in functions:
		if godot_method_names.has(func_["name"]):
			own_builtin_functions.append(func_)
		elif overrides.has(func_["name"]):
			override_functions.append(func_)
		elif func_.get("static", false):
			own_static_functions.append(func_)
		else:
			own_functions.append(func_)

	var make_function_dropdown := func(section_label: String, func_arr: Array) -> void:
		if func_arr.is_empty(): return
		var toggle := _make_section_toggle(section_label, func_arr.size())
		var section_col := _section_color(section_label)
		toggle.add_theme_color_override("font_color", section_col)
		graph_node.add_child(toggle)
		var items : Array = []
		var make_func_btn := func(func_: Dictionary) -> Button:
			var is_override : bool = overrides.has(func_["name"])
			var missing_super : bool = is_override and not func_.get("calls_super", false)
			var btn := item_button_packed.instantiate()
			btn.text = " %s(%s): %s%s" % [func_["name"], func_["args"], func_["return"], " ⬆" if is_override else ""]
			btn.add_theme_color_override("font_color", settings.font_missing_super if missing_super else section_col)
			btn.add_theme_color_override("font_hover_color", settings.font_hover)
			if missing_super:
				btn.tooltip_text = "⚠ super() is not called"
			btn.set_meta("item_type", "function")
			btn.set_meta("func_name", func_["name"])
			var line: int = func_["line"]
			btn.pressed.connect(func(): _open_script(script_path, line))
			return btn
		add_items_direct.call(items, func_arr, make_func_btn, true)
		toggle.pressed.connect(func():
			var expanding = not items[0].visible
			for item in items: item.visible = expanding
			toggle.text = "%s %s (%d)" % ["▼" if expanding else "▶", section_label, func_arr.size()]
			if expanding:
				_dropdown_open_nodes[class_name_] = true
				_apply_border(graph_node, _autoload_color(class_name_))
				call_deferred("_rebuild_call_edges")
			else:
				graph_node.reset_size()
				var any_open := false
				for dd in graph_node.get_meta("dropdowns", []):
					if dd["label"] == "Variables" or dd["label"] == "TODOs": continue
					if dd["items"].size() > 0 and dd["items"][0].visible:
						any_open = true
						break
				if not any_open:
					_dropdown_open_nodes.erase(class_name_)
				_rebuild_call_edges()
		)
		graph_node.get_meta("dropdowns").append({"toggle": toggle, "items": items, "label": section_label, "count": func_arr.size(), "funcs": func_arr})

	make_function_dropdown.call("Static Functions", own_static_functions)
	make_function_dropdown.call("Functions", own_functions)
	make_function_dropdown.call("Built-in Functions", own_builtin_functions)
	make_function_dropdown.call("Overrides", override_functions)

	var todos: Array = _class_data[class_name_].get("todos", [])
	if todos.size() > 0:
		var toggle := _make_section_toggle("TODOs", todos.size())
		toggle.add_theme_color_override("font_color", settings.font_todo_header)
		graph_node.add_child(toggle)
		var items : Array = []
		var make_todo_btn := func(todo: Dictionary) -> Button:
			var btn := todo_button_packed.instantiate() as Button
			btn.text = " L%d: %s" % [todo["line"], todo["text"]]
			btn.add_theme_color_override("font_color", settings.font_todo_header)
			btn.add_theme_color_override("font_hover_color", settings.font_hover)
			btn.set_meta("item_type", "todo")
			btn.pressed.connect(func(): _open_script(script_path, todo["line"]))
			return btn
		add_items_direct.call(items, todos, make_todo_btn, false)
		toggle.pressed.connect(func():
			var expanding = not items[0].visible
			for item in items: item.visible = expanding
			toggle.text = "%s TODOs (%d)" % ["▼" if expanding else "▶", todos.size()]
			if not expanding: graph_node.reset_size())
		graph_node.get_meta("dropdowns").append({"toggle": toggle, "items": items, "label": "TODOs", "count": todos.size()})

	return graph_node

func _open_script(script_path: String, line: int) -> void:
	var script := load(script_path) as Script
	if not script: return
	EditorInterface.edit_script(script, line, 0)
	if settings.dock_position == ProjectMapperSettings.DockPosition.MAIN_SCREEN:
		EditorInterface.set_main_screen_editor("Script")


func _on_begin_node_move() -> void:
	pass # Replace with function body.
