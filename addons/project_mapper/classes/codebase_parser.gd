class_name CodebaseParser

static func scan_project(scan_path: String = "res://") -> Dictionary:
	# Always scan the full project so ancestor chains are complete.
	var result = {}
	_scan_dir("res://", result)
	_inject_godot_ancestors(result)

	#Tag autoloads immediately so we can reference them
	_tag_autoloads(result)
	_scan_scenes(result)

	#Build a map to resolve Global Autoload names back to their node keys
	var autoload_map = {}
	for cname in result:
		if result[cname].has("autoload_name"):
			autoload_map[result[cname]["autoload_name"]] = cname

	for cname in result:
		if not result[cname].get("builtin", false):
			var path: String = result[cname]["path"]
			var source = FileAccess.get_file_as_string(path)
			if source != "":
				var stripped = _strip_comments_and_strings(source, path)
				result[cname]["outbound_calls"] = _parse_outbound_calls(stripped, result, _lang(path), autoload_map)

	# If a subfolder was selected, keep only classes in that folder plus every
	# ancestor (shown dimmed) and discard everything else.
	if scan_path != "res://":
		var in_scope: Dictionary = {}
		for cname in result:
			if result[cname].get("path", "").begins_with(scan_path):
				in_scope[cname] = true

		var keep: Dictionary = {}
		var queue: Array = in_scope.keys()
		while queue.size() > 0:
			var cname: String = queue.pop_back()
			if keep.has(cname):
				continue
			keep[cname] = true
			var parent: String = result.get(cname, {}).get("extends", "")
			if parent != "":
				queue.append(parent)

		for cname in result.keys():
			if not keep.has(cname):
				result.erase(cname)
			elif not in_scope.has(cname) and not result[cname].get("builtin", false):
				result[cname]["out_of_scope"] = true

	return result

# ---------------------------------------------------------------------------
# Language detection
# ---------------------------------------------------------------------------

static func _lang(path: String) -> String:
	var ext = path.get_extension().to_lower()
	#GDScript or C#
	if ext == "gd" or ext == "cs": 
		return ext
	#C++
	elif ext in ["cpp", "cxx", "cc", "h", "hpp", "hxx"]: 
		return "cpp"
	
	return ""

# ---------------------------------------------------------------------------
# Ancestor injection
# ---------------------------------------------------------------------------
static func _inject_godot_ancestors(result: Dictionary) -> void:
	var to_check: Array = result.keys()
	var visited: Dictionary = {}
	while to_check.size() > 0:
		var cname: String = to_check.pop_back()
		if visited.has(cname):
			continue
		visited[cname] = true
		var parent: String = result[cname]["extends"]
		if parent == "" or result.has(parent):
			continue
		var grandparent: String = _godot_parent(parent)
		result[parent] = {
			"extends": grandparent,
			"path": "",
			"variables": [], "functions": [], "signals": [], "scenes": [],
			"builtin": true, "todos": [], "signal_connections": [], "outbound_calls": [],
		}
		if grandparent != "":
			to_check.append(parent)

static func _godot_parent(cname: String) -> String:
	if not ClassDB.class_exists(cname):
		return ""
	var parent: String = ClassDB.get_parent_class(cname)
	return parent if parent != "" else ""

# ---------------------------------------------------------------------------
# Directory scan
# ---------------------------------------------------------------------------
static func _scan_dir(path: String, result: Dictionary) -> void:
	if path.contains("res://addons/"):
		return
	var dir = DirAccess.open(path)
	if not dir:
		return
	dir.list_dir_begin()
	var fname = dir.get_next()
	while fname != "":
		if not fname.begins_with("."):
			var full = path.path_join(fname)
			if dir.current_is_dir():
				_scan_dir(full, result)
			elif _lang(full) != "":
				_parse_script(full, result)
		fname = dir.get_next()

# ---------------------------------------------------------------------------
# Comment / string stripping (dispatch by language)
# ---------------------------------------------------------------------------
static func _strip_comments_and_strings(src: String, path: String = "") -> String:
	var lang = _lang(path)
	if lang == "cs" or lang == "cpp":
		return _strip_c_style(src)
	return _strip_gdscript(src)

