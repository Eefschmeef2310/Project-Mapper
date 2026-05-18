@tool
extends EditorPlugin

var _dock: EditorDock
var _view = preload("uid://dnna7ajx7urn5")
var _settings_dirty: bool = false
var _is_main_screen: bool = false
var _is_main_screen_cached: bool = false
var _loaded_dock_position: int = -1

const SETTINGS_PATH = "res://addons/project_mapper/project_mapper_settings.tres"

func _has_main_screen() -> bool:
	if not _is_main_screen_cached:
		_is_main_screen_cached = true
		var s := _load_or_create_settings()
		_is_main_screen = s != null and s.dock_position == ProjectMapperSettings.DockPosition.MAIN_SCREEN
	return _is_main_screen

func _get_plugin_name() -> String:
	return "Project Mapper"

func _get_plugin_icon() -> Texture2D:
	return EditorInterface.get_base_control().get_theme_icon("GraphEdit", "EditorIcons")

func _make_visible(visible: bool) -> void:
	if _view and _is_main_screen:
		_view.visible = visible

func _enter_tree() -> void:
	_view = _view.instantiate()
	_loaded_dock_position = _view.settings.dock_position
	_view.settings.changed.connect(_on_settings_changed)

	_has_main_screen()  # Ensure _is_main_screen is cached before use

	if _is_main_screen:
		_view.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_view.size_flags_vertical = Control.SIZE_EXPAND_FILL
		EditorInterface.get_editor_main_screen().add_child(_view)
		_make_visible(false)
		call_deferred(&"_select_main_screen")
	else:
		_dock = EditorDock.new()
		_dock.title = "Project Mapper"
		_dock.default_slot = EditorDock.DOCK_SLOT_BOTTOM
		_dock.available_layouts = EditorDock.DOCK_LAYOUT_HORIZONTAL \
				| EditorDock.DOCK_LAYOUT_FLOATING
		_dock.add_child(_view)
		add_dock(_dock)
		_dock.make_visible()

func _exit_tree() -> void:
	if _settings_dirty:
		ResourceSaver.save(_view.settings, SETTINGS_PATH)

	if _dock:
		remove_dock(_dock)
		_dock.queue_free()
	elif _view:
		_view.queue_free()

func _on_settings_changed() -> void:
	_settings_dirty = true
	if _view.settings.dock_position != _loaded_dock_position:
		ResourceSaver.save(_view.settings, SETTINGS_PATH)
		_settings_dirty = false
		call_deferred("_reload_plugin")

func _select_main_screen() -> void:
	EditorInterface.set_main_screen_editor(_get_plugin_name())
	_reorder_main_screen_button()

func _reorder_main_screen_button() -> void:
	var container := _find_main_screen_container(EditorInterface.get_base_control())
	if container == null:
		return
	var our_idx := -1
	var script_idx := -1
	for i in container.get_child_count():
		var child := container.get_child(i)
		if not child is Button:
			continue
		if child.text == _get_plugin_name(): our_idx = i
		elif child.text == "Script": script_idx = i
	if our_idx >= 0 and script_idx >= 0:
		var insert_at := script_idx + 1 if our_idx > script_idx else script_idx
		container.move_child(container.get_child(our_idx), insert_at)

func _find_main_screen_container(node: Node) -> Container:
	if node is BoxContainer:
		var has_2d := false
		var has_script := false
		for child in node.get_children():
			if child is Button:
				if child.text == "2D": has_2d = true
				if child.text == "Script": has_script = true
		if has_2d and has_script:
			return node
	for child in node.get_children():
		var result := _find_main_screen_container(child)
		if result:
			return result
	return null

func _reload_plugin() -> void:
	# Queue re-enable on EditorInterface (a singleton that outlives this plugin instance)
	# so it runs next frame — after Godot has fully torn down the main screen tab.
	Callable(EditorInterface, "set_plugin_enabled").bind("project_mapper", true).call_deferred()
	EditorInterface.set_plugin_enabled("project_mapper", false)

func _load_or_create_settings() -> ProjectMapperSettings:
	if ResourceLoader.exists(SETTINGS_PATH):
		return load(SETTINGS_PATH) as ProjectMapperSettings
	var s := ProjectMapperSettings.new()
	DirAccess.make_dir_recursive_absolute(SETTINGS_PATH.get_base_dir())
	ResourceSaver.save(s, SETTINGS_PATH)
	return s