static func _strip_gdscript(src: String) -> String:
	var result := ""
	var i := 0
	var n := src.length()
	while i < n:
		var c := src[i]
		if c == "#":
			while i < n and src[i] != "\n":
				i += 1
		elif c == "\"":
			i += 1
			while i < n:
				if src[i] == "\\" : i += 2
				elif src[i] == "\"": i += 1; break
				else: i += 1
		elif c == "'":
			i += 1
			while i < n:
				if src[i] == "\\" : i += 2
				elif src[i] == "'": i += 1; break
				else: i += 1
		else:
			result += c
			i += 1
	return result

static func _strip_c_style(src: String) -> String:
	var result := ""
	var i := 0
	var n := src.length()
	while i < n:
		# Line comment
		if i + 1 < n and src[i] == "/" and src[i + 1] == "/":
			while i < n and src[i] != "\n":
				i += 1
		# Block comment
		elif i + 1 < n and src[i] == "/" and src[i + 1] == "*":
			i += 2
			while i + 1 < n:
				if src[i] == "*" and src[i + 1] == "/":
					i += 2
					break
				i += 1
		# Verbatim string C# @"..."
		elif i + 1 < n and src[i] == "@" and src[i + 1] == "\"":
			i += 2
			while i + 1 < n:
				if src[i] == "\"" and src[i + 1] == "\"":
					i += 2 # escaped quote inside verbatim
				elif src[i] == "\"":
					i += 1
					break
				else:
					i += 1
		# Regular string
		elif src[i] == "\"":
			i += 1
			while i < n:
				if src[i] == "\\" : i += 2
				elif src[i] == "\"": i += 1; break
				else: i += 1
		# Char literal
		elif src[i] == "'":
			i += 1
			while i < n:
				if src[i] == "\\" : i += 2
				elif src[i] == "'": i += 1; break
				else: i += 1
		else:
			result += src[i]
			i += 1
	return result

# ---------------------------------------------------------------------------
# TODO parsing
# ---------------------------------------------------------------------------
static func _parse_todos(source: String) -> Array:
	var todos = []
	var rx = RegEx.new()
	rx.compile(r"#[^\n]*(?:TODO|FIXME|todo|fixme)[^\n]*")
	for m in rx.search_all(source):
		var line = source.count("\n", 0, m.get_start()) + 1
		todos.append({ "line": line, "text": m.get_string().lstrip("#").strip_edges() })
	# Also catch C-style // TODO and /* TODO
	var crx = RegEx.new()
	crx.compile(r"//[^\n]*(?:TODO|FIXME|todo|fixme)[^\n]*")
	for m in crx.search_all(source):
		var line = source.count("\n", 0, m.get_start()) + 1
		todos.append({ "line": line, "text": m.get_string().lstrip("/").strip_edges() })
	return todos

# ---------------------------------------------------------------------------
# GDScript Signal Connections
# ---------------------------------------------------------------------------

static func _parse_signal_connections(source: String, stripped: String, class_lookup: Dictionary) -> Array:
	var connections = []
	
	var new_rx = RegEx.new()
	new_rx.compile(r"(\w+)\.(\w+)\.connect\s*\(")
	
	var legacy_rx = RegEx.new()
	legacy_rx.compile(r"(\w+)\.connect\s*\(\s*[\"'](\w+)[\"']")
	
	var local_var_types: Dictionary = {}
	
	var typed_var_rx = RegEx.new()
	typed_var_rx.compile(r"(?m)^(?:@\w+\s+)*var\s+(\w+)\s*:\s*(\w+)")
	
	for m in typed_var_rx.search_all(source):
		local_var_types[m.get_string(1)] = m.get_string(2)
	for m in new_rx.search_all(stripped):
		var receiver = m.get_string(1)
		var sig = m.get_string(2)
		var target = local_var_types.get(receiver, "")
		if target != "" and class_lookup.has(target):
			connections.append({ "signal": sig, "target": target })
	for m in legacy_rx.search_all(stripped):
		var receiver = m.get_string(1)
		var sig = m.get_string(2)
		var target = local_var_types.get(receiver, "")
		if target != "" and class_lookup.has(target):
			connections.append({ "signal": sig, "target": target })
	return connections

# ---------------------------------------------------------------------------
# Outbound call parsing (shared logic, works for all languages after strip)
# ---------------------------------------------------------------------------

static func _parse_outbound_calls(stripped: String, class_lookup: Dictionary, lang: String, autoload_map: Dictionary = {}) -> Array:
	var calls = []
	var seen = {}
	
	# Extract function positions to figure out who is calling
	var func_pos = []
	if lang == "gd":
		var rx = RegEx.new()
		rx.compile(r"(?m)^(?:static\s+)?func\s+(\w+)")
		for m in rx.search_all(stripped):
			func_pos.append({"name": m.get_string(1), "pos": m.get_start()})
	elif lang == "cs":
		var rx = RegEx.new()
		rx.compile(r"(?:public|private|protected|internal|override|virtual|static|async|abstract)\s+(?:static\s+|async\s+|override\s+|virtual\s+|abstract\s+)*\w[\w<>?, \[\]]*\s+(\w+)\s*\(")
		for m in rx.search_all(stripped):
			var fname = m.get_string(1)
			if not fname in ["if", "while", "for", "foreach", "switch", "catch", "using"]:
				func_pos.append({"name": fname, "pos": m.get_start()})
	elif lang == "cpp":
		var rx = RegEx.new()
		rx.compile(r"(?:virtual\s+|static\s+|inline\s+|explicit\s+|override\s+)*\w[\w:<>*& ]*?\s+(\w+)\s*\(")
		for m in rx.search_all(stripped):
			var fname = m.get_string(1)
			if not fname in ["if", "while", "for", "switch", "return", "else", "case"]:
				func_pos.append({"name": fname, "pos": m.get_start()})

	var local_var_types: Dictionary = {}
	var typed_var_rx = RegEx.new()
	typed_var_rx.compile(r"(?m)^\s*(?:@\w+\s+)*var\s+(\w+)\s*:\s*(\w+)")
	for m in typed_var_rx.search_all(stripped):
		local_var_types[m.get_string(1)] = m.get_string(2)

	var cs_var_rx = RegEx.new()
	cs_var_rx.compile(r"\b([A-Z]\w+)\s+([a-z_]\w*)\s*[=;{(,)]")
	for m in cs_var_rx.search_all(stripped):
		var type = m.get_string(1)
		var vname = m.get_string(2)
		if class_lookup.has(type):
			local_var_types[vname] = type

	var call_rx = RegEx.new()
	call_rx.compile(r"\b(\w+)\.(\w+)\s*\(")
	for m in call_rx.search_all(stripped):
		var call_pos = m.get_start()
		var caller = ""
		
		# Find the closest preceding function
		for i in range(func_pos.size() - 1, -1, -1):
			if func_pos[i].pos < call_pos:
				caller = func_pos[i].name
				break

		var receiver: String = m.get_string(1)
		var method: String = m.get_string(2)
		var target: String = ""
		
		if class_lookup.has(receiver): 
			target = receiver
		elif autoload_map.has(receiver): 
			target = autoload_map[receiver]
		else:
			target = local_var_types.get(receiver, "")
			if not class_lookup.has(target): target = ""
				
		if target == "": continue
		
		var key = "%s::%s::%s" % [target, method, caller]
		if seen.has(key): continue
		seen[key] = true
		
		# Record the caller too
		calls.append({ "target": target, "method": method, "caller": caller })
	return calls
	
# ---------------------------------------------------------------------------
# Script parsing (dispatch by language)
# ---------------------------------------------------------------------------

static func _parse_script(path: String, result: Dictionary) -> void:
	match _lang(path):
		"gd": _parse_gdscript(path, result)
		"cs": _parse_csharp(path, result)
		"cpp": _parse_cpp(path, result)

# ── GDScript ────────────────────────────────────────────────────────────────

static func _parse_gdscript(path: String, result: Dictionary) -> void:
	var source = FileAccess.get_file_as_string(path)
	if source == "":
		return

	var class_name_rx = RegEx.new()
	class_name_rx.compile(r"(?m)^class_name\s+(\w+)")
	var extends_rx = RegEx.new()
	extends_rx.compile(r"(?m)^extends\s+(\w+)")
	var var_rx = RegEx.new()
	var_rx.compile(r"(?m)^(?:@\w+\s+)*var\s+(\w+)(?:\s*:\s*(\w+))?")
	var func_rx = RegEx.new()
	func_rx.compile(r"(?m)^(static\s+)?func\s+(\w+)\s*\(([^)]*)\)(?:\s*->\s*(\w+))?")

	var cname_match = class_name_rx.search(source)
	var extends_match = extends_rx.search(source)
	var cname = cname_match.get_string(1) if cname_match else path.get_file().get_basename()
	var parent = extends_match.get_string(1) if extends_match else "RefCounted"

	var variables = []
	for m in var_rx.search_all(source):
		var line = source.count("\n", 0, m.get_start()) + 1
		variables.append({
			"name": m.get_string(1),
			"type": m.get_string(2) if m.get_string(2) != "" else "Variant",
			"line": line
		})

	var super_rx = RegEx.new()
	super_rx.compile(r"\bsuper\b")
	var functions = []
	for m in func_rx.search_all(source):
		var line = source.count("\n", 0, m.get_start()) + 1
		var body_start = m.get_end()
		var next_func = func_rx.search(source, body_start)
		var body = source.substr(body_start, next_func.get_start() - body_start if next_func else -1)
		var calls_super = super_rx.search(_strip_gdscript(body)) != null
		functions.append({
			"name": m.get_string(2),
			"args": m.get_string(3).strip_edges(),
			"return": m.get_string(4) if m.get_string(4) != "" else "void",
			"line": line,
			"calls_super": calls_super,
			"static": m.get_string(1) != ""
		})

	var stripped = _strip_gdscript(source)

	var signal_rx := RegEx.new()
	signal_rx.compile(r"(?m)^signal\s+(\w+)(?:\s*\(([^)]*)\))?")
	var emit_rx := RegEx.new()
	emit_rx.compile(r"\b(\w+)\.emit\s*\(")
	var legacy_emit_rx := RegEx.new()
	legacy_emit_rx.compile(r"emit_signal\s*\(\s*[\"'](\w+)[\"']")
	var emitted_signals: Dictionary = {}
	for m in emit_rx.search_all(stripped):
		emitted_signals[m.get_string(1)] = true
	for m in legacy_emit_rx.search_all(source):
		emitted_signals[m.get_string(1)] = true
	var signals: Array = []
	for m in signal_rx.search_all(source):
		var sig_name: String = m.get_string(1)
		var sig_args: String = m.get_string(2).strip_edges() if m.get_string(2) != "" else ""
		var line: int = source.count("\n", 0, m.get_start()) + 1
		signals.append({"name": sig_name, "args": sig_args, "line": line, "emitted": emitted_signals.has(sig_name)})

	result[cname] = {
		"extends": parent,
		"path": path,
		"variables": variables,
		"functions": functions,
		"signals": signals,
		"scenes": [],
		"todos": _parse_todos(source),
		"signal_connections": _parse_signal_connections(source, stripped, result),
		"outbound_calls": [],
	}

static func _tag_autoloads(result: Dictionary) -> void:
	for property in ProjectSettings.get_property_list():
		var pname: String = property["name"]
		if not pname.begins_with("autoload/"): continue
		var autoload_name := pname.substr(9)
		var raw: String = str(ProjectSettings.get_setting(pname, "")).lstrip("*")
		var path: String = raw
		if raw.begins_with("uid://"):
			var uid_int := ResourceUID.text_to_id(raw)
			if uid_int != ResourceUID.INVALID_ID:
				path = ResourceUID.get_id_path(uid_int)
		for class_name_ in result:
			if result[class_name_].get("path", "") == path:
				result[class_name_]["autoload_name"] = autoload_name
				break

# ── C# ──────────────────────────────────────────────────────────────────────

static func _parse_csharp(path: String, result: Dictionary) -> void:
	var source = FileAccess.get_file_as_string(path)
	if source == "":
		return

	# class_name / partial class
	var class_rx = RegEx.new()
	class_rx.compile(r"(?:public|private|internal|protected)?\s*(?:partial\s+)?(?:class|struct|record)\s+(\w+)(?:\s*<[^>]+>)?(?:\s*:\s*([\w\s,<>]+))?")
	# fields: access type name
	var field_rx = RegEx.new()
	field_rx.compile(r"(?:public|private|protected|internal|static|readonly|const)\s+(?:static\s+|readonly\s+|const\s+)*(\w[\w<>, \[\]?]*)\s+(\w+)\s*(?:=|;|{)")
	# methods
	var method_rx = RegEx.new()
	method_rx.compile(r"(?:public|private|protected|internal|override|virtual|static|async|abstract)\s+(?:static\s+|async\s+|override\s+|virtual\s+|abstract\s+)*(\w[\w<>?, \[\]]*)\s+(\w+)\s*\(([^)]*)\)")
	# base() call in constructor / override
	var super_rx = RegEx.new()
	super_rx.compile(r"\bbase\s*[\.(]")

	var cm = class_rx.search(source)
	var cname = cm.get_string(1) if cm else path.get_file().get_basename()

	# Parse first parent from : Base, IFoo, IBar
	var parent = "GodotObject"
	if cm and cm.get_string(2) != "":
		var parts = cm.get_string(2).split(",")
		for p in parts:
			var trimmed = p.strip_edges()
			# Skip interface names (conventionally start with I + uppercase)
			if not (trimmed.begins_with("I") and trimmed.length() > 1 and trimmed[1] == trimmed[1].to_upper()):
				parent = trimmed.split("<")[0].strip_edges()
				break

	var variables = []
	for m in field_rx.search_all(source):
		var line = source.count("\n", 0, m.get_start()) + 1
		variables.append({
			"name": m.get_string(2),
			"type": m.get_string(1).strip_edges(),
			"line": line
		})

	var functions = []
	for m in method_rx.search_all(source):
		var ret_type = m.get_string(1).strip_edges()
		var fname = m.get_string(2)
		# Skip property accessors and common false-positives
		if fname in ["if", "while", "for", "foreach", "switch", "catch", "using"]:
			continue
		var line = source.count("\n", 0, m.get_start()) + 1
		var body_start = m.get_end()
		var next_m = method_rx.search(source, body_start)
		var body = source.substr(body_start, next_m.get_start() - body_start if next_m else -1)
		var calls_super = super_rx.search(_strip_c_style(body)) != null
		functions.append({
			"name": fname,
			"args": m.get_string(3).strip_edges(),
			"return": ret_type,
			"line": line,
			"calls_super": calls_super
		})

	result[cname] = {
		"extends": parent,
		"path": path,
		"variables": variables,
		"functions": functions,
		"signals": [],
		"scenes": [],
		"todos": _parse_todos(source),
		"signal_connections": [],
		"outbound_calls": [],
	}
	
# ── C++ ─────────────────────────────────────────────────────────────────────

static func _parse_cpp(path: String, result: Dictionary) -> void:
	var source = FileAccess.get_file_as_string(path)
	if source == "":
		return

	# Only parse headers for class declarations; .cpp bodies are parsed for calls
	var is_header = path.get_extension().to_lower() in ["h", "hpp", "hxx"]

	# class Name : public Base
	var class_rx = RegEx.new()
	class_rx.compile(r"\b(?:class|struct)\s+(\w+)(?:\s*:\s*(?:public|protected|private)\s+(\w+))?")
	# member variables (very rough — type name; or type name =)
	var field_rx = RegEx.new()
	field_rx.compile(r"^\s*(?:(?:static|const|mutable|volatile|inline)\s+)*(\w[\w:<>*& ]+?)\s+(\w+)\s*(?:=|;)")
	# methods: return_type name(args)
	var method_rx = RegEx.new()
	method_rx.compile(r"(?:virtual\s+|static\s+|inline\s+|explicit\s+|override\s+)*(\w[\w:<>*& ]*?)\s+(\w+)\s*\(([^)]*)\)\s*(?:const\s*)?(?:override\s*)?(?:=\s*0\s*)?[{;]")
	var super_rx = RegEx.new()
	super_rx.compile(r"\b(\w+)::\1\s*\(") # constructor delegation heuristic

	var cm = class_rx.search(source)
	if not cm and not is_header:
		# .cpp with no class: still scan for outbound calls in second pass
		# Register under filename so it appears in the graph
		var cname = path.get_file().get_basename()
		if not result.has(cname):
			result[cname] = {
				"extends": "", "path": path,
				"variables": [], "functions": [], "signals": [], "scenes": [],
				"todos": _parse_todos(source),
				"signal_connections": [], "outbound_calls": [],
			}
		return

	var cname = cm.get_string(1) if cm else path.get_file().get_basename()
	var parent = cm.get_string(2) if (cm and cm.get_string(2) != "") else ""

	var stripped = _strip_c_style(source)

	var variables = []
	if is_header:
		for m in field_rx.search_all(stripped):
			var type = m.get_string(1).strip_edges()
			var vname = m.get_string(2).strip_edges()
			# Filter out keywords that look like types
			if type in ["return", "delete", "new", "if", "else", "for", "while", "case"]:
				continue
			var line = source.count("\n", 0, m.get_start()) + 1
			variables.append({ "name": vname, "type": type, "line": line })

	var functions = []
	for m in method_rx.search_all(stripped):
		var ret = m.get_string(1).strip_edges()
		var fname = m.get_string(2)
		if fname in ["if", "while", "for", "switch", "return", "else"]:
			continue
		if ret in ["return", "delete", "else", "case"]:
			continue
		var line = source.count("\n", 0, m.get_start()) + 1
		var body_start = m.get_end()
		var next_m = method_rx.search(stripped, body_start)
		var body = stripped.substr(body_start, next_m.get_start() - body_start if next_m else -1)
		var calls_super = super_rx.search(body) != null
		functions.append({
			"name": fname,
			"args": m.get_string(3).strip_edges(),
			"return": ret,
			"line": line,
			"calls_super": calls_super
		})

	result[cname] = {
		"extends": parent,
		"path": path,
		"variables": variables,
		"functions": functions,
		"signals": [],
		"scenes": [],
		"todos": _parse_todos(source),
		"signal_connections": [],
		"outbound_calls": [],
	}

# ---------------------------------------------------------------------------
# Scene scanning
# ---------------------------------------------------------------------------

static func _collect_scenes(path: String, out: Array) -> void:
	if path.contains("res://addons/"): return
	var dir := DirAccess.open(path)
	if not dir: return
	dir.list_dir_begin()
	var fname := dir.get_next()
	while fname != "":
		if not fname.begins_with("."):
			var full := path.path_join(fname)
			if dir.current_is_dir():
				_collect_scenes(full, out)
			elif fname.ends_with(".tscn"):
				out.append(full)
		fname = dir.get_next()

static func _scan_scenes(result: Dictionary) -> void:
	var path_to_class: Dictionary = {}
	for cname in result:
		var p: String = result[cname].get("path", "")
		if p != "":
			path_to_class[p] = cname

	var scene_files: Array = []
	_collect_scenes("res://", scene_files)
	if scene_files.is_empty(): return

	var ext_res_rx := RegEx.new()
	ext_res_rx.compile(r'\[ext_resource[^\]]*\]')
	var path_attr_rx := RegEx.new()
	path_attr_rx.compile(r'path="([^"]+)"')
	var id_attr_rx := RegEx.new()
	id_attr_rx.compile(r'\bid="([^"]+)"')
	var node_rx := RegEx.new()
	node_rx.compile(r'\[node[^\]]*\]')
	var script_rx := RegEx.new()
	script_rx.compile(r'script\s*=\s*ExtResource\s*\(\s*"([^"]+)"\s*\)')

	for scene_path in scene_files:
		var source := FileAccess.get_file_as_string(scene_path)
		if source == "": continue

		var res_map: Dictionary = {}
		for m in ext_res_rx.search_all(source):
			var tag := m.get_string()
			if not 'type="Script"' in tag: continue
			var pm := path_attr_rx.search(tag)
			var im := id_attr_rx.search(tag)
			if pm and im:
				res_map[im.get_string(1)] = pm.get_string(1)
		if res_map.is_empty(): continue

		var node_m := node_rx.search(source)
		if not node_m: continue
		if "parent=" in node_m.get_string(): continue

		var body_start := node_m.get_end()
		var next_node_m := node_rx.search(source, body_start)
		var node_body := source.substr(body_start, next_node_m.get_start() - body_start if next_node_m else -1)

		var sm := script_rx.search(node_body)
		if not sm: continue

		var script_path: String = res_map.get(sm.get_string(1), "")
		if script_path == "": continue

		var cname_: String = path_to_class.get(script_path, "")
		if cname_ == "": continue

		result[cname_]["scenes"].append(scene_path)
